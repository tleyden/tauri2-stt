use std::process::ExitCode;

use whisperkit_swift_rs::{load_model, transcribe_from_path, TranscribeOptions};

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let Some(audio_path) = args.next() else {
        eprintln!("usage: cargo run --example transcribe_path -- <audio-path> [model]");
        return ExitCode::FAILURE;
    };
    let model = args.next().unwrap_or_else(|| "tiny".to_string());

    if !load_model(&model, false) {
        eprintln!("failed to load WhisperKit model: {model}");
        return ExitCode::FAILURE;
    }

    let Some(result) = transcribe_from_path(
        &audio_path,
        TranscribeOptions {
            word_timestamps: true,
            without_timestamps: false,
        },
    ) else {
        eprintln!("failed to transcribe audio path: {audio_path}");
        return ExitCode::FAILURE;
    };

    println!("Transcript: {}", result.transcript);
    println!(
        "Detected language: {}",
        result
            .detected_language_code
            .as_deref()
            .unwrap_or("unknown")
    );
    ExitCode::SUCCESS
}
