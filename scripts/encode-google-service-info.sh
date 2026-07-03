#!/bin/bash
#
# encode-google-service-info.sh
#
# Helper script to encode GoogleService-Info.plist for GitHub secrets
#
# Usage:
#   ./scripts/encode-google-service-info.sh /path/to/GoogleService-Info.plist
#
# The base64-encoded string will be copied to your clipboard (macOS) or printed to stdout

set -euo pipefail

PLIST_PATH="${1:-}"

if [ -z "$PLIST_PATH" ]; then
  echo "❌ Error: Please provide the path to GoogleService-Info.plist"
  echo ""
  echo "Usage:"
  echo "  ./scripts/encode-google-service-info.sh /path/to/GoogleService-Info.plist"
  echo ""
  echo "Example:"
  echo "  ./scripts/encode-google-service-info.sh ~/Downloads/GoogleService-Info.plist"
  exit 1
fi

if [ ! -f "$PLIST_PATH" ]; then
  echo "❌ Error: File not found: $PLIST_PATH"
  exit 1
fi

# Verify it's a valid plist
if ! plutil -lint "$PLIST_PATH" > /dev/null 2>&1; then
  echo "❌ Error: $PLIST_PATH is not a valid plist file"
  exit 1
fi

echo "✅ Found valid GoogleService-Info.plist"
echo ""

# Encode to base64
BASE64_STRING=$(base64 -i "$PLIST_PATH")

# Try to copy to clipboard (macOS)
if command -v pbcopy > /dev/null 2>&1; then
  echo "$BASE64_STRING" | pbcopy
  echo "✅ Base64 string copied to clipboard!"
  echo ""
  echo "Next steps:"
  echo "1. Go to GitHub repository: Settings → Secrets and variables → Actions"
  echo "2. Click 'New repository secret'"
  echo "3. Name: GOOGLE_SERVICE_INFO_PLIST_BASE64"
  echo "4. Value: Paste from clipboard (Cmd+V)"
  echo "5. Click 'Add secret'"
else
  # No clipboard available, print to stdout
  echo "✅ Base64 string:"
  echo ""
  echo "$BASE64_STRING"
  echo ""
  echo "Copy the string above and:"
  echo "1. Go to GitHub repository: Settings → Secrets and variables → Actions"
  echo "2. Click 'New repository secret'"
  echo "3. Name: GOOGLE_SERVICE_INFO_PLIST_BASE64"
  echo "4. Value: Paste the base64 string"
  echo "5. Click 'Add secret'"
fi

echo ""
echo "Documentation: docs/engineering/firebase-distribution-setup.md"
