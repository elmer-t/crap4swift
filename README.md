# crap4swift

A CRAP metric analyzer for Swift packages — a port of Uncle Bob's
[`crap4java`](https://github.com/unclebob/crap4java) to SwiftPM, SwiftSyntax and
llvm-cov.

```
CRAP = CC^2 * (1 - coverage)^3 + CC
```

**C**hange **R**isk **A**nti-**P**atterns. The idea it encodes: complexity is
only dangerous when it is untested. A gnarly method with thorough tests is
something you can change; a gnarly method with no tests is something you can
only pray over. The cubed uncovered fraction means coverage buys forgiveness
fast, and the squared complexity means nothing buys you out of a monster.

## What the numbers do

The threshold is `8.0`. That single number says two things at once:

| Complexity | Coverage needed to pass |
| ---------: | ----------------------- |
|        1–2 | none                    |
|          3 | 17.8%                   |
|          4 | 37.0%                   |
|          5 | 50.7%                   |
|          6 | 61.8%                   |
|          7 | 72.7%                   |
|          8 | 100%                    |
|        9+  | **impossible**          |

A method with nine decision points scores at least 9 no matter how perfectly it
is tested. That is not a bug in the formula, it is the point: past a certain
size, the fix is to split the method, not to write more tests for it.

## Usage

```sh
swift build -c release
.build/release/crap4swift            # every .swift file under Sources/
.build/release/crap4swift --changed  # only what git says you touched
.build/release/crap4swift Sources/MyLib/Parser.swift
.build/release/crap4swift Packages/Networking
.build/release/crap4swift --help
```

Or during development: `swift run crap4swift --changed`.

For each SwiftPM package owning a selected file, crap4swift deletes stale
coverage artifacts, runs `swift test --enable-code-coverage`, reads the llvm-cov
JSON export SwiftPM produces, and scores every method in the selection.

Exit codes: `0` clean, `1` usage or execution error, `2` threshold exceeded —
so it drops straight into CI as a gate.

There is a runnable example in `Examples/SampleProject`: one tested function and
one untested branchy one.

```sh
$ swift run crap4swift Examples/SampleProject
  CRAP  CC  COVERAGE  METHOD                            LOCATION
------  --  --------  --------------------------------  ------------------------------------------------------
110.00  10     0.00%  Fizz.summarize(_:verbose:limit:)  Examples/SampleProject/Sources/SampleLib/Fizz.swift:11
  2.00   2   100.00%  Fizz.label(_:)                    Examples/SampleProject/Sources/SampleLib/Fizz.swift:3

2 methods analyzed, 1 over the threshold of 8.00, worst 110.00 in Fizz.summarize(_:verbose:limit:).
CRAP threshold exceeded: 110.00 > 8.00
```

The tool scores itself too — `swift run crap4swift` — which is the honest way to
find out whether a quality gate is worth keeping. It passes its own: 102
methods, none over 8.0.

## How complexity is counted

`CC = 1 + decisions`, counted from the SwiftSyntax tree — never from regexes.

Counted: `if` (an `else if` is a nested `if`, so it counts; a bare `else` does
not), `guard`, `for`, `while`, `repeat`, each `case` item of a `switch`
(`default` is not a decision), each `catch`, the ternary `?:`, and each
short-circuiting `&&`, `||` and `??`.

Not counted: optional chaining `?.` and `try?`. They are everywhere in idiomatic
Swift and counting them buries the real branching under noise.

Scored units are declarations with a body: functions and methods including
nested ones, computed-property accessors (`get`, `set`, `willSet`, `didSet`),
and subscript accessors. Initializers and deinitializers are skipped, mirroring
the constructor exclusion in `crap4java`; so are protocol requirements and
anything else without a body.

Closures are not scored on their own, but their branches — and their coverage —
fold into the method that contains them, so a method that hides its logic in a
trailing closure cannot hide from the score.

## How coverage is attributed

llvm-cov reports mangled Swift symbols, so methods are matched to coverage
records by **source position**, not by name: every record starting inside a
method's body belongs to it, except records inside a nested unit that is scored
separately.

Coverage is the fraction of llvm-cov *code regions* that executed, which is the
closest available analog to the JaCoCo INSTRUCTION counters `crap4java` uses.
Expansion, skipped, gap and branch regions are ignored.

When no coverage can be attributed, the method reports `N/A` and sorts to the
bottom — an unknown score is a gap in the measurement, not evidence of a
problem.

## Layout

```
Sources/crap4swift/            CLI entry point
Sources/Crap4SwiftCore/
  CliApplication.swift         orchestration and the exit-code contract
  CliArgumentsParser.swift     the four supported invocations
  SourceFileFinder.swift       Sources/** discovery and path expansion
  ChangedFileDetector.swift    git status --porcelain
  PackageRootFinder.swift      nearest Package.swift, the module analog
  CoverageRunner.swift         clean, run tests, locate the export
  LlvmCovCoverageParser.swift  llvm.coverage.json.export reader
  CoverageData.swift           positional coverage attribution
  SwiftMethodParser.swift      SwiftSyntax walk that finds scorable units
  ComplexityCounter.swift      cyclomatic complexity
  CrapAnalyzer.swift           complexity + coverage -> sorted rows
  ReportFormatter.swift        the table
  CrapScore.swift              the formula and the threshold
Tests/Crap4SwiftCoreTests/     unit tests for all of the above
Examples/SampleProject/        a package with one good and one crappy function
```

`spec.md` is the full specification, written against `crap4java`'s and marking
every deliberate deviation.

## Requirements

Swift 5.9 or newer, on macOS or Linux. The only dependency is
[swift-syntax](https://github.com/swiftlang/swift-syntax), accepted in the
`600.0.0 ..< 603.0.0` range and pinned by `Package.resolved`. Built and tested
against Swift 6.0 with swift-syntax 602.0.0.

Xcode projects and `.xcresult` bundles are out of scope; the tool speaks SwiftPM.
