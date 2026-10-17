import Foundation

struct NTVImportHTTPRequest {
    let method: String
    let target: String
    let headers: [String: String]
    let body: String
    let isComplete: Bool

    init?(_ data: Data) {
        guard data.count <= 65_536, let text = String(data: data, encoding: .utf8),
              let boundary = text.range(of: "\r\n\r\n") else { return nil }
        let header = String(text[..<boundary.lowerBound])
        guard header.utf8.count <= 16_384 else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count == 3, parts[2] == "HTTP/1.1", parts[1].hasPrefix("/") else { return nil }
        method = String(parts[0]); target = String(parts[1])
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let key = line[..<colon].lowercased()
            guard !key.isEmpty, fields[key] == nil else { return nil }
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard fields["transfer-encoding"] == nil else { return nil }
        headers = fields
        let length: Int
        if let value = fields["content-length"] {
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let count = Int(value), count <= 32_768 else { return nil }
            length = count
        } else {
            guard method != "POST" else { return nil }
            length = 0
        }
        body = String(text[boundary.upperBound...])
        guard body.utf8.count <= length else { return nil }
        isComplete = body.utf8.count == length
    }
}

/// The random path is a temporary capability shown only on the TV's QR screen.
/// Host/Origin checks additionally reject cross-site form posts and rebinding.
struct NTVAddonImportPolicy {
    let path: String
    let host: String
    let expiresAt: Date
    private var submissions: [Date] = []
    var origin: String { "http://" + host }

    init(host: String, now: Date = Date()) {
        self.host = host
        path = "/" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + "/"
        expiresAt = now.addingTimeInterval(15 * 60)
    }
    mutating func authorize(_ request: NTVImportHTTPRequest, now: Date = Date()) -> Int {
        guard now < expiresAt else { return 410 }
        guard request.target == path, request.headers["host"]?.lowercased() == host.lowercased() else { return 403 }
        guard request.method == "GET" || request.method == "POST" else { return 405 }
        if request.method == "POST" {
            guard request.headers["origin"] == origin,
                  request.headers["content-type"]?.split(separator: ";").first?.lowercased() == "application/x-www-form-urlencoded" else { return 403 }
            submissions.removeAll { now.timeIntervalSince($0) >= 60 }
            guard submissions.count < 12 else { return 429 }
            submissions.append(now)
        }
        return 200
    }
}
