package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestConfigStoreSaveLoadLanguage(t *testing.T) {
	dir := t.TempDir()
	store := &ConfigStore{path: filepath.Join(dir, "config.json")}

	if err := store.Save(AppConfig{Language: "zh-cn"}); err != nil {
		t.Fatalf("save config: %v", err)
	}
	if _, err := os.Stat(store.Path()); err != nil {
		t.Fatalf("config file was not written: %v", err)
	}

	cfg, err := store.Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	if cfg.Language != LanguageChinese {
		t.Fatalf("Language = %q, want %q", cfg.Language, LanguageChinese)
	}
}

func TestConfigStoreLoadMissingDefaultsToEnglish(t *testing.T) {
	store := &ConfigStore{path: filepath.Join(t.TempDir(), "missing", "config.json")}

	cfg, err := store.Load()
	if err != nil {
		t.Fatalf("load missing config: %v", err)
	}
	if cfg.Language != LanguageEnglish {
		t.Fatalf("Language = %q, want %q", cfg.Language, LanguageEnglish)
	}
}
