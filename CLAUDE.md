# Breathe Well

Offline Android-App mit mehreren Atemtechniken (Box Breathing, 4-7-8,
Coherent Breathing, Custom), reine Web-App in einer Datei, die per
[apk-builder](../apk-builder) zur APK wird. Details zu Technik-Engine,
Datenmodell und Streak-Logik stehen in [README.md](README.md) - dort
nachlesen statt hier duplizieren.

## Build & Test

Kein Bundler, kein Build-Step für die Web-App selbst - `web/index.html`
ist direkt per `file://` im Browser lauffähig und dort auch primär zu
testen (Technik wechseln, Session-Ablauf pro Technik, Custom-Editor,
Settings, Verlauf, Persistenz nach Reload). `?fast=1` an die URL anhängen,
um alle Zeit-Konstanten durch 10 zu teilen und schnell durchzuklicken.

APK bauen - **nicht** direkt `apk-builder\new-app.ps1`/`build-apk.ps1`
aufrufen, sondern immer über den eigenen Wrapper, der Portrait-Lock und
Keep-Screen-On nachpatcht (apk-builder unterstützt beides nicht nativ, und
`apps\BreatheWell` wird bei jedem `-Force`-Lauf komplett neu generiert):

```powershell
cd "D:\claude code projects\breathe-well"
.\build.ps1                              # Debug-APK
.\build.ps1 -Release                     # signierte Release-APK
.\build.ps1 -Release -Install            # + adb install auf verbundenes Gerät
.\build.ps1 -VersionName "1.1" -VersionCode 2 -Release   # bei jedem Release hochzählen
```

Was sich nur auf dem echten Gerät (Pixel 11 Pro) verifizieren lässt, nicht
im Desktop-Browser: ob der Bildschirm während einer echten Session wach
bleibt, WebView-Force-Dark-Verhalten, Portrait-Lock, Zurück-Taste/-Wischgeste
während einer aktiven Session (muss den Abbrechen-Dialog öffnen statt die
App zu schließen), sowie die tägliche Erinnerung (Berechtigungsdialog beim
ersten Anschalten, Benachrichtigung erscheint zur eingestellten Zeit auch
bei geschlossener App, übersteht einen Geräte-Neustart).

## Konventionen

- Alles in `web/index.html` (HTML+CSS+JS inline), kein Framework, keine
  externen Abhängigkeiten - muss offline funktionieren.
- `icon.xml` liegt bewusst **neben** `web/`, nicht darin.
- localStorage-Keys sind versioniert und namespaced (`breathewell.settings.v1`,
  `breathewell.sessions.v1`, ...) - bei einer Schemaänderung neue
  Versionsnummer statt stillschweigender Migration.
- Nur `finishSession()` schreibt einen Session-Record - `cancelSession()`
  nie. Die Streak-Logik baut genau darauf auf (siehe README).
- Neue Atemtechnik hinzufügen: nur ein Eintrag in `TECHNIQUES` (Sekunden je
  Phase + Default-Rundenzahl) plus die zugehörigen Home-Karte/Strings im
  Markup - die Session-Engine selbst braucht keine technik-spezifische
  Verzweigung.
- Harter Anspruch: kein Netzwerkzugriff, keine Gerätedaten außer dem, was
  die App selbst braucht. `new-app.ps1` wird ohne `-Online` aufgerufen.
- Kein Audio bisher (bewusst zurückgestellt, siehe README) - kein
  WebGL für den Pacer (siehe [hopper](../hopper): auf echtem Gerät stark
  geruckelt trotz sauberem Desktop-Test).
- Die Erinnerungs-Java-Klassen liegen als echte Quelldateien unter
  `android-src/*.java` (nicht als PowerShell-String-Patch) und werden von
  `build.ps1` unverändert ins generierte Projekt kopiert - bei Änderungen
  dort direkt editieren, nicht in `build.ps1`.

## Aktueller Stand

Siehe "Aktueller Stand" in [README.md](README.md).
