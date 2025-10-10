#!/bin/bash

# ACF Image Downloader Setup Script
# Installs dependencies, prepares directories, and wires up the getimage alias.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERR]${NC} $1"
}

if [[ "$OSTYPE" != "darwin"* ]]; then
  print_error "This setup script is intended for macOS."
  exit 1
fi

# Ensure Homebrew paths are available when launched via Finder
if [ -d "/opt/homebrew/bin" ] && [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
if [ -d "/usr/local/bin" ] && [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
  export PATH="/usr/local/bin:$PATH"
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TARGET_DIR="$HOME/Downloads/acf-images"
DOWNLOAD_SCRIPT="$TARGET_DIR/download_images.sh"

print_status "Starting ACF image downloader setup..."

# Ensure Homebrew
if ! command -v brew >/dev/null 2>&1; then
  print_status "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ $(uname -m) == "arm64" ]]; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  print_success "Homebrew installed."
else
  print_success "Homebrew already installed."
fi

print_status "Making sure Homebrew formulas are up to date..."
brew update

print_status "Ensuring ImageOptim CLI is installed for post-processing..."
brew install imageoptim-cli

# Required packages for the downloader
REQUIRED_TOOLS=(wget imagemagick ffmpeg jq rg)
for tool in "${REQUIRED_TOOLS[@]}"; do
  if brew list "$tool" >/dev/null 2>&1; then
    print_success "$tool already installed."
  else
    print_status "Installing $tool..."
    brew install "$tool"
    print_success "$tool installed."
  fi
done

print_status "Creating directory structure in $TARGET_DIR..."
mkdir -p "$TARGET_DIR" "$TARGET_DIR/output" "$TARGET_DIR/logs" "$TARGET_DIR/processed"
print_success "Directories ready."

if [[ ! -f "$SCRIPT_DIR/download_images.sh" ]]; then
  print_error "download_images.sh not found in $SCRIPT_DIR. Run this script from the repository root."
  exit 1
fi

print_status "Installing the downloader script..."
cp "$SCRIPT_DIR/download_images.sh" "$DOWNLOAD_SCRIPT"
chmod +x "$DOWNLOAD_SCRIPT"
print_success "Installed to $DOWNLOAD_SCRIPT"

# Update or add the getimage function (changed from alias to support URL arguments)
print_status "Adding/updating getimage function in ~/.zshrc..."

# Remove old alias if it exists
if grep -q '^alias getimage=' "$HOME/.zshrc" 2>/dev/null; then
  sed -i '' '/^alias getimage=/d' "$HOME/.zshrc"
fi

# Remove old function if it exists
if grep -q '^getimage()' "$HOME/.zshrc" 2>/dev/null; then
  sed -i '' '/^getimage()/,/^}/d' "$HOME/.zshrc"
  sed -i '' '/^# ACF image downloader$/d' "$HOME/.zshrc"
fi

# Add new function
{
  echo ""
  echo "# ACF image downloader"
  echo 'getimage() {'
  echo '  if [[ -f $HOME/Downloads/acf-images/download_images.sh ]]; then'
  echo '    $HOME/Downloads/acf-images/download_images.sh "$@"'
  echo '  else'
  echo '    echo "getimage script not found"'
  echo '  fi'
  echo '}'
} >> "$HOME/.zshrc"

print_success "Function ready. Run 'source ~/.zshrc' or restart your terminal to load it."

print_status "Setup finished. Next steps:"
echo "  1. Place ACF HTML export files in $TARGET_DIR"
echo "  2. Run: source ~/.zshrc   # or open a new terminal"
echo "  3. Execute: getimage"
echo ""
print_success "Happy downloading!"
