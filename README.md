# ccx

> 简体中文 | [English](README.en.md)

**Claude Code API 切换器**（终端命令：`xx`）。在 Claude Code 官方账号与各家第三方
Anthropic 兼容 API（DeepSeek、智谱 GLM、小米 MiMo 等）之间快速切换。

它最大的不同：**不写任何 Claude Code 配置文件**，切换只靠环境变量——所以从设计上**不可能弄丢你的
MCP / 插件 / hooks**；并且支持**多个终端同时各用各的 API、互不干扰**。

> **Windows 原生版**：GitHub Release 提供轻量 `xx.exe`，不需要 Node.js。**macOS / Linux**
> 以及偏好 npm 的用户，继续用 `npm install -g @cc-x/cc-x`（命令仍是 `xx`）。

---

## 目录

- [它解决什么问题](#它解决什么问题)
- [和 cc-switch 怎么选](#和-cc-switch-怎么选)
- [安全说明](#安全说明)
- [环境要求](#环境要求)
- [安装](#安装)
- [快速上手](#快速上手)
- [两种启用方式（核心概念）](#两种启用方式核心概念)
- [菜单操作详解](#菜单操作详解)
- [命令行用法](#命令行用法)
- [配置字段说明](#配置字段说明)
- [模型映射与 effort](#模型映射与-effort)
- [认证字段：AUTH_TOKEN vs API_KEY](#认证字段auth_token-vs-api_key)
- [多账号怎么管](#多账号怎么管)
- [维护供应商预设](#维护供应商预设)
- [首次使用：跳过登录 / 引导](#首次使用跳过登录--引导)
- [数据与文件位置](#数据与文件位置)
- [常见问题（FAQ）](#常见问题faq)
- [卸载](#卸载)
- [设计原则与初心](#设计原则与初心)
- [许可](#许可)

---

## 它解决什么问题

Claude Code 支持通过环境变量接入不同的 API 后端。但手动切换很麻烦：

- 每次都要去改 `settings.json` 或敲一长串 `export`；
- 第三方 API 还需要配套设置**模型映射**（它们只认自己的模型名）；
- 开多个终端并行干活时，想让每个终端用不同的 API 更是没有顺手的办法。

ccx 把这些收进一个命令 `xx`：选一下，要么**仅当前终端临时启用**，要么**设为以后默认**。

## 和 cc-switch 怎么选

cc-switch 是优秀的**全能型 GUI**——想要图形界面、想统一管理 MCP、还要同时切
Codex / Gemini 等多个 CLI，它更合适。ccx 走相反的**极简路线**，两者定位不同：

| | ccx（命令 `xx`） | cc-switch |
|---|---|---|
| 形态 | 终端命令（轻量） | 桌面 GUI（全能） |
| 职责 | 只切 API，一件事做到位 | API + MCP + 多 CLI + 提示词… |
| 改不改配置文件 | **完全不碰**（纯环境变量） | 以自有数据库为准，重写配置文件 |
| 会不会弄丢 MCP / 插件 | **设计上不可能** | 有用户反馈被覆盖丢失 |
| 多终端并行不同 API | **原生支持**（进程级隔离） | 全局切换，易相互影响 |

**这些情况下，更推荐用 ccx：**
- 你是命令行党，喜欢敲一下就切；
- 经常**同时开多个终端、各跑不同 API** 并行工作；
- 被“切换把配置 / MCP 弄坏”坑过，想要**零风险**；
- 只想要“切 API”这一件事，不想要一堆用不上的功能。

**这些情况下，更推荐用 cc-switch：** 想要图形界面、需要在一个工具里统管 MCP 和多个 AI CLI、喜欢一站式。

## 安全说明

- **不写任何 Claude Code 配置文件**：不碰 `~/.claude/settings.json`，更不会打开 `~/.claude.json`
  （你的 MCP 配置就在这个文件里）。MCP / 插件 / hooks / 权限**物理上不可能**被它影响。
- 只通过环境变量工作，且只动这 7 个“受管”变量，其它一律不碰：
  `ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_API_KEY`、
  `ANTHROPIC_DEFAULT_OPUS_MODEL`、`ANTHROPIC_DEFAULT_SONNET_MODEL`、
  `ANTHROPIC_DEFAULT_HAIKU_MODEL`、`CLAUDE_CODE_EFFORT_LEVEL`。
- 切换时自动清除目标配置没用到的受管变量，避免上一个的残留（含两种认证字段互斥）。

> 💡 **关于 `settings.json` 等 Claude Code 配置文件**：不建议用第三方工具去管理它（ccx 也刻意
> 不碰）。需要修改时，直接用 Claude Code 官方的 `/update-config`，用自然语言说出你的需求（例如
> “允许运行 npm 命令”“换成深色主题”），Claude Code 会自己安全地维护这个文件——比让外部工具乱改更可靠。

## 环境要求

- **Windows 原生版**：Windows 10/11 x64；不需要 Node.js。
- **npm 全平台版**：Node.js ≥ 18（包名 `@cc-x/cc-x`）。
- **已安装 Claude Code（`claude` 命令在 PATH 中）**：「本次启用」会直接调用 `claude`。

> Go 原生版当前先发 **Windows x64**；macOS / Linux 原生资产在后续 M8 处理。npm 版仍覆盖
> Windows / macOS / Linux。

## 安装

**Windows 原生版（推荐）**

```powershell
irm https://github.com/becomeless/cc-x/releases/latest/download/install.ps1 | iex
```

安装器会下载最新 GitHub Release 里的 `ccx_*_windows_amd64.zip`，安装到
`%LOCALAPPDATA%\Programs\ccx`，并把该目录加入用户 PATH。安装后新开终端，运行：

```powershell
xx --version
```

**npm 全平台版**

```bash
npm install -g @cc-x/cc-x
```

装好后在任意终端敲 `xx` 即可。升级：`npm update -g @cc-x/cc-x`；卸载：`npm uninstall -g @cc-x/cc-x`。
（npm 包名是 `@cc-x/cc-x`，终端命令是 `xx`。）

**从源码（开发 / 自定义）**

```bash
git clone https://github.com/becomeless/cc-x
cd cc-x
```

Go 原生 Windows 构建（注入版本号并生成 Release zip）：

```powershell
.\scripts\build-windows-release.ps1 -Version 0.4.1
.\dist\release\ccx_0.4.1_windows_amd64\xx.exe --version
```

npm 版开发：

```bash
npm install
npm run build
npm link    # 之后 xx 可用
```

**安装后请新开一个终端。**

## 快速上手

1. 新开终端，运行 `xx`。首次运行会在 `~/.cc-mini/providers.json` 生成 4 个默认配置
   （官方 + DeepSeek + 智谱GLM + 小米MiMo），**密钥为空**。
2. 用 ↑↓ 选中要配置的配置 → Enter → 选「编辑」→ 按序号填入你的 **API 密钥**（在本机操作）。
3. 配好后：
   - 想让以后新终端**默认**用它 → 选「设为默认」，然后**新开终端**敲 `claude`。
   - 想在当前终端**临时/并行**用它 → 选「本次启用」，它会立即启动 Claude。

## 两种启用方式（核心概念）

这是理解 ccx 的关键。Claude 用哪个 API，本质由**环境变量**决定，ccx 提供两种作用范围：

| | 本次启用 | 设为默认 |
|---|---|---|
| 机制 | 只给**当前终端这一个进程**设环境变量并启动 `claude` | 把该 API 写成**用户环境变量** |
| 作用范围 | 仅当前终端，**阅后即焚**（关掉终端就没了） | 之后**新开**的终端裸敲 `claude` 默认用它 |
| 对其它 / 运行中会话 | **零影响** | **零影响**（环境变量在进程启动时定型，运行中不会变） |
| 典型场景 | 多终端并行，各用各 API 互不干扰 | 设定你最常用的“主力 API” |

**并行多终端示例**：你可以同时开 4 个终端，分别 `xx 官方 -s`、`xx DeepSeek -s`、
`xx 智谱GLM -s`、`xx 小米MiMo -s`，得到 4 个同时运行、各用各 API、互不干扰的 Claude。

**为什么不用全局配置文件来切？** 因为 `settings.json` 是全局共享的，改它会波及**正在运行**
的其它会话（典型表现：另一个终端突然报 `... cannot be parsed as a URL` 之类）。ccx 用环境
变量避开了这个坑：进程级隔离 + 用户级默认，互不打架。

## 菜单操作详解

运行 `xx` 进入主菜单（`↑↓` 移动，`Enter` 选择，`q` / `Esc` 退出；也支持按数字快捷选择）。
在主菜单选中某个配置时，按 **`Shift+↑↓`（或 `PgUp`/`PgDn`）可直接把它上/下移动来排序**，改完即时保存：

- **选中一个配置 → Enter**，进入动作菜单：
  - **本次启用** — 仅当前终端设环境变量并立刻启动 Claude。退出 Claude 后回到命令行。
  - **设为默认** — 写用户环境变量；**需新开终端**裸敲 `claude` 才生效，不影响运行中的会话。
  - **编辑** — 进入表单（见下）。
  - **删除** — 删除该配置（会二次确认；建议保留「官方」）。
  - **返回**。
- **＋ 新增配置** — 新建一个空配置并进入编辑表单。
- **🌐 语言 / Language** — 中英文界面即时切换（选择会记住，写回 `~/.cc-mini/providers.json` 的 `lang`）。
- **退出**。

**编辑表单**：`↑↓` 选要改的字段，`Enter` 进入修改；继续往下可选「保存并返回」/「放弃修改」。
进入某项后**直接回车 = 不修改**、输入 `-` = 清空、`Esc` = 取消该项不改。
其中第一项是**「供应商」**：选一个供应商（来自预设目录）后，会**自动填入** API 地址、三档模型映射、
认证字段（多 API 地址的供应商，如小米 MiMo 的按量付费 API 与 TokenPlan，会让你先选一个）；「备注」随你写。
「API 地址」也可单独打开列表（预设 + 已有地址 + 手动输入）覆盖。

> 「供应商」是选单，进入后 `Esc` 即可单键取消；「备注」用普通输入（回车=不改、`-`=清空，兼容中文输入法）。

## 命令行用法

```bash
xx                       # 打开交互菜单
xx DeepSeek              # 直接「设为默认」到名为 DeepSeek 的配置
xx DeepSeek -s           # 「本次启用」DeepSeek 并立即启动 Claude（--session 同义）
xx -l                    # 列出所有配置及状态（--list 同义）
xx --lang en             # 本次界面用英文（zh / en）
xx --help                # 查看全部参数
```

- `xx <名称>`：默认是「设为默认」（写用户环境变量）。
- 加 `-s` / `--session`：改为「本次启用」（进程级 + 启动 Claude）。

## 配置字段说明

| 字段 | 对应环境变量 | 说明 |
|---|---|---|
| 供应商 | — | 从预设目录里选；选后自动带出 API 地址/模型/认证字段。也是配置的唯一标识，同名时自动追加「 2/3…」（见“多账号”） |
| 备注 | — | 自己写，用于在列表里区分同供应商的多份配置 |
| API 地址 | `ANTHROPIC_BASE_URL` | 第三方的接入点；官方留空＝走登录态 |
| 认证字段 | — | 选择密钥放进 `AUTH_TOKEN` 还是 `API_KEY`（见下） |
| API 密钥 | `ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_API_KEY` | 对应认证字段的值 |
| opus → 模型 | `ANTHROPIC_DEFAULT_OPUS_MODEL` | `opus` 档映射到的具体模型 |
| sonnet → 模型 | `ANTHROPIC_DEFAULT_SONNET_MODEL` | `sonnet` 档映射到的具体模型 |
| haiku → 模型 | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `haiku` 档映射到的模型；**Claude Code 的后台任务也用它** |
| effort 思考档 | `CLAUDE_CODE_EFFORT_LEVEL` | 思考深度，见下 |

> ccx **刻意不设** `ANTHROPIC_MODEL`、也不碰 `settings.json` 的 `model` 字段。
> 你在会话里用 `/model opus|sonnet|haiku` 现场选档，映射表负责把它翻译成对应供应商的模型。

## 模型映射与 effort

**为什么第三方必须配模型映射？** 第三方端点只认它自己的模型名（如 `deepseek-v4-pro`），
而 Claude Code 默认会去叫 `claude-*`；不映射就会报错。而且后台任务走 `haiku` 档，
所以 `haiku → 模型` 也必须填（否则后台请求失败，表现为“主对话能用但时不时报错”）。

**effort（思考深度）**：`low < medium < high < xhigh < max`，越高越聪明但越慢越费 token；
`auto` = 回到模型默认；留空 = 不设。注意 **effort 是 Claude 模型的特性，第三方是否真生效取决于各家实现**。

各家参考配置（默认配置已按此预置）：

| 配置 | BASE_URL | OPUS / SONNET | HAIKU（含后台） | effort |
|---|---|---|---|---|
| 官方 | （留空＝登录态） | — | — | 留空 / `auto` |
| DeepSeek | `https://api.deepseek.com/anthropic` | `deepseek-v4-pro` | `deepseek-v4-flash` | `max`（官方文档推荐） |
| 智谱GLM | `https://open.bigmodel.cn/api/anthropic` | `GLM-4.7` | `glm-4.5-air` | 留空 |
| 小米MiMo | `https://api.xiaomimimo.com/anthropic`（按量付费）<br>`https://token-plan-cn.xiaomimimo.com/anthropic`（TokenPlan） | `mimo-v2.5-pro` | `mimo-v2.5-pro` | 留空 |

> 模型名会随各家更新而变化，请以各供应商官方接入文档为准。

## 认证字段：AUTH_TOKEN vs API_KEY

密钥放进哪个变量，决定了发出的请求头不同：

| 选项 | 实际请求头 | 谁用 |
|---|---|---|
| `ANTHROPIC_AUTH_TOKEN`（默认） | `Authorization: Bearer <key>` | 绝大多数第三方中转 |
| `ANTHROPIC_API_KEY` | `x-api-key: <key>` | 官方 API，以及少数只认这种头的中转 |

有些端点只认其中一种，放错会 401。编辑时可在「认证字段」里切换；切换配置时 ccx 会自动
清掉另一个，避免残留导致认证冲突。

## 多账号怎么管

同一家有多个账号（如个人 / 公司各一个 DeepSeek Key）：**直接建多份配置即可**——
选同一个供应商建第二份时，名称会自动变成 `DeepSeek 2`，再用**备注**写明「个人 / 公司」加以区分，
列表里显示成「供应商 — 备注」，一眼可辨。

## 维护供应商预设

`presets.json`（随工具发布）是**供应商目录**，新增/编辑配置时选「供应商」就来自这里。
加一个供应商即多一个预设，无需改代码。每个供应商的字段：

```json
[
  {
    "name": "DeepSeek",
    "auth": "AUTH_TOKEN",
    "effort": "max",
    "urls": [ { "label": "Anthropic 兼容", "url": "https://api.deepseek.com/anthropic" } ],
    "models": { "opus": "deepseek-v4-pro", "sonnet": "deepseek-v4-pro", "haiku": "deepseek-v4-flash" }
  }
]
```

- `urls` 可以有**多个**（例如某家把 API 与 TokenPlan 放在不同地址）——选该供应商时会让你先挑一个。
- `models` 是该供应商三档（opus/sonnet/haiku）的**推荐映射**，选供应商时自动填入，之后仍可手动改。
- `auth`（`AUTH_TOKEN`/`API_KEY`）、`effort` 为可选，选供应商时一并带出。

此外，编辑「API 地址」时弹出的列表还会**自动收录**你 `providers.json` 里已用过的地址（标 `(已有:配置名)`）。

## 首次使用：跳过登录 / 引导

用第三方 API（token 鉴权）时，Claude Code **首次启动仍可能弹出登录 / 引导界面**——
因为它没记录“已完成引导”。一次性修复：在 `~/.claude.json` 里加一个键
`"hasCompletedOnboarding": true`。

配置文件位置：

- Windows：`用户目录\.claude.json`（即 `C:\Users\你的用户名\.claude.json`）
- macOS / Linux：`~/.claude.json`

改法（**重要：这个文件还存着你的 MCP 等配置，务必只“加键”，不要整体覆盖**）：

- 文件**已存在**：在最外层 `{ }` 里加上这一行（注意逗号），其它内容原样保留：
  ```json
  {
    "hasCompletedOnboarding": true
  }
  ```
- 文件**不存在**：新建一个，内容就是上面这段。

> ccx 刻意**不替你改这个文件**——它正是 MCP 所在、最不该被工具乱动的地方。
> 这一步只需做一次（个别版本可能还需其它设置，以官方为准）。

## 数据与文件位置

- 配置（含密钥，**明文**存于本机，勿外传）：`~/.cc-mini/providers.json`（含界面语言 `lang`）。
- 供应商目录：随工具发布的 `presets.json`；也可在 `~/.cc-mini/presets.json` 放一份**自定义目录**覆盖它（优先级最高）。
- 「设为默认」写的是**用户环境变量**（不是 Claude 配置文件）：
  - **Windows** → 注册表 `HKCU\Environment` + 广播一次变更；
  - **macOS / Linux** → shell 启动文件（按 `$SHELL` 选 `~/.zshrc` / `~/.bash_profile` / `~/.bashrc` / `~/.profile`）里的
    `# >>> xx >>>` … `# <<< xx <<<` 标记块（幂等重写）。
  - 两者语义一致：**只影响新开终端**；切到「官方」会清除全部受管变量。
- **不修改任何 Claude 配置文件。**

## 常见问题（FAQ）

**Q：我在一个终端切换，会不会影响另一个正在运行的终端？**
不会。「本次启用」是进程级的；「设为默认」写的是用户环境变量，只对**新开**的进程生效，
运行中的会话在启动时就已定型，不受影响。

**Q：我“设为默认”了，但当前终端敲 `claude` 还是旧的？**
正常。当前终端是旧环境，请**新开一个终端**再敲 `claude`。

**Q：之前出现过 `... cannot be parsed as a URL` 的报错？**
那是某个配置的 API 地址填成了无效值（如随手输入的测试串）。进「编辑」改正或删除该配置即可。

**Q：第三方设了 effort 没反应？**
effort 是 Claude 模型特性，第三方端点未必支持。DeepSeek 官方推荐 `max`，其余各家未必生效，
留空即可。

**Q：密钥安全吗？**
保存在本机用户目录、受账户权限保护。注意别把 `providers.json` 提交到仓库。

## 卸载

- **先清环境变量**：在 `xx` 里执行「设为默认 → 官方」一次清除全部受管变量（比手删干净）。
- 卸载命令本体：
  - Windows 原生版：删除 `%LOCALAPPDATA%\Programs\ccx`，并从用户 PATH 移除这个目录；或运行：
    ```powershell
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = irm https://github.com/becomeless/cc-x/releases/latest/download/install.ps1; & ([scriptblock]::Create($s)) -Uninstall"
    ```
  - npm 版：`npm uninstall -g @cc-x/cc-x`；
  - macOS / Linux 若用过「设为默认」→ 顺手删掉 shell 启动文件里的 `# >>> xx >>>` 标记块。
- 删除数据目录 `~/.cc-mini/`。

## 设计原则与初心

ccx 的诞生，源于我自己用 cc-switch 时反复遇到的不顺。这不是批评——cc-switch 很强大、很全能，
我只是想走另一条更轻的路。

所以 ccx 只信奉一条原则：**越简单越好。**

- 只做“切 API”这一件事，把它做到位；
- 能不碰的就不碰——尤其**绝不写 Claude Code 配置文件**（`~/.claude/settings.json`、`~/.claude.json`）；
- 每加一个功能前，先问一句：能不能不加。

欢迎 Issue / PR。但请记得：**让它更简单的改动，比让它更强大的改动更受欢迎**；
任何会写 Claude Code 配置文件的改动都不会被接受。

## 许可

[MIT](LICENSE)
