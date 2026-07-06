# WhisperKit CLI POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Swift command-line proof of concept in `swift-only-poc` that transcribes an audio file with WhisperKit using `large-v3-v20240930_626MB` before any Tauri integration.

**Architecture:** Create a SwiftPM package with a thin executable target and a separate core target. The core target owns argument parsing, WhisperKit configuration, transcription, and output formatting; the executable target only wires `CommandLine.arguments` to the async runner. Parser and formatter tests run without downloading the model, while a manual smoke command exercises real inference.

**Tech Stack:** Swift 6.3, Swift Package Manager, XCTest, WhisperKit from `https://github.com/argmaxinc/argmax-oss-swift.git` `from: "0.9.0"`, macOS Core ML runtime.

---

## File Structure

- Create `swift-only-poc/Package.swift`
  - Declares one executable product, one executable target, one core target, and one XCTest target.
  - Depends on WhisperKit only in the core target.
- Create `swift-only-poc/Sources/WhisperCLIPoc/main.swift`
  - Contains the `@main` entry point.
  - Prints help or errors and exits with stable status codes.
- Create `swift-only-poc/Sources/WhisperCLIPocCore/CLIOptions.swift`
  - Parses `--audio`, `--model`, `--prewarm`, `--word-timestamps`, `--no-word-timestamps`, `--verbose`, and `--help`.
  - Keeps defaults close to the requested sample.
- Create `swift-only-poc/Sources/WhisperCLIPocCore/TranscriptionRunner.swift`
  - Builds `WhisperKitConfig`.
  - Builds `DecodingOptions`.
  - Runs `whisperKit.transcribe(audioPath:decodeOptions:)`.
- Create `swift-only-poc/Sources/WhisperCLIPocCore/TranscriptPrinter.swift`
  - Formats the full text, language, segment timestamps, and optional word timestamps.
- Create `swift-only-poc/Tests/WhisperCLIPocCoreTests/CLIOptionsTests.swift`
  - Tests argument parsing and error cases without model download.
- Create `swift-only-poc/Tests/WhisperCLIPocCoreTests/TranscriptPrinterTests.swift`
  - Tests timestamp formatting through a small value type, avoiding fragile construction of WhisperKit model structs.
- Create `swift-only-poc/README.md`
  - Documents package resolve/build/test/smoke commands and expected first-run model download behavior.

## Task 1: SwiftPM Package Scaffold

**Files:**
- Create: `swift-only-poc/Package.swift`
- Create: `swift-only-poc/Sources/WhisperCLIPoc/main.swift`
- Create: `swift-only-poc/Sources/WhisperCLIPocCore/CLIOptions.swift`
- Create: `swift-only-poc/Tests/WhisperCLIPocCoreTests/CLIOptionsTests.swift`

- [ ] **Step 1: Create the SwiftPM manifest**

Create `swift-only-poc/Package.swift`:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WhisperCLIPoc",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WhisperCLIPoc", targets: ["WhisperCLIPoc"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "WhisperCLIPocCore",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .executableTarget(
            name: "WhisperCLIPoc",
            dependencies: ["WhisperCLIPocCore"]
        ),
        .testTarget(
            name: "WhisperCLIPocCoreTests",
            dependencies: ["WhisperCLIPocCore"]
        )
    ]
)
```

- [ ] **Step 2: Add the first failing parser tests**

Create `swift-only-poc/Tests/WhisperCLIPocCoreTests/CLIOptionsTests.swift`:

```swift
import XCTest
@testable import WhisperCLIPocCore

final class CLIOptionsTests: XCTestCase {
    func testParsesRequiredAudioAndDefaults() throws {
        let options = try CLIOptions.parse([
            "WhisperCLIPoc",
            "--audio",
            "/tmp/sample.wav"
        ])

        XCTAssertEqual(options.audioPath, "/tmp/sample.wav")
        XCTAssertEqual(options.model, "large-v3-v20240930_626MB")
        XCTAssertTrue(options.wordTimestamps)
        XCTAssertFalse(options.prewarm)
        XCTAssertTrue(options.verbose)
    }

    func testParsesOptionalFlags() throws {
        let options = try CLIOptions.parse([
            "WhisperCLIPoc",
            "--audio",
            "/tmp/sample.wav",
            "--model",
            "tiny",
            "--prewarm",
            "--no-word-timestamps",
            "--quiet"
        ])

        XCTAssertEqual(options.audioPath, "/tmp/sample.wav")
        XCTAssertEqual(options.model, "tiny")
        XCTAssertTrue(options.prewarm)
        XCTAssertFalse(options.wordTimestamps)
        XCTAssertFalse(options.verbose)
    }

    func testMissingAudioThrowsUsageError() {
        XCTAssertThrowsError(try CLIOptions.parse(["WhisperCLIPoc"])) { error in
            XCTAssertEqual(error as? CLIError, .missingAudioPath)
        }
    }

    func testUnknownFlagThrowsUsageError() {
        XCTAssertThrowsError(try CLIOptions.parse([
            "WhisperCLIPoc",
            "--audio",
            "/tmp/sample.wav",
            "--bad-flag"
        ])) { error in
            XCTAssertEqual(error as? CLIError, .unknownArgument("--bad-flag"))
        }
    }

    func testHelpThrowsHelpRequested() {
        XCTAssertThrowsError(try CLIOptions.parse(["WhisperCLIPoc", "--help"])) { error in
            XCTAssertEqual(error as? CLIError, .helpRequested)
        }
    }
}
```

- [ ] **Step 3: Run tests to verify the parser target does not exist yet**

Run:

```bash
cd swift-only-poc
swift test --filter CLIOptionsTests
```

Expected: FAIL because `CLIOptions`, `CLIError`, and `WhisperCLIPocCore` source files do not exist yet.

- [ ] **Step 4: Add CLI parser implementation**

Create `swift-only-poc/Sources/WhisperCLIPocCore/CLIOptions.swift`:

```swift
import Foundation

public struct CLIOptions: Equatable {
    public let audioPath: String
    public let model: String
    public let wordTimestamps: Bool
    public let prewarm: Bool
    public let verbose: Bool

    public static let defaultModel = "large-v3-v20240930_626MB"

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        var audioPath: String?
        var model = defaultModel
        var wordTimestamps = true
        var prewarm = false
        var verbose = true

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--audio":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue("--audio")
                }
                audioPath = arguments[index]
            case "--model":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue("--model")
                }
                model = arguments[index]
            case "--word-timestamps":
                wordTimestamps = true
            case "--no-word-timestamps":
                wordTimestamps = false
            case "--prewarm":
                prewarm = true
            case "--verbose":
                verbose = true
            case "--quiet":
                verbose = false
            case "--help", "-h":
                throw CLIError.helpRequested
            default:
                throw CLIError.unknownArgument(argument)
            }

            index += 1
        }

        guard let audioPath else {
            throw CLIError.missingAudioPath
        }

        return CLIOptions(
            audioPath: audioPath,
            model: model,
            wordTimestamps: wordTimestamps,
            prewarm: prewarm,
            verbose: verbose
        )
    }
}

public enum CLIError: Error, Equatable, CustomStringConvertible {
    case helpRequested
    case missingAudioPath
    case missingValue(String)
    case unknownArgument(String)

    public var description: String {
        switch self {
        case .helpRequested:
            return CLIOptions.usage
        case .missingAudioPath:
            return "Missing required --audio path.\n\n\(CLIOptions.usage)"
        case let .missingValue(argument):
            return "Missing value for \(argument).\n\n\(CLIOptions.usage)"
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument)\n\n\(CLIOptions.usage)"
        }
    }
}

public extension CLIOptions {
    static let usage = """
    Usage:
      swift run WhisperCLIPoc --audio /absolute/path/to/audio.wav [options]

    Options:
      --audio <path>             Required path to a local audio file.
      --model <name>             WhisperKit model name. Default: large-v3-v20240930_626MB
      --prewarm                  Sequentially prewarm Core ML models before loading.
      --word-timestamps          Include word timestamps. Enabled by default.
      --no-word-timestamps       Disable word timestamps.
      --verbose                  Enable WhisperKit info logging. Enabled by default.
      --quiet                    Disable WhisperKit logging.
      --help, -h                 Show this help.
    """
}
```

- [ ] **Step 5: Add a temporary executable entry point**

Create `swift-only-poc/Sources/WhisperCLIPoc/main.swift`:

```swift
import Foundation
import WhisperCLIPocCore

@main
struct WhisperCLIPoc {
    static func main() {
        do {
            let options = try CLIOptions.parse(CommandLine.arguments)
            print("Parsed options for \(options.audioPath)")
        } catch CLIError.helpRequested {
            print(CLIOptions.usage)
        } catch {
            fputs("\(error)\n", stderr)
            Foundation.exit(2)
        }
    }
}
```

- [ ] **Step 6: Run parser tests**

Run:

```bash
cd swift-only-poc
swift test --filter CLIOptionsTests
```

Expected: PASS for all `CLIOptionsTests`.

## Task 2: Transcript Formatting

**Files:**
- Create: `swift-only-poc/Sources/WhisperCLIPocCore/TranscriptPrinter.swift`
- Create: `swift-only-poc/Tests/WhisperCLIPocCoreTests/TranscriptPrinterTests.swift`

- [ ] **Step 1: Add failing formatting tests**

Create `swift-only-poc/Tests/WhisperCLIPocCoreTests/TranscriptPrinterTests.swift`:

```swift
import XCTest
@testable import WhisperCLIPocCore

final class TranscriptPrinterTests: XCTestCase {
    func testFormatsSegmentsAndWords() {
        let transcript = PrintableTranscript(
            text: "Hello world.",
            language: "en",
            segments: [
                PrintableSegment(
                    start: 0.0,
                    end: 1.25,
                    text: "Hello world.",
                    words: [
                        PrintableWord(start: 0.0, end: 0.45, word: "Hello"),
                        PrintableWord(start: 0.5, end: 1.1, word: "world")
                    ]
                )
            ]
        )

        let output = TranscriptPrinter.render(transcript)

        XCTAssertEqual(output, """
        Full text: Hello world.
        Language: en
        [0.00s - 1.25s] Hello world.
          [0.00s - 0.45s] Hello
          [0.50s - 1.10s] world
        """)
    }

    func testFormatsMissingLanguage() {
        let transcript = PrintableTranscript(
            text: "Bonjour.",
            language: nil,
            segments: []
        )

        let output = TranscriptPrinter.render(transcript)

        XCTAssertEqual(output, """
        Full text: Bonjour.
        Language: unknown
        """)
    }
}
```

- [ ] **Step 2: Run tests to verify formatter types do not exist yet**

Run:

```bash
cd swift-only-poc
swift test --filter TranscriptPrinterTests
```

Expected: FAIL because `PrintableTranscript`, `PrintableSegment`, `PrintableWord`, and `TranscriptPrinter` do not exist.

- [ ] **Step 3: Add formatter implementation**

Create `swift-only-poc/Sources/WhisperCLIPocCore/TranscriptPrinter.swift`:

```swift
import Foundation

public struct PrintableTranscript: Equatable {
    public let text: String
    public let language: String?
    public let segments: [PrintableSegment]

    public init(text: String, language: String?, segments: [PrintableSegment]) {
        self.text = text
        self.language = language
        self.segments = segments
    }
}

public struct PrintableSegment: Equatable {
    public let start: Double
    public let end: Double
    public let text: String
    public let words: [PrintableWord]

    public init(start: Double, end: Double, text: String, words: [PrintableWord] = []) {
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }
}

public struct PrintableWord: Equatable {
    public let start: Double
    public let end: Double
    public let word: String

    public init(start: Double, end: Double, word: String) {
        self.start = start
        self.end = end
        self.word = word
    }
}

public enum TranscriptPrinter {
    public static func render(_ transcript: PrintableTranscript) -> String {
        var lines: [String] = [
            "Full text: \(transcript.text)",
            "Language: \(transcript.language ?? "unknown")"
        ]

        for segment in transcript.segments {
            lines.append("[\(formatSeconds(segment.start))s - \(formatSeconds(segment.end))s] \(segment.text)")

            for word in segment.words {
                lines.append("  [\(formatSeconds(word.start))s - \(formatSeconds(word.end))s] \(word.word)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
```

- [ ] **Step 4: Run formatter tests**

Run:

```bash
cd swift-only-poc
swift test --filter TranscriptPrinterTests
```

Expected: PASS for all `TranscriptPrinterTests`.

## Task 3: WhisperKit Inference Runner

**Files:**
- Create: `swift-only-poc/Sources/WhisperCLIPocCore/TranscriptionRunner.swift`
- Modify: `swift-only-poc/Sources/WhisperCLIPoc/main.swift`

- [ ] **Step 1: Add the WhisperKit runner**

Create `swift-only-poc/Sources/WhisperCLIPocCore/TranscriptionRunner.swift`:

```swift
import Foundation
import WhisperKit

public enum TranscriptionRunner {
    public static func transcribe(options: CLIOptions) async throws -> [PrintableTranscript] {
        let config = WhisperKitConfig(
            model: options.model,
            verbose: options.verbose,
            logLevel: .info,
            prewarm: options.prewarm
        )
        let whisperKit = try await WhisperKit(config)

        let decodingOptions = DecodingOptions(
            wordTimestamps: options.wordTimestamps,
            withoutTimestamps: false
        )

        let results = try await whisperKit.transcribe(
            audioPath: options.audioPath,
            decodeOptions: decodingOptions
        )

        return results.map { result in
            PrintableTranscript(
                text: result.text,
                language: result.language,
                segments: result.segments.map { segment in
                    PrintableSegment(
                        start: Double(segment.start),
                        end: Double(segment.end),
                        text: segment.text,
                        words: (segment.words ?? []).map { word in
                            PrintableWord(
                                start: Double(word.start),
                                end: Double(word.end),
                                word: word.word
                            )
                        }
                    )
                }
            )
        }
    }
}
```

- [ ] **Step 2: Replace the temporary executable with the async runner**

Replace `swift-only-poc/Sources/WhisperCLIPoc/main.swift` with:

```swift
import Foundation
import WhisperCLIPocCore

@main
struct WhisperCLIPoc {
    static func main() async {
        do {
            let options = try CLIOptions.parse(CommandLine.arguments)
            let transcripts = try await TranscriptionRunner.transcribe(options: options)

            guard !transcripts.isEmpty else {
                print("No transcription results returned.")
                return
            }

            for transcript in transcripts {
                print(TranscriptPrinter.render(transcript))
            }
        } catch CLIError.helpRequested {
            print(CLIOptions.usage)
        } catch {
            fputs("\(error)\n", stderr)
            Foundation.exit(2)
        }
    }
}
```

- [ ] **Step 3: Build the executable**

Run:

```bash
cd swift-only-poc
swift build
```

Expected: PASS. SwiftPM resolves `argmax-oss-swift`, builds `WhisperKit`, then builds `WhisperCLIPoc`.

- [ ] **Step 4: Run the full unit test suite**

Run:

```bash
cd swift-only-poc
swift test
```

Expected: PASS for `CLIOptionsTests` and `TranscriptPrinterTests`.

## Task 4: CLI Documentation and Manual Smoke Test

**Files:**
- Create: `swift-only-poc/README.md`

- [ ] **Step 1: Add README with exact usage**

Create `swift-only-poc/README.md`:

```markdown
# WhisperKit CLI POC

Standalone Swift command-line proof of concept for transcribing local audio with WhisperKit before wiring speech-to-text into Tauri.

## Build

```bash
swift package resolve
swift build
```

## Test

```bash
swift test
```

## Run

Use an absolute path to a local audio file:

```bash
swift run WhisperCLIPoc --audio /absolute/path/to/audio.wav
```

The default model is `large-v3-v20240930_626MB`. WhisperKit downloads the model on first use if it is not already present locally.

To reduce peak memory during first Core ML specialization:

```bash
swift run WhisperCLIPoc --audio /absolute/path/to/audio.wav --prewarm
```

To do a faster wiring check with a smaller model:

```bash
swift run WhisperCLIPoc --audio /absolute/path/to/audio.wav --model tiny
```

## Output

The CLI prints:

- full transcript text
- detected language
- segment timestamps
- word timestamps when the selected model returns them
```

- [ ] **Step 2: Verify help output without running inference**

Run:

```bash
cd swift-only-poc
swift run WhisperCLIPoc --help
```

Expected output starts with:

```text
Usage:
  swift run WhisperCLIPoc --audio /absolute/path/to/audio.wav [options]
```

- [ ] **Step 3: Run real transcription smoke test**

Run this with a real local audio path:

```bash
cd swift-only-poc
swift run WhisperCLIPoc --audio /absolute/path/to/audio.wav --prewarm
```

Expected:

- On first use, WhisperKit downloads `large-v3-v20240930_626MB`.
- The command prints `Full text: ...`.
- The command prints `Language: ...`.
- The command prints segment lines such as `[0.00s - 1.25s] ...`.
- If word timestamps are available, the command prints indented word lines such as `  [0.00s - 0.45s] Hello`.

## Task 5: Final Verification

**Files:**
- Verify: `swift-only-poc/Package.swift`
- Verify: `swift-only-poc/Sources/WhisperCLIPoc/main.swift`
- Verify: `swift-only-poc/Sources/WhisperCLIPocCore/CLIOptions.swift`
- Verify: `swift-only-poc/Sources/WhisperCLIPocCore/TranscriptionRunner.swift`
- Verify: `swift-only-poc/Sources/WhisperCLIPocCore/TranscriptPrinter.swift`
- Verify: `swift-only-poc/Tests/WhisperCLIPocCoreTests/CLIOptionsTests.swift`
- Verify: `swift-only-poc/Tests/WhisperCLIPocCoreTests/TranscriptPrinterTests.swift`
- Verify: `swift-only-poc/README.md`

- [ ] **Step 1: Run formatting check**

Run:

```bash
cd swift-only-poc
swift format lint --recursive Package.swift Sources Tests
```

Expected: PASS if `swift-format` is available. If the command is not installed, record that formatting verification was skipped because `swift-format` is missing.

- [ ] **Step 2: Run tests**

Run:

```bash
cd swift-only-poc
swift test
```

Expected: PASS.

- [ ] **Step 3: Run build**

Run:

```bash
cd swift-only-poc
swift build
```

Expected: PASS.

- [ ] **Step 4: Run help command**

Run:

```bash
cd swift-only-poc
swift run WhisperCLIPoc --help
```

Expected: PASS and prints usage.

- [ ] **Step 5: Run inference smoke test**

Run:

```bash
cd swift-only-poc
swift run WhisperCLIPoc --audio /absolute/path/to/audio.wav --prewarm
```

Expected: PASS with non-empty transcript output. This step requires network access on first model download and a real audio file path.

## Self-Review

- Spec coverage: The plan uses the requested `large-v3-v20240930_626MB` model by default, sets `verbose: true`, `logLevel: .info`, supports `prewarm`, enables `wordTimestamps`, keeps `withoutTimestamps: false`, transcribes by audio path, and prints full text, language, segment timestamps, and word timestamps.
- Placeholder scan: The only `/absolute/path/to/audio.wav` text appears in user-facing CLI examples where the user must supply a machine-local audio file. Implementation files contain concrete defaults and behavior.
- Type consistency: `CLIOptions`, `CLIError`, `PrintableTranscript`, `PrintableSegment`, `PrintableWord`, `TranscriptPrinter`, and `TranscriptionRunner` are introduced before use in executable code. Test target imports only `WhisperCLIPocCore`.
