package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

type SessionStore struct {
	path string
}

type persistedSession struct {
	BaseURL  string            `json:"base_url"`
	SavedAt  time.Time         `json:"saved_at"`
	Cookies  []persistedCookie `json:"cookies"`
	UserID   int               `json:"user_id,omitempty"`
	Nickname string            `json:"nickname,omitempty"`
}

type persistedCookie struct {
	Name     string    `json:"name"`
	Value    string    `json:"value"`
	Path     string    `json:"path,omitempty"`
	Domain   string    `json:"domain,omitempty"`
	Expires  time.Time `json:"expires,omitempty"`
	Secure   bool      `json:"secure,omitempty"`
	HTTPOnly bool      `json:"http_only,omitempty"`
}

func NewSessionStore() (*SessionStore, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return nil, err
	}
	return &SessionStore{
		path: filepath.Join(dir, "HGSC", "session.json"),
	}, nil
}

func (s *SessionStore) Load(client *UniCsACClient) (bool, error) {
	data, err := os.ReadFile(s.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}

	var session persistedSession
	if err := json.Unmarshal(data, &session); err != nil {
		return false, err
	}
	if session.BaseURL != "" && session.BaseURL != client.BaseURL() {
		return false, nil
	}
	cookies := make([]*http.Cookie, 0, len(session.Cookies))
	now := time.Now()
	for _, cookie := range session.Cookies {
		if cookie.Name == "" {
			continue
		}
		if !cookie.Expires.IsZero() && cookie.Expires.Before(now) {
			continue
		}
		cookies = append(cookies, &http.Cookie{
			Name:     cookie.Name,
			Value:    cookie.Value,
			Path:     cookie.Path,
			Domain:   cookie.Domain,
			Expires:  cookie.Expires,
			Secure:   cookie.Secure,
			HttpOnly: cookie.HTTPOnly,
		})
	}
	if len(cookies) == 0 {
		return false, nil
	}
	return true, client.SetSessionCookies(cookies)
}

func (s *SessionStore) Save(client *UniCsACClient, user *User) error {
	cookies, err := client.SessionCookies()
	if err != nil {
		return err
	}
	session := persistedSession{
		BaseURL: client.BaseURL(),
		SavedAt: time.Now(),
	}
	if user != nil {
		session.UserID = user.UID
		session.Nickname = user.Nickname
	}
	for _, cookie := range cookies {
		if cookie == nil || cookie.Name == "" {
			continue
		}
		session.Cookies = append(session.Cookies, persistedCookie{
			Name:     cookie.Name,
			Value:    cookie.Value,
			Path:     cookie.Path,
			Domain:   cookie.Domain,
			Expires:  cookie.Expires,
			Secure:   cookie.Secure,
			HTTPOnly: cookie.HttpOnly,
		})
	}
	if len(session.Cookies) == 0 {
		return s.Clear()
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(session, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, data, 0600)
}

func (s *SessionStore) Clear() error {
	if err := os.Remove(s.path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func (s *SessionStore) Path() string {
	return s.path
}
