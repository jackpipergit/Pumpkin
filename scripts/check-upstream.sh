#!/usr/bin/env bash
#
# Report which patch branches would conflict if rebased onto current
# upstream/master.
#
# Read-only with respect to the repository: the only ref change is the upstream
# fetch. Every rebase is trialled on a detached HEAD inside a throwaway
# worktree, so no real branch and no real working tree is touched.
#
# Exit 0 if every branch applies cleanly, 1 if any conflict.
# Set CONFLICT_REPORT=<path> to also write the conflicting branch names, one
# per line, for CI to turn into an issue body.

set -euo pipefail

UPSTREAM_REMOTE="upstream"
UPSTREAM_URL="https://github.com/Pumpkin-MC/Pumpkin.git"
UPSTREAM_REF="upstream/master"
PIN_FILE="fork/PINNED_SHA"
BRANCH_FILE="fork/BRANCHES"

export GIT_MERGE_AUTOEDIT=no

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

WT=""
cleanup() {
    [ -n "$WT" ] || return 0
    if [ -d "$WT" ]; then
        git -C "$WT" rebase --abort >/dev/null 2>&1 || true
        git worktree remove --force "$WT" >/dev/null 2>&1 || true
        rm -rf "$WT"
    fi
    git worktree prune >/dev/null 2>&1 || true
}

wgit() { git -C "$WT" "$@"; }

ensure_upstream() {
    if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
        note "adding remote $UPSTREAM_REMOTE (fetch only)"
        git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
        git remote set-url --push "$UPSTREAM_REMOTE" DISABLED
    fi
}

rebase_in_progress() {
    [ -d "$(wgit rev-parse --git-path rebase-merge)" ] ||
        [ -d "$(wgit rev-parse --git-path rebase-apply)" ]
}

# rerere.autoupdate resolves and stages conflicts it recognises, but git still
# stops and waits for --continue. Advance while nothing is left unmerged;
# bounded so a rebase that cannot advance fails instead of spinning.
#
# 0 = finished, 1 = unresolved paths (left in CONFLICT_PATHS), 2 = bound hit.
CONFLICT_PATHS=""
drive_rebase() {
    local limit="$1" i
    CONFLICT_PATHS=""
    for ((i = 0; i <= limit; i++)); do
        if ! rebase_in_progress; then
            return 0
        fi
        CONFLICT_PATHS="$(wgit diff --name-only --diff-filter=U | tr '\n' ' ')"
        CONFLICT_PATHS="${CONFLICT_PATHS% }"
        if [ -n "$CONFLICT_PATHS" ]; then
            return 1
        fi
        GIT_EDITOR=true wgit rebase --continue || true
    done
    return 2
}

# Patch branches may exist only as remote-tracking refs (CI clones).
resolve_branch() {
    local b="$1" c
    c="$(git rev-parse --verify --quiet "refs/heads/$b^{commit}")" &&
        { printf '%s' "$c"; return 0; }
    c="$(git rev-parse --verify --quiet "refs/remotes/origin/$b^{commit}")" &&
        { printf '%s' "$c"; return 0; }
    return 1
}

cd "$(git rev-parse --show-toplevel)"

ensure_upstream
note "fetching $UPSTREAM_REMOTE"
git fetch "$UPSTREAM_REMOTE" --tags

git rev-parse --verify --quiet "${UPSTREAM_REF}^{commit}" >/dev/null ||
    die "$UPSTREAM_REF does not resolve after fetch"

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

COMMITS=()
for branch in "${BRANCHES[@]}"; do
    commit="$(resolve_branch "$branch")" ||
        die "branch '$branch' resolves neither locally nor as origin/$branch"
    COMMITS+=("$commit")
done

trap cleanup EXIT
WT="$(mktemp -d)"
git worktree add --detach --quiet "$WT" "$UPSTREAM_REF"

RESULTS=()
for ((n = 0; n < ${#BRANCHES[@]}; n++)); do
    branch="${BRANCHES[$n]}"
    commit="${COMMITS[$n]}"
    note "trialling $branch"
    wgit checkout --detach --force --quiet "$commit"
    base="$(wgit merge-base "$commit" "$UPSTREAM_REF")"
    count="$(wgit rev-list --count "$base..$commit")"
    if ! wgit rebase --onto "$UPSTREAM_REF" "$base"; then
        rebase_in_progress || die "$branch: rebase failed to start"
    fi
    status=0
    drive_rebase "$((count + 5))" || status=$?
    if [ "$status" -eq 0 ]; then
        RESULTS+=("clean")
    else
        if [ "$status" -eq 2 ]; then
            CONFLICT_PATHS="rebase could not be advanced automatically"
        fi
        RESULTS+=("CONFLICT ($CONFLICT_PATHS)")
        wgit rebase --abort
    fi
done

cleanup
WT=""
trap - EXIT

printf '\n'
if [ -r "$PIN_FILE" ]; then
    pin="$(tr -d '[:space:]' <"$PIN_FILE")"
    if [ -n "$pin" ] && git rev-parse --verify --quiet "${pin}^{commit}" >/dev/null; then
        printf 'upstream/master is %s commit(s) ahead of the pin %s\n\n' \
            "$(git rev-list --count "$pin..$UPSTREAM_REF")" "$pin"
    fi
fi

conflicts=0
for ((n = 0; n < ${#BRANCHES[@]}; n++)); do
    printf '%s: %s\n' "${BRANCHES[$n]}" "${RESULTS[$n]}"
    case "${RESULTS[$n]}" in
    CONFLICT*) conflicts=$((conflicts + 1)) ;;
    esac
done

if [ -n "${CONFLICT_REPORT:-}" ]; then
    : >"$CONFLICT_REPORT"
    for ((n = 0; n < ${#BRANCHES[@]}; n++)); do
        case "${RESULTS[$n]}" in
        CONFLICT*) printf '%s\n' "${BRANCHES[$n]}" >>"$CONFLICT_REPORT" ;;
        esac
    done
fi

printf '\n%s of %s branch(es) conflict with %s\n' \
    "$conflicts" "${#BRANCHES[@]}" "$UPSTREAM_REF"

if [ "$conflicts" -ne 0 ]; then
    exit 1
fi
