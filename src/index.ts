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
  type Provider,
  type ProviderState,
  type Store,
  type StorePaths,
} from './config/store.js';
import { setDefault } from './env/default.js';
import { sessionLaunch } from './env/session.js';
import { providerDisplayName, resolveLang, setLang, T } from './i18n/index.js';
import { padDisplay } from './utils/display.js';

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
  // 语言：--lang > providers.json lang > 环境 > 默认 zh。在产出任何文案前先定好。
  setLang(resolveLang(opts.lang, store.lang));

  if (opts.list) {
    runList(store);
    return;
  }
  if (name) {
    const target = store.providers.find((p) => p.name === name);
    if (!target) {
      console.error(`  ${T('error.notFound', name)}`);
      console.error(`  ${T('error.existing', store.providers.map((p) => p.name).join(', '))}`);
      process.exitCode = 1;
      return;
    }
    if (opts.session) runSession(target);
    else runDefault(paths, store, target, opts.defaultScope);
    return;
  }
  stub('打开交互菜单（TUI）', opts); // M4
}

/** 非官方且未填密钥时给黄字提示（对齐现版）。 */
function warnIfNoKey(p: Provider): void {
  if (getProviderState(p).key === 'noKey') {
    console.error(`  ${T('session.noKey', providerDisplayName(p))}`);
  }
}

/** 本次启用：套环境 + 启动 claude，阻塞至其退出。 */
function runSession(p: Provider): void {
  warnIfNoKey(p);
  console.log('');
  console.log(`  ${T('session.launch', providerDisplayName(p))}`);
  console.log(`  ${T('session.starting')}`);
  console.log('');
  const res = sessionLaunch(p);
  if (res.claudeMissing) {
    console.error(`  ${T('session.noClaude')}`);
    process.exitCode = 1;
    return;
  }
  if (res.spawnError) {
    console.error(`  ${res.spawnError.message}`);
    process.exitCode = 1;
    return;
  }
  if (typeof res.status === 'number' && res.status !== 0) process.exitCode = res.status;
}

/** 设为默认：写用户环境变量（或 dry-run）+ 更新 store.current。 */
function runDefault(paths: StorePaths, store: Store, p: Provider, scope: 'user' | 'process'): void {
  warnIfNoKey(p);
  const name = providerDisplayName(p);
  const r = setDefault(paths, store, p, scope);

  if (r.dryRun) {
    console.log(`  ${T('default.done', name)}`);
    console.log(`  ${T('default.dryRun')}`);
    return;
  }
  if (r.windows && !r.windows.ok) {
    console.error(`  ${T('default.failed', r.windows.error ?? '')}`);
    process.exitCode = 1;
    return;
  }
  if (r.unix?.unsupported) {
    console.error(`  ${T('default.fishUnsupported')}`);
    return;
  }
  console.log(`  ${T('default.done', name)}`);
  if (r.unix) console.log(`  ${T('default.unixWrote', r.unix.file)}`);
}

/** `--list`：列出所有配置及状态。官方档显示名走 i18n（评审①），其余原样。 */
function runList(store: Store): void {
  const cur = store.providers.find((p) => p.name === store.current);
  console.log('');
  console.log(`  ${T('list.default', cur ? providerDisplayName(cur) : store.current)}`);
  for (const p of store.providers) {
    const mark = p.name === store.current ? '▶' : ' ';
    const note = p.note ? `  — ${p.note}` : '';
    console.log(`   ${mark} ${padDisplay(providerDisplayName(p), 18)}[${stateLabel(getProviderState(p))}]${note}`);
  }
  console.log('');
}

/** 语义状态枚举 → 当前语言文案。effort 值两种语言相同，原样附加。 */
function stateLabel(s: ProviderState): string {
  const base =
    s.key === 'official'
      ? T('state.login')
      : s.key === 'noKey'
        ? T('state.noKey')
        : s.key === 'apiKey'
          ? T('state.apiKey')
          : T('state.hasKey');
  return s.effort ? `${base} · effort=${s.effort}` : base;
}

function stub(what: string, opts: GlobalOpts): void {
  const store = opts.storeDir ?? '~/.cc-mini';
  console.log(`[cc-x ${pkg.version}] (桩) 将执行：${what}`);
  console.log(`  store=${store}  lang=${opts.lang ?? '(自动)'}`);
}

main();
