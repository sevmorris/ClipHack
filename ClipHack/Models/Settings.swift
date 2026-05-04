import Foundation

struct ClipHackSettings: Codable, Equatable, Sendable {
    enum SampleRate: Int, CaseIterable, Codable, Sendable {
        case s44100 = 44100
        case s48000 = 48000
    }

    enum MonoChannel: String, CaseIterable, Codable, Sendable {
        case left
        case right
    }

    var sampleRate: SampleRate = .s44100
    var limitDb: Double = -1.0
    var levelingEnabled: Bool = false
    var dcBlockHz: Int = 80
    var loudnormEnabled: Bool = false
    var loudnormTarget: Double = -18.0
    var stereoOutput: Bool = false
    var channel: MonoChannel = .left
    var outputDirectoryPath: String? = nil

    private static let storageKey = "ClipHackSettings"

    static func load() -> ClipHackSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(ClipHackSettings.self, from: data)
        else {
            return ClipHackSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
