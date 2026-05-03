import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                section("Overview") {
                    text("""
                    ClipHack prepares audio clips for use in a mix — leveling dynamics, \
                    normalizing loudness, and brick-wall limiting peaks. It's designed for \
                    broadcast clips (news, promos) that need to sit at a consistent level \
                    before dropping into a podcast or show.
                    """)
                }
                section("Presets") {
                    text("Presets save and recall all settings at once. Three built-in presets are included:")
                    VStack(alignment: .leading, spacing: 8) {
                        definition("Broadcast Conform", "Broadcast clips (news, ads) played live into a Zoom call via Farrago/Loopback. Leveling on low to tame wildly dynamic sources without pumping. Loudness normalized to -18 LUFS.")
                        definition("Clean & Limit", "Minimal processing — high-pass at DC block + limiter only. Good for already well-produced sources that just need a safety ceiling.")
                        definition("Normalize & Limit", "High-pass + EBU R128 loudness normalization + limiter. No leveling. Good for sources with consistent dynamics that just need a loudness target.")
                    }
                    text("To save your own preset, open the preset menu and choose **Save Current Settings…**. To delete a custom preset, choose **Delete Preset** from the same menu. Built-in presets cannot be deleted.")
                }
                section("Getting Started") {
                    steps([
                        "Set your sample rate, ceiling, and any processing options.",
                        "Drag and drop audio or video files onto the window.",
                        "Click Process.",
                        "Output files are saved alongside the originals (or to your chosen output folder)."
                    ])
                }
                section("Output Naming") {
                    text("Output filenames reflect what processing was applied:")
                    code("{original-name}-{rate}{leveled-}{norm-}clipped-{limit}dB.wav")
                    VStack(alignment: .leading, spacing: 4) {
                        text("Examples:")
                        code("clip-44kclipped-1dB.wav")
                        code("clip-44kleveled-norm-clipped-1dB.wav")
                    }
                }
                section("Processing Pipeline") {
                    text("ClipHack uses FFmpeg. Each stage is optional except high-pass, phase rotation, and the final limiter:")
                    numberedList([
                        "Resample to target sample rate (skipped if already matching).",
                        "Channel extraction — pan stereo to mono (left or right channel).",
                        "High-pass filter + phase rotation — removes low-frequency rumble and DC offset; allpass filter corrects phase shift. Always applied.",
                        "Level Audio — dynamic normalization via dynaudnorm. Evens out level variation across the clip.",
                        "Loudness Norm — two-pass EBU R128 loudness normalization to a target LUFS.",
                        "Brick-wall limiting with 2× oversampled true peak control."
                    ])
                    text("Output format: 24-bit WAV")
                }
                section("Settings") {
                    definition("Sample Rate", "Output sample rate — 44.1 kHz or 48 kHz.")
definition("Ceiling", "Brick-wall limiter ceiling, from -6 dB to -1 dB. Sets the maximum peak level of the output.")
                    definition("High Pass", "High-pass filter cutoff frequency (20–90 Hz). At 20 Hz it acts as a DC blocker only. Higher values (60–90 Hz) remove low-frequency rumble. Always applied — drag to 20 Hz to minimize effect.")
                    definition("Level Audio", "Enables dynamic leveling (dynaudnorm). Best for wildly dynamic sources. Not recommended for already-compressed broadcast content.")
                    definitionView("Aggressiveness") {
                        Text("Controls how responsive the leveler is. Three parameters scale together:")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            GridRow {
                                Text("Level").font(.caption.bold())
                                Text("Frame (f)").font(.caption.bold())
                                Text("Gaussian (g)").font(.caption.bold())
                                Text("Max Gain (m)").font(.caption.bold())
                            }
                            .foregroundStyle(.secondary)
                            Divider().gridCellColumns(4)
                            ForEach([
                                ("Gentle",     "750 ms", "31", "8×"),
                                ("Low",        "600 ms", "25", "11×"),
                                ("Medium",     "450 ms", "19", "14×"),
                                ("High",       "300 ms", "13", "17×"),
                                ("Aggressive", "150 ms", "7",  "20×"),
                            ], id: \.0) { row in
                                GridRow {
                                    Text(row.0).font(.caption)
                                    Text(row.1).font(.system(.caption, design: .monospaced))
                                    Text(row.2).font(.system(.caption, design: .monospaced))
                                    Text(row.3).font(.system(.caption, design: .monospaced))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text("Three parameters are always fixed: **RMS-based** measurement (responds to perceived loudness, not transient peaks), **channel-coupled** (L and R get the same gain, preserving the stereo image), and **boundary extension** (gain holds steady at the start and end of the file rather than tapering to zero).")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    definition("Loudness Norm", "Enables two-pass EBU R128 loudness normalization. Runs before the limiter.")
                    definition("Target", "Loudness normalization target in LUFS, from -35 to -14. -18 LUFS is a common podcast insertion target.")
                    definition("Output Directory", "Custom output folder for processed files. Defaults to the same directory as the source file.")
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

    private func text(_ string: String) -> some View {
        Text(string)
            .fixedSize(horizontal: false, vertical: true)
    }

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
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func numberedList(_ items: [String]) -> some View {
        steps(items)
    }

    private func definitionView(_ term: String, @ViewBuilder detail: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(term).font(.body.bold())
            detail()
        }
        .padding(.bottom, 4)
    }

    private func definition(_ term: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term)
                .font(.body.bold())
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}

#Preview {
    HelpView()
}
