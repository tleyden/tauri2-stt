import Foundation

public struct PrintableTranscript: Equatable {
  public let text: String
  public let language: String?
  public let segments: [PrintableSegment]

  public init(text: String, language: String?, segments: [PrintableSegment]) {
    self.text = text
    self.language = language
    self.segments = segments
  }
}

public struct PrintableSegment: Equatable {
  public let start: Double
  public let end: Double
  public let text: String
  public let words: [PrintableWord]

  public init(start: Double, end: Double, text: String, words: [PrintableWord] = []) {
    self.start = start
    self.end = end
    self.text = text
    self.words = words
  }
}

public struct PrintableWord: Equatable {
  public let start: Double
  public let end: Double
  public let word: String

  public init(start: Double, end: Double, word: String) {
    self.start = start
    self.end = end
    self.word = word
  }
}

public enum TranscriptPrinter {
  public static func render(_ transcript: PrintableTranscript) -> String {
    var lines: [String] = [
      "Full text: \(transcript.text)",
      "Language: \(transcript.language ?? "unknown")",
    ]

    for segment in transcript.segments {
      lines.append(
        "[\(formatSeconds(segment.start))s - \(formatSeconds(segment.end))s] \(segment.text)")

      for word in segment.words {
        lines.append("  [\(formatSeconds(word.start))s - \(formatSeconds(word.end))s] \(word.word)")
      }
    }

    return lines.joined(separator: "\n")
  }

  private static func formatSeconds(_ value: Double) -> String {
    String(format: "%.2f", value)
  }
}
