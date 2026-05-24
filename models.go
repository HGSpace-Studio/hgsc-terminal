package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

const DefaultBaseURL = "https://cschat.ccccocccc.cc/rpc/UniCsAC.php"

type APIResponse struct {
	Success  bool                       `json:"success"`
	Message  string                     `json:"message"`
	User     *User                      `json:"user,omitempty"`
	Friends  []Friend                   `json:"friends,omitempty"`
	Requests []FriendRequest            `json:"requests,omitempty"`
	Notices  []Notice                   `json:"notices,omitempty"`
	Groups   []Group                    `json:"groups,omitempty"`
	Room     *Group                     `json:"room,omitempty"`
	Messages []Message                  `json:"messages,omitempty"`
	Data     json.RawMessage            `json:"data,omitempty"`
	Raw      map[string]json.RawMessage `json:"-"`
}

type User struct {
	UID          int    `json:"uid"`
	Nickname     string `json:"nickname"`
	Avatar       string `json:"avatar"`
	IsFriend     bool   `json:"is_friend"`
	CanAddFriend bool   `json:"can_add_friend"`
	OnlineStatus string `json:"online_status"`
}

type Friend struct {
	UID          int    `json:"uid"`
	FriendID     int    `json:"friend_id"`
	Nickname     string `json:"nickname"`
	Remark       string `json:"remark"`
	Avatar       string `json:"avatar"`
	UnreadCount  int    `json:"unread_count"`
	OnlineStatus string `json:"online_status"`
	LastMsg      string `json:"last_msg"`
	LastMessage  string `json:"last_message"`
}

type FriendRequest struct {
	RequestID  int            `json:"request_id"`
	ID         int            `json:"id"`
	FromUID    int            `json:"from_uid"`
	ToUID      int            `json:"to_uid"`
	Type       int            `json:"type"`
	Status     int            `json:"status"`
	Nickname   string         `json:"nickname"`
	Username   string         `json:"username"`
	Avatar     string         `json:"avatar"`
	Content    string         `json:"content"`
	Message    string         `json:"message"`
	Reason     string         `json:"reason"`
	CreateTime FlexibleString `json:"create_time"`
	HandleTime FlexibleString `json:"handle_time"`
	CreatedAt  FlexibleString `json:"created_at"`
	AddTime    FlexibleString `json:"add_time"`
}

type Notice struct {
	ID      int            `json:"id"`
	Title   string         `json:"title"`
	Content string         `json:"content"`
	AddTime FlexibleString `json:"add_time"`
	IsRead  int            `json:"is_read"`
	Link    string         `json:"link"`
	Route   string         `json:"route"`
}

func (n Notice) NoticeID() int {
	return n.ID
}

func (n Notice) StatusLabel() string {
	if n.IsRead == 0 {
		return "unread"
	}
	return "read"
}

func (n Notice) Timestamp() string {
	return strings.TrimSpace(string(n.AddTime))
}

func (n Notice) Summary() string {
	text := strings.TrimSpace(n.Content)
	if text == "" {
		text = strings.TrimSpace(n.Title)
	}
	return compactText(text, 80)
}

func (r FriendRequest) RID() int {
	if r.RequestID != 0 {
		return r.RequestID
	}
	return r.ID
}

func (r FriendRequest) DisplayName() string {
	name := strings.TrimSpace(r.Nickname)
	if name == "" {
		name = strings.TrimSpace(r.Username)
	}
	if name == "" {
		name = fmt.Sprintf("UID %d", r.FromUID)
	}
	return name
}

func (r FriendRequest) Text() string {
	msg := strings.TrimSpace(r.Content)
	if msg == "" {
		msg = strings.TrimSpace(r.Message)
	}
	if msg == "" {
		msg = strings.TrimSpace(r.Reason)
	}
	return msg
}

func (r FriendRequest) StatusLabel() string {
	switch r.Status {
	case 0:
		return "pending"
	case 1:
		return "accepted"
	case 2:
		return "refused"
	default:
		return fmt.Sprintf("status %d", r.Status)
	}
}

func (r FriendRequest) KindLabel() string {
	switch r.Type {
	case 1:
		return "friend"
	default:
		return fmt.Sprintf("type %d", r.Type)
	}
}

func (r FriendRequest) Timestamp() string {
	for _, value := range []FlexibleString{r.CreateTime, r.HandleTime, r.CreatedAt, r.AddTime} {
		text := strings.TrimSpace(string(value))
		if text != "" {
			return text
		}
	}
	return ""
}

func (r FriendRequest) Summary() string {
	msg := strings.TrimSpace(r.Message)
	if msg == "" {
		msg = strings.TrimSpace(r.Content)
	}
	if msg == "" {
		msg = strings.TrimSpace(r.Reason)
	}
	return fmt.Sprintf("[%s/%s] %s", r.KindLabel(), r.StatusLabel(), msg)
}

func (f Friend) ID() int {
	if f.FriendID != 0 {
		return f.FriendID
	}
	return f.UID
}

func (f Friend) DisplayName() string {
	name := strings.TrimSpace(f.Remark)
	if name == "" {
		name = strings.TrimSpace(f.Nickname)
	}
	if name == "" {
		name = fmt.Sprintf("User %d", f.ID())
	}
	return name
}

func (f Friend) Subtitle() string {
	parts := make([]string, 0, 2)
	if f.OnlineStatus != "" {
		parts = append(parts, f.OnlineStatus)
	}
	last := strings.TrimSpace(f.LastMessage)
	if last == "" {
		last = strings.TrimSpace(f.LastMsg)
	}
	if last != "" {
		parts = append(parts, compactText(last, 42))
	}
	return strings.Join(parts, " | ")
}

type Group struct {
	RoomID      int    `json:"room_id"`
	ID          int    `json:"id"`
	RoomName    string `json:"room_name"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Notice      string `json:"notice"`
	InviteCode  string `json:"invite_code"`
	UnreadCount int    `json:"unread_count"`
	MemberCount int    `json:"member_count"`
	IsInGroup   bool   `json:"is_in_group"`
	IsAdmin     bool   `json:"is_admin"`
	IsOwner     bool   `json:"is_owner"`
}

func (g Group) Room() int {
	if g.RoomID != 0 {
		return g.RoomID
	}
	return g.ID
}

func (g Group) DisplayName() string {
	name := strings.TrimSpace(g.RoomName)
	if name == "" {
		name = strings.TrimSpace(g.Name)
	}
	if name == "" {
		name = fmt.Sprintf("Room %d", g.Room())
	}
	return name
}

func (g Group) Subtitle() string {
	parts := make([]string, 0, 3)
	if g.MemberCount > 0 {
		parts = append(parts, fmt.Sprintf("%d members", g.MemberCount))
	}
	if g.Description != "" {
		parts = append(parts, compactText(g.Description, 42))
	}
	if g.Notice != "" {
		parts = append(parts, compactText(g.Notice, 42))
	}
	return strings.Join(parts, " | ")
}

type Message struct {
	ID            int            `json:"id"`
	MsgID         int            `json:"msg_id"`
	UID           int            `json:"uid"`
	FromUID       int            `json:"from_uid"`
	UserID        int            `json:"user_id"`
	Nickname      string         `json:"nickname"`
	SenderName    string         `json:"sender_name"`
	Content       string         `json:"content"`
	Img           string         `json:"img"`
	Image         string         `json:"image"`
	ImageURL      string         `json:"image_url"`
	Voice         string         `json:"voice"`
	VoiceURL      string         `json:"voice_url"`
	Duration      int            `json:"duration"`
	VoiceDuration int            `json:"voice_duration"`
	AddTime       FlexibleString `json:"add_time"`
	CreatedAt     FlexibleString `json:"created_at"`
	CreateTime    FlexibleString `json:"create_time"`
	Time          FlexibleString `json:"time"`
	CanRecall     bool           `json:"can_recall"`
	IsEssence     bool           `json:"is_essence"`
	IsMentioned   bool           `json:"is_mentioned"`
	ReplyTo       int            `json:"reply_to"`
}

func (m Message) MessageID() int {
	if m.MsgID != 0 {
		return m.MsgID
	}
	return m.ID
}

func (m Message) SenderID() int {
	for _, id := range []int{m.FromUID, m.UID, m.UserID} {
		if id != 0 {
			return id
		}
	}
	return 0
}

func (m Message) Sender() string {
	name := strings.TrimSpace(m.Nickname)
	if name == "" {
		name = strings.TrimSpace(m.SenderName)
	}
	if name == "" {
		if id := m.SenderID(); id != 0 {
			name = "UID " + strconv.Itoa(id)
		} else {
			name = "unknown"
		}
	}
	return name
}

func (m Message) Timestamp() string {
	for _, value := range []FlexibleString{m.AddTime, m.CreatedAt, m.CreateTime, m.Time} {
		text := strings.TrimSpace(string(value))
		if text != "" {
			return text
		}
	}
	return ""
}

func (m Message) Body() string {
	body := strings.TrimSpace(m.Content)
	if body == "" && m.Img != "" {
		body = "[image] " + m.Img
	}
	if body == "" && m.Image != "" {
		body = "[image] " + m.Image
	}
	if body == "" && m.ImageURL != "" {
		body = "[image] " + m.ImageURL
	}
	if body == "" && m.Voice != "" {
		body = fmt.Sprintf("[voice %ds] %s", m.voiceDuration(), m.Voice)
	}
	if body == "" && m.VoiceURL != "" {
		body = fmt.Sprintf("[voice %ds] %s", m.voiceDuration(), m.VoiceURL)
	}
	if body == "" {
		body = "[empty]"
	}
	return body
}

func (m Message) ImageLink() string {
	for _, value := range []string{m.ImageURL, m.Image, m.Img} {
		value = strings.TrimSpace(value)
		if value != "" {
			return value
		}
	}
	return ""
}

func (m Message) HasImage() bool {
	return m.ImageLink() != ""
}

func (m Message) voiceDuration() int {
	if m.Duration > 0 {
		return m.Duration
	}
	return m.VoiceDuration
}

type ConversationType string

const (
	ConversationFriend ConversationType = "private"
	ConversationGroup  ConversationType = "group"
)

type Conversation struct {
	Type        ConversationType
	ID          int
	Name        string
	Subtitle    string
	UnreadCount int
}

type FlexibleString string

func (s *FlexibleString) UnmarshalJSON(data []byte) error {
	data = bytes.TrimSpace(data)
	if bytes.Equal(data, []byte("null")) {
		*s = ""
		return nil
	}
	var text string
	if err := json.Unmarshal(data, &text); err == nil {
		*s = FlexibleString(text)
		return nil
	}
	var number json.Number
	if err := json.Unmarshal(data, &number); err == nil {
		if number.String() == "0" {
			*s = ""
		} else {
			*s = FlexibleString(number.String())
		}
		return nil
	}
	return fmt.Errorf("unsupported flexible string value: %s", compactText(string(data), 80))
}

func compactText(s string, max int) string {
	s = strings.Join(strings.Fields(strings.TrimSpace(s)), " ")
	if len([]rune(s)) <= max {
		return s
	}
	r := []rune(s)
	if max <= 1 {
		return string(r[:max])
	}
	return string(r[:max-1]) + "..."
}
