package main

import (
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

func parseUIDList(raw string) []int {
	parts := strings.Split(raw, ",")
	uids := make([]int, 0, len(parts))
	seen := make(map[int]struct{}, len(parts))
	for _, part := range parts {
		id, err := strconv.Atoi(strings.TrimSpace(part))
		if err != nil || id <= 0 {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		uids = append(uids, id)
	}
	return uids
}

func (a *App) showSearch() {
	query := tview.NewInputField().SetLabel(translate(a.lang, "form.search") + ": ").SetFieldWidth(40)
	form := tview.NewForm()
	form.AddFormItem(query)
	form.AddButton(translate(a.lang, "ui.search"), func() {
		q := strings.TrimSpace(query.GetText())
		if q == "" {
			a.setStatus(translate(a.lang, "status.search_query_required"))
			return
		}
		a.closeModal()
		a.performSearch(q)
	})
	form.AddButton(translate(a.lang, "ui.cancel"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.search") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 70, 10)
}

func (a *App) performSearch(query string) {
	a.showMain(translate(a.lang, "menu.search"), a.textPanel(translate(a.lang, "menu.search"), translate(a.lang, "loading.searching")), nil, translate(a.lang, "loading.searching"))
	go func() {
		results, err := a.searchAll(query)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.search_failed"), err)
				return
			}
			a.showSearchResults(query, results)
		})
	}()
}

func (a *App) searchAll(query string) ([]SearchResult, error) {
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return nil, nil
	}
	results := make([]SearchResult, 0, 64)
	seen := make(map[string]struct{})
	addConv := func(conv Conversation, snippet string) {
		if conv.ID <= 0 {
			return
		}
		key := fmt.Sprintf("%s:%d", conv.Type, conv.ID)
		if _, ok := seen[key]; ok {
			return
		}
		seen[key] = struct{}{}
		results = append(results, SearchResult{Kind: SearchResultConversation, Conversation: conv, Snippet: snippet})
	}
	if a.cache != nil {
		if cached, err := a.cache.Search(query, 80); err == nil {
			for _, item := range cached {
				key := fmt.Sprintf("%s:%d", item.Conversation.Type, item.Conversation.ID)
				if item.Kind == SearchResultMessage {
					key = fmt.Sprintf("%s:%d:%d", item.Conversation.Type, item.Conversation.ID, item.Message.MessageID())
				}
				if _, ok := seen[key]; ok {
					continue
				}
				seen[key] = struct{}{}
				results = append(results, item)
			}
		}
	}
	conversations, err := a.conversations()
	if err != nil {
		return results, nil
	}
	for _, conv := range conversations {
		name := strings.ToLower(conv.Name)
		subtitle := strings.ToLower(conv.Subtitle)
		if strings.Contains(name, q) || strings.Contains(subtitle, q) {
			addConv(conv, conv.Subtitle)
		}
	}
	sort.SliceStable(results, func(i, j int) bool {
		if results[i].Kind != results[j].Kind {
			return results[i].Kind < results[j].Kind
		}
		return results[i].Conversation.Name < results[j].Conversation.Name
	})
	return results, nil
}

func (a *App) showSearchResults(query string, results []SearchResult) {
	list := tview.NewList()
	list.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.search") + " ")
	list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyEsc:
			a.showHome("")
			return nil
		case tcell.KeyF5:
			a.performSearch(query)
			return nil
		}
		return event
	})
	if len(results) == 0 {
		list.AddItem(translate(a.lang, "list.no_search_results"), translate(a.lang, "list.search_empty_hint"), 0, nil)
	} else {
		for _, result := range results {
			result := result
			switch result.Kind {
			case SearchResultConversation:
				label := fmt.Sprintf("[%s] %s", a.conversationTypeLabel(result.Conversation.Type), result.Conversation.Name)
				list.AddItem(label, result.Snippet, 0, func() {
					a.openChat(result.Conversation)
				})
			case SearchResultMessage:
				label := fmt.Sprintf("%s #%d", result.Conversation.Name, result.Message.MessageID())
				list.AddItem(label, compactText(result.Snippet, 70), 0, func() {
					a.openChat(result.Conversation)
					a.setStatus(translate(a.lang, "status.search_message_hit", result.Message.MessageID()))
				})
			}
		}
	}
	a.showMain(translate(a.lang, "menu.search"), list, list, translate(a.lang, "status.search_done", len(results)))
}

func (a *App) showChatSearch(session *ChatSession) {
	if session == nil {
		return
	}
	query := tview.NewInputField().SetLabel(translate(a.lang, "form.search") + ": ").SetFieldWidth(40)
	form := tview.NewForm()
	form.AddFormItem(query)
	form.AddButton(translate(a.lang, "ui.search"), func() {
		q := strings.TrimSpace(query.GetText())
		if q == "" {
			a.setStatus(translate(a.lang, "status.search_query_required"))
			return
		}
		a.closeModal()
		a.searchChatMessages(session, q)
	})
	form.AddButton(translate(a.lang, "ui.cancel"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "chat.search_title") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 70, 10)
}

func (a *App) searchChatMessages(session *ChatSession, query string) {
	if session == nil {
		return
	}
	a.setStatus(translate(a.lang, "loading.searching"))
	go func() {
		messages := make([]Message, 0, 64)
		seen := make(map[int]struct{})
		add := func(msg Message) {
			id := msg.MessageID()
			if id == 0 {
				return
			}
			if _, ok := seen[id]; ok {
				return
			}
			seen[id] = struct{}{}
			messages = append(messages, msg)
		}
		for _, msg := range session.Messages {
			hay := strings.ToLower(msg.SearchText())
			if strings.Contains(hay, strings.ToLower(query)) {
				add(msg)
			}
		}
		if a.cache != nil {
			if cached, err := a.cache.SearchMessages(session.Conv, query, 80); err == nil {
				for _, msg := range cached {
					add(msg)
				}
			}
		}
		sort.SliceStable(messages, func(i, j int) bool {
			return messages[i].MessageID() < messages[j].MessageID()
		})
		a.ui.QueueUpdateDraw(func() {
			if !a.isActiveChat(session) {
				return
			}
			a.showChatMessageResults(session, query, messages)
		})
	}()
}

func (a *App) showChatMessageResults(session *ChatSession, query string, messages []Message) {
	list := tview.NewList()
	list.SetBorder(true).SetTitle(" " + translate(a.lang, "chat.search_title") + " ")
	list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyEsc:
			a.showChat(session, "")
			return nil
		case tcell.KeyF5:
			a.searchChatMessages(session, query)
			return nil
		}
		return event
	})
	if len(messages) == 0 {
		list.AddItem(translate(a.lang, "list.no_search_results"), translate(a.lang, "list.search_empty_hint"), 0, nil)
	} else {
		for _, msg := range messages {
			msg := msg
			label := fmt.Sprintf("#%d %s", msg.MessageID(), msg.Sender())
			list.AddItem(label, compactText(msg.Body(), 90), 0, func() {
				a.showMessageActions(session, msg)
			})
		}
	}
	a.showMain(translate(a.lang, "chat.search_title"), list, list, translate(a.lang, "status.search_done", len(messages)))
}

func (a *App) showMessageActions(session *ChatSession, msg Message) {
	form := tview.NewForm()
	details := tview.NewTextView()
	details.SetDynamicColors(true)
	details.SetWrap(true)
	details.SetText(fmt.Sprintf(
		"[::b]ID[::-] %d\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %d",
		msg.MessageID(),
		translate(a.lang, "field.sender"),
		tview.Escape(msg.Sender()),
		translate(a.lang, "field.time"),
		tview.Escape(msg.Timestamp()),
		translate(a.lang, "field.message"),
		tview.Escape(msg.Body()),
		translate(a.lang, "field.reply_to"),
		msg.ReplyTo,
	))
	form.AddFormItem(details)
	form.AddButton(translate(a.lang, "ui.reply"), func() {
		session.ReplyTo = msg.MessageID()
		a.closeModal()
		a.setStatus(translate(a.lang, "status.reply_target_set", msg.MessageID()))
		a.showChat(session, "")
	})
	form.AddButton(translate(a.lang, "ui.recall"), func() {
		a.closeModal()
		a.recallMessage(session.Conv, msg.MessageID())
	})
	if session.Conv.Type == ConversationGroup {
		form.AddButton(translate(a.lang, "ui.essence"), func() {
			a.closeModal()
			a.toggleEssence(session.Conv, msg.MessageID())
		})
	}
	if img := msg.ImageLink(); img != "" {
		form.AddButton(translate(a.lang, "ui.open"), func() {
			_ = openExternalURL(img)
		})
	}
	form.AddButton(translate(a.lang, "ui.copy"), func() {
		text := fmt.Sprintf("#%d %s\n%s\n%s", msg.MessageID(), msg.Sender(), msg.Timestamp(), msg.Body())
		if err := copyToClipboard(text); err != nil {
			a.setStatus(translate(a.lang, "error.copy_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.copied_message"))
	})
	form.AddButton(translate(a.lang, "ui.back"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.message_actions") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 92, 18)
}

func (a *App) showConversationInfo(conv Conversation) {
	if conv.Type == ConversationGroup {
		a.setStatus(translate(a.lang, "loading.conversation_info"))
		go func() {
			group, err := a.client.GroupViewInfo(conv.ID)
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError(translate(a.lang, "error.load_group_info_failed"), err)
					return
				}
				a.showGroupInfo(conv, group)
			})
		}()
		return
	}
	uid := conv.PeerUID
	if uid == 0 {
		uid = conv.ID
	}
	a.setStatus(translate(a.lang, "loading.conversation_info"))
	go func() {
		user, err := a.client.UserInfo(uid)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.load_user_info_failed"), err)
				return
			}
			a.showUserInfo(conv, user)
		})
	}()
}

func (a *App) showUserInfo(conv Conversation, user *User) {
	form := tview.NewForm()
	text := tview.NewTextView()
	text.SetDynamicColors(true)
	text.SetWrap(true)
	text.SetText(fmt.Sprintf(
		"[::b]%s[::-] %d\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s",
		translate(a.lang, "field.uid"), user.UID,
		translate(a.lang, "field.username"), tview.Escape(user.Username),
		translate(a.lang, "field.nickname"), tview.Escape(user.Nickname),
		translate(a.lang, "field.status"), tview.Escape(user.OnlineStatus),
		translate(a.lang, "field.avatar"), tview.Escape(user.Avatar),
		translate(a.lang, "field.signature"), tview.Escape(user.Signature),
	))
	form.AddFormItem(text)
	form.AddButton(translate(a.lang, "ui.chat"), func() {
		a.closeModal()
		a.openChat(conv)
	})
	form.AddButton(translate(a.lang, "ui.copy"), func() {
		body := fmt.Sprintf("UID: %d\nUsername: %s\nNickname: %s\nStatus: %s\nAvatar: %s\nSignature: %s", user.UID, user.Username, user.Nickname, user.OnlineStatus, user.Avatar, user.Signature)
		if err := copyToClipboard(body); err != nil {
			a.setStatus(translate(a.lang, "error.copy_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.copied_user_info"))
	})
	form.AddButton(translate(a.lang, "ui.back"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.user_info") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 94, 18)
}

func (a *App) showGroupInfo(conv Conversation, group *Group) {
	form := tview.NewForm()
	text := tview.NewTextView()
	text.SetDynamicColors(true)
	text.SetWrap(true)
	text.SetText(fmt.Sprintf(
		"[::b]%s[::-] %d\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %d\n[::b]%s[::-] %t\n[::b]%s[::-] %t\n[::b]%s[::-] %t\n[::b]%s[::-] %s",
		translate(a.lang, "field.room_id"), group.Room(),
		translate(a.lang, "field.room_name"), tview.Escape(group.DisplayName()),
		translate(a.lang, "field.description"), tview.Escape(group.Description),
		translate(a.lang, "field.notice"), tview.Escape(group.Notice),
		translate(a.lang, "field.member_count"), group.MemberCount,
		translate(a.lang, "field.in_group"), group.IsInGroup,
		translate(a.lang, "field.admin"), group.IsAdmin,
		translate(a.lang, "field.owner"), group.IsOwner,
		translate(a.lang, "field.invite_code"), tview.Escape(group.InviteCode),
	))
	form.AddFormItem(text)
	form.AddButton(translate(a.lang, "ui.chat"), func() {
		a.closeModal()
		a.openChat(conv)
	})
	form.AddButton(translate(a.lang, "ui.members"), func() {
		a.closeModal()
		a.showGroupMembers(conv)
	})
	form.AddButton(translate(a.lang, "ui.essence"), func() {
		a.closeModal()
		a.showEssenceMessages(conv)
	})
	form.AddButton(translate(a.lang, "ui.copy"), func() {
		body := fmt.Sprintf("Room ID: %d\nName: %s\nDescription: %s\nNotice: %s\nMembers: %d", group.Room(), group.DisplayName(), group.Description, group.Notice, group.MemberCount)
		if err := copyToClipboard(body); err != nil {
			a.setStatus(translate(a.lang, "error.copy_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.copied_group_info"))
	})
	form.AddButton(translate(a.lang, "ui.back"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.group_info") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 96, 20)
}

func (a *App) showGroupMembers(conv Conversation) {
	if conv.Type != ConversationGroup {
		a.setStatus(translate(a.lang, "status.group_members_only"))
		return
	}
	a.showMain(translate(a.lang, "ui.members"), a.textPanel(translate(a.lang, "ui.members"), translate(a.lang, "loading.members")), nil, translate(a.lang, "loading.members"))
	go func() {
		members, err := a.client.GroupMembers(conv.ID)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.load_group_members_failed"), err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.members") + " ")
			list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
				switch event.Key() {
				case tcell.KeyEsc:
					a.openChat(conv)
					return nil
				case tcell.KeyF5:
					a.showGroupMembers(conv)
					return nil
				}
				return event
			})
			if len(members) == 0 {
				list.AddItem(translate(a.lang, "list.no_members"), "", 0, nil)
			}
			for _, member := range members {
				member := member
				label := member.DisplayName()
				if role := member.RoleLabel(); role != "" {
					label += " [" + role + "]"
				}
				if status := strings.TrimSpace(member.OnlineStatus); status != "" {
					label += " - " + status
				}
				list.AddItem(label, member.Subtitle(), 0, func() {
					a.showMemberActions(conv, member)
				})
			}
			a.showMain(translate(a.lang, "ui.members"), list, list, translate(a.lang, "status.members_loaded", len(members)))
		})
	}()
}

func (a *App) showMemberActions(conv Conversation, member GroupMember) {
	form := tview.NewForm()
	text := tview.NewTextView()
	text.SetDynamicColors(true)
	text.SetWrap(true)
	text.SetText(fmt.Sprintf(
		"[::b]%s[::-] %d\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s",
		translate(a.lang, "field.uid"), member.ID(),
		translate(a.lang, "field.nickname"), tview.Escape(member.DisplayName()),
		translate(a.lang, "field.role"), tview.Escape(member.RoleLabel()),
		translate(a.lang, "field.status"), tview.Escape(member.OnlineStatus),
	))
	form.AddFormItem(text)
	form.AddButton(translate(a.lang, "ui.mention"), func() {
		a.chatMu.Lock()
		session := a.activeChat
		a.chatMu.Unlock()
		if session == nil || session.Conv.Type != ConversationGroup || session.Conv.ID != conv.ID {
			a.setStatus(translate(a.lang, "status.open_group_first"))
			return
		}
		session.Mentions = append(session.Mentions, member.ID())
		a.setStatus(translate(a.lang, "status.member_added_to_mentions", member.DisplayName()))
		a.closeModal()
		a.showChat(session, "")
	})
	form.AddButton(translate(a.lang, "ui.chat"), func() {
		a.closeModal()
		a.openChat(conv)
	})
	form.AddButton(translate(a.lang, "ui.copy"), func() {
		body := fmt.Sprintf("UID: %d\nName: %s\nRole: %s\nStatus: %s", member.ID(), member.DisplayName(), member.RoleLabel(), member.OnlineStatus)
		if err := copyToClipboard(body); err != nil {
			a.setStatus(translate(a.lang, "error.copy_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.copied_member_info"))
	})
	form.AddButton(translate(a.lang, "ui.back"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.member") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 92, 18)
}

func (a *App) showEssenceMessages(conv Conversation) {
	if conv.Type != ConversationGroup {
		a.setStatus(translate(a.lang, "status.essence_group_only"))
		return
	}
	a.showMain(translate(a.lang, "ui.essence"), a.textPanel(translate(a.lang, "ui.essence"), translate(a.lang, "loading.essence")), nil, translate(a.lang, "loading.essence"))
	go func() {
		messages, err := a.client.EssenceMessages(conv.ID)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.load_essence_failed"), err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.essence") + " ")
			list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
				switch event.Key() {
				case tcell.KeyEsc:
					a.openChat(conv)
					return nil
				case tcell.KeyF5:
					a.showEssenceMessages(conv)
					return nil
				}
				return event
			})
			if len(messages) == 0 {
				list.AddItem(translate(a.lang, "list.no_essence"), "", 0, nil)
			}
			for _, msg := range messages {
				msg := msg
				list.AddItem(fmt.Sprintf("#%d %s", msg.MessageID(), msg.Sender()), compactText(msg.Body(), 80), 0, func() {
					a.showMessageActions(&ChatSession{Conv: conv, Stop: make(chan struct{})}, msg)
				})
			}
			a.showMain(translate(a.lang, "ui.essence"), list, list, translate(a.lang, "status.essence_loaded", len(messages)))
		})
	}()
}

func (a *App) showJoinGroupEntryForm() {
	roomID := tview.NewInputField().SetLabel(translate(a.lang, "field.room_id") + ": ").SetFieldWidth(18)
	code := tview.NewInputField().SetLabel(translate(a.lang, "form.invite_code") + ": ").SetFieldWidth(28)
	answer := tview.NewInputField().SetLabel(translate(a.lang, "form.answer") + ": ").SetFieldWidth(36)
	form := tview.NewForm()
	form.AddFormItem(roomID)
	form.AddFormItem(code)
	form.AddFormItem(answer)
	form.AddButton(translate(a.lang, "ui.join_apply"), func() {
		id, err := strconv.Atoi(strings.TrimSpace(roomID.GetText()))
		if err != nil || id <= 0 {
			a.setStatus(translate(a.lang, "status.invalid_room_id"))
			return
		}
		a.closeModal()
		a.setStatus(translate(a.lang, "action.send_group_request"))
		go func() {
			err := a.client.ApplyJoinGroup(id, strings.TrimSpace(code.GetText()), strings.TrimSpace(answer.GetText()))
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError(translate(a.lang, "error.join_apply_failed"), err)
					return
				}
				a.setStatus(translate(a.lang, "status.join_apply_sent"))
			})
		}()
	})
	form.AddButton(translate(a.lang, "ui.cancel"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.join_group") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 72, 12)
}

func (a *App) sendChatImageMessage(session *ChatSession, path, caption string) {
	if session == nil {
		return
	}
	path = strings.TrimSpace(path)
	if path == "" {
		a.setStatus(translate(a.lang, "status.image_path_required"))
		return
	}
	if _, err := os.Stat(path); err != nil {
		a.setStatus(translate(a.lang, "error.image_path_invalid") + ": " + err.Error())
		return
	}
	a.setStatus(translate(a.lang, "action.sending_message"))
	replyTo := session.ReplyTo
	mentions := append([]int(nil), session.Mentions...)
	go func() {
		err := a.sendMessage(session.Conv, SendMessageOptions{
			Content:     caption,
			ImagePath:   path,
			ReplyTo:     replyTo,
			MentionUIDs: mentions,
		})
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.send_failed"), err)
				return
			}
			a.setStatus(translate(a.lang, "action.message_sent"))
			session.ReplyTo = 0
			session.Mentions = nil
			a.refreshChat(session, true)
		})
	}()
}

func (a *App) recallMessage(conv Conversation, msgID int) {
	if msgID <= 0 {
		a.setStatus(translate(a.lang, "status.invalid_message_id"))
		return
	}
	a.setStatus(translate(a.lang, "action.recalling_message"))
	go func() {
		err := a.client.RecallMessage(conv, msgID)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.recall_failed"), err)
				return
			}
			a.setStatus(translate(a.lang, "status.message_recalled", msgID))
			a.chatMu.Lock()
			session := a.activeChat
			a.chatMu.Unlock()
			if session != nil && session.Conv.Type == conv.Type && session.Conv.ID == conv.ID {
				a.refreshChat(session, true)
			}
		})
	}()
}

func (a *App) toggleEssence(conv Conversation, msgID int) {
	if conv.Type != ConversationGroup {
		a.setStatus(translate(a.lang, "status.essence_group_only"))
		return
	}
	a.setStatus(translate(a.lang, "action.toggling_essence"))
	go func() {
		err := a.client.ToggleEssence(conv.ID, msgID)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.toggle_essence_failed"), err)
				return
			}
			a.setStatus(translate(a.lang, "status.essence_toggled", msgID))
			a.chatMu.Lock()
			session := a.activeChat
			a.chatMu.Unlock()
			if session != nil && session.Conv.Type == conv.Type && session.Conv.ID == conv.ID {
				a.refreshChat(session, true)
			}
		})
	}()
}

func (a *App) showImageAction(link string) {
	form := tview.NewForm()
	text := tview.NewTextView()
	text.SetDynamicColors(true)
	text.SetWrap(true)
	text.SetText(tview.Escape(link))
	form.AddFormItem(text)
	form.AddButton(translate(a.lang, "ui.copy"), func() {
		if err := copyToClipboard(link); err != nil {
			a.setStatus(translate(a.lang, "error.copy_image_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.copied_image_link"))
	})
	form.AddButton(translate(a.lang, "ui.download"), func() {
		a.setStatus(translate(a.lang, "action.downloading_image"))
		go func() {
			dest, err := a.downloadImageLink(link)
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.setStatus(translate(a.lang, "error.download_image_failed") + ": " + err.Error())
					return
				}
				a.setStatus(translate(a.lang, "status.image_downloaded", dest))
			})
		}()
	})
	form.AddButton(translate(a.lang, "ui.open"), func() {
		if err := openExternalURL(link); err != nil {
			a.setStatus(translate(a.lang, "error.open_image_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.opened_image_link"))
	})
	form.AddButton(translate(a.lang, "ui.back"), func() {
		a.closeModal()
		a.chatMu.Lock()
		session := a.activeChat
		a.chatMu.Unlock()
		if session != nil {
			a.showImageLinks(session)
		}
	})
	form.AddButton(translate(a.lang, "ui.close"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.image_link") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 96, 11)
}

func (a *App) downloadImageLink(link string) (string, error) {
	base := link
	if base == "" {
		return "", fmt.Errorf("empty link")
	}
	name := sanitizeFileNameFromURL(base)
	dir := userDownloadDir()
	if dir == "" {
		var err error
		dir, err = os.UserCacheDir()
		if err != nil {
			return "", err
		}
	}
	targetDir := filepath.Join(dir, "CsAC-Terminal")
	if err := os.MkdirAll(targetDir, 0700); err != nil {
		return "", err
	}
	dest := filepath.Join(targetDir, name)
	if err := a.client.DownloadURL(link, dest); err != nil {
		return "", err
	}
	return dest, nil
}

func userDownloadDir() string {
	if profile := strings.TrimSpace(os.Getenv("USERPROFILE")); profile != "" {
		return filepath.Join(profile, "Downloads")
	}
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		return filepath.Join(home, "Downloads")
	}
	return ""
}

func sanitizeFileNameFromURL(raw string) string {
	parsed, err := url.Parse(raw)
	if err == nil && parsed.Path != "" {
		raw = parsed.Path
	}
	name := filepath.Base(raw)
	name = strings.TrimSpace(name)
	if name == "." || name == "/" || name == "" {
		return "image"
	}
	return name
}
