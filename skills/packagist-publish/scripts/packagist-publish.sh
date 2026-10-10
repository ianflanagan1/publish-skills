#!/usr/bin/env bash
#
# Submits a Composer package that is already on GitHub to Packagist, and adds the GitHub
# webhook that keeps Packagist up to date. Each step is skipped when already done, so it is
# safe to re-run after a failure.
#
#   1. Submit the package to Packagist
#   2. Add the GitHub webhook that tells Packagist about new pushes and tags
#
# Usage: packagist-publish.sh <dir>
#
# Needs:
#   The package's origin remote to be a public GitHub repo (run github-publish.sh first)
#   A Packagist API token in the macOS keychain, stored under your Packagist username:
#     security add-generic-password -a <packagist-username> -s packagist-api-token -w
#
# The token is never put on a command line. Runs itself inside this repo's devbox when gh
# or jq isn't on the PATH. Exits 0 when published, 1 otherwise.

set -euo pipefail

KEYCHAIN_SERVICE=packagist-api-token

die() {
    echo "packagist-publish: $*" >&2
    exit 1
}

[ $# -eq 1 ] || die "usage: packagist-publish.sh <dir>"
dir=$(cd "$1" 2>/dev/null && pwd) || die "no such directory: $1"

script_dir=$(cd "$(dirname "$0")" && pwd -P)
if ! command -v gh >/dev/null || ! command -v jq >/dev/null; then
    [ -z "${PUBLISH_SKILLS_IN_DEVBOX:-}" ] || die "gh or jq is missing even inside devbox"
    PUBLISH_SKILLS_IN_DEVBOX=1 exec devbox run --config "$script_dir/../../.." -- \
        "$script_dir/$(basename "$0")" "$dir"
fi

packagist_credentials() {
    local entry
    entry=$(security find-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null) \
        || die "no '$KEYCHAIN_SERVICE' keychain item; see the header of this script"
    PACKAGIST_USER=$(sed -n 's/^ *"acct"<blob>="\(.*\)"$/\1/p' <<<"$entry")
    PACKAGIST_TOKEN=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w)
}

cd "$dir"
[ -f composer.json ] || die "no composer.json in $dir"
package=$(jq -r '.name // empty' composer.json)
[ -n "$package" ] || die "composer.json has no name"

origin=$(git remote get-url origin 2>/dev/null) || die "no origin remote; run github-publish.sh first"
repo=$(sed -E 's#^.*github\.com[:/]##; s#\.git$##' <<<"$origin")
[ "$repo" != "$origin" ] || die "origin is $origin, not a GitHub repo"
visibility=$(gh repo view "$repo" --json visibility --jq '.visibility | ascii_downcase')
[ "$visibility" = public ] || die "$repo is $visibility; Packagist needs a public repo"

[ -n "$(git tag)" ] || echo "Packagist: no tags yet, so only dev-$(git branch --show-current) will be installable" >&2

# 1. Package
if curl -fsS -o /dev/null "https://packagist.org/packages/$package.json" 2>/dev/null; then
    echo "Packagist: $package already exists"
else
    packagist_credentials
    jq -n --arg url "https://github.com/$repo" '{repository: {url: $url}}' \
        | curl -sS --fail-with-body -X POST \
            -H 'Content-Type: application/json' \
            -H @<(printf 'Authorization: Bearer %s:%s\n' "$PACKAGIST_USER" "$PACKAGIST_TOKEN") \
            --data @- \
            https://packagist.org/api/create-package >/dev/null \
        || die "Packagist refused the submission"
    echo "Packagist: submitted $package"
fi

# 2. Webhook
if gh api "repos/$repo/hooks" --jq '.[].config.url' | grep -q 'packagist\.org'; then
    echo "Webhook: Packagist hook already exists"
else
    [ -n "${PACKAGIST_TOKEN:-}" ] || packagist_credentials
    HOOK_URL="https://packagist.org/api/github?username=$PACKAGIST_USER" HOOK_SECRET="$PACKAGIST_TOKEN" \
        jq -n '{name: "web", active: true, events: ["push"], config: {url: env.HOOK_URL, content_type: "json", secret: env.HOOK_SECRET}}' \
        | gh api "repos/$repo/hooks" --method POST --input - >/dev/null \
        || die "could not add the webhook; the gh token needs the admin:repo_hook scope"
    echo "Webhook: added"
fi

echo "Published: https://packagist.org/packages/$package"
