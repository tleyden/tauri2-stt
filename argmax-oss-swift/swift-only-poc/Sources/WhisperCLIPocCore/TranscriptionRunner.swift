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
}
