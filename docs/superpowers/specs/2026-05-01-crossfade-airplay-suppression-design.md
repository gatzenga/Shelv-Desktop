# Crossfade über AirPlay sauber unterdrücken (macOS)

## Problem

Bei aktiviertem Crossfade (z. B. 10 s) bricht der Song über AirPlay (Apple TV, Sonos) abrupt 10 s vor dem Ende ab und der nächste Song startet hart. Gapless funktioniert dagegen sauber, ebenso die Now-Playing-Anzeige (Cover, Titel, Künstler).

Ursache: Der `CrossfadeEngine` startet beim Fade einen zweiten `AVQueuePlayer` parallel. Über AirPlay sendet macOS einen einzelnen gepufferten Stream — Sonos und ältere Apple-TV-Geräte droppen beim Player-Wechsel den ersten Stream hart, statt zu mischen. Apple Music selbst crossfadet aus demselben Grund nicht über AirPlay.

Die bestehende Detection (`isAirPlayRouteActive` in `AudioPlayerService.swift:871–906`) prüft nur `kAudioDevicePropertyTransportType` des System-Default-Output-Device. Sie greift bei diesem User nicht zuverlässig.

## Ziel

Bei AirPlay-Routen wird Crossfade still übersprungen — der Song läuft komplett zu Ende, der nächste startet danach (wie ohne Crossfade-Toggle). Gapless, Now-Playing-Cover und Titel bleiben unverändert. Kein Video-Vollbild auf Apple TV. Apple-TV-Bedienung darf den Stream nicht unterbrechen.

## Design

### Detection härten

`refreshAirPlayRouteState()` erweitert um zwei zusätzliche Signale:

1. **Device-Name-Heuristik** als Fallback: `kAudioObjectPropertyName` des Default-Output-Device lesen. Strings, die `AirPlay`, `Apple TV`, `HomePod`, `Sonos` (case-insensitive) enthalten, werden als AirPlay-Route gewertet.
2. **Erweiterte Transport-Blacklist**: explizite Behandlung von `kAudioDeviceTransportTypeAirPlay` und `kAudioDeviceTransportTypeVirtual` (statt nur Whitelist).

Logik: Route gilt als „AirPlay-incompatible", wenn **eines** der Signale anschlägt (Transport-Whitelist-Miss ODER Transport-Blacklist-Hit ODER Name-Match).

### Defensiver Re-Check vor Crossfade-Trigger

In `checkCrossfadeTrigger`, **direkt vor** dem `guard !isCrossfadeIncompatibleRoute`-Check, einmal `refreshAirPlayRouteState()` synchron aufrufen. Damit hängt das Verhalten nicht mehr daran, ob der CoreAudio-Property-Listener rechtzeitig gefeuert hat.

### Verhalten bei AirPlay-Route

- Crossfade-Trigger: kompletter Skip (return). Song läuft natürlich zu Ende, dann normaler `next()`.
- Gapless-Pfad bleibt **aktiv** — der ist über AirPlay unproblematisch (`AVQueuePlayer` mit präladenem `insert(after:)`).
- Wenn der User Crossfade _und_ Gapless gleichzeitig aktiviert hat: bei AirPlay-Route fällt Crossfade weg, der Gapless-Pfad wird als Fallback aktiv. Dafür im Trigger-Code: bei AirPlay den Gapless-Block (Zeilen 828–843) auch dann durchlaufen, wenn `crossfadeEnabled == true` ist. Konkret: nach dem `guard !isCrossfadeIncompatibleRoute` einen zweiten Check, der bei AirPlay ohne Crossfade weiterläuft und stattdessen Gapless triggert.

### Kein Video auf Apple TV

`allowsExternalPlayback = false` in `CrossfadeEngine.init()` (Zeile 48–49) bleibt. `MPNowPlayingInfoCenter` mit Artwork (Zeile 1000, 1075) sorgt für Cover + Titel auf dem Apple TV. Beides ist bereits korrekt verkabelt — keine Änderung nötig, nur dokumentiert dass es so bleiben muss.

### UI-Hinweis (optional)

Im `CrossfadePanel` (PlaybackSettingsWindow) unter dem Toggle eine kleine sekundär-graue Zeile:

> „Bei AirPlay automatisch deaktiviert."

Lokalisiert via `tr()`. Niedrige Priorität — wenn unklar, weglassen.

## Was nicht geändert wird

- `CrossfadeEngine` selbst — keine Pipeline-Umbauten, kein `AVAudioEngine`-Wechsel.
- Now-Playing-Info-Pfad.
- Gapless-Pfad.
- iOS-Code (`/Users/vasco/Repositorys/Shelv`) bleibt unangetastet.

## Akzeptanzkriterien

1. AirPlay zu Apple TV: Song spielt komplett durch, nächster startet ohne abrupten Cut. Cover + Titel auf Apple TV sichtbar.
2. AirPlay zu Sonos: dito.
3. Lokale Wiedergabe (Built-In, USB, Bluetooth, HDMI): Crossfade funktioniert wie bisher.
4. Apple-TV-Fernbedienung (Menu/Back) beendet die App-Session nicht — der Stream läuft weiter, weil kein Video-Routing aktiv ist.
5. Gapless funktioniert über AirPlay weiterhin (auch wenn Crossfade aktiv ist — fällt dann auf Gapless zurück).
