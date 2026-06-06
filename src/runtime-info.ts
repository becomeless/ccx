/**
 * Read-only facts about the current terminal process.
 */
import { getProviderEnvMap, type Store } from './config/store.js';
import { providerDisplayName, T } from './i18n/index.js';

/** Key-safe description of the API currently visible to this terminal process. */
export function currentTerminalLine(store: Store): string {
  return T('terminal.current', currentTerminalTarget(store));
}

function currentTerminalTarget(store: Store): string {
  const base = (process.env.ANTHROPIC_BASE_URL ?? '').trim();
  if (!base) return T('terminal.official');

  const host = hostOf(base);
  const match = store.providers.find((p) => sameBase(base, getProviderEnvMap(p).ANTHROPIC_BASE_URL ?? ''));
  if (match) return T('terminal.matched', host, providerDisplayName(match));
  return T('terminal.unmatched', host);
}

function sameBase(a: string, b: string): boolean {
  return a.trim().replace(/\/+$/, '') === b.trim().replace(/\/+$/, '');
}

/** 从 API 地址提取 host（解析失败则原样返回），供菜单行尾显示复用。 */
export function hostOf(raw: string): string {
  const r = raw.trim();
  try {
    const u = new URL(r);
    return u.host || r;
  } catch {
    return r;
  }
}
