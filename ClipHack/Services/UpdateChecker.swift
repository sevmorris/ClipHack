import AppKit
import ClipHackKit

actor UpdateChecker {

    enum Result {
        case upToDate(version: String)
        case available(version: String, downloadURL: URL, releaseURL: URL)
        /// Newer than this build, but it needs a newer macOS than this Mac has.
        case needsNewerMacOS(version: String, minimum: String, installed: String)
        case error(String)
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: String
        let assets: [Asset]
        /// The release notes, which carry the minimum-macos marker.
        let body: String?

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case assets
            case body
        }
    }

    /// App release tags only (`v1.2.3`). Ignores non-semver asset releases.
    private static func isAppReleaseTag(_ tag: String) -> Bool {
        guard tag.first == "v" else { return false }
        let version = tag.dropFirst()
        guard version.contains(".") else { return false }
        return version.allSatisfy { $0.isNumber || $0 == "." }
    }

    func check() async -> Result {
        do {
            guard let release = try await fetchLatestAppRelease() else {
                return .error("No app release found on GitHub.")
            }

            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            guard let releaseURL = URL(string: release.htmlUrl)
                    ?? URL(string: "https://github.com/sevmorris/ClipHack-releases/releases") else {
                return .error("Invalid release URL in GitHub response.")
            }
            let downloadURL = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
                .flatMap { URL(string: $0.browserDownloadUrl) }
                ?? releaseURL

            if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                // A release this Mac cannot run is not an update for it: its DMG
                // would replace a working app with one that will not open.
                if let minimum = ReleaseRequirement.minimumMacOS(inReleaseNotes: release.body),
                   !ReleaseRequirement.runs(on: ProcessInfo.processInfo.operatingSystemVersion, given: minimum) {
                    return .needsNewerMacOS(version: latestVersion, minimum: ReleaseRequirement.describe(minimum),
                                            installed: currentVersion)
                }
                return .available(version: latestVersion, downloadURL: downloadURL, releaseURL: releaseURL)
            } else {
                return .upToDate(version: currentVersion)
            }

        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func githubRequest(path: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw UpdateFetchError.badResponse
        }
        return (data, http)
    }

    private func fetchLatestAppRelease() async throws -> Release? {
        let (latestData, _) = try await githubRequest(
            path: "/repos/sevmorris/ClipHack-releases/releases/latest"
        )
        let latest = try JSONDecoder().decode(Release.self, from: latestData)
        if Self.isAppReleaseTag(latest.tagName) {
            return latest
        }

        let (listData, _) = try await githubRequest(
            path: "/repos/sevmorris/ClipHack-releases/releases?per_page=30"
        )
        let releases = try JSONDecoder().decode([Release].self, from: listData)
        return releases.first { Self.isAppReleaseTag($0.tagName) }
    }
}

private enum UpdateFetchError: LocalizedError {
    case badResponse

    var errorDescription: String? {
        "Could not reach GitHub. Check your internet connection."
    }
}

/// Show an update dialog. When `silent` is true (launch check), only prompt if
/// an update is actually available.
@MainActor
func checkForUpdates(silent: Bool = false) async {
    let result = await UpdateChecker().check()

    switch result {
    case .upToDate(let version):
        guard !silent else { return }
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "ClipHack \(version) is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()

    case .available(let version, let downloadURL, let releaseURL):
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "ClipHack \(version) is available."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadURL)
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }

    case .needsNewerMacOS(let version, let minimum, let installed):
        // Nothing this Mac can install, so the check at launch says nothing.
        guard !silent else { return }
        let alert = NSAlert()
        alert.messageText = "ClipHack \(version) needs macOS \(minimum)"
        alert.informativeText = "This Mac has macOS \(ReleaseRequirement.describe(ProcessInfo.processInfo.operatingSystemVersion)), "
            + "so ClipHack \(installed) is the newest version it can run."
        alert.addButton(withTitle: "OK")
        alert.runModal()

    case .error(let message):
        guard !silent else { return }
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
