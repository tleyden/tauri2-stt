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

    if options.verbose {
      logHardwareConfiguration(for: whisperKit)
    }

    let decodingOptions = DecodingOptions(
      withoutTimestamps: false,
      wordTimestamps: options.wordTimestamps
    )

    let results = try await whisperKit.transcribe(
      audioPath: options.audioPath,
      decodeOptions: decodingOptions
    )

    var transcripts: [PrintableTranscript] = []
    transcripts.reserveCapacity(results.count)

    for result in results {
      let segments = result.segments.map { segment in
        let words = (segment.words ?? []).map { word in
          PrintableWord(
            start: Double(word.start),
            end: Double(word.end),
            word: word.word
          )
        }

        return PrintableSegment(
          start: Double(segment.start),
          end: Double(segment.end),
          text: segment.text,
          words: words
        )
      }

      transcripts.append(
        PrintableTranscript(
          text: result.text,
          language: result.language,
          segments: segments
        )
      )
    }

    return transcripts
  }

  private static func logHardwareConfiguration(for whisperKit: WhisperKit) {
    let compute = whisperKit.modelCompute
    fputs(
      """
      Model initialization complete:
        - Model folder: \(whisperKit.modelFolder?.path ?? "Not specified")
        - Tokenizer folder: \(whisperKit.tokenizerFolder?.path ?? "Not specified")

      Hardware configuration:
        - Mel spectrogram: \(compute.melCompute.displayName) (\(compute.melCompute.description))
        - Audio encoder: \(compute.audioEncoderCompute.displayName) (\(compute.audioEncoderCompute.description))
        - Text decoder: \(compute.textDecoderCompute.displayName) (\(compute.textDecoderCompute.description))
        - Prefill: \(compute.prefillCompute.displayName) (\(compute.prefillCompute.description))

      """,
      stderr
    )
  }
}
