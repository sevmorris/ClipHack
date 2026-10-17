import SwiftUI

public struct HelpView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                section("Overview") {
                    text("""
                    ClipHack prepares audio clips for use in a mix — \
                    normalizing loudness, and brick-wall limiting peaks. It's designed for \
                    broadcast clips (news, promos) that need to sit at a consistent level \
                    before dropping into a podcast or show.
                    """)
                    text("The full manual covers downloading, sessions and the notes file in more detail:")
                    Link("sevmorris.github.io/ClipHack/manual",
                         destination: URL(string: "https://sevmorris.github.io/ClipHack/manual/")!)
                }
                section("Presets") {
                    text("Presets save and recall all settings at once. Three built-in presets are included:")
                    VStack(alignment: .leading, spacing: 8) {
                        definition("Broadcast Conform", "Broadcast clips (news, ads) played live into a Zoom call via Farrago/Loopback. Loudness normalized to -18 LUFS.")
                        definition("Clean & Limit", "Minimal processing — high-pass at DC block + limiter only. Good for already well-produced sources that just need a safety ceiling.")
                        definition("Normalize & Limit", "High-pass + EBU R128 loudness normalization + limiter. Good for sources with consistent dynamics that just need a loudness target.")
                    }
                    text("To save your own preset, open the preset menu and choose **Save Current Settings…**. To delete a custom preset, choose **Delete Preset** from the same menu. Built-in presets cannot be deleted.")
                }
                section("Getting Started") {
                    steps([
                        "Set your sample rate, ceiling, and any processing options.",
                        "Drag and drop audio or video files onto the window — or drop a folder, and ClipHack adds every audio file inside it.",
                        "Click Process.",
                        "Output files are saved alongside the originals (or to your chosen output folder)."
                    ])
                }
                section("Download from URL") {
                    text("Click the link button in the toolbar (⌘L), or drop a web link onto the window, to download a clip's audio into the file list. Video sources are saved as audio only (native codec, no re-encode) into the newest episode's clips folder (see Sessions), or ~/Music/ClipHack when no show folder is set.")
                    text("Downloads land straight in the session's folder — no folder per clip. If a clip of that name is already there, ClipHack stops and names it rather than overwriting or quietly reusing it; give this one a custom name and download it again.")
                    definition("Custom file name", "Optional. Names the download before it lands; stem only, the extension always matches the source audio. Leave blank to keep the source title.")
                    definition("The cut", "Optional. The part of the clip you want — 1:13 to :55, or :18 to end. It goes on the end of the file's name, with each colon written as a period because a file name can't hold one, and stays there when the clip is processed, so it is in front of you while you make the cut: Trump drill 1.13 to .55.m4a becomes Trump drill 1.13 to .55-44knorm-clipped-1dB.wav. The show's clip skill leaves it out of the name it files the clip under. It is also written under the clip's file name in the session's notes file, marked CUT, as you typed it.")
                    definition("Notes file", "ClipHack's own record of an episode's clips — HT_0379 2026-08-24/clips/HT_0379 2026-08-24.txt: each download's file name, cut and link, and the cut of any clip added from disk. It is how a link pasted again is recognised, and how a clip added back gets its cut. There is no need to open it. Nothing is ever appended: re-downloading a clip replaces its block. A temporary session keeps none.")
                    definition("Destination", "Where downloads land: the newest episode's clips folder, or ~/Music/ClipHack when no show folder is set. In a temporary session it is the Desktop. There is nothing to choose here; see Sessions.")
                    definition("Already downloaded", "ClipHack checks a link against the session's notes file. If the clip's file is still in the folder under the name it was downloaded with, it is added to the list instead of fetched a second time. If it has moved on since — processed, with its original in the Trash, or renamed and filed by the clip skill — ClipHack says so and asks; choose Download Again to fetch it anyway.")
                    text("Any row in the list — dropped or downloaded — can be renamed with right-click → Rename…, or by selecting it and pressing Return. The file is renamed on disk; the extension is kept.")
                }
                section("Sessions") {
                    text("One episode is one folder, and the folder's name is the session title — HT_0380 2026-08-24. ClipHack makes none of these folders: the week's prep makes each episode and its clips folder. ClipHack always works in the newest — the episode with the highest number in your show folder — and the current one is the window title.")
                    definition("Following the newest episode", "At launch, whenever you come back to ClipHack, and before each download, it looks for the newest episode and points the download folder and the output folder at its clips folder — so an episode's source audio, its notes file and its finished WAVs stay together, and a new week's episode is used without being chosen.")
                    definition("Set Cut…", "Right-click any row and choose Set Cut… to record the part to keep: the file is renamed to end with it (colons as periods), the notes file records it, and it shows on the row. Changing the cut replaces the one in the name; leave it empty to take it out. In a temporary session the cut goes in the file name only.")
                    definition("Temporary Session", "For a file that isn't for an episode. Downloads and processed audio go to the Desktop, no notes file is written, and the Output Directory controls are off. Your episode is left exactly as it was. Choose it again to leave, which goes back to the newest episode; quitting leaves it too, so ClipHack always opens on your episode. If macOS has refused ClipHack access to the Desktop, allow it in System Settings ▸ Privacy & Security ▸ Files and Folders.")
                    definition("Choose Show Folder", "The folder your episode folders live in. Taken from the episode ClipHack last used when none is set — it is simply the folder above the episode — so there is normally nothing to configure. Pick an episode folder by mistake and ClipHack uses the folder above it instead.")
                    text("A show folder usually holds more than episodes — templates, shared assets, incoming audio. Only numbered episodes are ever used.")
                }
                section("Output Naming") {
                    text("Output filenames reflect what processing was applied. The original name keeps the clip's cut, so Clip 1.13 to .55.m4a comes out as Clip 1.13 to .55-44kclipped-1dB.wav:")
                    code("{original-name}-{rate}{norm-}clipped-{limit}dB.wav")
                    VStack(alignment: .leading, spacing: 4) {
                        text("Example:")
                        code("clip-44kclipped-1dB.wav")
                    }
                }
                section("Processing Pipeline") {
                    text("ClipHack uses FFmpeg. Each stage is optional except high-pass, phase rotation, and the final limiter:")
                    numberedList([
                        "Resample to target sample rate (skipped if already matching).",
                        "Channel extraction — pan stereo to mono (left or right channel).",
                        "High-pass filter + phase rotation — removes low-frequency rumble and DC offset; allpass filter corrects phase shift. Always applied.",
                        "Loudness Norm — two-pass EBU R128 loudness normalization to a target LUFS.",
                        "Brick-wall limiting that holds sample peaks at your ceiling."
                    ])
                    text("Output format: 24-bit WAV")
                }
                section("Settings") {
                    text("These apply to every file in the queue. The one exception is channel handling, which a clip can override for itself — see **Per-clip output channels** below.")
                    definition("Sample Rate", "Output sample rate — 44.1 kHz or 48 kHz.")
                    definition("Ceiling", "Brick-wall limiter ceiling, from -6 dB to -1 dB. Sets the maximum peak level of the output.")
                    definition("High Pass", "High-pass filter cutoff — three options. DC Block (20 Hz): removes DC offset only, passes all audible content including bass fundamentals. 40 Hz: removes subsonic rumble while preserving music bass. 80 Hz: standard voice HPF, removes proximity effect and handling noise.")
                    definition("Dynamic Leveling", "Enables bidirectional dynamic normalization (dynaudnorm). Lifts quiet voices and tames loud ones. Best for panel recordings, live Q&As, or multi-guest interviews where voices are at inconsistent levels — not for regular solo voice use. Aggressiveness controls how quickly and strongly the leveling responds.")
                    definition("Loudness Norm", "Enables two-pass EBU R128 loudness normalization. Runs before the limiter.")
                    definition("Target", "Loudness normalization target in LUFS, from -35 to -14. -18 LUFS is a common podcast insertion target.")
                    definition("Trash Originals", "On by default. Moves each source file to the Trash once its processed output is written — the output is checked on disk first, and a file that fails to process is always kept. Recover anything you want back from the Trash. Note that a downloaded clip whose audio has been trashed will download again if you reuse the same link.")
                    definition("Output Directory", "Custom output folder for processed files. Defaults to the same directory as the source file.")
                }
                section("Per-Clip Output Channels") {
                    text("Some clips want stereo and others want one channel of a stereo source. Right-click a row and use **Output Channels** to set that clip on its own: Stereo, Mono — Left, Mono — Right, or Follow Settings to go back to the panel.")
                    text("The setting applies to every selected row at once, so several clips from the same source can be marked in one go. A clip that overrides the panel shows a small badge beside its name; rows without one follow the settings panel as they always have.")
                    text("Only channel handling can be set per clip. Sample rate, ceiling, filters and loudness stay the same for the whole batch.")
                    text("Because Process runs the whole queue rather than the selection, this is what lets a mixed batch — some stereo, some mono-left — go through in one pass instead of two.")
                    definition("Why it matters", "With mono output, ClipHack takes the channel you name rather than downmixing. A clip whose content sits on the right would come out silent under a Left setting, and which channel carries the audio is a property of that recording — so it belongs on the clip, not the batch.")
                }
                section("Acknowledgments") {
                    text("ClipHack bundles two open-source command-line tools:")
                    definition("yt-dlp", "Media downloader, released into the public domain (Unlicense). Bundled as the official standalone binary; the pinned version is updated with ClipHack releases.")
                    Link("github.com/yt-dlp/yt-dlp", destination: URL(string: "https://github.com/yt-dlp/yt-dlp")!)
                    definition("FFmpeg", "Audio engine for the entire processing chain.")
                    Link("ffmpeg.org", destination: URL(string: "https://ffmpeg.org")!)
                }
                Spacer()
            }
            .padding(30)
        }
        .frame(width: 580, height: 720)
    }

    // MARK: - Components

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ClipHack Help")
                .font(.largeTitle.bold())
            Text("Clip Prep for macOS")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }

    /// Parses inline markdown in help copy.
    ///
    /// `Text` only parses markdown for string *literals*; a `String` parameter picks the
    /// `StringProtocol` overload, which renders `**bold**` verbatim. Inline-only parsing
    /// keeps prose intact — full markdown swallows a leading "- " or "1. " and collapses newlines.
    private func markdown(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options))
            ?? AttributedString(string)
    }

    private func text(_ string: String) -> some View {
        Text(markdown(string))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Deliberately not markdown-parsed — code samples render literally.
    private func code(_ string: String) -> some View {
        Text(string)
            .font(.system(.body, design: .monospaced))
            .padding(8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.body.bold())
                        .frame(width: 20, alignment: .trailing)
                    Text(markdown(item))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func numberedList(_ items: [String]) -> some View {
        steps(items)
    }

    private func definition(_ term: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(markdown(term))
                .font(.body.bold())
            Text(markdown(detail))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}

#Preview {
    HelpView()
}
