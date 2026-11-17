#!/bin/bash
set -euo pipefail

base=${1:?usage: check-commit-messages.sh <base> <head> [pr-title]}
head=${2:?usage: check-commit-messages.sh <base> <head> [pr-title]}
title=${3:-}
pattern='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-zA-Z0-9._/-]+\))?!?: .+'
failed=0

if [[ -n "$title" ]] && [[ ! "$title" =~ $pattern ]]; then
  echo "::error::PR title \"$title\" is not a conventional commit message"
  failed=1
fi

while IFS= read -r line; do
  sha=${line%% *}
  subject=${line#* }
  if [[ ! "$subject" =~ $pattern ]]; then
    echo "::error::commit $sha \"$subject\" is not a conventional commit message"
    failed=1
  fi
done < <(git log --no-merges --format='%h %s' "$base..$head")

if (( failed )); then
  echo "Use <type>(<scope>)!: <description>, with type one of build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test."
fi
exit "$failed"
