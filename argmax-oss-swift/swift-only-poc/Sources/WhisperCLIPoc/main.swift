import Foundation
import WhisperCLIPocCore

@main
struct WhisperCLIPoc {
  static func main() async {
    do {
      let options = try CLIOptions.parse(CommandLine.arguments)
      let transcripts = try await TranscriptionRunner.transcribe(options: options)

      guard !transcripts.isEmpty else {
        print("No transcription results returned.")
        return
      }

      for transcript in transcripts {
        print(TranscriptPrinter.render(transcript))
      }
    } catch CLIError.helpRequested {
      print(CLIOptions.usage)
    } catch {
      fputs("\(error)\n", stderr)
      Foundation.exit(2)
    }
  }
}
