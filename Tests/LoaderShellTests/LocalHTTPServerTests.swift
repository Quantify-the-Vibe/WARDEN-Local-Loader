import Foundation
import Testing
@testable import LoaderShell

struct LocalHTTPServerTests {
    @Test
    func completeRequestDataWaitsForEntireBody() {
        let requestBody = #"{"model_id":"mock"}"#
        let headers = "POST /load HTTP/1.1\r\n" +
            "Host: 127.0.0.1\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(requestBody.utf8.count)\r\n" +
            "\r\n"
        let fullRequest = Data((headers + requestBody).utf8)

        let truncated = Data(fullRequest.prefix(fullRequest.count - 2))

        #expect(LocalHTTPServer.completeRequestData(from: truncated) == nil)
        #expect(LocalHTTPServer.completeRequestData(from: fullRequest) == fullRequest)
    }

    @Test
    func renderUsesServiceUnavailableReasonPhrase() {
        let response = HTTPResponse.json(statusCode: 503, [
            "status": "failed",
            "error": "failed_fast_active",
        ])

        let rendered = LocalHTTPServer.render(response: response)
        let renderedText = String(decoding: rendered, as: UTF8.self)

        #expect(renderedText.contains("HTTP/1.1 503 Service Unavailable"))
    }

    @Test
    func requestExceedsLimitWhenContentLengthIsTooLarge() {
        let headers = "POST /generate HTTP/1.1\r\n" +
            "Host: 127.0.0.1\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: 99999999\r\n" +
            "\r\n"
        let partial = Data(headers.utf8)
        #expect(LocalHTTPServer.requestExceedsLimit(partial))
    }

    @Test
    func renderUsesUnauthorizedReasonPhrase() {
        let response = HTTPResponse.json(statusCode: 401, [
            "status": "failed",
            "error": "unauthorized",
        ])

        let rendered = LocalHTTPServer.render(response: response)
        let renderedText = String(decoding: rendered, as: UTF8.self)

        #expect(renderedText.contains("HTTP/1.1 401 Unauthorized"))
    }

    @Test
    func renderIncludesCustomHeaders() {
        let response = HTTPResponse(
            statusCode: 401,
            body: Data("{}".utf8),
            headers: [
                "WWW-Authenticate": #"Bearer realm="W4L Loader", charset="UTF-8""#,
            ]
        )

        let rendered = LocalHTTPServer.render(response: response)
        let renderedText = String(decoding: rendered, as: UTF8.self)

        #expect(renderedText.contains("WWW-Authenticate: Bearer realm=\"W4L Loader\", charset=\"UTF-8\""))
    }

    @Test
    func normalizeRoutePathStripsQueryString() {
        #expect(LocalHTTPServer.normalizeRoutePath("/v1/models?limit=20") == "/v1/models")
        #expect(LocalHTTPServer.normalizeRoutePath("/status") == "/status")
    }

    @Test
    func unauthorizedResponseForOpenAIPathUsesOpenAIErrorShape() throws {
        let response = LocalHTTPServer.unauthorizedResponse(forPath: "/v1/chat/completions")
        #expect(response.statusCode == 401)
        #expect(response.headers["WWW-Authenticate"] != nil)

        let json = try #require(
            JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        )
        let error = try #require(json["error"] as? [String: Any])
        #expect(error["type"] as? String == "authentication_error")
        #expect(error["code"] as? String == "invalid_api_key")
    }

    @Test
    func unauthorizedResponseForControlPathUsesLoaderErrorShape() throws {
        let response = LocalHTTPServer.unauthorizedResponse(forPath: "/generate")
        #expect(response.statusCode == 401)

        let json = try #require(
            JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        )
        #expect(json["status"] as? String == "failed")
        #expect(json["error"] as? String == "unauthorized")
    }
}
