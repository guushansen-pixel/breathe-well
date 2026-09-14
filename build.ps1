<#
.SYNOPSIS
    Baut Breathe Well ueber apk-builder und patcht/kopiert danach alles nach,
    was apk-builder selbst nicht unterstuetzt: Portrait-Lock, Keep-Screen-On,
    einen Predictive-Back-Handler fuer die Zurueck-Wischgeste, und die
    taegliche Erinnerung (AlarmManager + Notification + JS-Bridge).
.DESCRIPTION
    apps\BreatheWell unter apk-builder wird bei jedem Lauf per -Force komplett
    neu aus dem WebView-Template erzeugt (siehe apk-builder\CLAUDE.md) - die
    Patches unten muessen deshalb bei jedem Build erneut angewendet werden.
    Sie sind mit throw-Guards abgesichert: aendert sich das Template von
    apk-builder, bricht der Build laut ab statt still eine unfertige APK zu
    bauen. Die Erinnerungs-Klassen (ReminderScheduler/-Receiver/BootReceiver)
    liegen als eigene .java-Dateien unter android-src\ und werden nur
    hineinkopiert, nicht als String-Patch generiert - lesbarer als alles in
    PowerShell-Strings zu quetschen.
.EXAMPLE
    .\build.ps1 -Release -Install
#>
[CmdletBinding()]
param(
    [string]$VersionName = '1.0',
    [int]$VersionCode = 1,
    [switch]$Release,
    [switch]$Install
)

$ErrorActionPreference = 'Stop'

# javac lehnt eine UTF-8-BOM als "Unzulaessiges Zeichen U+FEFF" ab, und
# Set-Content -Encoding utf8 schreibt in PowerShell 5.1 immer eine BOM -
# deshalb wie new-app.ps1 selbst ueber .NET BOM-frei schreiben.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-TextNoBom {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

$ApkBuilder = "D:\claude code projects\apk-builder"
$PackageId  = "com.daniel.breathewell"
$AppName    = "BreatheWell"
$appDir     = Join-Path $ApkBuilder "apps\$AppName"

& "$ApkBuilder\new-app.ps1" -Name $AppName -PackageId $PackageId `
    -WebRoot "D:\claude code projects\breathe-well\web" `
    -Icon "D:\claude code projects\breathe-well\icon.xml" `
    -IconBackground "#241B45" `
    -VersionName $VersionName -VersionCode $VersionCode -Force

$javaDir = Join-Path $appDir ("app\src\main\java\" + $PackageId.Replace('.', '\'))

# --- Erinnerungs-Klassen hineinkopieren (nicht Teil des apk-builder-Templates) --
Copy-Item "D:\claude code projects\breathe-well\android-src\ReminderScheduler.java" $javaDir -Force
Copy-Item "D:\claude code projects\breathe-well\android-src\ReminderReceiver.java" $javaDir -Force
Copy-Item "D:\claude code projects\breathe-well\android-src\BootReceiver.java" $javaDir -Force

# --- AndroidManifest.xml: Portrait-Lock + Predictive Back + Erinnerung ----
$manifestPath = Join-Path $appDir 'app\src\main\AndroidManifest.xml'
$manifest = Get-Content $manifestPath -Raw

# Patch 1: Portrait-Lock - eine Atem-Session soll das Layout nicht per
# Rotation neu aufbauen.
$launchModeNeedle = 'android:launchMode="singleTop">'
if ($manifest -notmatch [regex]::Escape($launchModeNeedle)) {
    throw "Manifest-Patchziel (launchMode) nicht gefunden - hat sich das apk-builder-Template geaendert?"
}
$manifest = $manifest -replace [regex]::Escape($launchModeNeedle), ('android:launchMode="singleTop"' + "`n            android:screenOrientation=`"portrait`">")

# Patch 2: Predictive Back explizit aktivieren - ab targetSdk 33 ist das
# Verhalten zwar schon Standard, aber nur mit diesem Attribut registriert
# Android unseren OnBackInvokedCallback (siehe MainActivity.java-Patch
# unten) zuverlaessig, statt sich auf einen impliziten Kompatibilitaets-
# Fallback zu verlassen.
$themeNeedle = 'android:theme="@style/AppTheme">'
if ($manifest -notmatch [regex]::Escape($themeNeedle)) {
    throw "Manifest-Patchziel (theme) nicht gefunden - hat sich das apk-builder-Template geaendert?"
}
$manifest = $manifest -replace [regex]::Escape($themeNeedle), ('android:theme="@style/AppTheme"' + "`n        android:enableOnBackInvokedCallback=`"true`">")

# Patch 3: Permissions + Receiver fuer die taegliche Erinnerung.
# POST_NOTIFICATIONS ist eine gefaehrliche Berechtigung (Laufzeit-Dialog,
# ab API 33) - der Dialog wird in MainActivity.java erst ausgeloest, wenn
# der Nutzer die Erinnerung tatsaechlich anschaltet, nicht beim App-Start.
$vibrateNeedle = '<uses-permission android:name="android.permission.VIBRATE" />'
if ($manifest -notmatch [regex]::Escape($vibrateNeedle)) {
    throw "Manifest-Patchziel (VIBRATE) nicht gefunden - hat sich das apk-builder-Template geaendert?"
}
$manifest = $manifest -replace [regex]::Escape($vibrateNeedle), ($vibrateNeedle + "`n    <uses-permission android:name=`"android.permission.POST_NOTIFICATIONS`" />`n    <uses-permission android:name=`"android.permission.RECEIVE_BOOT_COMPLETED`" />")

$activityCloseNeedle = '</activity>'
if ($manifest -notmatch [regex]::Escape($activityCloseNeedle)) {
    throw "Manifest-Patchziel (</activity>) nicht gefunden - hat sich das apk-builder-Template geaendert?"
}
$receiversBlock = $activityCloseNeedle + "`n`n        <receiver android:name=`".ReminderReceiver`" android:exported=`"false`" />`n        <receiver android:name=`".BootReceiver`" android:exported=`"false`">`n            <intent-filter>`n                <action android:name=`"android.intent.action.BOOT_COMPLETED`" />`n            </intent-filter>`n        </receiver>"
$manifest = $manifest -replace [regex]::Escape($activityCloseNeedle), $receiversBlock

Write-TextNoBom -Path $manifestPath -Content $manifest

# --- MainActivity.java: Keep-Screen-On + Predictive Back + Erinnerungs-Bridge --
$mainActivityPath = Join-Path $javaDir 'MainActivity.java'
$java = Get-Content $mainActivityPath -Raw

$importNeedle = 'import android.view.KeyEvent;'
if ($java -notmatch [regex]::Escape($importNeedle)) {
    throw "MainActivity.java Import-Patchziel nicht gefunden - hat sich das apk-builder-Template geaendert?"
}
$newImports = "import android.view.WindowManager;`nimport android.window.OnBackInvokedDispatcher;`nimport android.Manifest;`nimport android.content.pm.PackageManager;`nimport android.webkit.JavascriptInterface;"
$java = $java -replace [regex]::Escape($importNeedle), ($importNeedle + "`n" + $newImports)

# Patch 4: Bildschirm waehrend Session wach halten. FLAG_KEEP_SCREEN_ON
# braucht keine Manifest-Permission (anders als WAKE_LOCK+PowerManager).
$ccNeedle = 'setContentView(webView);'
if ($java -notmatch [regex]::Escape($ccNeedle)) {
    throw "MainActivity.java onCreate-Patchziel nicht gefunden - hat sich das apk-builder-Template geaendert?"
}
$java = $java -replace [regex]::Escape($ccNeedle), ($ccNeedle + "`n`n        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);")

# Patch 5: Zurueck-Wischgeste (Predictive Back). Bei targetSdk 33+ faengt
# onKeyDown/KEYCODE_BACK (unten im Template bereits vorhanden) die Geste des
# modernen Gesture-Nav-Zurueckwischens nicht mehr zuverlaessig ab - ohne
# eigenen OnBackInvokedCallback schliesst die Geste sonst direkt die App,
# statt (wie ein Tastendruck) im WebView zurueckzugehen und damit unseren
# Abbrechen-Dialog waehrend einer aktiven Session auszuloesen.
$keepScreenOnNeedle = 'getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);'
if ($java -notmatch [regex]::Escape($keepScreenOnNeedle)) {
    throw "MainActivity.java Predictive-Back-Patchziel nicht gefunden - Keep-Screen-On-Patch hat nicht wie erwartet gegriffen?"
}
$predictiveBackSnippet = $keepScreenOnNeedle + "`n`n        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {`n            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(`n                    OnBackInvokedDispatcher.PRIORITY_DEFAULT,`n                    () -> {`n                        if (webView.canGoBack()) {`n                            webView.goBack();`n                        } else {`n                            finish();`n                        }`n                    });`n        }"
$java = $java -replace [regex]::Escape($keepScreenOnNeedle), $predictiveBackSnippet

# Patch 6: JS-Bruecke fuer die Erinnerung registrieren. Sicher, weil die
# WebView ausschliesslich das eigene gebuendelte Asset laedt (siehe
# LocalWebViewClient) - kein Fernzugriff, der addJavascriptInterface
# missbrauchen koennte.
$clientNeedle = 'webView.setWebViewClient(new LocalWebViewClient());'
if ($java -notmatch [regex]::Escape($clientNeedle)) {
    throw "MainActivity.java JS-Bridge-Patchziel nicht gefunden - hat sich das apk-builder-Template geaendert?"
}
$java = $java -replace [regex]::Escape($clientNeedle), ("webView.addJavascriptInterface(new ReminderBridge(), `"AndroidReminders`");`n        " + $clientNeedle)

# Patch 7: ReminderBridge-Klasse - setReminder() fragt bei Bedarf einmalig
# die POST_NOTIFICATIONS-Berechtigung an (API 33+) und plant/verwirft ueber
# ReminderScheduler; laeuft in runOnUiThread, weil addJavascriptInterface-
# Methoden auf einem WebView-Hintergrundthread aufgerufen werden.
$localClientNeedle = 'private class LocalWebViewClient extends WebViewClient {'
if ($java -notmatch [regex]::Escape($localClientNeedle)) {
    throw "MainActivity.java ReminderBridge-Patchziel nicht gefunden - hat sich das apk-builder-Template geaendert?"
}
$reminderBridgeClass = "private class ReminderBridge {`n        @JavascriptInterface`n        public void setReminder(final int hour, final int minute) {`n            runOnUiThread(new Runnable() {`n                public void run() {`n                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&`n                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {`n                        requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1001);`n                    }`n                    ReminderScheduler.enable(MainActivity.this, hour, minute);`n                }`n            });`n        }`n`n        @JavascriptInterface`n        public void cancelReminder() {`n            runOnUiThread(new Runnable() {`n                public void run() { ReminderScheduler.disable(MainActivity.this); }`n            });`n        }`n    }`n`n    " + $localClientNeedle
$java = $java -replace [regex]::Escape($localClientNeedle), $reminderBridgeClass

Write-TextNoBom -Path $mainActivityPath -Content $java

Write-Host "  [ok] Patches angewendet (Portrait-Lock, Keep-Screen-On, Predictive Back, Erinnerung)" -ForegroundColor Green

if ($Release -and $Install) {
    & "$ApkBuilder\build-apk.ps1" -App $AppName -Release -Install
} elseif ($Release) {
    & "$ApkBuilder\build-apk.ps1" -App $AppName -Release
} elseif ($Install) {
    & "$ApkBuilder\build-apk.ps1" -App $AppName -Install
} else {
    & "$ApkBuilder\build-apk.ps1" -App $AppName
}
