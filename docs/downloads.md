# Shelv Desktop Downloads & Offline Mode

Downloads let you save music from your Navidrome server directly to your Mac so you can listen without a network connection. Once songs are downloaded, you can switch Shelv into Offline Mode — the app then plays exclusively from your local library without attempting any server requests.

---

## Enabling the feature

Downloads are disabled by default. Enable them in **Settings → Downloads**. Once enabled, download buttons appear throughout the app — on album and artist detail pages, in context menus, and the Downloads sidebar entry becomes active. The Offline Mode menu item (View → Offline Mode) also becomes available.

---

## Downloading music

### Albums and artists

Every album detail page has a download button. Clicking it queues all songs in the album. Once all songs are downloaded, the button changes to a delete option so you can free up the storage again.

From the Artists view, you can download or delete an entire artist's discography at once. Shelv fetches all albums for the artist first, then queues all songs.

Download badges appear on album covers throughout the app:
- A **checkmark** means all songs in the album are downloaded.
- A **partial bar** means some songs are downloaded, but not all.

### Bulk download

Settings → Downloads → **Bulk Download** queues your entire library for download in one step. Shelv prioritises which songs to download first based on what you actually listen to:

1. Albums you play most frequently
2. Albums you played most recently
3. Starred / favourited items
4. Everything else, alphabetically

A configurable storage limit (default: 10 GB) acts as a ceiling. Once the limit is reached, Shelv stops queuing new songs — already-queued downloads finish normally.

### Download progress

While a batch is in progress, a progress bar appears at the bottom of the sidebar showing how many songs have completed out of the total and a cancel button. Individual downloads can also be cancelled from the Downloads tab.

Downloads run in the background — you can switch to other apps and they will continue. Completed or in-flight downloads are resumed automatically if the app is restarted mid-batch.

---

## Offline Mode

Switch into Offline Mode via **View → Offline Mode** in the menu bar (requires Downloads to be enabled). In Offline Mode:

- All playback comes from the local download database — no network requests are made
- The library view shows only downloaded albums and artists
- Sort options that require server data (Most Played, Recently Added) are hidden; albums and artists can be sorted by Name or Year
- Discover sections that rely on server data are hidden

Exit Offline Mode the same way to reconnect to the server and resume normal streaming. Shelv does not automatically leave Offline Mode when a connection becomes available.

---

## Transcoding

By default, Shelv requests audio from your Navidrome server in its original format (`raw`). If your server or connection can't handle lossless files well, you can enable transcoding via **Playback → Transcoding Settings** in the menu bar.

Shelv applies separate policies for three situations:

| Situation | What it controls |
|-----------|-----------------|
| **Wi-Fi streaming** | Format and bitrate when streaming over Wi-Fi |
| **Ethernet / other streaming** | Format and bitrate when streaming over a wired or unrecognised connection |
| **Downloads** | Format and bitrate when saving songs to your Mac |

For each situation you can choose:
- **Format** — `raw` (original file, no re-encoding), `mp3`, or `opus`
- **Bitrate** — the target bitrate for the chosen format (only relevant if the format is not `raw`)

Setting the download format to something other than `raw` is useful if you want to save storage — a 192 kbps MP3 takes significantly less space than a lossless FLAC file.

Transcoding requires your Navidrome server to support it. If the server doesn't support the chosen format, Shelv falls back to `raw` automatically.

---

## Storage management

The Downloads tab shows:
- Total number of downloaded songs
- Total storage used by downloads
- A breakdown by artist and by album

Individual albums and artists can be deleted from the Downloads tab or from their detail pages. To clear all downloads at once, use **Settings → Downloads → Delete All Downloads**.

---

## Settings reference

| Setting | Description |
|---------|-------------|
| Enable Downloads | Master switch. When off, no download UI is shown anywhere in the app, and the Offline Mode menu item is disabled. |
| Offline Mode | When on, Shelv plays only from local downloads and hides all server-dependent UI. Accessible via View → Offline Mode (requires Downloads to be enabled). |
| Storage limit | Maximum storage Shelv will use for the bulk download queue. Songs already queued finish even if the limit is reached mid-batch. |
| Enable Transcoding | When off, all streams and downloads use the original file format from the server. Accessible via Playback → Transcoding Settings. |
| Wi-Fi format / bitrate | Codec and bitrate used when streaming over Wi-Fi (if transcoding is on). |
| Cellular / other format / bitrate | Codec and bitrate used for other network types (if transcoding is on). |
| Download format / bitrate | Codec and bitrate used when saving songs to the device (if transcoding is on). |
