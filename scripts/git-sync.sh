#!/usr/bin/env bash
# git-sync — pull every git repo under ~/git (or $1), recursively, and
# print a status report. Submodules are updated with their parent repo.
# Returns you to the directory you started in.
#
# Packaged as `git-sync` by modules/shell-aliases.nix and
# hosts/airbook-darwin/default.nix.
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

echo
printf '%s%-40s %-18s %s%s\n' "$B" "REPO" "BRANCH" "RESULT" "$N"
printf '%s\n' "${report[@]}"
echo
printf '%s%d repos%s: %s%d updated%s, %d up to date, %s%d skipped%s, %s%d failed%s\n' \
  "$B" "${#repos[@]}" "$N" "$G" "$n_new" "$N" "$n_up" "$Y" "$n_skip" "$N" "$R" "$n_fail" "$N"

[ "$n_fail" -eq 0 ]
