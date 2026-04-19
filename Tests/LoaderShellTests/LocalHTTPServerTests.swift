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
}
