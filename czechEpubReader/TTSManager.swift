import Foundation
import Combine
import AVFoundation
import MediaPlayer

// MARK: - TTS State
enum TTSState {
    case idle
    case synthesizing
    case playing
    case paused
}

// MARK: - TTS Manager
class TTSManager: NSObject, AVAudioPlayerDelegate, ObservableObject {

    @Published var state: TTSState = .idle
    @Published var progress: Double = 0
    @Published var currentPosition: Int = 0
    @Published var errorMessage: String? = nil

    // Sherpa-onnx C API handle
    private var tts: OpaquePointer? = nil
    private var sampleRate: Int32 = 22050

    // Audio playback
    private var audioPlayer: AVAudioPlayer?
    private var audioSession = AVAudioSession.sharedInstance()

    // Text chunking
    private var chunks: [String] = []
    private var chunkOffsets: [Int] = []
    private var currentChunkIndex: Int = 0

    var onFinished: (() -> Void)?

    /// Název knihy a aktuální kapitola pro Lock Screen
    var bookTitle: String = ""
    var chapterTitle: String = ""

    // MARK: - Init

    override init() {
        super.init()
        setupRemoteControls()
        loadModel()
    }

    deinit {
        if let tts = tts {
            SherpaOnnxDestroyOfflineTts(tts)
        }
    }

    // MARK: - Model Loading

    private func loadModel() {
        #if targetEnvironment(simulator)
        errorMessage = "TTS není podporováno na simulátoru. Spusťte na fyzickém zařízení."
        return
        #endif

        guard
            let modelPath = Bundle.main.path(forResource: "cs_CZ-jirka-medium", ofType: "onnx"),
            let modelConfigPath = Bundle.main.path(forResource: "cs_CZ-jirka-medium.onnx", ofType: "json"),
            let tokensPath = Bundle.main.path(forResource: "tokens", ofType: "txt")
        else {
            errorMessage = "TTS model nenalezen v bundle. Přidejte model soubory do Xcode projektu."
            return
        }

        // espeak-ng-data musí být folder reference (modrá složka) v bundle
        guard let resourcePath = Bundle.main.resourcePath else {
            errorMessage = "Nelze získat resource path."
            return
        }
        let espeakDataDir = resourcePath + "/espeak-ng-data"

        // Debug — ověř že soubory existují
        let fm = FileManager.default
        print("=== TTS Debug ===")
        print("modelPath: \(modelPath)")
        print("modelConfigPath: \(modelConfigPath)")
        print("tokensPath: \(tokensPath)")
        print("espeakDataDir: \(espeakDataDir)")
        print("model exists: \(fm.fileExists(atPath: modelPath))")
        print("config exists: \(fm.fileExists(atPath: modelConfigPath))")
        print("tokens exists: \(fm.fileExists(atPath: tokensPath))")
        print("espeak exists: \(fm.fileExists(atPath: espeakDataDir))")
        print("=================")
        var vitsConfig = SherpaOnnxOfflineTtsVitsModelConfig()
        vitsConfig.model = UnsafePointer(strdup(modelPath))
        vitsConfig.lexicon = UnsafePointer(strdup(""))
        vitsConfig.tokens = UnsafePointer(strdup(tokensPath))
        vitsConfig.data_dir = UnsafePointer(strdup(espeakDataDir))
        vitsConfig.noise_scale = 0.667
        vitsConfig.noise_scale_w = 0.8
        vitsConfig.length_scale = 1.0

        var modelConfig = SherpaOnnxOfflineTtsModelConfig()
        modelConfig.vits = vitsConfig
        modelConfig.num_threads = 2
        modelConfig.debug = 1
        modelConfig.provider = UnsafePointer(strdup("cpu"))

        var config = SherpaOnnxOfflineTtsConfig()
        config.model = modelConfig
        config.rule_fsts = UnsafePointer(strdup(""))
        config.max_num_sentences = 1

        tts = SherpaOnnxCreateOfflineTts(&config)

        if tts == nil {
            errorMessage = "Nepodařilo se inicializovat TTS engine. Zkontrolujte model soubory."
            return
        }

        sampleRate = SherpaOnnxOfflineTtsSampleRate(tts)
    }

    // MARK: - Public API

    func startReading(text: String, fromPosition: Int) {
        guard tts != nil else {
            errorMessage = "TTS engine není připraven."
            return
        }
        setupAudioSession()
        stop()

        currentPosition = fromPosition

        let subtext: String
        if fromPosition > 0 && fromPosition < text.count {
            let idx = text.index(text.startIndex, offsetBy: fromPosition)
            subtext = String(text[idx...])
        } else {
            subtext = text
        }

        chunks = splitIntoChunks(subtext, maxLength: 500)
        chunkOffsets = buildOffsets(chunks: chunks, baseOffset: fromPosition)
        currentChunkIndex = 0

        state = .synthesizing
        synthesizeNextChunk()
    }

    func pause() {
        audioPlayer?.pause()
        state = .paused
    }

    func resume() {
        audioPlayer?.play()
        state = .playing
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        chunks = []
        chunkOffsets = []
        currentChunkIndex = 0
        state = .idle
        progress = 0
        clearNowPlayingInfo()
    }

    // MARK: - Synthesis Loop

    private func synthesizeNextChunk() {
        guard currentChunkIndex < chunks.count else {
            DispatchQueue.main.async {
                self.state = .idle
                self.onFinished?()
            }
            return
        }

        let chunk = chunks[currentChunkIndex]
        let ttsHandle = tts

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let handle = ttsHandle else { return }

            // Volání C API pro syntézu
            let audio = SherpaOnnxOfflineTtsGenerate(handle, chunk, 0, 1.0)
            defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

            guard let audio = audio, audio.pointee.n > 0 else {
                DispatchQueue.main.async {
                    self.currentChunkIndex += 1
                    self.synthesizeNextChunk()
                }
                return
            }

            // Převod Float32 samples na pole Swift
            let count = Int(audio.pointee.n)
            let samples = Array(UnsafeBufferPointer(start: audio.pointee.samples, count: count))
            let sr = Int(self.sampleRate)

            DispatchQueue.main.async {
                self.currentPosition = self.chunkOffsets[self.currentChunkIndex]
                self.progress = Double(self.currentChunkIndex) / Double(max(self.chunks.count, 1))
                self.playAudio(samples: samples, sampleRate: sr)
            }
        }
    }

    private func playAudio(samples: [Float], sampleRate: Int) {
        guard !samples.isEmpty else {
            currentChunkIndex += 1
            synthesizeNextChunk()
            return
        }

        guard let wavData = floatSamplesToWAV(samples: samples, sampleRate: sampleRate) else {
            currentChunkIndex += 1
            synthesizeNextChunk()
            return
        }

        // Aktivuj audio session těsně před přehráváním
        try? AVAudioSession.sharedInstance().setActive(true)

        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            state = .playing
            updateNowPlayingInfo(chunkText: chunks[safe: currentChunkIndex] ?? "")
        } catch {
            errorMessage = "Chyba přehrávání: \(error.localizedDescription)"
            currentChunkIndex += 1
            synthesizeNextChunk()
        }
    }

    // AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        currentChunkIndex += 1
        state = .synthesizing
        synthesizeNextChunk()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.allowBluetooth, .allowBluetoothA2DP]
        )
    }

    // MARK: - Remote Controls (Lock Screen)

    private func setupRemoteControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.state == .playing {
                self.pause()
            } else {
                self.resume()
            }
            return .success
        }
    }

    private func updateNowPlayingInfo(chunkText: String) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = chunkText.prefix(60).description
        info[MPMediaItemPropertyArtist] = bookTitle.isEmpty ? "czechEpubReader" : bookTitle
        info[MPMediaItemPropertyAlbumTitle] = chapterTitle
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Text chunking

    private func splitIntoChunks(_ text: String, maxLength: Int) -> [String] {
        var chunks: [String] = []
        var current = ""

        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if current.count + trimmed.count + 2 > maxLength {
                if !current.isEmpty { chunks.append(current) }
                current = trimmed + "."
            } else {
                current += (current.isEmpty ? "" : " ") + trimmed + "."
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func buildOffsets(chunks: [String], baseOffset: Int) -> [Int] {
        var offsets: [Int] = []
        var offset = baseOffset
        for chunk in chunks {
            offsets.append(offset)
            offset += chunk.count
        }
        return offsets
    }

    // MARK: - WAV encoding

    private func floatSamplesToWAV(samples: [Float], sampleRate: Int) -> Data? {
        let numSamples = samples.count
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = UInt32(numSamples * 2)
        let chunkSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.appendLE(chunkSize)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(numChannels)
        data.appendLE(UInt32(sampleRate))
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)
        data.append(contentsOf: "data".utf8)
        data.appendLE(dataSize)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let s16 = Int16(clamped * 32767)
            data.appendLE(UInt16(bitPattern: s16))
        }
        return data
    }
}

// MARK: - Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Data helper
private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
