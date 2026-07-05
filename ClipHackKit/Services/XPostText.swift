import Foundation

/// Best-effort fetch of an X/Twitter post's body text for pre-filling Notes.
///
/// X serves logged-out visitors a client-rendered app shell with no post text
/// and no og:/twitter: meta tags, so the page itself is unscrapeable. Instead
/// we hit `cdn.syndication.twimg.com/tweet-result` — the same no-auth JSON
/// backend that powers embedded-tweet widgets across the web. This is
/// undocumented and may break whenever X changes it; every failure path
/// returns nil and the caller silently proceeds without pre-filled notes.
enum XPostText {

    // MARK: - URL detection

    /// The numeric status ID for an X/Twitter post URL, or nil if the URL is
    /// not a post link. Matches `…/status/<digits>` and `…/i/web/status/<digits>`,
    /// so it rejects profile, media-gallery, search, and home paths.
    nonisolated static func statusID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              let host = comps.host?.lowercased() else { return nil }

        let bare: String
        if host.hasPrefix("www.") { bare = String(host.dropFirst(4)) }
        else if host.hasPrefix("mobile.") { bare = String(host.dropFirst(7)) }
        else { bare = host }
        guard bare == "x.com" || bare == "twitter.com" else { return nil }

        let parts = comps.path.split(separator: "/").map(String.init)
        guard let statusIdx = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }),
              statusIdx + 1 < parts.count else { return nil }

        let candidate = parts[statusIdx + 1]
        guard !candidate.isEmpty, candidate.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        return candidate
    }

    // MARK: - Endpoint

    /// The token X's embed widget derives from the ID (`(id/1e15 * π)` in
    /// base-36, zeros and dot stripped). The endpoint does not currently
    /// validate it, but matching the widget maximizes durability if it ever
    /// starts.
    nonisolated static func token(forID id: String) -> String {
        guard let n = Double(id) else { return "0" }
        var s = base36((n / 1e15) * Double.pi)
        s.removeAll { $0 == "0" || $0 == "." }
        return s.isEmpty ? "0" : s
    }

    nonisolated static func syndicationURL(forID id: String) -> URL? {
        var comps = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")
        comps?.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "token", value: token(forID: id)),
            URLQueryItem(name: "lang", value: "en"),
        ]
        return comps?.url
    }

    // MARK: - Parsing

    private struct TweetResult: Decodable {
        let text: String?
        let displayTextRange: [Int]?

        enum CodingKeys: String, CodingKey {
            case text
            case displayTextRange = "display_text_range"
        }
    }

    /// The post's visible body text from a `tweet-result` JSON payload, or nil
    /// if the bytes aren't that payload (a bad ID returns an HTML error page,
    /// which fails to decode) or carry no usable text.
    nonisolated static func parsePostText(fromJSON data: Data) -> String? {
        guard let result = try? JSONDecoder().decode(TweetResult.self, from: data),
              let text = result.text else { return nil }
        let trimmed = trimmedText(text, displayTextRange: result.displayTextRange)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trims the post text to its `display_text_range` (UTF-16 indices), which
    /// drops the trailing t.co media link X appends; falls back to the whole
    /// text when the range is absent or out of bounds.
    nonisolated static func trimmedText(_ text: String, displayTextRange: [Int]?) -> String {
        if let range = displayTextRange, range.count == 2 {
            let lo = range[0], hi = range[1]
            let units = Array(text.utf16)
            if lo >= 0, hi <= units.count, lo <= hi {
                let slice = Array(units[lo..<hi])
                let sub = String(utf16CodeUnits: slice, count: slice.count)
                return sub.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Fetch

    /// Fetches the post body for an X/Twitter URL, or nil for any non-X URL,
    /// network failure, non-200, non-JSON body, or missing text. Never throws.
    nonisolated static func fetchPostText(for urlString: String, session: URLSession = .shared) async -> String? {
        guard let id = statusID(from: urlString), let url = syndicationURL(forID: id) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return parsePostText(fromJSON: data)
        } catch {
            return nil
        }
    }

    // MARK: - Private

    /// JS `Number.toString(36)`-style rendering of a non-negative Double —
    /// integer part, then up to 20 fractional base-36 digits.
    private nonisolated static func base36(_ value: Double) -> String {
        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let intPart = value.rounded(.towardZero)

        var intStr = ""
        var ip = intPart
        if ip < 1 {
            intStr = "0"
        } else {
            while ip >= 1 {
                let d = Int(ip.truncatingRemainder(dividingBy: 36))
                intStr = String(digits[d]) + intStr
                ip = (ip / 36).rounded(.towardZero)
            }
        }

        var fracStr = ""
        var frac = value - intPart
        var count = 0
        while frac > 0, count < 20 {
            frac *= 36
            let d = Int(frac.rounded(.towardZero))
            fracStr += String(digits[min(d, 35)])
            frac -= Double(d)
            count += 1
        }

        return fracStr.isEmpty ? intStr : intStr + "." + fracStr
    }
}
