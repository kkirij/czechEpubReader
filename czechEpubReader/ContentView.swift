import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @StateObject private var epubManager = EPUBManager()
    @StateObject private var ttsManager  = TTSManager()

    @State private var showCalibration   = false
    @State private var calibKindleLoc    = ""
    @State private var calibLocFactor    = 115
    @State private var showFilePicker    = false
    @State private var kindleLocInput    = "0"
    @State private var selectedChapterID: Int? = nil
    @State private var lastBookURL: URL? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                bookInfoBar

                Divider()

                if epubManager.isLoaded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            positionSection
                            chapterListSection
                        }
                        .padding()
                    }

                    Divider()

                    playbackControls
                        .padding()
                } else {
                    emptyState
                }
            }
            .navigationTitle("Hlasitá čtečka")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Otevřít EPUB", systemImage: "book.badge.plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
            .alert("Chyba", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    epubManager.errorMessage = nil
                    ttsManager.errorMessage  = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                restoreLastSession()
            }
        }
    }

    // MARK: - Sub-views

    private var bookInfoBar: some View {
        HStack {
            Image(systemName: "book.closed.fill")
                .foregroundColor(.accentColor)
            Text(epubManager.isLoaded ? epubManager.bookTitle : "Žádná kniha")
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if epubManager.isLoaded {
                Text("LOC 0–\(epubManager.totalKindleLoc)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "book.pages")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Otevřete EPUB knihu")
                .font(.title2)
            Text("Klepněte na ikonu knihy v pravém horním rohu.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showFilePicker = true
            } label: {
                Label("Vybrat soubor", systemImage: "folder")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Kindle pozice (LOC)", systemImage: "text.cursor")
                    .font(.headline)
                Spacer()
                Button {
                    showCalibration = true
                } label: {
                    Label("Kalibrace", systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                TextField("Kindle LOC", text: $kindleLocInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    .onChange(of: kindleLocInput) { newValue in
                        if let loc = Int(newValue), let url = lastBookURL {
                            BookmarkStore.shared.save(url: url, kindleLoc: loc)
                        }
                    }

                Menu {
                    ForEach(epubManager.chapters) { chapter in
                        Button {
                            let loc = epubManager.kindleLocFromChars(chapter.characterOffset)
                            kindleLocInput = String(loc)
                            selectedChapterID = chapter.id
                        } label: {
                            Text(chapter.title)
                        }
                    }
                } label: {
                    Label("Kapitola", systemImage: "list.number")
                }
                .buttonStyle(.bordered)
            }

            if let loc = Int(kindleLocInput) {
                let charPos = epubManager.charsFromKindleLoc(loc)
                if charPos < epubManager.fullText.count {
                    let preview = String(epubManager.text(from: charPos).prefix(80))
                    Text("LOC \(loc) / \(percentStr(charPos)) — \(preview)…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Text("LOC faktor: \(calibLocFactor) znaků/LOC")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showCalibration) {
            calibrationSheet
        }
    }

    private var calibrationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Zadej LOC z Kindle na místě kde právě jsi v knize. Aplikace si spočítá správný přepočet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Aktuální LOC v Kindle")
                        .font(.headline)
                    TextField("např. 1500", text: $calibKindleLoc)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Odpovídající LOC v aplikaci")
                        .font(.headline)
                    TextField("Kindle LOC", text: $kindleLocInput)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Text("Nastav v aplikaci stejnou pozici jako v Kindle a vlož LOC číslo z Kindle výše.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    applyCalibration()
                    showCalibration = false
                } label: {
                    Label("Kalibrovat", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(calibKindleLoc.isEmpty || kindleLocInput.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Kalibrace LOC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Zavřít") { showCalibration = false }
                }
            }
        }
    }

    private var chapterListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Kapitoly", systemImage: "list.bullet")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(epubManager.chapters) { chapter in
                Button {
                    let loc = epubManager.kindleLocFromChars(chapter.characterOffset)
                    kindleLocInput = String(loc)
                    selectedChapterID = chapter.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.title)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text("LOC \(epubManager.kindleLocFromChars(chapter.characterOffset))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedChapterID == chapter.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        selectedChapterID == chapter.id
                        ? Color.accentColor.opacity(0.1)
                        : Color(.tertiarySystemBackground)
                    )
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            if ttsManager.state != .idle {
                VStack(spacing: 4) {
                    ProgressView(value: ttsManager.progress)
                        .tint(.accentColor)
                    HStack {
                        Text("LOC \(epubManager.kindleLocFromChars(ttsManager.currentPosition)) / \(percentStr(ttsManager.currentPosition))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(stateLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 24) {
                Button {
                    ttsManager.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .disabled(ttsManager.state == .idle)

                Button {
                    handlePlayPause()
                } label: {
                    Image(systemName: playPauseIcon)
                        .font(.largeTitle)
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.borderedProminent)

                // Záložka — uloží aktuální LOC
                Button {
                    let loc = epubManager.kindleLocFromChars(ttsManager.currentPosition)
                    kindleLocInput = String(loc)
                    saveCurrentPosition()
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .disabled(ttsManager.state == .idle)
            }
        }
    }

    // MARK: - Persistence

    private func applyCalibration() {
        guard
            let kindleLoc = Int(calibKindleLoc), kindleLoc > 0,
            let appLoc = Int(kindleLocInput), appLoc > 0
        else { return }

        // charPosition odpovídající appLoc při starém faktoru
        let charPos = appLoc * calibLocFactor

        // Nový faktor = charPos / kindleLoc
        let newFactor = max(1, charPos / kindleLoc)
        calibLocFactor = newFactor
        epubManager.locFactor = newFactor

        // Přepočítej kindleLocInput na nový faktor
        kindleLocInput = String(charPos / newFactor)

        // Ulož faktor
        UserDefaults.standard.set(newFactor, forKey: "locFactor")
    }

    /// Obnoví poslední session při spuštění aplikace
    private func restoreLastSession() {
        let savedFactor = UserDefaults.standard.integer(forKey: "locFactor")
        if savedFactor > 0 {
            calibLocFactor = savedFactor
            epubManager.locFactor = savedFactor
        }
        guard let url = BookmarkStore.shared.loadURL() else { return }
        let loc = BookmarkStore.shared.loadKindleLoc()
        lastBookURL = url
        epubManager.load(url: url)
        kindleLocInput = String(loc)
    }

    /// Uloží aktuální URL knihy a LOC pozici
    private func saveCurrentPosition() {
        guard let url = lastBookURL else { return }
        let loc = Int(kindleLocInput) ?? 0
        BookmarkStore.shared.save(url: url, kindleLoc: loc)
    }

    // MARK: - Actions

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            ttsManager.stop()
            lastBookURL = url
            epubManager.load(url: url)
            kindleLocInput = "0"
            selectedChapterID = nil
            // Ulož novou knihu s pozicí 0
            BookmarkStore.shared.save(url: url, kindleLoc: 0)
        case .failure(let error):
            epubManager.errorMessage = error.localizedDescription
        }
    }

    private func handlePlayPause() {
        switch ttsManager.state {
        case .idle:
            let loc = Int(kindleLocInput) ?? 0
            let charPos = epubManager.charsFromKindleLoc(loc)
            // Předej název knihy a kapitoly pro Lock Screen
            ttsManager.bookTitle = epubManager.bookTitle
            ttsManager.chapterTitle = epubManager.chapter(at: charPos)?.title ?? ""
            ttsManager.startReading(text: epubManager.fullText, fromPosition: charPos)
        case .playing:
            ttsManager.pause()
        case .paused:
            ttsManager.resume()
        case .synthesizing:
            break
        }
    }

    // MARK: - Helpers

    private func percentStr(_ charPos: Int) -> String {
        guard epubManager.fullText.count > 0 else { return "0%" }
        let pct = Double(charPos) / Double(epubManager.fullText.count) * 100
        return String(format: "%.1f%%", pct)
    }

    private var playPauseIcon: String {
        switch ttsManager.state {
        case .idle:         return "play.fill"
        case .synthesizing: return "play.fill"
        case .playing:      return "pause.fill"
        case .paused:       return "play.fill"
        }
    }

    private var stateLabel: String {
        switch ttsManager.state {
        case .idle:         return ""
        case .synthesizing: return "Syntéza…"
        case .playing:      return "Čte…"
        case .paused:       return "Pozastaveno"
        }
    }

    private var errorMessage: String? {
        epubManager.errorMessage ?? ttsManager.errorMessage
    }
}

#Preview {
    ContentView()
}
