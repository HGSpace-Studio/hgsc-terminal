package main

import "testing"

func TestMergeMessagesDeduplicatesByID(t *testing.T) {
	existing := []Message{{ID: 1, Content: "old"}, {ID: 2, Content: "two"}}
	incoming := []Message{{ID: 2, Content: "dupe"}, {ID: 3, Content: "new"}}

	got := mergeMessages(existing, incoming)
	if len(got) != 3 {
		t.Fatalf("len(mergeMessages) = %d", len(got))
	}
	if got[0].ID != 1 || got[1].ID != 2 || got[2].ID != 3 {
		t.Fatalf("merged IDs = %d,%d,%d", got[0].ID, got[1].ID, got[2].ID)
	}
}

func TestNormalizeAPIURL(t *testing.T) {
	if got := normalizeAPIURL("upload/a.png"); got != "https://cschat.ccccocccc.cc/upload/a.png" {
		t.Fatalf("normalize relative URL = %q", got)
	}
	if got := normalizeAPIURL("https://example.com/a.png"); got != "https://example.com/a.png" {
		t.Fatalf("normalize absolute URL = %q", got)
	}
}
