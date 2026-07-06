import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import "./App.css";

type TranscriptionResult = {
  transcript: string;
  detectedLanguageCode: string | null;
};

const defaultAudioPath =
  "/Users/tleyden/Development/tauri2-stt/argmax-oss-swift/notebook_lm_podcast_30s.wav";

function App() {
  const [audioPath, setAudioPath] = useState(defaultAudioPath);
  const [wordTimestamps, setWordTimestamps] = useState(true);
  const [withoutTimestamps, setWithoutTimestamps] = useState(false);
  const [result, setResult] = useState<TranscriptionResult | null>(null);
  const [status, setStatus] = useState("Loading WhisperKit model...");
  const [isTranscribing, setIsTranscribing] = useState(false);

  async function transcribe() {
    setResult(null);
    setStatus("Transcribing...");
    setIsTranscribing(true);

    try {
      const transcription = await invoke<TranscriptionResult | null>(
        "transcribe_audio_path",
        {
          path: audioPath,
          wordTimestamps,
          withoutTimestamps,
        },
      );

      setResult(transcription);
      setStatus(
        transcription ? "Transcription complete." : "No transcript returned.",
      );
    } catch (err) {
      setStatus(`Transcription failed: ${err}`);
    } finally {
      setIsTranscribing(false);
    }
  }

  return (
    <main className="app-shell">
      <section className="workspace">
        <header className="header">
          <h1>WhisperKit transcription</h1>
          <p>{status}</p>
        </header>

        <form
          className="transcription-form"
          onSubmit={(event) => {
            event.preventDefault();
            transcribe();
          }}
        >
          <label className="field">
            <span>Audio path</span>
            <input
              value={audioPath}
              onChange={(event) => setAudioPath(event.currentTarget.value)}
              spellCheck={false}
              disabled={isTranscribing}
            />
          </label>

          <div className="options">
            <label>
              <input
                type="checkbox"
                checked={wordTimestamps}
                onChange={(event) =>
                  setWordTimestamps(event.currentTarget.checked)
                }
                disabled={isTranscribing}
              />
              Word timestamps
            </label>
            <label>
              <input
                type="checkbox"
                checked={withoutTimestamps}
                onChange={(event) =>
                  setWithoutTimestamps(event.currentTarget.checked)
                }
                disabled={isTranscribing}
              />
              Without timestamps
            </label>
          </div>

          <div className="actions">
            <button
              type="submit"
              className="transcribe-button"
              disabled={isTranscribing}
              aria-busy={isTranscribing}
            >
              {isTranscribing ? (
                <>
                  <span className="button-spinner" aria-hidden="true" />
                  Transcribing...
                </>
              ) : (
                "Transcribe"
              )}
            </button>
          </div>
        </form>

        <section className="result-panel" aria-live="polite">
          <div className="result-meta">
            <span>Detected language</span>
            <strong>{result?.detectedLanguageCode ?? "-"}</strong>
          </div>
          <pre>{result?.transcript ?? ""}</pre>
        </section>
      </section>
    </main>
  );
}

export default App;
