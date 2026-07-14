import Foundation

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    var bearerToken: String? {
        guard let value = headers["authorization"] else { return nil }
        let parts = value.split(whereSeparator: { $0.isWhitespace })
        guard parts.count == 2, parts[0].lowercased() == "bearer", !parts[1].isEmpty else { return nil }
        return String(parts[1])
    }
}
enum HTTPParseError: Error { case malformed, unsupportedMethod, tooLarge, incomplete }
struct HTTPRequestParser {
    let maxHeaderBytes: Int
    let maxBodyBytes: Int
    let maxTotalBytes: Int
    init(maxHeaderBytes: Int = 16 * 1024, maxBodyBytes: Int = 256 * 1024, maxTotalBytes: Int = 272 * 1024) {
        self.maxHeaderBytes = maxHeaderBytes; self.maxBodyBytes = maxBodyBytes; self.maxTotalBytes = maxTotalBytes
    }
    func parse(_ data: Data) throws -> HTTPRequest {
        guard data.count <= maxTotalBytes else { throw HTTPParseError.tooLarge }
        guard let marker = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > maxHeaderBytes { throw HTTPParseError.tooLarge }; throw HTTPParseError.incomplete
        }
        guard marker.lowerBound <= maxHeaderBytes, let head = String(data: data[..<marker.lowerBound], encoding: .utf8) else { throw HTTPParseError.tooLarge }
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { throw HTTPParseError.malformed }
        let parts = first.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "HTTP/1.1", parts[1].hasPrefix("/"), !parts[1].hasPrefix("//") else { throw HTTPParseError.malformed }
        let method = String(parts[0]); guard ["GET", "POST"].contains(method) else { throw HTTPParseError.unsupportedMethod }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { throw HTTPParseError.malformed }
            let key = pair[0].lowercased(); guard headers[key] == nil else { throw HTTPParseError.malformed }
            headers[key] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { throw HTTPParseError.malformed }
        let rawLength = headers["content-length"] ?? "0"
        guard !rawLength.isEmpty, rawLength.allSatisfy(\.isNumber), let length = Int(rawLength) else { throw HTTPParseError.malformed }
        guard length <= maxBodyBytes else { throw HTTPParseError.tooLarge }
        let body = Data(data[marker.upperBound...])
        guard body.count >= length else { throw HTTPParseError.incomplete }
        guard body.count == length else { throw HTTPParseError.malformed }
        return HTTPRequest(method: method, path: String(parts[1]), headers: headers, body: body)
    }
}
