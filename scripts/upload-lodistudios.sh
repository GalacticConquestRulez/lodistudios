#!/usr/bin/env bash
#
# Upload the lodistudios site folders from this server into the GitHub repo.
#
# Run this ON THE SERVER that holds the files. It copies:
#
#     /root/lodistudios      ->  root-lodistudios/
#     /var/www/lodistudios   ->  www-lodistudios/
#
# into a clone of the repo branch, then commits and pushes. Paths are kept
# under separate prefixes so files with the same name in both trees don't
# overwrite each other.
#
# Usage:
#     ./upload-lodistudios.sh              # copy, show what changed, push
#     ./upload-lodistudios.sh --dry-run    # copy and show, but don't commit
#
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/GalacticConquestRulez/lodistudios.git}"
BRANCH="${BRANCH:-claude/lodistudios-folder-upload-6ft1ds}"
SRC_ROOT="${SRC_ROOT:-/root/lodistudios}"
SRC_WWW="${SRC_WWW:-/var/www/lodistudios}"
WORKDIR="${WORKDIR:-$HOME/lodistudios-upload}"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# --- checks ----------------------------------------------------------------

command -v git >/dev/null || die "git is not installed."

MISSING=0
[ -d "$SRC_ROOT" ] || { echo "missing: $SRC_ROOT"; MISSING=1; }
[ -d "$SRC_WWW" ]  || { echo "missing: $SRC_WWW";  MISSING=1; }
[ "$MISSING" -eq 0 ] || die "Source folder(s) not found. Set SRC_ROOT / SRC_WWW to the right paths."

say "Source sizes"
du -sh "$SRC_ROOT" "$SRC_WWW"

# --- get the repo ----------------------------------------------------------

if [ -d "$WORKDIR/.git" ]; then
    say "Updating existing clone at $WORKDIR"
    git -C "$WORKDIR" fetch origin "$BRANCH"
    git -C "$WORKDIR" checkout "$BRANCH"
    git -C "$WORKDIR" reset --hard "origin/$BRANCH"
else
    say "Cloning $BRANCH into $WORKDIR"
    git clone --branch "$BRANCH" "$REPO_URL" "$WORKDIR"
fi

cd "$WORKDIR"

# --- copy ------------------------------------------------------------------

copy_tree() {
    local src="$1" dest="$2"
    mkdir -p "$dest"
    if command -v rsync >/dev/null; then
        rsync -a --delete --exclude='.git' "$src/" "$dest/"
    else
        rm -rf "${dest:?}"/*
        cp -a "$src/." "$dest/"
        rm -rf "$dest/.git"
    fi
}

say "Copying $SRC_ROOT -> root-lodistudios/"
copy_tree "$SRC_ROOT" "$WORKDIR/root-lodistudios"

say "Copying $SRC_WWW -> www-lodistudios/"
copy_tree "$SRC_WWW" "$WORKDIR/www-lodistudios"

# --- size guard ------------------------------------------------------------
# GitHub hard-rejects any single file over 100 MB and warns above 50 MB.

say "Checking for oversized files (GitHub rejects >100MB)"
BIG=$(find root-lodistudios www-lodistudios -type f -size +100M 2>/dev/null || true)
if [ -n "$BIG" ]; then
    echo "$BIG" | while read -r f; do echo "  TOO BIG: $(du -h "$f" | cut -f1)  $f"; done
    die "Remove these files or track them with Git LFS, then re-run."
fi
find root-lodistudios www-lodistudios -type f -size +50M 2>/dev/null \
    | while read -r f; do echo "  large:  $(du -h "$f" | cut -f1)  $f"; done
echo "  (no blocking files)"

# --- review ----------------------------------------------------------------

git add -A

say "Files staged: $(git diff --cached --name-only | wc -l)"
git diff --cached --stat | tail -20

say "Review this list before it goes public"
git diff --cached --name-only | head -60
TOTAL=$(git diff --cached --name-only | wc -l)
[ "$TOTAL" -gt 60 ] && echo "  ... and $((TOTAL - 60)) more"

if git diff --cached --quiet; then
    say "Nothing changed — repo already matches these folders. Done."
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    say "Dry run: stopping before commit. Staged copy is at $WORKDIR"
    exit 0
fi

# --- commit and push -------------------------------------------------------

say "Committing"
git commit -q -m "Add lodistudios site files from /root and /var/www

Copied from $SRC_ROOT and $SRC_WWW on $(hostname) at $(date -u '+%Y-%m-%d %H:%M UTC')."

say "Pushing to $BRANCH"
DELAY=2
for attempt in 1 2 3 4 5; do
    if git push -u origin "$BRANCH"; then
        say "Pushed. https://github.com/GalacticConquestRulez/lodistudios/tree/$BRANCH"
        exit 0
    fi
    [ "$attempt" -eq 5 ] && die "Push failed after 5 attempts."
    echo "Push failed (attempt $attempt). Retrying in ${DELAY}s..."
    sleep "$DELAY"
    DELAY=$((DELAY * 2))
done
