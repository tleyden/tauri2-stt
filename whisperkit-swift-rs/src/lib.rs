use serde::Deserialize;
use swift_rs::{swift, SRString};

swift!(fn load_model_swift(model: &SRString, prewarm: bool) -> bool);
swift!(fn transcribe_path_swift(
    audio_path: &SRString,
    word_timestamps: bool,
    without_timestamps: bool
) -> Option<SRString>);

pub struct TranscribeOptions {
    pub word_timestamps: bool,
    pub without_timestamps: bool,
}

pub struct TranscriptionResult {
    pub transcript: String,
    pub detected_language_code: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BridgeTranscriptionResult {
    transcript: String,
    detected_language_code: Option<String>,
}

pub fn load_model(model: &str, prewarm: bool) -> bool {
    let model: SRString = model.into();
    unsafe { load_model_swift(&model, prewarm) }
}

pub fn transcribe_from_path(path: &str, options: TranscribeOptions) -> Option<TranscriptionResult> {
    let path: SRString = path.into();
    let result = unsafe {
        transcribe_path_swift(&path, options.word_timestamps, options.without_timestamps)
    }?;

    decode_transcription_result_json(result.as_str())
}

fn decode_transcription_result_json(json: &str) -> Option<TranscriptionResult> {
    let result: BridgeTranscriptionResult = serde_json::from_str(json).ok()?;
    Some(TranscriptionResult {
        transcript: result.transcript,
        detected_language_code: result.detected_language_code,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_transcription_result_json_from_swift() {
        let result = decode_transcription_result_json(
            r#"{"transcript":"hello from swift","detectedLanguageCode":"en"}"#,
        )
        .expect("valid JSON should decode");

        assert_eq!(result.transcript, "hello from swift");
        assert_eq!(result.detected_language_code.as_deref(), Some("en"));
    }
}
