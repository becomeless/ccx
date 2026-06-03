# ccx → npm/TypeScript 重写：交接文档 / 任务清单

> 本文件是 **跨上下文窗口的唯一事实来源（source of truth）**。
> 接手时先读完本文，再读 `AGENTS.md`，然后看 `src/` 当前实现。
> 每完成一个里程碑，回来勾选下方 checklist 并补充「已知问题 / 进度笔记」。
>
> 本文件现在是 npm/TypeScript 版的实施记录与维护来源。Go 二进制方案已放弃并从 `main` 移除。

---

## 0. 一句话目标

把现有 PowerShell-only 的 `ccx`（命令 `xx`）重写为 **npm 全局包**（TypeScript），
做到 **`npm install -g @cc-x/cc-x` 一条命令跨平台安装**、Windows / macOS / Linux 同一套代码、
并内建 **中英文切换（i18n）**。
行为、数据格式、铁律与现版完全对齐，体验只能更好、不能更差。

---

## 1. 已锁定的决策（不要再推翻，除非用户明确改主意）

| 项 | 决策 | 理由 |
|---|---|---|
| 语言 | **TypeScript**（Node.js ≥18） | 与 Claude Code 同生态；npm 分发零摩擦；用户必有 Node.js |
| 菜单 UI | **全自绘 ANSI 列表（raw keypress）+ cooked readline 文本输入**（不上 Ink，**也弃用 inquirer**） | M4 实测：inquirer 的 readline 与自绘菜单的 raw 模式抢 stdin、收不到按键。改回 PS 原版双机制：菜单/ASCII 字段走 raw keypress（同一套，验证可用），中文字段走 `node:readline` cooked 模式（兼容输入法，评审④）。同一时刻只跑一套，互不干扰。Ink/inquirer 均不采用 |
| JSON | 原生 `JSON.parse`/`stringify` | `providers.json` / `presets.json` 格式**保持不变**，老用户零迁移 |
| presets 兜底 | **`src/config/presets.ts` 的 `BUILTIN_PRESETS` 常量** | 等价于现 `$BuiltinPresetsJson`；加载优先级 **用户 `~/.cc-mini/presets.json` > 包内 `presets.json` > 内置常量**（评审⑤） |
| i18n | **单文件 `src/i18n/messages.ts`**（`key→{zh,en}`），逻辑层禁止硬编码中文 | 实际未用双 JSON（tsc 不拷 JSON 到 dist、import 断言跨版本坑）；中英同处一行，便于维护与审阅，详见 §5 偏离说明 |
| 首版平台 | **Windows / macOS / Linux 同时** | npm 没有平台编译差异，天然全平台 |
| 分发 | **npm registry**（`npm install -g @cc-x/cc-x`） | 一条命令装好，一条命令更新，零自建分发 |
| 主线 | `main` 只维护 npm/TypeScript 版；旧 PowerShell 版通过历史 tag 归档 | 避免两套实现长期并行 |

仓库：`github.com/becomeless/cc-x`（origin，HTTPS）。`gh` CLI 可用（v2.90）。

> **npm 包名（已定）**：`ccx` 已被占用（1.0.0）；`cc-x` 看似可用（`npm view` 报 404），但 **npm 的相似名规则**
>   会把连字符去掉再比对（`cc-x`→`ccx`），无作用域的 `cc-x` 发布时被 E403「too similar to existing package ccx」拒绝。
>   最终改用**作用域包 `@cc-x/cc-x`**（作用域豁免相似名规则；`becomeless` 组织名已被占用，故作用域用 `@cc-x`，GitHub 仓库仍是 `becomeless/cc-x`）。
>   **命令名仍是 `xx`**（`package.json` 的 `bin: { "xx": ... }`），不受包名影响。安装：`npm i -g @cc-x/cc-x`。

---

## 1.5 架构师评审补充（2026-06-02，对照真实 `xx.ps1` 逐行核出的 6 点）

> 这 6 条是 plan 原稿没覆盖到位的地方，**实现时务必照办**。其中 ①④ 是「中英文切换」的两个真陷阱。

**① 🔴 i18n 数据层 sentinel：`"官方"` 既是显示文案、又是数据主键 —— 必须拆开。**
真实代码里 `"官方"` 是贯穿全局的判断条件（`name -eq '官方'` → 显示"登录态"`xx.ps1:170`、跳过缺密钥警告
`:233/:259`、删除时"建议保留"`:629`），而 `name` 同时是 providers.json 的**唯一主键**（`current`/`xx <name>`/删除全靠它）。
**不能既翻译它显示成 "Official" 又拿它当稳定 key。** 修法：数据层加稳定标识 `builtin`（官方档 = `"official"`），
代码判断优先认 `builtin === 'official'`，中/英只是它的**显示名**。
读旧文件容错：没有 `builtin` 字段时，仅当 `name === '官方' && env 为空` 才认作官方档。
**不采用「仅以 env 为空」判定官方**——半创建/未填 base 的第三方档 env 也可能是空，会误判。
（M1 已落地：`Provider.builtin?: string`，官方档 `builtin:'official'`；`defaultStore()` 写它、`isOfficial()` 读它。）
DeepSeek/智谱GLM/小米MiMo 是专有名词，**保持原样不翻译**，只有"官方"这个普通名词需要这层拆分。

**② 🔴 Windows 上 `claude` 是 `claude.cmd`（npm shim），Session-Launch 不是白嫖。**
plan 把"inherit stdio 天然解决"当红利——这对 macOS/Linux 成立，**对 Windows 过于乐观**：
`spawn('claude')` 不带 `shell:true` 找不到 `.cmd`；带了 `shell:true`+`stdio:inherit` 又易破坏 Ctrl+C/TTY 信号。
做法：用 `which` 解析真实路径，对 `.cmd` 单独处理，**Windows 上必须实测信号与 TTY**，别假设白嫖。

**③ 🟡 Windows 持久化钉死 `powershell.exe`（5.1，必然存在），不是 `pwsh`（7+，用户可能没装）。**
把现版 `Set-UserEnv-Fast`（注册表循环写 `HKCU:\Environment`）+ `Invoke-EnvBroadcast`（单次 100ms
`WM_SETTINGCHANGE` 广播）原样搬成一段 here-string，用 `child_process` 调 `powershell.exe -NoProfile -Command`。

**④ 🟡 文本输入用 readline/cooked 模式，别用 raw 逐字符读 —— 为兼容中文输入法。**
真实代码特意分两套：密钥/模型用 raw 逐键（`Read-Value`），**中文名称/备注用 `Read-Host`**（注释明说"兼容输入法"）。
raw 逐字符读中文会让输入法组词崩。**（M4 落地修正：当时倾向 `@inquirer/prompts` 的 cooked 模式，但实测它与自绘菜单的
raw 模式抢 stdin、文本输入收不到字；最终改用 `node:readline` 的 cooked 模式实现 `readText`，inquirer 一并弃用。见决策表 + §12。）**

**⑤ 🟢 presets 支持用户覆盖：`~/.cc-mini/presets.json`（可选）> 内置常量兜底。**
现版从脚本同目录读 presets.json、用户可直接改加供应商；npm 全局装后文件躲在 node_modules 里不好改。
改成优先读用户目录的 `presets.json`，加供应商不必动 node_modules、也不必等发版。

**⑥ 🟢 `--default-scope process` 在 Node 里重定义为「不落盘 dry-run」。**
PS 里它写进程作用域；Node 进程一退即没、无意义。它真实用途是**测试时不写注册表/不写 rc 文件**——
在 Node 里就定义成"算好 env + 更新 store.current，但跳过平台持久化"的 dry-run，文档讲清。

---

## 2. 铁律（违反即作废，来自 CLAUDE.md）

**ccx 永远不写任何 Claude Code 配置文件** —— 不写 `~/.claude/settings.json`、不碰 `~/.claude.json`（MCP 配置）。
它 **只通过环境变量切换 API**。这是工具存在的全部理由（不可能误伤用户的 MCP/插件/hooks）。

- ccx 允许写自己的运行数据 `~/.cc-mini/providers.json`。
- 「设为默认」在 Unix 上写 shell 启动文件（`.zshrc`/`.bashrc`）—— 这与现版 `install.ps1` 改 `$PROFILE`
  同性质，**不碰 `~/.claude`，不违反铁律**。这是 Unix 上唯一的「持久化用户环境变量」手段。
- 任何写 Claude Code config 文件的设计都要拒绝。拿不准时，选「让工具更简单」的那条路。

### 受管的 7 个环境变量（只动这些，其它一律不碰）

```
ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN
ANTHROPIC_API_KEY
ANTHROPIC_DEFAULT_OPUS_MODEL
ANTHROPIC_DEFAULT_SONNET_MODEL
ANTHROPIC_DEFAULT_HAIKU_MODEL
CLAUDE_CODE_EFFORT_LEVEL
```

**故意不设** `ANTHROPIC_MODEL`（模型选择交给会话内 `/model`；三个 `*_MODEL` 把 opus/sonnet/haiku 映射到各家真实模型名）。
启用某配置时：该配置用到的键 → 设值；没用到的受管键 → 清除。

---

## 3. 数据格式（必须保持兼容，老用户文件能直接读）

### 3.1 `~/.cc-mini/providers.json`（用户配置，含明文密钥，**绝不提交**）

Windows 路径用 `%USERPROFILE%\.cc-mini\providers.json`；Unix 用 `$HOME/.cc-mini/providers.json`。
Node 里统一用 `os.homedir()`。可被 `--store-dir` 覆盖（测试用）。

结构（字段名、大小写、嵌套必须一致）：

```json
{
  "current": "官方",
  "providers": [
    { "name": "官方", "note": "", "env": {} },
    {
      "name": "DeepSeek", "note": "备注可空",
      "env": {
        "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "sk-...",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
        "CLAUDE_CODE_EFFORT_LEVEL": "max"
      }
    }
  ]
}
```

- `env` **只存非空的受管键**（按 KnownKeys 顺序，跳过空白值）。
- `name` 是唯一键（`current`、`xx <name>`、删除都靠它）。同供应商可多条，靠 `note` 区分。
- 首次运行若文件不存在：用内置默认（官方 + DeepSeek + 智谱GLM + 小米MiMo，密钥空）生成。
- **新增字段**：顶层 `"lang": "zh"`（缺省视为 `zh`）。读时容错：旧文件没有该字段不报错。
- 写入：UTF-8 **无 BOM**；缩进 2 空格。

### 3.1.1 模型名的 `[1m]` 后缀处理（来自官方 model-config 文档）

`[1m]` 是 Claude Code 的**上下文窗口标记**：把 `opus`/`sonnet` 别名切到 100 万 token 上下文，可附加到
`ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_SONNET_MODEL`（例：`claude-opus-4-8[1m]`）。
**剥离逻辑在 Claude Code**——CC 把模型 ID 发给 provider 前会自己删掉 `[1m]`，**不是我们的活**。

对 cc-x 的影响 = **几乎零代码**（模型字段本就是自由文本，原样存进 env var）。要守住 3 条边界：

1. **不要清洗/校验掉方括号** —— 模型输入框保持 free-text 原样存储，重写时别手贱加正则把 `[1m]` 过滤掉。
2. **`[1m]` 只对官方 Anthropic 模型（Opus4.6+/Sonnet4.6）有意义** —— 第三方中转（DeepSeek/GLM/MiMo）加它无意义甚至有害
   （CC 剥后缀后第三方不一定支持 1M，可能报错）。**presets 目录里第三方供应商绝不预置 `[1m]`。**
3. **仅 OPUS/SONNET 两个变量适用，HAIKU 不带**（haiku 不支持 1M；它是 per-variable 读取，非 per-model）。

可选增强（follow-up，非首版）：编辑表单给 opus/sonnet 行加「☐ 1M 上下文」开关，勾选自动在模型名尾部加/去 `[1m]`，
并提示"仅 Anthropic 官方模型有效，第三方勿用"。省去手敲方括号、防止误用。

### 3.2 `presets.json`（供应商目录，随仓库分发 + 内置兜底）

每条：`{ name, auth, urls:[{label,url}], models:{opus,sonnet,haiku}, effort? }`。
- `auth`：`"AUTH_TOKEN"`（Bearer，多数第三方）或 `"API_KEY"`（x-api-key，官方/少数）。
- `urls`：可多个（如 MiMo 有「按量付费API」「TokenPlan」两个），多个时让用户选。
- `models`：推荐的三档映射；`effort` 可选（DeepSeek=max，其余多为空）。
- 选了某供应商 → 自动填 base url（多 url 弹选择）、三档模型、auth 字段、effort。
- 运行时加载优先级（评审⑤，已落地于 `src/config/presets.ts`）：**用户 `~/.cc-mini/presets.json`（可选）> 包内 `presets.json` >
  内置 `BUILTIN_PRESETS` 常量**；任一步文件缺失/解析失败都安静跌落下一步，绝不抛错中断启动。

---

## 4. 两种启用模式（核心，逐字对齐现版语义）

### 4.1 本次启用（Session-Launch）—— 进程级、阅后即焚
1. 取目标配置的 env map。
2. 对 7 个受管键：有值 `process.env[key] = value`，没值 `delete process.env[key]`（**只动这 7 个**）。
3. 找到 `claude` 可执行（`which`/`where` 查找；找不到给红字提示并返回）。
4. `child_process.spawn('claude', [], { stdio: 'inherit' })` —— **stdio inherit 天然把真实控制台句柄
   传给子进程**，不会像 PowerShell 的 `pwsh -File` 那样把 stdin 包成管道导致 claude 误判 `isTTY`。
5. 等 claude 退出后返回（菜单场景回到上级菜单；CLI 场景结束）。
6. 多终端并行各跑各的 API、互不干扰。

### 4.2 设为默认（Set-Default）—— 持久化用户环境变量，仅影响**新开**终端
对 7 个受管键：目标配置有值的写值，没值的清除。然后 `store.current = name` 并存盘。

**平台分叉（唯一有平台差异的地方）：**

- **Windows**：
  1. 出于零原生依赖的考虑，通过 `child_process.execSync` 调用 PowerShell 完成注册表写入 +
     单次 `WM_SETTINGCHANGE` 广播。逻辑与现版 `Set-RegistryAndBroadcast` 完全一致：
     - 直写 `HKCU\Environment`：有值 `SetValue`，无值 `DeleteValue`
     - 只广播一次（`SendMessageTimeout`，超时 100ms，`lParam="Environment"`）
  2. 备选方案：如果未来想摘掉 PowerShell 依赖，可引入 `node-ffi` 或写极小 `.node` addon——
     但 v1 不折腾，PowerShell 在 Windows 上必然存在。
  3. 绝不用「逐个 setx」——广播 7 次太慢。

- **macOS / Linux**：写 shell 启动文件里的 **marker 块**（幂等，可重复重写）：
  ```sh
  # >>> xx >>>
  export ANTHROPIC_BASE_URL="https://..."
  export ANTHROPIC_AUTH_TOKEN="sk-..."
  # ...只导出当前配置用到的受管键
  # <<< xx <<<
  ```
  - 每次「设为默认」**整体重写**这个块（用正则定位 `# >>> xx >>>` … `# <<< xx <<<`，替换或追加）。
    重写即自动「清除」上个默认里多余的 export（块里只剩当前配置的键）。
  - 选哪个文件：按 `$SHELL` basename — `zsh`→`~/.zshrc`，`bash`→ macOS 用 `~/.bash_profile`（登录 shell）、
    Linux 用 `~/.bashrc`；都没有就 `~/.profile`。
  - **fish 语法不同**（`set -gx K V`，无 `export`）：v1 可先不支持，检测到 fish 给提示「请手动设置或用本次启用」；
    或单独写 `~/.config/fish/config.fish` 的 fish 块。列为 follow-up。
  - 语义与 Windows 一致：**只影响新开终端，不动正在运行的会话**（rc 文件只在新交互 shell 启动时加载）。

---

## 5. i18n 设计（中英文切换）

> **实现偏离（2026-06-02，M2 已落地）**：本节原稿设想 `zh.json` + `en.json` 两个文件，实际改为**单个
> `src/i18n/messages.ts`**（`key → { zh, en }`）。原因：tsc 不会把 JSON 拷进 dist，需额外构建步骤 + import 断言的
> 跨 Node 版本坑；单 TS 目录零文件 IO、中英同处一行不易漏翻。需要外部审阅或同步时，一行 `JSON.stringify(messages)`
> 即可导出双语 JSON。`T()` / `resolveLang` / `setLang` / `providerDisplayName` 在 `src/i18n/index.ts`；
> CJK 宽度对齐在 `src/utils/display.ts`（基于 `string-width`）。下面的 JSON 示例仅作 key 命名参考。

- **实际实现**：`src/i18n/messages.ts` 导出 `messages: Record<string, { zh, en }>`（单目录，key 命名如 `menu.exit`/`state.login`）。
  ```ts
  export const messages = {
    'menu.exit': { zh: '退出', en: 'Exit' },
    'list.default': { zh: '默认配置：{0}', en: 'Default: {0}' }, // 占位符 {0} {1}…
  };
  ```
- `src/i18n/index.ts`：`T(key, ...args): string` —— 查当前语言文案、按序替换 `{0}`，
  缺 key 返回 key 本身、缺当前语言回退 `zh`（便于发现漏翻）。另含 `setLang`/`getLang`/`resolveLang`/`providerDisplayName`。
- 语言来源优先级：`--lang en` 参数 > `providers.json` 的 `lang` 字段 > 环境 `LC_ALL`/`LANG`（含 `zh` 视为中文）> 默认 `zh`。
- 主菜单加一项「语言 / Language」即时切换并存盘（写回 `lang` 字段）。
- **所有 user-facing 字符串都走 `T()`**；提交前 grep 确认逻辑层无裸中英文硬编码。
- 需要时可从 `messages.ts` 导出双语 JSON 快照，供文案审阅或外部工具消费。
- CJK 宽度对齐：用 `string-width`（npm 包，封装了 `eastasianwidth`）处理全角=2 半角=1。
- ⚠️ **两个跨语言真陷阱见 §1.5 ①④**：①数据层 `"官方"` sentinel 与主键冲突（要拆 `builtin` 标识）；
  ④文本输入必须走 cooked 模式兼容中文输入法。i18n 不止是「UI 字符串抽 JSON」，这两条才是难点。

---

## 6. CLI 参数（对齐现版 + 新增 --lang）

| 现版（PowerShell） | npm 版 | 行为 |
|---|---|---|
| `xx` | `xx` | 打开交互菜单 |
| `xx DeepSeek` | `xx DeepSeek` | 设为默认到该配置 |
| `xx DeepSeek -Session` | `xx DeepSeek --session` / `-s` | 本次启用并启动 claude |
| `xx -List` | `xx --list` / `-l` | 列出所有配置及状态 |
| `xx -StoreDir <d>` | `xx --store-dir <d>` | 覆盖存储目录（测试用） |
| `xx -DefaultScope Process` | `xx --default-scope process` | 设为默认写到哪：`user`(默认持久) / `process`(仅测试，不持久) |
| （无） | `xx --lang zh\|en` | 本次界面语言 |
| （无） | `xx --version` / `xx --help` | 版本 / 帮助 |

CLI 解析用 `commander`（npm 标准，自生成 help）。找不到 `<name>` 时：红字「找不到配置：X」+ 列出现有名字，退出码 1。

---

## 7. 菜单结构（三级，逐项复刻现版交互）

参考 `xx.ps1` 的 `Main-Menu` / `Action-Menu` / `Edit-Form` 及各 `Pick-*`。
**实现（M4 已落地，非 Ink）**：用自绘 ANSI 列表 `ui/select.ts`（raw keypress）渲染各级菜单；选中记忆/toast 由
`ui/menus.ts` 的循环 + 局部变量管理（不用 React/组件状态）。文本输入走 `ui/text.ts`（raw `readValue` ASCII / cooked `readText` 中文）。

**一级 · 主菜单**（`MainMenu`）
- 列出所有配置：`名称(对齐16)  (默认)(对齐8) [状态] — 备注`。
- 状态文案：`官方`→`登录态`；否则 `密钥未填` / `密钥·API_KEY` / `密钥已设`；
  若有 effort 追加 ` · effort=xxx`。
- `Shift+↑↓` 或 `PgUp/PgDn` **就地排序**配置并立即存盘（只在配置区前 N 项内移动）。
- 「＋ 新增配置」（亮黄色）、「语言 / Language」、「退出」。
- **记住选中项**：从二级返回后光标停在刚操作的配置上；新建成功后落到新配置；删除后夹取范围。

**二级 · 动作菜单**（`ActionMenu`，标题含配置名/默认标记/备注/状态）
- `本次启用` → 启动 claude，退出后**回到本菜单**（停在该项）。
- `设为默认` → 执行后**留在本页**，顶部绿色 toast 提示一轮（不回一级）。
- `编辑` → 进表单；保存/放弃都回本菜单停在「编辑」。改了名字/供应商且它是当前默认时，同步 `current`。
- `删除` → 二次确认 `(y/N)`；`官方` 给「建议保留」提示；删后回一级。
- `返回 / q / Esc` → 回一级。
- **记住选中的动作项**。

**三级 · 编辑表单**（`EditForm`，一屏显示所有字段，选序号改单项）
- 字段：供应商 / 备注 / API 地址 / 认证字段 / API 密钥(默认显示 `****`) / opus / sonnet / haiku / effort。
- 🆕 **密钥明文切换（新需求 2026-06-02）**：表单里 API 密钥行默认掩码 `********`，提供一个切换把它显示成
  明文（再切回 `****`）。实现：表单维护 `showSecret` 布尔；菜单加一项「👁 显示/隐藏密钥明文」（或在密钥行上按
  特定键），翻转后**仅重绘该行**——明文时显示真实 token，掩码时显示 `********`（空值仍显示 `(空)`）。
  默认隐藏（防肩窥/录屏泄露）；切换只影响本次表单的**显示**，不改任何数据、不持久化。
  输入态（`Read-Value -Secret`）仍逐字符回显 `*`，与这里的"查看态"是两回事。
- 选「供应商」→ `PickProvider`（从目录选或自定义手填名）；选定后自动填 base(多 url 弹 `PickProviderUrl`)、
  三档模型、auth、effort。
- 选「API 地址」→ `PickBaseUrl`（目录所有 url + 已有配置用过的 url + 手动输入 + 不修改）。
- 选「认证字段」→ `PickAuth`（AUTH_TOKEN / API_KEY）。
- 选「effort」→ `PickEffort`（low/medium/high/xhigh/max/auto/留空）。
- 文本输入语义：回车空=不改、输入 `-` 回车=清空、Esc=取消（密钥用掩码显示）。
- 「保存并返回」：名字空则拒绝；按 auth 把密钥写进 `ANTHROPIC_API_KEY` 或 `ANTHROPIC_AUTH_TOKEN`；
  `resolveUniqueName`（同名被别条占用则追加 ` 2`/` 3`…，排除自身）；`buildProviderEnv`（按 KnownKeys 顺序、丢空值）。
- **记住选中字段**：改完一项回到表单停在原项。

**通用菜单交互**（由 `ui/select.ts` 统一实现）：↑↓ 导航（跳过空分隔行）、数字键直选、Enter 确认、q/Esc 取消、Ctrl+C 退出、
Shift+↑↓·PgUp·PgDn 就地排序、原地重绘不闪烁、**进入即清屏（CLEAR_SCREEN）制造整页感**；
非交互/无 TTY（判 `process.stdin.isTTY`）回退到「打印列表 + `readline` 读序号」。

---

## 8. 项目结构（**as-built**，M0–M4 实际落地）

```
ccx/
  package.json                // name:"@cc-x/cc-x", bin:{xx:"dist/index.js"}, type:module, publishConfig.access:public, files:[dist,presets.json,…]
  tsconfig.json               // target:ES2022, module/moduleResolution:NodeNext, strict, outDir:dist
  src/
    index.ts                  // 入口：commander 解析 → CLI 路径(--list/xx <name>/-s) 或 openMenu(TUI)
    actions.ts                // launchSession（CLI 与菜单共用，破 index↔menus 循环依赖）
    config/
      types.ts                // KNOWN_KEYS / Provider(含 builtin) / Store(含 lang) / Preset 等类型
      store.ts                // providers.json 读写、默认生成、isOfficial / buildProviderEnv / getProviderState
                              //   / resolveUniqueName / reconcileBuiltin / reconcileCurrent / peekStoreLang …
      presets.ts              // BUILTIN_PRESETS 常量 + loadPresets（用户~/.cc-mini > 包内 > 内置）
    env/
      session.ts              // 本次启用：applyManagedEnv + sessionLaunch（spawn inherit；Win 经 cmd.exe 启 .cmd）
      default.ts              // 设为默认：computeManagedVals + setDefault（平台分叉 + process dry-run + 失败不改 current）
      persist-windows.ts      // powershell.exe 经 JSON payload 写 HKCU\Environment + 单次广播
      persist-unix.ts         // shell rc marker 块 buildBlock/writeMarkerBlock + rcTargetFor（zsh/bash/fish/.profile）
    i18n/
      messages.ts             // key→{zh,en} 单目录（非双 JSON，见 §5）
      index.ts                // T()/setLang/getLang/resolveLang/providerDisplayName
    ui/
      select.ts               // 自绘 ↑↓ 列表（raw keypress / 排序 / 原地重绘 / 进入清屏 / 非交互回退）
      text.ts                 // readValue(raw 逐键, ASCII 字段) / readText(cooked readline, 中文字段)
      pickers.ts              // pickProvider / pickProviderUrl / pickBaseUrl / pickAuth / pickEffort
      edit.ts                 // 编辑表单（含密钥明文切换 §7）
      menus.ts                // openMenu(主菜单) + actionMenu(动作菜单)
      format.ts               // stateLabel / noteSuffix（--list 与菜单共用）
    utils/
      display.ts              // displayWidth / padDisplay / truncateDisplay（基于 string-width）
      ansi.ts                 // 颜色 + 光标 + CLEAR_SCREEN（零依赖）
  presets.json                // 供应商目录（随包发布）
  _smoke/                     // gitignored 冒烟脚本（m1–m3、m5fix），开发期验证用
  docs/npm-rewrite-plan.md
```

依赖（运行时仅 3 个，**无 Ink/react/chalk/inquirer**）：
- **`commander`** — CLI 参数解析（自生成 help、`.choices` 严格校验）
- **`string-width`** — CJK 宽度计算
- **`which`** — 跨平台查找 claude 可执行（Win 上找 `claude.cmd`）
- 颜色用自写 `utils/ansi.ts`（零依赖）；TUI 全自绘，不引框架。
- devDeps：`typescript` / `tsx` / `@types/node` / `@types/which`。

---

## 9. 构建 / 测试命令

```powershell
# 开发（直接跑 TS）
npx tsx src/index.ts
npx tsx src/index.ts --list
npx tsx src/index.ts DeepSeek --session --store-dir ./test-store --default-scope process

# 构建
npx tsc

# 本地链接测试（模拟全局安装）
npm link
xx --list

# 发布
npm publish
```

本地验证（不污染真实环境）：用 `--store-dir <临时目录>` + `--default-scope process`。

---

## 10. 里程碑 Checklist（完成就勾，并在末尾记进度）

- [x] **M0 项目骨架**：`package.json`（name=`cc-x`, bin=`xx`, ESM, Node≥18）、`tsconfig.json`（NodeNext+strict）、
      `src/index.ts`（commander 解析 + 分派桩，含 `KNOWN_KEYS`）。`npm run build` 通过、`--list`/`<name> -s`/无参/`--version` 跑通。
      依赖已装：commander / @inquirer/prompts / string-width / which（+ typescript/tsx/@types）。包名 `cc-x` 已确认可用。
- [x] **M1 数据层**（完成，2026-06-02；`_smoke/m1.ts` 21 项断言全过、`tsc` 干净、`--list` 实跑正确）：
  - [x] `src/config/types.ts`：`KNOWN_KEYS` / `ManagedKey` / `Lang` / `Provider`（含 `builtin?`）/ `Store`（含 `lang?`）/ `Preset` 等类型。
  - [x] `src/config/store.ts`：`resolveStorePaths`(`--store-dir`/默认 ~/.cc-mini)、`defaultStore`(官方带 `builtin:'official'`)、
        `loadStore`(容错规整 + 缺文件即生成落盘)、`saveStore`(UTF-8 无 BOM + 2 空格 + 末尾换行)、`isOfficial`(builtin 优先、仅旧数据空 env 名称兜底)、
        `getProviderEnvMap`、`buildProviderEnv`(按 KNOWN_KEYS 序、丢空)、`getProviderState`(返回**语义枚举** KeyState+effort，不含界面文案，留给 i18n)、
        `findProvider`、`resolveUniqueName`、`getLang`/`setLang`。
  - [x] `src/config/presets.ts`：`BUILTIN_PRESETS` 常量(镜像 presets.json) + `loadPresets`(用户 `~/.cc-mini/presets.json` > 包内 presets.json > 内置兜底；坏 json 安静跌落)。
  - [x] `index.ts` 改从数据层 import；`--list` 接真实 store（CJK 对齐、状态文案与现版一致）；`xx <不存在>` 报错并 exit 1。文案仍临时中文，待 M2 接 i18n。
  - [x] 编译 + `_smoke/m1.ts` 冒烟（gitignored）：默认生成、UTF-8 无 BOM 往返、旧文件无 builtin 容错、状态枚举、buildProviderEnv 按序丢空 + 保 `[1m]`、resolveUniqueName、presets 三级加载全过。
- [x] **M2 i18n**（基础设施完成，2026-06-02；`_smoke/m2.ts` 20 项断言全过、`tsc` 干净、`--list` 中英实跑正确）：
  - [x] `src/i18n/messages.ts`（单目录 key→{zh,en}，见 §5 实现偏离）+ `src/i18n/index.ts`：`T(key,...args)`（占位符 `{0}`、缺 key 回退 key 本身）、
        `setLang`/`getLang`、`resolveLang`(--lang > store.lang > 环境 LANG > 默认 zh)、`providerDisplayName`(官方档显示名走 i18n，评审①)。
  - [x] `src/utils/display.ts`：`displayWidth`/`padDisplay` 基于 `string-width`，替换手写码点判断。
  - [x] `index.ts` 现有文案（list/state/error + 默认标签）全部走 `T()`；官方档中英显示名切换、数据主键 `name` 不变。
  - [ ] **留待 M4/M5**：菜单/表单文案（M4 写时即用 `T()`）；commander `--help`/option 描述的 i18n（M5 收尾）；主菜单「语言切换」项 + 写回 `store.lang`（M4）。
- [x] **M3 两模式**（完成，2026-06-02；`_smoke/m3.ts` 全过，含 Windows 真机验证）：
  - [x] `env/session.ts`：`applyManagedEnv`(有值 set/没值 delete，只动 7 个)、`resolveClaude`(which)、`sessionLaunch`(spawn inherit stdio；
        Windows 经 cmd.exe + 引号包裹启动 `.cmd`，绕开 Node 的 EINVAL，评审②)。**已用假 claude.cmd 真机验证退出码透传。**
  - [x] `env/persist-windows.ts`：`powershell.exe`(评审③) 子进程经 JSON payload(env var) 写 HKCU\Environment + 单次 100ms 广播。**已用 throwaway 键真机验证写/删。**
  - [x] `env/persist-unix.ts`：`buildBlock`/`writeMarkerBlock`(幂等替换 marker 块)/`rcTargetFor`(zsh/bash[darwin→.bash_profile/linux→.bashrc]/fish→提示不支持/其余→.profile，用 posix join)。**macOS 实机加载行为待用户在 Mac 验证；写入逻辑已单测。**
  - [x] `env/default.ts`：`computeManagedVals`(键→值/null) + `setDefault`(平台分叉 + `process` 作用域 dry-run 不落盘，评审⑥)。
  - [x] `index.ts`：`runSession`/`runDefault` 替掉桩；缺密钥黄字警告、claude 缺失/退出码处理；全部文案走 `T()`。端到端 `xx <name>` / `-s` / `--default-scope process` 中英实跑正确。
- [x] **M4 TUI**（完成，2026-06-02，用户真机验证全过）：
  - [x] `utils/ansi.ts`（颜色+光标+CLEAR_SCREEN）、`ui/select.ts`（自绘↑↓列表：数字直选/Shift+↑↓·PgUp·PgDn 排序/原地重绘/进入即清屏整页感/非交互回退）。
  - [x] `ui/text.ts`：**弃用 inquirer**——`readValue`(raw 逐键，ASCII 字段，密钥回显*) + `readText`(cooked readline，中文字段兼容输入法)。见决策表。
  - [x] `ui/pickers.ts`（供应商/地址/认证/effort）、`ui/edit.ts`（编辑表单 + **密钥明文切换 §7** + 名/供应商改动同步 current）、`ui/format.ts`、`ui/menus.ts`（主菜单排序/记忆选中/新增/**语言切换写回 store.lang**/退出；动作菜单 toast/删除二次确认）。
  - [x] 用户真机验证：输入(密钥/模型/`[1m]`保留)、中文输入法、整页切换、编辑回写、排序、语言切换、明文切换 全部正常。`tsc` 干净、三个 smoke 仍全过。
  - [x] 顺带：移除未用的 `@inquirer/prompts` 依赖（deps 仅剩 commander/string-width/which）。
- [x] **M5 健壮性收口 + help i18n + 发布前回归**（完成，2026-06-02；参数本就已存在，重点是「收紧」而非「补参数」）：
  - [x] 3 个 P1 修复：①持久化失败/fish 不支持时不更新 `store.current`（default.ts）；②`--default-scope`/`--lang`
        用 commander `.choices` 严格校验，拼错报错退出、不再静默回退危险路径；③编辑使官方档变第三方时清 `builtin`，且旧数据名称兜底仅认
        `name==='官方' && env为空`（store.ts `reconcileBuiltin` / `isOfficial`）；④删除当前默认配置后回退到剩余官方档或第一项（`reconcileCurrent`）。
        `_smoke/m5fix.ts` 全过 + CLI 实测。
  - [x] help i18n：parse 前用 `peekArg(--lang/--store-dir)` + `peekStoreLang`（只读不生成）定语言，commander 的
        description/argument/option/version/help 文案全走 `T()`。实测 `--help` 中英切换正确（commander 内建的 Usage/Options 段标题仍英文，标准做法，可接受）。
  - [x] 发布前回归：CLI 全路径（--version/--help/--list/`<name>` 设默认/未知名/拼错参数）× 中英各走一遍，全部正确；4 个 smoke 无回归。菜单交互此前已用户真机验证。
  - [ ] 可选（未做，follow-up）：编辑表单「1M 上下文」开关（§3.1.1）。
- [x] **M6 分发**：npm publish（作用域包名 `@cc-x/cc-x`，需先建 npm 组织 `cc-x` + publishConfig.access=public）；
      README 更新安装说明（`npm install -g @cc-x/cc-x`）；`npm update -g @cc-x/cc-x` 更新说明。详见 `docs/publish-guide.md`。
      **已于 2026-06-02 首发成功**（`@cc-x/cc-x@0.3.0`，registry 可见，`v0.3.0` tag 已指向发布提交）。
- [x] **M7 文档**（完成，2026-06-02）：
  - [x] `README.md` / `README.en.md`：npm 全平台版为主（`npm i -g @cc-x/cc-x`）；环境要求改 Node≥18；
        CLI 用 `-s/--list/--lang/--help`；菜单加「🌐 语言切换」；「设为默认」改成跨平台（Win 注册表 / Unix rc 块）；卸载/数据位置同步；presets 用户目录覆盖。
  - [x] `CLAUDE.md`（本地未跟踪）：补「两条并行 edition」说明 + npm 版构建/测试命令 + 指向 plan。
  - [x] `docs/publish-guide.md`：M6 发布手把手教程（npm 账号/2FA、检查清单、`npm pack --dry-run`、publish、打 tag、后续发版、坑）。
  - [x] 版本号去 alpha → `0.3.0`。`npm pack --dry-run` 预览干净（24 文件，无密钥/node_modules/src）。
  - [ ] 可选 follow-up：正式测试框架替代 `_smoke/`。

---

## 11. 已知问题 / 风险 / 待定

- **`socket connection closed unexpectedly` 报错与 ccx 无关，且新版不应去"修"它（2026-06-02 已调查定论）**：
  该错是 Claude Code 自身 HTTP 客户端（Node `fetch`）直连模型 API 时连接被对端断开，**在官方 `api.anthropic.com`
  和多个第三方端点上都复现** → 共同点是用户本机到 API 的网络链路（代理/VPN 不稳），不是任何单一端点、更不是切换器。
  ccx 只设 7 个受管环境变量后即退出，**不在请求链路里、也不碰任何代理类变量**，物理上不可能造成或缓解它。
  ⛔ **不要给 ccx 加重试/代理/请求包装层**——那会让它坐进请求链路，违背"纯环境变量、绝不沾请求"的铁律。
  缓解归属在 ccx 之外（稳定代理、Claude Code 自身重试）。下个对话若再遇到此错，按此结论处理，勿当 ccx bug。
- **npm 包名**：`ccx` 已被占用；`cc-x` 撞 npm 相似名规则（归一化=`ccx`）被 E403 拒，最终定为**作用域包 `@cc-x/cc-x`**（命令名仍 `xx`）。见 §1。
- **fish shell**：export 语法不同（`set -gx`），v1 暂不支持设为默认（给提示）。follow-up。
- **macOS 实测**：rc 文件写入与 claude TTY 行为需在 mac 实机验证。npm link 后即可测，比 Go 交叉编译方便得多。
- ~~**Ink 学习曲线**~~（已作废）：M4 最终**既不用 Ink 也不用 inquirer**，全自绘 ANSI 列表（`ui/select.ts`）+ `node:readline`
  cooked 文本输入。原因：inquirer 的 readline 与自绘菜单的 raw 模式抢 stdin。详见决策表 + §7 + §12。
- **非交互 fallback 小限**：`ui/select.ts` 的非交互回退重复 `createInterface` 读管道会丢缓冲（真实 TTY 不受影响）。低优先 polish。
- **Windows 注册表持久化**：当前方案走 PowerShell 子进程（Windows 上必然存在），干净无原生依赖。若未来想摘掉，可选 `node-ffi` 或 `.node` addon。
- **版本号**：npm 版用 `package.json` 的 `version` 字段（npm 标准）。
- **Node.js 版本**：Claude Code 要求 Node ≥18，`ccx` 跟随这个下限。

---

## 12. 进度笔记（每次接手在此追加，倒序）

- 2026-06-03（**主线收口为 npm-only**）：创建 GitHub Release `v0.3.0` 并设为 Latest；`main`
  删除旧 PowerShell 版文件（`xx.ps1` / `install.ps1` / `ccx.psm1` / `ccx.psd1` / `publish-psgallery.ps1`）
  和已放弃的 Go 方案文档（`docs/go-rewrite-plan.md`）。旧版仍可通过历史 tag（如 `v0.2.3`）查阅，不再在主线维护。
- 2026-06-02（**包名改作用域 `@cc-x/cc-x`**）：实测 `npm publish` 时 `cc-x` 被 npm **相似名规则**以
  E403「too similar to existing package ccx」拒绝（连字符去掉后归一化=`ccx`，撞已存在的 `ccx@1.0.0`）。
  当初"`cc-x` 已确认可用"是误判——`npm view cc-x` 报 404 测不出相似名规则。改用**作用域包 `@cc-x/cc-x`**
  （作用域豁免该规则；`becomeless` 组织名已被占用，故作用域用 `@cc-x`，GitHub 仓库仍是 `becomeless/cc-x`；命令名仍 `xx`）。已改 `package.json`（name + `publishConfig.access=public`，
  作用域公开包首发必需）、package-lock、README 中英安装/包名、`docs/publish-guide.md`（新增建 npm 组织步骤 + 反转
  `--access` 说明 + 失效的可用性检查改对）、本 plan 决策/风险。**仓库名 cc-x 不动**（GitHub repo 叫 cc-x 没问题，只是 npm 包名加作用域）。
  **当时下一步**：用户已在 npmjs.com 建组织 `cc-x`（`becomeless` 被占）→ `npm publish`（首发，access 已由 publishConfig 配好）。
- 2026-06-02（**M6 首发成功，里程碑收尾**）：`@cc-x/cc-x@0.3.0` 已 `npm publish` 成功并在 registry 可见
  （24 文件、解包 ~110 kB、3 运行时依赖；README 正常渲染，仓库/作者指向 `becomeless`）。作用域改动提交 `824017d`
  已 push 到 `origin/main`，`v0.3.0` tag 本地 + 远端均已移到 `824017d`（与发布内容一致）。安装路径：`npm i -g @cc-x/cc-x`，命令仍 `xx`。
- 2026-06-02（**store 健壮性收口**）：`loadStore` 对不可读文件、JSON 语法损坏、顶层结构损坏和 provider 条目结构损坏统一抛
  `StoreError(read|parse|format)`；入口输出带路径的双语友好提示并退出 1，绝不静默重建/覆盖用户密钥。新增
  `_smoke/m6-store-robust.ts` 覆盖文件零改动、旧数据兼容和修好 JSON 后恢复。
- 2026-06-02（**GitHub 仓库改名**）：仓库 slug 从 `becomeless/ccx` 改为 `becomeless/cc-x`，与 npm 包名统一；
  同步更新 npm 元数据、README clone 地址、PSGallery 元数据、Go 版计划中的未来 `go.mod` 示例及本地 `origin`。
- 2026-06-02（**M6 发布前复核收口**）：补齐官方档降级边界（旧数据名称兜底收紧为 `name==='官方' && env为空`）；
  删除当前默认配置后回退到剩余官方档/第一项；`package.json bin.xx` 去掉 npm 会自动清理的 `./` 前缀；发布教程修正
  `cc-x --version` 命令名混淆、把 2FA / bypass-2FA granular token 写成发布必备条件；铁律统一精确为「不写 Claude Code 配置文件」。
- 2026-06-02（**M7 文档完成 + 版本定 0.3.0**）：README 中英双版当时改成「npm 全平台版为主 + 旧 PowerShell 入口备选」
  （后续主线已收口为 npm-only）；安装/环境/CLI/菜单语言项/设为默认跨平台/卸载/数据位置/presets 用户覆盖全部同步；
  CLAUDE.md 补双 edition 说明；新增 `docs/publish-guide.md`（M6 发布手把手）。
  版本 `0.3.0-alpha.0`→`0.3.0`，`npm pack --dry-run` 包内容干净（24 文件）。**当时只剩 M6**：用户准备好 npm 账号后照 publish-guide 发布
  （`npm login` + `npm publish` 需用户亲自做，对外不可逆）。
- 2026-06-02（**M5 完成**）：help i18n（parse 前 `peekArg`+`peekStoreLang` 定语言，commander 全文案走 `T()`，`--help` 中英实测正确）
  + 发布前回归（CLI 全路径 ×中英 + 4 smoke 全过）。M0–M5 全部完成。**当时下一步 M6 分发**：npm publish（当时计划无作用域包 `cc-x`，
  后续已改为 `@cc-x/cc-x`）+ README 更新安装命令。M6 前可考虑：真机 `npm link` 端到端验一遍、补正式测试框架替代 `_smoke/`。
- 2026-06-02（**M5 起步：3 个 P1 修复 + 文档收口**，用户 review 指出）：
  ① 修 3 个 P1（见 §10 M5）：持久化失败不更新 current、`--default-scope`/`--lang` 严格校验、官方档变第三方清 builtin。
  ② **文档收口**：把被推翻的旧设计从「正文」里清掉（不再只靠补丁注记）——决策表 presets/i18n 行、§3.2 presets 优先级、
  §5 i18n 文件结构、§7 菜单实现、§8 项目结构与依赖、§10 M5/M6、§11 风险，全部改成 as-built（cc-x / 全自绘非 Ink / messages.ts
  单目录 / deps 仅 commander+string-width+which）。SoT 现与代码一致。**M5 剩余**：help i18n + 中英回归（+ 可选 1M 开关）。
- 2026-06-02（深夜，**M4 TUI 完成**，用户真机验证全过）：编辑表单 + 各 picker + **密钥明文切换** + 新增 + **语言切换** 全落地。
  关键修正：① **弃用 inquirer**——它与自绘菜单的 raw 模式抢 stdin、文本输入收不到字；改回 PS 双机制（raw 逐键 readValue + cooked
  readline readText，后者兼容中文输入法）。② selectMenu 进入时 `CLEAR_SCREEN` 清屏归位，补上「整页切换」的页面感。
  移除未用的 @inquirer/prompts 依赖。**下一步 M5**：`--lang`/`--version`/`--help`/`--store-dir`/`--default-scope` 收尾 + commander
  的 description/option 帮助文案接 i18n（M2 推迟到此）；可选 1M 开关。**M4 遗留小项**（可放 M5/M7）：非交互 fallback 重复 createInterface
  读管道丢缓冲；编辑「官方」档若改供应商，builtin='official' 仍在（边角，正常用不到）。
- 2026-06-02（深夜，**M4 进行中——菜单底座 + 主/动作菜单**）：新增 `utils/ansi.ts`(零依赖颜色+光标控制)、
  `ui/select.ts`(自绘↑↓菜单：数字直选/Shift+↑↓·PgUp·PgDn 排序/原地重绘不闪/Ctrl+C/非交互回退)、`ui/format.ts`(stateLabel/noteSuffix 共用)、
  `actions.ts`(launchSession 抽出，破 index↔menus 循环)、`ui/menus.ts`(主菜单：列表+排序+记忆选中；动作菜单：本次启用/设为默认 toast/删除二次确认)。
  `index.ts` 菜单桩换成 `openMenu`、`parseAsync`。`tsc` 干净；非交互管道实测主菜单/动作菜单渲染与选择正确（交互 TTY 手感待用户在真实终端验）。
  **M4 还差**：编辑表单(`ui/edit.ts`)+各 picker(供应商/地址/认证/effort)+**密钥明文切换**(§7)+新增配置+主菜单「语言切换」写回 store.lang。
  **已知小限**：非交互 fallback 重复 createInterface 读管道会丢缓冲（真实 TTY 不受影响，列为后续 polish）。
- 2026-06-02（深夜，**M3 两种启用模式完成**）：`env/{session,default,persist-windows,persist-unix}.ts` 全落地，`index.ts`
  的 session/default 桩换成真实实现。`_smoke/m3.ts` 全过，**含 Windows 真机验证**：假 `claude.cmd` 经 cmd.exe 启动 + 退出码
  透传（评审②）、`powershell.exe` 注册表写/删 + 广播（评审③，用 throwaway 键不碰真实配置）。端到端 `xx <name> --default-scope
  process` 中英 dry-run 正确。**唯一待真机验证**：macOS rc 文件加载行为（写入逻辑已单测）。**下一步 M4 TUI**：用 `@inquirer/prompts`
  + 自绘列表搭三级菜单（主菜单排序/记忆选中、动作菜单 toast、编辑表单 + picker + 密钥明文切换 §7、语言切换写回 store.lang）；
  文本输入走 cooked 模式兼容输入法（评审④）。⚠️ M4 是交互式 TUI，自动化冒烟难覆盖，需在真实终端里人工验证。
- 2026-06-02（夜，**M2 i18n 基础设施完成**）：`messages.ts`（单目录，偏离原稿双 JSON，理由见 §5）+ `i18n/index.ts`
  （`T`/`setLang`/`resolveLang`/`providerDisplayName`）+ `utils/display.ts`（string-width 对齐）。`index.ts` 现有文案全部
  走 `T()`，官方档显示名中英切换而数据主键 `name` 不变（评审①落到实处）。`_smoke/m2.ts` 20 项全过、`--list --lang en`
  实跑正确（`Default: Official` / `Logged in` / `No key`）。**下一步 M3 两种启用模式**：`env/session.ts`（spawn claude，
  inherit stdio；Windows 注意 `claude.cmd` + which 解析，评审②）、`env/default.ts` + `persist-windows.ts`（`powershell.exe`
  注册表+单次广播，评审③）+ `persist-unix.ts`（rc marker 块）。先把 CLI 路径 `xx <name>` / `-s` 跑通（目前是桩）。
- 2026-06-02（晚，**M1 完成**）：`types.ts` + `store.ts` + `presets.ts` 全部落地，`index.ts` 接通 `--list`。
  `tsc` 干净、`_smoke/m1.ts` 21 项断言全过、构建产物实跑 `--list` 正确。关键实现决策：`isOfficial` 用
  **builtin 优先、`name==='官方' && env为空` 兜底**；`getProviderState` 只返回**语义枚举**
  不返回中文，翻译留给 i18n（贯彻评审①的数据/显示解耦）；presets 三级加载 + 坏 json 安静兜底。
  **下一步 M2 i18n**：建 `i18n/zh.json`+`en.json`+`T()`，把 `index.ts`/数据层里临时中文（如 `runList`/`stateLabel`）替换掉，
  并按评审①把官方档显示名做成 `T('provider.official')`。另：调查清楚 `socket closed` 报错**与 ccx 无关**（官方+第三方都复现 =
  本机网络问题），结论存进 §11，新版不为此加请求层。
- 2026-06-02：决策锁定。① **包名定为 `cc-x`**（`ccx` 已被占；命令名仍 `xx`）。② **UI 改用 `@inquirer/prompts`
  + 自绘 ANSI 列表，放弃 Ink**（过度工程 + 输入法考虑）。③ 完成架构师评审，对照真实 `xx.ps1` 补出 6 点（见 §1.5），
  重点是 i18n 的两个真陷阱（`"官方"` sentinel 与主键冲突、文本输入 cooked 模式兼容输入法）。④ 新增需求：编辑表单**密钥明文切换**
  （见 §7）。⑤ 已卸载/待卸载 winget 装的 Go（npm 路线不再需要）。⑥ M0 骨架搭建中。
- 2026-06-01：推翻 Go 二进制方案，改走 npm（TypeScript）。保留 `docs/go-rewrite-plan.md` 为长期参考。i18n JSON 设计为双版共享。尚未写任何 TS 代码（M0 未开始）。
