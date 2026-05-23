package main

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestSessionStoreSaveLoadAndClear(t *testing.T) {
	dir := t.TempDir()
	store := &SessionStore{path: filepath.Join(dir, "session.json")}

	client := NewUniCsACClient(DefaultBaseURL)
	if err := client.SetSessionCookies([]*http.Cookie{
		{Name: "PHPSESSID", Value: "abc123", Path: "/"},
		{Name: "__test", Value: "challenge", Path: "/"},
	}); err != nil {
		t.Fatalf("set cookies: %v", err)
	}

	if err := store.Save(client, &User{UID: 4, Nickname: "tester"}); err != nil {
		t.Fatalf("save session: %v", err)
	}
	if _, err := os.Stat(store.Path()); err != nil {
		t.Fatalf("session file was not written: %v", err)
	}

	nextClient := NewUniCsACClient(DefaultBaseURL)
	loaded, err := store.Load(nextClient)
	if err != nil {
		t.Fatalf("load session: %v", err)
	}
	if !loaded {
		t.Fatal("Load reported no saved session")
	}
	cookies, err := nextClient.SessionCookies()
	if err != nil {
		t.Fatalf("read cookies: %v", err)
	}
	if len(cookies) != 2 {
		t.Fatalf("loaded %d cookies, want 2", len(cookies))
	}

	if err := store.Clear(); err != nil {
		t.Fatalf("clear session: %v", err)
	}
	if _, err := os.Stat(store.Path()); !os.IsNotExist(err) {
		t.Fatalf("session file still exists or stat failed unexpectedly: %v", err)
	}
}
