# WhisperKit CLI POC

Standalone Swift command-line proof of concept for transcribing local audio with WhisperKit before wiring speech-to-text into Tauri.

## Build

```bash
swift package resolve
swift build
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
