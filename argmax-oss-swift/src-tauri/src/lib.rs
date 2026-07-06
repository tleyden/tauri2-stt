use serde::Serialize;
use std::path::Path;

pub const DEFAULT_WHISPERKIT_MODEL: &str = "large-v3-v20240930_626MB";
const DEFAULT_WHISPERKIT_PREWARM: bool = false;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptionResponse {
    transcript: String,
    detected_language_code: Option<String>,
}

#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[cfg(target_os = "macos")]
fn ensure_whisperkit_model_loaded() -> Result<(), String> {
    use std::sync::OnceLock;

    static MODEL_LOAD_RESULT: OnceLock<Result<(), String>> = OnceLock::new();

    MODEL_LOAD_RESULT
        .get_or_init(|| {
            if whisperkit_swift_rs::load_model(DEFAULT_WHISPERKIT_MODEL, DEFAULT_WHISPERKIT_PREWARM)
            {
                println!("WhisperKit: model loaded: {DEFAULT_WHISPERKIT_MODEL}");
                Ok(())
            } else {
                Err(format!(
                    "failed to load WhisperKit model {DEFAULT_WHISPERKIT_MODEL}"
                ))
            }
        })
        .clone()
}

#[cfg(target_os = "macos")]
fn transcribe_audio_path_blocking(
    path: String,
    word_timestamps: bool,
    without_timestamps: bool,
) -> Result<Option<TranscriptionResponse>, String> {
    if !Path::new(&path).is_file() {
        return Err(format!("audio file does not exist: {path}"));
    }

    ensure_whisperkit_model_loaded()?;

    let options = whisperkit_swift_rs::TranscribeOptions {
        word_timestamps,
        without_timestamps,
    };
    let result = whisperkit_swift_rs::transcribe_from_path(&path, options)
        .ok_or_else(|| "WhisperKit transcription failed".to_string())?;

    Ok(Some(TranscriptionResponse {
        transcript: result.transcript,
        detected_language_code: result.detected_language_code,
    }))
}

#[cfg(not(target_os = "macos"))]
fn transcribe_audio_path_blocking(
    _path: String,
    _word_timestamps: bool,
    _without_timestamps: bool,
) -> Result<Option<TranscriptionResponse>, String> {
    Err("WhisperKit bridge is only available on macOS".to_string())
}

#[tauri::command]
async fn transcribe_audio_path(
    path: String,
    word_timestamps: bool,
    without_timestamps: bool,
) -> Result<Option<TranscriptionResponse>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        transcribe_audio_path_blocking(path, word_timestamps, without_timestamps)
    })
    .await
    .map_err(|err| format!("transcription worker failed: {err}"))?
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_large_v3_as_default_whisperkit_model() {
        assert_eq!(DEFAULT_WHISPERKIT_MODEL, "large-v3-v20240930_626MB");
    }

    #[test]
    fn transcribe_command_rejects_missing_audio_path_without_panicking() {
        let result = tauri::async_runtime::block_on(transcribe_audio_path(
            "/definitely/not/a/real/audio/file.wav".to_string(),
            false,
            false,
        ));

        assert!(result.is_err());
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|_app| {
            #[cfg(target_os = "macos")]
            {
                tauri::async_runtime::spawn_blocking(|| {
                    if let Err(err) = ensure_whisperkit_model_loaded() {
                        eprintln!("WhisperKit: {err}");
                    }
                });
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![greet, transcribe_audio_path])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
