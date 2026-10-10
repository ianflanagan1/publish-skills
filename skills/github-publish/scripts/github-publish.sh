#!/usr/bin/env bash
#
# Publishes a git repository directory to GitHub, under the account gh is logged in as.
# Each step is skipped when already done, so it is safe to re-run after a failure.
#
#   1. Create the GitHub repo
#   2. Add it as the origin remote
#   3. Push the current branch and all tags
#   4. Wait for the CI run on the pushed commit, when the repo has a workflow
#
# Usage: github-publish.sh <dir> <public|private> [repo-name]
#
# repo-name defaults to the directory's name. The repo description comes from composer.json
# or package.json when there is one. An existing repo is never edited: if its visibility
# differs from the one asked for, the script stops.
#
# Runs itself inside this repo's devbox when gh or jq isn't on the PATH.
# Exits 0 when published and CI passed (or there is no CI), 1 otherwise.

set -euo pipefail

die() {
    echo "github-publish: $*" >&2
    exit 1
}

{ [ $# -ge 2 ] && [ $# -le 3 ]; } || die "usage: github-publish.sh <dir> <public|private> [repo-name]"
dir=$(cd "$1" 2>/dev/null && pwd) || die "no such directory: $1"
visibility=$2
case "$visibility" in
    public | private) ;;
    *) die "visibility must be public or private, not '$visibility'" ;;
esac
name=${3:-$(basename "$dir")}

script_dir=$(cd "$(dirname "$0")" && pwd -P)
if ! command -v gh >/dev/null || ! command -v jq >/dev/null; then
    [ -z "${PUBLISH_SKILLS_IN_DEVBOX:-}" ] || die "gh or jq is missing even inside devbox"
    PUBLISH_SKILLS_IN_DEVBOX=1 exec devbox run --config "$script_dir/../../.." -- \
        "$script_dir/$(basename "$0")" "$dir" "$visibility" "$name"
fi

cd "$dir"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$dir is not a git repository"
[ -z "$(git status --porcelain)" ] || die "uncommitted changes in $dir"
branch=$(git branch --show-current)
[ -n "$branch" ] || die "HEAD is detached in $dir"

owner=$(gh api user --jq .login)
repo="$owner/$name"

description=""
for manifest in composer.json package.json; do
    if [ -f "$manifest" ]; then
        description=$(jq -r '.description // ""' "$manifest")
        break
    fi
done

# 1. Repo
if gh repo view "$repo" >/dev/null 2>&1; then
    actual=$(gh repo view "$repo" --json visibility --jq '.visibility | ascii_downcase')
    [ "$actual" = "$visibility" ] || die "$repo already exists and is $actual, not $visibility"
    echo "GitHub: $repo already exists"
else
    gh repo create "$repo" "--$visibility" --description "$description"
fi

# 2. Remote
if origin=$(git remote get-url origin 2>/dev/null); then
    case "$origin" in
        *github.com[:/]"$repo" | *github.com[:/]"$repo".git) ;;
        *) die "origin is $origin, not $repo" ;;
    esac
else
    git remote add origin "git@github.com:$repo.git"
fi

# 3. Push
git push -u origin "$branch"
git push origin --tags

# 4. CI
shopt -s nullglob
workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
shopt -u nullglob
if [ ${#workflows[@]} -eq 0 ]; then
    echo "CI: no workflows"
else
    commit=$(git rev-parse HEAD)
    run_id=""
    for _ in $(seq 1 20); do
        run_id=$(gh run list --repo "$repo" --commit "$commit" --limit 1 --json databaseId --jq '.[0].databaseId // empty')
        [ -n "$run_id" ] && break
        sleep 3
    done
    [ -n "$run_id" ] || die "no CI run started for $commit"

    if gh run watch "$run_id" --repo "$repo" --exit-status >/dev/null; then
        echo "CI: passed"
    else
        gh run view "$run_id" --repo "$repo" --log-failed | tail -50 >&2
        die "CI failed: https://github.com/$repo/actions/runs/$run_id"
    fi
fi

echo "Published: https://github.com/$repo"
