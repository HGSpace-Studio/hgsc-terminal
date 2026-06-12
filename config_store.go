package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

type ConfigStore struct {
	path string
}

func NewConfigStore() (*ConfigStore, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return nil, err
	}
	return &ConfigStore{
		path: filepath.Join(dir, "HGSC", "config.json"),
	}, nil
}

func (s *ConfigStore) Load() (AppConfig, error) {
	cfg := AppConfig{Language: LanguageEnglish}
	data, err := os.ReadFile(s.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return cfg, nil
		}
		return cfg, err
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return AppConfig{Language: LanguageEnglish}, err
	}
	cfg.Language = normalizeLanguage(cfg.Language)
	return cfg, nil
}

func (s *ConfigStore) Save(cfg AppConfig) error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0700); err != nil {
		return err
	}
	cfg.Language = normalizeLanguage(cfg.Language)
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, data, 0600)
}

func (s *ConfigStore) Path() string {
	return s.path
}
