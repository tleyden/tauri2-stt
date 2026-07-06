# WhisperKit CLI POC

Standalone Swift command-line proof of concept for transcribing local audio with WhisperKit before wiring speech-to-text into Tauri.

## Build

From this package directory:

```bash
cd argmax-oss-swift/swift-only-poc
swift package resolve
swift build
```

## Run

Use an absolute path to a local audio file:

```bash
swift run WhisperCLIPoc --audio /absolute/path/to/audio.wav
```

Or run it from the repository root without changing directories:

```bash
swift run --package-path argmax-oss-swift/swift-only-poc WhisperCLIPoc --audio /absolute/path/to/audio.wav
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

## Related CLI

The `whisperkit-swift-rs/whisperkit-swift` package builds the Swift/Rust bridge static library and does not declare a `WhisperCLIPoc` executable product. Its helper script runs Argmax's dependency CLI instead:

```bash
cd whisperkit-swift-rs/whisperkit-swift
./run.sh transcribe --audio-path /absolute/path/to/audio.wav
```

## Output

The CLI prints:

- full transcript text
- detected language
- segment timestamps
- word timestamps when the selected model returns them
