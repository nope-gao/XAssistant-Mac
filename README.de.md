# XAssistant Mac

[简体中文](README.md) | [繁體中文](README.zh-Hant.md) | [English](README.en.md) | [日本語](README.ja.md) | [Español](README.es.md) | [Français](README.fr.md) | **Deutsch**

Lokales macOS-Werkzeug zum Aufzeichnen von Tastatur- und Mausaktivität und zum Exportieren animierter Videos mit einer 3D-Heatmap.

Die Funktionen und Ideen stammen von [xuhk/XAssistant](https://github.com/xuhk/XAssistant) und wurden nativ in Swift neu umgesetzt. Dies ist eine inoffizielle macOS-Version ohne Verbindung zum ursprünglichen Autor. Quellcode und Grafiken des Windows-Projekts wurden nicht kopiert. Veröffentlicht unter der [MIT-Lizenz](LICENSE).

## Funktionen

- Aufzeichnung im Hintergrund über die Menüleiste, mit Tagesstatistik und Tastatur-Heatmap.
- Erkennung integrierter und externer Tastaturen; MacBook- und Mac-Vollformatlayouts mit manueller Auswahl.
- Start- und Endzeit mit Kurzbefehlen zur ersten Aufzeichnung und zur aktuellen Zeit.
- Export animierter Anschläge und kumulierter Heatmaps als MP4 mit 1080p und 30 Bildern/s in Downloads; Leerlauf wird automatisch verkürzt.
- Maus ein- oder ausschließen; Geschwindigkeiten von 0.5× bis 256×, einschließlich 128×.
- Dynamische Farbskala anhand der aktuell höchsten kumulierten Anzahl oder feste Skala anhand des endgültigen Maximums im gewählten Zeitraum.
- Fünf Sekunden Schlussbild mit langsam rotierender Kamera.
- Synchroner Klang für jeden Anschlag mit unterschiedlicher Klangfarbe pro physischer Taste; Tastatur-, mechanischer, sanfter oder stummer Modus.

## Installation

Erfordert **Apple Silicon und macOS 13 oder neuer**. Für die heruntergeladene App ist Xcode nicht erforderlich.

- **Direkter Download:** Öffne die [neueste Veröffentlichung](https://github.com/nope-gao/XAssistant-Mac/releases/latest), lade `XAssistant-Mac-arm64.zip` herunter, entpacke sie und verschiebe **XAssistant Mac.app** nach `~/Applications`.
- **Installation oder Update im Terminal:** Beende zunächst die laufende App und führe Folgendes aus:

```bash
curl -fsSL https://raw.githubusercontent.com/nope-gao/XAssistant-Mac/main/install.sh -o /tmp/xassistant-install.sh && bash /tmp/xassistant-install.sh
```

Das Installationsskript lädt die neueste Veröffentlichung, prüft SHA-256 und testet, ob die neue App die Signaturanforderung der installierten App erfüllt. Inkompatible Updates werden vor dem Ersetzen gestoppt. Anschließend wird ohne sudo nach `~/Applications` installiert; Aufzeichnungen bleiben erhalten. Eine Veröffentlichung mit angehängtem App-ZIP ist erforderlich. GitHubs automatisch erzeugtes Source code ZIP enthält nur Quellcode.

Der vorhandene Download v0.4.0 ist ad-hoc signiert und nicht von Apple notarisiert. Wenn macOS das Öffnen blockiert, prüfe die Herkunft und nutze **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen**. Erlaube danach die Eingabeüberwachung.

## Sprache

Die Voreinstellung lautet **Systemsprache**. Die App durchsucht die geordnete macOS-Sprachliste nach einer unterstützten Sprache: **简体中文, 繁體中文, English, 日本語, Español, Français, Deutsch**. Ohne passende Sprache wird Englisch verwendet. Unten im Fenster kannst du die Sprache wählen oder zur Systemsprache zurückkehren; die Einstellung wird gespeichert.

Oberfläche, Menüs, bereits angezeigte Meldungen, Datums- und Zahlenformate, Mausbeschriftungen, Funktionstastennamen und Videotexte folgen dieser Auswahl. Buchstabentasten behalten das physische ANSI-Layout. Das Video behält die Sprache vom Beginn des Exports; währenddessen ist die manuelle Umschaltung deaktiviert. Die Sprache eigener Berechtigungsdialoge und technischer Systemfehler bestimmt macOS.

## Videoklang

Wähle **Tastenanschläge** (Standard), **Mechanisch**, **Sanfte Anschläge** oder **Stumm**. Jede physische Taste hat eine eigene kurze Klangfarbe. Der Klang wird nur beim Drücken ausgelöst und auf das erste Videobild mit dem sichtbaren Anschlag ausgerichtet. Bei hoher Geschwindigkeit überlagern sich dicht aufeinanderfolgende Klänge. Ohne Maus werden auch keine Mausklicks vertont. Die letzten fünf Sekunden bleiben still.

Der Ton wird lokal synthetisiert. Mikrofon, Aufnahmen deiner echten Tastatur und externe Klangdateien werden nicht verwendet. Videos mit Ton enthalten eine AAC-Spur mit 48 kHz; Stumm erzeugt keine Audiospur.

## Aus dem Quellcode bauen

Xcode Command Line Tools werden benötigt. Das Skript erzeugt nur ARM64-Apps; nicht alle unterstützten macOS-Versionen wurden geprüft.

Führe den ersten Befehl nur aus, wenn die Entwicklerwerkzeuge fehlen. Baue im Projektordner; Signaturprüfung und interne Tests sind enthalten. Beende vor der Installation die bestehende App.

```bash
xcode-select --install
bash build.sh
mkdir -p "$HOME/Applications"
ditto "dist/XAssistant Mac.app" "$HOME/Applications/XAssistant Mac.app"
open "$HOME/Applications/XAssistant Mac.app"
```

Lokale Builds verwenden standardmäßig eine Ad-hoc-Signatur, ohne Developer ID und Notarisierung. Das Ersetzen einer App kann bestehende Berechtigungen ungültig machen.

## Verwendung und Berechtigungen

Öffne nach dem ersten Start **Systemeinstellungen → Datenschutz & Sicherheit → Eingabeüberwachung**, erlaube **XAssistant Mac** am installierten Speicherort und beende und starte die App erneut. Benutze Tastatur und Maus und prüfe vor dem Export, ob sich die Zeit der letzten Aufzeichnung und die Zähler tatsächlich aktualisieren.

Ein Neubau oder Austausch kann die Berechtigung ungültig machen. Ist der Schalter aktiv, aber die App zeichnet nicht auf, beende sie und führe Folgendes aus:

```bash
tccutil reset ListenEvent local.jasongao.xassistantmac
```

Füge die installierte App erneut zur Eingabeüberwachung hinzu, erlaube den Zugriff und starte sie neu. Der Befehl setzt nur die Eingabeüberwachung dieser App zurück.

Wähle Zeitraum, Tempo, Mausoption, Farbskala und Klang und klicke auf **In Downloads exportieren**. Aktivität aus nicht aufgezeichneten Zeiträumen lässt sich nicht wiederherstellen.

## Lokale Daten und Datenschutz

Die Daten liegen unter `~/Library/Application Support/XAssistantMac/`. Die App lädt sie nicht hoch und enthält keine Telemetrie. Das Installationsskript greift zum Herunterladen auf GitHub zu.

Für die animierte Wiedergabe werden Druck- und Loslasszeitpunkte, physische Tastenkennungen, Geräteinformationen und Ereignisreihenfolge gespeichert. Hinzu kommen Anwendungsnamen, Bundle IDs und Nutzungsdauer. Fertiger Text aus Eingabemethoden, Fenstertitel, Webadressen und Mauskoordinaten werden nicht gelesen. **Tasten und ihre Reihenfolge können dennoch Rückschlüsse auf eingegebenen Text zulassen. Aufzeichnungen sind sensible Daten; veröffentliche den Datenordner nicht.**

## Bekannte Einschränkungen

- Hauptsächlich ANSI-Layouts. ISO/JIS sind nicht vollständig unterstützt; die automatische Erkennung deckt möglicherweise nicht alle Drittgeräte ab.
- Fn-, Medien- und sichere Eingaben werden möglicherweise nicht vollständig aufgezeichnet. Touch ID wird nicht als normale Taste erfasst.
- Bei mehreren Tastaturen kann die Zuordnung zur Quelle eingeschränkt sein. Automatische Wiederholungen beim Gedrückthalten zählen nicht als einzelne Anschläge.
- Videos werden direkt mit SceneKit, Metal und AVFoundation erzeugt; Blender wird nicht benötigt.

## Update veröffentlichen (Wartung)

Der vorhandene Download v0.4.0 ist ad-hoc signiert. Das Umschalten der Eingabeüberwachung kann die alte Signaturanforderung beibehalten: Der Schalter ist dann aktiv, die Aufzeichnung jedoch blockiert. Künftige Veröffentlichungen **erfordern eine beständige Developer ID Application-Signaturidentität**; ohne Zertifikat wird die Veröffentlichung gestoppt.

Konfiguriere die GitHub-Actions-Secrets `SIGNING_CERTIFICATE_BASE64` (Base64-kodierte P12-Datei), `SIGNING_CERTIFICATE_PASSWORD` und `SIGNING_IDENTITY`. Private Schlüssel gehören niemals ins Repository. Der Workflow importiert das Zertifikat in einen temporären Schlüsselbund und löscht diesen danach. Verwende für Updates dieselbe Identität. Der erste Wechsel von ad-hoc zu Developer ID erfordert einmalig eine neue Freigabe.

Aktualisiere Version und Buildnummer in `build.sh`, committe die Änderungen und pushe den passenden Tag:

```bash
git tag v0.4.1
git push origin main --tags
```

Pushes auf main prüfen Übersetzungen, Anschlagtiming und tatsächliche Audio-/Videocodierung. Versionstags veröffentlichen nach bestandenen Tests ein App-ZIP mit Prüfsumme. Verwende für spätere Updates jeweils eine neue Versionsnummer. Alternativ kannst du mit lokal installiertem Zertifikat `SIGNING_IDENTITY="Developer ID Application: …" bash package.sh` ausführen und `dist/XAssistant-Mac-arm64.zip` sowie `dist/SHA256SUMS` manuell an die GitHub-Veröffentlichung anhängen.

`ALLOW_ADHOC_PACKAGE=1 bash package.sh` dient nur lokalen Tests, nicht Updates mit dauerhaft erhaltenen Berechtigungen. Ein fester Pfad und eine Bundle ID allein beheben wechselnde Ad-hoc-Signaturen nicht. Siehe [Apples Erklärung zu Signaturanforderungen und Datenschutzberechtigungen](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
