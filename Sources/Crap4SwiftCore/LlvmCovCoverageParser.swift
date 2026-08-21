import Foundation

/// Reads the llvm-cov JSON export that SwiftPM writes after
/// `swift test --enable-code-coverage`.
///
/// This is the analog of the JaCoCo XML reader in `crap4java`. Region counters
/// are the closest thing llvm-cov offers to JaCoCo's INSTRUCTION counters: they
/// are finer-grained than lines and they distinguish partially executed lines.
public struct LlvmCovCoverageParser {
    public init() {}

    public func parse(jsonData: Data) throws -> CoverageData {
        let export = try JSONDecoder().decode(LlvmCovExport.self, from: jsonData)

        var recordsByFile: [String: [CoverageRecord]] = [:]
        for dataSet in export.data {
            for function in dataSet.functions ?? [] {
                guard let filename = function.filenames.first,
                      let record = Self.record(from: function.regions)
                else { continue }
                recordsByFile[CoverageData.normalizeKey(filename), default: []].append(record)
            }
        }
        for key in recordsByFile.keys {
            recordsByFile[key]?.sort { ($0.startLine, $0.endLine) < ($1.startLine, $1.endLine) }
        }
        return CoverageData(recordsByFile: recordsByFile)
    }

    public func parse(file path: String) throws -> CoverageData {
        try parse(jsonData: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    /// A region is `[lineStart, colStart, lineEnd, colEnd, executionCount, fileID, expandedFileID, kind]`.
    /// Only code regions (kind 0) are counted: expansion, skipped, gap and
    /// branch regions either double-count or describe unreachable text.
    static func record(from regions: [[Int]]) -> CoverageRecord? {
        var startLine = Int.max
        var endLine = Int.min
        var covered = 0
        var total = 0

        for region in regions {
            guard region.count >= 5 else { continue }
            let kind = region.count >= 8 ? region[7] : 0
            guard kind == 0 else { continue }
            startLine = min(startLine, region[0])
            endLine = max(endLine, region[2])
            total += 1
            if region[4] > 0 { covered += 1 }
        }

        guard total > 0, startLine != Int.max else { return nil }
        return CoverageRecord(
            startLine: startLine,
            endLine: endLine,
            coveredRegions: covered,
            totalRegions: total
        )
    }
}

// MARK: - Export schema (llvm.coverage.json.export v2)

struct LlvmCovExport: Decodable {
    let data: [LlvmCovDataSet]
}

struct LlvmCovDataSet: Decodable {
    let functions: [LlvmCovFunction]?
}

struct LlvmCovFunction: Decodable {
    let name: String
    let filenames: [String]
    let regions: [[Int]]
}
