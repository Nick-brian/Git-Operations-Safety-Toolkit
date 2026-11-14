#!/usr/bin/env bash
#
# Git Recovery Assistant
# Restore a remote branch to a known-good branch or commit.
#
# Safety:
# - Does not reset, clean, checkout, or otherwise modify local files.
# - Fetches remote refs before inspecting them.
# - Creates and verifies a recovery branch before changing the target.
# - Requires the exact word RESTORE before the force-push.
# - Uses --force-with-lease to avoid overwriting an unexpected update.
#
# Requirements: Bash, Git, SSH access to GitHub, and permission to push branches.
# Tested design target: Fedora/Linux + GitHub.com.
#
set -Eeuo pipefail

readonly RESET=$'\033[0m'
readonly GREEN=$'\033[0;32m'
readonly RED=$'\033[0;31m'
readonly YELLOW=$'\033[1;33m'
readonly CYAN=$'\033[0;36m'

info()    { printf '%s[INFO]%s %s\n' "$CYAN" "$RESET" "$*"; }
success() { printf '%s[OK]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()    { printf '%s[WARNING]%s %s\n' "$YELLOW" "$RESET" "$*"; }
die()     { printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

ask() {
    local prompt="$1" default="$2" answer
    read -r -p "$prompt [$default]: " answer
    printf '%s' "${answer:-$default}"
}

confirm() {
    local answer
    read -r -p "$1 (yes/no): " answer
    [[ "$answer" == "yes" ]]
}

remote_hash() {
    local branch="$1" result
    result=$(git ls-remote --heads "$REMOTE" "refs/heads/$branch") ||
        die "Could not query remote branch '$branch'."
    [[ -n "$result" ]] || die "Remote branch '$branch' does not exist."
    awk 'NR == 1 {print $1}' <<< "$result"
}

printf '\n======================================\n'
printf '       GIT RECOVERY ASSISTANT\n'
printf '======================================\n\n'

command -v git >/dev/null 2>&1 || die "Git is not installed."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    die "Run this script from inside a Git repository."

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

info "Repository: $REPO_ROOT"
info "This tool changes remote branch references only."
info "It will not reset, clean, or overwrite your local working files."

if [[ -n "$(git status --porcelain)" ]]; then
    warn "Your local working tree has staged or unstaged changes."
    warn "They will not be changed by this script, but keep them safe."
fi

printf '\n========== CONFIGURATION ==========\n'
REMOTE=$(ask "Git remote name" "origin")
TARGET=$(ask "Remote branch to restore" "main")
SOURCE=$(ask "Known-good source branch" "dev")

[[ "$TARGET" != "$SOURCE" ]] || die "Source and target must differ."
git check-ref-format --branch "$TARGET" >/dev/null ||
    die "Invalid target branch name: $TARGET"
git check-ref-format --branch "$SOURCE" >/dev/null ||
    die "Invalid source branch name: $SOURCE"
git remote get-url "$REMOTE" >/dev/null 2>&1 ||
    die "Remote '$REMOTE' does not exist."

REMOTE_URL=$(git remote get-url "$REMOTE")
case "$REMOTE_URL" in
    *github.com*) ;;
    *) die "This version is intended for GitHub.com. Remote URL: $REMOTE_URL" ;;
esac

printf '\n'
info "Remote: $REMOTE ($REMOTE_URL)"
info "Target branch: $TARGET"
info "Known-good source: $SOURCE"

printf '\n========== SSH CHECK ==========\n'
command -v ssh >/dev/null 2>&1 || die "SSH client not found."
SSH_OUTPUT=$(ssh -T -o BatchMode=yes -o ConnectTimeout=10 git@github.com 2>&1 || true)
if grep -q "successfully authenticated" <<< "$SSH_OUTPUT"; then
    success "GitHub SSH authentication is working."
else
    printf '%s\n' "$SSH_OUTPUT"
    die "GitHub SSH authentication could not be confirmed. Fix SSH before continuing."
fi

printf '\n'
info "Fetching current remote information..."
git fetch "$REMOTE" || die "Fetch failed. Check network access and permissions."

TARGET_HASH=$(remote_hash "$TARGET")
SOURCE_HASH=$(remote_hash "$SOURCE")

printf '\n========== BRANCH COMPARISON ==========\n'
printf 'Target: %s\nCurrent commit: %s\n\n' "$TARGET" "$TARGET_HASH"
printf 'Source: %s\nSource commit:  %s\n' "$SOURCE" "$SOURCE_HASH"

if [[ "$TARGET_HASH" == "$SOURCE_HASH" ]]; then
    success "Target already points to the same commit as the source. Nothing to do."
    exit 0
fi

printf '\n========== PRESERVE CURRENT TARGET ==========\n'
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
RECOVERY="recovery-${TARGET}-${TIMESTAMP}"

if git ls-remote --exit-code --heads "$REMOTE" "refs/heads/$RECOVERY" >/dev/null 2>&1; then
    die "Recovery branch '$RECOVERY' already exists. Run again to generate a new timestamp."
fi

info "A recovery branch will preserve the current target:"
printf '  %s -> %s\n' "$RECOVERY" "$TARGET_HASH"

confirm "Create and verify this recovery branch?" ||
    die "Cancelled. No remote branch was changed."

git push "$REMOTE" "$TARGET_HASH:refs/heads/$RECOVERY" ||
    die "Could not create recovery branch. Target was not changed."

RECOVERY_HASH=$(remote_hash "$RECOVERY")
[[ "$RECOVERY_HASH" == "$TARGET_HASH" ]] ||
    die "Recovery branch verification failed. Target was not changed."

success "Current target preserved as '$RECOVERY'."

printf '\n========== RESTORATION PREVIEW ==========\n'
printf 'Repository:       %s\n' "$REPO_ROOT"
printf 'Remote:           %s\n' "$REMOTE"
printf 'Target branch:    %s\n' "$TARGET"
printf 'Current target:   %s\n' "$TARGET_HASH"
printf 'New target:       %s\n' "$SOURCE_HASH"
printf 'Source branch:    %s\n' "$SOURCE"
printf 'Recovery branch:  %s\n' "$RECOVERY"
printf '\n'
warn "The next operation rewrites the remote '$TARGET' branch history."
warn "The source branch and recovery branch will not be intentionally changed."
warn "Repository branch protection may reject the push."
warn "Local files and staged changes will not be restored or modified."
printf '\n'

read -r -p "Type RESTORE exactly to proceed: " APPROVAL
[[ "$APPROVAL" == "RESTORE" ]] || die "Restoration cancelled. Recovery branch remains available."

printf '\n'
info "Restoring '$TARGET' to the source commit..."
git push \
    --force-with-lease="refs/heads/$TARGET:$TARGET_HASH" \
    "$REMOTE" \
    "$SOURCE_HASH:refs/heads/$TARGET" ||
    die "Restore push failed. Check branch protection and whether the target changed."

printf '\n========== FINAL VERIFICATION ==========\n'
FINAL_TARGET=$(remote_hash "$TARGET")
FINAL_SOURCE=$(remote_hash "$SOURCE")
FINAL_RECOVERY=$(remote_hash "$RECOVERY")

[[ "$FINAL_TARGET" == "$SOURCE_HASH" ]] ||
    die "Verification failed: target does not match source."
[[ "$FINAL_SOURCE" == "$SOURCE_HASH" ]] ||
    die "Verification failed: source branch changed unexpectedly."
[[ "$FINAL_RECOVERY" == "$TARGET_HASH" ]] ||
    die "Verification failed: recovery branch does not match the original target."

success "RESTORATION COMPLETED AND VERIFIED"
printf '\n'
printf 'Target:   %s -> %s\n' "$TARGET" "$FINAL_TARGET"
printf 'Source:   %s -> %s\n' "$SOURCE" "$FINAL_SOURCE"
printf 'Recovery: %s -> %s\n' "$RECOVERY" "$FINAL_RECOVERY"
printf '\n'
warn "Your local working directory was not restored."
printf 'Inspect it separately with: git status\n\n'
