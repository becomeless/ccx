/**
 * 三级菜单：主菜单 ↔ 动作菜单 ↔ 编辑表单（M4）。
 *
 * 主菜单：列表 + 排序（Shift+↑↓/PgUp/PgDn）+ 记忆选中 + 新增 + 语言切换 + 退出。
 * 动作菜单：本次启用 / 设为默认（绿条 toast）/ 编辑 / 删除（二次确认）/ 返回。
 * 编辑表单见 ui/edit.ts（含密钥明文切换）。
 */
import { createInterface } from 'node:readline';

import { launchSession } from '../actions.js';
import { isOfficial, reconcileCurrent, saveStore, type Provider, type Store, type StorePaths } from '../config/store.js';
import type { Preset } from '../config/types.js';
import { setDefault, type DefaultScope } from '../env/default.js';
import { getLang, providerDisplayName, setLang, T } from '../i18n/index.js';
import { banner as updateBanner, maybeRefresh, MODE_NOTIFY, upgradeCommand } from '../update/update.js';
import { padDisplay } from '../utils/display.js';
import { editForm } from './edit.js';
import { noteSuffix, stateLabel } from './format.js';
import { selectMenu } from './select.js';

async function readLine(prompt: string): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const ans = await new Promise<string>((res) => rl.question(prompt, res));
  rl.close();
  return ans.trim();
}

/** 一级 · 主菜单。布局：[profiles…] '' 新增 语言 '' 退出。 */
export async function openMenu(
  paths: StorePaths,
  store: Store,
  scope: DefaultScope,
  version: string,
  catalog: Preset[],
): Promise<void> {
  let sel = 0;
  let refreshed = false;
  for (;;) {
    const n = store.providers.length;
    // 更新检查（仅 notify 模式）：首轮触发一次后台刷新；横幅永远读缓存（瞬时、不阻塞）。
    let notice: string | undefined;
    if (store.update === MODE_NOTIFY) {
      if (!refreshed) {
        maybeRefresh(paths.dir);
        refreshed = true;
      }
      const latest = updateBanner(paths.dir, version);
      if (latest) notice = T('menu.updateAvailable', latest, upgradeCommand());
    }
    const updLabel = store.update === MODE_NOTIFY ? T('menu.updateNotify') : T('menu.updateOff');
    const buildItems = (): string[] => {
      const labels = store.providers.map((p) => {
        const dft = p.name === store.current ? T('menu.default') : '';
        return `${padDisplay(providerDisplayName(p), 16)}${padDisplay(dft, 8)}[${stateLabel(p)}]${noteSuffix(p)}`;
      });
      return [...labels, '', T('menu.newProfile'), T('menu.language'), updLabel, '', T('menu.exit')];
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
      ...(notice ? { notice } : {}),
      items: buildItems(),
      colors: { [n + 1]: 'yellow' },
      start: sel,
      movableCount: n,
      onMove,
      hint: T('menu.mainHint'),
      noNumber: true,
    });

    if (sel < 0 || sel === n + 5) return; // 退出 / Esc / q
    if (sel === n + 1) {
      // 新增配置
      const prov: Provider = { name: '', env: {} };
      if (await editForm(prov, store, catalog)) {
        store.providers.push(prov);
        saveStore(paths, store);
        sel = store.providers.length - 1; // 光标落到新配置
      }
    } else if (sel === n + 2) {
      // 语言切换：即时切并写回 store.lang
      const next = getLang() === 'zh' ? 'en' : 'zh';
      setLang(next);
      store.lang = next;
      saveStore(paths, store);
    } else if (sel === n + 3) {
      // 更新检查开关：关闭 <-> 提醒（关闭=删字段，与 Go 的 omitempty 对齐）
      if (store.update === MODE_NOTIFY) delete store.update;
      else store.update = MODE_NOTIFY;
      saveStore(paths, store);
    } else if (sel < n) {
      const target = store.providers[sel];
      if (target) await actionMenu(paths, store, target, scope, catalog);
      if (sel >= store.providers.length) sel = Math.max(0, store.providers.length - 1); // 删除后夹取
    }
  }
}

/** 二级 · 动作菜单（循环停留；返回/删除已确认才回一级）。 */
async function actionMenu(
  paths: StorePaths,
  store: Store,
  p: Provider,
  scope: DefaultScope,
  catalog: Preset[],
): Promise<void> {
  let sel = 0;
  let flash: string | undefined;
  for (;;) {
    const dft = p.name === store.current ? T('menu.default') : '';
    const title = `${T('action.titlePrefix')}${providerDisplayName(p)}${dft}${noteSuffix(p)}    [${stateLabel(p)}]`;
    const items = [T('action.session'), T('action.setDefault'), T('action.edit'), T('action.delete'), T('action.back')];

    sel = await selectMenu({ title, items, start: sel, ...(flash ? { status: flash } : {}), hint: T('action.hint'), noNumber: true });
    flash = undefined;

    if (sel === 0) {
      launchSession(p);
    } else if (sel === 1) {
      flash = applyDefault(paths, store, p, scope);
    } else if (sel === 2) {
      const old = p.name;
      if (await editForm(p, store, catalog)) {
        if (store.current === old) store.current = p.name; // 改了名/供应商时同步默认指向
        saveStore(paths, store);
      }
    } else if (sel === 3) {
      if (isOfficial(p)) console.log(`  ${T('action.deleteOfficialWarn')}`);
      const ans = await readLine(`  ${T('action.deleteConfirm', providerDisplayName(p))}`);
      if (ans === 'y' || ans === 'Y') {
        store.providers = store.providers.filter((x) => x !== p);
        reconcileCurrent(store);
        saveStore(paths, store);
        return;
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
