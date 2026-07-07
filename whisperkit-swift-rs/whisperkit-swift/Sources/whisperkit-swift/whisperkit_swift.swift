import Foundation
import SwiftRs
import WhisperKit

private final class WhisperKitBridgeState {
    static var whisperKit: WhisperKit?
}

private enum WhisperKitBridgeError: Error {
    case missingResult(String)
}

private struct BridgeTranscriptionResult: Codable {
    let transcript: String
    let detectedLanguageCode: String?
}

private func runSync<T>(_ operationName: String, _ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?

    Task {
        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }

    semaphore.wait()

    switch result {
    case .success(let value):
        return value
    case .failure(let error):
        throw error
    case .none:
        throw WhisperKitBridgeError.missingResult("\(operationName) failed without returning a result")
    }
}

private func logModelInitialization(for whisperKit: WhisperKit) {
    print("""
    whisperkit-swift: model initialization complete:
      - Model folder: \(whisperKit.modelFolder?.path ?? "Not specified")
      - Tokenizer folder: \(whisperKit.tokenizerFolder?.path ?? "Not specified")
    """)
}

@_cdecl("whisperkit_bridge_smoke_test_swift")
public func whisperKitBridgeSmokeTestSwift() -> SRString {
    SRString("whisperkit-swift-rs")
}

@_cdecl("load_model_swift")
public func loadModelSwift(model: SRString, prewarm: Bool) -> Bool {
    do {
        let config = WhisperKitConfig(
            model: model.toString(),
            verbose: false,
            logLevel: .info,
            prewarm: prewarm
        )
        WhisperKitBridgeState.whisperKit = try runSync("WhisperKit initialization") {
            try await WhisperKit(config)
        }
        if let whisperKit = WhisperKitBridgeState.whisperKit {
            logModelInitialization(for: whisperKit)
        }
        return true
    } catch {
        print("whisperkit-swift: failed to load model: \(error)")
        return false
    }
}

@_cdecl("transcribe_path_swift")
public func transcribePathSwift(
    audioPath: SRString,
    wordTimestamps: Bool,
    withoutTimestamps: Bool
) -> SRString? {
    guard let whisperKit = WhisperKitBridgeState.whisperKit else {
        print("whisperkit-swift: transcribe_path_swift called before load_model_swift")
        return nil
    }

    do {
        let decodingOptions = DecodingOptions(
            withoutTimestamps: withoutTimestamps,
            wordTimestamps: wordTimestamps
        )
        let results = try runSync("WhisperKit transcription") {
            try await whisperKit.transcribe(
                audioPath: audioPath.toString(),
                decodeOptions: decodingOptions
            )
        }

        let transcript = results.map(\.text).joined(separator: "\n")
        let detectedLanguageCode = results.first?.language
        let bridgeResult = BridgeTranscriptionResult(
            transcript: transcript,
            detectedLanguageCode: detectedLanguageCode
        )
        let data = try JSONEncoder().encode(bridgeResult)
        guard let json = String(data: data, encoding: .utf8) else {
            print("whisperkit-swift: failed to UTF-8 encode transcription JSON")
            return nil
        }
        return SRString(json)
    } catch {
        print("whisperkit-swift: failed to transcribe audio: \(error)")
        return nil
    }
}
