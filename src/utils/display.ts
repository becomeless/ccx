/**
 * 终端显示宽度工具：CJK/全角算 2、半角算 1。
 * 用 `string-width`（封装 eastasianwidth）替代现版手写的码点区间判断；切英文后对齐照样成立。
 */
import stringWidth from 'string-width';

export function displayWidth(s: string): number {
  return stringWidth(s);
}

/** 按显示宽度在右侧补空格到 `width`（不足才补，超出原样返回）。 */
export function padDisplay(s: string, width: number): string {
  const w = stringWidth(s);
  return w < width ? s + ' '.repeat(width - w) : s;
}

/**
 * 按显示宽度截断到 `max`（防止超宽行在终端换行打乱原地重绘的行数计算）。
 * ANSI-aware：转义序列（\x1b[…m）不计入宽度且整段保留；着色中途截断时补 \x1b[0m 防颜色泄漏。
 * （`stringWidth` 本身会剥离 ANSI，故首行判断已是可见宽度；逐字符循环需自行跳过转义序列。）
 */
export function truncateDisplay(s: string, max: number): string {
  if (stringWidth(s) <= max) return s;
  const chars = [...s];
  let out = '';
  let w = 0;
  let colored = false;
  for (let i = 0; i < chars.length; i++) {
    if (chars[i] === '\x1b') {
      const end = csiEnd(chars, i);
      for (let k = i; k <= end; k++) out += chars[k];
      colored = true;
      i = end;
      continue;
    }
    const cw = stringWidth(chars[i] ?? '');
    if (w + cw > max) break;
    out += chars[i];
    w += cw;
  }
  if (colored) out += '\x1b[0m';
  return out;
}

/** 从 ESC（chars[i]==='\x1b'）起返回 CSI 序列的最后一个下标（含终止字节 0x40–0x7E）。 */
function csiEnd(chars: string[], i: number): number {
  if (i + 1 >= chars.length || chars[i + 1] !== '[') return i; // 孤立 ESC
  let j = i + 2; // 跳过 ESC 和引导符 '['
  while (j < chars.length) {
    const c = chars[j] ?? '';
    if (c >= '@' && c <= '~') return j; // 终止字节
    j++;
  }
  return chars.length - 1;
}
