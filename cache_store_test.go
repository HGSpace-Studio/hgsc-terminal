package main

import (
	"path/filepath"
	"testing"
)

func TestCacheStoreSavesLoadsAndSearchesMessages(t *testing.T) {
	store, err := OpenCacheStore(filepath.Join(t.TempDir(), "cache.db"))
	if err != nil {
		t.Fatalf("OpenCacheStore: %v", err)
	}
	defer store.Close()

	conv := Conversation{
		Type:     ConversationGroup,
		ID:       42,
		Name:     "Chem Room",
		Subtitle: "lab notes",
	}
	messages := []Message{
		{ID: 2, UID: 7, Nickname: "Alice", Content: "second zinc message", AddTime: "2026-05-24 10:00:02", IsEssence: FlexibleBool(true)},
		{ID: 1, UID: 8, Nickname: "Bob", Content: "first cached message", AddTime: "2026-05-24 10:00:01", ImageURL: "upload/a.png"},
	}
	if err := store.SaveMessages(conv, messages); err != nil {
		t.Fatalf("SaveMessages: %v", err)
	}

	loaded, err := store.LoadMessages(conv, 10)
	if err != nil {
		t.Fatalf("LoadMessages: %v", err)
	}
	if len(loaded) != 2 {
		t.Fatalf("len(loaded) = %d", len(loaded))
	}
	if loaded[0].MessageID() != 1 || loaded[1].MessageID() != 2 {
		t.Fatalf("loaded message order = %d,%d", loaded[0].MessageID(), loaded[1].MessageID())
	}
	if got := loaded[0].ImageLink(); got != "upload/a.png" {
		t.Fatalf("ImageLink() = %q", got)
	}

	results, err := store.Search("zinc", 10)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) != 1 {
		t.Fatalf("len(results) = %d", len(results))
	}
	if results[0].Kind != SearchResultMessage || results[0].Message.MessageID() != 2 {
		t.Fatalf("unexpected result: %#v", results[0])
	}

	conversations, err := store.LoadConversations()
	if err != nil {
		t.Fatalf("LoadConversations: %v", err)
	}
	if len(conversations) != 1 || conversations[0].Name != "Chem Room" {
		t.Fatalf("LoadConversations() = %#v", conversations)
	}
}

func TestParseUIDList(t *testing.T) {
	got := parseUIDList("1, 2, nope, 2, 0, 3")
	want := []int{1, 2, 3}
	if len(got) != len(want) {
		t.Fatalf("parseUIDList length = %d", len(got))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("parseUIDList[%d] = %d, want %d", i, got[i], want[i])
		}
	}
}
