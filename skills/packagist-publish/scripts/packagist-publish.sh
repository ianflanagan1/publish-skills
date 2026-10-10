#!/usr/bin/env bash
#
# Submits a PHP Composer package that is already on GitHub to Packagist, and adds the GitHub
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
#   Your Packagist API tokens, stored under your Packagist username in the macOS keychain or,
#   on Linux, the Secret Service keyring (see the publish-skills README):
#     packagist-api-token       the main token
#     packagist-safe-api-token  the safe token
#
# The main token submits the package. The safe token, which can only trigger updates, is the
# webhook secret, because GitHub stores it. Neither is ever put on a command line.
#
# Runs itself inside this repo's devbox when gh or jq isn't on the PATH.
# Exits 0 when published, 1 otherwise.

set -euo pipefail

MAIN_TOKEN_SERVICE=packagist-api-token
SAFE_TOKEN_SERVICE=packagist-safe-api-token

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

missing_credential() {
    die "no '$1' credential; see the setup steps in the publish-skills README"
}

# Prints the username the credential for service $1 is stored under
credential_user() {
    local user
    case "$(uname -s)" in
        Darwin)
            user=$(security find-generic-password -s "$1" 2>/dev/null \
                | sed -n 's/^ *"acct"<blob>="\(.*\)"$/\1/p') ;;
        Linux)
            command -v secret-tool >/dev/null || die "secret-tool is missing; install libsecret-tools"
            user=$(secret-tool search --all service "$1" 2>/dev/null \
                | sed -n 's/^attribute\.username = //p' | head -1) ;;
        *) die "unsupported OS: $(uname -s)" ;;
    esac
    [ -n "$user" ] || missing_credential "$1"
    echo "$user"
}

# Prints the secret of the credential for service $1
credential_secret() {
    local secret
    case "$(uname -s)" in
        Darwin) secret=$(security find-generic-password -s "$1" -w 2>/dev/null) || true ;;
        Linux) secret=$(secret-tool lookup service "$1" 2>/dev/null) || true ;;
        *) die "unsupported OS: $(uname -s)" ;;
    esac
    [ -n "$secret" ] || missing_credential "$1"
    echo "$secret"
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
    user=$(credential_user "$MAIN_TOKEN_SERVICE")
    token=$(credential_secret "$MAIN_TOKEN_SERVICE")
    jq -n --arg url "https://github.com/$repo" '{repository: {url: $url}}' \
        | curl -sS --fail-with-body -X POST \
            -H 'Content-Type: application/json' \
            -H @<(printf 'Authorization: Bearer %s:%s\n' "$user" "$token") \
            --data @- \
            https://packagist.org/api/create-package >/dev/null \
        || die "Packagist refused the submission"
    echo "Packagist: submitted $package"
fi

# 2. Webhook
if gh api "repos/$repo/hooks" --jq '.[].config.url' | grep -q 'packagist\.org'; then
    echo "Webhook: Packagist hook already exists"
else
    user=$(credential_user "$SAFE_TOKEN_SERVICE")
    secret=$(credential_secret "$SAFE_TOKEN_SERVICE")
    HOOK_URL="https://packagist.org/api/github?username=$user" HOOK_SECRET=$secret \
        jq -n '{name: "web", active: true, events: ["push"], config: {url: env.HOOK_URL, content_type: "json", secret: env.HOOK_SECRET}}' \
        | gh api "repos/$repo/hooks" --method POST --input - >/dev/null \
        || die "could not add the webhook; the gh token needs the admin:repo_hook scope"
    echo "Webhook: added"
fi

echo "Published: https://packagist.org/packages/$package"
