import Foundation

/// HTTP/1.1 响应增量解析器（配合 Network.framework 的 CompatHTTPClient）。
/// 只做流式聊天需要的子集：状态行/头解析、Content-Length 与 chunked、按行输出。
/// 纯逻辑，可单测。
final class HTTPStreamParser {
    private var headerBuffer = Data()
    private(set) var headersParsed = false
    private(set) var statusCode: Int = 0
    private var chunkedTransfer = false
    private var expectedLength: Int?
    private var receivedBodyBytes = 0
    private var finishedBody = false

    // chunked 状态机
    private enum ChunkState {
        case sizeLine
        case data(remaining: Int)
        case dataTerminator
        case trailers
    }
    private var chunkState: ChunkState = .sizeLine
    private var sizeBuffer = Data()

    // 行输出缓冲 / 错误体收集
    private var lineBuffer = Data()
    private(set) var errorBody = Data()

    /// 喂一段收到的字节，返回可用的完整行（仅 200 响应）。
    /// 非 200 时所有字节进 errorBody，由调用方在结束时构造错误。
    func feed(_ data: Data) throws -> [String] {
        guard !finishedBody else { return [] }

        if !headersParsed {
            headerBuffer.append(data)
            guard let headerEnd = headerBuffer.range(of: Data("\r\n\r\n".utf8)) else {
                if headerBuffer.count > 64 * 1024 { throw ChatError.badResponse }
                return []
            }
            let headerData = headerBuffer.subdata(in: 0..<headerEnd.lowerBound)
            let bodyPart = headerBuffer.subdata(in: headerEnd.upperBound..<headerBuffer.count)
            headerBuffer = Data()
            try parseHeaders(headerData)
            headersParsed = true
            return try feed(bodyPart)
        }

        if statusCode != 200 {
            errorBody.append(data)
            if errorBody.count > 64 * 1024 { errorBody = errorBody.prefix(64 * 1024) }
            return []
        }

        if chunkedTransfer {
            return processChunked(data)
        }

        if data.isEmpty { return [] }

        if let expected = expectedLength {
            let take = min(data.count, max(0, expected - receivedBodyBytes))
            if take <= 0 { finishedBody = true; return [] }
            receivedBodyBytes += take
            let chunk = data.prefix(take)
            if receivedBodyBytes >= expected { finishedBody = true }
            return extractLines(from: Data(chunk))
        }

        // 无 Content-Length：读到连接关闭为止
        return extractLines(from: data)
    }

    var isComplete: Bool { finishedBody }

    func errorMessage(fallback: String) -> String {
        ErrorBodyExtractor.message(from: errorBody, fallback: fallback)
    }

    // MARK: - 头部

    private func parseHeaders(_ data: Data) throws {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw ChatError.badResponse }
        // 例：HTTP/1.1 200 OK
        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]) else {
            throw ChatError.badResponse
        }
        statusCode = code
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("transfer-encoding:") && lower.contains("chunked") {
                chunkedTransfer = true
            } else if lower.hasPrefix("content-length:"),
                      let value = Int(line.split(separator: ":", maxSplits: 1).last?
                          .trimmingCharacters(in: .whitespaces) ?? "") {
                expectedLength = value
            }
        }
    }

    // MARK: - chunked

    private func processChunked(_ data: Data) -> [String] {
        var out: [String] = []
        var idx = 0
        let bytes = [UInt8](data)
        while idx < bytes.count && !finishedBody {
            switch chunkState {
            case .sizeLine:
                while idx < bytes.count {
                    sizeBuffer.append(bytes[idx]); idx += 1
                    if sizeBuffer.count >= 2,
                       sizeBuffer[sizeBuffer.count - 2] == 0x0D, sizeBuffer[sizeBuffer.count - 1] == 0x0A {
                        let line = String(decoding: sizeBuffer.dropLast(2), as: UTF8.self)
                        sizeBuffer = Data()
                        let hex = line.split(separator: ";").first.map(String.init) ?? line
                        if let size = Int(hex.trimmingCharacters(in: .whitespaces), radix: 16) {
                            if size == 0 {
                                chunkState = .trailers
                            } else {
                                chunkState = .data(remaining: size)
                            }
                        }
                        break
                    }
                }
            case .data(let remaining):
                let take = min(remaining, bytes.count - idx)
                out.append(contentsOf: extractLines(from: Data(bytes[idx..<idx + take])))
                idx += take
                chunkState = take == remaining ? .dataTerminator : .data(remaining: remaining - take)
            case .dataTerminator:
                // 吃掉 \r\n
                var skipped = 0
                while idx < bytes.count && skipped < 2 {
                    idx += 1; skipped += 1
                }
                if skipped == 2 { chunkState = .sizeLine }
            case .trailers:
                // 忽略 trailer，直到空行；简单起见：本段结束即认为完成
                finishedBody = true
            }
        }
        return out
    }

    // MARK: - 行拆分

    private func extractLines(from data: Data) -> [String] {
        lineBuffer.append(data)
        var lines: [String] = []
        while let lf = lineBuffer.firstIndex(of: 0x0A) {
            var lineData = lineBuffer.prefix(upTo: lf)
            if lineData.last == 0x0D { lineData = lineData.dropLast() }
            if let line = String(data: Data(lineData), encoding: .utf8) {
                lines.append(line)
            }
            lineBuffer = Data(lineBuffer[lineBuffer.index(after: lf)...])
        }
        return lines
    }
}
