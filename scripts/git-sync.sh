#!/usr/bin/env bash
# git-sync — pull every git repo under ~/git (or $1), recursively, and
# print a status report. Submodules are updated with their parent repo.
# Returns you to the directory you started in.
#
# Packaged as `git-sync` by modules/shell-aliases.nix.
#
# Usage: git-sync [root-dir]     (default: ~/git)
set -u

root="${1:-$HOME/git}"
[ -d "$root" ] || { echo "git-sync: $root is not a directory" >&2; exit 1; }

# Never block on a password/passphrase prompt or a new host key.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes}"

if [ -t 1 ]; then
  G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' B=$'\e[1m' D=$'\e[2m' N=$'\e[0m'
else
  G='' Y='' R='' B='' D='' N=''
fi

pushd "$root" >/dev/null || exit 1

# Every directory with a real .git *dir* (submodules have a .git *file* and
# are handled by their parent's --recurse-submodules). Nested standalone
# repos are found too; node_modules and .git internals are skipped.
repos=()
while IFS= read -r -d '' gitdir; do
  repos+=("${gitdir%/.git}")
done < <(find . \( -name node_modules -o -name .direnv \) -prune -o \
              -name .git -type d -print0 -prune 2>/dev/null | sort -z)

n_up=0 n_new=0 n_skip=0 n_fail=0
report=()

for repo in "${repos[@]}"; do
  name="${repo#./}"; [ "$name" = "." ] && name="$(basename "$root")"
  printf '%s→ %s%s\n' "$D" "$name" "$N" >&2

  pushd "$repo" >/dev/null || continue
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(detached)")
  dirty=""; [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] && dirty=" *dirty*"

  if [ "$branch" = "(detached)" ]; then
    status="${Y}SKIP${N}  detached HEAD"; n_skip=$((n_skip+1))
  elif ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    status="${Y}SKIP${N}  no upstream"; n_skip=$((n_skip+1))
  else
    before=$(git rev-parse HEAD)
    if out=$(git pull --ff-only --recurse-submodules 2>&1); then
      if [ -f .gitmodules ]; then
        git submodule update --init --recursive >/dev/null 2>&1 \
          || out="$out (submodule update failed)"
      fi
      after=$(git rev-parse HEAD)
      if [ "$before" = "$after" ]; then
        status="${G}OK${N}    up to date"; n_up=$((n_up+1))
      else
        cnt=$(git rev-list --count "$before..$after")
        status="${G}${B}PULL${N}  +$cnt commit(s)"; n_new=$((n_new+1))
      fi
    else
      reason=$(printf '%s\n' "$out" | grep -m1 -iE 'fatal|error|not possible|diverg|denied|could not' || printf '%s\n' "$out" | tail -1)
      status="${R}FAIL${N}  ${reason}"; n_fail=$((n_fail+1))
    fi
  fi
  popd >/dev/null

  report+=("$(printf '%-40s %-18s %s%s' "$name" "$branch" "$status" "$dirty")")
done

popd >/dev/null   # back to where we started

# --- Claude Code project memories --------------------------------------------
# Claude keeps each project's memory in ~/.claude/projects/<slug>/memory/ (slug =
# the project's path with / turned into -), which stays on the host it was
# written on. This merges them with the private claude-memory repo
# (~/.claude/shared-memory, under projects/<slug>/), so every host ends up with
# the same memories.
#
# Each file is merged three ways against its copy from the last sync on this
# host (~/.claude/.memory-sync-base/<slug>/): a change on one side wins
# (deletions too); edits on both sides go through `git merge-file`, by union
# for the MEMORY.md indexes. On a real conflict the repo's version is kept and
# this host's is saved next to it as <name>.conflict-<host>.md, which isn't
# synced, so merge it by hand.
mem_same() {  # both missing, or both present with the same bytes
  { [ ! -e "$1" ] && [ ! -e "$2" ]; } || { [ -e "$1" ] && [ -e "$2" ] && cmp -s "$1" "$2"; }
}

mem_put() {  # mem_put SRC DEST...: copy SRC to each DEST, or delete them if SRC is gone
  local src=$1 dst; shift
  for dst in "$@"; do
    if [ ! -e "$src" ]; then rm -f "$dst"
    elif ! cmp -s "$src" "$dst" 2>/dev/null; then cp "$src" "$dst"
    fi
  done
}

sync_claude_memory() {
  local repo="$HOME/.claude/shared-memory" projects="$HOME/.claude/projects"
  local bases="$HOME/.claude/.memory-sync-base" host tmp empty out
  host=$(hostname -s)
  [ -d "$repo/.git" ] || { mem_status="${Y}SKIP${N}  no ~/.claude/shared-memory clone"; return 2; }
  if ! out=$(git -C "$repo" pull --rebase -q 2>&1); then
    mem_status="${R}FAIL${N}  pull: $(printf '%s\n' "$out" | tail -1)"; return 1
  fi

  local slugs=() d s
  shopt -s nullglob
  for d in "$projects"/*/memory "$repo"/projects/*; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    s=${d%/memory}; s=${s##*/}
    slugs+=("$s")
  done
  mapfile -t slugs < <(printf '%s\n' "${slugs[@]}" | grep . | sort -u)

  tmp=$(mktemp -d); empty="$tmp/empty"; : > "$empty"
  local changed=0 notes=() ldir bdir rdir name f l b r res rc
  local -a union
  for s in "${slugs[@]}"; do
    ldir="$projects/$s/memory" rdir="$repo/projects/$s" bdir="$bases/$s"
    mkdir -p "$ldir" "$rdir" "$bdir"
    for name in $( { for f in "$ldir"/*.md "$rdir"/*.md "$bdir"/*.md; do basename "$f"; done; } \
                   | grep -v '\.conflict-.*\.md$' | sort -u ); do
      l="$ldir/$name" b="$bdir/$name" r="$rdir/$name"
      if mem_same "$l" "$r"; then res=$l
      elif mem_same "$l" "$b"; then res=$r     # changed only in the repo
      elif mem_same "$r" "$b"; then res=$l     # changed only here
      elif [ ! -e "$l" ]; then res=$r          # deleted here, edited there: keep the edit
      elif [ ! -e "$r" ]; then res=$l          # and the other way round
      else
        union=(); [ "$name" = MEMORY.md ] && union=(--union)
        [ -e "$b" ] || b=$empty
        git merge-file -p "${union[@]}" "$l" "$b" "$r" > "$tmp/$name"; rc=$?
        if [ "$rc" -eq 0 ]; then res="$tmp/$name"
        else
          cp "$l" "$ldir/${name%.md}.conflict-$host.md"
          notes+=("$s/$name (this host's copy: ${name%.md}.conflict-$host.md)")
          res=$r
        fi
      fi
      if [ "$res" = "$l" ]; then mem_put "$res" "$r" "$bdir/$name"
      elif [ "$res" = "$r" ]; then mem_put "$res" "$l" "$bdir/$name"
      else mem_put "$res" "$l" "$r" "$bdir/$name"
      fi
    done
    rmdir "$rdir" 2>/dev/null || true   # don't leave empty project dirs in the repo
  done
  rm -rf "$tmp"

  if [ -n "$(git -C "$repo" status --porcelain -- projects 2>/dev/null)" ]; then
    git -C "$repo" add -A -- projects
    changed=$(git -C "$repo" diff --cached --name-only | wc -l)
    git -C "$repo" commit -q -m "auto: sync project memories [$host]"
    if ! git -C "$repo" push -q 2>/dev/null; then
      { git -C "$repo" pull --rebase -q && git -C "$repo" push -q; } 2>/dev/null \
        || { mem_status="${R}FAIL${N}  push (run git-sync again)"; return 1; }
    fi
  fi
  if [ ${#notes[@]} -gt 0 ]; then
    mem_status="${Y}CONFLICT${N} ${notes[*]}"; return 3
  fi
  mem_status="${G}OK${N}    ${#slugs[@]} projects, $changed file(s) pushed"
}

printf '%s→ claude memories%s\n' "$D" "$N" >&2
mem_status=""
sync_claude_memory; rc=$?
case $rc in 0) ;; 2) n_skip=$((n_skip+1)) ;; *) n_fail=$((n_fail+1)) ;; esac
report+=("$(printf '%-40s %-18s %s' "~/.claude memories" "" "$mem_status")")

echo
printf '%s%-40s %-18s %s%s\n' "$B" "REPO" "BRANCH" "RESULT" "$N"
printf '%s\n' "${report[@]}"
echo
printf '%s%d repos%s: %s%d updated%s, %d up to date, %s%d skipped%s, %s%d failed%s\n' \
  "$B" "${#repos[@]}" "$N" "$G" "$n_new" "$N" "$n_up" "$Y" "$n_skip" "$N" "$R" "$n_fail" "$N"

[ "$n_fail" -eq 0 ]
