// Package i18n 是 i18n 运行时：T() 翻译、当前语言、语言解析，以及配置的本地化显示助手。
//
// 语言来源优先级（plan §5）：--lang > providers.json 的 lang > 环境 LC_ALL/LANG/LANGUAGE > 默认 zh。
package i18n

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/becomeless/cc-x/internal/config"
)

var current = config.LangZH

// SetLang 设置本次进程的界面语言（启动时按 ResolveLang 的结果调用一次）。
func SetLang(lang config.Lang) { current = lang }

// GetLang 返回当前界面语言。
func GetLang() config.Lang { return current }

// T 翻译：查目录取当前语言文案，按序替换 {0} {1} …。
// 缺 key 时返回 key 本身（便于一眼发现漏翻），缺当前语言文案时回退 zh。
func T(key string, args ...any) string {
	m, ok := messages[key]
	if !ok {
		return key
	}
	s := m.zh
	if current == config.LangEN && m.en != "" {
		s = m.en
	}
	for i, a := range args {
		s = strings.ReplaceAll(s, "{"+strconv.Itoa(i)+"}", fmt.Sprint(a))
	}
	return s
}

// ResolveLang 解析本次界面语言。explicit 来自 --lang，storeLang 来自 providers.json。
// 环境变量：含 zh -> 中文；以 en 开头（如 en_US）-> 英文；其余默认 zh。
func ResolveLang(explicit, storeLang config.Lang) config.Lang {
	if explicit != "" {
		return explicit
	}
	if storeLang != "" {
		return storeLang
	}
	env := strings.ToLower(firstNonEmpty(os.Getenv("LC_ALL"), os.Getenv("LANG"), os.Getenv("LANGUAGE")))
	if strings.Contains(env, "zh") {
		return config.LangZH
	}
	if strings.HasPrefix(env, "en") {
		return config.LangEN
	}
	return config.LangZH
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

// ProviderDisplayName 返回配置的显示名：官方档显示翻译后的「官方/Official」（评审①：显示名与数据主键解耦）；
// 其余是专有名词，原样显示 Name。
func ProviderDisplayName(p config.Provider) string {
	if config.IsOfficial(p) {
		return T("provider.official")
	}
	return p.Name
}

// StateLabel 返回配置的状态文案（语义枚举 -> 当前语言；effort 原样附加）。
func StateLabel(p config.Provider) string {
	s := config.GetProviderState(p)
	var base string
	switch s.Key {
	case config.KeyOfficial:
		base = T("state.login")
	case config.KeyNone:
		base = T("state.noKey")
	case config.KeyAPIKey:
		base = T("state.apiKey")
	default:
		base = T("state.hasKey")
	}
	if s.Effort != "" {
		return base + " · effort=" + s.Effort
	}
	return base
}

// NoteSuffix 返回备注后缀（有备注才显示）。
func NoteSuffix(p config.Provider) string {
	if p.Note != "" {
		return "  — " + p.Note
	}
	return ""
}
