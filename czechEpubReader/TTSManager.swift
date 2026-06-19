import Foundation
import Combine
import AVFoundation
import MediaPlayer
import NaturalLanguage

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

    // Aktuálně čtený chunk text a pozice v fullText
    @Published var currentChunkText: String = ""
    @Published var currentChunkOffset: Int = 0   // char offset chunku v fullText
    @Published var currentWordIndex: Int = 0      // index aktuálně čteného slova v chunku

    // Slova aktuálního chunku pro zvýraznění
    private(set) var currentChunkWords: [String] = []
    private(set) var currentChunkWordOffsets: [Int] = []  // char offset každého slova v chunku
    private var wordTimer: Timer?

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

    func stop() {
        wordTimer?.invalidate()
        wordTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        chunks = []
        chunkOffsets = []
        currentChunkIndex = 0
        audioBuffer = [:]
        currentChunkText = ""
        currentChunkWords = []
        currentWordIndex = 0
        state = .idle
        progress = 0
        clearNowPlayingInfo()
    }

    func pause() {
        wordTimer?.invalidate()
        audioPlayer?.pause()
        state = .paused
    }

    func resume() {
        audioPlayer?.play()
        state = .playing
        startWordTimer()
    }

    // MARK: - Synthesis Loop (s prefetch bufferem)

    // Buffer předsyntetizovaných WAV dat
    private var audioBuffer: [Int: Data] = [:]   // chunkIndex → WAV data
    private let bufferSize = 3                    // kolik chunků dopředu syntetizovat
    private let synthesisQueue = DispatchQueue(label: "tts.synthesis", qos: .userInitiated)

    private func synthesizeNextChunk() {
        guard currentChunkIndex < chunks.count else {
            DispatchQueue.main.async {
                self.state = .idle
                self.onFinished?()
            }
            return
        }

        // Pokud máme chunk v bufferu, přehraj ho okamžitě
        if let wavData = audioBuffer[currentChunkIndex] {
            audioBuffer.removeValue(forKey: currentChunkIndex)
            currentPosition = chunkOffsets[safe: currentChunkIndex] ?? currentPosition
            currentChunkOffset = currentPosition
            currentChunkText = chunks[safe: currentChunkIndex] ?? ""
            progress = Double(currentChunkIndex) / Double(max(chunks.count, 1))
            playWAV(wavData)
            prefetchUpcoming()
            return
        }

        // Jinak syntetizuj aktuální chunk a zároveň prefetchuj další
        state = .synthesizing
        prefetchChunk(index: currentChunkIndex) { [weak self] wavData in
            guard let self = self else { return }
            guard let wavData = wavData else {
                self.currentChunkIndex += 1
                self.synthesizeNextChunk()
                return
            }
            self.currentPosition = self.chunkOffsets[safe: self.currentChunkIndex] ?? self.currentPosition
            self.currentChunkOffset = self.currentPosition
            self.currentChunkText = self.chunks[safe: self.currentChunkIndex] ?? ""
            self.progress = Double(self.currentChunkIndex) / Double(max(self.chunks.count, 1))
            self.playWAV(wavData)
            self.prefetchUpcoming()
        }
    }

    /// Syntetizuje chunky dopředu do bufferu
    private func prefetchUpcoming() {
        let start = currentChunkIndex + 1
        let end = min(start + bufferSize, chunks.count)
        for i in start..<end {
            guard audioBuffer[i] == nil else { continue }
            prefetchChunk(index: i) { [weak self] wavData in
                guard let self = self, let wavData = wavData else { return }
                self.audioBuffer[i] = wavData
            }
        }
    }

    /// Syntetizuje jeden chunk asynchronně
    private func prefetchChunk(index: Int, completion: @escaping (Data?) -> Void) {
        guard index < chunks.count, let handle = tts else {
            completion(nil)
            return
        }
        let chunk = chunks[index]
        let sr = Int(sampleRate)

        synthesisQueue.async { [weak self] in
            guard let self = self else { completion(nil); return }
            let audio = SherpaOnnxOfflineTtsGenerate(handle, chunk, 0, 1.0)
            defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

            guard let audio = audio, audio.pointee.n > 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let count = Int(audio.pointee.n)
            let samples = Array(UnsafeBufferPointer(start: audio.pointee.samples, count: count))
            let wavData = self.floatSamplesToWAV(samples: samples, sampleRate: sr)
            DispatchQueue.main.async { completion(wavData) }
        }
    }

    private func playWAV(_ wavData: Data) {
        try? AVAudioSession.sharedInstance().setActive(true)
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            state = .playing
            updateNowPlayingInfo(chunkText: chunks[safe: currentChunkIndex] ?? "")
            startWordTimer()
        } catch {
            errorMessage = "Chyba přehrávání: \(error.localizedDescription)"
            currentChunkIndex += 1
            synthesizeNextChunk()
        }
    }

    private func startWordTimer() {
        wordTimer?.invalidate()
        currentWordIndex = 0

        // Rozlož chunk na slova s jejich offsety
        let text = currentChunkText
        var words: [String] = []
        var offsets: [Int] = []
        var idx = text.startIndex
        while idx < text.endIndex {
            // Přeskoč mezery
            while idx < text.endIndex && text[idx].isWhitespace { idx = text.index(after: idx) }
            guard idx < text.endIndex else { break }
            let wordStart = idx
            let charOffset = text.distance(from: text.startIndex, to: wordStart)
            // Najdi konec slova
            while idx < text.endIndex && !text[idx].isWhitespace { idx = text.index(after: idx) }
            words.append(String(text[wordStart..<idx]))
            offsets.append(charOffset)
        }
        currentChunkWords = words
        currentChunkWordOffsets = offsets

        guard !words.isEmpty, let duration = audioPlayer?.duration, duration > 0 else { return }

        // Průměrná délka slova v sekundách
        let interval = duration / Double(words.count)

        wordTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if self.currentWordIndex < words.count - 1 {
                self.currentWordIndex += 1
                // Aktualizuj currentPosition na úrovni slova
                let wordCharOffset = offsets[self.currentWordIndex]
                self.currentPosition = self.currentChunkOffset + wordCharOffset
            } else {
                timer.invalidate()
            }
        }
    }

    private func playAudio(samples: [Float], sampleRate: Int) {
        guard !samples.isEmpty,
              let wavData = floatSamplesToWAV(samples: samples, sampleRate: sampleRate) else {
            currentChunkIndex += 1
            synthesizeNextChunk()
            return
        }
        playWAV(wavData)
    }

    // AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        currentChunkIndex += 1
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

        // Rozdělení na věty — každá věta = jeden chunk
        // Použij NLTokenizer pro přesnější rozdělení na věty
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                // Pokud je věta příliš dlouhá, rozděl ji dál
                if sentence.count > maxLength {
                    let sub = sentence.components(separatedBy: CharacterSet(charactersIn: ",;:"))
                    var current = ""
                    for part in sub {
                        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        if current.count + trimmed.count > maxLength {
                            if !current.isEmpty { chunks.append(current) }
                            current = trimmed
                        } else {
                            current += (current.isEmpty ? "" : ", ") + trimmed
                        }
                    }
                    if !current.isEmpty { chunks.append(current) }
                } else {
                    chunks.append(sentence)
                }
            }
            return true
        }
        return chunks.isEmpty ? [text] : chunks
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
