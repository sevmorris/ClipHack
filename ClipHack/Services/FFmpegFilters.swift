import Foundation

/// Shared FFmpeg `filter` fragments for ClipHack processing chains.
enum FFmpegFilters {

    /// Resample to `rate` Hz. Uses SWResample with a large filter — the bundled static
    /// FFmpeg build does not include the SoXR engine (`resampler=soxr` fails at runtime).
    nonisolated static func aresample(to rate: Int) -> String {
        "aresample=\(rate):filter_size=512:cutoff=0.97:phase_shift=10"
    }

    /// Final export resample with triangular high-pass dither when encoding 24-bit PCM.
    nonisolated static func aresampleWithDither(to rate: Int) -> String {
        "aresample=\(rate):filter_size=512:cutoff=0.97:phase_shift=10:dither_method=triangular_hp"
    }

    /// Linear amplitude for `alimiter=limit=N` from a dBFS ceiling.
    nonisolated static func limiterCeilingAmplitude(dBFS: Double) -> String {
        String(format: "%.6f", pow(10.0, dBFS / 20.0))
    }
}
