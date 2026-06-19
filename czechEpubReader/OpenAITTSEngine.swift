import Foundation
import AVFoundation

// MARK: - OpenAI TTS Engine
class OpenAITTSEngine {

    enum Voice: String, CaseIterable {
        case alloy   = "alloy"
        case echo    = "echo"
        case fable   = "fable"
        case onyx    = "onyx"
        case nova    = "nova"
        case shimmer = "shimmer"

        var displayName: String {
            switch self {
            case .alloy:   return "Alloy (neutrální)"
            case .echo:    return "Echo (mužský)"
            case .fable:   return "Fable (expresivní)"
            case .onyx:    return "Onyx (hluboký)"
            case .nova:    return "Nova (ženský)"
            case .shimmer: return "Shimmer (jemný)"
            }
        }
    }

    enum Model: String, CaseIterable {
        case tts1    = "tts-1"       // rychlejší, levnější
        case tts1HD  = "tts-1-hd"   // vyšší kvalita

        var displayName: String {
            switch self {
            case .tts1:   return "TTS-1 (rychlý)"
            case .tts1HD: return "TTS-1 HD (vyšší kvalita)"
            }
        }
    }

    private let apiKey: String
    var voice: Voice = .onyx
    var model: Model = .tts1HD
    var speed: Double = 1.0   // 0.25–4.0

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Syntetizuje text a vrátí MP3 data
    func synthesize(text: String) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw TTSError.missingAPIKey
        }

        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model.rawValue,
            "input": text,
            "voice": voice.rawValue,
            "speed": speed,
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.networkError("Neplatná odpověď serveru")
        }

        if httpResponse.statusCode == 401 {
            throw TTSError.invalidAPIKey
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Neznámá chyba"
            throw TTSError.apiError(httpResponse.statusCode, errorText)
        }

        return data
    }

    enum TTSError: LocalizedError {
        case missingAPIKey
        case invalidAPIKey
        case networkError(String)
        case apiError(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Chybí OpenAI API klíč. Zadejte ho v Nastavení."
            case .invalidAPIKey:
                return "Neplatný OpenAI API klíč."
            case .networkError(let msg):
                return "Chyba sítě: \(msg)"
            case .apiError(let code, let msg):
                return "OpenAI chyba \(code): \(msg)"
            }
        }
    }
}
