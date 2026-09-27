# XFC Bridge

**X-Touch One Controller für Final Cut Pro**

XFC Bridge ist eine native macOS-Menüleisten-App. Sie verbindet den physischen
Behringer X-Touch One über CoreMIDI mit Final Cut Pro. Transport, Jogwheel,
Marker, Clipverschiebung, Timeline-Zoom und Video-Keyframes lassen sich damit
am Controller bedienen. Es werden keine virtuellen MIDI-Ports oder
Drittanbieter-Runtimes benötigt.

## Schnellstart

1. Lade die DMG-Datei von GitHub Releases herunter und öffne sie. Ziehe
   `XFC Bridge.app` auf die Verknüpfung **Programme**.
2. Öffne die App und erlaube ihr unter **Systemeinstellungen → Datenschutz &
   Sicherheit → Bedienungshilfen** den Zugriff.
3. Verbinde den X-Touch One per USB im Mackie-Control-Modus (MC), öffne Final
   Cut Pro und klicke in dessen Fenster.
4. Prüfe im Menüleistensymbol **XFC**, ob MIDI verbunden und Bedienungshilfen
   erlaubt sind. Klicke danach wieder in Final Cut und teste **Play/Stop**.

**[Zur vollständigen Anleitung mit allen Tasten und Lösungen bei Problemen](ANLEITUNG.md)**

## Was die App kann

| Bereich | Funktionen |
| --- | --- |
| Transport | Play, Stop, Rewind, Fast Forward, Jog-Shuttle und Audio-Scrub |
| Schnitt und Marker | Schnitt setzen, Marker setzen, bearbeiten und anspringen |
| Timeline | Per Steuerkreuz navigieren, zoomen und Cliphöhe ändern |
| NUDGE | Clips auswählen und in 1- oder 10-Frame-Schritten verschieben |
| CYCLE | In-/Out-Bereich setzen und in Dauerschleife abspielen |
| DROP | Videoanimationseditor öffnen/schließen und Keyframes setzen, löschen und anspringen |
| Bank | Rückgängig und Wiederholen |

Die Modustasten zeigen den aktiven Zustand mit ihren LEDs an. DROP-Keyframes
arbeiten mit dem Parameter, den du im Videoanimationseditor mit der Maus
gewählt hast, zum Beispiel **Deckkraft**.

## Voraussetzungen und erster Start

Der Download enthält eine App für **Apple Silicon**. Sie ist für **macOS 15
oder neuer** konfiguriert; praktisch getestet wurde sie bisher unter macOS 27
mit einem X-Touch One und Final Cut Pro.

Version 1.0.0 ist lokal signiert, aber noch nicht mit einer Apple Developer ID
signiert oder von Apple notarisiert. macOS kann den ersten Start deshalb
blockieren. Wenn du den Download aus dem offiziellen Repository geprüft hast,
versuche die App einmal zu öffnen und wähle dann unter **Systemeinstellungen →
Datenschutz & Sicherheit → Dennoch öffnen**. Siehe dazu
[Apples Anleitung zum sicheren Öffnen von Apps](https://support.apple.com/de-de/102445).

## Versionierung

`1.0.x` steht für Fehlerkorrekturen, `1.x.0` für neue Funktionen und `x.0.0`
für größere Versionssprünge mit Änderungen an Bedienung oder Zuordnungen.

## Lizenz

Copyright © 2026 Dominik Weiland. XFC Bridge wird unter der
**GNU General Public License Version 3 (GPL-3.0-only)** veröffentlicht.
Den vollständigen Lizenztext findest du in [LICENSE](LICENSE).
Der Quellcode ist in diesem GitHub-Repository verfügbar.

## Entwicklung unterstützen

Wenn dir XFC Bridge hilft, kannst du die Entwicklung freiwillig über
[Ko-fi](https://ko-fi.com/dominik_w) oder
[PayPal](https://paypal.me/DominikWeiland) unterstützen.
Im Menüleistensymbol **XFC** zeigt **Über XFC Bridge …** außerdem die Version,
den Autor und Schaltflächen zu beiden Seiten.

## Für Entwickler

Das native Xcode-Projekt ist `XFCBridge.xcodeproj` mit dem gemeinsamen Scheme
`XFCBridge` und Ziel **My Mac**. Der SwiftPM-Aufbau bleibt für Tests und das
separate, nur lesende MIDI-Diagnoseprogramm `MIDIDump` erhalten:

```sh
./scripts/test.sh
./scripts/build-app.sh
./scripts/package-dmg.sh
```

Der Skript-Build legt `build/XFC Bridge.app` ab. Die App Sandbox ist wegen
Accessibility-Steuerung und simulierten Eingaben deaktiviert. Die Skripte
verwenden derzeit das lokale macOS-26-SDK, weil Compiler und macOS-27-SDK der
installierten Command Line Tools aus unterschiedlichen Swift-6.4-Patchständen
stammen. Nach einem konsistenten CLT-Update kann `XFCBRIDGE_SDKROOT` auf das
aktuelle SDK gesetzt werden.
