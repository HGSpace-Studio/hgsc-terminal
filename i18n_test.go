package main

import "testing"

func TestNormalizeLanguage(t *testing.T) {
	tests := map[Language]Language{
		"":        LanguageEnglish,
		"en":      LanguageEnglish,
		"zh":      LanguageChinese,
		"zh-cn":   LanguageChinese,
		"cn":      LanguageChinese,
		"chinese": LanguageChinese,
		"other":   LanguageEnglish,
	}
	for input, want := range tests {
		if got := normalizeLanguage(input); got != want {
			t.Fatalf("normalizeLanguage(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestTranslateFallsBackToEnglishAndFormats(t *testing.T) {
	if got := translate(Language("other"), "auth.login"); got != "Login" {
		t.Fatalf("fallback translate = %q", got)
	}
	if got := translate(LanguageChinese, "status.unread_items", 3); got != "未读项目：3" {
		t.Fatalf("formatted translate = %q", got)
	}
	if got := translate(LanguageChinese, "missing.key"); got != "missing.key" {
		t.Fatalf("missing translate = %q", got)
	}
}

func TestTranslationsHaveSameKeys(t *testing.T) {
	for key := range translations[LanguageEnglish] {
		if translations[LanguageChinese][key] == "" {
			t.Fatalf("missing Chinese translation for %q", key)
		}
	}
	for key := range translations[LanguageChinese] {
		if translations[LanguageEnglish][key] == "" {
			t.Fatalf("missing English translation for %q", key)
		}
	}
}
