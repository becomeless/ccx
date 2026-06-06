package tui

import (
	"fmt"
	"os"
	"strings"

	"github.com/becomeless/cc-x/internal/check"
	"github.com/becomeless/cc-x/internal/config"
	"github.com/becomeless/cc-x/internal/defaults"
	"github.com/becomeless/cc-x/internal/display"
	"github.com/becomeless/cc-x/internal/env"
	"github.com/becomeless/cc-x/internal/i18n"
	"github.com/becomeless/cc-x/internal/launch"
	"github.com/becomeless/cc-x/internal/presets"
	"github.com/becomeless/cc-x/internal/runtimeinfo"
	"github.com/becomeless/cc-x/internal/update"
)

// OpenMenu 一级 · 主菜单。布局：[profiles…] ” 新增 语言 ” 退出。对应 npm 版 openMenu。
func OpenMenu(t *Terminal, paths config.StorePaths, store *config.Store, scope defaults.Scope, version string, catalog []presets.Preset) {
	sel := 0
	refreshed := false
	flash := ""
	warnFlash := ""
	for {
		n := len(store.Providers)
		// 更新检查（仅 notify 模式）：首轮触发一次后台刷新；横幅永远读缓存（瞬时、不阻塞）。
		notices := []string{runtimeinfo.CurrentTerminalLine(store)}
		if needsFirstRunHint(store) {
			notices = append(notices, i18n.T("menu.firstRunHint"))
		}
		if warnFlash != "" {
			notices = append(notices, warnFlash)
		}
		if store.Update == update.ModeNotify {
			if !refreshed {
				update.MaybeRefresh(paths.Dir)
				refreshed = true
			}
			if latest, ok := update.Banner(paths.Dir, version); ok {
				notices = append(notices, i18n.T("menu.updateAvailable", latest, update.UpgradeCommand()))
			}
		}
		updLabel := i18n.T("menu.updateOff")
		if store.Update == update.ModeNotify {
			updLabel = i18n.T("menu.updateNotify")
		}
		buildItems := func() []string {
			labels := make([]string, n)
			for i := range store.Providers {
				p := store.Providers[i]
				dft := ""
				if p.Name == store.Current {
					dft = i18n.T("menu.default")
				}
				labels[i] = display.Pad(i18n.ProviderDisplayName(p), 16) + display.Pad(dft, 8) + "[" + i18n.StateLabel(p) + "]" + i18n.NoteSuffix(p)
			}
			items := append([]string{}, labels...)
			return append(items, "", i18n.T("menu.newProfile"), i18n.T("menu.language"), updLabel, "", i18n.T("menu.exit"))
		}
		onMove := func(from, to int) []string {
			ps := store.Providers
			if from >= 0 && from < len(ps) && to >= 0 && to < len(ps) {
				ps[from], ps[to] = ps[to], ps[from]
				_ = config.Save(paths, store)
			}
			return buildItems()
		}

		defaultName := defaultDisplayName(store)
		shortcut := rune(0)
		sel = SelectMenu(t, SelectOptions{
			Title:        i18n.T("menu.mainTitle", version, defaultName),
			Notice:       strings.Join(notices, "\n"),
			Status:       flash,
			Items:        buildItems(),
			Colors:       map[int]Color{n + 1: ColorYellow},
			Start:        sel,
			MovableCount: n,
			OnMove:       onMove,
			OnKey: func(r rune, idx int) int {
				if idx >= n {
					return -1
				}
				switch r {
				case 'e', 's', 'd':
					shortcut = r
					return idx
				}
				return -1
			},
			Hint:     i18n.T("menu.mainHint"),
			NoNumber: true,
		})
		flash = ""
		warnFlash = ""

		if shortcut != 0 && sel >= 0 && sel < n {
			p := &store.Providers[sel]
			switch shortcut {
			case 'e':
				old := p.Name
				if EditForm(t, p, store, catalog) {
					if store.Current == old {
						store.Current = p.Name
					}
					_ = config.Save(paths, store)
				}
			case 's':
				tuiLaunchSession(*p)
			case 'd':
				warnFlash, flash = applyDefault(paths, store, p, scope)
			}
			continue
		}

		switch {
		case sel < 0 || sel == n+5: // 退出 / Esc / q
			return
		case sel == n+1: // 新增配置
			prov := config.Provider{Env: map[string]string{}}
			if EditForm(t, &prov, store, catalog) {
				store.Providers = append(store.Providers, prov)
				_ = config.Save(paths, store)
				sel = len(store.Providers) - 1
			}
		case sel == n+2: // 语言切换：即时切并写回 store.lang
			next := config.LangEN
			if i18n.GetLang() == config.LangEN {
				next = config.LangZH
			}
			i18n.SetLang(next)
			store.Lang = next
			_ = config.Save(paths, store)
		case sel == n+3: // 更新检查开关：关闭 <-> 提醒
			if store.Update == update.ModeNotify {
				store.Update = update.ModeOff
			} else {
				store.Update = update.ModeNotify
			}
			_ = config.Save(paths, store)
		case sel < n:
			actionMenu(t, paths, store, &store.Providers[sel], scope, catalog)
			if sel >= len(store.Providers) {
				sel = max(0, len(store.Providers)-1) // 删除后夹取
			}
		}
	}
}

// actionMenu 二级 · 动作菜单（循环停留；返回/删除已确认才回一级）。
func actionMenu(t *Terminal, paths config.StorePaths, store *config.Store, p *config.Provider, scope defaults.Scope, catalog []presets.Preset) {
	sel := 0
	flash := ""
	warnFlash := "" // 黄字警告（如缺密钥），走 Notice 与绿色 Status 区分
	for {
		dft := ""
		if p.Name == store.Current {
			dft = i18n.T("menu.default")
		}
		title := i18n.T("action.titlePrefix") + i18n.ProviderDisplayName(*p) + dft + i18n.NoteSuffix(*p) + "    [" + i18n.StateLabel(*p) + "]"
		items := []string{i18n.T("action.session"), i18n.T("action.setDefault"), i18n.T("action.check"), i18n.T("action.edit"), i18n.T("action.delete"), i18n.T("action.back")}

		opts := SelectOptions{Title: title, Items: items, Start: sel, Hint: i18n.T("action.hint"), NoNumber: true}
		if warnFlash != "" {
			opts.Notice = warnFlash
		}
		if flash != "" {
			opts.Status = flash
		}
		sel = SelectMenu(t, opts)
		flash = ""
		warnFlash = ""

		switch sel {
		case 0:
			tuiLaunchSession(*p)
		case 1:
			warnFlash, flash = applyDefault(paths, store, p, scope)
		case 2:
			r := check.Profile(*p)
			if r.OK {
				flash = r.Message
			} else {
				warnFlash = r.Message
			}
		case 3:
			old := p.Name
			if EditForm(t, p, store, catalog) {
				if store.Current == old {
					store.Current = p.Name // 改名/供应商时同步默认指向
				}
				_ = config.Save(paths, store)
			}
		case 4:
			if config.IsOfficial(*p) {
				fmt.Printf("  %s\n", i18n.T("action.deleteOfficialWarn"))
			}
			ans, _ := t.ReadLine("  " + i18n.T("action.deleteConfirm", i18n.ProviderDisplayName(*p)))
			if ans == "y" || ans == "Y" {
				removeProvider(store, p)
				config.ReconcileCurrent(store)
				_ = config.Save(paths, store)
				return
			}
		default:
			return // 返回 / q / Esc
		}
	}
}

func defaultDisplayName(store *config.Store) string {
	if store.Current == "" {
		return "—"
	}
	for _, p := range store.Providers {
		if p.Name == store.Current {
			return i18n.ProviderDisplayName(p)
		}
	}
	return store.Current
}

// applyDefault 设为默认，返回 (warn, toast)：warn 为黄字警告（缺密钥），toast 为绿色结果。
// 分开返回让调用方各自上色，避免警告被染成「成功」绿。对应 npm 版 applyDefault。
func applyDefault(paths config.StorePaths, store *config.Store, p *config.Provider, scope defaults.Scope) (warn, toast string) {
	name := i18n.ProviderDisplayName(*p)
	if config.GetProviderState(*p).Key == config.KeyNone {
		warn = i18n.T("default.noKey", name)
	}
	r := defaults.SetDefault(paths, store, *p, scope)
	switch {
	case r.DryRun:
		return warn, i18n.T("default.done", name) + "  " + i18n.T("default.dryRun")
	case r.WinOK != nil && !*r.WinOK:
		return warn, i18n.T("default.failed", r.WinErr)
	case r.Unix != nil && r.Unix.Unsupported:
		return warn, i18n.T("default.fishUnsupported")
	default:
		return warn, i18n.T("default.done", name)
	}
}

// tuiLaunchSession 菜单内「本次启用」：提示 + banner + 套环境启动 claude，退出后回到动作菜单。
func tuiLaunchSession(p config.Provider) {
	if config.GetProviderState(p).Key == config.KeyNone {
		fmt.Fprintf(os.Stderr, "  %s\n", i18n.T("session.noKey", i18n.ProviderDisplayName(p)))
	}
	fmt.Println("")
	fmt.Printf("  %s\n", i18n.T("session.launch", i18n.ProviderDisplayName(p)))
	fmt.Printf("  %s\n", i18n.T("session.starting"))
	fmt.Println("")
	bin, ok := launch.ResolveClaude()
	if !ok {
		fmt.Fprintf(os.Stderr, "  %s\n", i18n.T("session.noClaude"))
		fmt.Fprintf(os.Stderr, "  %s\n", i18n.T("session.noClaudeHint"))
		return
	}
	env.ApplyManaged(p)
	_, _ = launch.LaunchSession(bin)
}

func needsFirstRunHint(store *config.Store) bool {
	hasThirdParty := false
	for _, p := range store.Providers {
		if config.IsOfficial(p) {
			continue
		}
		hasThirdParty = true
		if config.GetProviderState(p).Key != config.KeyNone {
			return false
		}
	}
	return hasThirdParty
}

// removeProvider 从 store.Providers 删除指针 p 指向的元素。
func removeProvider(store *config.Store, p *config.Provider) {
	for i := range store.Providers {
		if &store.Providers[i] == p {
			store.Providers = append(store.Providers[:i], store.Providers[i+1:]...)
			return
		}
	}
}
