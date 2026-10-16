import Foundation

/// Recognises an X/Twitter post link by its status ID, so the same post is the
/// same clip whatever tracking query (`?s=43`) or host form it arrives with.
enum XPostLink {

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
}
