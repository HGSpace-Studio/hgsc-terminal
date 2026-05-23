package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const browserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

var (
	challengeVarsRE = regexp.MustCompile(`var\s+a=toNumbers\("([0-9a-fA-F]+)"\),b=toNumbers\("([0-9a-fA-F]+)"\),c=toNumbers\("([0-9a-fA-F]+)"\)`)
	challengeLocRE  = regexp.MustCompile(`location\.href="([^"]+)"`)
)

type UniCsACClient struct {
	baseURL string
	http    *http.Client
}

func NewUniCsACClient(baseURL string) *UniCsACClient {
	jar, _ := cookiejar.New(nil)
	return &UniCsACClient{
		baseURL: baseURL,
		http: &http.Client{
			Timeout: 20 * time.Second,
			Jar:     jar,
		},
	}
}

func (c *UniCsACClient) BaseURL() string {
	return c.baseURL
}

func (c *UniCsACClient) SessionCookies() ([]*http.Cookie, error) {
	u, err := url.Parse(c.baseURL)
	if err != nil {
		return nil, err
	}
	if c.http.Jar == nil {
		return nil, nil
	}
	return c.http.Jar.Cookies(u), nil
}

func (c *UniCsACClient) SetSessionCookies(cookies []*http.Cookie) error {
	u, err := url.Parse(c.baseURL)
	if err != nil {
		return err
	}
	if c.http.Jar == nil {
		jar, err := cookiejar.New(nil)
		if err != nil {
			return err
		}
		c.http.Jar = jar
	}
	c.http.Jar.SetCookies(u, cookies)
	return nil
}

func (c *UniCsACClient) Login(username, password string) (*User, error) {
	var out APIResponse
	if err := c.PostForm("auth/login", url.Values{"username": {username}, "pwd": {password}}, &out); err != nil {
		return nil, err
	}
	if out.User == nil {
		return nil, errors.New("login succeeded but server did not return a user")
	}
	return out.User, nil
}

func (c *UniCsACClient) Register(username, nickname, password string) (*User, error) {
	var out APIResponse
	values := url.Values{
		"username":    {username},
		"nickname":    {nickname},
		"pwd":         {password},
		"confirm_pwd": {password},
	}
	if err := c.PostForm("auth/register", values, &out); err != nil {
		return nil, err
	}
	if out.User == nil {
		return nil, errors.New("register succeeded but server did not return a user")
	}
	return out.User, nil
}

func (c *UniCsACClient) Logout() error {
	var out APIResponse
	return c.PostForm("auth/logout", nil, &out)
}

func (c *UniCsACClient) Test() error {
	var out APIResponse
	return c.Get("test", nil, &out)
}

func (c *UniCsACClient) CurrentUser() (*User, error) {
	var out APIResponse
	if err := c.Get("user/get_info", nil, &out); err != nil {
		return nil, err
	}
	if out.User == nil {
		return nil, errors.New("server did not return current user")
	}
	return out.User, nil
}

func (c *UniCsACClient) Friends() ([]Friend, error) {
	var out APIResponse
	if err := c.Get("user/get_friends", nil, &out); err != nil {
		return nil, err
	}
	return out.Friends, nil
}

func (c *UniCsACClient) Groups() ([]Group, error) {
	var out APIResponse
	if err := c.Get("user/get_groups", nil, &out); err != nil {
		return nil, err
	}
	return out.Groups, nil
}

func (c *UniCsACClient) PublicGroups() ([]Group, error) {
	var out APIResponse
	if err := c.Get("group/get_public_list", nil, &out); err != nil {
		return nil, err
	}
	if len(out.Groups) > 0 {
		return out.Groups, nil
	}
	var groups []Group
	for _, key := range []string{"rooms", "list", "data"} {
		if raw, ok := out.Raw[key]; ok {
			if json.Unmarshal(raw, &groups) == nil {
				return groups, nil
			}
		}
	}
	return groups, nil
}

func (c *UniCsACClient) CreateGroup(name string) (*Group, error) {
	var out APIResponse
	if err := c.PostForm("group/create", url.Values{"room_name": {name}}, &out); err != nil {
		return nil, err
	}
	group := Group{}
	if out.Room != nil {
		group = *out.Room
	}
	for _, key := range []string{"room_id", "id"} {
		if raw, ok := out.Raw[key]; ok {
			var id int
			if json.Unmarshal(raw, &id) == nil {
				group.RoomID = id
				break
			}
		}
	}
	if raw, ok := out.Raw["invite_code"]; ok {
		_ = json.Unmarshal(raw, &group.InviteCode)
	}
	if group.RoomName == "" {
		group.RoomName = name
	}
	if group.Room() == 0 {
		return nil, errors.New("group created but server did not return room_id")
	}
	return &group, nil
}

func (c *UniCsACClient) ApplyJoinGroup(roomID int, code, answer string) error {
	values := url.Values{"room_id": {fmt.Sprint(roomID)}}
	if code != "" {
		values.Set("code", code)
	}
	if answer != "" {
		values.Set("answer", answer)
	}
	var out APIResponse
	return c.PostForm("group/apply_join", values, &out)
}

func (c *UniCsACClient) SendFriendRequest(uid int, message string) error {
	values := url.Values{"to_uid": {fmt.Sprint(uid)}}
	if message != "" {
		values.Set("message", message)
	}
	var out APIResponse
	return c.PostForm("friend/send_request", values, &out)
}

func (c *UniCsACClient) GroupMessages(roomID, afterID, beforeID, limit int) ([]Message, error) {
	values := url.Values{"room_id": {fmt.Sprint(roomID)}}
	if afterID > 0 {
		values.Set("after_id", fmt.Sprint(afterID))
	}
	if beforeID > 0 {
		values.Set("before_id", fmt.Sprint(beforeID))
	}
	if limit > 0 {
		values.Set("limit", fmt.Sprint(limit))
	}
	var out APIResponse
	if err := c.Get("message/get_group_msg", values, &out); err != nil {
		return nil, err
	}
	return decodeMessages(out), nil
}

func (c *UniCsACClient) GroupMessagesAfter(roomID, afterID int) ([]Message, error) {
	return c.GroupMessages(roomID, afterID, 0, 80)
}

func (c *UniCsACClient) PrivateMessages(friendID, lastID, beforeID, afterID int) ([]Message, error) {
	values := url.Values{"friend_id": {fmt.Sprint(friendID)}}
	if lastID > 0 {
		values.Set("last_id", fmt.Sprint(lastID))
	}
	if beforeID > 0 {
		values.Set("before_id", fmt.Sprint(beforeID))
	}
	if afterID > 0 {
		values.Set("after_id", fmt.Sprint(afterID))
	}
	var out APIResponse
	if err := c.Get("message/get_private_msg", values, &out); err != nil {
		return nil, err
	}
	return decodeMessages(out), nil
}

func (c *UniCsACClient) PrivateMessagesAfter(friendID, afterID int) ([]Message, error) {
	if afterID > 0 {
		return c.PrivateMessages(friendID, 0, 0, afterID)
	}
	return c.PrivateMessages(friendID, 0, 0, 0)
}

func (c *UniCsACClient) SendGroupMessage(roomID int, content string) error {
	var out APIResponse
	return c.PostForm("message/send_group_msg", url.Values{
		"room_id": {fmt.Sprint(roomID)},
		"content": {content},
	}, &out)
}

func (c *UniCsACClient) SendPrivateMessage(friendID int, content string) error {
	var out APIResponse
	return c.PostForm("message/send_private_msg", url.Values{
		"friend_id": {fmt.Sprint(friendID)},
		"content":   {content},
	}, &out)
}

func (c *UniCsACClient) MarkRead(conv Conversation, lastMsgID int) error {
	values := url.Values{}
	if conv.Type == ConversationGroup {
		values.Set("room_id", fmt.Sprint(conv.ID))
	} else {
		values.Set("friend_id", fmt.Sprint(conv.ID))
	}
	if lastMsgID > 0 {
		values.Set("last_msg_id", fmt.Sprint(lastMsgID))
	}
	var out APIResponse
	return c.PostForm("message/mark_read", values, &out)
}

func (c *UniCsACClient) UploadImage(path string) (string, error) {
	var out APIResponse
	if err := c.PostMultipart("utils/upload_image", "image", path, nil, &out); err != nil {
		return "", err
	}
	return extractURL(out), nil
}

func (c *UniCsACClient) UploadVoice(path string) (string, error) {
	var out APIResponse
	if err := c.PostMultipart("utils/upload_voice", "voice", path, nil, &out); err != nil {
		return "", err
	}
	return extractURL(out), nil
}

func (c *UniCsACClient) Get(route string, values url.Values, out *APIResponse) error {
	reqURL, err := c.routeURL(route, values)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodGet, reqURL, nil)
	if err != nil {
		return err
	}
	c.prepareHeaders(req)
	return c.do(req, out)
}

func (c *UniCsACClient) PostForm(route string, values url.Values, out *APIResponse) error {
	reqURL, err := c.routeURL(route, nil)
	if err != nil {
		return err
	}
	if values == nil {
		values = url.Values{}
	}
	req, err := http.NewRequest(http.MethodPost, reqURL, strings.NewReader(values.Encode()))
	if err != nil {
		return err
	}
	c.prepareHeaders(req)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	return c.do(req, out)
}

func (c *UniCsACClient) PostJSON(route string, payload any, out *APIResponse) error {
	reqURL, err := c.routeURL(route, nil)
	if err != nil {
		return err
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPost, reqURL, bytes.NewReader(body))
	if err != nil {
		return err
	}
	c.prepareHeaders(req)
	req.Header.Set("Content-Type", "application/json")
	return c.do(req, out)
}

func (c *UniCsACClient) PostMultipart(route, fileField, filePath string, values map[string]string, out *APIResponse) error {
	file, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	for key, value := range values {
		if err := writer.WriteField(key, value); err != nil {
			return err
		}
	}
	part, err := writer.CreateFormFile(fileField, filepath.Base(filePath))
	if err != nil {
		return err
	}
	if _, err := io.Copy(part, file); err != nil {
		return err
	}
	if err := writer.Close(); err != nil {
		return err
	}

	reqURL, err := c.routeURL(route, nil)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPost, reqURL, &body)
	if err != nil {
		return err
	}
	c.prepareHeaders(req)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	return c.do(req, out)
}

func (c *UniCsACClient) routeURL(route string, values url.Values) (string, error) {
	u, err := url.Parse(c.baseURL)
	if err != nil {
		return "", err
	}
	q := u.Query()
	q.Set("route", route)
	for key, vals := range values {
		for _, value := range vals {
			q.Add(key, value)
		}
	}
	u.RawQuery = q.Encode()
	return u.String(), nil
}

func (c *UniCsACClient) do(req *http.Request, out *APIResponse) error {
	c.prepareHeaders(req)

	resp, body, err := c.doOnce(req)
	if err != nil {
		return err
	}
	if isChallengePage(body) {
		retryURL, err := c.solveChallenge(req.URL, body)
		if err != nil {
			return err
		}
		retry, err := cloneRequest(req)
		if err != nil {
			return err
		}
		retry.URL = retryURL
		c.prepareHeaders(retry)

		resp, body, err = c.doOnce(retry)
		if err != nil {
			return err
		}
		if isChallengePage(body) {
			return errors.New("server returned the JavaScript challenge again after setting __test cookie")
		}
	}

	if resp.StatusCode == http.StatusUnauthorized {
		if json.Unmarshal(body, out) == nil {
			_ = json.Unmarshal(body, &out.Raw)
		}
		return errors.New(defaultMessage(out, "not logged in"))
	}
	if resp.StatusCode == http.StatusForbidden {
		if json.Unmarshal(body, out) == nil {
			_ = json.Unmarshal(body, &out.Raw)
		}
		return errors.New(defaultMessage(out, "access forbidden: "+compactText(string(body), 180)))
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		if json.Unmarshal(body, out) == nil {
			_ = json.Unmarshal(body, &out.Raw)
		}
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, defaultMessage(out, compactText(string(body), 180)))
	}

	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("decode response failed: %w; body: %s", err, compactText(string(body), 300))
	}
	_ = json.Unmarshal(body, &out.Raw)

	if !out.Success {
		return errors.New(defaultMessage(out, "request failed"))
	}
	return nil
}

func (c *UniCsACClient) prepareHeaders(req *http.Request) {
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", browserUserAgent)
	}
	if req.Header.Get("Accept") == "" {
		req.Header.Set("Accept", "application/json, text/plain, */*")
	}
	if req.Header.Get("Accept-Language") == "" {
		req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	}
	if req.Header.Get("Referer") == "" {
		req.Header.Set("Referer", "https://cschat.ccccocccc.cc/")
	}
	if req.Method == http.MethodPost && req.Header.Get("Origin") == "" {
		req.Header.Set("Origin", "https://cschat.ccccocccc.cc")
	}
}

func (c *UniCsACClient) doOnce(req *http.Request) (*http.Response, []byte, error) {
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, nil, err
	}
	if len(bytes.TrimSpace(body)) == 0 {
		return resp, body, fmt.Errorf("empty response with HTTP %d", resp.StatusCode)
	}
	return resp, body, nil
}

func cloneRequest(req *http.Request) (*http.Request, error) {
	clone := req.Clone(req.Context())
	if req.Body != nil {
		if req.GetBody == nil {
			return nil, errors.New("request body cannot be replayed after JavaScript challenge")
		}
		body, err := req.GetBody()
		if err != nil {
			return nil, err
		}
		clone.Body = body
	}
	return clone, nil
}

func isChallengePage(body []byte) bool {
	return bytes.Contains(body, []byte(`document.cookie="__test=`)) &&
		bytes.Contains(body, []byte(`/aes.js`)) &&
		bytes.Contains(body, []byte(`slowAES.decrypt`))
}

func (c *UniCsACClient) solveChallenge(requestURL *url.URL, body []byte) (*url.URL, error) {
	matches := challengeVarsRE.FindSubmatch(body)
	if len(matches) != 4 {
		return nil, errors.New("server returned JavaScript challenge but challenge variables were not found")
	}

	key, err := hex.DecodeString(string(matches[1]))
	if err != nil {
		return nil, err
	}
	iv, err := hex.DecodeString(string(matches[2]))
	if err != nil {
		return nil, err
	}
	ciphertext, err := hex.DecodeString(string(matches[3]))
	if err != nil {
		return nil, err
	}
	if len(iv) != aes.BlockSize {
		return nil, fmt.Errorf("invalid challenge IV length: %d", len(iv))
	}
	if len(ciphertext) == 0 || len(ciphertext)%aes.BlockSize != 0 {
		return nil, fmt.Errorf("invalid challenge ciphertext length: %d", len(ciphertext))
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	plaintext := make([]byte, len(ciphertext))
	cipher.NewCBCDecrypter(block, iv).CryptBlocks(plaintext, ciphertext)

	cookieURL := &url.URL{Scheme: requestURL.Scheme, Host: requestURL.Host, Path: "/"}
	c.http.Jar.SetCookies(cookieURL, []*http.Cookie{
		{Name: "__test", Value: hex.EncodeToString(plaintext), Path: "/"},
	})

	retryURL := *requestURL
	if locMatches := challengeLocRE.FindSubmatch(body); len(locMatches) == 2 {
		if loc, err := url.Parse(string(locMatches[1])); err == nil {
			resolved := requestURL.ResolveReference(loc)
			if resolved.Scheme == requestURL.Scheme && resolved.Host == requestURL.Host {
				retryURL = *resolved
			}
		}
	}
	query := retryURL.Query()
	if query.Get("i") == "" {
		query.Set("i", "1")
		retryURL.RawQuery = query.Encode()
	}
	return &retryURL, nil
}

func defaultMessage(out *APIResponse, fallback string) string {
	if strings.TrimSpace(out.Message) != "" {
		return out.Message
	}
	return fallback
}

func decodeMessages(out APIResponse) []Message {
	if len(out.Messages) > 0 {
		return out.Messages
	}
	for _, key := range []string{"msg", "message_list", "list", "data"} {
		raw, ok := out.Raw[key]
		if !ok {
			continue
		}
		var messages []Message
		if json.Unmarshal(raw, &messages) == nil {
			return messages
		}
		var wrapped struct {
			Messages []Message `json:"messages"`
			List     []Message `json:"list"`
		}
		if json.Unmarshal(raw, &wrapped) == nil {
			if len(wrapped.Messages) > 0 {
				return wrapped.Messages
			}
			if len(wrapped.List) > 0 {
				return wrapped.List
			}
		}
	}
	return nil
}

func extractURL(out APIResponse) string {
	for _, key := range []string{"url", "path", "src"} {
		raw, ok := out.Raw[key]
		if !ok {
			continue
		}
		var value string
		if json.Unmarshal(raw, &value) == nil {
			return value
		}
	}
	return ""
}
