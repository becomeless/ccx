/**
 * 极简 ANSI 颜色 + 光标控制（不引 chalk，零依赖）。
 * 非 TTY 或设了 NO_COLOR 时自动退化为无色，方便管道/重定向。
 */
const enabled = Boolean(process.stdout.isTTY) && !process.env.NO_COLOR;

const wrap = (open: number, close: number) => (s: string): string =>
  enabled ? `\x1b[${open}m${s}\x1b[${close}m` : s;

export const green = wrap(32, 39);
export const yellow = wrap(33, 39);
export const cyan = wrap(36, 39);
export const red = wrap(31, 39);
export const dim = wrap(2, 22);
export const bold = wrap(1, 22);

export type Color = 'green' | 'yellow' | 'cyan' | 'red' | 'dim' | 'bold' | 'none';

export function paint(s: string, color: Color): string {
  switch (color) {
    case 'green':
      return green(s);
    case 'yellow':
      return yellow(s);
    case 'cyan':
      return cyan(s);
    case 'red':
      return red(s);
    case 'dim':
      return dim(s);
    case 'bold':
      return bold(s);
    default:
      return s;
  }
}

// —— 光标 / 屏幕控制 ——
export const HIDE_CURSOR = '\x1b[?25l';
export const SHOW_CURSOR = '\x1b[?25h';

/** 光标上移 n 行（n<=0 时为空串）。 */
export const cursorUp = (n: number): string => (n > 0 ? `\x1b[${n}A` : '');

/** 从光标处清到屏幕末尾。 */
export const CLEAR_DOWN = '\x1b[0J';

/** 回到行首。 */
export const CR = '\r';

/** 清屏 + 清回滚 + 光标归位（等价于 PowerShell 的 Clear-Host，制造「整页」感）。 */
export const CLEAR_SCREEN = '\x1b[2J\x1b[3J\x1b[H';
