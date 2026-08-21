import Foundation

/// Renders scored methods as a fixed-width table, worst first.
public struct ReportFormatter {
    private let threshold: Double

    public init(threshold: Double = Crap4Swift.threshold) {
        self.threshold = threshold
    }

    public func format(_ metrics: [MethodMetrics], relativeTo projectRoot: String) -> String {
        guard !metrics.isEmpty else { return "No methods to score." }

        let rows = metrics.map { metric -> [String] in
            [
                Self.crapText(metric.crap),
                "\(metric.descriptor.complexity)",
                Self.coverageText(metric.coverage),
                metric.descriptor.displayName,
                location(of: metric.descriptor, relativeTo: projectRoot),
            ]
        }
        let header = ["CRAP", "CC", "COVERAGE", "METHOD", "LOCATION"]
        let widths = Self.columnWidths(header: header, rows: rows)
        // Numbers read best right-aligned, names left-aligned.
        let alignments: [Alignment] = [.right, .right, .right, .left, .left]

        var lines: [String] = []
        lines.append(Self.line(header, widths: widths, alignments: alignments))
        lines.append(Self.line(widths.map { String(repeating: "-", count: $0) }, widths: widths, alignments: alignments))
        for row in rows {
            lines.append(Self.line(row, widths: widths, alignments: alignments))
        }
        lines.append("")
        lines.append(summary(metrics))
        return lines.joined(separator: "\n")
    }

    func summary(_ metrics: [MethodMetrics]) -> String {
        let scored = metrics.filter { $0.crap.numericValue != nil }
        let unscored = metrics.count - scored.count
        let over = scored.filter { ($0.crap.numericValue ?? 0) > threshold }.count

        var parts = ["\(metrics.count) method\(metrics.count == 1 ? "" : "s") analyzed"]
        if unscored > 0 { parts.append("\(unscored) without coverage") }
        parts.append("\(over) over the threshold of \(Self.number(threshold))")
        if let worst = scored.first {
            parts.append("worst \(Self.number(worst.crap.numericValue ?? 0)) in \(worst.descriptor.displayName)")
        }
        return parts.joined(separator: ", ") + "."
    }

    func location(of descriptor: MethodDescriptor, relativeTo projectRoot: String) -> String {
        let path = SourceFileFinder.displayPath(descriptor.filePath, relativeTo: projectRoot)
        return "\(path):\(descriptor.declarationLine)"
    }

    // MARK: - Cells

    static func crapText(_ score: CrapScore) -> String {
        guard let value = score.numericValue else { return "N/A" }
        return number(value)
    }

    static func coverageText(_ coverage: Double?) -> String {
        guard let coverage else { return "N/A" }
        return String(format: "%.2f%%", coverage * 100)
    }

    static func number(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - Layout

    enum Alignment {
        case left
        case right
    }

    static func columnWidths(header: [String], rows: [[String]]) -> [Int] {
        var widths = header.map { $0.count }
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }
        return widths
    }

    static func line(_ cells: [String], widths: [Int], alignments: [Alignment]) -> String {
        var padded: [String] = []
        for (index, cell) in cells.enumerated() {
            let width = index < widths.count ? widths[index] : cell.count
            let alignment = index < alignments.count ? alignments[index] : .left
            padded.append(pad(cell, to: width, alignment: alignment))
        }
        // The last column never needs trailing padding.
        return padded.enumerated()
            .map { $0.offset == padded.count - 1 ? $0.element.trimmingTrailingSpaces() : $0.element }
            .joined(separator: "  ")
    }

    static func pad(_ text: String, to width: Int, alignment: Alignment) -> String {
        guard text.count < width else { return text }
        let padding = String(repeating: " ", count: width - text.count)
        return alignment == .right ? padding + text : text + padding
    }
}

extension String {
    func trimmingTrailingSpaces() -> String {
        var result = self
        while result.hasSuffix(" ") { result.removeLast() }
        return result
    }
}
