import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @StateObject private var epubManager = EPUBManager()
    @StateObject private var ttsManager  = TTSManager()

    @State private var showFilePicker    = false
    @State private var kindleLocInput    = "0"
    @State private var selectedChapterID: Int? = nil
    @State private var lastBookURL: URL? = nil
    @State private var positionTimer: Timer? = nil

    // Kalibrace
    @State private var showCalibration   = false
    @State private var calibKindleLoc    = ""
    @State private var calibLocFactor    = 115

    // Skrytí klávesnice
    @FocusState private var locFieldFocused: Bool

    // Přepínač LOC / procenta
    enum PositionMode { case loc, percent }
    @State private var positionMode: PositionMode = .loc
    @State private var percentInput = "0.0"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                bookInfoBar

                Divider()

                if epubManager.isLoaded {
                    positionSection
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 6)

                    Divider()

                    // Náhled čteného textu — fixní výška
                    textPreviewSection
                        .padding(.horizontal)
                        .padding(.vertical, 6)

                    Divider()

                    // Fixní nadpis kapitol
                    HStack {
                        Label("Kapitoly", systemImage: "list.bullet")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Scrollovatelný seznam kapitol
                    ScrollViewReader { chapterProxy in
                        ScrollView {
                            chapterListSection
                                .padding(.horizontal)
                                .padding(.bottom)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            locFieldFocused = false
                        }
                        .onChange(of: currentReadingChapterID) { chapterID in
                            if let id = chapterID {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    chapterProxy.scrollTo("chapter_\(id)", anchor: .top)
                                }
                            }
                        }
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
            .onChange(of: ttsManager.state) { newState in
                if newState == .playing || newState == .synthesizing {
                    startPositionTimer()
                } else {
                    stopPositionTimer()
                    if newState == .idle || newState == .paused {
                        syncLocInput()
                    }
                }
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
                Label("Kindle pozice", systemImage: "text.cursor")
                    .font(.headline)
                Spacer()
                Picker("Režim", selection: $positionMode) {
                    Text("LOC").tag(PositionMode.loc)
                    Text("%").tag(PositionMode.percent)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                Button {
                    showCalibration = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                if positionMode == .loc {
                    TextField("Kindle LOC", text: $kindleLocInput)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($locFieldFocused)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Hotovo") { locFieldFocused = false }
                            }
                        }
                        .onChange(of: kindleLocInput) { newValue in
                            if let loc = Int(newValue) {
                                let charPos = epubManager.charsFromKindleLoc(loc)
                                let pct = epubManager.fullText.count > 0
                                    ? Double(charPos) / Double(epubManager.fullText.count) * 100 : 0
                                percentInput = String(format: "%.1f", pct)
                                if let url = lastBookURL {
                                    BookmarkStore.shared.save(url: url, kindleLoc: loc)
                                }
                            }
                        }
                } else {
                    TextField("% (0.0–100.0)", text: $percentInput)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($locFieldFocused)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Hotovo") { locFieldFocused = false }
                            }
                        }
                        .onChange(of: percentInput) { newValue in
                            let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                            if let pct = Double(normalized), pct >= 0, pct <= 100 {
                                let charPos = Int(pct / 100.0 * Double(epubManager.fullText.count))
                                let loc = epubManager.kindleLocFromChars(charPos)
                                kindleLocInput = String(loc)
                                if let url = lastBookURL {
                                    BookmarkStore.shared.save(url: url, kindleLoc: loc)
                                }
                            }
                        }
                }

                // Tlačítko Kapitola — stejně široké jako přepínač + kalibrační tlačítko
                Menu {
                    ForEach(epubManager.chapters) { chapter in
                        Button {
                            let loc = epubManager.kindleLocFromChars(chapter.characterOffset)
                            kindleLocInput = String(loc)
                            let pct = epubManager.fullText.count > 0
                                ? Double(chapter.characterOffset) / Double(epubManager.fullText.count) * 100 : 0
                            percentInput = String(format: "%.1f", pct)
                            selectedChapterID = chapter.id
                            locFieldFocused = false
                        } label: {
                            Label("Kapitola", systemImage: "list.number")
                                .frame(maxWidth: .infinity)
                        }
                    }
                } label: {
                    Label("Kapitola", systemImage: "list.number")
                        .frame(width: 128)
                }
                .buttonStyle(.bordered)
            }

            if let loc = Int(kindleLocInput) {
                let charPos = epubManager.charsFromKindleLoc(loc)
                if charPos < epubManager.fullText.count {
                    Text("LOC \(loc) / \(percentStr(charPos))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showCalibration) {
            calibrationSheet
        }
    }

    private var textPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ttsManager.state == .playing || ttsManager.state == .synthesizing || ttsManager.state == .paused,
               !ttsManager.currentChunkText.isEmpty {
                // Aktuální věta
                Text(ttsManager.currentChunkText)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Příští věta šedě
                let postPos = ttsManager.currentChunkOffset + ttsManager.currentChunkText.count
                if postPos < epubManager.fullText.count {
                    Text(epubManager.text(from: postPos).prefix(150).description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                let charPos = currentCharPosition
                if charPos < epubManager.fullText.count {
                    Text(epubManager.text(from: charPos).prefix(300).description)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .frame(maxWidth: .infinity)
    }

    private var calibrationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Otevři Kindle na konkrétním místě, zapamatuj si LOC číslo a nastav stejné místo v aplikaci.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("LOC v Kindle")
                        .font(.headline)
                    TextField("např. 2906", text: $calibKindleLoc)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("LOC v aplikaci (aktuální)")
                        .font(.headline)
                    Text(kindleLocInput.isEmpty ? "0" : kindleLocInput)
                        .font(.title2)
                        .bold()
                        .foregroundColor(.accentColor)
                    Text("Nastav v aplikaci stejné místo jako v Kindle, pak zadej Kindle LOC výše.")
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
                .disabled(calibKindleLoc.isEmpty)

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

    private var currentReadingChapterID: Int? {
        epubManager.chapter(at: ttsManager.currentPosition)?.id
    }

    private var chapterListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(epubManager.chapters) { chapter in
                let isCurrentlyReading = currentReadingChapterID == chapter.id
                let isSelected = selectedChapterID == chapter.id

                Button {
                    let loc = epubManager.kindleLocFromChars(chapter.characterOffset)
                    kindleLocInput = String(loc)
                    let pct = epubManager.fullText.count > 0
                        ? Double(chapter.characterOffset) / Double(epubManager.fullText.count) * 100 : 0
                    percentInput = String(format: "%.1f", pct)
                    selectedChapterID = chapter.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chapter.title)
                                .font(isCurrentlyReading ? .subheadline.bold() : .subheadline)
                                .foregroundColor(isCurrentlyReading ? .accentColor : .primary)
                                .lineLimit(1)
                            Text("LOC \(epubManager.kindleLocFromChars(chapter.characterOffset))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isCurrentlyReading {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                        } else if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        isCurrentlyReading
                        ? Color.accentColor.opacity(0.15)
                        : isSelected
                            ? Color.accentColor.opacity(0.08)
                            : Color(.tertiarySystemBackground)
                    )
                    .cornerRadius(8)
                }
                .id("chapter_\(chapter.id)")
            }
        }
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

            // Tlačítka přeskoku
            HStack(spacing: 8) {
                Button {
                    skipPosition(forward: false)
                } label: {
                    Label(skipLabel(forward: false), systemImage: "chevron.left")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.bordered)

                Button {
                    skipPosition(forward: true)
                } label: {
                    HStack(spacing: 4) {
                        Text(skipLabel(forward: true))
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Kalibrace

    private func skipLabel(forward: Bool) -> String {
        switch positionMode {
        case .loc:     return forward ? "+10 LOC" : "-10 LOC"
        case .percent: return forward ? "+0.1%" : "-0.1%"
        }
    }

    private func skipPosition(forward: Bool) {
        let direction: Double = forward ? 1 : -1
        switch positionMode {
        case .loc:
            let current = Int(kindleLocInput) ?? 0
            let newLoc = max(0, min(current + Int(direction * 10), epubManager.totalKindleLoc))
            kindleLocInput = String(newLoc)
            let charPos = epubManager.charsFromKindleLoc(newLoc)
            let pct = epubManager.fullText.count > 0
                ? Double(charPos) / Double(epubManager.fullText.count) * 100 : 0
            percentInput = String(format: "%.1f", pct)
        case .percent:
            let current = Double(percentInput.replacingOccurrences(of: ",", with: ".")) ?? 0
            let newPct = max(0, min(current + direction * 0.1, 100))
            percentInput = String(format: "%.1f", newPct)
            let charPos = Int(newPct / 100.0 * Double(epubManager.fullText.count))
            let loc = epubManager.kindleLocFromChars(charPos)
            kindleLocInput = String(loc)
        }
        // Ulož novou pozici
        if let url = lastBookURL, let loc = Int(kindleLocInput) {
            BookmarkStore.shared.save(url: url, kindleLoc: loc)
        }
    }

    private func applyCalibration() {
        guard
            let kindleLoc = Int(calibKindleLoc), kindleLoc > 0,
            let appLoc = Int(kindleLocInput), appLoc > 0
        else { return }

        // charPos při aktuálním appLoc
        let charPos = epubManager.charsFromKindleLoc(appLoc)
        guard charPos > 0 else { return }

        // Nový faktor
        let newFactor = max(1, charPos / kindleLoc)
        calibLocFactor = newFactor
        epubManager.applyLocFactor(newFactor)

        // Přepočítej vstupní pole na nový LOC
        kindleLocInput = String(epubManager.kindleLocFromChars(charPos))

        // Ulož
        UserDefaults.standard.set(newFactor, forKey: "locFactor")
        print("Kalibrace: nový faktor \(newFactor), LOC \(kindleLocInput)")
    }

    // MARK: - Timer

    private func startPositionTimer() {
        stopPositionTimer()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            syncLocInput()
        }
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private var currentCharPosition: Int {
        if let loc = Int(kindleLocInput) {
            return epubManager.charsFromKindleLoc(loc)
        }
        return 0
    }

    private func syncLocInput() {
        guard ttsManager.currentPosition > 0 else { return }
        let loc = epubManager.kindleLocFromChars(ttsManager.currentPosition)
        kindleLocInput = String(loc)
        let pct = epubManager.fullText.count > 0
            ? Double(ttsManager.currentPosition) / Double(epubManager.fullText.count) * 100 : 0
        percentInput = String(format: "%.1f", pct)
        if let url = lastBookURL {
            BookmarkStore.shared.save(url: url, kindleLoc: loc)
        }
    }

    // MARK: - Persistence

    private func restoreLastSession() {
        let savedFactor = UserDefaults.standard.integer(forKey: "locFactor")
        if savedFactor > 0 {
            epubManager.applyLocFactor(savedFactor)
        }
        guard let url = BookmarkStore.shared.loadURL() else { return }
        let loc = BookmarkStore.shared.loadKindleLoc()
        lastBookURL = url
        epubManager.load(url: url)
        if savedFactor > 0 {
            epubManager.applyLocFactor(savedFactor)
        }
        kindleLocInput = String(loc)
        // Synchronizuj procenta po načtení
        let charPos = epubManager.charsFromKindleLoc(loc)
        let pct = epubManager.fullText.count > 0
            ? Double(charPos) / Double(epubManager.fullText.count) * 100 : 0
        percentInput = String(format: "%.1f", pct)
    }

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
