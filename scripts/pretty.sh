#!/usr/bin/env bash

# Run prettier on each staged file that needs it without touching the working tree copy if they differ.

source ./scripts/common.sh

set -Eeuo pipefail

echoe() {
  echo "$@" >&2
}

lock() {
  local lockfile="$1"
  if [ -e "$lockfile" ]; then
    echoe "Lockfile '$lockfile' already exists. Check no other operation is occuring or delete lockfile"
    return 1
  else
    touch "$lockfile"
  fi
}

unlock() {
  rm "$1"
}

trap 'unlock $(git rev-parse --show-toplevel)/.git/index.lock || true' ERR

main() {
  local stagedFiles
  stagedFiles="$(cachedTSLintFiles)"$'\n'"$(cachedPrettierFiles)"

  if [ -n "$stagedFiles" ]; then
    # Could use git-update-index --cacheinfo to add a file without creating directories and stuff.
    local tmpdir
    tmpdir=$(mktemp -d "pretty.XXXXXXXXX")
    IFS=$'\n'
    for file in $stagedFiles; do
      if cmp -s <(staged "$file") "$file"; then
	echo "WARN: Staged copy of '$file' matches working copy. Modifying both"
	lock .git/index.lock
	case "$file" in
	  *.md | *.css) prettier --write "$file";;
	  *) tslint --project . --fix "$file";;
	esac
	unlock .git/index.lock
	git add "$file"
      else
	echo "WARN: Staged copy of '$file' does not match working copy: only prettifying staged copy."
	(
	  cd "$tmpdir"
	  mkdir -p "$(dirname "$file")"
	  lock ../.git/index.lock
      tmpfile=$(mktemp "pretty.XXXXXXXXX")
	  case "$file" in
	    *.md | *.css) staged "$file" | prettier --stdin-filepath "$file" > "$tmpfile" && mv "$tmpfile" "$file";;
	    *) staged "$file" > "$tmpfile"
	      tslint -c ../tslint.json --fix "$tmpfile" 2>/dev/null
          mv "$tmpfile" "$file";;
	  esac
	  chmod --reference="../$file" "$file" # match permissions
	  # Can't hold lock while git add occurs. Hopefully release and reacquire happen fast enough to prevent race.
	  unlock ../.git/index.lock
	  GIT_WORK_TREE=. git add "$file"
	)
      fi
    done
    rm -rf "$tmpdir"
  fi
}

main