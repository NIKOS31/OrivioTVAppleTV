import Foundation
import Network

/// Secondary links supplied by addon data, not a DNS firewall or media
/// redirect policy. A configured LAN addon may refer to its own service;
/// an Internet addon cannot supply a literal private/loopback destination.
enum NTVAddonLinkPolicy {
    static func permits(_ raw: String, source: URL) -> Bool {
        guard let target = try? NTVAddonTransportPolicy.target(raw),
              let host = target.host else { return false }
        let sourceHost = canonicalHost(source.host ?? "")
        let destinationHost = canonicalHost(host)
        guard !destinationHost.isEmpty else { return false }
        let local = isNonPublicHost(destinationHost)
        if local {
            return NTVAddonTransportPolicy.permits(source)
                && isNonPublicHost(sourceHost)
                && destinationHost == sourceHost
                && effectivePort(target) == effectivePort(source)
                && !(source.scheme?.lowercased() == "https" && target.scheme?.lowercased() != "https")
        }
        return true
    }

    private static func effectivePort(_ url: URL) -> Int {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }

    private static func canonicalHost(_ host: String) -> String {
        var value = host.lowercased()
        if value.hasPrefix("["), value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }
        while value.hasSuffix(".") { value.removeLast() }
        return value
    }

    private static func isNonPublicHost(_ host: String) -> Bool {
        if host.contains("%") { return true } // scoped/escaped address aliases
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
           (parts.count != 4 || parts.contains(where: { $0.count > 1 && $0.hasPrefix("0") })) { return true }
        if let address = IPv4Address(host) { return isNonPublicIPv4(Array(address.rawValue)) }
        if let address = IPv6Address(host) {
            let bytes = Array(address.rawValue)
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
                return isNonPublicIPv4(Array(bytes.suffix(4)))
            }
            // Unspecified, loopback, IPv4-compatible, ULA, multicast and
            // link/site-local destinations; block translation aliases too.
            if bytes.prefix(12).allSatisfy({ $0 == 0 }) { return true }
            if bytes[0] & 0xfe == 0xfc || bytes[0] == 0xff { return true }
            if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0x80 || bytes[1] & 0xc0 == 0xc0 { return true }
            if bytes[0] == 0, bytes[1] == 0x64, bytes[2] == 0xff, bytes[3] == 0x9b { return true }
            if bytes[0] & 0xe0 != 0x20 { return true }
            if bytes[0] == 0x20, bytes[1] == 0x02 { return true } // 6to4 alias
            if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0, bytes[3] == 0 { return true } // Teredo
            return false
        }
        if host.contains(":") { return true }
        // Resolver-specific numeric IPv4 forms (127.1, 2130706433, octal,
        // hexadecimal) cannot pass as Internet hostnames.
        if host.split(separator: ".").allSatisfy({ part in
            part.allSatisfy({ $0.isASCII && $0.isNumber }) || part.hasPrefix("0x")
        }) { return true }
        if !host.contains(".") { return true }
        return ["localhost", "local", "internal", "home", "lan"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    private static func isNonPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return true }
        let a = bytes[0], b = bytes[1]
        if a == 0 || a == 10 || a == 127 || a >= 224 { return true }
        if a == 100, (64...127).contains(b) { return true }
        if a == 169, b == 254 { return true }
        if a == 172, (16...31).contains(b) { return true }
        if a == 192, b == 168 || b == 0 { return true }
        if a == 198, b == 18 || b == 19 { return true }
        return false
    }
}
