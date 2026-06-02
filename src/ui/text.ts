/**
 * 文本输入。**不用 inquirer**——它的 readline 会和自绘 selectMenu 的 raw 模式抢 stdin、收不到按键。
 * 改回现版 PS 的两套机制（同一时刻只有一套在跑，互不干扰）：
 *
 *  · readValue：raw 逐键行编辑器（与 selectMenu 同机制，已验证可用），用于 ASCII 字段（密钥/模型/effort）。
 *               密钥回显 `*`。语义对齐 Read-Value：回车空=不改、`-`=清空、Esc=取消、Ctrl+C 退出。
 *  · readText ：cooked 模式 readline（兼容中文输入法，评审④），用于中文字段（备注/自定义名/手动地址）。
 */
import { createInterface, emitKeypressEvents, type Key } from 'node:readline';

import { T } from '../i18n/index.js';

export interface ReadResult {
  changed: boolean;
  value: string;
}

/** raw 逐键读 ASCII 字段：回车空=不改、`-`=清空、其它=替换、Esc/Ctrl+C=取消。 */
export async function readValue(label: string, current: string, secret = false): Promise<ReadResult> {
  const stdin = process.stdin;
  const stdout = process.stdout;
  const cur = current === '' ? T('empty.paren') : secret ? '********' : current;
  stdout.write(`\n  ${label}  [${T('edit.current', cur)}]  ${T('edit.inputHint')}\n  > `);

  if (!stdin.isTTY) {
    const line = await readText(''); // 非交互回退
    if (line === undefined || line === '') return { changed: false, value: current };
    if (line === '-') return { changed: true, value: '' };
    return { changed: true, value: line };
  }

  emitKeypressEvents(stdin);
  const wasRaw = stdin.isRaw ?? false;
  stdin.setRawMode(true);
  stdin.resume();

  let buf = '';
  return new Promise<ReadResult>((resolve) => {
    const cleanup = (): void => {
      stdin.off('keypress', onKey);
      if (!wasRaw) stdin.setRawMode(false);
      stdin.pause();
      stdout.write('\n');
    };
    const onKey = (str: string | undefined, key: Key): void => {
      if (key?.ctrl && key.name === 'c') {
        cleanup();
        resolve({ changed: false, value: current });
        process.exit(130);
      }
      if (key?.name === 'return' || key?.name === 'enter') {
        cleanup();
        if (buf === '') resolve({ changed: false, value: current });
        else if (buf === '-') resolve({ changed: true, value: '' });
        else resolve({ changed: true, value: buf });
        return;
      }
      if (key?.name === 'escape') {
        cleanup();
        resolve({ changed: false, value: current });
        return;
      }
      if (key?.name === 'backspace') {
        if (buf.length > 0) {
          buf = buf.slice(0, -1);
          stdout.write('\b \b');
        }
        return;
      }
      // 普通字符（含粘贴的多字符），过滤控制字符
      if (str && !key?.ctrl && !key?.meta) {
        const printable = [...str].filter((c) => c >= ' ' && c !== '\x7f').join('');
        if (printable) {
          buf += printable;
          stdout.write(secret ? '*'.repeat(printable.length) : printable);
        }
      }
    };
    stdin.on('keypress', onKey);
  });
}

/** cooked 模式读一行（兼容中文输入法）；Ctrl+C/中止返回 undefined。 */
export async function readText(message: string): Promise<string | undefined> {
  const stdin = process.stdin;
  if (stdin.isTTY) stdin.setRawMode(false); // 确保 cooked，输入法才能组词
  stdin.resume();
  const rl = createInterface({ input: stdin, output: process.stdout });
  return new Promise<string | undefined>((resolve) => {
    let done = false;
    rl.on('SIGINT', () => {
      if (done) return;
      done = true;
      rl.close();
      resolve(undefined);
    });
    rl.question(message ? `${message}` : '  > ', (ans) => {
      if (done) return;
      done = true;
      rl.close();
      resolve(ans);
    });
  });
}
