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
        metrics.sorted { sortKey(of: $0) < sortKey(of: $1) }
    }

    /// The whole ordering expressed as one comparable key: unscored rows sink,
    /// worse scores rise, and the remaining ties break deterministically.
    /// Negation turns "descending" into "ascending" without a second comparator.
    static func sortKey(of metric: MethodMetrics) -> (Int, Double, Int, String, String, Int) {
        let score = metric.crap.numericValue
        return (
            score == nil ? 1 : 0,
            -(score ?? 0),
            -metric.descriptor.complexity,
            metric.descriptor.displayName,
            metric.descriptor.filePath,
            metric.descriptor.declarationLine
        )
    }

    /// The worst numeric score, or `0` when nothing could be scored.
    public static func maximumCrap(_ metrics: [MethodMetrics]) -> Double {
        metrics.compactMap { $0.crap.numericValue }.max() ?? 0.0
    }
}
