import SwiftUI

struct SettingsView: View {

    @ObservedObject var ttsManager: TTSManager
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    @State private var selectedVoice: OpenAITTSEngine.Voice = {
        let raw = UserDefaults.standard.string(forKey: "openai_voice") ?? "onyx"
        return OpenAITTSEngine.Voice(rawValue: raw) ?? .onyx
    }()
    @State private var selectedModel: OpenAITTSEngine.Model = {
        let raw = UserDefaults.standard.string(forKey: "openai_model") ?? "tts-1-hd"
        return OpenAITTSEngine.Model(rawValue: raw) ?? .tts1HD
    }()
    @State private var speed: Double = UserDefaults.standard.double(forKey: "openai_speed") == 0
        ? 1.0
        : UserDefaults.standard.double(forKey: "openai_speed")
    @State private var showAPIKey: Bool = false

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Engine výběr
                Section("TTS Engine") {
                    Picker("Engine", selection: $ttsManager.engineType) {
                        Text("Piper (offline)").tag(TTSEngineType.sherpaOnnx)
                        Text("OpenAI (online)").tag(TTSEngineType.openAI)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: ttsManager.engineType) { _ in
                        applySettings()
                    }

                    if ttsManager.engineType == .sherpaOnnx {
                        Label("Offline, zdarma, čeština cs-CZ-jirka", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Label("Online, vyžaduje API klíč a internet", systemImage: "wifi")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - OpenAI nastavení
                if ttsManager.engineType == .openAI {
                    Section("OpenAI API klíč") {
                        HStack {
                            if showAPIKey {
                                TextField("sk-...", text: $apiKey)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("sk-...", text: $apiKey)
                            }
                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Link("Získat API klíč → platform.openai.com",
                             destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }

                    Section("Hlas") {
                        Picker("Hlas", selection: $selectedVoice) {
                            ForEach(OpenAITTSEngine.Voice.allCases, id: \.self) { voice in
                                Text(voice.displayName).tag(voice)
                            }
                        }
                    }

                    Section("Model") {
                        Picker("Model", selection: $selectedModel) {
                            ForEach(OpenAITTSEngine.Model.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Rychlost řeči") {
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(value: $speed, in: 0.5...2.0, step: 0.1)
                            Text(String(format: "%.1f×", speed))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Section("Cena") {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("TTS-1: $15 / 1M znaků", systemImage: "dollarsign.circle")
                                .font(.caption)
                            Label("TTS-1 HD: $30 / 1M znaků", systemImage: "dollarsign.circle.fill")
                                .font(.caption)
                            Label("Průměrná kniha ≈ 1.4M znaků → $21–$42", systemImage: "book")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Nastavení")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Uložit") {
                        applySettings()
                        dismiss()
                    }
                    .bold()
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Zrušit") { dismiss() }
                }
            }
        }
    }

    private func applySettings() {
        UserDefaults.standard.set(apiKey, forKey: "openai_api_key")
        UserDefaults.standard.set(selectedVoice.rawValue, forKey: "openai_voice")
        UserDefaults.standard.set(selectedModel.rawValue, forKey: "openai_model")
        UserDefaults.standard.set(speed, forKey: "openai_speed")

        if ttsManager.engineType == .openAI && !apiKey.isEmpty {
            let engine = OpenAITTSEngine(apiKey: apiKey)
            engine.voice = selectedVoice
            engine.model = selectedModel
            engine.speed = speed
            ttsManager.openAIEngine = engine
        }
    }
}
