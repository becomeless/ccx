/**
 * 列表/菜单行的文案格式化（--list 与 TUI 菜单共用，避免重复）。
 */
import { getProviderState, type Provider } from '../config/store.js';
import { T } from '../i18n/index.js';

/** 配置的状态文案（语义枚举 → 当前语言；effort 原样附加）。 */
export function stateLabel(p: Provider): string {
  const s = getProviderState(p);
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

/** 备注后缀（有备注才显示）。 */
export function noteSuffix(p: Provider): string {
  return p.note ? `  — ${p.note}` : '';
}
