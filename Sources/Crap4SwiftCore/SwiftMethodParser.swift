import Foundation
import SwiftParser
import SwiftSyntax

/// Parses Swift source into the units that get a CRAP score.
///
/// Reported units are declarations that have a body:
///
///   - functions and methods, including nested functions
///   - computed-property accessors (`get`, `set`, `willSet`, `didSet`)
///   - subscript accessors
///
/// Not reported: initializers and deinitializers (the analog of the constructor
/// exclusion in `crap4java`), protocol requirements and other bodyless
/// declarations (the analog of abstract methods), and closures (the analog of
/// anonymous-class methods). A closure's branches are folded into the unit that
/// contains it rather than being lost.
public struct SwiftMethodParser {
    public init() {}

    public func parse(source: String, filePath: String) -> [MethodDescriptor] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: tree)
        let collector = MethodCollector(filePath: filePath, converter: converter)
        collector.walk(tree)
        return collector.methods
    }

    public func parse(file path: String) throws -> [MethodDescriptor] {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw Crap4SwiftError.unreadableSource(path: path, reason: "\(error)")
        }
        return parse(source: String(decoding: data, as: UTF8.self), filePath: path)
    }
}

final class MethodCollector: SyntaxVisitor {
    private let filePath: String
    private let converter: SourceLocationConverter
    /// Enclosing declaration names, e.g. `["Greeter", "greet(name:)"]`.
    private var scope: [String] = []
    private(set) var methods: [MethodDescriptor] = []

    init(filePath: String, converter: SourceLocationConverter) {
        self.filePath = filePath
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Scope tracking

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_ node: ClassDeclSyntax) { pop() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_ node: StructDeclSyntax) { pop() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_ node: EnumDeclSyntax) { pop() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_ node: ActorDeclSyntax) { pop() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { push(node.name.text) }
    override func visitPost(_ node: ProtocolDeclSyntax) { pop() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.extendedType.trimmedDescription)
    }

    override func visitPost(_ node: ExtensionDeclSyntax) { pop() }

    // MARK: - Units

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = Self.functionName(node)
        if let body = node.body {
            record(name: name, declaration: node, braced: body.leftBrace, body.rightBrace, complexityRoot: body)
        }
        // Pushed even for bodyless declarations so `visitPost` stays balanced.
        return push(name)
    }

    override func visitPost(_ node: FunctionDeclSyntax) { pop() }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let accessorBlock = binding.accessorBlock else { continue }
            recordAccessors(of: accessorBlock, named: binding.pattern.trimmedDescription, declaration: node)
        }
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        if let accessorBlock = node.accessorBlock {
            recordAccessors(of: accessorBlock, named: "subscript", declaration: node)
        }
        return .visitChildren
    }

    // MARK: - Recording

    private func recordAccessors(
        of accessorBlock: AccessorBlockSyntax,
        named name: String,
        declaration: some SyntaxProtocol
    ) {
        switch accessorBlock.accessors {
        case .getter(let statements):
            // Shorthand form: `var title: String { "..." }`
            record(
                name: "\(name){get}",
                declaration: declaration,
                braced: accessorBlock.leftBrace, accessorBlock.rightBrace,
                complexityRoot: statements
            )
        case .accessors(let accessors):
            for accessor in accessors {
                guard let body = accessor.body else { continue }
                record(
                    name: "\(name){\(accessor.accessorSpecifier.text)}",
                    declaration: accessor,
                    braced: body.leftBrace, body.rightBrace,
                    complexityRoot: body
                )
            }
        }
    }

    private func record(
        name: String,
        declaration: some SyntaxProtocol,
        braced leftBrace: TokenSyntax,
        _ rightBrace: TokenSyntax,
        complexityRoot: some SyntaxProtocol
    ) {
        methods.append(
            MethodDescriptor(
                typeName: scope.joined(separator: "."),
                methodName: name,
                filePath: filePath,
                declarationLine: line(of: declaration.positionAfterSkippingLeadingTrivia),
                bodyStartLine: line(of: leftBrace.positionAfterSkippingLeadingTrivia),
                bodyEndLine: line(of: rightBrace.endPositionBeforeTrailingTrivia),
                complexity: ComplexityCounter.complexity(of: complexityRoot)
            )
        )
    }

    // MARK: - Helpers

    @discardableResult
    private func push(_ name: String) -> SyntaxVisitorContinueKind {
        scope.append(name)
        return .visitChildren
    }

    private func pop() {
        if !scope.isEmpty { scope.removeLast() }
    }

    private func line(of position: AbsolutePosition) -> Int {
        converter.location(for: position).line
    }

    /// `greet(name:)` — the argument labels disambiguate overloads.
    static func functionName(_ node: FunctionDeclSyntax) -> String {
        let labels = node.signature.parameterClause.parameters
            .map { "\($0.firstName.text):" }
            .joined()
        return "\(node.name.text)(\(labels))"
    }
}
