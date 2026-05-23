package main

import (
	"encoding/json"
	"testing"
)

func TestMessageDecodesMixedTimeFields(t *testing.T) {
	payload := []byte(`{
		"success": true,
		"messages": [{
			"id": 14,
			"uid": 4,
			"from_uid": null,
			"to_uid": null,
			"nickname": "万盛",
			"content": "可爱万盛",
			"msg_type": 1,
			"image_url": "",
			"voice_url": "",
			"duration": 0,
			"voice_duration": 0,
			"add_time": "2026-04-29 18:48:35",
			"created_at": 0,
			"avatar": "upload/avatar_4_1777527010.png",
			"is_recalled": 0
		}]
	}`)

	var out APIResponse
	if err := json.Unmarshal(payload, &out); err != nil {
		t.Fatalf("unmarshal API response: %v", err)
	}
	if got := out.Messages[0].Timestamp(); got != "2026-04-29 18:48:35" {
		t.Fatalf("Timestamp() = %q", got)
	}
	if got := out.Messages[0].Body(); got != "可爱万盛" {
		t.Fatalf("Body() = %q", got)
	}
}
