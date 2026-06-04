# ccx

> `xx` — one command to switch Claude Code between APIs. **Zero config risk.**
>
> [简体中文](README.md) | English

Switching Claude Code between the official account and third-party APIs means juggling
environment variables — or trusting a tool that rewrites your Claude config. ccx takes a
different path: **switching happens purely at the environment-variable layer.** It never
reads or writes any Claude Code config file. Your MCP, plugins, hooks — it won't touch them.

```text
  cc-x v0.4.4 · Claude Code API switcher     (default = used by bare `claude` in new terminals)

   ▶ Official          (default)[Logged in]
     DeepSeek                   [Key set] — work
     智谱GLM                    [No key]
     小米MiMo                   [No key]

     New profile  ·  切换到中文  ·  Update check: off  ·  Exit

  ↑↓ move · Enter open · Shift+↑↓ reorder · q quit
```

> **Two builds**: the **native Go build** is recommended — GitHub Releases provide a lightweight
> `xx` / `xx.exe` with no Node.js, for Windows x64, macOS Intel / Apple Silicon, Linux x64 / arm64.
> If you prefer npm, install `@cc-x/cc-x` (command is still `xx`). Both builds are feature-equal.

---

## Install

> Install [Claude Code](https://claude.ai/code) first (`claude` on PATH). **Open a new terminal** after installing.

**Windows (native, recommended)**

```powershell
irm https://github.com/becomeless/cc-x/releases/latest/download/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\Programs\ccx` and adds it to your user PATH automatically — no manual step.

**macOS / Linux (native, recommended)**

```bash
curl -fsSL https://github.com/becomeless/cc-x/releases/latest/download/install.sh | sh
```

Installs to `~/.local/bin`. If that directory isn't on PATH, the installer prints a hint (the Unix
installer deliberately doesn't edit your shell config).

**npm (any platform, Node.js ≥ 18)**

```bash
npm install -g @cc-x/cc-x
```

---

## 60-second quick start

The first run of `xx` seeds 4 profiles in `~/.cc-mini/providers.json` (Official + DeepSeek +
Zhipu GLM + Xiaomi MiMo), **with empty keys**.

1. `xx` → ↑↓ to a profile → Enter → **Edit** → **API key** → paste your key
2. Then either:
   - **Use this session** — launch Claude now in this terminal (temporary, parallel-friendly)
   - **Set default** — bare `claude` in new terminals uses it from now on

```bash
xx                 # open the menu
xx DeepSeek        # set as default
xx DeepSeek -s     # use this session, launch Claude now (--session)
xx -l              # list all profiles and state (--list)
xx --help          # all options
```

---

## Two modes (the key concept)

Which API Claude uses is decided by **environment variables**. ccx offers two scopes:

| | Use this session (`-s`) | Set default |
|---|---|---|
| Mechanism | Sets env vars on this process + launches `claude` | Writes **user environment variables** |
| Scope | This terminal only; **gone when you close it** | **New** terminals going forward |
| Running sessions | Unaffected | Unaffected (env freezes at process start) |
| Best for | Parallel terminals on different APIs | Set your daily-driver API once |

**Parallel example**: open 4 terminals and run `xx Official -s`, `xx DeepSeek -s`, `xx 智谱GLM -s`,
`xx 小米MiMo -s` — four Claudes running at once, each on its own API, zero interference.

**Why not a global config file?** `settings.json` is shared globally; editing it hits running
sessions (classic symptom: another terminal suddenly says `cannot be parsed as a URL`).
Environment variables are naturally process-isolated.

---

## ccx vs cc-switch

cc-switch is an excellent full-featured GUI; ccx takes the opposite, minimal approach.

| | ccx (`xx`) | cc-switch |
|---|---|---|
| Form | Terminal command (lightweight) | Desktop GUI (full-featured) |
| Scope | Just API switching | API + MCP + multiple CLIs + prompts… |
| Touches config? | **Never** (env vars only) | Rewrites config from its own DB |
| Can lose MCP? | **Physically impossible** | Users have reported it |
| Parallel terminals | **Native** (process isolation) | Global switch; sessions can clash |

- → **ccx**: terminal natives, parallel-session runners, anyone burned by a config-wrecking switcher, "just switch the API" people
- → **cc-switch**: GUI preference, all-in-one MCP + multi-CLI management

---

## Design philosophy

> ccx holds one rule: **simpler is better.**

One job (switch the API). Touch as little as possible. Before adding a feature, ask whether it can be left out.

This isn't laziness — it's intentional. The smaller the tool, the fewer surfaces for failure.
Your MCP, plugins, and hooks belong in Claude Code's own config files; ccx doesn't manage them,
and therefore can't break them.

Issues / PRs welcome — **changes that make it simpler are more welcome than ones that make it
more powerful.** Anything that writes a Claude Code config file will not be accepted.

---

## Configuration

### Fields

| Field | Environment variable | Notes |
|---|---|---|
| API URL | `ANTHROPIC_BASE_URL` | Third-party endpoint; empty for Official = logged-in session |
| Auth field | — | `AUTH_TOKEN` (default) or `API_KEY`; **wrong one = 401** |
| API key | `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY` | Value for the chosen auth field |
| opus → model | `ANTHROPIC_DEFAULT_OPUS_MODEL` | Three-tier model mapping; haiku also covers background tasks — **must be set** |
| sonnet → model | `ANTHROPIC_DEFAULT_SONNET_MODEL` | |
| haiku → model | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | |
| effort level | `CLAUDE_CODE_EFFORT_LEVEL` | `low`–`max`; `auto` = model default; empty = unset. Third parties may not honor it |

> ccx **deliberately does not set** `ANTHROPIC_MODEL`. Use `/model opus|sonnet|haiku` in-session;
> the mapping table translates to the provider's real model name.

### Auth field: AUTH_TOKEN vs API_KEY

| Option | Request header | Used by |
|---|---|---|
| `AUTH_TOKEN` (default) | `Authorization: Bearer <key>` | Most third-party relays |
| `API_KEY` | `x-api-key: <key>` | The official API, and a few relays |

### Pre-seeded profiles

| Profile | BASE_URL | OPUS / SONNET | HAIKU (incl. background) | effort |
|---|---|---|---|---|
| Official | empty (logged-in) | — | — | — |
| DeepSeek | `api.deepseek.com/anthropic` | `deepseek-v4-pro` | `deepseek-v4-flash` | `max` (recommended) |
| Zhipu GLM | `open.bigmodel.cn/api/anthropic` | `GLM-4.7` | `glm-4.5-air` | — |
| Xiaomi MiMo | `api.xiaomimimo.com/anthropic` | `mimo-v2.5-pro` | `mimo-v2.5-pro` | — |

> Model names change as providers update. Xiaomi MiMo has both pay-as-you-go and TokenPlan
> endpoints; you pick one when selecting the provider.

### Advanced

- **Multiple accounts**: create multiple profiles from the same provider — names auto-suffix
  with ` 2`, ` 3`… Use **Note** to tell them apart, shown as "Provider — Note".
- **Custom providers**: `presets.json` is the provider catalog; add a JSON entry to offer a new
  one, no code change. Drop `~/.cc-mini/presets.json` to override the shipped catalog.
- **First-launch login prompt**: third-party APIs may still show onboarding. Add
  `"hasCompletedOnboarding": true` to `~/.claude.json` (**only this key** — don't overwrite
  the file; it also holds your MCP config).
- **Update check**: toggle to "notify" in the menu — a yellow one-liner appears atop the menu
  when a new release is out. At most one check per day; never auto-upgrades.

---

## Data & files

- **Profiles (plaintext keys, keep local)**: `~/.cc-mini/providers.json` (also holds `lang` and `update`)
- **Provider catalog**: shipped `presets.json`; override at `~/.cc-mini/presets.json`
- **"Set default" writes user environment variables** (not Claude config files):
  - Windows → registry `HKCU\Environment` + one change broadcast
  - Unix → `# >>> xx >>>` … `# <<< xx <<<` marker block in shell startup file (idempotent rewrite, chosen by `$SHELL`)
  - Same semantics either way: **only affects new terminals**; switching to "Official" clears all managed vars
- **No Claude Code config file is ever modified.**

ccx only touches these 7 "managed" variables (and clears the ones a target profile doesn't use):
`ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `ANTHROPIC_DEFAULT_OPUS_MODEL`,
`ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `CLAUDE_CODE_EFFORT_LEVEL`.

> 💡 To change `settings.json`, use Claude Code's own `/update-config` and describe what you want
> in natural language (e.g. "allow npm commands") — safer than letting an external tool rewrite it.

---

## FAQ

**Does switching in one terminal affect another?** No. "Use this session" is process-scoped;
"Set default" only affects new terminals.

**I set default but bare `claude` here is still the old one?** Expected — this terminal has
the old env. Open a new one.

**Seeing `cannot be parsed as a URL`?** A profile's API URL is invalid. Edit to fix or delete it.

**Set effort on a third party but nothing happens?** effort is a Claude-model feature; third
parties may not support it. DeepSeek recommends `max`; leave empty otherwise.

**Are keys safe?** Plaintext in your home dir, protected by your OS account. Don't commit
`providers.json` to a repo.

---

## Uninstall

1. Clear env vars: `xx` → Official → Set default
2. Remove the binary:
   - Windows native: re-run the [install command](#install) with `-Uninstall`
   - macOS / Linux native: `curl ... | sh -s -- --uninstall`; if you used Set default, also
     delete the `# >>> xx >>>` block in your shell startup file
   - npm: `npm uninstall -g @cc-x/cc-x`
3. Delete data: `rm -rf ~/.cc-mini`

---

## License

[MIT](LICENSE)
