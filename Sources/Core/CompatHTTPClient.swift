import Foundation
import Network

/// 兼容网络引擎：直接用 Network.framework 走 TCP/TLS，完全绕开 CFNetwork（URLSession）。
/// 背景：iOS 18 + 特定系统代理配置下，CFNetwork 初始化 URL 转义路径会崩
/// （-[__NSCFNumber length]: unrecognized selector @ CFURLCreateStringByAddingPercentEscapes）。
/// 该引擎不读系统代理、不使用 CFNetwork，可作逃生通道；HTTP/1.1 + chunked 足够 SSE 聊天。
final class CompatHTTPClient: @unchecked Sendable {
    func stream(config: EndpointConfig, messages: [ChatMessage]) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try StreamingChatClient.buildRequest(config: config, messages: messages)
                    var parser = SSEDeltaParser()
                    for try await line in try Self.lines(for: request) {
                        if Task.isCancelled { break }
                        for event in try parser.feed(line: line) {
                            if case .finished = event {
                                continuation.finish()
                                return
                            }
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    if error is ChatError {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish(throwing: ChatError.network(error.localizedDescription))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 连接与收发

    private static func lines(for request: URLRequest) throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let url = request.url, let hostString = url.host, !hostString.isEmpty else {
                continuation.finish(throwing: ChatError.badURL)
                return
            }
            let scheme = (url.scheme ?? "https").lowercased()
            let isTLS = scheme == "https"
            let portValue = url.port ?? (isTLS ? 443 : 80)
            guard let port = NWEndpoint.Port(rawValue: UInt16(truncatingIfNeeded: portValue)) else {
                continuation.finish(throwing: ChatError.badURL)
                return
            }

            // 请求字节
            let path = url.path.isEmpty ? "/" : url.path
            let query = url.query.map { "?" + $0 } ?? ""
            var head = "\(request.httpMethod ?? "POST") \(path)\(query) HTTP/1.1\r\n"
            head += "Host: \(hostString)\r\n"
            for (name, value) in request.allHTTPHeaderFields ?? [:] {
                head += "\(name): \(value)\r\n"
            }
            let body = request.httpBody ?? Data()
            head += "Content-Length: \(body.count)\r\n"
            head += "Connection: close\r\n\r\n"
            var payload = Data(head.utf8)
            payload.append(body)

            let tls = isTLS ? NWProtocolTLS.Options() : nil
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = 30
            let params = NWParameters(tls: tls, tcp: tcp)
            let connection = NWConnection(host: NWEndpoint.Host(hostString), port: port, using: params)

            let parser = HTTPStreamParser()
            let lock = NSLock()

            func finishWithCurrentError(_ fallback: String) {
                if parser.statusCode != 0 && parser.statusCode != 200 {
                    continuation.finish(throwing: ChatError.http(parser.statusCode, parser.errorMessage(fallback: fallback)))
                } else {
                    continuation.finish()
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            continuation.finish(throwing: ChatError.network(error.localizedDescription))
                            connection.cancel()
                        }
                    })
                case .failed(let error):
                    continuation.finish(throwing: ChatError.network(error.localizedDescription))
                    connection.cancel()
                case .cancelled:
                    continuation.finish()
                default:
                    break
                }
            }

            func receiveLoop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        lock.lock()
                        let lines: [String]
                        var feedError: Error?
                        do { lines = try parser.feed(data) } catch { lines = []; feedError = error }
                        let done = parser.isComplete
                        lock.unlock()
                        if let feedError {
                            continuation.finish(throwing: feedError)
                            connection.cancel()
                            return
                        }
                        for line in lines { continuation.yield(line) }
                        if done {
                            finishWithCurrentError("连接结束")
                            connection.cancel()
                            return
                        }
                    }
                    if isComplete || error != nil {
                        finishWithCurrentError("连接结束")
                        connection.cancel()
                        return
                    }
                    receiveLoop()
                }
            }

            continuation.onTermination = { _ in connection.cancel() }
            connection.start(queue: DispatchQueue(label: "compat.http.client", qos: .userInitiated))
            receiveLoop()
        }
    }
}
