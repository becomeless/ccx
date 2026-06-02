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
