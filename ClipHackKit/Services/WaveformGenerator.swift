import Foundation
import AVFoundation
import Accelerate

struct WaveformData: Sendable, Equatable {
    let peaks: [Float]           // Mixed-down peak values per bucket
    let channelPeaks: [[Float]]  // Per-channel peak values; index 0 = L, 1 = R
    let channelCount: Int        // Number of channels in source audio
}

enum WaveformGenerator {
    static func generate(url: URL, targetSamples: Int = 500) async throws -> WaveformData {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try processAudio(url: url, targetSamples: targetSamples)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func processAudio(url: URL, targetSamples: Int) throws -> WaveformData {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProcessingError.analysisError("File does not exist")
        }

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = Int(file.length)

        guard totalFrames > 0 else {
            throw ProcessingError.analysisError("Audio file is empty")
        }

        let channels = Int(format.channelCount)
        let samplesPerBucket = max(1, totalFrames / targetSamples)
        let actualBuckets = (totalFrames + samplesPerBucket - 1) / samplesPerBucket

        var bucketPeaks = [Float](repeating: 0, count: actualBuckets)
        var channelBucketPeaks = [[Float]](repeating: [Float](repeating: 0, count: actualBuckets), count: channels)

        let chunkSize: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw ProcessingError.analysisError("Could not create audio buffer")
        }

        file.framePosition = 0
        var globalFrame = 0

        while file.framePosition < file.length {
            do {
                try file.read(into: buffer)
            } catch {
                if globalFrame > 0 { break }
                throw ProcessingError.analysisError("Error reading audio: \(error.localizedDescription)")
            }

            if buffer.frameLength == 0 { break }

            guard let channelData = buffer.floatChannelData else {
                throw ProcessingError.analysisError("Could not access channel data")
            }

            // Walk the chunk one bucket-sized run at a time and take each run's
            // peak with vDSP_maxmgv (max |x|, NEON-vectorized) instead of a
            // per-sample loop. A max is exact, so the result is identical.
            let frames = Int(buffer.frameLength)
            var offset = 0
            while offset < frames {
                let bucketIndex = (globalFrame + offset) / samplesPerBucket
                guard bucketIndex < actualBuckets else { break }
                let runEnd = min(frames, (bucketIndex + 1) * samplesPerBucket - globalFrame)
                let runLength = runEnd - offset

                for channel in 0..<channels {
                    var runPeak: Float = 0
                    vDSP_maxmgv(channelData[channel] + offset, 1, &runPeak, vDSP_Length(runLength))
                    channelBucketPeaks[channel][bucketIndex] = max(channelBucketPeaks[channel][bucketIndex], runPeak)
                }
                offset = runEnd
            }

            globalFrame += frames
        }

        // The mixed-down peak of a bucket is the loudest channel's peak.
        for channel in 0..<channels {
            for bucketIndex in 0..<actualBuckets {
                bucketPeaks[bucketIndex] = max(bucketPeaks[bucketIndex], channelBucketPeaks[channel][bucketIndex])
            }
        }

        return WaveformData(peaks: bucketPeaks, channelPeaks: channelBucketPeaks, channelCount: channels)
    }
}
