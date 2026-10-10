# publish-skills

Claude Code skills for publishing a project: `/github-publish` creates a GitHub repo, pushes and waits for CI. `/packagist-publish` submits a PHP Composer package to Packagist and adds the webhook that keeps it updated.

## Why

Publishing is the same few steps every time, and they touch accounts outside your machine. Scripts make those steps deterministic and safe to re-run, and give an agent two narrow commands to call instead of general access to `gh` and the Packagist API.

## What it does

`skills/github-publish/scripts/github-publish.sh <dir> <public|private> [repo-name]`:

1. Creates the repo under the account `gh` is logged in as, with the description from the project's manifest when it has one: `composer.json`, `package.json`, `Cargo.toml`, `pyproject.toml`, `pom.xml`, `*.csproj` or `*.gemspec`. An existing repo is never edited; if its visibility differs from the one asked for, the script stops.
2. Adds it as the `origin` remote, or checks that `origin` already points at it.
3. Pushes the current branch and all tags.
4. Waits for the CI run on the pushed commit and prints the failing log on failure.

`skills/packagist-publish/scripts/packagist-publish.sh <dir>`:

1. Submits the package to Packagist, reading the name from `composer.json` and the URL from `origin`, which must be a public GitHub repo.
2. Adds the GitHub webhook that tells Packagist about new pushes and tags.

Each step is skipped when it's already done, so after a failure you fix the cause and run the script again. Both scripts refuse to run on a work tree with uncommitted changes, or one without the remote they need.

`gh`, `jq` and `yq` come from this repo's [devbox](https://www.jetify.com/devbox). The scripts run themselves inside it when either is missing from the PATH, so they work from any directory without a global install.

## Setup

Once per machine.

### 1. Install the tools

```sh
cd ~/projects/skills/publish-skills
devbox install
devbox run -- gh config set git_protocol ssh   # push over your existing SSH key
```

`git_protocol` is saved in `gh`'s own config (`~/.config/gh/config.yml`), which every `gh` on the machine shares. Skip that line if `devbox run -- gh config get git_protocol` already prints `ssh`.

### 2. Log gh in with a limited token

Create a **classic** token at <https://github.com/settings/tokens> → *Generate new token (classic)*:

| Scope | Needed for |
|---|---|
| `public_repo` | creating public repos and pushing to them |
| `repo` | instead of `public_repo`, only if you'll publish private repos |
| `workflow` | pushing `.github/workflows/` files |
| `admin:repo_hook` | adding the Packagist webhook |
| `read:org` | nothing in these scripts; `gh auth login` refuses tokens without it. Read-only. |

Copy the token, then log in from the clipboard, so the token never appears on screen or in your scrollback:

```sh
pbpaste | devbox run -- gh auth login --with-token
devbox run -- gh auth status   # check the login and its scopes
```

`gh` keeps the token in the macOS keychain, so you log in once per token. Do it again when the token expires or you replace it.

### 3. Store the Packagist API tokens

Sign in at <https://packagist.org> with GitHub; your first submission claims your vendor name. Your profile page has two tokens, and the script uses each for one job:

| Token | Used for | Why that one |
|---|---|---|
| Main | submitting a new package | Only the main token can create packages. It stays in your keychain. |
| Safe | the webhook secret | The secret is stored on GitHub. The safe token can only trigger package updates, so it does little harm if it leaks. |

Store both in the macOS keychain under your Packagist username. Each command prompts for the token, so it never lands in your shell history:

```sh
security add-generic-password -a <packagist-username> -s packagist-api-token -w       # main
security add-generic-password -a <packagist-username> -s packagist-safe-api-token -w  # safe
```

### 4. Install the skills

Link each skill into Claude Code's skills directory:

```sh
ln -s ~/projects/skills/publish-skills/skills/github-publish ~/.claude/skills/github-publish
ln -s ~/projects/skills/publish-skills/skills/packagist-publish ~/.claude/skills/packagist-publish
```

Or install the plugin, which namespaces the skills as `/publish-skills:github-publish`:

```
/plugin marketplace add ianflanagan1/publish-skills
/plugin install publish-skills@publish-skills
```

### 5. Allow the scripts in Claude Code

In `~/.claude/settings.json`, allow the two scripts and deny direct use of the commands they wrap:

```json
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/skills/github-publish/scripts/github-publish.sh *)",
      "Bash(~/.claude/skills/packagist-publish/scripts/packagist-publish.sh *)"
    ],
    "deny": [
      "Bash(gh repo delete *)",
      "Bash(gh api *)",
      "Bash(gh auth token*)",
      "Bash(security find-generic-password *)"
    ]
  }
}
```

The deny rules stop accidents, not a determined agent: they match command prefixes, so a wrapper script or another tool gets round them. The real limits are the token scopes above.

## Usage

In Claude Code:

```
/github-publish ~/projects/my-tool public
/packagist-publish ~/projects/phpstan-rules/my-rule
```

Or run the scripts yourself:

```sh
skills/github-publish/scripts/github-publish.sh ~/projects/my-tool public
skills/packagist-publish/scripts/packagist-publish.sh ~/projects/phpstan-rules/my-rule
```

Both skills only run when you invoke them; Claude doesn't start publishing because it thinks it's relevant. Other skills can call the scripts as a step of a larger workflow.

## Development

```sh
devbox run lint   # shellcheck
```

## License

MIT
