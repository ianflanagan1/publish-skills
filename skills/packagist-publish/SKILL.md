---
name: packagist-publish
description: Submit a Composer package that is already a public GitHub repo to Packagist, and add the GitHub webhook that keeps it updated. Safe to re-run.
argument-hint: <dir>
disable-model-invocation: true
---

# Packagist publish

Publish a Composer package to Packagist with `scripts/packagist-publish.sh`, next to this file. The script does every Packagist and webhook step; never call the Packagist API or add hooks yourself.

## Before running

1. `<dir>` is the package's directory. It needs a `composer.json` with a `name`, and an `origin` remote that is a **public** GitHub repo. If there's no remote yet, publish to GitHub first with the github-publish skill's script, `../github-publish/scripts/github-publish.sh <dir> public [repo-name]`.
2. Check the package has a version tag. Without one, Packagist only offers `dev-<branch>`. If there's none, ask the user which version to tag before going on.

## Run

```sh
<directory containing this file>/scripts/packagist-publish.sh <dir>
```

The script submits the package and adds the webhook. Each step is skipped when already done.

## Report

- Success: the Packagist URL, in one line. Packagist reads the repo a few seconds after submission, so the page may briefly show no versions.
- Failure: the script's error, unchanged.

If the keychain item is missing or `gh` isn't logged in, tell the user to follow the setup steps in this skill repo's README. Never ask for a token, read the keychain, or try to log in yourself.
