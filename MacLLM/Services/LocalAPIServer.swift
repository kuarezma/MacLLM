import Foundation
import Network
import OSLog

final class LocalAPIServer: ObservableObject {
    static let shared = LocalAPIServer()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacLLM", category: "LocalAPIServer")

    @Published var isRunning: Bool = false
    @Published var port: UInt16 = 11434
    var endpointURL: String { "http://127.0.0.1:\(port)" }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.macllm.apiserver", qos: .userInitiated)

    var inferenceHandler: ((_ prompt: String, _ systemPrompt: String?, _ onToken: @escaping (String) -> Void, _ onCompletion: @escaping (String) -> Void) -> Void)?

    private init() {}

    func start(on port: UInt16 = 11434) {
        stop()
        self.port = port

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let portObj = NWEndpoint.Port(rawValue: port) else {
                logger.error("Geçersiz port: \(port)")
                return
            }

            let listener = try NWListener(using: params, on: portObj)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.logger.info("Yerel API Sunucusu port \(port) üzerinde çalışıyor.")
                    case .failed(let error):
                        self?.isRunning = false
                        self?.logger.error("API Sunucusu hata verdi: \(error.localizedDescription)")
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }

            listener.start(queue: queue)
        } catch {
            logger.error("Listener başlatılamadı: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    // MARK: - Connection Handling

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHTTPRequest(connection: connection)
    }

    private func readHTTPRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty, error == nil else {
                connection.cancel()
                return
            }

            if let requestString = String(data: data, encoding: .utf8) {
                self.processHTTPRequest(requestString, rawData: data, connection: connection)
            } else {
                self.sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\": \"Bad Request\"}")
            }
        }
    }

    private func processHTTPRequest(_ requestString: String, rawData: Data, connection: NWConnection) {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\": \"Invalid Request\"}")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\": \"Invalid Request Line\"}")
            return
        }

        let method = parts[0].uppercased()
        let path = parts[1]

        if method == "OPTIONS" {
            sendCORSResponse(connection: connection)
            return
        }

        var bodyString = ""
        if let bodyRange = requestString.range(of: "\r\n\r\n") {
            bodyString = String(requestString[bodyRange.upperBound...])
        }

        switch path {
        case "/v1/chat/completions":
            handleOpenAIChatCompletion(body: bodyString, connection: connection)

        case "/v1/models", "/api/tags":
            handleModelsList(connection: connection)

        case "/api/generate":
            handleOllamaGenerate(body: bodyString, connection: connection)

        case "/api/chat":
            handleOllamaChat(body: bodyString, connection: connection)

        default:
            sendHTTPResponse(connection: connection, statusCode: 404, body: "{\"error\": \"Not Found\", \"path\": \"\(path)\"}")
        }
    }

    // MARK: - OpenAI Endpoints

    private func handleOpenAIChatCompletion(body: String, connection: NWConnection) {
        guard let data = body.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\": \"Invalid OpenAI Chat JSON payload\"}")
            return
        }

        let stream = (json["stream"] as? Bool) ?? false
        var userPrompt = ""
        var systemPrompt: String? = nil

        for msg in messages {
            let role = (msg["role"] as? String) ?? "user"
            let content = (msg["content"] as? String) ?? ""
            if role == "system" {
                systemPrompt = content
            } else if role == "user" {
                userPrompt = content
            }
        }

        if let handler = inferenceHandler {
            if stream {
                sendChunkedSSEHeader(connection: connection)
                handler(userPrompt, systemPrompt) { [weak self] token in
                    self?.sendOpenAISSEChunk(token: token, connection: connection)
                } _: { [weak self] _ in
                    self?.sendOpenAISSEDone(connection: connection)
                }
            } else {
                handler(userPrompt, systemPrompt) { _ in } _: { [weak self] fullText in
                    let responsePayload: [String: Any] = [
                        "id": "chatcmpl-\(UUID().uuidString)",
                        "object": "chat.completion",
                        "created": Int(Date().timeIntervalSince1970),
                        "model": "MacLLM-Active",
                        "choices": [
                            [
                                "index": 0,
                                "message": ["role": "assistant", "content": fullText],
                                "finish_reason": "stop"
                            ]
                        ]
                    ]
                    let resData = (try? JSONSerialization.data(withJSONObject: responsePayload)) ?? Data()
                    self?.sendHTTPResponse(connection: connection, statusCode: 200, body: String(data: resData, encoding: .utf8) ?? "{}")
                }
            }
        } else {
            sendHTTPResponse(connection: connection, statusCode: 503, body: "{\"error\": \"MacLLM Inference engine is not ready.\"}")
        }
    }

    // MARK: - Ollama Endpoints

    private func handleOllamaGenerate(body: String, connection: NWConnection) {
        guard let data = body.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let prompt = json["prompt"] as? String else {
            sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\": \"Invalid Ollama generate JSON payload\"}")
            return
        }

        let system = json["system"] as? String

        if let handler = inferenceHandler {
            handler(prompt, system) { _ in } _: { [weak self] fullText in
                let responsePayload: [String: Any] = [
                    "model": "macllm",
                    "created_at": ISO8601DateFormatter().string(from: Date()),
                    "response": fullText,
                    "done": true
                ]
                let resData = (try? JSONSerialization.data(withJSONObject: responsePayload)) ?? Data()
                self?.sendHTTPResponse(connection: connection, statusCode: 200, body: String(data: resData, encoding: .utf8) ?? "{}")
            }
        } else {
            sendHTTPResponse(connection: connection, statusCode: 503, body: "{\"error\": \"MacLLM engine not ready.\"}")
        }
    }

    private func handleOllamaChat(body: String, connection: NWConnection) {
        handleOpenAIChatCompletion(body: body, connection: connection)
    }

    private func handleModelsList(connection: NWConnection) {
        let payload: [String: Any] = [
            "object": "list",
            "data": [
                [
                    "id": "MacLLM-Active",
                    "object": "model",
                    "owned_by": "macllm"
                ]
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        sendHTTPResponse(connection: connection, statusCode: 200, body: String(data: data, encoding: .utf8) ?? "{}")
    }

    // MARK: - HTTP Helpers

    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let response = """
        HTTP/1.1 \(statusCode) OK\r
        Content-Type: application/json\r
        Content-Length: \(bodyData.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization\r
        Connection: close\r
        \r
        \(body)
        """

        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    private func sendCORSResponse(connection: NWConnection) {
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization\r
        Access-Control-Max-Age: 86400\r
        Connection: close\r
        \r
        """
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    private func sendChunkedSSEHeader(connection: NWConnection) {
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        \r
        """
        if let data = header.data(using: .utf8) {
            connection.send(content: data, isComplete: false, completion: .contentProcessed({ _ in }))
        }
    }

    private func sendOpenAISSEChunk(token: String, connection: NWConnection) {
        let payload: [String: Any] = [
            "id": "chatcmpl-\(UUID().uuidString)",
            "object": "chat.completion.chunk",
            "created": Int(Date().timeIntervalSince1970),
            "model": "MacLLM-Active",
            "choices": [
                [
                    "index": 0,
                    "delta": ["content": token],
                    "finish_reason": NSNull()
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonStr = String(data: data, encoding: .utf8) {
            let chunk = "data: \(jsonStr)\n\n"
            if let chunkData = chunk.data(using: .utf8) {
                connection.send(content: chunkData, isComplete: false, completion: .contentProcessed({ _ in }))
            }
        }
    }

    private func sendOpenAISSEDone(connection: NWConnection) {
        let done = "data: [DONE]\n\n"
        if let data = done.data(using: .utf8) {
            connection.send(content: data, isComplete: true, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }
}
