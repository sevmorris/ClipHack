import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                section("Overview") {
                    text("""
                    ClipHacker prepares audio clips for use in a mix — leveling dynamics, \
                    normalizing loudness, and brick-wall limiting peaks. It's designed for \
                    broadcast clips (news, promos) that need to sit at a consistent level \
                    before dropping into a podcast or show.
                    """)
                }
                section("Getting Started") {
                    steps([
                        "Set your sample rate, ceiling, and any processing options.",
                        "Drag and drop audio files onto the window.",
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
                    text("ClipHacker uses FFmpeg. Each stage is optional except the final limiter:")
                    numberedList([
                        "Resample to target sample rate (skipped if already matching).",
                        "Noise Reduction — RNNoise neural network model (arnndn). Removes broadband background noise. Applied per-channel on stereo files.",
                        "Level Audio — dynamic normalization via dynaudnorm. Evens out level variation across the clip. Designed for broadcast sources, not dialog.",
                        "Loudness Norm — two-pass EBU R128 loudness normalization to a target LUFS.",
                        "Brick-wall limiting with 2× oversampled true peak control."
                    ])
                    text("Output format: 24-bit WAV")
                }
                section("Settings") {
                    definition("Sample Rate", "Output sample rate — 44.1 kHz or 48 kHz.")
                    definition("Ceiling", "Brick-wall limiter ceiling, from -6 dB to -1 dB. Sets the maximum peak level of the output.")
                    definition("Noise Reduction", "Enables RNNoise neural network noise reduction (arnndn). Attenuates broadband background noise — hiss, room tone, HVAC. Applied before leveling.")
                    definition("Level Audio", "Enables dynamic leveling (dynaudnorm). Best for broadcast clips with varying levels. Not recommended for dialog or music.")
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
                    definition("Target", "Loudness normalization target in LUFS, from -30 to -14. -16 LUFS is a common podcast insertion target.")
                    definition("Output Directory", "Custom output folder for processed files. Defaults to the same directory as the source file.")
                }
                Spacer()
            }
            .padding(30)
        }
        .frame(width: 560, height: 720)
    }

    // MARK: - Components

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ClipHacker Help")
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
