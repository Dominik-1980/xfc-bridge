# XFC Bridge einrichten und verwenden

XFC Bridge verbindet den **Behringer X-Touch One** mit **Final Cut Pro**. Die App
läuft unter dem Kürzel **XFC** in der macOS-Menüleiste. Sie verwendet den
physischen MIDI-Anschluss des Controllers; in Final Cut Pro musst du keinen
MIDI-Controller einrichten.

## Das brauchst du

- Einen Mac mit Apple Silicon und macOS 15 oder neuer. Getestet wurde die App
  bisher unter macOS 27 mit Final Cut Pro 12.3.
- Final Cut Pro und einen per USB angeschlossenen X-Touch One im
  Mackie-Control-Modus (MC). HUI- und reine MIDI-Modi verwenden andere
  Nachrichten und sind nicht für diese Belegung vorgesehen. Andere
  DAW-spezifische MC-Layouts können ebenfalls abweichen.
- Die DMG-Datei mit `XFC Bridge.app` aus dem Release-Download.

## In fünf Schritten starten

1. Lade die DMG-Datei des Releases herunter und öffne sie. Ziehe
   `XFC Bridge.app` auf die Verknüpfung **Programme** und starte erst die
   kopierte App.
2. Öffne die App. Da dieser Release noch keine Apple-Developer-ID-Signatur und
   keine Notarisierung hat, kann macOS den ersten Start blockieren. Wenn du
   den Download aus dem offiziellen Repository geprüft hast, versuche die
   App einmal zu öffnen und wähle anschließend unter **Systemeinstellungen →
   Datenschutz & Sicherheit → Dennoch öffnen**. Weitere Informationen:
   [Apple: Sicher Apps auf dem Mac öffnen](https://support.apple.com/de-de/102445).
3. Erlaube XFC Bridge den Zugriff unter **Systemeinstellungen → Datenschutz &
   Sicherheit → Bedienungshilfen**. Das Statusfenster bietet dafür die Taste
   **Bedienungshilfen erlauben …**. Nach der Freigabe startet sich die App
   gegebenenfalls neu. Falls sie das nicht tut, beende sie über das XFC-Menü
   und öffne sie erneut.
4. Verbinde den X-Touch One per USB und öffne Final Cut Pro mit einem Projekt.
   Klicke in Final Cut, sodass es im Vordergrund ist. XFC Bridge sendet nur
   dann Steuerbefehle.
5. Klicke auf **XFC** in der Menüleiste. Dort sollten **MIDI: X-Touch One
   (Ein-/Ausgang)**, **Bedienungshilfen: erlaubt**, **Final Cut: aktiv** und
   **Mapping aktiv** erscheinen. Klicke danach wieder ins Final-Cut-Fenster.
   Drücke am Controller **Play** und **Stop**: Die Wiedergabe in Final Cut
   sollte starten und anhalten.

Du kannst das Statusfenster schließen. XFC Bridge läuft im XFC-Menü weiter;
über **Statusfenster öffnen …** holst du es zurück.

## Die Grundfunktionen

| Controller | Wirkung in Final Cut Pro |
| --- | --- |
| Play / Stop | Wiedergabe starten / anhalten |
| Rewind / Fast Forward | Rückwärts / vorwärts abspielen |
| Jogwheel, SCRUB aus | Shuttle: schnelleres Drehen erhöht die Geschwindigkeit; beim Loslassen stoppt es |
| SCRUB | Langsamen Audio-Scrub ein- oder ausschalten |
| Jogwheel, SCRUB an | Langsam mit Ton rückwärts / vorwärts bewegen |
| REC | Schnitt an der Abspielposition setzen |
| Bank links / rechts | Rückgängig / Wiederholen |
| Steuerkreuz links / rechts | Ein Einzelbild zurück / vor |
| Steuerkreuz hoch / runter | Vorherigen / nächsten Schnittpunkt anspringen |

**SCRUB** bleibt eingeschaltet, bis du die Taste erneut drückst. Die anderen
Modustasten **MARKER**, **CYCLE**, **NUDGE**, **DROP** und **Lupe** sind
gegenseitig ausschließend: Eine leuchtende Modustaste zeigt die aktive Ebene.
Drücke sie erneut, um zur normalen Belegung zurückzukehren.

## Marker und In-/Out-Bereich

| Aktiver Modus | Taste | Wirkung |
| --- | --- | --- |
| MARKER | REC kurz | Marker setzen |
| MARKER | REC mindestens 0,6 Sekunden halten | Marker setzen und Text bearbeiten |
| MARKER | Rewind / Fast Forward | Vorherigen / nächsten Marker anspringen |
| MARKER | Stop | Ausgewählten Marker löschen |
| CYCLE | Rewind / Fast Forward | In- / Out-Punkt setzen |
| CYCLE | Play | Ausgewählten Bereich in Dauerschleife abspielen |
| CYCLE | Stop während der Wiedergabe | Wiedergabe stoppen |
| CYCLE | Stop im Stillstand | Ausgewählten In-/Out-Bereich löschen |

## Clip auswählen und verschieben

Wähle in Final Cut Pro einen Clip und drücke **NUDGE**. Mit dem Steuerkreuz
wählst du einen anderen Clip: links/rechts in der Timeline, hoch/runter auf
einer anderen Ebene. **Rewind/Fast Forward** verschiebt den ausgewählten Clip
um jeweils **ein Einzelbild** nach links/rechts.

Das Jogwheel verschiebt den Clip in **10-Frame-Schritten**. Mit zusätzlich
aktiviertem **SCRUB** sind es **1-Frame-Schritte**.

## Video-Keyframes mit DROP

1. Wähle einen **Videoclip** in Final Cut Pro aus und drücke **DROP**. Der
   Videoanimationseditor öffnet sich.
2. Wähle dort mit der Maus den gewünschten Parameter, zum Beispiel
   **Deckkraft**. XFC Bridge wählt keinen Parameter automatisch aus.
3. Setze die Abspielposition und drücke **REC**, um einen Keyframe für diesen
   Parameter zu setzen. Mit **Rewind/Fast Forward** springst du zum vorherigen
   oder nächsten Keyframe.
4. Zum Löschen wähle einen **Keyframe selbst** im Editor aus und drücke
   **Stop**. Ohne ausgewählten Keyframe gibt es nichts zu löschen.
5. Drücke **DROP** erneut. Der Videoanimationseditor wird geschlossen und
   die normale Tastenbelegung ist wieder aktiv.

## Timeline-Anzeige mit der Lupe ändern

Drücke die **Lupe**, um das Steuerkreuz umzuschalten. **Links/rechts** zoomt
die Timeline heraus/hinein; **hoch/runter** ändert die Cliphöhe. Ein weiterer
Druck auf die Lupe stellt die normale Navigation wieder her.

## Wenn etwas nicht funktioniert

| Beobachtung | Prüfen |
| --- | --- |
| Kein XFC in der Menüleiste | Ist `XFC Bridge.app` geöffnet? Das Statusfenster darf geschlossen sein. |
| `MIDI: X-Touch One nicht gefunden` | USB-Verbindung und MC-Modus des Controllers prüfen; Controller bei Bedarf neu verbinden; App neu starten. |
| `MIDI: … (nur Eingang)` | Der Controller kann Befehle senden, aber die LED-Rückmeldung hat keinen MIDI-Ausgang. USB-Verbindung und weitere MIDI-Programme prüfen. |
| Tasten bewirken in Final Cut nichts | Final Cut muss im Vordergrund sein. Im XFC-Menü **Mapping aktiv** und **Bedienungshilfen: erlaubt** prüfen. |
| DROP öffnet den Editor, REC setzt aber keinen Keyframe | Einen Videoclip und im Videoanimationseditor einen Parameter wie **Deckkraft** auswählen. |
| Stop löscht keinen Keyframe | Den betreffenden Keyframe im Videoanimationseditor anklicken, dann Stop drücken. |
| macOS blockiert den ersten Start | Die [Apple-Anleitung](https://support.apple.com/de-de/102445) zum Öffnen einer nicht notarisierten App befolgen; nur einen Download aus vertrauenswürdiger Quelle freigeben. |

XFC Bridge belegt nur die hier beschriebenen Bedienelemente. Fader, Encoder,
Fußtaster und weitere Tasten steuern in Version 1.0.0 keine Final-Cut-Funktion.
Die App verändert keine Logic-Pro-Zuordnungen und legt keine virtuellen
MIDI-Ports an. Sie dient rein als temporäre Brücke zwischen Controller und Final Cut solange sie geöffnet ist.
