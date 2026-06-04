# ccx

> 简体中文 | [English](README.en.md)

**Claude Code API 切换器**（终端命令 `xx`）。一个命令，在 Claude Code 官方账号与各家第三方
Anthropic 兼容 API（DeepSeek、智谱 GLM、小米 MiMo…）之间来回切。

它和别的切换工具最大的不同——**绝不写任何 Claude Code 配置文件**，切换纯靠环境变量。所以：

- 🛡️ **配置零风险**：不碰 `~/.claude/settings.json`，更不打开存放 MCP 的 `~/.claude.json`，
  从设计上**不可能**弄丢你的 MCP / 插件 / hooks。
- 🔀 **多终端并行**：每个终端可以各用各的 API，互不干扰（进程级隔离）。
- ⚡ **一个命令**：`xx` 选一下，要么仅当前终端临时用，要么设为以后默认。

```text
  cc-x v0.4.4 · Claude Code API 切换器     （默认 = 新终端裸敲 claude 用的）

   ▶ 官方            （默认）[登录态]
     DeepSeek                [密钥已设] — 公司
     智谱GLM                 [密钥未填]
     小米MiMo                [密钥未填]

     新增配置
     切换到 English
     更新检查：关闭
     退出

  ↑↓ 选择 · Enter 进入 · Shift+↑↓（或 PgUp/PgDn）排序 · q 退出
```

> **两个版本**：推荐 **Go 原生版**——GitHub Release 提供轻量 `xx` / `xx.exe`，无需 Node.js，
> 覆盖 Windows x64、macOS Intel / Apple Silicon、Linux x64 / arm64。偏好 npm 的用户可装
> `@cc-x/cc-x`（命令仍是 `xx`）。两版功能一致。

---

## 和 cc-switch 怎么选

cc-switch 是优秀的**全能型 GUI**；ccx 走相反的**极简路线**，两者定位不同：

| | ccx（命令 `xx`） | cc-switch |
|---|---|---|
| 形态 | 终端命令（轻量） | 桌面 GUI（全能） |
| 职责 | 只切 API，一件事做到位 | API + MCP + 多 CLI + 提示词… |
| 改不改配置文件 | **完全不碰**（纯环境变量） | 以自有数据库为准，重写配置文件 |
| 会不会弄丢 MCP / 插件 | **设计上不可能** | 有用户反馈被覆盖丢失 |
| 多终端并行不同 API | **原生支持**（进程级隔离） | 全局切换，易相互影响 |

- **更适合用 ccx**：命令行党、爱敲一下就切；常同时开多个终端各跑不同 API；被“切换把配置 / MCP
  弄坏”坑过想要零风险；只想要“切 API”这一件事。
- **更适合用 cc-switch**：想要图形界面、要在一个工具里统管 MCP 和多个 AI CLI、喜欢一站式。

## 安装

> 需要先装好 **Claude Code**（`claude` 在 PATH 中）——「本次启用」会直接调用它。安装后请**新开一个终端**。

**Windows 原生版（推荐）**

```powershell
irm https://github.com/becomeless/cc-x/releases/latest/download/install.ps1 | iex
```

装到 `%LOCALAPPDATA%\Programs\ccx`，并**自动写入用户 PATH（无需手动配置）**。装完**新开一个终端**就能用
`xx`——已开着的终端读不到新 PATH，这是 Windows 的固有限制，不是要你手动设置。

**macOS / Linux 原生版（推荐）**

```bash
curl -fsSL https://github.com/becomeless/cc-x/releases/latest/download/install.sh | sh
```

装到 `~/.local/bin`（可用 `CCX_INSTALL_DIR` 改目录），并校验 `checksums.txt`。该目录是 XDG 标准 bin 目录、
多数系统默认已在 PATH；仅当它不在 PATH 时，安装器会打印一行提示让你加入（Unix 版刻意不自动改 shell 配置）。

**npm 全平台版**（需 Node.js ≥ 18）

```bash
npm install -g @cc-x/cc-x
```

新开终端运行 `xx --version` 验证安装。

## 快速上手（60 秒）

1. 新开终端运行 `xx`。首次会在 `~/.cc-mini/providers.json` 生成 4 个默认配置
   （官方 + DeepSeek + 智谱GLM + 小米MiMo），**密钥为空**。
2. ↑↓ 选中要用的那家 → Enter → 「编辑」→ 选「API 密钥」填入你的 key（在本机操作）。
3. 配好后二选一：
   - **设为默认**：以后**新开**终端裸敲 `claude` 就用它。
   - **本次启用**：立刻在当前终端启动 Claude（临时、可多终端并行）。

## 两种启用方式（核心概念）

这是理解 ccx 的关键。Claude 用哪个 API 本质由**环境变量**决定，ccx 提供两种作用范围：

| | 本次启用 | 设为默认 |
|---|---|---|
| 机制 | 只给**当前终端这一个进程**设环境变量并启动 `claude` | 把该 API 写成**用户环境变量** |
| 作用范围 | 仅当前终端，**阅后即焚**（关掉就没了） | 之后**新开**的终端裸敲 `claude` 默认用它 |
| 对运行中会话 | **零影响** | **零影响**（环境变量在进程启动时定型） |
| 典型场景 | 多终端并行，各用各 API | 设定最常用的“主力 API” |

**并行示例**：同时开 4 个终端分别 `xx 官方 -s`、`xx DeepSeek -s`、`xx 智谱GLM -s`、`xx 小米MiMo -s`，
得到 4 个同时运行、各用各 API、互不干扰的 Claude。

**为什么不用全局配置文件来切？** 因为 `settings.json` 全局共享，改它会波及**正在运行**的其它会话
（典型表现：另一终端突然报 `... cannot be parsed as a URL`）。环境变量天然进程隔离，避开了这个坑。

## 命令行用法

```bash
xx                       # 打开交互菜单
xx DeepSeek              # 「设为默认」到名为 DeepSeek 的配置
xx DeepSeek -s           # 「本次启用」DeepSeek 并立即启动 Claude（--session 同义）
xx -l                    # 列出所有配置及状态（--list 同义）
xx --lang en             # 本次界面用英文（zh / en）
xx --help                # 全部参数
```

`xx <名称>` 默认是「设为默认」；加 `-s` / `--session` 改为「本次启用」。

## 菜单与编辑

运行 `xx` 进入主菜单：`↑↓` 移动、`Enter` 选择、`q` / `Esc` 退出。选中某个配置时按
**`Shift+↑↓`（或 `PgUp`/`PgDn`）可上下移动排序**，即时保存。

- **选中配置 → Enter** 进入动作菜单：**本次启用** / **设为默认** / **编辑** / **删除**（二次确认，建议保留「官方」）/ **返回**。
- **新增配置** — 新建空配置并进入编辑表单。
- **切换到 English / 中文** — 界面语言即时切换，记忆在 `~/.cc-mini/providers.json` 的 `lang`。
- **更新检查：关闭 / 提醒** — 见[检查新版本](#检查新版本)。
- **退出**。

```text
  配置：DeepSeek — 公司    [密钥已设]

   ▶ 本次启用    — 仅当前终端，立即启动 Claude（并行多终端推荐）
     设为默认    — 新终端裸敲 claude 默认用它（不影响运行中会话）
     编辑
     删除
     返回

  ↑↓ 选择 · Enter 确认 · q 返回
```

**编辑表单**：`↑↓` 选字段、`Enter` 改，最下方可「保存并返回」/「放弃修改」。进入某项后**回车 = 不改**、
输入 `-` = 清空、`Esc` = 取消该项。第一项**「供应商」**最关键：选一个供应商（来自预设目录）后会
**自动填入** API 地址、三档模型映射、认证字段（多地址的供应商会先让你选一个）；「备注」随你写。

```text
  编辑配置 （↑↓ 选要改的项，Enter 进入；↓到底可选保存/放弃）

   ▶ 供应商        : DeepSeek
     备注          : 公司
     API 地址      : https://api.deepseek.com/anthropic
     认证字段      : AUTH_TOKEN
     API 密钥      : ********
     opus  → 模型  : deepseek-v4-pro
     sonnet→ 模型  : deepseek-v4-pro
     haiku → 模型  : deepseek-v4-flash
     effort 思考档 : max

     显示密钥明文（当前隐藏）

     保存并返回
     放弃修改
```

## 配置详解

### 字段

| 字段 | 对应环境变量 | 说明 |
|---|---|---|
| 供应商 | — | 从预设目录选；选后自动带出地址/模型/认证字段。也是配置唯一标识，同名自动追加「 2/3…」 |
| 备注 | — | 自己写，用于区分同供应商的多份配置 |
| API 地址 | `ANTHROPIC_BASE_URL` | 第三方接入点；官方留空＝走登录态 |
| 认证字段 | — | 密钥放进 `AUTH_TOKEN` 还是 `API_KEY`（见下） |
| API 密钥 | `ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_API_KEY` | 对应认证字段的值 |
| opus → 模型 | `ANTHROPIC_DEFAULT_OPUS_MODEL` | `opus` 档映射到的模型 |
| sonnet → 模型 | `ANTHROPIC_DEFAULT_SONNET_MODEL` | `sonnet` 档映射到的模型 |
| haiku → 模型 | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `haiku` 档映射到的模型；**后台任务也用它** |
| effort 思考档 | `CLAUDE_CODE_EFFORT_LEVEL` | 思考深度，见下 |

> ccx **刻意不设** `ANTHROPIC_MODEL`、也不碰 `settings.json` 的 `model`。你在会话里用
> `/model opus\|sonnet\|haiku` 现场选档，映射表负责把它翻译成对应供应商的模型。

### 模型映射与 effort

**为什么第三方必须配模型映射？** 第三方端点只认自己的模型名（如 `deepseek-v4-pro`），而 Claude Code
默认会叫 `claude-*`，不映射就报错。后台任务走 `haiku` 档，所以 `haiku → 模型` **也必须填**
（否则表现为“主对话能用但时不时报错”）。

**effort（思考深度）**：`low < medium < high < xhigh < max`，越高越聪明但越慢越费 token；`auto` = 模型
默认；留空 = 不设。注意 **effort 是 Claude 模型特性，第三方是否生效取决于各家实现**。

各家参考配置（默认已预置）：

| 配置 | BASE_URL | OPUS / SONNET | HAIKU（含后台） | effort |
|---|---|---|---|---|
| 官方 | （留空＝登录态） | — | — | 留空 / `auto` |
| DeepSeek | `https://api.deepseek.com/anthropic` | `deepseek-v4-pro` | `deepseek-v4-flash` | `max`（官方推荐） |
| 智谱GLM | `https://open.bigmodel.cn/api/anthropic` | `GLM-4.7` | `glm-4.5-air` | 留空 |
| 小米MiMo | `https://api.xiaomimimo.com/anthropic`（按量付费）<br>`https://token-plan-cn.xiaomimimo.com/anthropic`（TokenPlan） | `mimo-v2.5-pro` | `mimo-v2.5-pro` | 留空 |

> 模型名会随各家更新而变，请以各供应商官方接入文档为准。

### 认证字段：AUTH_TOKEN vs API_KEY

| 选项 | 实际请求头 | 谁用 |
|---|---|---|
| `ANTHROPIC_AUTH_TOKEN`（默认） | `Authorization: Bearer <key>` | 绝大多数第三方中转 |
| `ANTHROPIC_API_KEY` | `x-api-key: <key>` | 官方 API，及少数只认这种头的中转 |

放错会 401。编辑时可在「认证字段」切换；切换配置时 ccx 会自动清掉另一个，避免残留冲突。

## 多账号与维护预设

**多账号**：同一家有多个 key（个人 / 公司），直接建多份配置——选同一供应商建第二份时名称自动变
`DeepSeek 2`，再用**备注**写明区别，列表显示成「供应商 — 备注」，一眼可辨。

**维护供应商预设**：`presets.json`（随工具发布）是供应商目录，新增配置时选「供应商」就来自这里。
加一个供应商即多一个预设，无需改代码：

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

- `urls` 可有**多个**（如 API 与 TokenPlan 不同地址），选该供应商时先挑一个。
- `models` 是三档推荐映射，选供应商时自动填入，之后仍可手改。`auth` / `effort` 可选，一并带出。
- 也可在 `~/.cc-mini/presets.json` 放一份自定义目录覆盖随工具发布的版本（优先级最高）。

## 检查新版本

主菜单的「**更新检查**」开关默认**关闭**。切到「提醒」后，ccx 会在有新版本时于菜单顶部显示一行
黄字提示，并给出升级命令（不会自动下载安装，你决定何时升）。

- 不走 GitHub API，每天最多查一次，结果缓存在 `~/.cc-mini/update-check.json`；离线或失败都静默。
- 检查在后台进行、不拖慢启动——新版本通常在**下次打开**时才提示。
- 升级就是重新跑一次安装命令（原生版用[安装](#安装)里的一行命令，npm 版 `npm i -g @cc-x/cc-x@latest`）。

## 首次使用：跳过登录 / 引导

用第三方 API（token 鉴权）时，Claude Code **首次启动仍可能弹登录 / 引导**——因为它没记录“已完成引导”。
一次性修复：在 `~/.claude.json`（Windows 为 `C:\Users\你的用户名\.claude.json`）的最外层 `{ }` 里
**只加一个键**（其它内容原样保留）：

```json
{
  "hasCompletedOnboarding": true
}
```

> ⚠️ 这个文件还存着你的 MCP 等配置，**务必只“加键”、不要整体覆盖**。ccx 刻意不替你改它——它正是
> 最不该被工具乱动的地方。

## 数据与文件位置

- **配置（含明文密钥，勿外传）**：`~/.cc-mini/providers.json`（含界面语言 `lang`、更新检查 `update`）。
- **供应商目录**：随工具发布的 `presets.json`，或 `~/.cc-mini/presets.json`（自定义覆盖）。
- **更新检查缓存**：`~/.cc-mini/update-check.json`。
- **「设为默认」写的是用户环境变量**（不是 Claude 配置文件）：
  - **Windows** → 注册表 `HKCU\Environment` + 广播一次变更；
  - **macOS / Linux** → shell 启动文件里的 `# >>> xx >>>` … `# <<< xx <<<` 标记块（幂等重写，按 `$SHELL` 选文件）。
  - 二者语义一致：**只影响新开终端**；切到「官方」会清除全部受管变量。
- **不修改任何 Claude 配置文件。**

ccx 只动这 7 个“受管”环境变量，其它一律不碰，切换时还会清掉目标没用到的那些：
`ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN`、`ANTHROPIC_API_KEY`、`ANTHROPIC_DEFAULT_OPUS_MODEL`、
`ANTHROPIC_DEFAULT_SONNET_MODEL`、`ANTHROPIC_DEFAULT_HAIKU_MODEL`、`CLAUDE_CODE_EFFORT_LEVEL`。

> 💡 需要改 `settings.json` 时，直接用 Claude Code 官方的 `/update-config` 用自然语言说需求（如“允许运行
> npm 命令”），比让外部工具乱改更可靠。

## 常见问题（FAQ）

**在一个终端切换，会影响另一个正在运行的终端吗？** 不会。「本次启用」是进程级；「设为默认」只对**新开**
的进程生效，运行中的会话启动时已定型。

**“设为默认”了，但当前终端敲 `claude` 还是旧的？** 正常——当前终端是旧环境，请**新开终端**。

**出现 `... cannot be parsed as a URL`？** 某配置的 API 地址填成了无效值，进「编辑」改正或删除即可。

**第三方设了 effort 没反应？** effort 是 Claude 模型特性，第三方未必支持。DeepSeek 推荐 `max`，其余留空即可。

**密钥安全吗？** 明文存于本机用户目录、受账户权限保护。注意别把 `providers.json` 提交到仓库。

## 卸载

1. **先清环境变量**：在 `xx` 里执行「设为默认 → 官方」一次，清除全部受管变量。
2. **卸载本体**：
   - Windows 原生版：
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = irm https://github.com/becomeless/cc-x/releases/latest/download/install.ps1; & ([scriptblock]::Create($s)) -Uninstall"
     ```
   - macOS / Linux 原生版：
     ```bash
     curl -fsSL https://github.com/becomeless/cc-x/releases/latest/download/install.sh | sh -s -- --uninstall
     ```
   - npm 版：`npm uninstall -g @cc-x/cc-x`。
   - macOS / Linux 若用过「设为默认」，顺手删掉 shell 启动文件里的 `# >>> xx >>>` 标记块。
3. 删除数据目录 `~/.cc-mini/`。

## 设计原则与初心

ccx 源于我用 cc-switch 时反复遇到的不顺——不是批评，cc-switch 很强大，我只是想走一条更轻的路。
所以 ccx 只信奉一条：**越简单越好。** 只做“切 API”一件事；能不碰的就不碰（尤其**绝不写 Claude Code
配置文件**）；每加一个功能前先问一句能不能不加。

欢迎 Issue / PR——但**让它更简单的改动，比让它更强大的改动更受欢迎**；任何会写 Claude Code 配置文件
的改动都不会被接受。

## 许可

[MIT](LICENSE)
