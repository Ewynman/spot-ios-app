#!/bin/bash

# validate-documentation.sh
# Validates that documentation is updated when significant code changes are made
#
# Usage: ./validate-documentation.sh <base-branch>
#
# Arguments:
#   base-branch: Base branch to compare against (e.g., origin/main)
#
# Exit codes:
#   0: Documentation validation passed
#   1: Documentation may need updates

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BASE_BRANCH="${1:-origin/main}"

echo -e "${BLUE}=== Documentation Validation ===${NC}"
echo "Base branch: ${BASE_BRANCH}"
echo ""

# Fetch base branch
git fetch origin "${BASE_BRANCH##*/}" --depth=1 2>/dev/null || true

# Get all changed files
ALL_CHANGED_FILES=$(git diff --name-only "${BASE_BRANCH}" || true)

if [ -z "$ALL_CHANGED_FILES" ]; then
    echo -e "${GREEN}✓ No files changed${NC}"
    exit 0
fi

# Categorize changes
PRODUCTION_SWIFT=$(echo "$ALL_CHANGED_FILES" | grep -E '^Spot/.*\.swift$' | grep -v 'SpotTests/' | grep -v 'SpotUITests/' || true)
TEST_FILES=$(echo "$ALL_CHANGED_FILES" | grep -E '^(SpotTests|SpotUITests)/.*\.swift$' || true)
DOC_FILES=$(echo "$ALL_CHANGED_FILES" | grep -E '^docs/.*\.md$' || true)
CONFIG_FILES=$(echo "$ALL_CHANGED_FILES" | grep -E '\.(plist|xcconfig|yaml|yml|json)$' || true)
MIGRATIONS=$(echo "$ALL_CHANGED_FILES" | grep -E '^supabase/migrations/.*\.sql$' || true)

# Count changes (count non-empty lines)
count_files() {
    local files="$1"
    if [ -z "$files" ]; then
        echo "0"
    else
        echo "$files" | wc -l | tr -d ' '
    fi
}

PRODUCTION_COUNT=$(count_files "$PRODUCTION_SWIFT")
TEST_COUNT=$(count_files "$TEST_FILES")
DOC_COUNT=$(count_files "$DOC_FILES")
CONFIG_COUNT=$(count_files "$CONFIG_FILES")
MIGRATION_COUNT=$(count_files "$MIGRATIONS")

echo "Changed files:"
echo "  Production Swift: $PRODUCTION_COUNT"
echo "  Test files: $TEST_COUNT"
echo "  Documentation: $DOC_COUNT"
echo "  Config files: $CONFIG_COUNT"
echo "  Database migrations: $MIGRATION_COUNT"
echo ""

WARNINGS=()
SUGGESTIONS=()

# Check 1: Service/Repository changes should update architecture docs
if echo "$PRODUCTION_SWIFT" | grep -qE '^Spot/Services/'; then
    if [ "$DOC_COUNT" -eq 0 ]; then
        WARNINGS+=("Service layer changes detected but no documentation updated")
        SUGGESTIONS+=("Consider updating docs/engineering/architecture.md if service interfaces changed")
        SUGGESTIONS+=("Consider updating docs/engineering/networking-and-auth.md if auth/network logic changed")
    fi
fi

# Check 2: ViewModel changes should potentially update product docs
if echo "$PRODUCTION_SWIFT" | grep -qE '^Spot/ViewModels/'; then
    if [ "$DOC_COUNT" -eq 0 ]; then
        WARNINGS+=("ViewModel changes detected but no documentation updated")
        SUGGESTIONS+=("Consider updating relevant docs/product/*.md if user-facing behavior changed")
        SUGGESTIONS+=("Consider updating docs/diagrams/ if flow changed")
    fi
fi

# Check 3: Database migrations should update database docs
if [ "$MIGRATION_COUNT" -gt 0 ]; then
    if ! echo "$DOC_FILES" | grep -qE 'database-and-rls\.md'; then
        WARNINGS+=("Database migration added but docs/engineering/database-and-rls.md not updated")
        SUGGESTIONS+=("Update docs/engineering/database-and-rls.md to document new schema/RLS policies")
    fi
fi

# Check 4: Auth changes should update auth docs
if echo "$PRODUCTION_SWIFT" | grep -qE 'Auth|Session|SignIn|SignUp'; then
    if ! echo "$DOC_FILES" | grep -qE 'networking-and-auth\.md'; then
        WARNINGS+=("Authentication code changes detected but networking-and-auth.md not updated")
        SUGGESTIONS+=("Consider updating docs/engineering/networking-and-auth.md")
    fi
fi

# Check 5: Posting flow changes should update posting docs
if echo "$PRODUCTION_SWIFT" | grep -qE 'Post|Upload|Publish'; then
    if ! echo "$DOC_FILES" | grep -qE '(posting-flow\.md|posting-flow\.md)'; then
        WARNINGS+=("Posting/upload code changes detected")
        SUGGESTIONS+=("Consider updating docs/product/posting-flow.md or docs/diagrams/posting-flow.md")
    fi
fi

# Check 6: Deep link / Universal Links changes
if echo "$PRODUCTION_SWIFT" | grep -qE 'DeepLink|UniversalLink|Router'; then
    if ! echo "$DOC_FILES" | grep -qE 'universal-links\.md'; then
        WARNINGS+=("Deep link/routing changes detected")
        SUGGESTIONS+=("Consider updating docs/engineering/universal-links.md")
    fi
fi

# Check 7: Configuration changes should update config docs
if echo "$CONFIG_FILES" | grep -qE 'Info\.plist|\.entitlements'; then
    if ! echo "$DOC_FILES" | grep -qE 'configuration\.md'; then
        WARNINGS+=("Configuration file changes detected")
        SUGGESTIONS+=("Consider updating docs/engineering/configuration.md")
    fi
fi

# Check 8: Storage/media changes should update storage docs
if echo "$PRODUCTION_SWIFT" | grep -qE 'Storage|Media|Image|Upload'; then
    if ! echo "$DOC_FILES" | grep -qE '(storage-and-media\.md|image-moderation\.md)'; then
        WARNINGS+=("Storage or media code changes detected")
        SUGGESTIONS+=("Consider updating docs/engineering/storage-and-media.md or image-moderation.md")
    fi
fi

# Check 9: Significant production changes should have some doc updates
if [ "$PRODUCTION_COUNT" -ge 5 ] && [ "$DOC_COUNT" -eq 0 ]; then
    WARNINGS+=("Significant code changes ($PRODUCTION_COUNT files) with no documentation updates")
    SUGGESTIONS+=("Review docs/operations/documentation-maintenance.md for guidance")
fi

# Check 10: Data plane changes (Supabase-specific)
if echo "$PRODUCTION_SWIFT" | grep -qE 'Supabase|SpotSupabaseRepository|SpotPublishCoordinator'; then
    if ! echo "$DOC_FILES" | grep -qE 'data-plane\.md'; then
        WARNINGS+=("Supabase/data plane code changes detected")
        SUGGESTIONS+=("Consider updating docs/engineering/data-plane.md")
    fi
fi

echo -e "${BLUE}=== Summary ===${NC}"

if [ "${#WARNINGS[@]}" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Documentation may need updates${NC}"
    echo ""
    echo "Detected issues:"
    for warning in "${WARNINGS[@]}"; do
        echo -e "  ${YELLOW}⚠${NC} $warning"
    done
    echo ""
    
    if [ "${#SUGGESTIONS[@]}" -gt 0 ]; then
        echo "Suggestions:"
        for suggestion in "${SUGGESTIONS[@]}"; do
            echo -e "  ${BLUE}→${NC} $suggestion"
        done
        echo ""
    fi
    
    echo "Documentation guidelines:"
    echo "  - See docs/operations/documentation-maintenance.md for when to update docs"
    echo "  - Check the PR template checklist for documentation requirements"
    echo "  - Update relevant docs/ files when behavior, architecture, or config changes"
    echo "  - Update diagrams if flows change significantly"
    echo ""
    echo -e "${YELLOW}This is a WARNING - not a hard failure${NC}"
    echo "Please review if documentation updates are needed for your changes."
    echo ""
    
    # This is a warning only, not a hard failure
    # Change to exit 1 if you want to enforce documentation updates
    exit 0
else
    echo -e "${GREEN}✓ No obvious documentation gaps detected${NC}"
    
    if [ "$DOC_COUNT" -gt 0 ]; then
        echo ""
        echo "Documentation updates included:"
        echo "$DOC_FILES" | sed 's/^/  - /'
    fi
    
    exit 0
fi
