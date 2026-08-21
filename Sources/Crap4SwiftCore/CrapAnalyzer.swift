import Foundation

/// Turns source files plus coverage into scored report rows.
public struct CrapAnalyzer {
    private let parser: SwiftMethodParser

    public init(parser: SwiftMethodParser = SwiftMethodParser()) {
        self.parser = parser
    }

    public func analyze(files: [String], coverage: CoverageData) throws -> [MethodMetrics] {
        var metrics: [MethodMetrics] = []
        for file in files {
            let descriptors = try parser.parse(file: file)
            for descriptor in descriptors {
                let attributed = coverage.coverage(
                    forFile: descriptor.filePath,
                    span: descriptor.bodySpan,
                    excluding: Self.nestedSpans(of: descriptor, among: descriptors)
                )
                metrics.append(MethodMetrics(descriptor: descriptor, coverage: attributed))
            }
        }
        return Self.sorted(metrics)
    }

    /// Spans of units nested inside `descriptor`, whose coverage records belong
    /// to them rather than to their container.
    static func nestedSpans(of descriptor: MethodDescriptor, among all: [MethodDescriptor]) -> [ClosedRange<Int>] {
        let span = descriptor.bodySpan
        return all.compactMap { other in
            let otherSpan = other.bodySpan
            guard otherSpan != span,
                  otherSpan.lowerBound >= span.lowerBound,
                  otherSpan.upperBound <= span.upperBound
            else { return nil }
            return otherSpan
        }
    }

    /// Worst first. Rows without coverage sort last, since an unknown score is
    /// not evidence of a problem — it is evidence of a gap in the measurement.
    public static func sorted(_ metrics: [MethodMetrics]) -> [MethodMetrics] {
        metrics.sorted { left, right in
            let leftScore = left.crap.numericValue
            let rightScore = right.crap.numericValue
            if let leftScore, let rightScore {
                if leftScore != rightScore { return leftScore > rightScore }
            } else if leftScore != nil {
                return true
            } else if rightScore != nil {
                return false
            }
            if left.descriptor.complexity != right.descriptor.complexity {
                return left.descriptor.complexity > right.descriptor.complexity
            }
            if left.descriptor.displayName != right.descriptor.displayName {
                return left.descriptor.displayName < right.descriptor.displayName
            }
            if left.descriptor.filePath != right.descriptor.filePath {
                return left.descriptor.filePath < right.descriptor.filePath
            }
            return left.descriptor.declarationLine < right.descriptor.declarationLine
        }
    }

    /// The worst numeric score, or `0` when nothing could be scored.
    public static func maximumCrap(_ metrics: [MethodMetrics]) -> Double {
        metrics.compactMap { $0.crap.numericValue }.max() ?? 0.0
    }
}
