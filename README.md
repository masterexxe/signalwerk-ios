# Signalwerk für iPhone und iPad

Die App zum Signalwerk-Dashboard: Spenden und Sub-Bombs annehmen oder blockieren, Sounds im
OBS-Widget abspielen, Texte vorlesen lassen, den Twitch-Chat lesen und moderieren, die Notbremse
ziehen – am iPad als Pult mit allem auf einem Bildschirm, am iPhone mit Reitern.

Die App spricht mit der App-Schnittstelle des Dashboards (`/api/app/v1`, ab Signalwerk 2.5.0).
Ohne Server zeigt **Demo ansehen** die App mit Beispieldaten.

## Anmelden

Adresse des Dashboards eingeben (`dashboard.signalwerk.live`) und **Anmelden** tippen. Es öffnet
sich die Anmeldeseite des Dashboards (Team-Zugang oder Twitch); danach **Verbinden**. Das Gerät
bekommt einen eigenen Zugang, der im Schlüsselbund liegt. Abmelden geht in der App unter
Einstellungen und im Dashboard unter Einstellungen → Team → App-Geräte.

## Arbeitsbereich

Startansicht auf iPhone und iPad: oben der Twitch-Player des Kanals (wie im Arbeitsbereich des
Dashboards), darunter die Reiter Spenden, Sounds, TTS und Live-Voice. Der Player lässt sich
einklappen, der Ton läuft dann weiter; am iPhone im Querformat füllt er den Bildschirm. Während
Live-Voice ist sein Ton aus, damit das Mikrofon den Stream-Ton nicht wieder aufnimmt.

**Bei Twitch anmelden** (Menü über dem Player oder Einstellungen → Twitch im Player): Die
Anmeldeseite von twitch.tv öffnet sich in der App, danach lädt der Player mit dem Konto. Twitch
zeigt dann dieselbe Werbung wie auf twitch.tv; wer dort angemeldet keine sieht, sieht auch im
Player keine. Der Player läuft dafür als eigene Seite von `player.twitch.tv` (wie das
Popout-Fenster von Twitch) und nicht eingebettet: Eingebettete Seiten bekommen unter iOS keine
Cookies von twitch.tv. Die Anmeldung bleibt auf dem Gerät; abmelden geht im selben Menü.

## Mitteilungen, Live-Voice, Kurzbefehle

- **Mitteilungen:** In den Einstellungen der App einschalten. Bei jeder Spende oder Sub-Bomb, die
  auf Entscheidung wartet, kommt eine Mitteilung mit **Annehmen** und **Blockieren**. Dafür
  braucht das Dashboard den Push-Schlüssel von Apple in der `.env` (README des Dashboards,
  „Mitteilungen einrichten“).
- **Live-Voice** über das Mikrofon des Geräts, derselbe Weg wie im Browser: über den Alert-Dienst
  ins OBS-Widget, 20-ms-Rahmen mit 24 kHz. Beim Wechsel in den Hintergrund endet sie.
- **Kurzbefehle und Siri:** „Notbremse in Signalwerk“, „Was wartet in Signalwerk“, „Sound in
  Signalwerk abspielen“, Test-Ton, Widget neu laden. Die Notbremse lässt sich auf die
  Aktionstaste legen.

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `SignalwerkKit/` | Kern ohne Oberfläche: Datenmodelle, Schnittstelle, Live-Ereignisse (SSE), Chat über Socket.IO, Demo. Tests mit `swift test`. |
| `Signalwerk/` | Die App (SwiftUI, iOS 17+): Anmeldung, Pult, Spenden, Sounds, Sprache, Chat, Übersicht, Statistik, Einstellungen. |
| `SignalwerkUITests/` | Rundgang durch die Demo auf iPhone und iPad, mit Bildern. |
| `project.yml` | Xcode-Projekt für [XcodeGen](https://github.com/yonaskolb/XcodeGen). |
| `.github/workflows/ios.yml` | Cloud-Build auf macOS: bauen, testen, Bilder, TestFlight. |

## Cloud-Build

Jeder Push auf `main` baut die App und testet sie auf iPhone- und iPad-Simulator. Ergebnis,
Fehler und Bilder liegen danach im Zweig `ci-results` (immer der letzte Lauf).

Zu TestFlight: unter **Actions → iOS → Run workflow** den Haken **Danach zu TestFlight
hochladen** setzen, oder `[testflight]` in die Commit-Nachricht schreiben. Dafür braucht das
Repo diese Secrets (Settings → Secrets and variables → Actions):

| Secret | Inhalt |
| --- | --- |
| `APPLE_TEAM_ID` | Team-ID aus developer.apple.com → Membership details |
| `ASC_KEY_ID` | Schlüssel-ID des App-Store-Connect-API-Schlüssels (Rolle Admin) |
| `ASC_ISSUER_ID` | Issuer ID von derselben Seite |
| `ASC_KEY_P8` | Inhalt der `.p8`-Datei dieses Schlüssels |

Schlüssel gehören nur in die Secrets, nie in den Code.

## Lokal mit Xcode

```sh
brew install xcodegen
xcodegen generate
open Signalwerk.xcodeproj
```
