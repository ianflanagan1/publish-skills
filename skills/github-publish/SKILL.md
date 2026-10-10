---
name: github-publish
description: Publish a local git repository to GitHub as a public or private repo, push its branch and tags, and wait for CI. Safe to re-run.
argument-hint: <dir> <public|private> [repo-name]
disable-model-invocation: true
---

# GitHub publish

Publish a local repository to GitHub with `scripts/github-publish.sh`, next to this file. The script does every GitHub step; never replace one with your own `gh` or `git push` commands.

## Before running

1. Settle the three arguments from the user's request:
   - `<dir>`: the repository's directory.
   - `<public|private>`: never assume. If the user didn't say, ask.
   - `[repo-name]`: only when it should differ from the directory's name, for example a Composer package `vendor/phpstan-foo` in a directory `foo` gets `phpstan-foo`.
2. The work tree must be clean and on the branch to publish. If it isn't, reply `⚠️ Uncommitted changes.` and what's uncommitted, and stop; don't commit for the user unless they asked.

## Run

```sh
<directory containing this file>/scripts/github-publish.sh <dir> <public|private> [repo-name]
```

The script creates the repo, adds `origin`, pushes the current branch and all tags, and waits for the CI run on the pushed commit. Each step is skipped when already done.

## Report

- Success: a line `✅ Published.`, then the repo URL and the CI result, in one or two lines.
- Failure: a line `❌ Publish failed.`, then the script's error, unchanged, in a fenced `text` code block. For a CI failure, also the failing step from its log tail. Fix the cause and re-run the script; it picks up where it stopped.

If `gh` isn't logged in, reply `⚠️ gh isn't logged in.` and tell the user to follow the setup steps in this skill repo's README. Never ask for a token or try to log in yourself.
