---
name: mainwp-cli
description: Manage a MainWP Dashboard from the terminal. Use this skill when the user asks to interact with child sites, clients, tags, updates, costs, users, settings, monitoring, posts, pages, or REST API keys through the MainWP Dashboard REST API v2.
---

# mainwp CLI

`mainwp` is a command-line interface for the [MainWP Dashboard](https://mainwp.com) REST API v2. It is installed as a single binary, ships with shell completions, and uses [gum](https://github.com/charmbracelet/gum) for interactive prompts and [jq](https://stedolan.github.io/jq/) for JSON shaping. Source: <https://github.com/oscarhugopaz/mainwp-cli>.

Skill bundle version: 0.3.6. Tracks mainwp-cli 0.3.5 and later.

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
- install or update the mainwp-cli skill itself (`mainwp skill install`)

Do NOT load this skill for general WordPress administration tasks that do not go through a MainWP Dashboard. Do not load it for non-MainWP sites.

## Setup

### Install the CLI

The user is expected to install the CLI themselves. The agent should not run `brew install` unless the user explicitly asks. Suggest the right command based on the OS:

- macOS / Homebrew (preferred):
  ```bash
  brew install oscarhugopaz/tap/mainwp-cli
  ```
- Linux or manual: see <https://github.com/oscarhugopaz/mainwp-cli#install>.

After install, verify:

```bash
command -v mainwp && mainwp --version
```

If `gum` or `jq` are missing, the user can run `mainwp deps install` (which is interactive by default and skips if `--no-input` is set). Or they can install the deps directly through the platform package manager.

### Configure credentials

Check whether a profile is already configured:

```bash
mainwp config get
```

If the result is `{}`, the user has no profile yet. Run the guided setup:

```bash
mainwp init
```

It asks for the dashboard URL (e.g. `https://dashboard.example.com`) and a Bearer API key, stores them in `~/.config/mainwp-cli/config.json` with `0600` permissions, and verifies connectivity with `GET /sites/basic`. If the connectivity check fails, the most common reasons are:

- the URL is missing the scheme (must be `https://...`)
- the key has been revoked or does not have the right permissions
- the dashboard permalinks are set to "Plain" - the API requires any other setting
- a firewall is blocking the request

### Self-installation (skill install)

If the SKILL.md is not yet in any of the supported agent locations, suggest or run:

```bash
mainwp skill install
```

This subcommand installs the skill bundle (`SKILL.md` plus any helper files under `skills/mainwp-cli/`) into one or more of: claude-code (`~/.claude/skills/`), codex (`~/.codex/skills/`), pi (`~/.pi/agent/skills/`), opencode (`~/.config/opencode/skills/`), hermes (`~/.hermes/skills/`), or global (`~/.agents/skills/`).

It is interactive by default (`gum choose --no-limit` with space to toggle, enter to confirm); `all` expands to every supported agent. Non-interactive use:

```bash
mainwp skill install --all
mainwp skill install --agent opencode --agent codex
```

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

The `--profile NAME` flag is a *global* option: it must appear before the subcommand (`mainwp --profile staging sites list`, not `mainwp sites --profile staging list`). When the user runs `mainwp init`, the new credentials go into the currently active profile; switch with `mainwp config profile use NAME`.

### CI and one-off commands

For non-interactive use, env vars override the profile:

```bash
MAINWP_URL=https://dashboard.example.com \
MAINWP_API_KEY=xxxxx \
  mainwp sites list
```

`MAINWP_URL` and `MAINWP_API_KEY` are checked in that order: flag, env, profile, error. This is the recommended pattern for CI and for agents that should not write to the user's local config.

## Output formats

The CLI supports three output modes:

| Mode      | Trigger              | What you get                                                                                |
| --------- | -------------------- | ------------------------------------------------------------------------------------------- |
| Table     | default (TTY + gum)  | Aligned columns with gum styling                                                            |
| Plain     | `--plain`            | Tab-separated text, no styling                                                              |
| JSON      | `--json`             | Raw API response (one document per call)                                                    |
| Object    | detail endpoints     | Two-column `Field / Value` layout (or JSON with `--json`)                                   |

The rendered mode depends on the **TTY state of stdout**:

- If `[[ -t 1 ]]` (stdout is a TTY) **and** `gum` is installed, the output is styled with `gum table`.
- Otherwise (piped, redirected, CI, no `gum` on PATH), the CLI falls back to the plain-text path.
- `--plain` forces the plain path even in a TTY.
- `--json` forces the JSON path.

In scripts, **always prefer `--json`**. It is stable, parseable, and the only mode whose output is guaranteed not to change between releases. The default mode (gum or plain) is for human eyes.

```bash
mainwp --json sites list | jq '.data[] | {id, name, url}'
```

### Empty columns are dropped

Since 0.3.5, list endpoints drop columns whose values are all empty. So `mainwp clients list` shows only `ID,Name,Email` (the `Status` field is not part of the clients payload), while `mainwp sites list` still shows `ID,Name,URL,Status` because every site row has a status. An agent should not assume a fixed column set; use `--json` and inspect the response keys to discover what is available.

### Response envelope shapes

The MainWP API does not use a single shape for list endpoints. The CLI normalises every shape through `_mainwp_extract_list` (in `lib/commands/_common.sh`), so callers do not have to. The shapes you may see in `--json` output, and the tables the CLI renders from each, are:

| `--json` response shape           | Renders as                                |
| --------------------------------- | ----------------------------------------- |
| `[a, b, c]` (bare array)           | one row per element                       |
| `{"success":1, "data":[a, b]}`    | one row per element of `data`             |
| `{"data":{"k": [users]}}`          | one row per user; `site` column = `k`     |
| `{"k": obj, "k": obj}` (e.g. tags) | one row per value, with `id` from the key |

For complex jq pipelines against the raw `--json` output, the third and fourth shapes are the ones to be aware of. The CLI handles them automatically; only use this table when you are working around the CLI by hand.

## Common patterns

### List sites

```bash
mainwp sites list
mainwp sites list --status connected --per-page 50
mainwp --json sites list | jq '.data[] | {id, name, url}'
```

The first page returns the full set. Site IDs are numeric strings (`"45"`, `"44"`, etc.) even when the underlying database ID is a different number, so always quote them.

### Run an update across the whole dashboard

```bash
mainwp updates run-all
```

`run-all` and `run-site` return a "started" response immediately. Wait a few minutes, then re-check with `mainwp updates list` to confirm. The API does not give a synchronous "finished" signal.

### Add a child site

```bash
mainwp sites add \
  --url https://new-site.com \
  --name "New Site" \
  --admin admin
```

### Create a client

```bash
mainwp clients add --name "Acme" --email ops@acme.com
```

`Status` is not part of the clients payload - do not pass `--status` here. If the response shows a `Status` column at all, the value will always be empty.

### Update a single post

```bash
mainwp posts update-status 12 341 publish
```

The first ID is the site ID; the second is the post ID. The help text always shows the order.

### Batch operation

```bash
mainwp batch --json '{
  "sites": { "create": [{"url":"https://a.tld","name":"A","admin":"admin"}] },
  "tags":  { "create": [{"name":"Production"}] }
}'
```

The payload must be a valid JSON object that maps to MainWP's batch schema; see <https://docs.mainwp.com/api-reference/rest-api/batch>.

### Sync one or all sites

```bash
mainwp sites sync          # sync all
mainwp sites sync 12       # sync one
```

`mainwp sites sync` with no site ID syncs every connected site; with an ID, it syncs only that one.

## Error handling

The CLI exits non-zero on:

- network errors (host unreachable, TLS issues)
- API errors (4xx/5xx with the API's `message` field printed to stderr)
- validation errors (missing required args, unknown subcommands, unknown agent names)

In scripts, check `$?` after each call. To debug, re-run with `--json` to see the raw response, or with `-q` to suppress informational messages. Common failures:

| Symptom                                                                                 | Likely cause                                                                                              |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `Network error contacting ... : curl: (22) The requested URL returned error: 400`        | A `--key=value` filter was passed to a GET endpoint that does not accept a body; the CLI now passes filters as query args (since 0.3.3), but custom jq-based or curl-direct invocations can still hit this. |
| `Network error contacting ... : curl: (22) The requested URL returned error: 500`        | A server-side failure. The body usually contains `{"code":"...","message":"..."}`. Read with `--json` to inspect. |
| `✗ Unknown sites subcommand: '12'`                                                      | You forgot to pass the subcommand. Use `mainwp sites get 12`, not `mainwp sites 12`.                     |
| `✗ Command 'api-keys' has no entry point.`                                              | Bug fixed in 0.3.2. If you still see it, the user is on a stale install - run `brew update && brew upgrade mainwp-cli`. |
| `No dashboard URL configured for profile 'X'. Run: mainwp init`                          | No profile, no env vars, no flag. Either run `mainwp init` or pass `MAINWP_URL` + `MAINWP_API_KEY`.         |
| `column: line too long`                                                                 | Bug fixed in 0.3.4 (gum + long-value collision). Re-run with `--plain` if you see it.                       |

## How the CLI is shaped

- **Single binary at `bin/mainwp`.** No Python, no Node, no compiled extensions.
- **Subcommands are one-file-per-feature** under `lib/commands/`. The dispatch is in `bin/mainwp:mainwp_dispatch`.
- **Profiles are JSON** in `~/.config/mainwp-cli/config.json` (chmod `0600`).
- **HTTP client is curl** with the Bearer token in `Authorization`. No SDK.
- **Bash 3.2 compatible** (the macOS system bash). The "printf + eval" trick is used to share global arrays between functions because `declare -g` does not exist in 3.2.
- **Three output paths** share the same data: gum (TTY), plain, and JSON. The list renderer drops empty columns automatically.

## Reference

- CLI source: <https://github.com/oscarhugopaz/mainwp-cli>
- MainWP REST API v2 docs: <https://docs.mainwp.com/api-reference/rest-api/overview>
- Postman collection: <https://www.postman.com/mainwp/mainwp/collection/ujfddk4/mainwp-rest-api-v2-current>
- Top-level help: `mainwp --help`
- Per-command help: `mainwp help <command>` or `mainwp <command> --help`
- Skill bundle install: `mainwp skill install`
- Configuration: `mainwp config` (subcommands: `get`, `set`, `profile`, `path`)
