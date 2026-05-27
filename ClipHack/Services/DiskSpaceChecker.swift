import Foundation

enum DiskSpaceChecker {
    private static let tempHeadroomBytes: Int64 = 200 * 1024 * 1024
    private static let outputHeadroomBytes: Int64 = 100 * 1024 * 1024
    private static let tempMultiplier: Int64 = 5

    static func clipHackBatchBlockedReason(
        inputURLs: [URL],
        outputDirectories: [URL],
        concurrentJobs: Int
    ) -> String? {
        guard !inputURLs.isEmpty else { return nil }

        let sizes = inputURLs.compactMap { fileSize(at: $0) }
        guard !sizes.isEmpty else { return nil }

        let largestInput = sizes.max() ?? 0
        let workers = max(1, min(concurrentJobs, inputURLs.count))
        let tempRequired = largestInput * tempMultiplier * Int64(workers) + tempHeadroomBytes

        if let reason = insufficientSpaceReason(
            requiredBytes: tempRequired,
            at: FileManager.cliphackTempDirectory,
            context: "temporary processing files"
        ) {
            return reason
        }

        var requiredPerDirectory: [String: Int64] = [:]
        for (url, dir) in zip(inputURLs, outputDirectories) {
            let inputBytes = fileSize(at: url) ?? largestInput
            requiredPerDirectory[dir.path, default: outputHeadroomBytes] += inputBytes
        }

        for (path, required) in requiredPerDirectory {
            if let reason = insufficientSpaceReason(
                requiredBytes: required,
                at: URL(fileURLWithPath: path, isDirectory: true),
                context: "processed output files"
            ) {
                return reason
            }
        }

        return nil
    }

    private static func insufficientSpaceReason(
        requiredBytes: Int64,
        at directory: URL,
        context: String
    ) -> String? {
        guard let available = availableBytes(at: directory) else { return nil }
        guard available < requiredBytes else { return nil }

        let needMB = max(1, requiredBytes / (1024 * 1024))
        let haveMB = max(0, available / (1024 * 1024))
        return "Not enough disk space for \(context) on “\(directory.path)” (\(haveMB) MB free, about \(needMB) MB needed). Free space and try again."
    }

    private static func availableBytes(at url: URL) -> Int64? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard let values = try? directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ]),
        let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return capacity
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) else {
            return nil
        }
        if let allocated = values.totalFileAllocatedSize { return Int64(allocated) }
        if let size = values.fileSize { return Int64(size) }
        return nil
    }
}
