# jellyfin-theme-downloader

Automatically downloads theme songs for every movie and TV show in your Jellyfin library. Places a `theme.mp3` in each media folder, which Jellyfin picks up natively. All themes are volume-normalised to EBU R128 so nothing blasts louder than anything else.

---

## How it works

1. Searches YouTube for every movie/show folder that doesn't already have a `theme.mp3`
2. Prints a numbered table of what it found so you can review before downloading
3. Asks which entries to skip (e.g. documentaries, wrong results)
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

---

## Usage

**1. Edit the paths at the top of the script to match your setup:**
```bash
MOVIES_DIR="/media/movies"
TV_DIR="/media/tv"
```

**2. Run it:**
```bash
bash jellyfin-theme-downloader.sh
```

**3. Review the table**, enter any numbers you want to skip, press Enter.

**4. Enable theme music in Jellyfin:**
Go to each user's settings → Display → enable **Theme Music**.

---

## Configuration

| Variable | Default | Description |
|:--|:--|:--|
| `MOVIES_DIR` | `/media/movies` | Path to your movies folder |
| `TV_DIR` | `/media/tv` | Path to your TV shows folder |
| `TRIM_SECONDS` | `90` | How many seconds to trim each theme to |
| `TARGET_LUFS` | `-14` | Loudness target (EBU R128, matches streaming platforms) |

---

## Notes

- Folder names don't need to be clean — the script strips resolution tags, codec names, release groups, and season markers automatically (e.g. `Blade Runner 2049 (2017) [2160p] [4K] [BluRay]` → `Blade Runner 2049`)
- Results over 10 minutes are flagged with ⚠ in the preview table — these are usually full scores or documentaries rather than a theme
- The script tries to find a result under 10 minutes first (two attempts), then falls back to whatever YouTube returns if nothing shorter is found
- yt-dlp should be updated occasionally as YouTube changes — run the install command again to get the latest version