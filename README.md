# 🎙️ ScreenRec

Native macOS-Bildschirmaufnahme für Apple Silicon.

## Funktionen

- 🖥️ Ganzen Bildschirm aufnehmen
- 🪟 Ein einzelnes Fenster aufnehmen
- 🎤 Mikrofon optional
- 🔊 Systemaudio optional
- 🖱️ Mauszeiger optional
- 💾 MP4-Ausgabe
- 📁 Frei wählbarer Speicherort
- 📌 Menüleisten-App ohne Dock-Symbol
- ⚡ Native Swift + ScreenCaptureKit
- 🧩 GitHub Actions erstellt automatisch eine DMG

## Voraussetzungen

- macOS 15 oder neuer
- Apple Silicon empfohlen
- Bildschirmaufnahme-Berechtigung
- Mikrofon-Berechtigung nur bei aktivierter Mikrofonaufnahme

## GitHub Build

Unter **Actions** den Workflow `Build ScreenRec DMG` starten.

Der Workflow erstellt eine `ScreenRec.dmg` und veröffentlicht sie bei einem GitHub Release.

## Lokal

```bash
chmod +x build.command install.command uninstall.command
./install.command
```

## Berechtigungen

Nach dem ersten Start:

**Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme**

und bei Bedarf:

**Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon**

ScreenRec aktivieren und die App danach neu starten.

## Technologie

ScreenRec verwendet Apples ScreenCaptureKit für die Bildschirm-/Fensteraufnahme und Audioerfassung. Der GitHub-Build läuft auf einem Apple-Silicon-macOS-15-Runner. Apple dokumentiert `SCStream`, `SCContentFilter` und `SCStreamConfiguration` als die nativen APIs für diesen Anwendungsfall.

