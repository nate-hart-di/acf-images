# ACF Images Brownfield Architecture Document

## Introduction

This document captures the CURRENT STATE of the **acf-images** project - a bash-based utility for downloading and processing images from WordPress ACF (Advanced Custom Fields) HTML exports. This serves as a reference for understanding the existing implementation and planned enhancements.

### Document Scope

Comprehensive documentation of the entire system, including existing functionality and planned improvements.

### Change Log

| Date       | Version | Description                 | Author      |
| ---------- | ------- | --------------------------- | ----------- |
| 2025-10-02 | 1.0     | Initial brownfield analysis | BMad Master |

## Quick Reference - Key Files and Entry Points

### Critical Files for Understanding the System

- **Main Script**: `download_images.sh` - Core image downloading and processing logic
- **Setup Script**: `setup_acf_downloader.sh` - Installation and dependency management
- **Documentation**: `README_ACF_SETUP.md` - User-facing setup and usage instructions
- **Configuration**: `.gitignore` - Git tracking exclusions

### Directory Structure

```
acf-images/
├── download_images.sh          # Main executable script
├── setup_acf_downloader.sh     # Setup and installation script
├── README_ACF_SETUP.md         # User documentation
├── .gitignore                  # Git exclusions
├── .bmad-core/                 # BMad-Method framework files
├── logs/                       # Chronological execution logs (YYYYMMDD-HHMMSS_slug.log)
├── output/                     # Downloaded images organized by slug/section
├── processed/                  # Archive of processed HTML files
├── web-bundles/                # BMad web UI bundles
└── *.html                      # Input HTML files (processed then archived)
```

## High Level Architecture

### Technical Summary

**ACF Images** is a command-line bash utility designed specifically for Dealer Inspire developers to extract and download images from WordPress ACF HTML exports. It intelligently handles WordPress-generated image variations, attempts to download full-resolution originals, and organizes output by ACF field structure.

### Actual Tech Stack

| Category        | Technology      | Version | Notes                                      |
| --------------- | --------------- | ------- | ------------------------------------------ |
| Runtime         | Bash            | 5.x     | macOS zsh environment                      |
| Download Tool   | wget            | Latest  | Installed via Homebrew                     |
| Image Conversion| ffmpeg          | Latest  | Optional - AVIF to PNG conversion          |
| Image Conversion| ImageMagick     | Latest  | Fallback for AVIF conversion               |
| Package Manager | Homebrew        | Latest  | macOS dependency management                |
| Utilities       | grep, sed       | System  | Text processing and pattern matching       |
| Additional Tools| jq, rg          | Latest  | JSON processing and advanced search        |

### Repository Structure Reality Check

- Type: Single repository (standalone utility)
- Package Manager: Homebrew (for system dependencies)
- Notable: Bash-only implementation, no external frameworks

## Source Tree and Module Organization

### Project Structure (Actual)

```text
acf-images/
├── download_images.sh              # Main execution logic (465 lines)
│   ├── Input validation and setup
│   ├── WordPress suffix detection/removal
│   ├── Intelligent filename generation
│   ├── Image download with fallback logic
│   ├── AVIF conversion handling
│   └── Logging and archival
├── setup_acf_downloader.sh        # Installation script (107 lines)
│   ├── Homebrew installation check
│   ├── Dependency installation
│   ├── Directory structure creation
│   └── Shell alias configuration
├── README_ACF_SETUP.md            # User documentation
├── logs/                          # Per-run execution logs
├── output/                        # Downloaded images by slug
│   └── [slug]/                   # Organized by HTML file name
│       ├── images/               # General images (no ACF structure)
│       └── [acf-field-name]/     # ACF field-specific images
├── processed/                     # Archived HTML inputs
└── .bmad-core/                    # BMad-Method framework (optional)
```

### Key Modules and Their Purpose

#### Core Functions (`download_images.sh`)

1. **`get_original_filename()`** (lines 98-123)
   - **Purpose**: Strips WordPress-generated size suffixes from filenames
   - **Current Issue**: Over-aggressive - removes ALL `NNNxNNN` patterns, including custom dimensions
   - **Logic**: Regex pattern matching for dimension suffixes and keywords (thumbnail, medium, scaled, etc.)
   - **Returns**: Cleaned filename for full-resolution download attempt

2. **`slugify()`** (lines 126-135)
   - **Purpose**: Converts arbitrary text to lowercase hyphen-separated slugs
   - **Used For**: Directory names, filename components

3. **`generate_filename()`** (lines 138-173)
   - **Purpose**: Creates intelligent filenames based on order, section, and alt text
   - **Pattern**: `<index>-<section>-<label>.extension`
   - **Example**: `3-hero-image-homepage-banner.jpg`

4. **`download_image()`** (lines 176-240)
   - **Purpose**: Downloads single image with full-size attempt and fallback
   - **Workflow**:
     1. Detect WordPress suffix
     2. Attempt full-size download (suffix removed)
     3. Fallback to original URL if full-size fails
     4. Convert AVIF to PNG if needed
   - **Tracking**: Updates SUCCESS_COUNT or FAIL_COUNT

5. **`download_image_custom()`** (lines 259-325)
   - **Purpose**: Specialized download for ACF field images
   - **Difference**: Uses ACF field name in filename pattern
   - **Same Logic**: Full-size attempt with fallback

6. **`convert_avif_if_needed()`** (lines 243-256)
   - **Purpose**: Automatically converts AVIF images to PNG
   - **Tools**: ffmpeg (preferred) or ImageMagick (fallback)
   - **Action**: Replaces AVIF with PNG, deletes original

#### Installation Functions (`setup_acf_downloader.sh`)

- **Homebrew Management**: Installs Homebrew if missing (macOS only)
- **Dependency Installation**: wget, imagemagick, ffmpeg, jq, rg
- **Directory Creation**: ~/Downloads/acf-images/{output,logs,processed}
- **Alias Setup**: Adds/updates `getimage` alias in ~/.zshrc

## Data Models and APIs

### Input Data Model

**HTML Structure Expected**:
```html
<!-- ACF field structure -->
<div data-name="hero_image">
  <img src="https://example.com/image-500x250.jpg" alt="Hero Banner">
</div>

<!-- General image -->
<img src="https://example.com/photo.jpg" alt="Description">
```

**Extraction Pattern**:
- `data-name` attributes indicate ACF field sections
- `src` attributes with image extensions (png, jpg, jpeg, gif, svg, webp, avif, bmp)
- `alt` attributes for intelligent naming (optional)

### Output Data Model

**Filename Pattern**:
```
<global-index>-<section-slug>-<label-slug>.<extension>

Examples:
- 0-hero-image-homepage-banner.jpg
- 1-product-showcase-red-car.png
- 5-unknown-dealer-logo.svg
```

**Directory Organization**:
```
output/
└── [html-slug]/
    ├── images/              # Images without ACF structure
    │   └── 2-unknown-generic-photo.jpg
    └── [acf-field-name]/    # ACF field-specific images
        └── 0-hero-banner.jpg
```

### Logging API

**Log File Format**: `YYYYMMDD-HHMMSS_slug.log`

**Log Entry Types**:
- Standard output (visible in terminal and log)
- Debug output (only with `DEBUG=1`)
- Success/failure indicators (✓/✗)

## Technical Debt and Known Issues

### Critical Technical Debt

1. **WordPress Suffix Detection - OVERLY AGGRESSIVE** (Priority: HIGH)
   - **Location**: `download_images.sh` lines 106-114
   - **Issue**: Removes ALL dimension patterns (`NNNxNNN`), not just WordPress defaults
   - **Impact**: Incorrectly attempts to download non-existent full-size versions for custom-dimensioned images
   - **Example**: `custom-image-500x250.jpg` → attempts `custom-image.jpg` (doesn't exist)
   - **Correct Behavior**: Only remove WordPress default sizes (150x150, 300x300, 1024x1024, 1536x1536, 2048x2048, scaled, thumbnail, medium, large)
   - **Fix Required**: Whitelist of WordPress default dimensions instead of regex catch-all

2. **No ImageOptim Integration** (Priority: MEDIUM)
   - **Current Workflow**: Manual drag-and-drop to ImageOptim after completion
   - **Enhancement**: Automatically run ImageOptim CLI on output directory when processing completes
   - **Benefit**: Streamlined workflow, consistent optimization

3. **AVIF Conversion Dependencies** (Priority: LOW)
   - **Issue**: Requires ffmpeg OR ImageMagick for AVIF support
   - **Current**: Silently skips if neither installed
   - **Better**: Warn user more prominently, suggest installation

### Workarounds and Gotchas

- **HTML File Location**: Script only processes FIRST .html file in ~/Downloads/acf-images/
- **ACF Field Detection**: Only recognizes `data-name` attributes ending with `_image` or containing `image`
- **Alt Text Search**: Looks up to 3 lines ahead if alt attribute not on same line as src
- **Duplicate Index Preservation**: WordPress duplicates like `-500x250-2` become `-2` after suffix removal

## Integration Points and External Dependencies

### External Services

| Service | Purpose          | Integration Type | Key Files              |
| ------- | ---------------- | ---------------- | ---------------------- |
| None    | Standalone tool  | N/A              | N/A                    |

### External Tools

| Tool        | Purpose                 | Required | Fallback                     |
| ----------- | ----------------------- | -------- | ---------------------------- |
| wget        | HTTP downloads          | YES      | None - exits if missing      |
| ffmpeg      | AVIF → PNG conversion   | NO       | ImageMagick                  |
| ImageMagick | AVIF → PNG conversion   | NO       | Skip conversion              |
| grep/sed    | Text processing         | YES      | System built-ins (always available) |

### Internal Integration Points

- **Shell Alias**: `getimage` → `~/Downloads/acf-images/download_images.sh`
- **Directory Dependencies**: Expects ~/Downloads/acf-images/ structure
- **macOS Integration**: Uses `open` command to reveal output folder

## Development and Deployment

### Local Development Setup

1. **Prerequisites**:
   - macOS (script currently macOS-only due to Homebrew)
   - Zsh shell (default on modern macOS)

2. **Setup Steps**:
   ```bash
   # Clone/download repository
   cd acf-images

   # Run setup script
   ./setup_acf_downloader.sh

   # Load alias
   source ~/.zshrc

   # Test
   getimage
   ```

3. **Required Environment**:
   - Writable ~/Downloads directory
   - Internet connection for wget downloads
   - Terminal with prompt interaction support

### Usage Workflow

1. **Prepare Input**: Place HTML export in ~/Downloads/acf-images/
2. **Execute**: Run `getimage` (or `DEBUG=1 getimage` for verbose output)
3. **Review Output**: Check terminal for success/failure counts
4. **Access Images**: Output directory auto-opens on macOS
5. **Manual Optimization**: Drag output folder to ImageOptim (current workflow)
6. **Archive Decision**: Choose to keep or remove original HTML file

### Build and Deployment Process

- **Build Command**: N/A (bash scripts, no compilation)
- **Deployment**: Copy scripts to ~/Downloads/acf-images/, set executable permissions
- **Installation**: `./setup_acf_downloader.sh` handles full setup
- **Updates**: Re-run setup script to update scripts in place

## Testing Reality

### Current Test Coverage

- Unit Tests: 0% (none exist)
- Integration Tests: Manual testing only
- E2E Tests: None
- Manual Testing: Primary QA method (developer usage on real HTML exports)

### Running Tests

```bash
# No automated tests currently
# Manual testing workflow:
DEBUG=1 getimage  # Run with debug output
# Verify logs/ output for correctness
# Check output/ for expected images
```

## Planned Enhancements

### 1. Fix WordPress Suffix Detection (HIGH PRIORITY)

**Problem**: Current regex removes ALL dimension patterns, not just WordPress defaults.

**Files Affected**:
- `download_images.sh` lines 106-114 (`get_original_filename` function)

**Solution Approach**:
- Create whitelist of WordPress default dimensions
- Check against whitelist before removal
- Preserve custom dimensions in filenames

**WordPress Default Sizes** (to remove):
- `-150x150` (thumbnail)
- `-300x225`, `-300x300` (medium)
- `-768xNNN` (medium_large)
- `-1024xNNN` (large)
- `-1536x1536`, `-2048x2048` (WordPress 4.4+ large sizes)
- `-scaled` (WordPress 5.3+ big image threshold)

### 2. ImageOptim CLI Integration (MEDIUM PRIORITY)

**Enhancement**: Automatically optimize downloaded images using ImageOptim CLI.

**Files Affected**:
- `download_images.sh` (add post-processing step before final summary)
- `setup_acf_downloader.sh` (install imageoptim-cli via Homebrew)

**New Files/Modules Needed**:
- None (modify existing files)

**Integration Approach**:
```bash
# After line 417 (after AVIF conversion, before opening directory)
if command -v imageoptim > /dev/null 2>&1; then
  print "Optimizing images with ImageOptim..."
  imageoptim "$BASE_DIR"
  print "  Optimization complete"
else
  print "  Note: ImageOptim CLI not installed. Install with: brew install imageoptim-cli"
fi
```

**Setup Script Changes**:
- Add `imageoptim-cli` to REQUIRED_TOOLS array
- Install via Homebrew during setup

## Appendix - Useful Commands and Scripts

### Frequently Used Commands

```bash
getimage              # Process first HTML file in ~/Downloads/acf-images/
DEBUG=1 getimage      # Verbose output with debug information
open ~/Downloads/acf-images/output/  # View all output folders
```

### Debugging and Troubleshooting

- **Logs**: Check `~/Downloads/acf-images/logs/` for timestamped logs
- **Debug Mode**: Set `DEBUG=1` for verbose logging
- **Common Issues**:
  - "No HTML files found" → Place .html file in ~/Downloads/acf-images/
  - "No images found" → HTML may not contain valid image src attributes
  - "wget not found" → Run setup script: `./setup_acf_downloader.sh`
  - "Alias not found" → Run `source ~/.zshrc` or restart terminal

### Analyzing Logs

```bash
# View latest log
tail -f ~/Downloads/acf-images/logs/$(ls -t ~/Downloads/acf-images/logs | head -n1)

# Search logs for failures
grep "✗" ~/Downloads/acf-images/logs/*.log

# Count total downloads across all runs
grep "✓" ~/Downloads/acf-images/logs/*.log | wc -l
```

### Shell Alias Management

The `getimage` alias is defined in `~/.zshrc`:
```bash
alias getimage="[[ -f $HOME/Downloads/acf-images/download_images.sh ]] && $HOME/Downloads/acf-images/download_images.sh || echo 'getimage script not found'"
```

To modify or remove:
```bash
# Edit alias
vim ~/.zshrc  # Search for "getimage"

# Remove alias
sed -i '' '/getimage/d' ~/.zshrc

# Reload
source ~/.zshrc
```

## Use Case: Dealer Inspire Workflow

**Target Audience**: Dealer Inspire developers working with WordPress sites

**Typical Scenario**:
1. Export ACF field group data as HTML from WordPress admin
2. Place HTML file in ~/Downloads/acf-images/
3. Run `getimage` to batch download all images
4. Images are organized by ACF field structure
5. Full-resolution originals attempted when WordPress thumbnails detected
6. Drag output folder to ImageOptim for compression (soon automatic)
7. Use optimized images in development/design work

**Key Benefits**:
- Preserves image order from HTML document
- Intelligent naming based on context and alt text
- Automatic WordPress thumbnail → full-size resolution
- Organized output structure matching ACF fields
- Chronological logs for auditing downloads
- Archived HTML inputs for reference

## Next Steps for Development

1. ✅ **Documentation Complete** - This brownfield architecture document created
2. ⏳ **Fix WordPress Suffix Detection** - Implement whitelist-based approach
3. ⏳ **Add ImageOptim Integration** - Automatic optimization after downloads
4. ⏳ **Setup Git Repository** - Initialize version control with proper .gitignore
5. 🔮 **Future Enhancements**:
   - Support for URL input (download from live websites)
   - Parallel downloads for performance
   - Configuration file for custom WordPress sizes
   - Linux/Windows compatibility (remove macOS-specific dependencies)
