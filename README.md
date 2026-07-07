<p align="center">
  <a href="https://deepwiki.com/tleyden/tauri2-stt"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
</p>

<p align="center">
  <a href="./AppScreenshot.png"><img src="./AppScreenshot.png" alt="App screenshot" width="900"></a>
</p>

This is part of a series of prototyping repos:

1. (this repo) [Local model speech-to-text transcription library running from a Tauri2 desktop app](https://github.com/tleyden/tauri2-stt)
2. [Text-to-speech local model from Tauri/rust](https://github.com/tleyden/tauri2-qwen3-tts)
3. [Gemma4-12b from Tauri/rust](https://github.com/tleyden/tauri2-local-llm)

I created these while prototyping local AI options for two apps I'm building: [Fluensy](https://fluensy.app) (language learning for professionals) and [brain3](https://github.com/tleyden/brain3) (MCP server for markdown vaults).

## P0 Requirements

1. Doesn't require GPU, but will use it if available
2. Runs on macOS
3. Fast
4. Relatively low resource requirements
5. Callable from Tauri2 via FFI (not sidecar)
6. Accurate timestamps in transcripts
7. Streaming transcriptions
8. Allow for commercial use


## How to run it

The Tauri 2 app is in the local repo subdirectory [`./argmax-oss-swift`](./argmax-oss-swift).

```sh
cd argmax-oss-swift
bun install
bun run tauri dev
```


## Design notes - best integration strategy?

### Option 1: [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (implemented)

#### Strengths

1. Supports all requirements

#### Risks

1. Async API, needs to be wrapped in sync wrappers on the swift side


### Option 2: WhisperX

#### Strengths

1. Accurate timestamps

#### Risks

1. Requires python sidecar
