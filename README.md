# czechEpubReader

iOS aplikace pro hlasité čtení EPUB knih v češtině pomocí offline TTS enginu.

## Funkce

- 📚 Otevírání EPUB souborů z lokálního úložiště, iCloud Drive nebo Files
- 🔊 Hlasité čtení v češtině pomocí offline TTS (nevyžaduje internet)
- 📍 Podpora Kindle LOC pozic pro snadné navázání čtení
- 🔖 Automatické ukládání poslední knihy a pozice
- 🔒 Přehrávání při zamčené obrazovce s ovládáním na Lock Screen
- 🎧 Podpora Bluetooth sluchátek
- 📖 Seznam kapitol s LOC pozicemi
- 📊 Zobrazení procentuálního průběhu knihy
- 🎯 Kalibrační nástroj pro přesné mapování Kindle LOC

## Technologie

| Komponenta | Technologie |
|------------|-------------|
| UI | SwiftUI |
| EPUB parsing | [EPUBKit](https://github.com/witekbobrowski/EPUBKit) |
| TTS engine | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) |
| TTS model | Piper cs_CZ-jirka-medium |
| Minimum iOS | 16.0 |

## Požadavky

- Xcode 15+
- iOS 16.0+
- Fyzické iOS zařízení (TTS nefunguje na simulátoru)

## Instalace

### 1. Klonování repozitáře

```bash
git clone https://github.com/TVOJE_JMENO/czechEpubReader.git
cd czechEpubReader
```

### 2. Závislosti

Přidej přes `File → Add Package Dependencies` v Xcode:

```
https://github.com/witekbobrowski/EPUBKit
```

### 3. sherpa-onnx XCFramework

Stáhni z [sherpa-onnx releases](https://github.com/k2-fsa/sherpa-onnx/releases):

```
sherpa-onnx-v1.x.x-ios.tar.bz2
```

Rozbal a přidej do projektu:
- `sherpa-onnx.xcframework` → **Embed & Sign**
- `onnxruntime.xcframework` → **Do Not Embed**

### 4. Český TTS model

Stáhni z [sherpa-onnx TTS models](https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models):

```bash
curl -L -O https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-cs_CZ-jirka-medium.tar.bz2
tar xjf vits-piper-cs_CZ-jirka-medium.tar.bz2
```

Přidej do Xcode projektu (target `czechEpubReader`):
- `cs_CZ-jirka-medium.onnx` — Create groups
- `cs_CZ-jirka-medium.onnx.json` — Create groups
- `tokens.txt` — Create groups
- `espeak-ng-data/` — **Create folder references** (modrá ikona!)

### 5. Info.plist

Přidej klíč pro přehrávání na pozadí:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### 6. Bridging Header

Vytvoř `czechEpubReader-Bridging-Header.h`:

```objc
#ifndef czechEpubReader_Bridging_Header_h
#define czechEpubReader_Bridging_Header_h

#import "sherpa-onnx/c-api/c-api.h"

#endif
```

V Build Settings nastav:
- `Objective-C Bridging Header` → `czechEpubReader/czechEpubReader-Bridging-Header.h`
- `Header Search Paths` → `$(PROJECT_DIR)/czechEpubReader/sherpa-onnx.xcframework/ios-arm64/Headers`

## Použití

1. **Otevři knihu** — klepni na ikonu knihy vpravo nahoře a vyber EPUB soubor
2. **Nastav pozici** — zadej Kindle LOC číslo nebo vyber kapitolu ze seznamu
3. **Spusť čtení** — stiskni ▶ Play
4. **Ovládání** — Play/Pause/Stop, záložka pro uložení aktuální pozice

### Kindle LOC kalibrace

Aplikace používá faktor `115 znaků/LOC` optimalizovaný pro češtinu. Pokud pozice nesedí s tvým Kindle, použij kalibrační dialog (ikona posuvníků vedle pole LOC):

1. Otevři Kindle na konkrétním místě
2. Zadej LOC číslo z Kindle
3. Nastav stejné místo v aplikaci
4. Potvrď kalibraci — aplikace si zapamatuje faktor

## Architektura

```
czechEpubReaderApp.swift   — vstupní bod (@main)
ContentView.swift          — hlavní UI (SwiftUI)
EPUBManager.swift          — načítání a parsování EPUB (EPUBKit)
TTSManager.swift           — syntéza řeči (sherpa-onnx C API)
BookmarkStore.swift        — persistence poslední knihy a pozice
```

## Poznámky

- Model soubory (`.onnx`, `espeak-ng-data/`) a XCFrameworks nejsou součástí repozitáře kvůli velikosti
- TTS funguje pouze na fyzickém zařízení, ne na simulátoru
- Aplikace nevyžaduje internet — vše běží offline

## Licence

MIT
