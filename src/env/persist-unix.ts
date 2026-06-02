/**
 * macOS / Linux 持久化：在 shell 启动文件里维护一个 marker 块（幂等，可重复重写）。
 *
 *   # >>> xx >>>
 *   export ANTHROPIC_BASE_URL='https://...'
 *   ...只导出当前配置用到的受管键...
 *   # <<< xx <<<
 *
 * 每次「设为默认」整体重写该块 —— 自动清除上个默认里多余的 export。语义与 Windows 一致：
 * 只影响新开终端、不动运行中会话（rc 文件仅在新交互 shell 启动时加载）。
 * fish 语法不同（set -gx），v1 不支持，由调用方据 `kind==='fish'` 给提示（评审/plan §4.2）。
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname } from 'node:path';
import { join as posixJoin } from 'node:path/posix';

import type { EnvVals } from './persist-windows.js';

const BEGIN = '# >>> xx >>>';
const END = '# <<< xx <<<';

export type ShellKind = 'zsh' | 'bash' | 'fish' | 'sh';

export interface RcTarget {
  file: string;
  kind: ShellKind;
}

/** 单引号包裹值，按 shell 规则转义内部单引号（'\'' 收尾再起）。 */
function shQuote(v: string): string {
  return `'${v.split("'").join("'\\''")}'`;
}

/** 生成 marker 块文本（只含非空键，按传入顺序）。 */
export function buildBlock(vals: EnvVals): string {
  const lines = [BEGIN];
  for (const [k, v] of Object.entries(vals)) {
    if (v !== null && v !== '') lines.push(`export ${k}=${shQuote(v)}`);
  }
  lines.push(END);
  return lines.join('\n');
}

const BLOCK_RE = /# >>> xx >>>[\s\S]*?# <<< xx <<</;

/** 把 marker 块写进/替换进指定 rc 文件（纯 fs，可测）。返回写入的文件路径。 */
export function writeMarkerBlock(file: string, vals: EnvVals): string {
  const block = buildBlock(vals);
  let text = existsSync(file) ? readFileSync(file, 'utf-8') : '';
  if (BLOCK_RE.test(text)) {
    text = text.replace(BLOCK_RE, block);
  } else {
    const sep = text === '' || text.endsWith('\n') ? '' : '\n';
    text = `${text}${sep}${text === '' ? '' : '\n'}${block}\n`;
  }
  const dir = dirname(file);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  writeFileSync(file, text, 'utf-8');
  return file;
}

/** 据 $SHELL basename + 平台选 rc 文件。 */
export function rcTargetFor(shellPath: string | undefined, platform: NodeJS.Platform, home: string): RcTarget {
  // 这些是 Unix-destined 路径，用 posix join 保证宿主无关（生产仅在 Unix 上运行）。
  const base = (shellPath ?? '').split('/').pop() ?? '';
  if (base === 'zsh') return { file: posixJoin(home, '.zshrc'), kind: 'zsh' };
  if (base === 'fish') return { file: posixJoin(home, '.config', 'fish', 'config.fish'), kind: 'fish' };
  if (base === 'bash') {
    // macOS 登录 shell 读 .bash_profile；Linux 交互非登录读 .bashrc。
    return { file: posixJoin(home, platform === 'darwin' ? '.bash_profile' : '.bashrc'), kind: 'bash' };
  }
  return { file: posixJoin(home, '.profile'), kind: 'sh' };
}

export interface UnixPersistResult {
  kind: ShellKind;
  /** fish：v1 未写入，调用方据此提示。 */
  unsupported?: boolean;
  /** 实际写入的 rc 文件（unsupported 时为目标路径但未写）。 */
  file: string;
}

/** 设为默认的 Unix 实现：选 rc 文件并重写 marker 块（fish 跳过）。 */
export function persistUnix(vals: EnvVals): UnixPersistResult {
  const target = rcTargetFor(process.env.SHELL, process.platform, homedir());
  if (target.kind === 'fish') return { kind: 'fish', unsupported: true, file: target.file };
  writeMarkerBlock(target.file, vals);
  return { kind: target.kind, file: target.file };
}
