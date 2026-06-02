/**
 * 三级菜单（M4，最小可用版）：主菜单 ↔ 动作菜单。
 *
 * 本轮已实现：列表 + 排序（Shift+↑↓/PgUp/PgDn）+ 记忆选中、本次启用、设为默认（绿条 toast）、删除（二次确认）。
 * 「新增 / 编辑」+ 各 picker + 密钥明文切换 + 语言切换 下一步加（现暂提示 coming soon）。
 */
import { createInterface } from 'node:readline';

import { isOfficial, saveStore, type Provider, type Store, type StorePaths } from '../config/store.js';
import { setDefault, type DefaultScope } from '../env/default.js';
import { launchSession } from '../actions.js';
import { providerDisplayName, T } from '../i18n/index.js';
import { padDisplay } from '../utils/display.js';
import { noteSuffix, stateLabel } from './format.js';
import { selectMenu } from './select.js';

async function readLine(prompt: string): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const ans = await new Promise<string>((res) => rl.question(prompt, res));
  rl.close();
  return ans.trim();
}

/** 一级 · 主菜单。 */
export async function openMenu(paths: StorePaths, store: Store, scope: DefaultScope, version: string): Promise<void> {
  let sel = 0;
  for (;;) {
    const n = store.providers.length;
    const buildItems = (): string[] => {
      const labels = store.providers.map((p) => {
        const dft = p.name === store.current ? T('menu.default') : '';
        return `${padDisplay(providerDisplayName(p), 16)}${padDisplay(dft, 8)}[${stateLabel(p)}]${noteSuffix(p)}`;
      });
      return [...labels, '', T('menu.newProfile'), '', T('menu.exit')];
    };
    const onMove = (from: number, to: number): string[] => {
      const ps = store.providers;
      const a = ps[from];
      const b = ps[to];
      if (a && b) {
        ps[from] = b;
        ps[to] = a;
        saveStore(paths, store);
      }
      return buildItems();
    };

    sel = await selectMenu({
      title: T('menu.mainTitle', version),
      items: buildItems(),
      colors: { [n + 1]: 'yellow' },
      start: sel,
      movableCount: n,
      onMove,
      hint: T('menu.mainHint'),
    });

    if (sel < 0 || sel === n + 3) return; // 退出 / Esc / q
    if (sel === n + 1) {
      console.log(`  ${T('menu.comingSoon')}`); // 新增：下一步实现
      continue;
    }
    const target = store.providers[sel];
    if (target) await actionMenu(paths, store, target, scope);
    if (sel >= store.providers.length) sel = Math.max(0, store.providers.length - 1); // 删除后夹取
  }
}

/** 二级 · 动作菜单（循环停留；只有返回/删除已确认才回一级）。 */
async function actionMenu(paths: StorePaths, store: Store, p: Provider, scope: DefaultScope): Promise<void> {
  let sel = 0;
  let flash: string | undefined;
  for (;;) {
    const dft = p.name === store.current ? T('menu.default') : '';
    const title = `${T('action.titlePrefix')}${providerDisplayName(p)}${dft}${noteSuffix(p)}    [${stateLabel(p)}]`;
    const items = [T('action.session'), T('action.setDefault'), T('action.edit'), T('action.delete'), T('action.back')];

    sel = await selectMenu({ title, items, start: sel, ...(flash ? { status: flash } : {}), hint: T('action.hint') });
    flash = undefined;

    if (sel === 0) {
      launchSession(p); // 启动 claude，退出后回到本菜单
    } else if (sel === 1) {
      flash = applyDefault(paths, store, p, scope); // 留在本页，绿条提示
    } else if (sel === 2) {
      console.log(`  ${T('menu.comingSoon')}`); // 编辑：下一步实现
    } else if (sel === 3) {
      if (isOfficial(p)) console.log(`  ${T('action.deleteOfficialWarn')}`);
      const ans = await readLine(`  ${T('action.deleteConfirm', providerDisplayName(p))}`);
      if (ans === 'y' || ans === 'Y') {
        store.providers = store.providers.filter((x) => x !== p);
        saveStore(paths, store);
        return; // 配置已删，回一级
      }
    } else {
      return; // 返回 / q / Esc
    }
  }
}

/** 设为默认并返回一行 toast 文案。 */
function applyDefault(paths: StorePaths, store: Store, p: Provider, scope: DefaultScope): string {
  const name = providerDisplayName(p);
  const r = setDefault(paths, store, p, scope);
  if (r.dryRun) return `${T('default.done', name)}  ${T('default.dryRun')}`;
  if (r.windows && !r.windows.ok) return T('default.failed', r.windows.error ?? '');
  if (r.unix?.unsupported) return T('default.fishUnsupported');
  return T('default.done', name);
}
