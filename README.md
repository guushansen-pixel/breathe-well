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
eigenen `build.ps1`-Wrapper, der nach dem Erzeugen des Projekts zwei Dinge
nachpatcht, die apk-builder selbst nicht kann:

- **Portrait-Lock** (`android:screenOrientation="portrait"` im Manifest) -
  eine Atem-Session soll bei Drehung nicht neu aufgebaut werden.
- **Bildschirm bleibt während der Session wach**
  (`FLAG_KEEP_SCREEN_ON` in `MainActivity.onCreate`) - braucht anders als
  `WAKE_LOCK` keine Manifest-Permission. Zusätzlich fragt die Web-App selbst
  per `navigator.wakeLock` einen Screen-Wake-Lock an (Backup, falls der
  native Flag aus irgendeinem Grund nicht greift).

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
Rundenzahl). Vier Phasen-Slots in fester Reihenfolge -
`inhale → hold1 → exhale → hold2` - jede mit `seconds: 0` überspringbar:

- **Box Breathing**: 4-4-4-4.
- **4-7-8**: 4s ein / 7s halten / 8s aus (kein zweiter Hold).
- **Coherent Breathing**: 5.5s ein / 5.5s aus (keine Holds).
- **Eigenes Muster**: alle vier Werte + Rundenzahl frei einstellbar
  (`settings.customPattern`).

`resolveTechnique(id)` löst das auf ein Phasen-Array auf; die
Session-Engine (`startSession`/`tickActive`/`advancePhase`) kennt keine
technik-spezifischen Fälle, sondern läuft nur die Phasenliste ab - eine neue
Technik braucht später nur einen neuen `TECHNIQUES`-Eintrag, keine neue
Engine-Logik.

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

## Streak

Kalendertagbasiert (`dayKey()` + sortierte Menge distinkter Tage), DST-sicher
über Tages-Arithmetik statt roher Millisekunden-Differenzen - identisch zu
ice-breaths Implementierung.

## Aktueller Stand (Stage 1)

Vier Techniken (Box, 4-7-8, Coherent, Custom), rein visueller Pacer ohne
Audio, Verlauf mit Streak + Technik-Breakdown, Theme
System/Hell/Dunkel. Noch nicht auf dem Pixel 11 Pro geräte-getestet -
nächster Schritt: Release-APK bauen und die Geräte-Checkliste (Portrait-Lock,
Keep-Screen-On über volle Session-Dauer, Android-Zurück während aktiver
Session, Light/Dark-Darstellung) durchgehen.

## Bewusst zurückgestellt

Audio-Cues/Sprachführung, geführte Programme/Kurse, ein Technik-Builder über
die vier Zahlenfelder hinaus, Reminders/Benachrichtigungen, weitere
Techniken über das Kernset hinaus, Wim Hof (das deckt ice-breath ab),
Vibration (kein Bedarf angemeldet, VIBRATE-Permission ist durch das
apk-builder-Template ohnehin gesetzt, aber ungenutzt).
