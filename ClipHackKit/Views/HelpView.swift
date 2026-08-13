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
                    text("A clip added back later — dropped, or picked up from a folder — arrives with the notes saved beside it, shown under its name in the list. Point at them to read the full text.")
                }
                section("Download from URL") {
                    text("Click the link button in the toolbar (⌘L), or drop a web link onto the window, to download a clip's audio into the file list. Video sources are saved as audio only (native codec, no re-encode) into your chosen download folder (~/Music/ClipHack by default).")
                    text("Each download gets its own folder, named after the file — Some Title/Some Title.m4a. Processed output lands in that folder too, so everything for one clip stays together. A repeated title gets its own folder (-2, -3, …) rather than overwriting the earlier one.")
                    definition("Custom file name", "Optional. Names the download — and its folder — before it lands; stem only, the extension always matches the source audio. Leave blank to keep the source title.")
                    definition("Notes", "Optional free text kept with the file row and written to the clip's notes file. Drag the grip in the box's bottom-right corner to make it taller; the size is remembered. For X/Twitter post links, the post's text is fetched and pre-filled here automatically (best-effort) — edit or clear it as you like.")
                    definition("Save clip notes", "Writes file name, notes, and source URL to a text file beside the audio in its folder — Some Title/Some Title.txt. It records the download as it happened: renaming the file afterwards does not rewrite it.")
                    definition("Destination", "Where clip folders are created. Defaults to ~/Music/ClipHack; use Change… to pick any folder — it's remembered for future downloads. If that folder is missing when you download, ClipHack asks for a new one.")
                    definition("Already downloaded", "Downloading a link you already used adds the clip you have instead of fetching a second copy. ClipHack checks the notes files in the destination, so this works days later in a new session too. Delete a clip's audio and the link downloads again as normal.")
                    text("Any row in the list — dropped or downloaded — can be renamed with right-click → Rename…, or by selecting it and pressing Return. The file is renamed on disk; the extension is kept.")
                }
                section("Output Naming") {
                    text("Output filenames reflect what processing was applied:")
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
                        "Brick-wall limiting with 2× oversampled true peak control."
                    ])
                    text("Output format: 24-bit WAV")
                }
                section("Settings") {
                    definition("Sample Rate", "Output sample rate — 44.1 kHz or 48 kHz.")
                    definition("Ceiling", "Brick-wall limiter ceiling, from -6 dB to -1 dB. Sets the maximum peak level of the output.")
                    definition("High Pass", "High-pass filter cutoff — three options. DC Block (20 Hz): removes DC offset only, passes all audible content including bass fundamentals. 40 Hz: removes subsonic rumble while preserving music bass. 80 Hz: standard voice HPF, removes proximity effect and handling noise.")
                    definition("Dynamic Leveling", "Enables bidirectional dynamic normalization (dynaudnorm). Lifts quiet voices and tames loud ones. Best for panel recordings, live Q&As, or multi-guest interviews where voices are at inconsistent levels — not for regular solo voice use. Aggressiveness controls how quickly and strongly the leveling responds.")
                    definition("Loudness Norm", "Enables two-pass EBU R128 loudness normalization. Runs before the limiter.")
                    definition("Target", "Loudness normalization target in LUFS, from -35 to -14. -18 LUFS is a common podcast insertion target.")
                    definition("Trash Originals", "On by default. Moves each source file to the Trash once its processed output is written — the output is checked on disk first, and a file that fails to process is always kept. Recover anything you want back from the Trash. Note that a downloaded clip whose audio has been trashed will download again if you reuse the same link.")
                    definition("Output Directory", "Custom output folder for processed files. Defaults to the same directory as the source file.")
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
