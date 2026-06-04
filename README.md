# mainwp-cli

A friendly, scriptable command-line interface for the
[MainWP Dashboard](https://mainwp.com) REST API v2.

Built with **bash** + [gum](https://github.com/charmbracelet/gum) so that
everyday commands feel polished, while power users can pipe JSON around
in shell pipelines.

- Single static binary entry point: `mainwp`
- Per-profile credentials (URL + Bearer token) so you can manage multiple
  MainWP Dashboards from the same machine
- First-class `--json` output for piping into `jq`, scripts, and CI
- Covers every documented v2 endpoint: sites, clients, tags, updates,
  costs, users, settings, monitoring, API keys, posts, pages, and the
  global `/batch` orchestrator
- Installs with a single `brew install` from a Homebrew tap

```
$ mainwp sites list
  ID  Name                URL                       Status
  12  Samay Garden        https://wp.samaygarden…   connected
  19  Dynamic Dutch       https://dynamicdutch.com  connected
```

## Table of contents

- [Requirements](#requirements)
- [Install](#install)
  - [Homebrew (recommended)](#homebrew-recommended)
  - [Manual install](#manual-install)
- [Quick start](#quick-start)
- [Configuration and profiles](#configuration-and-profiles)
- [Global options](#global-options)
- [Commands](#commands)
  - [`init` and `config`](#init-and-config)
  - [`sites`](#sites)
  - [`clients`](#clients)
  - [`tags`](#tags)
  - [`updates`](#updates)
  - [`costs`](#costs)
  - [`users`](#users)
  - [`settings`](#settings)
  - [`monitoring`](#monitoring)
  - [`api-keys`](#api-keys)
  - [`posts` and `pages`](#posts-and-pages)
  - [`batch`](#batch)
- [Output modes](#output-modes)
- [Shell completion](#shell-completion)
- [Environment variables](#environment-variables)
- [Exit codes](#exit-codes)
- [Development](#development)
- [License](#license)

## Requirements

- macOS or Linux
- `bash` 3.2 or newer (the macOS system bash works)
- [`gum`](https://github.com/charmbracelet/gum) (only required for
  interactive prompts and styled output; falls back to plain text when
  missing)
- [`jq`](https://stedolan.github.io/jq/) (used internally for JSON
  shaping; installed automatically by the Homebrew formula)
- A MainWP Dashboard reachable over HTTPS with [REST API v2
  enabled](https://docs.mainwp.com/api-reference/rest-api/overview)

## Install

### Homebrew (recommended)

```bash
brew tap oscarhugopaz/mainwp-cli
brew install mainwp
```

To upgrade later:

```bash
brew update
brew upgrade mainwp
```

### Manual install

```bash
git clone https://github.com/oscarhugopaz/mainwp-cli.git
cd mainwp-cli
sudo install -m 0755 bin/mainwp /usr/local/bin/mainwp
```

You can also drop the directory anywhere on your `$PATH` and symlink the
binary:

```bash
ln -s "$(pwd)/bin/mainwp" /usr/local/bin/mainwp
```

## Quick start

```bash
# 1. Connect the CLI to your MainWP Dashboard. The init wizard asks for
#    the dashboard URL and your Bearer token, then verifies connectivity.
mainwp init

# 2. Try a couple of commands
mainwp sites list
mainwp sites count
mainwp clients list

# 3. Pipe JSON anywhere
mainwp --json sites list | jq '.[] | {id,name,url}'

# 4. Run an update across the whole dashboard
mainwp updates run-all
```

## Configuration and profiles

Credentials are stored in `~/.config/mainwp/config.json` with `0600`
permissions. The file is a tiny JSON document keyed by profile name:

```json
{
  "active": "production",
  "profiles": {
    "default":   { "url": "https://...", "api_key": "..." },
    "staging":   { "url": "https://...", "api_key": "..." },
    "production":{ "url": "https://...", "api_key": "..." }
  }
}
```

Useful subcommands:

| Command                                       | Purpose                                  |
| --------------------------------------------- | ---------------------------------------- |
| `mainwp init`                                 | Interactive setup for the active profile |
| `mainwp config get`                           | Print the active profile as JSON         |
| `mainwp config set url https://dashboard.tld` | Update the dashboard URL                 |
| `mainwp config set key <token>`               | Update the API key (stored 0600)         |
| `mainwp config set api-path wp-json/mainwp/v2`| Override the API base path               |
| `mainwp config profile list`                  | List configured profiles                 |
| `mainwp config profile create NAME`           | Create a new (empty) profile             |
| `mainwp config profile use NAME`              | Switch the active profile                |
| `mainwp config profile delete NAME`           | Delete a profile and its credentials     |
| `mainwp config path`                          | Print the absolute path to the config    |

You can also point to a different config file with the standard
`XDG_CONFIG_HOME` environment variable.

## Global options

These can appear before the subcommand:

| Flag             | Description                                            |
| ---------------- | ------------------------------------------------------ |
| `--profile NAME` | Use a named profile (default: `default`)               |
| `--json`         | Output raw JSON for the API call (no styling)          |
| `--plain`        | Output plain text (skip gum styling even if present)   |
| `--no-input`     | Disable interactive prompts (fail on missing args)    |
| `-q, --quiet`    | Suppress informational messages                        |
| `-V, --version`  | Print version and exit                                 |
| `-h, --help`     | Show the top-level help                                |

After the subcommand, the same flags are accepted where it makes sense
(e.g. `mainwp sites list --json --per-page 5`).

## Commands

### `init` and `config`

See [Configuration and profiles](#configuration-and-profiles). `init` is
a guided walkthrough that prompts for the URL and key and verifies that
`/sites/basic` returns 200.

### `sites`

Manage child sites connected to the dashboard.

```bash
mainwp sites list
mainwp sites basic
mainwp sites count
mainwp sites get 12
mainwp sites security 12
mainwp sites non-mainwp-changes 12
mainwp sites client 12
mainwp sites costs 12
mainwp sites plugins 12
mainwp sites themes 12

# Writes
mainwp sites add --url https://new.tld --name "New site" --admin admin
mainwp sites edit 12 --name "Renamed site"
mainwp sites sync                # all sites
mainwp sites sync 12             # one site
mainwp sites reconnect 12
mainwp sites disconnect 12
mainwp sites check 12
mainwp sites suspend 12
mainwp sites unsuspend 12
mainwp sites remove 12

# Plugins / themes
mainwp sites plugin activate 12 akismet/akismet.php
mainwp sites plugin deactivate 12 akismet/akismet.php
mainwp sites plugin delete 12 akismet/akismet.php
mainwp sites theme activate 12 twentytwentyfour
mainwp sites theme delete 12 twentytwentythree
```

Common filters accepted by `list`/`basic`:

```
--per-page N --page N --search TEXT --status STATUS
--include IDS --exclude IDS --with-tags
```

### `clients`

```bash
mainwp clients list
mainwp clients count
mainwp clients get 34
mainwp clients add --name "Acme" --email ops@acme.com --phone "+1-555-0100"
mainwp clients edit 34 --status active
mainwp clients remove 34
mainwp clients suspend 34
mainwp clients unsuspend 34
mainwp clients sites 34
mainwp clients sites-count 34
mainwp clients costs 34

# Custom client fields
mainwp clients fields list
mainwp clients fields add --name "Account manager"
mainwp clients fields edit 6 --description "Primary owner"
mainwp clients fields delete 6
```

### `tags`

```bash
mainwp tags list
mainwp tags get 7
mainwp tags add --name "Production" --color "#7fb100"
mainwp tags edit 7 --name "Production sites"
mainwp tags remove 7
mainwp tags sites 7
mainwp tags clients 7
```

### `updates`

```bash
mainwp updates list --type plugins
mainwp updates for-site 12
mainwp updates ignored --type plugins
mainwp updates site-ignored 12

# Run updates
mainwp updates run-all
mainwp updates run-site 12
mainwp updates wp 12
mainwp updates plugins 12 --slug akismet/akismet.php
mainwp updates themes 12
mainwp updates translations 12

# Ignore management
mainwp updates ignore-wp 12
mainwp updates ignore-plugins 12 --slug akismet/akismet.php
mainwp updates ignore-themes 12
```

### `costs`

```bash
mainwp costs list
mainwp costs get 22
mainwp costs add \
  --name "Hosting plan" --price 49 --payment-type subscription \
  --product-type hosting --renewal-type monthly --sites 12
mainwp costs edit 22 --price 59
mainwp costs remove 22
mainwp costs sites 22
mainwp costs clients 22
```

### `users`

```bash
mainwp users list --websites 12,19
mainwp users create --username editor01 --email editor01@example.com \
                    --role editor --websites 12 --send-password true
mainwp users edit 12 41 --role author
mainwp users delete 12 41
mainwp users update-admin-password --password 'S3cure!' --groups production
mainwp users import ./users.csv --has-header
```

`users/import` expects a CSV with 10 columns:
`username,email,first_name,last_name,user_url,password,send_password,role,select_sites,select_groups`.

### `settings`

```bash
mainwp settings general get
mainwp settings general set --timezone_string="America/New_York" --frequency_auto_update=weekly

mainwp settings advanced get
mainwp settings advanced set --mainwp_maximum_requests=8 --mainwp_ssl_verify_certificate=1

mainwp settings monitoring get
mainwp settings monitoring set --mainwp_uptime_monitoring_active=1 \
                               --mainwp_uptime_monitoring_interval=5

mainwp settings emails get
mainwp settings emails set daily-digest --disable=1
mainwp settings emails set daily-digest --subject="Today's summary" --recipients=ops@acme.com

mainwp settings cost-tracker get
mainwp settings cost-tracker set --currency=USD --currency_position=left
mainwp settings cost-tracker product-types add --title "Hosting" --color "#ff8800"
mainwp settings cost-tracker product-types edit hosting --title "Web hosting"
mainwp settings cost-tracker product-types delete hosting
mainwp settings cost-tracker payment-methods add --title "Stripe"
mainwp settings cost-tracker payment-methods edit stripe --title "Stripe (renewed)"
mainwp settings cost-tracker payment-methods delete stripe

mainwp settings insights get
mainwp settings insights set --enable_insights_logging=1

mainwp settings api-backups get
mainwp settings api-backups set cloudways --enabled=true --username=api-user

mainwp settings tools get
mainwp settings tools set --mainwp_theme=light --guided_tours=0
mainwp settings tools destroy-sessions
mainwp settings tools destroy-sessions --status <destroy_id>
mainwp settings tools renew-connections
mainwp settings tools disconnect-all-sites
mainwp settings tools clear-activation-data
mainwp settings tools restore-info-messages
```

### `monitoring`

```bash
mainwp monitoring list
mainwp monitoring basic
mainwp monitoring count
mainwp monitoring get 12
mainwp monitoring heartbeat 12 --period 24h
mainwp monitoring incidents 12
mainwp monitoring incidents-count 12
mainwp monitoring check 12
mainwp monitoring settings 12 --interval=5m --timeout=30000 --type=http
mainwp monitoring global-settings --interval=10m --timeout=60000
```

### `api-keys`

```bash
mainwp api-keys list
mainwp api-keys add --active true --permissions read,write --description "Automation"
mainwp api-keys edit 15 --active false
mainwp api-keys delete 15
```

The create response includes the freshly generated token. **Save it
immediately - tokens are only shown once.**

### `posts` and `pages`

Cross-site content management.

```bash
mainwp posts list --status publish --websites 12,19 --maximum 50
mainwp posts get 12 341
mainwp posts create 12 --title "Release notes" --content "..." --status draft
mainwp posts edit 12 341 --status publish
mainwp posts update-status 12 341 publish
mainwp posts delete 12 341

mainwp pages list --status draft --clients 22
mainwp pages get 12 58
mainwp pages create 12 --title "About" --content "..." --status draft
mainwp pages edit 12 58 --post_title "About us"
mainwp pages update-status 12 58 publish
mainwp pages delete 12 58
```

`--extra '<json>'` is available on `posts create` and `pages create`/
`edit` for forwarding arbitrary Gutenberg-compatible fields (categories,
tags, custom meta, etc.).

### `batch`

Run a single batched request across multiple controllers. Useful for
multi-action workflows like "add this tag, sync these sites, and create
this client at once".

```bash
mainwp batch --json '{
  "sites":  { "create": [{"url":"https://a.tld","name":"A","admin":"admin"}], "sync":[12,19] },
  "tags":   { "create": [{"name":"Managed"}] }
}'
mainwp batch ./payload.json
```

The payload must be a valid JSON object. See the [batch endpoint
docs](https://docs.mainwp.com/api-reference/rest-api/batch) for the full
schema.

## Output modes

| Mode      | Trigger              | What you get                                                  |
| --------- | -------------------- | ------------------------------------------------------------- |
| Table     | default (TTY + gum)  | Aligned columns with headers, gum styling                    |
| Plain     | `--plain`            | Tab-separated rows, no gum styling                            |
| JSON      | `--json`             | Raw API response (one JSON document per call)                 |
| Object    | detail endpoints     | Two-column `Field / Value` layout (or JSON with `--json`)     |
| Spinner   | long writes          | `gum spin` while curl runs; non-fatal if gum is missing       |

## Shell completion

```bash
# bash
source <(mainwp completion bash)

# zsh
source <(mainwp completion zsh)
```

The completions are static (no shell-side completion framework required)
and cover every top-level command and subcommand.

## Environment variables

| Variable          | Effect                                                |
| ----------------- | ----------------------------------------------------- |
| `MAINWP_URL`      | Override the dashboard URL from the active profile   |
| `MAINWP_API_KEY`  | Override the API key from the active profile         |
| `XDG_CONFIG_HOME` | Change where the config file is stored               |

Environment variables take precedence over values stored in the config
file - handy in CI.

## Exit codes

| Code | Meaning                                                |
| ---- | ------------------------------------------------------ |
| 0    | Success                                                |
| 1    | API error or other runtime failure (message on stderr) |
| 2    | Invalid usage (unknown command, missing required args) |

## Development

Clone the repo and run the CLI from source:

```bash
git clone https://github.com/oscarhugopaz/mainwp-cli.git
cd mainwp-cli
./bin/mainwp --version
```

Lint and test:

```bash
brew install shellcheck shfmt
shellcheck bin/mainwp lib/*.sh lib/commands/*.sh
shfmt -d bin lib
```

The structure is intentionally small:

```
bin/mainwp                 entry point, dispatches subcommands
lib/                       shared libraries
  output.sh                gum + plain text output helpers
  config.sh                config file + profile management
  api.sh                   curl-based HTTP client
  ui.sh                    gum-based interactive prompts
  commands/                one file per subcommand
    _common.sh             shared helpers (parsing, kv flag collection)
    init.sh, config.sh
    sites.sh, clients.sh, tags.sh, updates.sh, costs.sh
    users.sh, settings.sh, monitoring.sh, api-keys.sh
    posts.sh, pages.sh, batch.sh
    completion.sh
completions/               static bash + zsh completion scripts
tests/                     bats tests (run with: bats tests/)
```

Bash 3.2 compatibility is required (it's the macOS system bash). The
helpers in `_common.sh` use the "printf + eval" trick to mutate global
arrays because bash 3.2 has no `declare -g`.

## Related projects

- [homebrew-mainwp-cli](https://github.com/oscarhugopaz/homebrew-mainwp-cli) -
  the Homebrew tap used by `brew install mainwp`.
- [MainWP REST API v2 docs](https://docs.mainwp.com/api-reference/rest-api/overview)
- [MainWP Postman collection](https://www.postman.com/mainwp/mainwp/collection/ujfddk4/mainwp-rest-api-v2-current)

## License

MIT - see [LICENSE](LICENSE).
