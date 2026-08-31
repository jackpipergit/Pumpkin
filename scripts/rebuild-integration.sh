#!/usr/bin/env bash
#
# Rebuild the integration branch deterministically.
#
# Rebases every patch branch listed in fork/BRANCHES onto a pinned upstream
# commit, then recreates the integration branch by merging them back in file
# order. The result is a pure function of (pinned SHA, patch branch contents):
# two runs over the same inputs must produce the same tree hash.
#
# Usage: scripts/rebuild-integration.sh [TARGET_SHA]

set -euo pipefail

INTEGRATION_BRANCH="minechunk"
UPSTREAM_REMOTE="upstream"
UPSTREAM_URL="https://github.com/Pumpkin-MC/Pumpkin.git"
UPSTREAM_REF="upstream/master"
PIN_FILE="fork/PINNED_SHA"
BRANCH_FILE="fork/BRANCHES"

export GIT_MERGE_AUTOEDIT=no

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

ensure_upstream() {
    if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
        note "adding remote $UPSTREAM_REMOTE (fetch only)"
        git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
        git remote set-url --push "$UPSTREAM_REMOTE" DISABLED
    fi
}

rebase_in_progress() {
    [ -d "$(git rev-parse --git-path rebase-merge)" ] ||
        [ -d "$(git rev-parse --git-path rebase-apply)" ]
}

merge_in_progress() {
    [ -f "$(git rev-parse --git-path MERGE_HEAD)" ]
}

in_progress() {
    if [ "$1" = "rebase" ]; then
        rebase_in_progress
    else
        merge_in_progress
    fi
}

# rerere.autoupdate resolves and stages conflicts it recognises, but git still
# stops and waits for --continue. Drive the operation forward for as long as
# nothing is left unmerged; bounded so an operation that cannot advance fails
# instead of spinning.
#
# $1 = rebase|merge, $2 = iteration bound.
# 0 = finished, 1 = unresolved paths (left in CONFLICT_PATHS), 2 = bound hit.
CONFLICT_PATHS=""
drive() {
    local op="$1" limit="$2" i
    CONFLICT_PATHS=""
    for ((i = 0; i <= limit; i++)); do
        if ! in_progress "$op"; then
            return 0
        fi
        CONFLICT_PATHS="$(git diff --name-only --diff-filter=U)"
        if [ -n "$CONFLICT_PATHS" ]; then
            return 1
        fi
        GIT_EDITOR=true git "$op" --continue || true
    done
    return 2
}

manual_hint() {
    printf 'Rebase %s by hand and resolve the conflict; rerere will record the\n' "$1" >&2
    printf 'resolution so future runs apply it automatically. Then re-run this script:\n' >&2
    printf '    git rebase --onto %s "$(git merge-base %s %s)" %s\n' \
        "$TARGET_SHA" "$1" "$UPSTREAM_REF" "$1" >&2
}

cd "$(git rev-parse --show-toplevel)"

if [ -n "$(git status --porcelain)" ]; then
    die "working tree is not clean (tracked changes or untracked files present); commit, stash or clean it first"
fi

ensure_upstream
note "fetching $UPSTREAM_REMOTE"
git fetch "$UPSTREAM_REMOTE" --tags

if [ "$#" -ge 1 ]; then
    TARGET_INPUT="$1"
else
    if [ ! -r "$PIN_FILE" ]; then
        die "$PIN_FILE not found and no TARGET_SHA argument given; the pin file only exists on the branches carrying fork metadata, so check one out or pass the SHA explicitly"
    fi
    TARGET_INPUT="$(tr -d '[:space:]' <"$PIN_FILE")"
    [ -n "$TARGET_INPUT" ] || die "$PIN_FILE is empty"
fi

TARGET_SHA="$(git rev-parse --verify --quiet "${TARGET_INPUT}^{commit}")" ||
    die "'$TARGET_INPUT' does not resolve to a commit; check the pin or fetch upstream"

# Read the branch list before any checkout: the steps below switch branches and
# fork/BRANCHES does not exist on all of them.
[ -r "$BRANCH_FILE" ] ||
    die "$BRANCH_FILE not found; run this from a branch that carries the fork metadata"

BRANCHES=()
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    if [ -n "$line" ]; then
        BRANCHES+=("$line")
    fi
done <"$BRANCH_FILE"

[ "${#BRANCHES[@]}" -gt 0 ] || die "$BRANCH_FILE lists no branches"

for branch in "${BRANCHES[@]}"; do
    git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null ||
        die "local branch '$branch' does not exist; create it first: git branch $branch origin/$branch"
done

note "target $TARGET_SHA"
note "branches: ${BRANCHES[*]}"

for branch in "${BRANCHES[@]}"; do
    base="$(git merge-base "$branch" "$UPSTREAM_REF")"
    count="$(git rev-list --count "$base..$branch")"
    note "rebasing $branch ($count commit(s))"
    if ! git rebase --onto "$TARGET_SHA" "$base" "$branch"; then
        rebase_in_progress || die "$branch: rebase failed to start"
    fi
    status=0
    drive rebase "$((count + 5))" || status=$?
    if [ "$status" -eq 1 ]; then
        printf 'error: %s: unresolved conflicts in:\n%s\n' "$branch" "$CONFLICT_PATHS" >&2
        manual_hint "$branch"
        git rebase --abort
        exit 1
    elif [ "$status" -ne 0 ]; then
        printf 'error: %s: rebase stopped and could not be advanced automatically\n' "$branch" >&2
        manual_hint "$branch"
        git rebase --abort
        exit 1
    fi
done

note "recreating $INTEGRATION_BRANCH at $TARGET_SHA"
git checkout -B "$INTEGRATION_BRANCH" "$TARGET_SHA"

for branch in "${BRANCHES[@]}"; do
    note "merging $branch"
    if ! git merge --no-ff --no-edit "$branch"; then
        merge_in_progress || die "$branch: merge failed to start"
    fi
    status=0
    drive merge 5 || status=$?
    if [ "$status" -eq 1 ]; then
        printf 'error: %s: unresolved merge conflicts in:\n%s\n' "$branch" "$CONFLICT_PATHS" >&2
        printf 'Resolve it on the branch itself so rerere records the resolution, then re-run this script.\n' >&2
        git merge --abort
        exit 1
    elif [ "$status" -ne 0 ]; then
        printf 'error: %s: merge stopped and could not be advanced automatically\n' "$branch" >&2
        git merge --abort
        exit 1
    fi
done

printf '\n'
note "$INTEGRATION_BRANCH rebuilt"
printf 'target:  %s\n' "$TARGET_SHA"
printf 'applied: %s\n' "${BRANCHES[*]}"
printf 'head:    %s\n' "$(git rev-parse HEAD)"
printf 'tree:    %s\n' "$(git rev-parse 'HEAD^{tree}')"
printf '\nsurface area vs upstream:\n'
git diff --stat "$TARGET_SHA..HEAD"
