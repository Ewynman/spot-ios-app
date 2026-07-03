#!/bin/bash

# increment-build-number.sh
# Increments the build number in the Xcode project
#
# Usage: ./scripts/increment-build-number.sh [new-build-number]
#
# If new-build-number is not provided, it will auto-increment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_FILE="Spot.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo -e "${RED}Error: $PROJECT_FILE not found${NC}"
    exit 1
fi

# Get current build number
CURRENT_BUILD=$(grep -m 1 "CURRENT_PROJECT_VERSION = " "$PROJECT_FILE" | sed 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);/\1/')

if [ -z "$CURRENT_BUILD" ]; then
    echo -e "${RED}Error: Could not find CURRENT_PROJECT_VERSION in project file${NC}"
    exit 1
fi

echo -e "${BLUE}Current build number: ${CURRENT_BUILD}${NC}"

# Determine new build number
if [ -n "$1" ]; then
    NEW_BUILD="$1"
    echo -e "${YELLOW}Setting build number to: ${NEW_BUILD}${NC}"
else
    NEW_BUILD=$((CURRENT_BUILD + 1))
    echo -e "${YELLOW}Auto-incrementing to: ${NEW_BUILD}${NC}"
fi

# Create backup
cp "$PROJECT_FILE" "${PROJECT_FILE}.backup"

# Update build number for main app target only (first 2 occurrences)
# This preserves test target build numbers
awk -v new_build="$NEW_BUILD" '
    /CURRENT_PROJECT_VERSION = [0-9]+;/ {
        if (count < 2) {
            sub(/CURRENT_PROJECT_VERSION = [0-9]+;/, "CURRENT_PROJECT_VERSION = " new_build ";")
            count++
        }
    }
    { print }
' "${PROJECT_FILE}.backup" > "$PROJECT_FILE"

# Verify the change
echo ""
echo -e "${BLUE}Updated build numbers in project:${NC}"
grep "CURRENT_PROJECT_VERSION = " "$PROJECT_FILE" | head -4

# Check if git repo
if git rev-parse --git-dir > /dev/null 2>&1; then
    echo ""
    echo -e "${GREEN}✓ Build number updated successfully${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review the changes: git diff $PROJECT_FILE"
    echo "  2. Commit the change: git add $PROJECT_FILE && git commit -m 'Bump build number to $NEW_BUILD'"
    echo "  3. Or restore backup: mv ${PROJECT_FILE}.backup $PROJECT_FILE"
else
    echo -e "${GREEN}✓ Build number updated successfully${NC}"
fi

# Clean up backup if successful
rm -f "${PROJECT_FILE}.backup"

exit 0
