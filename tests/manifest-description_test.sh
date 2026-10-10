#!/bin/sh
# Behaviour of skills/github-publish/scripts/manifest-description.sh. Run with tests/run.sh.

root=$(cd "$(dirname "$0")/.." && pwd)
manifest_description=$root/skills/github-publish/scripts/manifest-description.sh

setUp() {
    project=$(mktemp -d "${SHUNIT_TMPDIR:-${TMPDIR:-/tmp}}/test.XXXXXX")
}

tearDown() {
    rm -rf "$project"
}

description() {
    bash "$manifest_description" "$project"
}

test_reads_the_description_from_composer_json() {
    echo '{"name": "a/b", "description": "A PHP package"}' >"$project/composer.json"
    assertEquals 'A PHP package' "$(description)"
}

test_reads_the_description_from_package_json() {
    echo '{"name": "b", "description": "A Node package"}' >"$project/package.json"
    assertEquals 'A Node package' "$(description)"
}

test_reads_the_package_description_from_cargo_toml() {
    printf '[package]\nname = "b"\ndescription = "A Rust crate"\n' >"$project/Cargo.toml"
    assertEquals 'A Rust crate' "$(description)"
}

test_reads_a_workspace_package_description_from_cargo_toml() {
    printf '[workspace.package]\ndescription = "A Rust workspace"\n' >"$project/Cargo.toml"
    assertEquals 'A Rust workspace' "$(description)"
}

test_reads_the_project_description_from_pyproject_toml() {
    printf '[project]\nname = "b"\ndescription = "A Python project"\n' >"$project/pyproject.toml"
    assertEquals 'A Python project' "$(description)"
}

test_reads_a_poetry_description_from_pyproject_toml() {
    printf '[tool.poetry]\nname = "b"\ndescription = "A Poetry project"\n' >"$project/pyproject.toml"
    assertEquals 'A Poetry project' "$(description)"
}

test_reads_the_description_from_a_namespaced_pom_xml() {
    cat >"$project/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <artifactId>b</artifactId>
  <description>A Maven project</description>
</project>
XML
    assertEquals 'A Maven project' "$(description)"
}

test_reads_the_description_from_any_property_group_of_a_csproj() {
    cat >"$project/Tool.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <PropertyGroup>
    <Description>A .NET project</Description>
  </PropertyGroup>
</Project>
XML
    assertEquals 'A .NET project' "$(description)"
}

test_reads_the_summary_from_a_gemspec_in_either_quote_style() {
    printf 'Gem::Specification.new do |spec|\n  spec.summary = "A Ruby gem"\nend\n' >"$project/b.gemspec"
    assertEquals 'A Ruby gem' "$(description)"
    printf "Gem::Specification.new do |s|\n  s.summary     = 'A Ruby gem'\nend\n" >"$project/b.gemspec"
    assertEquals 'A Ruby gem' "$(description)"
}

test_keeps_colons_and_quotes_in_a_toml_or_xml_description() {
    printf '[package]\ndescription = "Tool: does \\"things\\" fast"\n' >"$project/Cargo.toml"
    assertEquals 'Tool: does "things" fast' "$(description)"
    rm "$project/Cargo.toml"
    printf '<project><description>Tool: does "things" fast</description></project>\n' >"$project/pom.xml"
    assertEquals 'Tool: does "things" fast' "$(description)"
}

test_prefers_composer_json_over_other_manifests() {
    echo '{"description": "From composer"}' >"$project/composer.json"
    echo '{"description": "From package"}' >"$project/package.json"
    assertEquals 'From composer' "$(description)"
}

test_skips_a_manifest_without_a_description() {
    echo '{"name": "a/b"}' >"$project/composer.json"
    echo '{"description": "From package"}' >"$project/package.json"
    assertEquals 'From package' "$(description)"
}

test_prints_nothing_and_succeeds_without_a_manifest() {
    out=$(description)
    assertEquals 0 $?
    assertEquals '' "$out"
}

test_prints_nothing_for_a_manifest_it_cannot_parse() {
    echo 'not json' >"$project/composer.json"
    assertEquals '' "$(description 2>/dev/null)"
}

# shellcheck disable=SC1090
. "$SHUNIT2"
