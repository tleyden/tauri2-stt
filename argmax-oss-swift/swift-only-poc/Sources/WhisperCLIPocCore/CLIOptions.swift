import Foundation

public struct CLIOptions: Equatable {
  public let audioPath: String
  public let model: String
  public let wordTimestamps: Bool
  public let prewarm: Bool
  public let verbose: Bool

  public static let defaultModel = "large-v3-v20240930_626MB"

  public static func parse(_ arguments: [String]) throws -> CLIOptions {
    var audioPath: String?
    var model = defaultModel
    var wordTimestamps = true
    var prewarm = false
    var verbose = true

    var index = 1
    while index < arguments.count {
      let argument = arguments[index]

      switch argument {
      case "--audio":
        index += 1
        guard index < arguments.count else {
          throw CLIError.missingValue("--audio")
        }
        audioPath = arguments[index]
      case "--model":
        index += 1
        guard index < arguments.count else {
          throw CLIError.missingValue("--model")
        }
        model = arguments[index]
      case "--word-timestamps":
        wordTimestamps = true
      case "--no-word-timestamps":
        wordTimestamps = false
      case "--prewarm":
        prewarm = true
      case "--verbose":
        verbose = true
      case "--quiet":
        verbose = false
      case "--help", "-h":
        throw CLIError.helpRequested
      default:
        throw CLIError.unknownArgument(argument)
      }

      index += 1
    }

    guard let audioPath else {
      throw CLIError.missingAudioPath
    }

    return CLIOptions(
      audioPath: audioPath,
      model: model,
      wordTimestamps: wordTimestamps,
      prewarm: prewarm,
      verbose: verbose
    )
  }
}

public enum CLIError: Error, Equatable, CustomStringConvertible {
  case helpRequested
  case missingAudioPath
  case missingValue(String)
  case unknownArgument(String)

  public var description: String {
    switch self {
    case .helpRequested:
      return CLIOptions.usage
    case .missingAudioPath:
      return "Missing required --audio path.\n\n\(CLIOptions.usage)"
    case .missingValue(let argument):
      return "Missing value for \(argument).\n\n\(CLIOptions.usage)"
    case .unknownArgument(let argument):
      return "Unknown argument: \(argument)\n\n\(CLIOptions.usage)"
    }
  }
}

extension CLIOptions {
  public static let usage = """
    Usage:
      swift run WhisperCLIPoc --audio /absolute/path/to/audio.wav [options]

    Options:
      --audio <path>             Required path to a local audio file.
      --model <name>             WhisperKit model name. Default: large-v3-v20240930_626MB
      --prewarm                  Sequentially prewarm Core ML models before loading.
      --word-timestamps          Include word timestamps. Enabled by default.
      --no-word-timestamps       Disable word timestamps.
      --verbose                  Enable WhisperKit info logging. Enabled by default.
      --quiet                    Disable WhisperKit logging.
      --help, -h                 Show this help.
    """
}
