# ACF Image Downloader

Automates downloading high-resolution images from WordPress ACF HTML exports or live URLs. The tooling keeps meaningful file names, records logs per run, and archives every processed HTML input.

## Quick Start

```bash
# From the repository root
./setup_acf_downloader.sh
source ~/.zshrc   # or open a new terminal session

# Option 1: Process HTML file in directory
getimage

# Option 2: Fetch and process from URL
getimage https://example.dealerinspire.com/inventory/new-vehicles
```

## What the Setup Script Does

- Installs Homebrew (if missing) and the required CLI tools: `wget`, `imagemagick`, `ffmpeg`, `jq`, and `rg`.
- Creates `~/Downloads/acf-images/` with the following structure:
  - `output/` – downloaded images grouped by HTML slug and ACF section.
  - `logs/` – per-run logs named `YYYYMMDD-HHMMSS_slug.log` for easy chronological sorting.
  - `processed/` – copies of every HTML file that has been processed.
- Copies `download_images.sh` into that directory and marks it executable.
- Adds/updates a `getimage` alias in your `~/.zshrc` that executes the script.

## Daily Workflow

### Option 1: HTML File Input (Traditional)

1. Drop a WordPress ACF HTML export into `~/Downloads/acf-images/`.
2. Run `getimage`.
3. Review the output shown in the terminal:
   - Success and failure counts.
   - The output directory path.
   - The log file for that run.
4. When prompted, decide whether to keep or delete the original HTML file. Regardless of your answer, a copy is stored (and overwritten on subsequent runs) inside `~/Downloads/acf-images/processed/`.

### Option 2: URL Input (Direct Fetch) - WITH AUTOMATIC AUTHENTICATION

1. **Login to the site in Chrome** (if authentication required)
2. Copy the URL from your browser
3. Run `getimage https://example.com/page-with-images`
4. The script will **automatically**:
   - **Extract your Chrome cookies for the domain** (SSO, OAuth, session cookies - everything!)
   - Fetch the HTML using your authenticated session
   - Download all images using the same authentication
   - Save it with a timestamped filename
   - Process all images as usual
   - Archive the fetched HTML in `processed/`
5. All images are downloaded and optimized automatically.

**🔒 Authentication Support:**
- **Automatic Chrome Cookie Extraction** - No manual cookie export needed!
- **Works with SSO/OAuth** - Login once in Chrome, script uses your session
- **Dev Site Access** - Download from password-protected staging/dev sites
- **Session Persistence** - Images download with same auth as HTML
- **Secure** - Cookies are temporary and never committed to git

**Examples:**
```bash
# Fetch from public site (no auth needed)
getimage https://example.dealerinspire.com/inventory/new-vehicles

# Fetch from SSO-protected dev site (uses your Chrome login automatically)
getimage https://dev-site.dealerinspire.com/media-gallery

# Fetch specific vehicle page (authenticated if needed)
getimage https://staging.dealerinspire.com/new/Honda/2024-Accord

# Fetch from any password-protected site (just login in Chrome first)
getimage https://yoursite.com/admin/gallery
```

**How It Works:**
1. You login to the site in Chrome (SSO, OAuth, whatever)
2. Script automatically extracts session cookies from Chrome's database
3. Cookies are used for both HTML and image downloads
4. Works seamlessly for both public and protected content

## Logging & History

- Logs live in `~/Downloads/acf-images/logs/` and are prefixed with the run timestamp, e.g. `20240930-133500_mysite.log`.
- To inspect the latest log: `tail -f ~/Downloads/acf-images/logs/$(ls -t ~/Downloads/acf-images/logs | head -n1)`.

## Processed HTML Archive

- Every time `getimage` runs, the source HTML is copied to `~/Downloads/acf-images/processed/`.
- If a file with the same name already exists, it is overwritten so the archive always contains the latest version.
- Choosing `n` at the prompt removes the original from `~/Downloads/acf-images/` after the copy is made.

## Notes on Image Naming

- Filenames follow the pattern `<order>-<section>-<alt-or-derived>.extension`, preserving appearance order while staying descriptive.
- WordPress-generated downsized suffixes are intelligently detected and stripped using a whitelist approach:
  - **Removed**: WordPress default sizes (`-150x150`, `-300x300`, `-768xNNN`, `-1024xNNN`, `-1536x1536`, `-2048x2048`, `-scaled`, `-thumbnail`, `-medium`, `-large`)
  - **Preserved**: Custom dimensions (e.g., `-250x188`, `-500x375`) that don't match WordPress defaults
  - When a WordPress suffix is detected, the script attempts to download the full-resolution original, with automatic fallback to the sized version if unavailable.

## Automatic Image Optimization

- Images are automatically optimized using ImageOptim CLI after download (if installed).
- This eliminates the need to manually drag folders to ImageOptim.
- The setup script installs `imageoptim-cli` via Homebrew automatically.

## Troubleshooting

- **Alias not found:** re-run `source ~/.zshrc` or restart your terminal.
- **Missing dependencies:** rerun `./setup_acf_downloader.sh`; it re-installs anything missing.
- **Want to reset:** delete `~/Downloads/acf-images/` and run the setup again.
- **Need logs:** check the `logs/` folder mentioned above; each log mirrors the on-screen output plus debug messages when `DEBUG=1`.

## Optional Flags

- Run `DEBUG=1 getimage` to emit extra diagnostics to both the terminal and the log file.

That’s it—place HTML exports, run `getimage`, and let the script do the rest.
