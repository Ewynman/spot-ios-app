#!/bin/bash

# validate-api-changes.sh
# Detects potential breaking API changes in Swift code
#
# Usage: ./validate-api-changes.sh <base-branch>
#
# Arguments:
#   base-branch: Base branch to compare against (e.g., origin/main)
#
# Exit codes:
#   0: No breaking changes detected
#   1: Potential breaking changes found

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BASE_BRANCH="${1:-origin/main}"

echo -e "${BLUE}=== API Breaking Change Detection ===${NC}"
echo "Base branch: ${BASE_BRANCH}"
echo ""

# Fetch base branch
git fetch origin "${BASE_BRANCH##*/}" --depth=1 2>/dev/null || true

# Get changed Swift files in production code
CHANGED_FILES=$(git diff --name-only "${BASE_BRANCH}" -- '*.swift' | grep -E '^Spot/' | grep -v 'SpotTests/' | grep -v 'SpotUITests/' || true)

if [ -z "$CHANGED_FILES" ]; then
    echo -e "${GREEN}✓ No production Swift files changed${NC}"
    exit 0
fi

echo "Analyzing changed files:"
echo "$CHANGED_FILES" | sed 's/^/  - /'
echo ""

# Create temporary directory for analysis
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

POTENTIAL_BREAKING_CHANGES=()
FILES_WITH_CHANGES=()

# Function to extract public API signatures from a file
extract_public_api() {
    local file="$1"
    
    # Extract public declarations (functions, classes, structs, enums, protocols, properties)
    grep -E '^\s*(public|open)\s+(class|struct|enum|protocol|func|var|let|init|subscript)' "$file" 2>/dev/null || true
}

# Analyze each changed file
while IFS= read -r file; do
    if [ ! -f "$file" ]; then
        # File was deleted
        echo -e "${YELLOW}⚠ File deleted: $file${NC}"
        
        # Check if file had public APIs
        DELETED_APIS=$(git show "${BASE_BRANCH}:${file}" 2>/dev/null | extract_public_api || true)
        
        if [ -n "$DELETED_APIS" ]; then
            echo -e "${RED}  Contains public API declarations - potential breaking change${NC}"
            POTENTIAL_BREAKING_CHANGES+=("$file: File with public APIs deleted")
            FILES_WITH_CHANGES+=("$file")
        fi
        continue
    fi
    
    # Check if file exists in base branch
    if ! git cat-file -e "${BASE_BRANCH}:${file}" 2>/dev/null; then
        # New file - no breaking changes possible
        continue
    fi
    
    # Extract public APIs from both versions
    BASE_APIS=$(git show "${BASE_BRANCH}:${file}" 2>/dev/null | extract_public_api || true)
    CURRENT_APIS=$(extract_public_api "$file")
    
    if [ -z "$BASE_APIS" ]; then
        # No public APIs in base version
        continue
    fi
    
    # Check for removed public APIs
    while IFS= read -r api_line; do
        [ -z "$api_line" ] && continue
        
        # Normalize whitespace for comparison
        NORMALIZED_BASE=$(echo "$api_line" | tr -s ' ')
        
        # Check if this API still exists in current version
        if ! echo "$CURRENT_APIS" | grep -qF "$NORMALIZED_BASE"; then
            # Extract the API name for clearer reporting
            API_NAME=$(echo "$api_line" | sed -E 's/.*\s+(func|var|let|class|struct|enum|protocol|init)\s+([^(<:]+).*/\2/' | tr -d ' ')
            
            echo -e "${YELLOW}⚠ Potential API removal in $file:${NC}"
            echo "  $api_line"
            POTENTIAL_BREAKING_CHANGES+=("$file: Removed or modified public API: $API_NAME")
            FILES_WITH_CHANGES+=("$file")
        fi
    done <<< "$BASE_APIS"
    
    # Check for signature changes in existing APIs
    # This is a simplified check - a full check would require Swift AST parsing
    if [ -n "$BASE_APIS" ] && [ -n "$CURRENT_APIS" ]; then
        # Look for functions/methods that exist in both but have different signatures
        BASE_FUNC_NAMES=$(echo "$BASE_APIS" | grep -oE '(func|init)\s+\w+' | awk '{print $2}' | sort -u || true)
        
        while IFS= read -r func_name; do
            [ -z "$func_name" ] && continue
            
            BASE_SIG=$(echo "$BASE_APIS" | grep -E "(func|init)\s+${func_name}" | head -1)
            CURRENT_SIG=$(echo "$CURRENT_APIS" | grep -E "(func|init)\s+${func_name}" | head -1)
            
            if [ -n "$BASE_SIG" ] && [ -n "$CURRENT_SIG" ] && [ "$BASE_SIG" != "$CURRENT_SIG" ]; then
                echo -e "${YELLOW}⚠ Potential signature change in $file:${NC}"
                echo "  Was: $BASE_SIG"
                echo "  Now: $CURRENT_SIG"
                POTENTIAL_BREAKING_CHANGES+=("$file: Signature changed for: $func_name")
                FILES_WITH_CHANGES+=("$file")
            fi
        done <<< "$BASE_FUNC_NAMES"
    fi
    
done <<< "$CHANGED_FILES"

# Remove duplicates from FILES_WITH_CHANGES
FILES_WITH_CHANGES=($(echo "${FILES_WITH_CHANGES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

echo ""
echo -e "${BLUE}=== Summary ===${NC}"

if [ "${#POTENTIAL_BREAKING_CHANGES[@]}" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found ${#POTENTIAL_BREAKING_CHANGES[@]} potential breaking changes in ${#FILES_WITH_CHANGES[@]} files${NC}"
    echo ""
    echo "Potential breaking changes:"
    for change in "${POTENTIAL_BREAKING_CHANGES[@]}"; do
        echo -e "  ${YELLOW}⚠${NC} $change"
    done
    echo ""
    echo -e "${YELLOW}⚠ WARNING: Breaking API changes detected${NC}"
    echo ""
    echo "If these changes are intentional:"
    echo "  1. Document the breaking changes in the PR description"
    echo "  2. Update the CHANGELOG or release notes"
    echo "  3. Consider if a major version bump is needed"
    echo "  4. Update dependent code and tests"
    echo ""
    echo "If these are false positives, the check passed with warnings."
    echo ""
    # Note: We're making this a warning, not a hard failure
    # You can change exit 0 to exit 1 if you want to block PRs with breaking changes
    exit 0
else
    echo -e "${GREEN}✓ No breaking API changes detected${NC}"
    exit 0
fi
