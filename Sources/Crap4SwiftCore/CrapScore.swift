import Foundation

/// Global tuning constants for the CRAP metric.
public enum Crap4Swift {
    /// The CRAP score above which the run is considered a failure.
    /// Matches the fixed threshold used by `crap4java`.
    public static let threshold: Double = 8.0
}

/// A CRAP score, which is unavailable when no coverage could be attributed.
public enum CrapScore: Equatable {
    case value(Double)
    case notAvailable

    /// The numeric score, or `nil` when coverage was unavailable.
    public var numericValue: Double? {
        switch self {
        case .value(let score): return score
        case .notAvailable: return nil
        }
    }

    /// `CRAP = CC^2 * (1 - coverage)^3 + CC`
    ///
    /// - Parameters:
    ///   - complexity: cyclomatic complexity, `>= 1`.
    ///   - coverage: covered fraction in `0.0 ... 1.0`, or `nil` when unknown.
    public static func compute(complexity: Int, coverage: Double?) -> CrapScore {
        guard let coverage else { return .notAvailable }
        let cc = Double(complexity)
        let covered = min(max(coverage, 0.0), 1.0)
        let uncovered = 1.0 - covered
        return .value(cc * cc * uncovered * uncovered * uncovered + cc)
    }
}
