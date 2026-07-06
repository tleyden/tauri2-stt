# Rust <-> Swift bridge plan: WhisperKit STT via swift-rs

## Decision

Reuse the same `swift-rs` toolchain shape already proven twice in sibling repos —
`../makertime/screen-ocr-swift-rs` (production, ships `screen_capture_swift`, `perform_ocr_swift`,
`resize_image_swift`) and `../tauri2-qwen3-tts/qwen3-tts-swift-rs` (this session's own prior
success, wrapping MLX/Qwen3TTS) — and wrap the transcription logic already validated in
`swift-only-poc/Sources/WhisperCLIPocCore/TranscriptionRunner.swift`. Create a new sibling crate,
`whisperkit-swift-rs/`, next to `swift-only-poc/`, mirroring `qwen3-tts-swift-rs`'s position next
to `hamptus-mlx-swift-qwen3-tts/`.

This is a simpler port than the Qwen3-TTS one in one respect (WhisperKit is CoreML-based, not
MLX/Metal, so the `xcodebuild`-for-metallib fallback ladder does not apply — see risk table) and
harder in another (WhisperKit's core APIs are `async`, unlike `Qwen3TTSPipeline`'s synchronous
`generate()`, so bridging into a synchronous `@_cdecl` export is new, unproven territory for this
family of bridges).

## Reference materials to copy from / consult

- `../tauri2-qwen3-tts/qwen3-tts-swift-rs/Cargo.toml` — `swift-rs = "1.0.6"` as both a normal and
  `[build-dependencies]` (with `features = ["build"]`) entry.
- `../tauri2-qwen3-tts/qwen3-tts-swift-rs/build.rs` — the `SwiftLinker::new(...).with_package(...).link()`
  three-line shape. **Skip** the `build_metallib()` half entirely (WhisperKit ships/downloads
  Core ML models, not compiled `.metal` shaders — see risk table row 2).
- `../makertime/screen-ocr-swift-rs/src/lib.rs` — `resize_image_swift(image: SRData, scale: Float)`
  is the exact precedent for **raw bytes passed IN** to Swift (not just out), which is new to this
  bridge family (`vision-swift`/`qwen3-tts-swift` only ever returned `SRData`, never accepted it).
- `swift-only-poc/Sources/WhisperCLIPocCore/TranscriptionRunner.swift` — the exact
  `WhisperKitConfig` → `WhisperKit(config)` → `DecodingOptions` → `whisperKit.transcribe(audioPath:decodeOptions:)`
  call sequence to wrap, unchanged.
- `swift-only-poc/Sources/WhisperCLIPocCore/CLIOptions.swift` — confirms the tunable knobs already
  proven to work: `model`, `wordTimestamps`, `prewarm`.
- `argmax-oss-swift` (the WhisperKit package itself, checked out under
  `swift-only-poc/.build/checkouts/argmax-oss-swift/`) confirms two API facts this plan depends on:
  - `WhisperKit.transcribe(audioPath:decodeOptions:)` returns `[TranscriptionResult]`, where
    `TranscriptionResult` (`Sources/WhisperKit/Core/Models.swift:467`) exposes `text` and
    `language` (a plain detected-language string) but **no confidence score**.
  - `WhisperKit.detectLanguage(audioPath:) async throws -> (language: String, langProbs: [String: Float])`
    (`Sources/WhisperKit/Core/WhisperKit.swift:533`) is the only public API exposing per-language
    probabilities — confirms the user's "the API supports those fields" claim, but means
    `detectedLanguageConfidence` requires a **second** call/decoding pass, not a free field on the
    transcribe result.
  - `AudioProcessor.loadAudio(fromPath:...)` (`Sources/WhisperKit/Core/Audio/AudioProcessor.swift:229`)
    is `AVAudioFile`-based and file-path only — there is no public in-memory byte-buffer loader.
    Raw-bytes input therefore needs a temp-file round trip inside the Swift wrapper (bytes in →
    temp file → same path-based call), the mirror image of `qwen3-tts-swift`'s
    `synthesize_swift`, which already does a temp-file round trip in the *other* direction
    (samples → temp WAV file → bytes out).

## Risk ranking

| Risk | Concern | Status |
| --- | --- | --- |
| 🟢 | Calling into `argmax-oss-swift`/WhisperKit from a plain SwiftPM package built via `swift build`, no Xcode project | Same shape as `vision-swift`/`qwen3-tts-swift`; `swift-only-poc` itself already builds and runs this exact dependency via plain `swift build`/`swift run` |
| 🟢 | Passing raw bytes **in** to Swift (`SRData` parameter, not just return value) | Proven by `screen-ocr-swift-rs`'s `resize_image_swift(image: SRData, scale: Float)` |
| 🟢 | No Metal/`.metallib` resource-bundling problem | Unlike Qwen3-TTS/MLX, WhisperKit is Core ML — no `xcodebuild` fallback ladder needed here |
| 🟡 | **New:** bridging `async` WhisperKit APIs (`WhisperKit(config)` init and `.transcribe(...)` are both `async throws`) into a synchronous `@_cdecl` export | Not needed in either precedent — `Qwen3TTSPipeline(modelPath:)` and `.generate()` are synchronous. Needs a semaphore-based sync bridge (`Task { ... }` + `DispatchSemaphore`); the Rust-called thread is not part of Swift's cooperative thread pool, so this should be deadlock-safe, but it is unverified in this codebase and must be checked, not assumed |
| 🟡 | Model distribution: WhisperKit downloads Core ML models from Hugging Face at first use (per `swift-only-poc/README.md`), rather than bundling them at build time | Needs a writable, persistent cache location once wired into a signed `.app` (Phase 2); fine for `cargo run`/dev |
| 🟡 | Struct-shaped output (`transcript` + `detectedLanguageCode` + `detectedLanguageConfidence`) has no scalar/`SRData`/`SRString` analog in `swift-rs` | Plan: JSON-encode a `Codable` struct into a single `SRString`, decode with `serde_json` on the Rust side. Still just flat scalars — doesn't need `swift-bridge` |
| 🟡 | Raw bytes alone don't self-describe container format (wav/mp3/m4a) and `AVAudioFile` needs a recognizable file extension | Plan: accept an explicit format/extension parameter alongside the byte buffer (default `"wav"`) |
| ⚪ | `swift-bridge` maintenance/complexity | Deferred, as in the Qwen3-TTS plan — nothing here needs richer types than a flat JSON string |

## Phase 1 — swift-rs wrapper crate (`whisperkit-swift-rs/`)

### Step 1: Scaffold the crate shape
Create `whisperkit-swift-rs/Cargo.toml` and `build.rs`, copied from `qwen3-tts-swift-rs` almost
verbatim, minus the metallib step:

```rust
SwiftLinker::new("14.0") // matches swift-only-poc/Package.swift's .macOS(.v14)
    .with_package("whisperkit-swift", "./whisperkit-swift/")
    .link();
```

Do **not** add the `cargo:rustc-link-lib=c++` line speculatively — WhisperKit is Swift/ObjC +
Core ML, not a C++ core like MLX. Add it only if the link step actually fails with C++ runtime
symbols, and note the finding.

Do add the async/Concurrency rpath line proactively, since `TranscriptionRunner` already uses
`async`/`await` throughout (confirmed by reading it): `println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");`
— and remember (per the Qwen3-TTS lesson) this line must be repeated in
`argmax-oss-swift/src-tauri/build.rs` in Phase 2, since `rustc-link-arg` doesn't propagate to a
downstream consumer crate.

### Step 2: `whisperkit-swift/Package.swift`
Same shape as `qwen3-tts-swift`'s manifest: `.macOS(.v14)` platform, `.library(type: .static)`
product, `SwiftRs` + the WhisperKit product dependency, pinned exactly like `swift-only-poc`:

```swift
.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
// ...
.product(name: "WhisperKit", package: "argmax-oss-swift")
```

### Step 3: Prove the copied toolchain builds before touching WhisperKit
Add one placeholder `@_cdecl` function (trivial string return, mirroring `get_frontmost_app_swift`)
and confirm `cargo build` alone drives `swift build` and links successfully — isolates toolchain
plumbing from WhisperKit/Core ML integration risk.

### Step 4: Load the model — and resolve the async→sync bridge
Add `load_model_swift(model: SRString, prewarm: Bool) -> Bool`, storing the loaded `WhisperKit`
instance in a private static (mirroring `TTSState.pipeline` in `qwen3-tts-swift`). Since
`WhisperKit(config)` init is `async throws`, wrap it in a small sync-bridge helper:

```swift
func runSync<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>!
    Task {
        result = await Result { try await operation() }
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}
```

This is the one genuinely new risk in this plan (see risk table). Verify empirically that calling
this from the thread Rust invokes `@_cdecl` functions on does not deadlock, before building
anything on top of it.

### Step 5: Decisive test — transcribe from a file path
Add:

```swift
@_cdecl("transcribe_path_swift")
public func transcribePathSwift(
    audioPath: SRString,
    wordTimestamps: Bool,
    withoutTimestamps: Bool,
    includeLanguageConfidence: Bool
) -> SRString?
```

Internally: reuse `TranscriptionRunner`'s exact config/decode/transcribe sequence (or import
`WhisperCLIPocCore` directly as a dependency of `whisperkit-swift` to avoid re-deriving it — worth
trying first, since it already has zero WhisperKit-callback surface, just a plain async function).
Build a `Codable` result struct, JSON-encode it, return as `SRString`:

```swift
struct BridgeTranscriptionResult: Codable {
    let transcript: String
    let detectedLanguageCode: String?
    let detectedLanguageConfidence: Double?
}
```

If `includeLanguageConfidence` is true, make the extra `whisperKit.detectLanguage(audioPath:)` call
and take `langProbs[language]` as the confidence value; otherwise leave it `nil` to avoid the
extra ~30s-audio decoding pass on the common path.

Declare in Rust:

```rust
swift!(fn transcribe_path_swift(
    audio_path: &SRString,
    word_timestamps: Bool,
    without_timestamps: Bool,
    include_language_confidence: Bool,
) -> Option<SRString>);
```

with a thin wrapper that `serde_json::from_str`s the returned string into a
`TranscriptionResult { transcript: String, detected_language_code: Option<String>, detected_language_confidence: Option<f64> }`.
Validate against a real audio fixture end-to-end via `cargo run --example transcribe_path`,
comparing output text against what `swift run WhisperCLIPoc --audio ...` already produces (known
good, from the working POC). **Use a small/fast model (e.g. `tiny`) for this step**, not the
default `large-v3-v20240930_626MB`, to keep iteration fast — switch to the production model choice
in Phase 2.

### Step 6: Raw-bytes input
Add:

```swift
@_cdecl("transcribe_bytes_swift")
public func transcribeBytesSwift(
    audioBytes: SRData,
    formatHint: SRString,
    wordTimestamps: Bool,
    withoutTimestamps: Bool,
    includeLanguageConfidence: Bool
) -> SRString?
```

Write `audioBytes` to `FileManager.default.temporaryDirectory/<UUID>.<formatHint>`, delegate to the
same internal helper Step 5 uses, delete the temp file afterward (mirror `synthesize_swift`'s own
temp-file cleanup, just bytes-in instead of bytes-out). Rust wrapper:
`transcribe_from_bytes(bytes: &[u8], format_hint: &str, options: TranscribeOptions) -> Option<TranscriptionResult>`.
`format_hint` defaults to `"wav"` at the call site the user is targeting (CPAL output), but the
Swift/Rust surface itself stays format-agnostic.

### Step 7: Rust API surface (`whisperkit-swift-rs/src/lib.rs`)

```rust
pub struct TranscribeOptions {
    pub word_timestamps: bool,
    pub without_timestamps: bool,
    pub include_language_confidence: bool,
}

pub struct TranscriptionResult {
    pub transcript: String,
    pub detected_language_code: Option<String>,
    pub detected_language_confidence: Option<f64>,
}

pub fn load_model(model: &str, prewarm: bool) -> bool;
pub fn transcribe_from_path(path: &str, options: TranscribeOptions) -> Option<TranscriptionResult>;
pub fn transcribe_from_bytes(bytes: &[u8], format_hint: &str, options: TranscribeOptions) -> Option<TranscriptionResult>;
```

This is the "roughly like `getOrTranscribeAudio`" shape the user asked for, translated to Rust:
one function per input mode (path vs. bytes), both returning the same optional result type.

### Step 8: Tests
- Unit test the JSON→`TranscriptionResult` decode path with a fixed fixture string (no model
  load, no audio needed) — fast, always-on.
- An `examples/transcribe_path.rs` and `examples/transcribe_bytes.rs`, gated as manual/opt-in
  (needs model download + a real audio fixture — none exists in the repo yet; needs a short
  WAV added under e.g. `whisperkit-swift-rs/test_data/`), mirroring `qwen3-tts-swift-rs`'s
  `cargo run --example synthesize` validation step.

## Phase 2 — wire up from Tauri Rust

### Step 1: Depend on the new crate
Add `whisperkit-swift-rs = { path = "../../whisperkit-swift-rs" }` to
`argmax-oss-swift/src-tauri/Cargo.toml`. Add a `src-tauri/build.rs` (none exists today — see
current `Cargo.toml`, no `build.rs` file) that repeats the concurrency-runtime rpath line from
Phase 1 Step 1, since it doesn't propagate transitively. Confirm with `cargo tauri build` whether
the `libc++` line ends up being needed here too (it wasn't needed for `qwen3-tts-swift-rs` itself,
but downstream link behavior can differ — verify, don't assume).

### Step 2: Model load lifecycle
Call `load_model` once, likely in the Tauri `setup` hook (mirroring `hamptus-mlx-swift-qwen3-tts`'s
startup load). Open question for the user: which model name to hardcode/default to for this app —
`swift-only-poc`'s default `large-v3-v20240930_626MB` (626MB download, most accurate) vs. a smaller
one for faster dev loop. Since `load_model_swift`'s call is blocking (via the Step 4 sync bridge),
run it via `tauri::async_runtime::spawn_blocking` so app startup doesn't stall the async runtime.

### Step 3: Tauri commands
Two commands, matching the two Rust functions from Phase 1 Step 7:

```rust
#[tauri::command]
async fn transcribe_audio_path(path: String, word_timestamps: bool, without_timestamps: bool, include_language_confidence: bool) -> Result<Option<TranscriptionResult>, String>

#[tauri::command]
async fn transcribe_audio_bytes(bytes: Vec<u8>, format_hint: String, word_timestamps: bool, without_timestamps: bool, include_language_confidence: bool) -> Result<Option<TranscriptionResult>, String>
```

Both must run the underlying (blocking, semaphore-based) Swift call inside
`tauri::async_runtime::spawn_blocking`, since it blocks its calling thread until Swift's `Task`
completes — never call it directly on an async command's executor thread.

### Step 4: Minimal test harness
Mirror the Qwen3-TTS harness pattern (`hamptus-mlx-swift-qwen3-tts/src/App.tsx`): a minimal
frontend with (a) a text input for a local file path invoking `transcribe_audio_path`, and (b) a
file-upload control that reads bytes client-side and invokes `transcribe_audio_bytes`, to exercise
both code paths. Display `transcript`, `detectedLanguageCode`, `detectedLanguageConfidence` from
the result. Manually click through both paths — this project has no GUI-automation tool available
either, per the Qwen3-TTS session's own finding, so flag this as manual-verification-required
rather than claiming it's tested from logs alone.

### Step 5: Packaged-app verification
Run a signed `.app` build (`cargo tauri build`), not just `cargo tauri dev`, and confirm:
- the Core ML model downloads to and loads from a writable, persistent location outside the app
  bundle (e.g. Application Support), since bundles themselves are typically read-only/sandboxed
  once signed;
- both transcription paths return correct text against a known sample, same as they did in dev.

## Explicitly out of scope for this plan

- Live/streaming microphone transcription (`AudioStreamTranscriber`) — this plan is batch/file
  transcription only, matching the `getOrTranscribeAudio(conversation, audioFilePath)` shape the
  user asked to mirror.
- Diarization, translation task mode, or VAD-based chunking beyond WhisperKit's own defaults.
- Any UI beyond the minimal test harness in Phase 2 Step 4.

## Success criteria

- `cargo build` alone (no `xcodebuild`, no manual Swift build step) in `whisperkit-swift-rs`
  produces a static library that loads a WhisperKit model and transcribes both a file path and a
  raw byte buffer.
- `transcribe_from_path`/`transcribe_from_bytes` return a `TranscriptionResult` whose `transcript`
  matches (module whitespace) what `swift run WhisperCLIPoc --audio ...` already prints for the
  same input file.
- `detected_language_code` is populated on every successful transcription; `detected_language_confidence`
  is populated only when explicitly requested (and costs a visibly separate, optional decoding
  pass, not hidden overhead on the default path).
- `word_timestamps`/`without_timestamps` visibly change the shape of the returned `transcript`
  (see open question 3 below — needs a decision on format).
- `argmax-oss-swift/src-tauri`, consuming `whisperkit-swift-rs` exactly as
  `hamptus-mlx-swift-qwen3-tts/src-tauri` consumes `qwen3-tts-swift-rs`, works end-to-end via
  `cargo tauri dev` with no manual build steps, and both Tauri commands are manually exercised
  from the running UI (not just log inspection).
- The packaged, signed `.app` runs standalone and transcribes correctly, with the Core ML model
  cache living somewhere writable and persistent.

## Ansnwered review questions:
1. **Timestamp shape.**  - just use whatever is returned by whisperkit
2. **Default model.** `large-v3-v20240930_626MB` yes, good default model

5. **Async→sync bridge safety.** acceptable risk.
here is example safe code from whisperkit cto:

Based on the patterns in the codebase, here are safe sync wrappers for WhisperKit's async API. These follow the `DispatchSemaphore` pattern used in the tests [1](#14-0)  and the deprecated sync methods in `MLTensorExtensions.swift` [2](#14-1) .

---

## Sync Wrapper Extension

```swift
import Foundation
import WhisperKit

@available(*, deprecated, message: "Sync wrappers block threads and are not recommended for production. Use async/await instead.")
extension WhisperKit {
    
    /// Synchronous wrapper for WhisperKit initialization
    /// - Warning: Blocks the calling thread. Not recommended for main thread or production use.
    public static func syncInit(
        _ config: WhisperKitConfig = WhisperKitConfig()
    ) throws -> WhisperKit {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<WhisperKit, Error>?
        
        Task {
            do {
                let whisperKit = try await WhisperKit(config)
                result = .success(whisperKit)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        switch result {
        case .success(let whisperKit):
            return whisperKit
        case .failure(let error):
            throw error
        case .none:
            throw WhisperError.transcriptionFailed("Initialization failed with unknown error")
        }
    }
    
    /// Synchronous wrapper for transcription
    /// - Warning: Blocks the calling thread. Not recommended for main thread or production use.
    public func syncTranscribe(
        audioPath: String,
        decodeOptions: DecodingOptions? = nil,
        callback: TranscriptionCallback = nil
    ) throws -> [TranscriptionResult] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[TranscriptionResult], Error>?
        
        Task {
            do {
                let transcription = try await transcribe(
                    audioPath: audioPath,
                    decodeOptions: decodeOptions,
                    callback: callback
                )
                result = .success(transcription)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        switch result {
        case .success(let transcription):
            return transcription
        case .failure(let error):
            throw error
        case .none:
            throw WhisperError.transcriptionFailed("Transcription failed with unknown error")
        }
    }
    
    /// Synchronous wrapper for language detection
    /// - Warning: Blocks the calling thread. Not recommended for main thread or production use.
    public func syncDetectLanguage(
        audioPath: String
    ) throws -> (language: String, langProbs: [String: Float]) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(language: String, langProbs: [String: Float]), Error>?
        
        Task {
            do {
                let detected = try await detectLanguage(audioPath: audioPath)
                result = .success(detected)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        switch result {
        case .success(let detected):
            return detected
        case .failure(let error):
            throw error
        case .none:
            throw WhisperError.transcriptionFailed("Language detection failed with unknown error")
        }
    }
}
```

## Usage Example

```swift
do {
    // Synchronous initialization
    let whisperKit = try WhisperKit.syncInit(
        WhisperKitConfig(model: "large-v3-v20240930_626MB")
    )
    
    // Synchronous transcription
    let results = try whisperKit.syncTranscribe(
        audioPath: "audio.wav",
        decodeOptions: DecodingOptions(wordTimestamps: true)
    )
    
    print(results.first?.text ?? "")
    
    // Synchronous language detection
    let (language, probs) = try whisperKit.syncDetectLanguage(audioPath: "audio.wav")
    print("Detected: \(language)")
} catch {
    print("Error: \(error)")
}
```

## Important Warnings

1. **Thread Blocking**: These wrappers block the calling thread and can cause thread exhaustion if used in concurrent contexts [2](#14-1) .
2. **Main Thread**: Never call these from the main thread in UI applications.
3. **Production Use**: The async/await pattern is the recommended approach for production code [1](#14-0) .
4. **Deprecated Pattern**: This follows the same pattern as the deprecated `MLTensorExtensions` sync methods, which are explicitly marked as unsafe for concurrent async contexts.

## Notes

The sync wrappers use the same `DispatchSemaphore` pattern found in the functional tests [1](#14-0) . All methods are marked with `@available(*, deprecated)` to discourage production use. For proper concurrency, use Swift's native `async/await` pattern throughout your application.

Wiki pages you might want to explore:
- [WhisperKit Tests (argmaxinc/argmax-oss-swift)](/wiki/argmaxinc/argmax-oss-swift#8.1)
- [Glossary (argmaxinc/argmax-oss-swift)](/wiki/argmaxinc/argmax-oss-swift#9)

### Citations

**File:** Tests/WhisperKitTests/FunctionalTests.swift (L68-84)
```swift
    func testBaseImplementation() throws {
        let audioFilePath = try XCTUnwrap(
            Bundle.current(for: self).path(forResource: "jfk", ofType: "wav"),
            "Audio file not found"
        )

        let dispatchSemaphore = DispatchSemaphore(value: 0)

        Task {
            let whisperKit = try await XCTUnwrapAsync(await WhisperKit(model: "large-v3"))
            let transcriptionResult: [TranscriptionResult] = try await whisperKit.transcribe(audioPath: audioFilePath)
            XCTAssertGreaterThan(transcriptionResult.text.count, 0)
            dispatchSemaphore.signal()
        }

        dispatchSemaphore.wait()
    }
```

**File:** Sources/ArgmaxCore/MLTensorExtensions.swift (L48-84)
```swift
    // MARK: Sync (legacy — uses DispatchSemaphore, unsafe in concurrent async contexts)

    @available(*, deprecated, message: "Use await toIntArray() instead.")
    func asIntArray() -> [Int] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [Int] = []
        Task(priority: .high) {
            result = await self.toIntArray()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @available(*, deprecated, message: "Use await toFloatArray() instead.")
    func asFloatArray() -> [Float] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [Float] = []
        Task(priority: .high) {
            result = await self.toFloatArray()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    @available(*, deprecated, message: "Use await toMLMultiArray() instead.")
    func asMLMultiArray() -> MLMultiArray {
        let semaphore = DispatchSemaphore(value: 0)
        var result = try! MLMultiArray(shape: [1], dataType: .float16, initialValue: 0.0)
        Task(priority: .high) {
            result = await self.toMLMultiArray()
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
```
