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
	Members  []GroupMember              `json:"members,omitempty"`
	Applies  []GroupApplication         `json:"applications,omitempty"`
	Messages []Message                  `json:"messages,omitempty"`
	Essences []Message                  `json:"essence_list,omitempty"`
	Data     json.RawMessage            `json:"data,omitempty"`
	Raw      map[string]json.RawMessage `json:"-"`
}

type User struct {
	UID          int    `json:"uid"`
	Username     string `json:"username"`
	Nickname     string `json:"nickname"`
	Avatar       string `json:"avatar"`
	IsFriend     bool   `json:"is_friend"`
	CanAddFriend bool   `json:"can_add_friend"`
	OnlineStatus string `json:"online_status"`
	Remark       string `json:"remark"`
	Signature    string `json:"signature"`
	Bio          string `json:"bio"`
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

type GroupApplication struct {
	ApplyID    int            `json:"apply_id"`
	ID         int            `json:"id"`
	RoomID     int            `json:"room_id"`
	UID        int            `json:"uid"`
	UserID     int            `json:"user_id"`
	Nickname   string         `json:"nickname"`
	Username   string         `json:"username"`
	Avatar     string         `json:"avatar"`
	Content    string         `json:"content"`
	Message    string         `json:"message"`
	Answer     string         `json:"answer"`
	Status     int            `json:"status"`
	CreateTime FlexibleString `json:"create_time"`
	AddTime    FlexibleString `json:"add_time"`
	HandleTime FlexibleString `json:"handle_time"`
}

func (a GroupApplication) IDValue() int {
	if a.ApplyID != 0 {
		return a.ApplyID
	}
	return a.ID
}

func (a GroupApplication) UserIDValue() int {
	if a.UID != 0 {
		return a.UID
	}
	return a.UserID
}

func (a GroupApplication) DisplayName() string {
	name := strings.TrimSpace(a.Nickname)
	if name == "" {
		name = strings.TrimSpace(a.Username)
	}
	if name == "" {
		name = fmt.Sprintf("UID %d", a.UserIDValue())
	}
	return name
}

func (a GroupApplication) Text() string {
	for _, value := range []string{a.Content, a.Message, a.Answer} {
		if text := strings.TrimSpace(value); text != "" {
			return text
		}
	}
	return ""
}

func (a GroupApplication) Timestamp() string {
	for _, value := range []FlexibleString{a.CreateTime, a.AddTime, a.HandleTime} {
		text := strings.TrimSpace(string(value))
		if text != "" {
			return text
		}
	}
	return ""
}

func (a GroupApplication) Summary() string {
	return strings.Join(nonEmptyStrings([]string{
		fmt.Sprintf("UID %d", a.UserIDValue()),
		compactText(a.Text(), 50),
		a.Timestamp(),
	}), " | ")
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
	RoomID        int            `json:"room_id"`
	ID            int            `json:"id"`
	RoomName      string         `json:"room_name"`
	Name          string         `json:"name"`
	Description   string         `json:"description"`
	Notice        string         `json:"notice"`
	InviteCode    string         `json:"invite_code"`
	Code          string         `json:"code"`
	FixedCode     string         `json:"fixed_code"`
	JoinCode      string         `json:"join_code"`
	Question      string         `json:"question"`
	ApplyQuestion string         `json:"apply_question"`
	AuditQuestion string         `json:"audit_question"`
	Answer        string         `json:"answer"`
	JoinType      FlexibleString `json:"join_type"`
	JoinMode      FlexibleString `json:"join_mode"`
	JoinMethod    FlexibleString `json:"join_method"`
	ShowPublic    FlexibleString `json:"show_public"`
	IsPublic      FlexibleString `json:"is_public"`
	UnreadCount   int            `json:"unread_count"`
	MemberCount   int            `json:"member_count"`
	IsInGroup     bool           `json:"is_in_group"`
	IsAdmin       bool           `json:"is_admin"`
	IsOwner       bool           `json:"is_owner"`
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

func (g Group) JoinTypeValue() string {
	for _, value := range []FlexibleString{g.JoinType, g.JoinMode, g.JoinMethod} {
		text := strings.TrimSpace(string(value))
		if text != "" {
			return text
		}
	}
	return ""
}

func (g Group) FixedCodeValue() string {
	for _, value := range []string{g.Code, g.FixedCode, g.JoinCode} {
		text := strings.TrimSpace(value)
		if text != "" {
			return text
		}
	}
	return ""
}

func (g Group) QuestionValue() string {
	for _, value := range []string{g.Question, g.ApplyQuestion, g.AuditQuestion} {
		text := strings.TrimSpace(value)
		if text != "" {
			return text
		}
	}
	return ""
}

func (g Group) ShowPublicEnabled() bool {
	for _, value := range []FlexibleString{g.ShowPublic, g.IsPublic} {
		text := strings.ToLower(strings.TrimSpace(string(value)))
		switch text {
		case "1", "true", "yes", "on":
			return true
		case "0", "false", "no", "off":
			return false
		}
	}
	return false
}

type GroupMember struct {
	UID          int            `json:"uid"`
	UserID       int            `json:"user_id"`
	Nickname     string         `json:"nickname"`
	Username     string         `json:"username"`
	Remark       string         `json:"remark"`
	Avatar       string         `json:"avatar"`
	Role         string         `json:"role"`
	IsOwner      bool           `json:"is_owner"`
	IsAdmin      bool           `json:"is_admin"`
	OnlineStatus string         `json:"online_status"`
	JoinTime     FlexibleString `json:"join_time"`
	AddTime      FlexibleString `json:"add_time"`
	MuteUntil    FlexibleString `json:"mute_until"`
}

func (m GroupMember) ID() int {
	if m.UID != 0 {
		return m.UID
	}
	return m.UserID
}

func (m GroupMember) DisplayName() string {
	name := strings.TrimSpace(m.Remark)
	if name == "" {
		name = strings.TrimSpace(m.Nickname)
	}
	if name == "" {
		name = strings.TrimSpace(m.Username)
	}
	if name == "" {
		name = fmt.Sprintf("UID %d", m.ID())
	}
	return name
}

func (m GroupMember) RoleLabel() string {
	switch {
	case m.IsOwner:
		return "owner"
	case m.IsAdmin:
		return "admin"
	case strings.TrimSpace(m.Role) != "":
		return m.Role
	default:
		return "member"
	}
}

func (m GroupMember) Subtitle() string {
	parts := make([]string, 0, 4)
	if m.Username != "" {
		parts = append(parts, "@"+m.Username)
	}
	if m.OnlineStatus != "" {
		parts = append(parts, m.OnlineStatus)
	}
	if text := strings.TrimSpace(string(m.MuteUntil)); text != "" {
		parts = append(parts, "muted until "+text)
	}
	for _, ts := range []FlexibleString{m.JoinTime, m.AddTime} {
		if text := strings.TrimSpace(string(ts)); text != "" {
			parts = append(parts, text)
			break
		}
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

func (m Message) VoiceLink() string {
	for _, value := range []string{m.VoiceURL, m.Voice} {
		value = strings.TrimSpace(value)
		if value != "" {
			return value
		}
	}
	return ""
}

func (m Message) SearchText() string {
	parts := []string{m.Sender(), m.Body()}
	if ts := m.Timestamp(); ts != "" {
		parts = append(parts, ts)
	}
	return strings.Join(parts, " | ")
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
	PeerUID     int
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
	var boolean bool
	if err := json.Unmarshal(data, &boolean); err == nil {
		if boolean {
			*s = "1"
		} else {
			*s = "0"
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

func nonEmptyStrings(values []string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" {
			out = append(out, value)
		}
	}
	return out
}
