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
};
