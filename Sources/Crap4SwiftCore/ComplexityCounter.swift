import SwiftSyntax

/// Counts cyclomatic complexity over a syntax tree.
///
/// `CC = 1 + decisions`, where a decision is:
///
///   - an `if` (an `else if` is a nested `if`, so it counts; a bare `else` does not)
///   - a `guard`
///   - a `for`, `while` or `repeat`
///   - each `case` item of a `switch` (`default` is not a decision)
///   - each `catch` clause
///   - a ternary `?:`
///   - each short-circuiting `&&`, `||` and `??`
///
/// Optional chaining (`a?.b`) and `try?` are deliberately not counted: they are
/// pervasive in idiomatic Swift and counting them drowns out real branching.
///
/// The walk descends into closures — their branches are part of the work the
/// enclosing unit has to be tested for — but stops at anything reported as its
/// own unit (nested functions, initializers, accessors, local types), so no
/// decision is counted twice.
public final class ComplexityCounter: SyntaxVisitor {
    private var decisions = 0

    public static func complexity(of node: some SyntaxProtocol) -> Int {
        let counter = ComplexityCounter(viewMode: .sourceAccurate)
        counter.walk(node)
        return counter.decisions + 1
    }

    // MARK: - Boundaries of separately reported units

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    // MARK: - Decisions

    override public func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        decisions += 1
        return .visitChildren
    }

    override public func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        decisions += 1
        return .visitChildren
    }

    override public func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        decisions += 1
        return .visitChildren
    }

    override public func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        decisions += 1
        return .visitChildren
    }

    override public func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        decisions += 1
        return .visitChildren
    }

    override public func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        decisions += 1
        return .visitChildren
    }

    override public func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        if let label = node.label.as(SwitchCaseLabelSyntax.self) {
            // `case .a, .b:` is two ways to reach the same body, so it is two
            // decisions. `default:` is the fall-through, not a decision.
            decisions += max(1, label.caseItems.count)
        }
        return .visitChildren
    }

    /// Operators are counted at token level. `Parser.parse` does not fold
    /// operator sequences, so `a && b` is a flat `SequenceExprSyntax` and there
    /// is no folded `TernaryExprSyntax`/`BinaryOperatorExprSyntax` tree to match
    /// against; the tokens themselves are the stable signal.
    override public func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        switch token.tokenKind {
        case .binaryOperator(let text) where text == "&&" || text == "||" || text == "??":
            decisions += 1
        case .infixQuestionMark:
            // The `?` of a ternary. Optional chaining and `try?` lex as
            // `postfixQuestionMark`, so they are not caught here.
            decisions += 1
        default:
            break
        }
        return .skipChildren
    }
}
