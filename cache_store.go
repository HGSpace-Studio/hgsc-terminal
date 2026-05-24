package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

type CacheStore struct {
	db   *sql.DB
	path string
}

type SearchResultKind string

const (
	SearchResultConversation SearchResultKind = "conversation"
	SearchResultMessage      SearchResultKind = "message"
)

type SearchResult struct {
	Kind         SearchResultKind
	Conversation Conversation
	Message      Message
	Snippet      string
}

func NewCacheStore() (*CacheStore, error) {
	dir, err := os.UserCacheDir()
	if err != nil {
		dir, err = os.UserConfigDir()
		if err != nil {
			return nil, err
		}
	}
	return OpenCacheStore(filepath.Join(dir, "CsAC-Terminal", "cache.db"))
}

func OpenCacheStore(path string) (*CacheStore, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	store := &CacheStore{db: db, path: path}
	if err := store.init(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return store, nil
}

func (s *CacheStore) init() error {
	for _, stmt := range []string{
		`CREATE TABLE IF NOT EXISTS conversations (
			conv_type TEXT NOT NULL,
			conv_id INTEGER NOT NULL,
			peer_uid INTEGER NOT NULL DEFAULT 0,
			name TEXT NOT NULL,
			subtitle TEXT NOT NULL,
			unread_count INTEGER NOT NULL DEFAULT 0,
			updated_at TEXT NOT NULL,
			PRIMARY KEY (conv_type, conv_id)
		)`,
		`CREATE TABLE IF NOT EXISTS messages (
			conv_type TEXT NOT NULL,
			conv_id INTEGER NOT NULL,
			msg_id INTEGER NOT NULL,
			sender_id INTEGER NOT NULL DEFAULT 0,
			sender TEXT NOT NULL,
			content TEXT NOT NULL,
			image_url TEXT NOT NULL,
			voice_url TEXT NOT NULL,
			timestamp TEXT NOT NULL,
			can_recall INTEGER NOT NULL DEFAULT 0,
			is_recalled INTEGER NOT NULL DEFAULT 0,
			is_essence INTEGER NOT NULL DEFAULT 0,
			is_mentioned INTEGER NOT NULL DEFAULT 0,
			reply_to INTEGER NOT NULL DEFAULT 0,
			raw_json TEXT NOT NULL,
			cached_at TEXT NOT NULL,
			PRIMARY KEY (conv_type, conv_id, msg_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_messages_search ON messages (content, sender)`,
		`CREATE INDEX IF NOT EXISTS idx_messages_conv_time ON messages (conv_type, conv_id, msg_id)`,
	} {
		if _, err := s.db.Exec(stmt); err != nil {
			return err
		}
	}
	if err := s.addColumnIfMissing("messages", "is_recalled", "INTEGER NOT NULL DEFAULT 0"); err != nil {
		return err
	}
	return nil
}

func (s *CacheStore) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

func (s *CacheStore) Path() string {
	if s == nil {
		return ""
	}
	return s.path
}

func (s *CacheStore) addColumnIfMissing(table, column, definition string) error {
	rows, err := s.db.Query("PRAGMA table_info(" + table + ")")
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var (
			cid        int
			name       string
			columnType string
			notNull    int
			defaultVal sql.NullString
			pk         int
		)
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultVal, &pk); err != nil {
			return err
		}
		if name == column {
			return rows.Err()
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	_, err = s.db.Exec("ALTER TABLE " + table + " ADD COLUMN " + column + " " + definition)
	return err
}

func (s *CacheStore) SaveConversation(conv Conversation) error {
	if s == nil || s.db == nil || conv.ID <= 0 {
		return nil
	}
	_, err := s.db.Exec(
		`INSERT INTO conversations (conv_type, conv_id, peer_uid, name, subtitle, unread_count, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(conv_type, conv_id) DO UPDATE SET
			peer_uid=excluded.peer_uid,
			name=excluded.name,
			subtitle=excluded.subtitle,
			unread_count=excluded.unread_count,
			updated_at=excluded.updated_at`,
		string(conv.Type), conv.ID, conv.PeerUID, conv.Name, conv.Subtitle, conv.UnreadCount, time.Now().Format(time.RFC3339),
	)
	return err
}

func (s *CacheStore) SaveConversations(conversations []Conversation) error {
	if s == nil || s.db == nil || len(conversations) == 0 {
		return nil
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	stmt, err := tx.Prepare(
		`INSERT INTO conversations (conv_type, conv_id, peer_uid, name, subtitle, unread_count, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(conv_type, conv_id) DO UPDATE SET
			peer_uid=excluded.peer_uid,
			name=excluded.name,
			subtitle=excluded.subtitle,
			unread_count=excluded.unread_count,
			updated_at=excluded.updated_at`,
	)
	if err != nil {
		_ = tx.Rollback()
		return err
	}
	defer stmt.Close()

	now := time.Now().Format(time.RFC3339)
	for _, conv := range conversations {
		if conv.ID <= 0 {
			continue
		}
		if _, err := stmt.Exec(string(conv.Type), conv.ID, conv.PeerUID, conv.Name, conv.Subtitle, conv.UnreadCount, now); err != nil {
			_ = tx.Rollback()
			return err
		}
	}
	return tx.Commit()
}

func (s *CacheStore) LoadConversations() ([]Conversation, error) {
	if s == nil || s.db == nil {
		return nil, nil
	}
	rows, err := s.db.Query(
		`SELECT conv_type, conv_id, peer_uid, name, subtitle, unread_count
		 FROM conversations
		 ORDER BY updated_at DESC, name COLLATE NOCASE ASC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var conversations []Conversation
	for rows.Next() {
		var conv Conversation
		var typ string
		if err := rows.Scan(&typ, &conv.ID, &conv.PeerUID, &conv.Name, &conv.Subtitle, &conv.UnreadCount); err != nil {
			return nil, err
		}
		conv.Type = ConversationType(typ)
		conversations = append(conversations, conv)
	}
	return conversations, rows.Err()
}

func (s *CacheStore) SaveMessages(conv Conversation, messages []Message) error {
	if s == nil || s.db == nil || conv.ID <= 0 || len(messages) == 0 {
		return nil
	}
	if err := s.SaveConversation(conv); err != nil {
		return err
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	stmt, err := tx.Prepare(
		`INSERT INTO messages
			(conv_type, conv_id, msg_id, sender_id, sender, content, image_url, voice_url, timestamp, can_recall, is_recalled, is_essence, is_mentioned, reply_to, raw_json, cached_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON CONFLICT(conv_type, conv_id, msg_id) DO UPDATE SET
			sender_id=excluded.sender_id,
			sender=excluded.sender,
			content=excluded.content,
			image_url=excluded.image_url,
			voice_url=excluded.voice_url,
			timestamp=excluded.timestamp,
			can_recall=excluded.can_recall,
			is_recalled=excluded.is_recalled,
			is_essence=excluded.is_essence,
			is_mentioned=excluded.is_mentioned,
			reply_to=excluded.reply_to,
			raw_json=excluded.raw_json,
			cached_at=excluded.cached_at`,
	)
	if err != nil {
		_ = tx.Rollback()
		return err
	}
	defer stmt.Close()

	now := time.Now().Format(time.RFC3339)
	for _, msg := range messages {
		msgID := msg.MessageID()
		if msgID <= 0 {
			continue
		}
		raw, err := json.Marshal(msg)
		if err != nil {
			_ = tx.Rollback()
			return err
		}
		if _, err := stmt.Exec(
			string(conv.Type), conv.ID, msgID, msg.SenderID(), msg.Sender(), msg.Body(), msg.ImageLink(), msg.VoiceLink(), msg.Timestamp(),
			boolToInt(msg.CanRecall.Bool()), boolToInt(msg.IsRecalled.Bool()), boolToInt(msg.IsEssence.Bool()), boolToInt(msg.IsMentioned.Bool()), msg.ReplyTo, string(raw), now,
		); err != nil {
			_ = tx.Rollback()
			return err
		}
	}
	return tx.Commit()
}

func (s *CacheStore) LoadMessages(conv Conversation, limit int) ([]Message, error) {
	if s == nil || s.db == nil || conv.ID <= 0 {
		return nil, nil
	}
	query := `SELECT raw_json, msg_id, sender_id, sender, content, image_url, voice_url, timestamp, can_recall, is_recalled, is_essence, is_mentioned, reply_to
		FROM messages
		WHERE conv_type = ? AND conv_id = ?
		ORDER BY msg_id DESC`
	args := []any{string(conv.Type), conv.ID}
	if limit > 0 {
		query += ` LIMIT ?`
		args = append(args, limit)
	}
	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []Message
	for rows.Next() {
		msg, err := scanCachedMessage(rows)
		if err != nil {
			return nil, err
		}
		messages = append(messages, msg)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	sort.SliceStable(messages, func(i, j int) bool {
		return messages[i].MessageID() < messages[j].MessageID()
	})
	return messages, nil
}

func (s *CacheStore) Search(query string, limit int) ([]SearchResult, error) {
	if s == nil || s.db == nil {
		return nil, nil
	}
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, nil
	}
	if limit <= 0 {
		limit = 80
	}
	like := "%" + query + "%"
	results := make([]SearchResult, 0, limit)

	convs, err := s.db.Query(
		`SELECT conv_type, conv_id, peer_uid, name, subtitle, unread_count
		 FROM conversations
		 WHERE name LIKE ? OR subtitle LIKE ?
		 ORDER BY updated_at DESC, name COLLATE NOCASE ASC
		 LIMIT ?`,
		like, like, limit,
	)
	if err != nil {
		return nil, err
	}
	for convs.Next() {
		var conv Conversation
		var typ string
		if err := convs.Scan(&typ, &conv.ID, &conv.PeerUID, &conv.Name, &conv.Subtitle, &conv.UnreadCount); err != nil {
			_ = convs.Close()
			return nil, err
		}
		conv.Type = ConversationType(typ)
		results = append(results, SearchResult{Kind: SearchResultConversation, Conversation: conv, Snippet: conv.Subtitle})
	}
	if err := convs.Close(); err != nil {
		return nil, err
	}
	if len(results) >= limit {
		return results, nil
	}

	rows, err := s.db.Query(
		`SELECT c.conv_type, c.conv_id, c.peer_uid, c.name, c.subtitle, c.unread_count,
				m.raw_json, m.msg_id, m.sender_id, m.sender, m.content, m.image_url, m.voice_url, m.timestamp,
				m.can_recall, m.is_recalled, m.is_essence, m.is_mentioned, m.reply_to
		 FROM messages m
		 LEFT JOIN conversations c ON c.conv_type = m.conv_type AND c.conv_id = m.conv_id
		 WHERE m.content LIKE ? OR m.sender LIKE ?
		 ORDER BY m.msg_id DESC
		 LIMIT ?`,
		like, like, limit-len(results),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var (
			conv                                    Conversation
			typ                                     sql.NullString
			id                                      sql.NullInt64
			peerUID                                 sql.NullInt64
			name                                    sql.NullString
			subtitle                                sql.NullString
			unread                                  sql.NullInt64
			rawJSON                                 string
			msgID, senderID, replyTo                int
			sender, content                         string
			imageURL, voiceURL                      string
			timestamp                               string
			canRecall, recalled, essence, mentioned int
		)
		if err := rows.Scan(&typ, &id, &peerUID, &name, &subtitle, &unread, &rawJSON, &msgID, &senderID, &sender, &content, &imageURL, &voiceURL, &timestamp, &canRecall, &recalled, &essence, &mentioned, &replyTo); err != nil {
			return nil, err
		}
		msg := assembleCachedMessage(rawJSON, msgID, senderID, sender, content, imageURL, voiceURL, timestamp, canRecall, recalled, essence, mentioned, replyTo)
		conv.Type = ConversationType(typ.String)
		if conv.Type == "" {
			conv.Type = ConversationFriend
		}
		conv.ID = int(id.Int64)
		conv.PeerUID = int(peerUID.Int64)
		conv.Name = name.String
		conv.Subtitle = subtitle.String
		conv.UnreadCount = int(unread.Int64)
		if conv.Name == "" {
			conv.Name = string(conv.Type) + " " + strings.TrimSpace(strings.TrimPrefix(msg.Sender(), "UID "))
		}
		results = append(results, SearchResult{Kind: SearchResultMessage, Conversation: conv, Message: msg, Snippet: msg.SearchText()})
	}
	return results, rows.Err()
}

func (s *CacheStore) SearchMessages(conv Conversation, query string, limit int) ([]Message, error) {
	if s == nil || s.db == nil || conv.ID <= 0 {
		return nil, nil
	}
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, nil
	}
	if limit <= 0 {
		limit = 80
	}
	rows, err := s.db.Query(
		`SELECT raw_json, msg_id, sender_id, sender, content, image_url, voice_url, timestamp, can_recall, is_recalled, is_essence, is_mentioned, reply_to
		 FROM messages
		 WHERE conv_type = ? AND conv_id = ? AND (content LIKE ? OR sender LIKE ?)
		 ORDER BY msg_id DESC
		 LIMIT ?`,
		string(conv.Type), conv.ID, "%"+query+"%", "%"+query+"%", limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var messages []Message
	for rows.Next() {
		msg, err := scanCachedMessage(rows)
		if err != nil {
			return nil, err
		}
		messages = append(messages, msg)
	}
	return messages, rows.Err()
}

type cachedMessageScanner interface {
	Scan(dest ...any) error
}

func scanCachedMessage(scanner cachedMessageScanner) (Message, error) {
	var (
		rawJSON                  string
		msgID, senderID, replyTo int
		sender, content          string
		imageURL, voiceURL       string
		timestamp                string
		canRecall, recalled      int
		essence                  int
		mentioned                int
	)
	if err := scanner.Scan(&rawJSON, &msgID, &senderID, &sender, &content, &imageURL, &voiceURL, &timestamp, &canRecall, &recalled, &essence, &mentioned, &replyTo); err != nil {
		return Message{}, err
	}
	return assembleCachedMessage(rawJSON, msgID, senderID, sender, content, imageURL, voiceURL, timestamp, canRecall, recalled, essence, mentioned, replyTo), nil
}

func assembleCachedMessage(rawJSON string, msgID, senderID int, sender, content, imageURL, voiceURL, timestamp string, canRecall, recalled, essence, mentioned, replyTo int) Message {
	var msg Message
	if strings.TrimSpace(rawJSON) != "" {
		_ = json.Unmarshal([]byte(rawJSON), &msg)
	}
	if msg.MessageID() == 0 {
		msg.ID = msgID
	}
	if msg.SenderID() == 0 {
		msg.UID = senderID
	}
	if strings.TrimSpace(msg.Nickname) == "" {
		msg.Nickname = sender
	}
	if strings.TrimSpace(msg.Content) == "" {
		msg.Content = content
	}
	if strings.TrimSpace(msg.ImageURL) == "" {
		msg.ImageURL = imageURL
	}
	if strings.TrimSpace(msg.VoiceURL) == "" {
		msg.VoiceURL = voiceURL
	}
	if msg.Timestamp() == "" {
		msg.AddTime = FlexibleString(timestamp)
	}
	msg.CanRecall = FlexibleBool(msg.CanRecall.Bool() || canRecall != 0)
	msg.IsRecalled = FlexibleBool(msg.IsRecalled.Bool() || recalled != 0)
	msg.IsEssence = FlexibleBool(msg.IsEssence.Bool() || essence != 0)
	msg.IsMentioned = FlexibleBool(msg.IsMentioned.Bool() || mentioned != 0)
	if msg.ReplyTo == 0 {
		msg.ReplyTo = replyTo
	}
	return msg
}

func boolToInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func cacheOrNil(cache *CacheStore, err error) *CacheStore {
	if err != nil {
		return nil
	}
	return cache
}

func cachedConversationsOrNil(cache *CacheStore) []Conversation {
	if cache == nil {
		return nil
	}
	conversations, err := cache.LoadConversations()
	if err != nil {
		return nil
	}
	return conversations
}

func isCacheUnavailable(err error) bool {
	return errors.Is(err, sql.ErrConnDone)
}
