# ccx

> [简体中文](README.md) | English

**A Claude Code API switcher** (terminal command `xx`). One command to switch Claude Code
between the official account and third-party Anthropic-compatible APIs (DeepSeek, Zhipu GLM,
Xiaomi MiMo…).

What sets it apart from other switchers — **it never writes any Claude Code config file**;
switching works purely through environment variables. So:

- 🛡️ **Zero config risk**: it never touches `~/.claude/settings.json`, never opens
  `~/.claude.json` (where MCP lives) — **physically incapable** of losing your MCP / plugins / hooks.
- 🔀 **Parallel terminals**: each terminal can run a different API without interference (process-level isolation).
- ⚡ **One command**: pick in `xx`, then use it for this terminal only or set it as the future default.

```text
  cc-x v0.4.4 · Claude Code API switcher     (default = used by bare `claude` in new terminals)

   ▶ Official          (default)[Logged in]
     DeepSeek                   [Key set] — work
     智谱GLM                    [No key]
     小米MiMo                   [No key]

     New profile
     切换到中文
     Update check: off
     Exit

  ↑↓ move · Enter open · Shift+↑↓ (or PgUp/PgDn) reorder · q quit
```

> **Two builds**: the **native Go build** is recommended — GitHub Releases provide a lightweight
> `xx` / `xx.exe` with no Node.js, for Windows x64, macOS Intel / Apple Silicon, Linux x64 / arm64.
> If you prefer npm, install `@cc-x/cc-x` (command is still `xx`). Both builds are feature-equal.

---

## ccx vs cc-switch

cc-switch is an excellent all-in-one **GUI**; ccx takes the opposite, **minimal** approach:

| | ccx (command `xx`) | cc-switch |
|---|---|---|
| Form | Terminal command (lightweight) | Desktop GUI (full-featured) |
| Scope | Only switches the API | API + MCP + multiple CLIs + prompts… |
| Touches config files? | **No** (env vars only) | Rewrites config files from its own DB |
| Can lose MCP / plugins? | **Impossible by design** | Users have reported it overwriting them |
| Different API per terminal | **Native** (process-level isolation) | Global switch; sessions can interfere |

- **ccx fits you if you** live in the terminal, often run several terminals with different APIs
  in parallel, have been burned by a switcher corrupting your config/MCP, or just want that one job done.
- **cc-switch fits you if you** want a GUI, need to manage MCP and several AI CLIs in one place,
  or prefer an all-in-one tool.

## Install

> Install **Claude Code** first (`claude` on PATH) — "Use this session" launches it. **Open a new terminal** after installing.

**Windows native (recommended)**

```powershell
irm https://github.com/becomeless/cc-x/releases/latest/download/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Programs\ccx` and adds it to your user PATH.

**macOS / Linux native (recommended)**

```bash
curl -fsSL https://github.com/becomeless/cc-x/releases/latest/download/install.sh | sh
```

Installs to `~/.local/bin` (override with `CCX_INSTALL_DIR`) and verifies `checksums.txt`. If that dir
isn't on PATH, follow the printed hint.

**npm, any platform** (needs Node.js ≥ 18)

```bash
npm install -g @cc-x/cc-x
```

Open a new terminal and run `xx --version` to verify.

## Quick start (60 seconds)

1. Open a new terminal and run `xx`. The first run creates 4 default profiles in
   `~/.cc-mini/providers.json` (Official + DeepSeek + Zhipu GLM + Xiaomi MiMo), **with empty keys**.
2. ↑↓ to the one you want → Enter → **Edit** → pick **API key** and paste your key (done locally).
3. Then either:
   - **Set default**: future **new** terminals running bare `claude` use it.
   - **Use this session**: launch Claude right now in this terminal (temporary, parallel-friendly).

## Two activation modes (core concept)

This is the key to ccx. Which API Claude uses is decided by **environment variables**; ccx offers two scopes:

| | Use this session | Set default |
|---|---|---|
| Mechanism | Sets env vars for **this one process** and launches `claude` | Writes the API as **user environment variables** |
| Scope | This terminal only, **ephemeral** (gone when you close it) | **New** terminals running bare `claude` use it |
| Effect on running sessions | **None** | **None** (env vars freeze at process start) |
| Typical use | Several terminals in parallel, each on its own API | Set your everyday "main API" |

**Parallel example**: open 4 terminals and run `xx Official -s`, `xx DeepSeek -s`, `xx 智谱GLM -s`,
`xx 小米MiMo -s` — four Claudes running at once, each on its own API, never interfering.

**Why not switch via a global config file?** Because `settings.json` is shared globally; editing it hits
**running** sessions (a classic symptom: another terminal suddenly reports `... cannot be parsed as a URL`).
Environment variables are process-isolated, sidestepping that trap.

## Command-line usage

```bash
xx                       # open the interactive menu
xx DeepSeek              # "Set default" to the profile named DeepSeek
xx DeepSeek -s           # "Use this session" for DeepSeek and launch Claude (--session)
xx -l                    # list all profiles and their state (--list)
xx --lang en             # UI language for this run (zh / en)
xx --help                # all options
```

`xx <name>` defaults to "Set default"; add `-s` / `--session` for "Use this session".

## Menus & editing

Run `xx` for the main menu: `↑↓` move, `Enter` select, `q` / `Esc` quit. With a profile selected,
**`Shift+↑↓` (or `PgUp`/`PgDn`) reorders** it, saved instantly.

- **Select a profile → Enter** for the action menu: **Use this session** / **Set default** / **Edit** /
  **Delete** (with confirm; keep "Official") / **Back**.
- **New profile** — create an empty profile and open the edit form.
- **Switch to 中文 / English** — instant language toggle, remembered in `lang` in `~/.cc-mini/providers.json`.
- **Update check: off / notify** — see [Checking for updates](#checking-for-updates).
- **Exit**.

```text
  Profile: DeepSeek — work    [Key set]

   ▶ Session    — this terminal only, launches Claude now (great for parallel terminals)
     Set default — used by bare claude in new terminals (running sessions unaffected)
     Edit
     Delete
     Back

  ↑↓ move · Enter select · q back
```

**Edit form**: `↑↓` pick a field, `Enter` to change; "Save & back" / "Discard" at the bottom. Inside a
field, **Enter = keep**, `-` = clear, `Esc` = cancel that field. The first field, **Provider**, is the key
one: picking a provider (from the preset catalog) **auto-fills** the API URL, the three model mappings, and
the auth field (providers with multiple URLs let you choose one first); "Note" is free text.

```text
  Edit profile (↑↓ pick a field, Enter to edit; save/discard at bottom)

   ▶ Provider      : DeepSeek
     Note          : work
     API URL       : https://api.deepseek.com/anthropic
     Auth field    : AUTH_TOKEN
     API key       : ********
     opus  → model : deepseek-v4-pro
     sonnet→ model : deepseek-v4-pro
     haiku → model : deepseek-v4-flash
     effort level  : max

     Show key in plaintext (now hidden)

     Save & back
     Discard
```

## Configuration reference

### Fields

| Field | Environment variable | Notes |
|---|---|---|
| Provider | — | Picked from the preset catalog; auto-fills URL/models/auth. Also the unique key; duplicates get " 2/3…" |
| Note | — | Free text to tell apart multiple profiles of the same provider |
| API URL | `ANTHROPIC_BASE_URL` | Third-party endpoint; empty for Official = use the logged-in session |
| Auth field | — | Put the key in `AUTH_TOKEN` or `API_KEY` (see below) |
| API key | `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY` | Value for the chosen auth field |
| opus → model | `ANTHROPIC_DEFAULT_OPUS_MODEL` | Model the `opus` tier maps to |
| sonnet → model | `ANTHROPIC_DEFAULT_SONNET_MODEL` | Model the `sonnet` tier maps to |
| haiku → model | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Model the `haiku` tier maps to; **background tasks use it too** |
| effort level | `CLAUDE_CODE_EFFORT_LEVEL` | Thinking depth, see below |

> ccx **deliberately does not set** `ANTHROPIC_MODEL` or touch `model` in `settings.json`. You pick the tier
> live with `/model opus\|sonnet\|haiku`, and the mapping translates it to the provider's real model.

### Model mapping & effort

**Why third parties need model mapping:** their endpoints only know their own model names (e.g.
`deepseek-v4-pro`), while Claude Code calls `claude-*` by default — without mapping it errors out. Background
tasks use the `haiku` tier, so `haiku → model` **must be set too** (otherwise: "main chat works but errors
now and then").

**effort (thinking depth):** `low < medium < high < xhigh < max` — higher is smarter but slower and burns
more tokens; `auto` = model default; empty = unset. Note **effort is a Claude-model feature; whether a third
party honors it depends on their implementation**.

Reference config per provider (defaults are pre-seeded):

| Profile | BASE_URL | OPUS / SONNET | HAIKU (incl. background) | effort |
|---|---|---|---|---|
| Official | (empty = logged-in) | — | — | empty / `auto` |
| DeepSeek | `https://api.deepseek.com/anthropic` | `deepseek-v4-pro` | `deepseek-v4-flash` | `max` (recommended) |
| Zhipu GLM | `https://open.bigmodel.cn/api/anthropic` | `GLM-4.7` | `glm-4.5-air` | empty |
| Xiaomi MiMo | `https://api.xiaomimimo.com/anthropic` (pay-as-you-go)<br>`https://token-plan-cn.xiaomimimo.com/anthropic` (TokenPlan) | `mimo-v2.5-pro` | `mimo-v2.5-pro` | empty |

> Model names change as providers update; follow each provider's official docs.

### Auth field: AUTH_TOKEN vs API_KEY

| Option | Request header | Used by |
|---|---|---|
| `ANTHROPIC_AUTH_TOKEN` (default) | `Authorization: Bearer <key>` | Most third-party relays |
| `ANTHROPIC_API_KEY` | `x-api-key: <key>` | The official API, and a few relays that only accept this |

The wrong one yields 401. Switch it under "Auth field"; on switch ccx clears the other to avoid a leftover conflict.

## Multiple accounts & maintaining presets

**Multiple accounts**: several keys for the same provider (personal / work)? Just create multiple profiles —
the second one off the same provider auto-names to `DeepSeek 2`; use **Note** to label them, shown as
"Provider — Note".

**Maintaining the provider catalog**: `presets.json` (shipped with the tool) is the catalog the "Provider"
picker reads. Add a provider to offer a new one — no code change:

```json
[
  {
    "name": "DeepSeek",
    "auth": "AUTH_TOKEN",
    "effort": "max",
    "urls": [ { "label": "Anthropic-compatible", "url": "https://api.deepseek.com/anthropic" } ],
    "models": { "opus": "deepseek-v4-pro", "sonnet": "deepseek-v4-pro", "haiku": "deepseek-v4-flash" }
  }
]
```

- `urls` can hold **several** (e.g. API vs TokenPlan endpoints); you choose one when picking the provider.
- `models` are the recommended three-tier mapping, auto-filled and still editable. `auth` / `effort` are optional.
- You can also drop a custom catalog at `~/.cc-mini/presets.json` to override the shipped one (highest priority).

## Checking for updates

The **Update check** toggle in the main menu is **off by default**. Switch it to **notify** and ccx shows a
one-line yellow notice atop the menu when a newer release exists, with the upgrade command (it never
auto-downloads — you decide when to upgrade).

- No GitHub API; checks at most once a day, cached in `~/.cc-mini/update-check.json`; offline/failure is silent.
- The check runs in the background and won't slow startup — a new version usually shows up on your **next** launch.
- To upgrade, just re-run the install command (native: the one-liner under [Install](#install); npm:
  `npm i -g @cc-x/cc-x@latest`).

## First run: skip login / onboarding

With a third-party API (token auth), Claude Code **may still show a login / onboarding screen on first
launch** — because it hasn't recorded "onboarding done". One-time fix: in `~/.claude.json` (Windows:
`C:\Users\<you>\.claude.json`), **add a single key** to the top-level `{ }` (keep everything else):

```json
{
  "hasCompletedOnboarding": true
}
```

> ⚠️ This file also holds your MCP config — **only add the key, never overwrite the whole file**. ccx
> deliberately won't edit it for you; it's exactly the file a tool shouldn't touch.

## Data & file locations

- **Profiles (plaintext keys, keep local)**: `~/.cc-mini/providers.json` (also holds `lang` and `update`).
- **Provider catalog**: the shipped `presets.json`, or `~/.cc-mini/presets.json` to override.
- **Update-check cache**: `~/.cc-mini/update-check.json`.
- **"Set default" writes user environment variables** (not Claude config files):
  - **Windows** → registry `HKCU\Environment` + one change broadcast;
  - **macOS / Linux** → a `# >>> xx >>>` … `# <<< xx <<<` marker block in the shell startup file
    (idempotent rewrite, chosen by `$SHELL`).
  - Same semantics either way: **only affects new terminals**; switching to "Official" clears all managed vars.
- **It modifies no Claude config file.**

ccx only ever touches these 7 "managed" variables (and clears the ones a target profile doesn't use):
`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `ANTHROPIC_DEFAULT_OPUS_MODEL`,
`ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `CLAUDE_CODE_EFFORT_LEVEL`.

> 💡 To change `settings.json`, use Claude Code's own `/update-config` and describe what you want in natural
> language (e.g. "allow npm commands") — safer than letting an external tool rewrite it.

## FAQ

**Does switching in one terminal affect another running one?** No. "Use this session" is process-level; "Set
default" only affects **new** processes — running sessions froze their env at start.

**I "Set default" but bare `claude` here is still the old one?** Expected — this terminal has the old env.
**Open a new terminal.**

**Seeing `... cannot be parsed as a URL`?** A profile's API URL is an invalid value; Edit to fix or delete it.

**Set effort on a third party but nothing happens?** effort is a Claude-model feature; third parties may not
support it. DeepSeek recommends `max`; otherwise leave it empty.

**Are keys safe?** Stored in plaintext under your home dir, protected by your account. Don't commit
`providers.json` to a repo.

## Uninstall

1. **Clear env vars first**: run "Set default → Official" once in `xx` to clear all managed variables.
2. **Remove the binary**:
   - Windows native:
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = irm https://github.com/becomeless/cc-x/releases/latest/download/install.ps1; & ([scriptblock]::Create($s)) -Uninstall"
     ```
   - macOS / Linux native:
     ```bash
     curl -fsSL https://github.com/becomeless/cc-x/releases/latest/download/install.sh | sh -s -- --uninstall
     ```
   - npm: `npm uninstall -g @cc-x/cc-x`.
   - macOS / Linux, if you used "Set default", also delete the `# >>> xx >>>` marker block in your shell startup file.
3. Delete the data dir `~/.cc-mini/`.

## Design principles

ccx was born from friction I kept hitting with cc-switch — not a criticism; it's powerful, I just wanted a
lighter path. So ccx holds one principle: **simpler is better.** Do one job (switch the API); touch as little
as possible (above all, **never write a Claude Code config file**); before adding a feature, ask whether it
can be left out.

Issues / PRs welcome — but **changes that make it simpler are more welcome than ones that make it more
powerful**, and anything that writes a Claude Code config file will not be accepted.

## License

[MIT](LICENSE)
