import Foundation
import Network

struct HTTPResponse {
    let statusCode: Int
    let body: Data
    let contentType: String

    init(statusCode: Int, body: Data, contentType: String = "application/json") {
        self.statusCode = statusCode
        self.body = body
        self.contentType = contentType
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
    func httpLoadModel(modelID: String) async -> HTTPResponse
    func httpGenerate(prompt: String) async -> HTTPResponse
    func httpReset() async -> HTTPResponse
    func httpOpenAIChatCompletions(bodyJSON: [String: Any]) async -> HTTPResponse
}

final class LocalHTTPServer: @unchecked Sendable {
    private weak var delegate: LocalHTTPServerDelegate?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "warden4.loader.http", qos: .userInitiated)

    private(set) var port: UInt16?

    init(delegate: LocalHTTPServerDelegate) {
        self.delegate = delegate
    }

    func start(onPort desiredPort: UInt16 = 8787) throws {
        if listener != nil { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: desiredPort)!)
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
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
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
            guard let requestData = Self.completeRequestData(from: combined) else {
                self.receiveRequest(on: connection, buffer: combined)
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
        let parts = request.components(separatedBy: "\r\n\r\n")
        let headerLines = parts.first?.components(separatedBy: "\r\n") ?? []
        guard let requestLine = headerLines.first else {
            return .json(statusCode: 400, ["status": "failed", "error": "missing_request_line"])
        }
        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else {
            return .json(statusCode: 400, ["status": "failed", "error": "invalid_request_line"])
        }

        let method = String(tokens[0])
        let path = String(tokens[1])
        let bodyText = parts.count > 1 ? parts[1] : ""
        let bodyJSON = bodyText.data(using: .utf8).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }

        switch (method, path) {
        case ("GET", "/status"):
            return .json(delegate?.httpStatusPayload() ?? ["status": "failed", "error": "delegate_missing"])
        case ("GET", "/models"):
            return .json(["models": delegate?.httpModelsPayload() ?? []])
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
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        case 501: statusText = "Not Implemented"
        case 503: statusText = "Service Unavailable"
        default: statusText = "OK"
        }
        var payload = Data()
        payload.append("HTTP/1.1 \(response.statusCode) \(statusText)\r\n".data(using: .utf8)!)
        payload.append("Content-Type: \(response.contentType)\r\n".data(using: .utf8)!)
        payload.append("Content-Length: \(response.body.count)\r\n".data(using: .utf8)!)
        payload.append("Connection: close\r\n\r\n".data(using: .utf8)!)
        payload.append(response.body)
        return payload
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
}
