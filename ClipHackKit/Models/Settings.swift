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

    enum HPFCutoff: Int, CaseIterable, Codable, Sendable {
        case dcBlock  = 20
        case lowCut   = 40
        case standard = 80
    }

    var sampleRate: SampleRate = .s44100
    var limitDb: Double = -1.0
    var hpfCutoff: HPFCutoff = .standard
    var dynamicLevelingEnabled: Bool = false
    var dynamicLevelingAmount: Double = 0.5
    var loudnormEnabled: Bool = false
    var loudnormTarget: Double = -18.0
    var stereoOutput: Bool = false
    var channel: MonoChannel = .left
    var outputDirectoryPath: String? = nil
    /// User-chosen folder for downloaded source audio; nil ⇒ ~/Music/ClipHack.
    var downloadDirectoryPath: String? = nil
    /// The show folder holding one subfolder per episode — the session list is
    /// read from here. nil until a session folder is chosen, at which point it
    /// is inferred from that folder's parent.
    var sessionRootPath: String? = nil

    private static let storageKey = "ClipHackSettings"

    /// Where preferences persist.
    ///
    /// Overridable because the view model writes on every change (`settings`
    /// has a saving `didSet`), so any test that constructs one and touches a
    /// setting would otherwise rewrite the real user's folders. Tests point
    /// this at a scratch suite; the app never reassigns it.
    static var store: UserDefaults = .standard

    static func load() -> ClipHackSettings {
        guard let data = store.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(ClipHackSettings.self, from: data)
        else {
            return ClipHackSettings()
        }
        return settings
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.store.set(data, forKey: Self.storageKey)
    }
}

// Custom decoder lives in an extension so the synthesized memberwise initializer
// remains available. Any missing key falls back to the property default — adding
// a new field to a persisted struct won't invalidate existing UserDefaults blobs.
extension ClipHackSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClipHackSettings()
        self.init(
            sampleRate:             try c.decodeIfPresent(SampleRate.self,  forKey: .sampleRate)             ?? d.sampleRate,
            limitDb:                try c.decodeIfPresent(Double.self,      forKey: .limitDb)                ?? d.limitDb,
            hpfCutoff:              try c.decodeIfPresent(HPFCutoff.self,   forKey: .hpfCutoff)              ?? d.hpfCutoff,
            dynamicLevelingEnabled: try c.decodeIfPresent(Bool.self,        forKey: .dynamicLevelingEnabled) ?? d.dynamicLevelingEnabled,
            dynamicLevelingAmount:  try c.decodeIfPresent(Double.self,      forKey: .dynamicLevelingAmount)  ?? d.dynamicLevelingAmount,
            loudnormEnabled:        try c.decodeIfPresent(Bool.self,        forKey: .loudnormEnabled)        ?? d.loudnormEnabled,
            loudnormTarget:         try c.decodeIfPresent(Double.self,      forKey: .loudnormTarget)         ?? d.loudnormTarget,
            stereoOutput:           try c.decodeIfPresent(Bool.self,        forKey: .stereoOutput)           ?? d.stereoOutput,
            channel:                try c.decodeIfPresent(MonoChannel.self, forKey: .channel)                ?? d.channel,
            outputDirectoryPath:    try c.decodeIfPresent(String.self,      forKey: .outputDirectoryPath)    ?? d.outputDirectoryPath,
            downloadDirectoryPath:  try c.decodeIfPresent(String.self,      forKey: .downloadDirectoryPath)  ?? d.downloadDirectoryPath,
            sessionRootPath:        try c.decodeIfPresent(String.self,      forKey: .sessionRootPath)        ?? d.sessionRootPath
        )
    }
}
