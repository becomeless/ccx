#!/usr/bin/env node
/**
 * cc-x —— Claude Code API 切换器（命令：xx）
 *
 * 入口：解析 CLI 参数 → 分派到 CLI 路径（--list / xx <name> / -s）或交互菜单（TUI）。
 *
 * 进度：M1 数据层、M2 i18n、M3 两种启用、M4 主/动作菜单已接入。
 *       编辑/新增表单 + 各 picker + 密钥明文切换 + 语言切换为 M4 后续。
 *
 * 铁律：绝不写 Claude Code 配置文件；API 切换只动 7 个受管环境变量。详见 CLAUDE.md / plan §2。
 */
import { createRequire } from 'node:module';
import { Command, Option } from 'commander';

import { launchSession, warnIfNoKey } from './actions.js';
import { loadStore, peekStoreLang, resolveStorePaths, type Provider, type Store, type StorePaths } from './config/store.js';
import { loadPresets } from './config/presets.js';
import { setDefault } from './env/default.js';
import { providerDisplayName, resolveLang, setLang, T } from './i18n/index.js';
import { noteSuffix, stateLabel } from './ui/format.js';
import { openMenu } from './ui/menus.js';
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

/** 从 argv 里轻量预读一个带值参数（`--name v` 或 `--name=v`），用于 parse 前定语言。 */
function peekArg(argv: string[], name: string): string | undefined {
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === name) return argv[i + 1];
    if (a && a.startsWith(`${name}=`)) return a.slice(name.length + 1);
  }
  return undefined;
}

function main(): void {
  // help/version 在 commander parse 时就打印，故须**在建命令前**定好语言：
  // --lang > providers.json 的 lang（只读探测，不生成文件）> 环境 > 默认 zh。
  const argv = process.argv;
  const earlyLang = peekArg(argv, '--lang');
  const lang = earlyLang === 'en' ? 'en' : earlyLang === 'zh' ? 'zh' : undefined;
  const storeLang = peekStoreLang(resolveStorePaths(peekArg(argv, '--store-dir')));
  setLang(resolveLang(lang, storeLang));

  const program = new Command();
  program
    .name('xx')
    .description(T('cli.desc'))
    .helpOption('-h, --help', T('cli.opt.help'))
    .version(pkg.version, '-v, --version', T('cli.opt.version'))
    .argument('[name]', T('cli.arg.name'))
    .option('-s, --session', T('cli.opt.session'))
    .option('-l, --list', T('cli.opt.list'))
    .option('--store-dir <dir>', T('cli.opt.storeDir'))
    .addOption(
      // [P1] 严格校验：拼错（如 proces）直接报错退出，不静默回退到危险的持久化路径。
      new Option('--default-scope <scope>', T('cli.opt.defaultScope')).choices(['user', 'process']).default('user'),
    )
    .addOption(new Option('--lang <lang>', T('cli.opt.lang')).choices(['zh', 'en']))
    .action(async (name: string | undefined, raw: GlobalOpts) => {
      await dispatch(name, normalizeOpts(raw));
    });

  void program.parseAsync();
}

function normalizeOpts(raw: GlobalOpts): GlobalOpts {
  const scope = raw.defaultScope === 'process' ? 'process' : 'user';
  const lang = raw.lang === 'en' ? 'en' : raw.lang === 'zh' ? 'zh' : undefined;
  return { ...raw, defaultScope: scope, lang };
}

/** 按参数把请求分派到对应路径。 */
async function dispatch(name: string | undefined, opts: GlobalOpts): Promise<void> {
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
    if (opts.session) launchSession(target);
    else runDefault(paths, store, target, opts.defaultScope);
    return;
  }
  await openMenu(paths, store, opts.defaultScope, pkg.version, loadPresets(opts.storeDir));
}

/** `--list`：列出所有配置及状态。官方档显示名走 i18n（评审①），其余原样。 */
function runList(store: Store): void {
  const cur = store.providers.find((p) => p.name === store.current);
  console.log('');
  console.log(`  ${T('list.default', cur ? providerDisplayName(cur) : store.current)}`);
  for (const p of store.providers) {
    const mark = p.name === store.current ? '▶' : ' ';
    console.log(`   ${mark} ${padDisplay(providerDisplayName(p), 18)}[${stateLabel(p)}]${noteSuffix(p)}`);
  }
  console.log('');
}

/** 设为默认：写用户环境变量（或 dry-run）+ 更新 store.current。 */
function runDefault(paths: StorePaths, store: Store, p: Provider, scope: DefaultScope): void {
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

main();
