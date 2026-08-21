import Foundation

/// A single analyzable unit of Swift code: a function, a nested function, or a
/// property/subscript accessor with a body.
public struct MethodDescriptor: Equatable {
    /// Enclosing type path, e.g. `Greeter` or `Outer.Inner`. Empty for file-scope code.
    public let typeName: String
    /// Unit name, e.g. `greet(name:)`, `title{get}`, `subscript{set}`.
    public let methodName: String
    /// Absolute path of the file the unit was parsed from.
    public let filePath: String
    /// 1-based line of the declaration itself (what the report points at).
    public let declarationLine: Int
    /// 1-based line range of the body, used to attribute coverage records.
    public let bodyStartLine: Int
    public let bodyEndLine: Int
    /// Cyclomatic complexity, `>= 1`.
    public let complexity: Int

    public init(
        typeName: String,
        methodName: String,
        filePath: String,
        declarationLine: Int,
        bodyStartLine: Int,
        bodyEndLine: Int,
        complexity: Int
    ) {
        self.typeName = typeName
        self.methodName = methodName
        self.filePath = filePath
        self.declarationLine = declarationLine
        self.bodyStartLine = bodyStartLine
        self.bodyEndLine = bodyEndLine
        self.complexity = complexity
    }

    public var displayName: String {
        typeName.isEmpty ? methodName : "\(typeName).\(methodName)"
    }

    public var bodySpan: ClosedRange<Int> {
        bodyStartLine ... max(bodyStartLine, bodyEndLine)
    }
}

/// A report row: a unit plus its measured coverage and CRAP score.
public struct MethodMetrics: Equatable {
    public let descriptor: MethodDescriptor
    /// Covered fraction in `0.0 ... 1.0`, or `nil` when coverage was unavailable.
    public let coverage: Double?
    public let crap: CrapScore

    public init(descriptor: MethodDescriptor, coverage: Double?) {
        self.descriptor = descriptor
        self.coverage = coverage
        self.crap = CrapScore.compute(complexity: descriptor.complexity, coverage: coverage)
    }
}
