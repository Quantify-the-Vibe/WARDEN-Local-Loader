import Foundation
import Network

struct HTTPResponse {
    let statusCode: Int
    let body: Data
    let contentType: String
    let headers: [String: String]

    init(
        statusCode: Int,
        body: Data,
        contentType: String = "application/json",
        headers: [String: String] = [:]
    ) {
        self.statusCode = statusCode
        self.body = body
        self.contentType = contentType
        self.headers = headers
    }

    static func json(statusCode: Int = 200, _ payload: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: statusCode, body: data)
    }
}

@MainActor
protocol LocalHTTPServerDelegate: AnyObject {
    func httpStatusPayload() -> [String: Any]
    func httpModelsPayload() -> [[String: Any]]
    func httpOpenAIModelsPayload() -> [String: Any]
    func httpLoadModel(modelID: String) async -> HTTPResponse
    func httpGenerate(prompt: String) async -> HTTPResponse
    func httpReset() async -> HTTPResponse
    func httpOpenAIChatCompletions(bodyJSON: [String: Any]) async -> HTTPResponse
}

final class LocalHTTPServer: @unchecked Sendable {
    private static let maxRequestBytes = 8 * 1_024 * 1_024
    private static let requestReadTimeoutSeconds: TimeInterval = 15

    private weak var delegate: LocalHTTPServerDelegate?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "warden4.loader.http", qos: .userInitiated)
    private let apiToken: String?

    private(set) var port: UInt16?

    init(delegate: LocalHTTPServerDelegate, apiToken: String? = ProcessInfo.processInfo.environment["W4L_API_TOKEN"]) {
        self.delegate = delegate
        if let token = apiToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            self.apiToken = token
        } else {
            self.apiToken = nil
        }
    }

    func start(onPort desiredPort: UInt16 = 8787) throws {
        if listener != nil { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let desired = NWEndpoint.Port(rawValue: desiredPort)!
        let listener = try NWListener(using: parameters, on: desired)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.port = listener.port?.rawValue
            case .failed, .cancelled:
                self.port = nil
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        if !Self.isLoopbackEndpoint(connection.endpoint) {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data(), startedAt: Date())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data, startedAt: Date) {
        if Date().timeIntervalSince(startedAt) > Self.requestReadTimeoutSeconds {
            connection.send(content: Self.render(response: .json(statusCode: 408, [
                "status": "failed",
                "error": "request_timeout",
            ])), completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            let combined = buffer + data
            if Self.requestExceedsLimit(combined) {
                connection.send(content: Self.render(response: .json(statusCode: 413, [
                    "status": "failed",
                    "error": "request_too_large",
                ])), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            guard let requestData = Self.completeRequestData(from: combined) else {
                self.receiveRequest(on: connection, buffer: combined, startedAt: startedAt)
                return
            }
            Task { @MainActor in
                let response = await self.route(data: requestData)
                connection.send(content: Self.render(response: response), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    @MainActor
    private func route(data: Data) async -> HTTPResponse {
        guard let request = String(data: data, encoding: .utf8) else {
            return .json(statusCode: 400, ["status": "failed", "error": "invalid_request_encoding"])
        }
        let headerSeparator = "\r\n\r\n"
        let headerSection: String
        let bodyText: String
        if let range = request.range(of: headerSeparator) {
            headerSection = String(request[..<range.lowerBound])
            bodyText = String(request[range.upperBound...])
        } else {
            headerSection = request
            bodyText = ""
        }
        let headerLines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            return .json(statusCode: 400, ["status": "failed", "error": "missing_request_line"])
        }
        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else {
            return .json(statusCode: 400, ["status": "failed", "error": "invalid_request_line"])
        }

        let method = String(tokens[0])
        let path = Self.normalizeRoutePath(String(tokens[1]))
        let headers = Self.headerDictionary(from: headerLines.dropFirst())
        let bodyJSON = bodyText.data(using: .utf8).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        if requiresAuthorization(method: method, path: path) {
            if !isAuthorized(headers: headers) {
                return Self.unauthorizedResponse(forPath: path)
            }
        }

        switch (method, path) {
        case ("GET", "/status"):
            return .json(delegate?.httpStatusPayload() ?? ["status": "failed", "error": "delegate_missing"])
        case ("GET", "/models"):
            return .json(["models": delegate?.httpModelsPayload() ?? []])
        case ("GET", "/v1/models"):
            return .json(delegate?.httpOpenAIModelsPayload() ?? ["object": "list", "data": []])
        case ("POST", "/load"):
            guard let modelID = bodyJSON?["model_id"] as? String, !modelID.isEmpty else {
                return .json(statusCode: 400, ["status": "failed", "error": "missing_model_id"])
            }
            return await delegate?.httpLoadModel(modelID: modelID)
                ?? .json(statusCode: 500, ["status": "failed", "error": "delegate_missing"])
        case ("POST", "/generate"):
            guard let prompt = bodyJSON?["prompt"] as? String, !prompt.isEmpty else {
                return .json(statusCode: 400, ["status": "failed", "error": "missing_prompt"])
            }
            return await delegate?.httpGenerate(prompt: prompt)
                ?? .json(statusCode: 500, ["status": "failed", "error": "delegate_missing"])
        case ("POST", "/reset"):
            return await delegate?.httpReset()
                ?? .json(statusCode: 500, ["status": "failed", "error": "delegate_missing"])
        case ("POST", "/v1/chat/completions"):
            guard let bodyJSON else {
                return .json(statusCode: 400, ["error": ["message": "missing_json_body", "type": "invalid_request_error"]])
            }
            return await delegate?.httpOpenAIChatCompletions(bodyJSON: bodyJSON)
                ?? .json(statusCode: 500, ["error": ["message": "delegate_missing", "type": "internal_error"]])
        default:
            return .json(statusCode: 404, ["status": "failed", "error": "route_not_found", "path": path])
        }
    }

    static func render(response: HTTPResponse) -> Data {
        let statusText: String
        switch response.statusCode {
        case 200: statusText = "OK"
        case 401: statusText = "Unauthorized"
        case 403: statusText = "Forbidden"
        case 400: statusText = "Bad Request"
        case 408: statusText = "Request Timeout"
        case 413: statusText = "Payload Too Large"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        case 501: statusText = "Not Implemented"
        case 503: statusText = "Service Unavailable"
        default: statusText = "OK"
        }
        var payload = Data()
        payload.append("HTTP/1.1 \(response.statusCode) \(statusText)\r\n".data(using: .utf8)!)
        payload.append("Content-Type: \(response.contentType)\r\n".data(using: .utf8)!)
        for (header, value) in response.headers {
            payload.append("\(header): \(value)\r\n".data(using: .utf8)!)
        }
        payload.append("Content-Length: \(response.body.count)\r\n".data(using: .utf8)!)
        payload.append("Connection: close\r\n\r\n".data(using: .utf8)!)
        payload.append(response.body)
        return payload
    }

    static func normalizeRoutePath(_ rawPath: String) -> String {
        guard let queryStart = rawPath.firstIndex(of: "?") else {
            return rawPath
        }
        return String(rawPath[..<queryStart])
    }

    static func unauthorizedResponse(forPath path: String) -> HTTPResponse {
        let payload: [String: Any]
        if path == "/v1/chat/completions" {
            payload = [
                "error": [
                    "message": "Unauthorized. Send Authorization: Bearer <W4L_API_TOKEN> or X-Loader-Token.",
                    "type": "authentication_error",
                    "code": "invalid_api_key",
                ],
            ]
        } else {
            payload = [
                "status": "failed",
                "error": "unauthorized",
                "detail": "Authorization required for this route.",
                "hint": "Send Authorization: Bearer <W4L_API_TOKEN> or X-Loader-Token: <W4L_API_TOKEN>.",
            ]
        }
        let body = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])) ?? Data("{}".utf8)
        return HTTPResponse(
            statusCode: 401,
            body: body,
            headers: [
                "WWW-Authenticate": #"Bearer realm="W4L Loader", charset="UTF-8""#,
            ]
        )
    }

    static func completeRequestData(from data: Data) -> Data? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        let headersData = data[..<headerRange.lowerBound]
        guard let headersText = String(data: headersData, encoding: .utf8) else {
            return data
        }

        let contentLength = headersText
            .components(separatedBy: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                guard parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                    return nil
                }
                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .first ?? 0

        let bodyStart = headerRange.upperBound
        let expectedTotalLength = data.distance(from: data.startIndex, to: bodyStart) + max(contentLength, 0)
        guard data.count >= expectedTotalLength else {
            return nil
        }
        return data.prefix(expectedTotalLength)
    }

    static func requestExceedsLimit(_ data: Data) -> Bool {
        if data.count > maxRequestBytes {
            return true
        }
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return false
        }
        let headersData = data[..<headerRange.lowerBound]
        guard let headersText = String(data: headersData, encoding: .utf8) else {
            return false
        }
        let contentLength = headersText
            .components(separatedBy: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                guard parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                    return nil
                }
                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .first ?? 0
        let bodyStart = headerRange.upperBound
        let expectedTotalLength = data.distance(from: data.startIndex, to: bodyStart) + max(contentLength, 0)
        return expectedTotalLength > maxRequestBytes
    }

    private static func headerDictionary(from lines: ArraySlice<String>) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        return headers
    }

    private func requiresAuthorization(method: String, path: String) -> Bool {
        guard apiToken != nil else { return false }
        switch (method, path) {
        case ("POST", "/load"), ("POST", "/generate"), ("POST", "/reset"), ("POST", "/v1/chat/completions"):
            return true
        default:
            return false
        }
    }

    private func isAuthorized(headers: [String: String]) -> Bool {
        guard let apiToken else { return true }
        if let bearer = headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           bearer == "Bearer \(apiToken)" {
            return true
        }
        if let direct = headers["x-loader-token"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           direct == apiToken {
            return true
        }
        return false
    }

    private static func isLoopbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return address.rawValue == IPv4Address.loopback.rawValue
        case .ipv6(let address):
            return address.rawValue == IPv6Address.loopback.rawValue
        case .name(let name, _):
            let normalized = name.lowercased()
            return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
        @unknown default:
            return false
        }
    }
}
