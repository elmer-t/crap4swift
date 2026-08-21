import Foundation

/// One llvm-cov function record, reduced to what CRAP needs.
public struct CoverageRecord: Equatable {
    public let startLine: Int
    public let endLine: Int
    public let coveredRegions: Int
    public let totalRegions: Int

    public init(startLine: Int, endLine: Int, coveredRegions: Int, totalRegions: Int) {
        self.startLine = startLine
        self.endLine = endLine
        self.coveredRegions = coveredRegions
        self.totalRegions = totalRegions
    }
}

/// Coverage for one SwiftPM package, indexed by source file.
///
/// Records are matched to methods by source position rather than by symbol
/// name: llvm-cov reports mangled Swift symbols, and matching mangled names
/// back to syntax is far more brittle than matching line spans.
public struct CoverageData: Equatable {
    public let recordsByFile: [String: [CoverageRecord]]

    public init(recordsByFile: [String: [CoverageRecord]]) {
        self.recordsByFile = recordsByFile
    }

    /// The state where no coverage export could be read; every method scores `N/A`.
    public static let unavailable = CoverageData(recordsByFile: [:])

    public var isAvailable: Bool { !recordsByFile.isEmpty }

    /// Covered fraction for a method body, or `nil` when nothing is attributable.
    ///
    /// Every record starting inside `span` belongs to the method — including the
    /// records emitted for its closures, matching how `ComplexityCounter` folds
    /// closure branches into the enclosing unit. Records starting inside a
    /// `nested` span belong to a separately reported unit and are excluded.
    public func coverage(
        forFile path: String,
        span: ClosedRange<Int>,
        excluding nested: [ClosedRange<Int>] = []
    ) -> Double? {
        guard let records = recordsByFile[Self.normalizeKey(path)] else { return nil }

        var covered = 0
        var total = 0
        for record in records where span.contains(record.startLine) {
            if nested.contains(where: { $0.contains(record.startLine) }) { continue }
            covered += record.coveredRegions
            total += record.totalRegions
        }
        guard total > 0 else { return nil }
        return Double(covered) / Double(total)
    }

    /// llvm-cov emits absolute paths that may run through symlinks (`/tmp` vs
    /// `/private/tmp` on macOS), so both sides are resolved before matching.
    public static func normalizeKey(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
