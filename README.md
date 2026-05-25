# jellyfin-theme-downloader

Automatically downloads theme songs for every movie and TV show in your Jellyfin library. Places a `theme.mp3` in each media folder, which Jellyfin picks up natively. All themes are volume-normalised to EBU R128 so nothing blasts louder than anything else.

---

## How it works

1. Searches YouTube for every folder that doesn't already have a `theme.mp3`
2. Prints a numbered preview table of what it found — you review before anything downloads
3. Enter any numbers you want to skip (documentaries, wrong results, etc.)
4. Downloads the rest, trimmed to 90 seconds, and normalises the volume

Re-run anytime — folders that already have a `theme.mp3` are skipped automatically.

---

## Requirements

**ffmpeg:**
```bash
apt install ffmpeg -y
```

**yt-dlp:**
```bash
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
  -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp
```

**python3** — used to parse yt-dlp metadata (usually pre-installed):
```bash
apt install python3 -y
```

> **Windows users:** run via [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) — everything works as-is inside a WSL terminal.

---

## Usage

**1. Edit `MEDIA_DIRS` at the top of the script to match your setup** (see Configuration below).

**2. Run it:**
```bash
bash jellyfin-theme-downloader.sh
```

**3. Review the preview table**, enter numbers to skip, press Enter.

**4. Enable theme music in Jellyfin:**
Go to each user's settings → Display → enable **Theme Music**.

---

## Configuration

### Media folders

```bash
MEDIA_DIRS=(
  "/media/movies:movie"
  "/media/tv:tv show"
)
```

Each entry is a folder path and a search label separated by `:`. The label is appended to the title when searching YouTube, followed by `theme song`:

```
"Blade Runner 2049"  +  "movie"    →  "Blade Runner 2049 movie theme song"
"Severance"          +  "tv show"  →  "Severance tv show theme song"
"Attack on Titan"    +  "anime"    →  "Attack on Titan anime theme song"
```

Add, remove, or relabel entries to match your library structure. You can have as many folders as you like, and if a folder doesn't exist it's skipped with a warning.

### Other settings

| Variable | Default | Description |
|:--|:--|:--|
| `TRIM_SECONDS` | `90` | How many seconds to trim each theme to |
| `TARGET_LUFS` | `-14` | Loudness target (EBU R128, matches streaming platforms) |
| `SEARCH_DELAY` | `1` | Seconds between YouTube searches — increase if you hit rate limits |

---

## Notes

- Folder names don't need to be clean — the script automatically strips resolution tags, codec names, release groups, and season markers (e.g. `Blade Runner 2049 (2017) [2160p] [4K] [BluRay] [5.1] [YTS.MX]` → `Blade Runner 2049`)
- Results over 10 minutes are flagged with ⚠ in the preview table — these are usually full scores or documentaries rather than a short theme
- The script tries to find a result under 10 minutes first (two attempts), then falls back to whatever YouTube returns if nothing shorter is found
- Update yt-dlp occasionally as YouTube changes — just re-run the install command to get the latest version