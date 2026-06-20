# czechEpubReader

iOS aplikace pro hlasité čtení EPUB knih v češtině.

## Funkce

- 📚 Otevírání EPUB souborů z lokálního úložiště, iCloud Drive nebo Files
- 🔊 Offline TTS v češtině (Piper cs-CZ-jirka) — nevyžaduje internet
- 🤖 Online TTS přes OpenAI (volitelné) — přirozenější hlas
- 📍 Podpora Kindle LOC pozic pro snadné navázání čtení
- 📊 Zobrazení procentuálního průběhu knihy
- 🔖 Automatické ukládání poslední knihy a pozice
- 🔒 Přehrávání při zamčené obrazovce s ovládáním na Lock Screen
- 🎧 Podpora Bluetooth sluchátek
- 📖 Seznam kapitol s LOC pozicemi a zvýrazněním aktuálně čtené kapitoly
- 🎯 Kalibrační nástroj pro přesné mapování Kindle LOC
- ⏩ Přeskakování dopředu/dozadu podle LOC nebo procent
- 🧹 Preprocessing textu pro přirozenější výslovnost (zkratky, symboly)

## Technologie

| Komponenta | Technologie |
|------------|-------------|
| UI | SwiftUI |
| EPUB parsing | [EPUBKit](https://github.com/witekbobrowski/EPUBKit) |
| Offline TTS | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) + Piper cs_CZ-jirka-medium |
| Online TTS | OpenAI TTS API (tts-1 / tts-1-hd) |
| Minimum iOS | 16.0 |

## Architektura

```
czechEpubReaderApp.swift   — vstupní bod (@main)
ContentView.swift          — hlavní UI (SwiftUI)
EPUBManager.swift          — načítání a parsování EPUB, LOC segmenty
TTSManager.swift           — syntéza řeči (sherpa-onnx C API + OpenAI)
OpenAITTSEngine.swift      — OpenAI TTS engine s retry logikou
TTSPreprocessor.swift      — preprocessing textu před syntézou
BookmarkStore.swift        — persistence poslední knihy a pozice
SettingsView.swift         — nastavení TTS enginu a API klíče
```

---

## Instalace přes AltStore (nejjednodušší)

> Nevyžaduje placený Apple Developer účet. Aplikace expiruje každých 7 dní,
> AltStore ji automaticky obnoví přes WiFi.

### 1. Nainstaluj AltStore

Jdi na [altstore.io](https://altstore.io) a postupuj podle návodu pro tvůj operační systém (Mac/Windows).

### 2. Přidej source

V AltStore na iPhonu:
```
Browse → + (vpravo nahoře) → vlož URL:
https://raw.githubusercontent.com/kkirij/czechEpubReader/main/apps.json
```

### 3. Nainstaluj

V AltStore najdi **czechEpubReader** a klepni **Free**.

### 4. Důvěřuj vývojáři

```
Nastavení → Obecné → VPN a správa zařízení → tvoje Apple ID → Důvěřovat
```

---

## Instalace přes Xcode (pro vývojáře)

### Požadavky

- Xcode 15+
- iOS 16.0+
- Fyzické iOS zařízení (TTS nefunguje na simulátoru)

### 1. Klonování

```bash
git clone https://github.com/kkirij/czechEpubReader.git
cd czechEpubReader
```

### 2. EPUBKit — Swift Package

```
File → Add Package Dependencies → https://github.com/witekbobrowski/EPUBKit
```

### 3. sherpa-onnx XCFramework

Stáhni z [sherpa-onnx releases](https://github.com/k2-fsa/sherpa-onnx/releases):

```bash
curl -L -O https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.40/sherpa-onnx-v1.12.40-ios.tar.bz2
tar xjf sherpa-onnx-v1.12.40-ios.tar.bz2
```

Přidej do Xcode projektu:
- `sherpa-onnx.xcframework` → **Embed & Sign**
- `onnxruntime.xcframework` → **Do Not Embed**

Přidej do Build Settings:
- `Header Search Paths` → `$(PROJECT_DIR)/czechEpubReader/sherpa-onnx.xcframework/ios-arm64/Headers`
- `Library Search Paths` → `$(PROJECT_DIR)/czechEpubReader/sherpa-onnx.xcframework/ios-arm64`

### 4. Bridging Header

Vytvoř `czechEpubReader-Bridging-Header.h`:

```objc
#ifndef czechEpubReader_Bridging_Header_h
#define czechEpubReader_Bridging_Header_h

#import "sherpa-onnx/c-api/c-api.h"

#endif
```

Build Settings → `Objective-C Bridging Header` → `czechEpubReader/czechEpubReader-Bridging-Header.h`

### 5. Český TTS model (Piper)

```bash
curl -L -O https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-cs_CZ-jirka-medium.tar.bz2
tar xjf vits-piper-cs_CZ-jirka-medium.tar.bz2
```

Přidej do Xcode (target `czechEpubReader`):

| Soubor | Způsob přidání |
|--------|---------------|
| `cs_CZ-jirka-medium.onnx` | Create groups |
| `cs_CZ-jirka-medium.onnx.json` | Create groups |
| `tokens.txt` | Create groups |
| `espeak-ng-data/` | **Create folder references** (modrá ikona!) |

### 6. Info.plist

Přidej klíč pro přehrávání na pozadí:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

---

## Použití

### Základní ovládání

1. **⚙ Nastavení** (vlevo nahoře) — výběr TTS enginu, OpenAI API klíč
2. **📚 Otevřít knihu** (vpravo nahoře) — výběr EPUB souboru
3. **LOC pole** — zadej Kindle LOC číslo nebo přepni na `%` pro procenta
4. **Kapitola** — výběr ze seznamu, automaticky nastaví pozici
5. **▶ Play** — spustí čtení od zadané pozice
6. **◀ ▶ šipky** — přeskočení o 10 LOC nebo 0.1 % dopředu/dozadu
7. **🔖 Záložka** — uloží aktuální pozici

### TTS enginy

| Engine | Kvalita | Cena | Internet |
|--------|---------|------|----------|
| Piper cs-CZ-jirka (offline) | ⭐⭐⭐ | Zdarma | Ne |
| OpenAI TTS-1 | ⭐⭐⭐⭐ | $15/1M znaků | Ano |
| OpenAI TTS-1 HD | ⭐⭐⭐⭐⭐ | $30/1M znaků | Ano |

Pro OpenAI zadej API klíč v Nastavení. Klíč získáš na [platform.openai.com](https://platform.openai.com/api-keys).

### Kindle LOC kalibrace

Aplikace používá faktor `115 znaků/LOC`. Pro přesnější mapování:

1. Klepni na ikonu posuvníků vedle LOC pole
2. Zadej LOC z Kindle na místě kde právě čteš
3. Nastav stejné místo v aplikaci
4. Klepni **Kalibrovat**

---

## Poznámky

- Model soubory (`.onnx`, `espeak-ng-data/`) a XCFrameworks nejsou v repozitáři — stáhni je zvlášť
- Offline TTS funguje pouze na fyzickém zařízení, ne na simulátoru
- OpenAI TTS má rate limit 50 requestů/minutu — aplikace automaticky čeká při přetížení

## Licence

MIT
