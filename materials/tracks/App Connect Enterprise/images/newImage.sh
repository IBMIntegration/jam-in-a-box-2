#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find the latest screenshot on desktop
LATEST_SCREENSHOT=$(ls -t ~/Desktop/Screenshot*.png 2>/dev/null | head -n 1)

if [ -z "$LATEST_SCREENSHOT" ]; then
  echo "No screenshot found on desktop"
  exit 1
fi

# Find the next available IA number
NEXT_NUM=1
while [ -f "$SCRIPT_DIR/IA$NEXT_NUM.png" ]; do
  ((NEXT_NUM++))
done

# Move the screenshot to the script directory with new name
mv "$LATEST_SCREENSHOT" "$SCRIPT_DIR/IA$NEXT_NUM.png"

# Copy markdown to clipboard
echo "   ![screenshot](images/IA$NEXT_NUM.png)" | pbcopy

echo "Moved screenshot to IA$NEXT_NUM.png and copied markdown to clipboard"
