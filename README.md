# Breathe Well

Multi-Technik-Atemapp als reine Web-App, die per [apk-builder](../apk-builder)
zu einer Android-APK wird. Läuft komplett offline, ohne Abhängigkeiten, alles
in einer Datei. Ziel: qualitativ mit den Bezahlversionen von
Othership/Breathwrk mithalten, ohne Internetzugriff und ohne
Gerätedaten-Zugriff. Ergänzt [ice-breath](../ice-breath) (das bewusst nur
Wim Hof abdeckt), statt es zu ersetzen.

## Bauen

```powershell
cd "D:\claude code projects\breathe-well"
.\build.ps1 -Release
```

Baut *nicht* direkt mit `apk-builder`s eigenen Skripten, sondern über den
eigenen `build.ps1`-Wrapper, der nach dem Erzeugen des Projekts alles
nachpatcht/-kopiert, was apk-builder selbst nicht kann:

- **Portrait-Lock** (`android:screenOrientation="portrait"` im Manifest) -
  eine Atem-Session soll bei Drehung nicht neu aufgebaut werden.
- **Bildschirm bleibt während der Session wach**
  (`FLAG_KEEP_SCREEN_ON` in `MainActivity.onCreate`) - braucht anders als
  `WAKE_LOCK` keine Manifest-Permission. Zusätzlich fragt die Web-App selbst
  per `navigator.wakeLock` einen Screen-Wake-Lock an (Backup, falls der
  native Flag aus irgendeinem Grund nicht greift).
- **Predictive-Back-Handler** für die Zurück-Wischgeste (Details siehe
  [apk-builder/CLAUDE.md](../apk-builder/CLAUDE.md)).
- **Tägliche Erinnerung**: kopiert `android-src/*.java`
  (`ReminderScheduler`/`ReminderReceiver`/`BootReceiver`) ins generierte
  Projekt und registriert eine JS-Bridge (`AndroidReminders`) - Details im
  Abschnitt "Erinnerung" unten.

`-VersionCode` bei jeder Auslieferung hochzählen, sonst sind zwei
APK-Versionen für Android nicht unterscheidbar:

```powershell
.\build.ps1 -VersionName "1.1" -VersionCode 2 -Release -Install
```

Das Icon liegt bewusst **neben** `web\`, nicht darin - sonst wanderte es
zusätzlich als Web-Asset in die APK.

Getestet wird primär im Desktop-Browser via `file://` (`web/index.html`
direkt öffnen). `?fast=1` an die URL anhängen, um alle Phasen-Dauern durch
10 zu teilen und eine komplette Session in Sekunden durchzuklicken.

## Technik-Engine

Eine Atemtechnik ist ein Eintrag in `TECHNIQUES` (Sekunden pro Phase +
Rundenzahl). Fünf Phasen-Slots in fester Reihenfolge -
`inhale → inhale2 → hold1 → exhale → hold2` - jede mit `seconds: 0`
überspringbar (`inhale2` ist ein optionaler kurzer zweiter Einatmer direkt
nach `inhale`, einzig für den Physiological Sigh gebraucht):

- **Box Breathing**: 4-4-4-4.
- **4-7-8**: 4s ein / 7s halten / 8s aus (kein zweiter Hold).
- **Coherent Breathing**: 5.5s ein / 5.5s aus (keine Holds).
- **Physiological Sigh**: 2s ein, 1s kurz nachatmen, 6s aus - Huberman/
  Feldman, per Stanford-RCT 2023 (Cell Reports Medicine) belegt als
  schnellster Weg, akuten Stress zu senken.
- **Verlängertes Ausatmen**: 4s ein / 8s aus, keine Holds - einfaches
  1:2-Verhältnis, aktiviert über den langen Ausatem den Vagusnerv (Nestor,
  *Breath*).
- **Wechselatmung** (Nadi Shodhana): 4s ein / 2s halten / 4s aus, Seite
  (links/rechts) wechselt pro Runde - klassische Yoga-Technik.
- **Bienenatmung** (Bhramari): 4s ein / 6s aus mit Summen - erhöht laut
  Forschung das Stickstoffmonoxid in der Nase (Nestor, *Breath*).
- **Eigenes Muster**: `inhale`/`hold1`/`exhale`/`hold2` + Rundenzahl frei
  einstellbar (`settings.customPattern`; `inhale2` bewusst nicht im
  Custom-Editor, um das Formular einfach zu halten).
- **Bellows Breath** (Bhastrika): 1s ein / 1s aus, 20 Runden - energetisierend
  statt beruhigend, füllt die "Energize"-Kategorie, die sonst in keiner
  anderen Technik hier vorkommt. Immer im Sitzen, bei Schwindel abbrechen.

`resolveTechnique(id)` löst das auf ein Phasen-Array auf; die
Session-Engine (`startSession`/`tickActive`/`advancePhase`) kennt keine
technik-spezifischen Fälle, sondern läuft nur die Phasenliste ab - eine neue
Technik braucht in der Regel nur einen neuen `TECHNIQUES`-Eintrag, keine
neue Engine-Logik. Einzige Ausnahme ist die Wechselatmung: ihr
`alternates: true`-Flag lässt `beginPhaseVisuals()` den Hinweistext für
Ein-/Ausatmen abhängig von `session.roundIndex` (gerade/ungerade) per
`nostrilHint()` statt per `phase.hint` berechnen, weil die Seite pro Runde
wechselt statt technik-fest zu sein.

Anders als bei ice-breaths Wim-Hof-Zyklus endet hier jede Runde immer in
einem "leere Lunge"-Zustand (Ausatmen oder Halten-nach-Ausatmen), die
nächste Runde kann also direkt mit Einatmen weitermachen - kein
Übergangs-Gap zwischen Runden nötig.

Der Pacer-Kreis nutzt reines CSS `transform: scale()` mit geeastem Progress
(`easeInOut(t) = 0.5 - 0.5*cos(π·t)`); die Farbe (`.pacer-circle.empty`)
spiegelt nur, ob die Lunge gerade voll oder leer ist - kein WebGL (siehe
[hopper](../hopper): WebGL-Shader liefen im Desktop-Browser sauber, ruckelten
aber stark auf dem echten Gerät).

Timing läuft über Wall-Clock-Epoch-Deltas (`Date.now() - phaseStartEpoch`),
nicht akkumulierte Frame-Deltas, um Drift bei Throttling zu vermeiden.

## Datenmodell (localStorage)

Namespace `breathewell.*`, getrennt von ice-breaths `wimhof.*`:

- `breathewell.settings.v1` - Theme (`system`/`light`/`dark`), zuletzt
  verwendete Technik, Rundenzahl pro Standard-Technik, Custom-Pattern.
- `breathewell.sessions.v1` - Array abgeschlossener Sessions:
  ```js
  { techniqueId, params /* aufgelöste Phasenliste */, startedAt, endedAt,
    plannedRounds, completedRounds }
  ```

Nur `finishSession()` (vollständiger Abschluss aller Runden) schreibt einen
Record, `cancelSession()` nie - dieselbe Konvention wie bei ice-breath, weil
die Streak-Logik genau darauf aufbaut.

## Erinnerung (Android-Bruecke)

Eine reine WebView-App kann keine zuverlässige Erinnerung stellen, wenn die
App geschlossen ist - `setTimeout`/Service-Worker-Background-Sync sind in
Android-WebView (anders als vollem Chrome) nicht verlässlich. Deshalb gibt
es hier zum ersten Mal eine kleine native Bruecke:

- `MainActivity` registriert `webView.addJavascriptInterface(new
  ReminderBridge(), "AndroidReminders")` - sicher, weil die WebView
  ausschließlich das eigene gebündelte Asset lädt (`LocalWebViewClient`
  leitet jeden externen Link an den Browser weiter, lädt ihn nie selbst).
- `window.AndroidReminders.setReminder(hour, minute)` /
  `.cancelReminder()` werden aus den Einstellungen aufgerufen
  (`applyReminderSchedule()`); existiert nur in der echten APK, im
  Desktop-Browser bleibt es ein no-op (die UI ist trotzdem testbar, nur die
  tatsächliche Benachrichtigung nicht).
- `ReminderScheduler` (eigene `SharedPreferences`, nicht `localStorage` -
  die Receiver laufen außerhalb der WebView und könnten das nicht lesen)
  plant über `AlarmManager.setAndAllowWhileIdle(...)` genau einen Alarm für
  den nächsten Zeitpunkt - bewusst kein exaktes Repeating, das würde
  `SCHEDULE_EXACT_ALARM` brauchen; ein paar Minuten Drift sind für eine
  Atem-Erinnerung egal.
- `ReminderReceiver` zeigt die Benachrichtigung und plant direkt den
  nächsten Tag neu ein (Selbstverkettung statt Repeating-Alarm).
- `BootReceiver` plant nach einem Geräte-Neustart neu, weil
  `AlarmManager`-Alarme das nicht überleben.
- `POST_NOTIFICATIONS` (API 33+) wird erst angefragt, wenn der Nutzer die
  Erinnerung tatsächlich anschaltet - nicht beim App-Start.

Die drei Java-Klassen liegen als Quelldateien unter `android-src/` und
werden von `build.ps1` unverändert in das generierte Projekt kopiert (statt
als PowerShell-String-Patch generiert zu werden).

## Streak

Kalendertagbasiert (`dayKey()` + sortierte Menge distinkter Tage), DST-sicher
über Tages-Arithmetik statt roher Millisekunden-Differenzen - identisch zu
ice-breaths Implementierung.

## Aktueller Stand

**Stage 1** (device-getestet auf dem Pixel 11 Pro, Feedback eingearbeitet):
Box, 4-7-8, Coherent, Custom; rein visueller Pacer ohne Audio; Verlauf mit
Streak + Technik-Breakdown; Theme System/Hell/Dunkel; Nase/Mund-Hinweise pro
Technik; Predictive-Back-Fix für die Zurück-Wischgeste (siehe
[apk-builder/CLAUDE.md](../apk-builder/CLAUDE.md)).

**Stage 2 - mehr Techniken** (gebaut, noch nicht geräte-getestet): vier
recherchierte, evidenzbasierte Techniken ergänzt - Physiological Sigh,
Verlängertes Ausatmen, Wechselatmung, Bienenatmung (Details siehe
"Technik-Engine" oben).

**Stage 3 - Vibration**: kurzer Puls bei Einatmen/Ausatmen, doppelter Puls
bei Halten-Phasen, langes Abschluss-Muster bei Session-Ende (`VIB`-Tabelle +
`vibrateForPhase()`), per Toggle in den Einstellungen abschaltbar (Default
an). Nutzt dieselbe `navigator.vibrate()`-API wie ice-breath.

Stage 2 + 3 device-getestet auf dem Pixel 11 Pro, vom Nutzer bestätigt
("klappt gut").

**Stage 2b - Bellows Breath**: energetisierende Technik ergänzt (siehe
"Technik-Engine" oben), schließt die bis dahin fehlende "Energize"-Kategorie.

**Stage 4 - Tägliche Erinnerung** (gebaut, noch nicht geräte-getestet -
braucht echten Geräte-Neustart-Test): siehe Abschnitt "Erinnerung" oben.
Erste Stage, die über reines WebView-JS hinausgeht (JS-Bridge,
AlarmManager, BroadcastReceiver, Laufzeit-Permission).

**Stage 6 - Adaptive Rundenzahl** (gebaut, noch nicht geräte-getestet):
siehe Abschnitt oben. Apnoe-/Atem-Anhalte-Training bewusst NICHT hier
eingebaut - das ist architektonisch [ice-breath](../ice-breath)s Job (offene,
nutzerbeendete Halte-Phasen + Bestzeiten-Tracking), nicht diese fest
getaktete Engine.

Audio ist als Nächstes dran, sobald es getestet werden kann (verschoben,
weil beim Bauen "alle schlafen").

**Review-Fixes (v1.7, 2026-09-15, im Browser verifiziert)**: Physiological
Sigh - der Kreis springt zwischen Einatmen und Nachatmen nicht mehr auf klein
zurück (Phasen haben jetzt `fromScale`/`toScale`, Einatmen 0.55→0.85,
Nachatmen 0.85→1.0); Feedback-Knöpfe rechnen vom Ausgangswert der Summary
aus statt zu kumulieren (dreimal "Zu leicht" = +1, nicht +3); Verlängertes
Ausatmen behält 1:2 (siehe unten); höchstens ein Verlaufseintrag "weg vom
Home" (`goHome()` baut ihn per `history.back()` ab) - vorher musste man auf
dem Home mehrfach Zurück drücken, bis die App schließt.

## Adaptive Rundenzahl / Sekunden (Stage 6)

Auf dem Summary-Screen fragt "Wie war die Session?" (zu leicht / passt genau
/ zu schwer) nach jeder abgeschlossenen Session. Was sich dadurch ändert,
hängt von der Technik ab:

- **Reine Verhältnis-Techniken** (`scaleSeconds: true` in `TECHNIQUES`: Box
  Breathing, Verlängertes Ausatmen) - hier steigert/senkt Feedback die
  Tiefe: alle aktiven Phasen gemeinsam um ±1s (geclampt 2-14s pro Phase,
  `settings.techniqueSeconds[id]`). Ausnahme mit `exhaleRatio` (Verlängertes
  Ausatmen, 2): nur der Einatmer ändert sich, der Ausatmer wird daraus
  abgeleitet, damit 1:2 erhalten bleibt (4-8 → 5-10, nicht 5-9). Box bleibt
  dabei immer gleichseitig
  (z.B. 5-5-5-5 statt 4-4-4-4) - die Zahl ist bei diesen Techniken nicht
  vorgeschrieben, nur das Verhältnis zählt (Idee von der App
  [State](https://www.shiftstate.io/), die Übungen über die Zeit vertieft
  statt nur die Wiederholungen zu erhöhen).
- **Alle anderen Techniken** (4-7-8, Coherent, Physiological Sigh,
  Wechselatmung, Bienenatmung, Bellows, Custom) - hier ändert Feedback
  stattdessen `techniqueRounds[id]` (bzw. `customPattern.rounds`) um ±1,
  geclampt an `ROUNDS_META`/`CUSTOM_STEPPER_META.rounds`. Deren Sekunden
  bleiben immer fest, weil sie das eigentliche, forschungsbasierte oder
  namensgebende Protokoll sind (4-7-8 ist per Definition 4-7-8, die
  Physiological-Sigh-Zeiten kommen aus der Stanford-Studie, Coherent
  Breathing ist auf die Resonanzfrequenz kalibriert) - eine willkürliche
  Sekundenänderung würde die Technik entweder falsch benennen oder ihre
  Evidenzbasis verlassen.

Kein eigenes Session-Datenmodell, keine Glättung über mehrere Sessions -
nur ein direkter Nudge fürs nächste Mal, über dieselben Werte, die auch die
Home-Karten-Stepper/der Custom-Editor schon bedienen.

## Kurse/Programme (Stage 5) - Brainstorm, noch nicht gebaut

Ideen für spätere geführte Mehrtages-/Mehr-Techniken-Programme, gesammelt
aber bewusst noch nicht implementiert:

- **Struktur**: ein Programm ist eine Sequenz aus mehreren Technik-Sessions
  (ggf. über mehrere Tage), keine neue Zeit-Engine - jede Etappe ist einfach
  ein Aufruf von `resolveTechnique(id)` mit bestimmten Rundenzahlen,
  hintereinander statt einzeln vom Nutzer gestartet.
- **Kandidaten für Programme**: "5 Minuten Reset" (Physiological Sigh →
  Verlängertes Ausatmen), "Einschlafroutine" (Coherent → 4-7-8),
  "Energie-Kickstart" (Bellows Breath → Box Breathing), "7-Tage-Einstieg"
  (jeden Tag eine andere Technik, baut auf dem bestehenden Streak-System
  auf statt es zu ersetzen).
- **Fortschritt**: ein Programm-Fortschritt ist nur eine abgeleitete Sicht
  auf `breathewell.sessions.v1` (welche Etappen wurden an welchem Tag
  abgeschlossen) - kein separates Datenmodell nötig, dieselbe Konvention wie
  bei Streak/History.
- **Offene Frage für später**: ob Programme optionale Sprachführung
  brauchen (dann erst nach Stage "Audio" sinnvoll) oder rein mit Text/Visuals
  auskommen wie der Rest der App.

## Bewusst zurückgestellt

Audio-Cues/Sprachführung, geführte Programme/Kurse (siehe Brainstorm oben),
ein Technik-Builder über die vier Zahlenfelder hinaus, Wim Hof (das deckt
ice-breath ab).
