#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/setup_acf_downloader.sh"

if [ ! -f "$TARGET_SCRIPT" ]; then
  echo "Setup script not found at $TARGET_SCRIPT"
  echo "Please keep the .command file next to setup_acf_downloader.sh"
  read -r -p "Press return to exit..." _
  exit 1
fi

# Extend PATH for common Homebrew locations when launched via Finder
if [ -d "/opt/homebrew/bin" ] && [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
  export PATH="/opt/homebrew/bin:$PATH"
fi
if [ -d "/usr/local/bin" ] && [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
  export PATH="/usr/local/bin:$PATH"
fi

"$TARGET_SCRIPT"
STATUS=$?

echo ""
if [ $STATUS -eq 0 ]; then
  echo "Setup completed successfully."
else
  echo "Setup exited with status $STATUS. Review the messages above for details."
fi

read -r -p "Press return to close..." _
exit $STATUS
