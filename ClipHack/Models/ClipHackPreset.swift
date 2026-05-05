import Foundation
import Observation

struct ClipHackPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var settings: ClipHackSettings

    init(id: UUID = UUID(), name: String, settings: ClipHackSettings) {
        self.id = id
        self.name = name
        self.settings = settings
    }

    static let builtIn: [ClipHackPreset] = [
        // Broadcast clips (news, ads) played live into a Zoom call via Farrago/Loopback.
        // Leveling tames wildly dynamic sources; loudness normalized to -18 LUFS.
        ClipHackPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Broadcast Conform",
            settings: ClipHackSettings(
                sampleRate: .s44100,
                limitDb: -1.0,
                dcBlockHz: 80,
                loudnormEnabled: true,
                loudnormTarget: -18.0,
                stereoOutput: false,
                channel: .left,
                outputDirectoryPath: nil
            )
        ),
        // Minimal processing — high-pass at DC block + limiter only. Good for already
        // well-produced sources that just need a safety ceiling.
        ClipHackPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Clean & Limit",
            settings: ClipHackSettings(
                sampleRate: .s44100,
                limitDb: -1.0,
                dcBlockHz: 20,
                loudnormEnabled: false,
                loudnormTarget: -18.0,
                stereoOutput: false,
                channel: .left,
                outputDirectoryPath: nil
            )
        ),
        // High-pass + EBU R128 loudness normalization + limiter. No leveling.
        // Good for sources with consistent dynamics that just need a loudness target.
        ClipHackPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Normalize & Limit",
            settings: ClipHackSettings(
                sampleRate: .s44100,
                limitDb: -1.0,
                dcBlockHz: 80,
                loudnormEnabled: true,
                loudnormTarget: -18.0,
                stereoOutput: false,
                channel: .left,
                outputDirectoryPath: nil
            )
        )
    ]
}

@Observable
final class ClipHackPresetStore {
    var presets: [ClipHackPreset] = []
    var selectedPresetID: UUID?

    private let userDefaultsKey = "ClipHackUserPresets"

    init() {
        loadPresets()
    }

    var allPresets: [ClipHackPreset] {
        ClipHackPreset.builtIn + presets
    }

    var selectedPreset: ClipHackPreset? {
        guard let id = selectedPresetID else { return nil }
        return allPresets.first { $0.id == id }
    }

    func savePreset(name: String, settings: ClipHackSettings) {
        let preset = ClipHackPreset(name: name, settings: settings)
        presets.append(preset)
        saveToUserDefaults()
    }

    func deletePreset(_ preset: ClipHackPreset) {
        presets.removeAll { $0.id == preset.id }
        if selectedPresetID == preset.id {
            selectedPresetID = nil
        }
        saveToUserDefaults()
    }

    func isBuiltIn(_ preset: ClipHackPreset) -> Bool {
        ClipHackPreset.builtIn.contains { $0.id == preset.id }
    }

    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        presets = (try? JSONDecoder().decode([ClipHackPreset].self, from: data)) ?? []
    }

    private func saveToUserDefaults() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
