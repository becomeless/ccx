#!/usr/bin/env node
/**
 * cc-x —— Claude Code API 切换器（命令：xx）
 *
 * 本文件是入口：解析 CLI 参数 → 分派到 CLI 路径或交互菜单（TUI）。
 *
 * 进度：M1 数据层已接入 `--list`（真实读 store）。`--session` / 设为默认 / 菜单仍为桩，
 *       分别在 M3 / M4 实现。界面文案目前用临时中文，M2 抽 i18n 时统一替换。
 *
 * 铁律：绝不写任何配置文件，只动 7 个受管环境变量。详见 CLAUDE.md / plan §2。
 */
import { createRequire } from 'node:module';
import { Command } from 'commander';

import {
  getProviderState,
  loadStore,
  resolveStorePaths,
  type ProviderState,
  type Store,
} from './config/store.js';

const require = createRequire(import.meta.url);
const pkg = require('../package.json') as { version: string };

type DefaultScope = 'user' | 'process';
type Lang = 'zh' | 'en';

interface GlobalOpts {
  session?: boolean;
  list?: boolean;
  storeDir?: string;
  defaultScope: DefaultScope;
  lang?: Lang;
}

function main(): void {
  const program = new Command();

  program
    .name('xx')
    .description('Claude Code API 切换器：在官方账号与第三方 Anthropic 兼容 API 间切换。')
    .version(pkg.version, '-v, --version', '显示版本号')
    .argument('[name]', '目标配置名；省略则打开交互菜单')
    .option('-s, --session', '本次启用：仅当前终端设环境变量并启动 claude（阅后即焚）')
    .option('-l, --list', '列出所有配置及状态')
    .option('--store-dir <dir>', '覆盖配置存储目录（测试用，默认 ~/.cc-mini）')
    .option('--default-scope <scope>', '设为默认写到哪：user(持久) / process(不落盘 dry-run，测试用)', 'user')
    .option('--lang <lang>', '本次界面语言：zh / en')
    .action((name: string | undefined, raw: GlobalOpts) => {
      dispatch(name, normalizeOpts(raw));
    });

  program.parse();
}

function normalizeOpts(raw: GlobalOpts): GlobalOpts {
  const scope = raw.defaultScope === 'process' ? 'process' : 'user';
  const lang = raw.lang === 'en' ? 'en' : raw.lang === 'zh' ? 'zh' : undefined;
  return { ...raw, defaultScope: scope, lang };
}

/** 按参数把请求分派到对应路径。 */
function dispatch(name: string | undefined, opts: GlobalOpts): void {
  const paths = resolveStorePaths(opts.storeDir);
  const store = loadStore(paths);

  if (opts.list) {
    runList(store);
    return;
  }
  if (name) {
    const target = store.providers.find((p) => p.name === name);
    if (!target) {
      console.error(`  找不到配置：${name}`);
      console.error(`  现有：${store.providers.map((p) => p.name).join(', ')}`);
      process.exitCode = 1;
      return;
    }
    if (opts.session) stub(`本次启用并启动 claude：${target.name}（--session）`, opts); // M3
    else stub(`设为默认：${target.name}（default-scope=${opts.defaultScope}）`, opts); // M3
    return;
  }
  stub('打开交互菜单（TUI）', opts); // M4
}

/** `--list`：列出所有配置及状态。文案为临时中文，M2 接 i18n 后替换。 */
function runList(store: Store): void {
  console.log('');
  console.log(`  默认配置：${store.current}`);
  for (const p of store.providers) {
    const mark = p.name === store.current ? '▶' : ' ';
    const note = p.note ? `  — ${p.note}` : '';
    console.log(`   ${mark} ${padDisplay(p.name, 18)}[${stateLabel(getProviderState(p))}]${note}`);
  }
  console.log('');
}

/** 语义状态 → 临时中文文案（M2 改为 i18n.T()）。 */
function stateLabel(s: ProviderState): string {
  const base =
    s.key === 'official'
      ? '登录态'
      : s.key === 'noKey'
        ? '密钥未填'
        : s.key === 'apiKey'
          ? '密钥·API_KEY'
          : '密钥已设';
  return s.effort ? `${base} · effort=${s.effort}` : base;
}

/** 按显示宽度右侧补空格（CJK=2，半角=1）。M2 会换成基于 string-width 的工具。 */
function padDisplay(s: string, width: number): string {
  let w = 0;
  for (const ch of s) {
    const c = ch.codePointAt(0) ?? 0;
    w += isWide(c) ? 2 : 1;
  }
  return w < width ? s + ' '.repeat(width - w) : s;
}

function isWide(c: number): boolean {
  return (
    (c >= 0x1100 && c <= 0x115f) ||
    (c >= 0x2e80 && c <= 0xa4cf) ||
    (c >= 0xac00 && c <= 0xd7a3) ||
    (c >= 0xf900 && c <= 0xfaff) ||
    (c >= 0xfe30 && c <= 0xfe4f) ||
    (c >= 0xff00 && c <= 0xff60) ||
    (c >= 0xffe0 && c <= 0xffe6)
  );
}

function stub(what: string, opts: GlobalOpts): void {
  const store = opts.storeDir ?? '~/.cc-mini';
  console.log(`[cc-x ${pkg.version}] (桩) 将执行：${what}`);
  console.log(`  store=${store}  lang=${opts.lang ?? '(自动)'}`);
}

main();
