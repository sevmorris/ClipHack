import AppKit

/// What the download popover's prefill needs from the pasteboard, split by
/// whether macOS counts it as reading the contents.
///
/// Under macOS's paste privacy rules (the per-app setting in Privacy & Security
/// › Paste from Other Apps, from macOS 15.4), a programmatic read of the
/// general pasteboard that the user did not start with a paste can show an
/// "Allow Paste?" alert. Asking whether the first item *looks like* a web URL,
/// or reading the change count or the access setting, never does. So the
/// prefill asks those first and reads only when there is something worth
/// reading. `.general` is the real pasteboard; tests pass a stub.
struct PasteboardURLSource {
    /// Changes whenever anything is copied. Reading it never prompts.
    var changeCount: () -> Int
    /// False when the user has set this app to Always Deny: a read would be
    /// refused anyway, so the prefill doesn't try.
    var readsAllowed: () -> Bool
    /// Whether the first item probably holds a web URL, by the system's
    /// detection. Never prompts.
    var probablyHoldsWebURL: () async -> Bool
    /// The pasteboard's string. This is the read that can prompt.
    var readString: () -> String?

    static let general = PasteboardURLSource(
        changeCount: { NSPasteboard.general.changeCount },
        readsAllowed: {
            guard #available(macOS 15.4, *) else { return true }
            return NSPasteboard.general.accessBehavior != .alwaysDeny
        },
        probablyHoldsWebURL: {
            // Before 15.4 there is neither detection nor a prompt to avoid, so a
            // plain read is as quiet as asking would be.
            guard #available(macOS 15.4, *) else { return true }
            do {
                let found = try await NSPasteboard.general.detectedPatterns(for: [\.probableWebURL])
                return found.contains(\.probableWebURL)
            } catch {
                return false
            }
        },
        readString: { NSPasteboard.general.string(forType: .string) }
    )
}
