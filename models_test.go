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

func TestMessageImageLink(t *testing.T) {
	msg := Message{ImageURL: "upload/a.png", Image: "ignored", Img: "ignored"}
	if got := msg.ImageLink(); got != "upload/a.png" {
		t.Fatalf("ImageLink() = %q", got)
	}
	if !msg.HasImage() {
		t.Fatal("HasImage() = false")
	}
}

func TestFriendRequestsDecodeRealShape(t *testing.T) {
	payload := []byte(`{"success":true,"requests":[{"id":17,"from_uid":1,"to_uid":25,"type":1,"status":0,"content":"请求添加你为好友","create_time":"2026-05-11 08:29:51","handle_time":null,"nickname":"小化喵~","avatar":"upload/avatar_1_2376d8d1f335_1778303645.png","username":"xiaohua"}]}`)

	var out APIResponse
	if err := json.Unmarshal(payload, &out); err != nil {
		t.Fatalf("unmarshal API response: %v", err)
	}
	if len(out.Requests) != 1 {
		t.Fatalf("len(Requests) = %d", len(out.Requests))
	}
	req := out.Requests[0]
	if req.RID() != 17 {
		t.Fatalf("RID() = %d", req.RID())
	}
	if got := req.StatusLabel(); got != "pending" {
		t.Fatalf("StatusLabel() = %q", got)
	}
	if got := req.KindLabel(); got != "friend" {
		t.Fatalf("KindLabel() = %q", got)
	}
	if got := req.Text(); got != "请求添加你为好友" {
		t.Fatalf("Text() = %q", got)
	}
	if got := req.Timestamp(); got != "2026-05-11 08:29:51" {
		t.Fatalf("Timestamp() = %q", got)
	}
}
