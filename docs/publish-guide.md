# M6 发布教程：把 `cc-x` 发到 npm（手把手）

> 这是给**你（becomeless）**的发布操作手册。npm 发布是**对外、且同一版本号不可重复**的动作，所以一步步来。
> 全程在仓库根目录 `D:\work\AI\ccx` 操作。包名 `cc-x`，命令 `xx`，当前版本 `0.3.0`（见 `package.json`）。

---

## 0. 一次性准备：npm 账号

1. 去 https://www.npmjs.com/signup 注册一个账号（如果还没有）。记住用户名 / 邮箱 / 密码。
2. **准备发布凭据（必需）**：npm 发布要求满足以下二选一：
   - 账号开启 **2FA**（npmjs.com → 头像 → Account → Two-Factor Authentication）。交互执行 `npm publish` 时输入一次性验证码（OTP）。
   - 使用开启 **Bypass 2FA** 的 granular access token（适合非交互发布）。
   首次手动发布推荐直接开启账号 2FA。
3. 在终端登录（这一步**只有你能做**，我无法替你登录）：
   ```bash
   npm login
   ```
   按 npm 提示在浏览器或终端完成登录；启用 2FA 后，发布时还会要求 OTP。
   验证是否登录成功：
   ```bash
   npm whoami        # 打印出你的用户名 = 已登录
   ```

> 如果你用 `! npm login` 的形式在本会话里跑，登录态就会留在这个会话里，我后续能帮你验证。

---

## 1. 发布前检查清单（逐项确认）

在仓库根目录依次跑：

```bash
# 1) 包名没被别人抢注（cc-x 之前确认是空的，发布前再确认一次）
npm view cc-x version        # 报 404 = 还没人发布过，可用；如果打印出版本号 = 已被占，停下找我

# 2) 版本号对不对（应为 0.3.0，且 npm 上不存在这个版本）
node -e "console.log(require('./package.json').version)"

# 3) 干净构建 + 类型检查（确保 dist 是最新的）
npm run typecheck
npm run build

# 4) 预览“真正会被发布的文件”（关键！确认有 dist/、presets.json、README，没有密钥/node_modules/src）
npm pack --dry-run
```

`npm pack --dry-run` 应该列出约 24 个文件：`LICENSE`、`README*.md`、`dist/**/*.js`、`package.json`、`presets.json`。
**如果看到 `.cc-mini`、`providers.json`、`node_modules`、`.env` 之类——立刻停下找我**（说明 `files` 字段或 `.gitignore` 出问题了）。

> 我们用的是 `package.json` 里的 `files: ["dist","presets.json","README.md","README.en.md"]` 白名单，
> 所以 `src/`、`_smoke/`、`docs/`、`node_modules/` 默认都不会被发布。`LICENSE` 由 npm 自动带上。

可选但推荐——**本机端到端验一遍编译产物**（不污染你的全局）：
```bash
npm link                       # 把本地包链接成全局
node dist/index.js --version   # 应打印 0.3.0（包名是 cc-x，但注册的命令只有 xx）
node dist/index.js --help      # 看帮助
npm unlink -g cc-x             # 验完解除链接
```

---

## 2. 正式发布

```bash
npm publish
```

- `cc-x` 是**无作用域的公开包**，首次发布**不需要** `--access public`（那是 `@scope/xxx` 作用域包才要的）。
- 账号 2FA 路径会提示输 OTP；非交互发布则使用开启 Bypass 2FA 的 granular token。
- `package.json` 里配了 `prepublishOnly: "npm run build"`，所以 publish 前会**自动再构建一次**，双保险。

发布成功后验证：
```bash
npm view cc-x                  # 能看到 0.3.0、文件列表等
```
也可以去 https://www.npmjs.com/package/cc-x 看看页面（README 会渲染在那里）。

---

## 3. 发布后

1. **真机装一遍**（最好新开一个干净终端）：
   ```bash
   npm install -g cc-x
   # 在没有 PS xx 函数的环境里：xx --version
   # 在你这台被 PS 函数占用的 Windows 机器上：cmd /c xx --version
   ```
2. **打 git tag 并推送**（对齐版本号，便于追溯）：
   ```bash
   git tag -a v0.3.0 -m "npm 版 cc-x 0.3.0 首发"
   git push origin main --tags
   ```
   > ⚠️ 顺序建议：**先 `npm publish` 成功，再 `git push`**（或同时），避免 README 里写着 `npm i -g cc-x`
   > 但包还没上线、别人装不上的尴尬窗口。
3. README 里的安装说明此时就“真的能用了”。

---

## 4. 以后怎么发新版本（更新流程）

同一个版本号**不能重发**，所以每次发布前必须先升版本号：

```bash
npm version patch      # 0.3.0 → 0.3.1（修 bug）；或 minor=0.4.0（加功能）、major=1.0.0（大改/稳定）
                       # 这条命令会自动改 package.json 的 version 并打一个 git tag
npm publish
git push origin main --tags
```

> 注意：**npm 版的版本号在 `package.json`**；**PowerShell 版的版本号在 `xx.ps1` 的 `$script:Version` 和
> `ccx.psd1` 的 `ModuleVersion`**——两条线各自独立，发哪条就只动哪条。PS 版发 PSGallery 的流程见现有发版习惯。

---

## 5. 几个要知道的“坑 / 规则”

- **版本不可变**：一旦 `cc-x@0.3.0` 发出去，就不能再用 `0.3.0` 这个号发不同内容。发错了只能：72 小时内 `npm unpublish cc-x@0.3.0`
  撤回，或 `npm deprecate cc-x@0.3.0 "说明"` 标记弃用，然后发 `0.3.1`。
- **`xx` 命令在你这台机器上被老 PowerShell 函数挡着**（PS 函数优先级高于外部命令）——这是正常的，过渡期就该如此。
  别人（没装 PS 版的）`npm i -g cc-x` 后敲 `xx` 会直接用到新版。你自己想用新版就用 `cmd /c xx` / `node dist/index.js`，或
  以后想切换时再从 `$PROFILE` 删掉老 `xx` 函数。
- **macOS / Linux 尚未真机大规模验证**：「本次启用」全平台一致没问题；「设为默认」写 rc 文件的逻辑只跑过单测。
  首发后若有 mac/linux 用户，留意反馈。要更稳妥，可以先找一台 mac 实测「设为默认」再大力推。
- **2FA OTP 过期**：publish 时 OTP 有时效，输慢了会失败，重新跑 `npm publish` 再输新码即可。

---

## 6. 我能帮你做 / 不能帮你做

| 我能做 | 你来做（我做不了） |
|---|---|
| 跑检查清单（typecheck/build/`npm pack --dry-run`）、修问题 | `npm login`（你的账号密码 / 2FA） |
| 升版本号、改 README、打 tag 的命令 | 最终 `npm publish` 的点头与 OTP |
| 发布后帮你验证 `npm view` / 装包测试 | 注册 npm 账号、开 2FA 或准备 granular token |

准备好账号后，你可以先 `! npm login` 登录，然后跟我说“开始发布”，我就带着你把检查清单和发布跑一遍。
