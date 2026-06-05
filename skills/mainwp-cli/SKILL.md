---
name: mainwp-cli
description: Manage a MainWP Dashboard from the terminal. Use this skill when the user asks to interact with child sites, clients, tags, updates, costs, users, settings, monitoring, posts, pages, or REST API keys through the MainWP Dashboard REST API v2.
---

# mainwp CLI

`mainwp` is a command-line interface for the [MainWP Dashboard](https://mainwp.com) REST API v2. It is installed as a single binary, ships with shell completions, and uses [gum](https://github.com/charmbracelet/gum) for interactive prompts and [jq](https://stedolan.github.io/jq/) for JSON shaping. Source: <https://github.com/oscarhugopaz/mainwp-cli>.

## When to use this skill

Load this skill when the user asks to do any of the following through a MainWP Dashboard:

- list, inspect, or modify child **sites** (list, get, add, edit, sync, plugins, themes, suspend, remove, ...)
- run or schedule WordPress core, plugin, theme, or translation **updates**
- manage **clients** or custom client fields
- manage **tags** (site groups)
- manage **cost tracker** records
- create, edit, or delete **users** across child sites
- read or update dashboard **settings** (general, advanced, monitoring, email, cost-tracker, insights, api-backups, tools)
- inspect or update **uptime monitoring** (monitors, heartbeat, incidents)
- manage **REST API keys**
- create, edit, or delete **posts** or **pages** on child sites
- run a global **batch** operation across multiple controllers

Do NOT load this skill for general WordPress administration tasks that do not go through a MainWP Dashboard. Do not load it for non-MainWP sites.

## Setup

### Install the CLI

The user is expected to install the CLI themselves. The agent should not run `brew install` unless the user explicitly asks. Suggest the right command based on the OS:

- macOS / Homebrew (preferred):
  ```bash
  brew tap oscarhugopaz/mainwp-cli
  brew install mainwp
  ```
- Linux or manual: see <https://github.com/oscarhugopaz/mainwp-cli#install>.

After install, verify:

```bash
command -v mainwp && mainwp --version
```

If `gum` or `jq` are missing, `mainwp deps install` will install them. Or `brew install gum jq` on macOS, or the platform package manager on Linux.

### Configure credentials

Check whether a profile is already configured:

```bash
mainwp config get
```

If the result is empty (`{}`), the user has no profile yet. Run the guided setup:

```bash
mainwp init
```

It asks for the dashboard URL (e.g. `https://dashboard.example.com`) and a Bearer API key, stores them in `~/.config/mainwp/config.json` with `0600` permissions, and verifies connectivity with `GET /sites/basic`.

### Multiple dashboards

For more than one dashboard, use named profiles:

```bash
mainwp config profile create staging
mainwp config set url  <URL> --profile staging
mainwp config set key  <KEY> --profile staging
mainwp config profile create production
mainwp config set url  <URL> --profile production
mainwp config set key  <KEY> --profile production

mainwp --profile staging    sites list
mainwp --profile production sites list
```

### CI and one-off commands

For non-interactive use, env vars override the profile:

```bash
MAINWP_URL=https://dashboard.example.com \
MAINWP_API_KEY=xxxxx \
  mainwp sites list
```

`MAINWP_URL` and `MAINWP_API_KEY` are checked in that order: flag, env, profile, error.

## Output formats

The CLI supports three output modes:

| Mode      | Trigger              | What you get                                                                                |
| --------- | -------------------- | ------------------------------------------------------------------------------------------- |
| Table     | default (TTY + gum)  | Aligned columns with headers, gum-styled                                                    |
| Plain     | `--plain`            | Tab-separated text, no styling                                                              |
| JSON      | `--json`             | Raw API response as JSON (one document per call)                                            |
| Object    | detail endpoints     | Two-column `Field / Value` layout (or JSON with `--json`)                                   |

**In scripts, always prefer `--json`.** It is stable, parseable, and the only mode whose output is guaranteed not to change between releases.

```bash
mainwp --json sites list | jq '.data[] | {id, name, url, status}'
```

## Command reference (most useful subset)

The full reference is in the README and in `mainwp --help` / `mainwp help <command>`.

### Sites

```bash
mainwp sites list                          # all child sites
mainwp sites basic                         # lightweight records
mainwp sites count
mainwp sites get 12                        # one site by id or domain
mainwp sites plugins 12                    # plugins on one site
mainwp sites themes 12                     # themes on one site

mainwp sites add --url https://x.tld --name "X" --admin admin
mainwp sites edit 12 --name "Renamed"
mainwp sites sync                          # sync all
mainwp sites sync 12                       # sync one
mainwp sites suspend 12
mainwp sites remove 12                     # destructive, requires confirm

mainwp sites plugin activate  12 akismet/akismet.php
mainwp sites plugin deactivate 12 akismet/akismet.php
```

### Updates

```bash
mainwp updates list --type plugins
mainwp updates run-all
mainwp updates run-site 12
mainwp updates wp 12                       # WordPress core on one site
mainwp updates plugins 12 --slug akismet/akismet.php
mainwp updates ignore-plugins 12 --slug akismet/akismet.php
```

`run-all` and `run-site` return a "started" response immediately. Wait a few minutes, then re-check with `mainwp updates list` to confirm.

### Clients, tags, costs, users

```bash
mainwp clients list
mainwp clients add --name "Acme" --email ops@acme.com
mainwp clients fields add --name "Account manager"

mainwp tags list
mainwp tags add --name "Production" --color "#7fb100"

mainwp costs list
mainwp costs add --name "Hosting" --price 49 --payment-type subscription \
  --product-type hosting --renewal-type monthly --sites 12

mainwp users list --websites 12,19
mainwp users create --username editor01 --email e@x.com --role editor --websites 12
mainwp users update-admin-password --password 'NEW!' --groups production
```

### Settings, monitoring, API keys

```bash
mainwp settings general get
mainwp settings monitoring get
mainwp settings emails set daily-digest --disable=1

mainwp monitoring list
mainwp monitoring check 12
mainwp monitoring settings 12 --interval=5m

mainwp api-keys list
mainwp api-keys add --active true --permissions read,write --description "Automation"
mainwp api-keys delete 15
```

### Posts and pages

```bash
mainwp posts list --status publish --websites 12,19 --maximum 50
mainwp posts create  12 --title "Release notes" --content "..." --status draft
mainwp posts edit    12 341 --status publish
mainwp posts update-status 12 341 publish
mainwp posts delete  12 341

mainwp pages list --clients 22
mainwp pages create 12 --title "About" --content "..." --status draft
```

For the `create`/`edit` calls, pass `--extra '<json>'` to forward arbitrary
post meta, categories, or tags.

### Batch

```bash
mainwp batch --json '{
  "sites": { "create": [{"url":"https://a.tld","name":"A","admin":"admin"}] },
  "tags":  { "create": [{"name":"Production"}] }
}'
```

The payload is a JSON object that maps to MainWP's batch schema; see <https://docs.mainwp.com/api-reference/rest-api/batch>.

## How the CLI is shaped

- **Single binary at `bin/mainwp`.** No Python, no Node, no compiled extensions.
- **Subcommands are one-file-per-feature** under `lib/commands/`. The dispatch is in `bin/mainwp:mainwp_dispatch`.
- **Profiles are JSON** in `~/.config/mainwp/config.json` (chmod `0600`).
- **HTTP client is curl** with the Bearer token in `Authorization`. No SDK.
- **Bash 3.2 compatible** (the macOS system bash). The "printf + eval" trick is used to share global arrays between functions because `declare -g` does not exist in 3.2.

## Common pitfalls

- **Wrong site vs post ID.** Most per-resource endpoints take the site ID first and the resource ID second, e.g. `mainwp posts get 12 341` (site 12, post 341). The help text always shows the order.
- **Tags vs clients vs sites vs posts endpoints differ in id type.** Some accept numeric IDs only, others accept numeric ID or email / domain. Read the API docs before passing strings.
- **Updates are async.** `run-all` and `run-site` start a job and return a "started" response. They do not wait for completion.
- **`--json` is the only mode to use in scripts.** The gum-styled output is for humans; do not pipe it to `jq` or `grep`.
- **`--no-input` exits with an error** if a required argument is missing. Use it for unattended scripts.
- **Cost tracker endpoints require the Cost Tracker add-on** to be enabled on the dashboard.
- **The Bearer token is shown only once** when you create a new API key. Store it immediately.

## Error handling

The CLI exits non-zero on:

- Network errors (host unreachable, TLS issues)
- API errors (4xx/5xx with the API's `message` field printed to stderr)
- Validation errors (missing required args, unknown subcommands)

In scripts, check `$?` after each call. To debug, re-run with `--json` to see the raw response, or with `-q` to suppress informational messages.

## Reference

- CLI source: <https://github.com/oscarhugopaz/mainwp-cli>
- MainWP REST API v2 docs: <https://docs.mainwp.com/api-reference/rest-api/overview>
- Postman collection: <https://www.postman.com/mainwp/mainwp/collection/ujfddk4/mainwp-rest-api-v2-current>
- Top-level help: `mainwp --help`
- Per-command help: `mainwp help <command>`
