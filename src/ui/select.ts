/**
 * 自绘 ↑↓ 选择菜单（对齐现版 Select-Menu）。
 *
 * - ↑↓ 导航（跳过 '' 分隔空行）、数字键直选、Enter 确认、q/Esc 取消、Ctrl+C 退出。
 * - 原地重绘（光标上移 + 清屏到底 + 隐藏光标）→ 不闪烁。
 * - 可选就地排序：传 onMove + movableCount，Shift+↑↓ 或 PgUp/PgDn 在顶部前 N 项内移动选中项。
 * - 非交互/无 TTY 时回退到「打印列表 + 读一行序号」。
 *
 * 注：文本输入（含中文）不在这里——那走 ui/text.ts（raw readValue / cooked readText，后者兼容输入法，评审④）。
 */
import { createInterface, emitKeypressEvents, type Key } from 'node:readline';

import { T } from '../i18n/index.js';
import { CLEAR_DOWN, CLEAR_SCREEN, CR, cursorUp, HIDE_CURSOR, paint, SHOW_CURSOR, type Color } from '../utils/ansi.js';
import { truncateDisplay } from '../utils/display.js';

export interface SelectOptions {
  title?: string;
  /** 菜单项；'' = 不可选的分隔空行（导航跳过）。 */
  items: string[];
  hint?: string;
  /** 顶部绿色 toast（如「已设为默认」），显示一轮。 */
  status?: string;
  /** 初始选中项（记忆选中）。 */
  start?: number;
  /** 按索引上色（如「＋ 新增配置」用黄色）。 */
  colors?: Record<number, Color>;
  /** 顶部可排序区的项数（仅前 N 项可被 Shift+↑↓/PgUp/PgDn 移动）。 */
  movableCount?: number;
  /** 排序回调：交换数据并返回重建后的菜单项标签数组。 */
  onMove?: (from: number, to: number) => string[];
}

/** 返回选中索引；取消（q/Esc/非法）返回 -1。 */
export async function selectMenu(opts: SelectOptions): Promise<number> {
  const stdin = process.stdin;
  const stdout = process.stdout;
  let items = opts.items.slice();

  if (!stdin.isTTY || !stdout.isTTY) return fallbackSelect(opts, items);

  const nextSel = (i: number, d: number): number => {
    const n = items.length;
    do {
      i = (i + d + n) % n;
    } while (items[i] === '');
    return i;
  };
  let idx = opts.start ?? 0;
  if (idx < 0 || idx >= items.length || items[idx] === '') idx = nextSel(Math.max(0, Math.min(idx, items.length - 1)), 1);

  emitKeypressEvents(stdin);
  const wasRaw = stdin.isRaw ?? false;
  stdin.setRawMode(true);
  stdin.resume();
  stdout.write(CLEAR_SCREEN + HIDE_CURSOR); // 清屏归位，制造「整页」感（每进一级菜单都是新页）

  let prevLines = 0;
  const render = (): void => {
    const cols = stdout.columns ?? 80;
    const lines: string[] = [''];
    if (opts.title) {
      lines.push(`  ${paint(opts.title, 'cyan')}`, '');
    }
    if (opts.status) {
      lines.push(`  ${paint(opts.status, 'green')}`, '');
    }
    for (let i = 0; i < items.length; i++) {
      const it = items[i] ?? '';
      if (it === '') {
        lines.push('');
        continue;
      }
      if (i === idx) lines.push(paint(`   ▶ ${it}`, 'green'));
      else lines.push(paint(`     ${it}`, opts.colors?.[i] ?? 'none'));
    }
    lines.push('');
    if (opts.hint) lines.push(`  ${paint(opts.hint, 'dim')}`);

    const block = lines.map((l) => truncateDisplay(l, cols - 1)).join('\n');
    const prefix = prevLines > 0 ? cursorUp(prevLines - 1) + CR + CLEAR_DOWN : '';
    stdout.write(prefix + block);
    prevLines = lines.length;
  };

  return new Promise<number>((resolve) => {
    const cleanup = (result: number): void => {
      stdin.off('keypress', onKey);
      stdout.write(`${SHOW_CURSOR}\n`);
      if (!wasRaw) stdin.setRawMode(false);
      stdin.pause();
      resolve(result);
    };
    const onKey = (str: string | undefined, key: Key): void => {
      if (key?.ctrl && key.name === 'c') {
        cleanup(-1);
        process.exit(130);
      }
      // 就地排序（仅可排序区内）
      if (opts.onMove && opts.movableCount) {
        const up = key?.name === 'pageup' || (Boolean(key?.shift) && key?.name === 'up');
        const down = key?.name === 'pagedown' || (Boolean(key?.shift) && key?.name === 'down');
        if (up && idx > 0 && idx < opts.movableCount) {
          items = opts.onMove(idx, idx - 1);
          idx -= 1;
          render();
          return;
        }
        if (down && idx < opts.movableCount - 1) {
          items = opts.onMove(idx, idx + 1);
          idx += 1;
          render();
          return;
        }
      }
      switch (key?.name) {
        case 'up':
          idx = nextSel(idx, -1);
          render();
          return;
        case 'down':
          idx = nextSel(idx, 1);
          render();
          return;
        case 'return':
        case 'enter':
          cleanup(idx);
          return;
        case 'escape':
          cleanup(-1);
          return;
        default:
          break;
      }
      const ch = str ?? '';
      if (/^[0-9]$/.test(ch)) {
        const n = Number.parseInt(ch, 10);
        if (n >= 1 && n <= items.length && items[n - 1] !== '') cleanup(n - 1);
        return;
      }
      if (ch === 'q') cleanup(-1);
    };
    stdin.on('keypress', onKey);
    render();
  });
}

/** 非交互回退：打印列表 + 读一行序号。 */
async function fallbackSelect(opts: SelectOptions, items: string[]): Promise<number> {
  const stdout = process.stdout;
  stdout.write('\n');
  if (opts.title) stdout.write(`  ${opts.title}\n\n`);
  items.forEach((it, i) => {
    if (it !== '') stdout.write(`   ${i + 1}. ${it}\n`);
  });
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const ans = await new Promise<string>((res) => rl.question(`  ${T('menu.prompt')}`, res));
  rl.close();
  const t = ans.trim();
  if (t === 'q') return -1;
  if (/^\d+$/.test(t)) {
    const n = Number.parseInt(t, 10);
    if (n >= 1 && n <= items.length && items[n - 1] !== '') return n - 1;
  }
  return -1;
}
