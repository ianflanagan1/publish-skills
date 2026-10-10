#!/usr/bin/env bash
#
# Prints a project's one-line description from its package manifest, or nothing when it has none.
#
# Usage: manifest-description.sh <dir>
#
# Manifests are tried in this order, and the first with a non-empty description wins:
#
#   composer.json    description                  PHP
#   package.json     description                  JavaScript
#   Cargo.toml       package.description          Rust (or workspace.package.description)
#   pyproject.toml   project.description          Python (or tool.poetry.description)
#   pom.xml          project > description        Java (Maven)
#   *.csproj         PropertyGroup > Description  .NET
#   *.gemspec        summary                      Ruby
#
# A manifest that can't be parsed counts as having no description. Needs jq and mikefarah's yq.
# Exits 0 whether or not it finds a description, 1 on a usage error.

set -uo pipefail

die() {
    echo "manifest-description: $*" >&2
    exit 1
}

[ $# -eq 1 ] || die "usage: manifest-description.sh <dir>"
cd "$1" 2>/dev/null || die "no such directory: $1"

# Prints the first non-empty line of its input
first_line() {
    sed -n '/./{p;q;}'
}

from_json() {
    jq -r '.description // empty' "$1" 2>/dev/null
}

from_toml() {
    yq -p toml -o yaml "$2 // \"\"" "$1" 2>/dev/null
}

from_csproj() {
    yq -p xml -o yaml '[.. | select(tag == "!!map" and has("Description")) | .Description][0] // ""' "$1" 2>/dev/null
}

from_gemspec() {
    sed -n -E "s/^[[:space:]]*[a-z_]+\.summary[[:space:]]*=[[:space:]]*[\"'](.*)[\"'][[:space:]]*\$/\1/p" "$1"
}

description() {
    local file
    [ -f composer.json ] && from_json composer.json
    [ -f package.json ] && from_json package.json
    [ -f Cargo.toml ] && from_toml Cargo.toml '.package.description // .workspace.package.description'
    [ -f pyproject.toml ] && from_toml pyproject.toml '.project.description // .tool.poetry.description'
    [ -f pom.xml ] && yq -p xml -o yaml '.project.description // ""' pom.xml 2>/dev/null
    for file in *.csproj; do
        [ -f "$file" ] && from_csproj "$file"
    done
    for file in *.gemspec; do
        [ -f "$file" ] && from_gemspec "$file"
    done
    return 0
}

description | first_line
