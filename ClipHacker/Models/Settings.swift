import Foundation

struct ClipHackerSettings: Codable, Equatable, Sendable {
    enum SampleRate: Int, CaseIterable, Codable, Sendable {
        case s44100 = 44100
        case s48000 = 48000
    }

    var sampleRate: SampleRate = .s44100
    var limitDb: Double = -1.0
    var levelingEnabled: Bool = false
    var levelingAmount: Double = 0.5
    var loudnormEnabled: Bool = false
    var loudnormTarget: Double = -16.0
    var stereoOutput: Bool = false
    var outputDirectoryPath: String? = nil

    private static let storageKey = "ClipHackerSettings"

    static func load() -> ClipHackerSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(ClipHackerSettings.self, from: data)
        else {
            return ClipHackerSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
