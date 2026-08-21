# crap4swift Specification

## 1. Purpose

`crap4swift` is a CRAP metric analyzer for Swift packages. It is a port of
[`crap4java`](https://github.com/unclebob/crap4java) to the Swift/SwiftPM
toolchain, and follows the same contract wherever the languages allow.

It shall:

- locate Swift source files to analyze
- generate coverage for the owning SwiftPM package of each analyzed file set
- parse Swift declarations and compute cyclomatic complexity
- combine complexity and coverage into CRAP scores
- print a tabular report sorted by worst score first
- fail when the maximum CRAP score exceeds the configured threshold

`crap4swift` is intended as a project-quality gate rather than a mutation tool.

## 2. Scope

This specification defines the command-line contract, source file selection
rules, coverage generation behavior, declaration parsing behavior, CRAP score
computation, report ordering and exit codes.

It does not define non-SwiftPM execution (Xcode projects, `.xcresult` bundles),
support for non-Swift source files, a machine-readable report format, or
configurable thresholds through the CLI.

## 3. Terminology

- `project root`
  The working root from which `crap4swift` is invoked.

- `package root`
  The nearest ancestor directory of an analyzed file that contains
  `Package.swift`. If none exists below the project root, the project root is
  the package root.

- `unit`
  A single report row: a declaration with a body, plus its cyclomatic
  complexity, coverage and CRAP score.

- `coverage N/A`
  The state where no coverage could be attributed to a unit, and therefore no
  CRAP score could be computed.

## 4. Command-Line Interface

### 4.1 Supported Forms

- `crap4swift`
- `crap4swift --changed`
- `crap4swift <path...>`
- `crap4swift --help`

### 4.2 Mode Semantics

- no arguments
  Analyze all Swift source files under `Sources/`.

- `--changed`
  Analyze changed Swift source files under `Sources/`.

- `<path...>`
  For each explicit path:
  - if it is a file, analyze that file
  - if it is a directory, analyze all Swift files under that directory's
    `Sources/` subtree

- `--help`, `-h`
  Print usage text and exit successfully. `--help` takes precedence over any
  other argument.

### 4.3 Invalid Usage

The tool shall exit with usage error when argument parsing fails, and shall
print usage text on CLI usage failure. Unknown options and the combination of
`--changed` with explicit paths are usage failures.

## 5. File Selection Rules

### 5.1 Default Source Discovery

In default mode, the tool shall analyze all `.swift` files under
`<project-root>/Sources/**`.

`Sources` is the SwiftPM analog of Maven's `src`. Unlike `src`, it does not
contain test code: `Tests/` is never scanned, because test code is the
measuring stick rather than the thing measured.

### 5.2 Changed-File Discovery

In `--changed` mode, the tool shall:

- invoke `git status --porcelain`
- interpret modified, added, renamed and untracked Swift files, resolving a
  rename to its new path
- discard deletions, since a deleted file has nothing to parse
- retain only `.swift` files that exist under `<project-root>/Sources/`
- sort the resulting file list in path order

### 5.3 Explicit Paths

When explicit paths are supplied:

- file paths shall be analyzed directly
- directory paths shall be expanded to `.swift` files under `<dir>/Sources/**`
- duplicates shall be removed
- the final list shall be sorted in path order

### 5.4 Empty Selection

If no Swift files are selected after expansion and filtering, the tool shall
print `No Swift files to analyze.` and exit successfully.

## 6. Package Grouping

The tool shall group selected files by package root before coverage generation,
determining the package root for a file by walking upward from the file's
directory until a `Package.swift` file is found or the walk leaves the project
root. If no nearer manifest is found, the project root shall be used.

Coverage generation and coverage-export lookup shall occur once per package
group.

## 7. Coverage Pipeline

For each package group, the tool shall:

1. delete stale coverage artifacts
2. run the package's tests with coverage instrumentation
3. read the resulting coverage export
4. analyze the selected Swift files in that package

### 7.1 Stale Artifact Cleanup

Before coverage generation, the tool shall delete every `codecov` directory
within `<package-root>/.build`, so that a run can never report scores derived
from a previous build. Symbolic links shall not be followed while searching.

### 7.2 Coverage Command

Coverage generation shall invoke `swift test --enable-code-coverage` with the
package root as the working directory.

### 7.3 Locating the Export

The tool shall locate the llvm-cov JSON export by asking SwiftPM
(`swift test --show-codecov-path`), and shall fall back to searching
`<package-root>/.build` for a `codecov/*.json` file when that query fails or
names a file that does not exist.

### 7.4 Missing Coverage Export

If no export can be located or parsed, the tool shall print a warning to stderr
and coverage for units in that package shall be reported as `N/A`.

## 8. Swift Declaration Parsing

The tool shall parse Swift source using SwiftSyntax, the Swift analog of the
JDK compiler tree APIs used by `crap4java`. Parsing shall not require type
checking, module resolution or a build.

Parsing is error-tolerant: a file that does not compile yields whatever
declarations could be recovered rather than failing the run.

### 8.1 Reported Units

The parser shall report declarations that have a body:

- functions and methods, at any nesting depth, including nested functions
- computed-property accessors (`get`, `set`, `willSet`, `didSet`)
- subscript accessors

A unit shall be identified by its enclosing declaration path and its name with
argument labels, e.g. `Greeter.greet(name:)`, `Box.value{set}`.

### 8.2 Exclusions

The parser shall ignore:

- initializers and deinitializers (the analog of the constructor exclusion)
- declarations without a body, such as protocol requirements (the analog of the
  abstract method exclusion)
- closures as units of their own (the analog of the anonymous-class exclusion)

### 8.3 Complexity Counting

Cyclomatic complexity shall be computed from syntax structure rather than
regular expressions, as `CC = 1 + decisions`, where each of the following is one
decision:

- an `if` — an `else if` is a nested `if` and therefore counts; a bare `else`
  does not
- a `guard`
- a `for`, `while` or `repeat`
- each `case` item of a `switch`; `default` is not a decision
- each `catch` clause
- a ternary `?:`
- each short-circuiting `&&`, `||` or `??`

Optional chaining (`?.`) and `try?` shall not be counted: they are pervasive in
idiomatic Swift and counting them would drown out real branching.

The count shall descend into closures, folding their decisions into the
enclosing unit, and shall stop at any declaration reported as its own unit, so
that no decision is counted twice.

The resulting complexity shall be an integer `CC >= 1`.

## 9. Coverage Attribution

Coverage shall be attributed to units by source position rather than by symbol
name, because llvm-cov reports mangled Swift symbols.

For a unit, the tool shall aggregate every coverage record whose start line
falls within the unit's body, excluding records that fall within the body of a
nested unit. This mirrors the complexity rule: a closure's regions count toward
the unit containing it, a nested function's do not.

Coverage shall be derived from llvm-cov code regions (kind 0), the closest
available analog of JaCoCo `INSTRUCTION` counters. Expansion, skipped, gap and
branch regions shall be ignored. Coverage is
`covered code regions / total code regions`.

If no usable coverage data is available for a unit, coverage shall be reported
as `N/A` and the CRAP score shall be reported as `N/A`.

## 10. CRAP Formula

For units with known coverage, CRAP shall be computed as:

`CRAP = CC^2 * (1 - coverage)^3 + CC`

Where `CC` is cyclomatic complexity and `coverage` is the unit's coverage
fraction in the range `0.0..1.0`.

## 11. Report

The tool shall print a tabular report containing, at minimum, the CRAP score,
the cyclomatic complexity, the coverage percentage, the unit's qualified name,
and its file and line.

The report shall be sorted by CRAP descending. Units with `N/A` CRAP shall
appear after units with numeric CRAP. Ties shall be broken deterministically by
complexity, then name, then location.

The report shall end with a summary line stating how many units were analyzed,
how many lacked coverage, how many exceeded the threshold, and the worst score.

## 12. Threshold

The CRAP threshold shall be `8.0`.

The tool shall determine the maximum numeric CRAP value in the result set. If it
is greater than `8.0`, the tool shall print
`CRAP threshold exceeded: <max> > 8.0` to stderr and exit with threshold-failure
status.

If no numeric CRAP values exist, the maximum shall be treated as `0.0` and the
threshold shall not be considered exceeded.

## 13. Exit Codes

- `0` Successful analysis, including empty selection or all scores at or below
  threshold.
- `1` CLI usage error, or an execution failure such as a failing test command or
  an unreadable source file.
- `2` CRAP threshold exceeded.

## 14. Error Handling

The tool shall fail fast on invalid command-line usage, coverage command
failure, and unreadable source files. Coverage measured against a failing test
suite is not a number worth acting on, so a non-zero test command is fatal.

Warnings about a missing coverage export shall not by themselves fail the run.

## 15. Non-Goals

The current implementation is not required to support configurable thresholds
via CLI, Xcode/`xcodebuild` projects or `.xcresult` bundles, directory recursion
outside the `Sources/` discovery rules, mutation analysis, or machine-readable
output formats.

## 16. Deviations from crap4java

Documented, deliberate differences:

1. **Computed-property and subscript accessors are scored.** Java has no
   equivalent, and in Swift a large amount of branching lives in `get`/`set`
   bodies. Each accessor is scored separately.
2. **Nested functions are scored.** They are ordinary declarations in Swift, and
   llvm-cov emits coverage records for them.
3. **`Tests/` is never scanned.** Maven's `src/**` includes `src/test/java`;
   SwiftPM keeps tests outside `Sources/`, and scoring the test suite is not
   useful.
4. **Attribution is positional, not by name.** JaCoCo reports readable method
   names; llvm-cov reports mangled Swift symbols, so line spans are the stable
   key.
5. **Closure branches fold into the enclosing unit** for both complexity and
   coverage, rather than disappearing the way anonymous-class methods do.
