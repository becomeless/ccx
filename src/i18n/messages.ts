/**
 * i18n 消息目录：key → { zh, en }。
 *
 * 设计取舍（偏离 plan §5 原稿的「两个 JSON 文件」）：用单个 TS 目录更简单——tsc 无需额外拷贝 JSON 到 dist、
 * 无 import 断言/运行时文件 IO 的跨 Node 版本坑、中英同处一行不易漏翻。将来若 Go 版要复用，
 * 一行 `JSON.stringify(messages)` 即可导出双语 JSON，投入不浪费。
 *
 * 约定：所有 user-facing 字符串都走 i18n 的 `T()`；逻辑层不得裸写中文（注释除外）。
 * 占位符用 `{0}` `{1}` …，由 `T(key, ...args)` 按序替换。
 */
export interface Msg {
  zh: string;
  en: string;
}

export const messages: Record<string, Msg> = {
  // —— CLI ——
  'cli.desc': {
    zh: 'Claude Code API 切换器：在官方账号与第三方 Anthropic 兼容 API 间切换。',
    en: 'Claude Code API switcher: switch between the official account and third-party Anthropic-compatible APIs.',
  },

  // —— 列表 / 状态 ——
  'list.default': { zh: '默认配置：{0}', en: 'Default: {0}' },
  'state.login': { zh: '登录态', en: 'Logged in' },
  'state.noKey': { zh: '密钥未填', en: 'No key' },
  'state.apiKey': { zh: '密钥·API_KEY', en: 'Key · API_KEY' },
  'state.hasKey': { zh: '密钥已设', en: 'Key set' },

  // —— 供应商显示名（仅官方这种普通名词需要翻译；DeepSeek/GLM/MiMo 是专有名词不翻）——
  'provider.official': { zh: '官方', en: 'Official' },

  // —— 错误 ——
  'error.notFound': { zh: '找不到配置：{0}', en: 'Profile not found: {0}' },
  'error.existing': { zh: '现有：{0}', en: 'Existing: {0}' },

  // —— 本次启用（session）——
  'session.noKey': { zh: '⚠ 配置 [{0}] 还没填密钥。', en: '⚠ Profile [{0}] has no key set.' },
  'session.launch': {
    zh: '▶ 本次启用：{0}（仅当前终端，不影响其它终端）',
    en: '▶ Session: {0} (this terminal only; others unaffected)',
  },
  'session.starting': {
    zh: '正在启动 Claude…（退出 Claude 后回到命令行）',
    en: 'Launching Claude… (returns here after Claude exits)',
  },
  'session.noClaude': { zh: '未找到 claude 命令，请确认它在 PATH 中。', en: 'claude not found on PATH.' },

  // —— 设为默认（default）——
  'default.writing': { zh: '正在写入用户环境变量…', en: 'Writing user environment variables…' },
  'default.done': {
    zh: '✓ 已设为默认：{0}  ·  新开终端裸敲 claude 生效（不影响运行中会话）',
    en: '✓ Default set: {0}  ·  effective in newly opened terminals (running sessions unaffected)',
  },
  'default.dryRun': {
    zh: '（dry-run：--default-scope process，未改系统，仅更新存储）',
    en: '(dry-run: --default-scope process; system untouched, store only)',
  },
  'default.unixWrote': {
    zh: '已写入 {0}（新开终端生效；或 source 它立即生效）',
    en: 'Wrote {0} (effective in new terminals; or source it now)',
  },
  'default.failed': { zh: '设为默认失败：{0}', en: 'Failed to set default: {0}' },
  'default.fishUnsupported': {
    zh: '⚠ 检测到 fish：v1 暂不支持「设为默认」，请手动设置或改用「本次启用」。',
    en: '⚠ fish detected: "set default" is unsupported in v1; set manually or use session launch.',
  },
};
