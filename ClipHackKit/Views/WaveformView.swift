import SwiftUI

struct WaveformView: View {
    let waveformData: WaveformData?

    private let dbLevels: [Double] = [0, -1, -2, -3, -4, -5, -6, -12, -18, -24, -36, -48]

    var body: some View {
        Group {
            if let data = waveformData {
                if data.channelCount >= 2 {
                    stereoView(data: data)
                } else {
                    channelView(peaks: data.peaks, showScale: true)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Channel views

    /// Renders a single waveform channel with an optional dB scale on the left.
    /// In stereo mode the L channel shows the scale; R uses a clear spacer to stay aligned.
    private func channelView(peaks: [Float], label: String? = nil, showScale: Bool = false) -> some View {
        HStack(spacing: 4) {
            if showScale {
                dbScale.frame(width: 32)
            } else {
                Color.clear.frame(width: 32)
            }
            ZStack(alignment: .topLeading) {
                dbGridLines
                WaveformShape(peaks: peaks)
                    .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .padding(.top, 3)
                }
            }
        }
    }

    private func stereoView(data: WaveformData) -> some View {
        VStack(spacing: 1) {
            channelView(peaks: data.channelPeaks[0], label: "L", showScale: true)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
            channelView(peaks: data.channelPeaks[1], label: "R")
        }
    }

    // MARK: - Scale & grid

    /// dB labels positioned relative to the channel's own geometry, so they align
    /// with the grid lines drawn inside the same view.
    private var dbScale: some View {
        GeometryReader { geometry in
            let midY = geometry.size.height / 2
            let visible = visibleLabels(midY: midY)

            ZStack {
                ForEach(visible, id: \.db) { item in
                    Text(formatDb(item.db))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .position(x: 16, y: item.y)

                    if item.db == 0 {
                        Text(formatDb(item.db))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .position(x: 16, y: geometry.size.height - item.y)
                    }
                }
            }
        }
    }

    private func visibleLabels(midY: CGFloat) -> [(db: Double, y: CGFloat)] {
        let edge: CGFloat = 6
        let minGap: CGFloat = 12
        var result: [(db: Double, y: CGFloat)] = []
        for db in dbLevels {
            let amplitude = pow(10.0, db / 20.0)
            let y = max(edge, min((1 - amplitude) * midY, midY - edge))
            if let prev = result.last, y - prev.y < minGap { continue }
            result.append((db, y))
        }
        return result
    }

    private var dbGridLines: some View {
        GeometryReader { geometry in
            let midY = geometry.size.height / 2

            Path { path in
                path.move(to: CGPoint(x: 0, y: midY))
                path.addLine(to: CGPoint(x: geometry.size.width, y: midY))

                for db in dbLevels {
                    let amplitude = pow(10, db / 20)
                    let yOffset = (1 - amplitude) * midY

                    path.move(to: CGPoint(x: 0, y: yOffset))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: yOffset))

                    path.move(to: CGPoint(x: 0, y: geometry.size.height - yOffset))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - yOffset))
                }
            }
            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
        }
    }

    private func formatDb(_ db: Double) -> String {
        db == 0 ? "0" : String(format: "%.0f", db)
    }
}

struct WaveformShape: Shape {
    let peaks: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard !peaks.isEmpty else { return path }

        let sampleWidth = rect.width / CGFloat(peaks.count)
        let midY = rect.midY
        path.move(to: CGPoint(x: 0, y: midY))

        for (index, peak) in peaks.enumerated() {
            let x = CGFloat(index) * sampleWidth + sampleWidth / 2
            let height = CGFloat(peak) * rect.height / 2
            path.addLine(to: CGPoint(x: x, y: midY - height))
        }

        for (index, peak) in peaks.enumerated().reversed() {
            let x = CGFloat(index) * sampleWidth + sampleWidth / 2
            let height = CGFloat(peak) * rect.height / 2
            path.addLine(to: CGPoint(x: x, y: midY + height))
        }

        path.closeSubpath()
        return path
    }
}

#Preview {
    let peaks: [Float] = [0.8, 0.5, 0.9, 0.3, 0.7, 0.6, 0.4]
    WaveformView(waveformData: WaveformData(peaks: peaks, channelPeaks: [peaks, peaks], channelCount: 2))
        .frame(height: 100)
        .padding()
}
