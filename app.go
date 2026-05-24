package main

import (
	"fmt"
	"net/url"
	"os/exec"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

type App struct {
	client  *UniCsACClient
	session *SessionStore
	config  *ConfigStore
	ui      *tview.Application
	pages   *tview.Pages

	user       *User
	status     *tview.TextView
	statusText string
	lang       Language
	screen     string
	chatMu     sync.Mutex
	activeChat *ChatSession
}

type ChatSession struct {
	Conv       Conversation
	View       *tview.TextView
	Input      *tview.InputField
	Messages   []Message
	LastID     int
	Stop       chan struct{}
	ImageLinks []string
}

func NewApp(client *UniCsACClient) *App {
	session, err := NewSessionStore()
	config, cfg := loadAppConfig()
	return &App{
		client:  client,
		session: sessionOrNil(session, err),
		config:  config,
		lang:    cfg.Language,
		ui:      tview.NewApplication(),
		pages:   tview.NewPages(),
	}
}

func loadAppConfig() (*ConfigStore, AppConfig) {
	cfg := AppConfig{Language: LanguageEnglish}
	config, err := NewConfigStore()
	if err != nil {
		return nil, cfg
	}
	loaded, err := config.Load()
	if err == nil {
		cfg = loaded
	}
	return config, cfg
}

func sessionOrNil(session *SessionStore, err error) *SessionStore {
	if err != nil {
		return nil
	}
	return session
}

func (a *App) replacePage(name string, root tview.Primitive) {
	for _, page := range []string{"splash", "auth", "register", "main", "chat", "modal"} {
		if page != name {
			a.pages.RemovePage(page)
		}
	}
	a.pages.RemovePage(name)
	a.pages.AddPage(name, root, true, true)
	a.pages.ShowPage("bg")
	a.pages.ShowPage(name)
	if a.ui != nil {
		a.ui.ForceDraw()
	}
}

func (a *App) Run() error {
	a.ui.EnableMouse(true)
	a.ui.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyCtrlC {
			a.ui.Stop()
			return nil
		}
		return event
	})

	a.pages.AddPage("bg", tview.NewBox().SetBackgroundColor(tcell.ColorDefault), true, true)
	a.showSplash(translate(a.lang, "app.starting") + "...")
	a.trySavedSession()
	return a.ui.SetRoot(a.pages, true).Run()
}

func (a *App) showSplash(message string) {
	a.screen = "splash"
	a.statusText = message
	panel := tview.NewTextView()
	panel.SetDynamicColors(true)
	panel.SetTextAlign(tview.AlignCenter)
	panel.SetText("\n[::b]CsAC-Terminal[::-]\n\n" + tview.Escape(message))
	panel.SetBorder(true).SetTitle(" " + translate(a.lang, "app.starting") + " ")

	root := tview.NewFlex().SetDirection(tview.FlexRow)
	root.AddItem(nil, 0, 1, false)
	root.AddItem(centerPrimitive(panel, 64, 8), 8, 0, true)
	root.AddItem(nil, 0, 1, false)

	a.replacePage("splash", root)
}

func (a *App) trySavedSession() {
	go func() {
		if a.session == nil {
			a.ui.QueueUpdateDraw(func() {
				a.showAuth(translate(a.lang, "status.session_storage_unavailable"))
			})
			return
		}
		loaded, err := a.session.Load(a.client)
		if err != nil {
			_ = a.session.Clear()
			a.ui.QueueUpdateDraw(func() {
				a.showAuth(translate(a.lang, "status.saved_session_could_not_be_loaded"))
			})
			return
		}
		if !loaded {
			a.ui.QueueUpdateDraw(func() {
				a.showAuth("")
			})
			return
		}
		user, err := a.client.CurrentUser()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				_ = a.session.Clear()
				a.showAuth(translate(a.lang, "status.session_expired"))
				return
			}
			a.user = user
			a.showHome(translate(a.lang, "status.session_restored"))
		})
	}()
}

func (a *App) showAuth(message string) {
	a.stopActiveChat()
	a.screen = "auth"
	if message != "" {
		a.statusText = message
	}

	username := tview.NewInputField().SetLabel(translate(a.lang, "auth.username") + ": ").SetFieldWidth(32)
	password := tview.NewInputField().SetLabel(translate(a.lang, "auth.password") + ": ").SetMaskCharacter('*').SetFieldWidth(32)

	form := tview.NewForm()
	form.AddFormItem(username)
	form.AddFormItem(password)
	form.AddButton(translate(a.lang, "auth.login"), func() {
		a.login(strings.TrimSpace(username.GetText()), password.GetText())
	})
	form.AddButton(translate(a.lang, "auth.register"), func() {
		a.showRegister("")
	})
	form.AddButton(translate(a.lang, "auth.language"), func() {
		a.showLanguagePicker()
	})
	form.AddButton(translate(a.lang, "auth.quit"), func() {
		a.ui.Stop()
	})
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "auth.login_title") + " ").SetTitleAlign(tview.AlignLeft)

	footer := a.newStatusBar()
	root := tview.NewFlex().SetDirection(tview.FlexRow)
	root.AddItem(nil, 0, 1, false)
	root.AddItem(centerPrimitive(form, 62, 12), 12, 0, true)
	root.AddItem(footer, 1, 0, false)

	a.replacePage("auth", root)
	a.ui.SetFocus(form)
}

func (a *App) showRegister(message string) {
	a.stopActiveChat()
	a.screen = "register"
	if message != "" {
		a.statusText = message
	}

	username := tview.NewInputField().SetLabel(translate(a.lang, "auth.username") + ": ").SetFieldWidth(32)
	nickname := tview.NewInputField().SetLabel(translate(a.lang, "auth.nickname") + ": ").SetFieldWidth(32)
	password := tview.NewInputField().SetLabel(translate(a.lang, "auth.password") + ": ").SetMaskCharacter('*').SetFieldWidth(32)
	confirm := tview.NewInputField().SetLabel(translate(a.lang, "auth.confirm") + ":  ").SetMaskCharacter('*').SetFieldWidth(32)

	form := tview.NewForm()
	form.AddFormItem(username)
	form.AddFormItem(nickname)
	form.AddFormItem(password)
	form.AddFormItem(confirm)
	form.AddButton(translate(a.lang, "auth.register"), func() {
		if password.GetText() != confirm.GetText() {
			a.setStatus(translate(a.lang, "status.passwords_mismatch"))
			return
		}
		a.register(strings.TrimSpace(username.GetText()), strings.TrimSpace(nickname.GetText()), password.GetText())
	})
	form.AddButton(translate(a.lang, "auth.back"), func() {
		a.showAuth("")
	})
	form.AddButton(translate(a.lang, "auth.language"), func() {
		a.showLanguagePicker()
	})
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "auth.create_account_title") + " ").SetTitleAlign(tview.AlignLeft)

	footer := a.newStatusBar()
	root := tview.NewFlex().SetDirection(tview.FlexRow)
	root.AddItem(nil, 0, 1, false)
	root.AddItem(centerPrimitive(form, 62, 15), 15, 0, true)
	root.AddItem(footer, 1, 0, false)

	a.replacePage("register", root)
	a.ui.SetFocus(form)
}

func (a *App) login(username, password string) {
	if username == "" || password == "" {
		a.setStatus(translate(a.lang, "status.auth_required", translate(a.lang, "auth.username"), translate(a.lang, "auth.password")))
		return
	}
	a.setStatus(translate(a.lang, "action.logging_in"))
	go func() {
		user, err := a.client.Login(username, password)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.login_failed"), err)
				return
			}
			a.user = user
			if err := a.saveSession(); err != nil {
				a.setStatus(translate(a.lang, "status.logged_in") + " " + err.Error())
			}
			a.showHome(translate(a.lang, "status.logged_in"))
		})
	}()
}

func (a *App) register(username, nickname, password string) {
	if username == "" || nickname == "" || password == "" {
		a.setStatus(translate(a.lang, "status.auth_register_required", translate(a.lang, "auth.username"), translate(a.lang, "auth.nickname"), translate(a.lang, "auth.password")))
		return
	}
	a.setStatus(translate(a.lang, "action.creating_account"))
	go func() {
		user, err := a.client.Register(username, nickname, password)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.register_failed"), err)
				return
			}
			a.user = user
			if err := a.saveSession(); err != nil {
				a.setStatus(translate(a.lang, "status.account_created") + " " + err.Error())
			}
			a.showHome(translate(a.lang, "status.account_created"))
		})
	}()
}

func (a *App) showHome(message string) {
	a.stopActiveChat()
	a.screen = "home"
	content := tview.NewTextView()
	content.SetDynamicColors(true)
	content.SetWrap(true)
	content.SetBorder(true).SetTitle(" " + translate(a.lang, "home.title") + " ")

	userLine := translate(a.lang, "status.not_logged_in")
	if a.user != nil {
		userLine = fmt.Sprintf("%s (UID %d)", tview.Escape(a.user.Nickname), a.user.UID)
	}
	fmt.Fprintf(content, "[::b]%s[::-]\n%s\n\n", translate(a.lang, "home.current_user"), userLine)
	fmt.Fprintln(content, translate(a.lang, "home.use_menu"))
	fmt.Fprintln(content, translate(a.lang, "home.shortcuts"))

	a.showMain(translate(a.lang, "home.title"), content, nil, message)
}

func (a *App) showMain(title string, content tview.Primitive, focus tview.Primitive, message string) {
	a.screen = "home"
	if message != "" {
		a.statusText = message
	}
	if content == nil {
		content = a.textPanel(title, translate(a.lang, "ui.no_content"))
	}

	header := tview.NewTextView()
	header.SetDynamicColors(true)
	header.SetTextAlign(tview.AlignCenter)
	header.SetText(a.headerText(title))

	menu := tview.NewList()
	menu.ShowSecondaryText(false)
	menu.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.title") + " ")
	menu.AddItem(translate(a.lang, "menu.chats"), "", 'c', func() { a.loadConversations() })
	menu.AddItem(translate(a.lang, "menu.friends"), "", 'f', func() { a.loadFriends() })
	menu.AddItem(translate(a.lang, "menu.groups"), "", 'g', func() { a.loadGroups() })
	menu.AddItem(translate(a.lang, "menu.public_groups"), "", 'p', func() { a.loadPublicGroups() })
	menu.AddItem(translate(a.lang, "menu.add_friend"), "", 'a', func() { a.showFriendRequestForm() })
	menu.AddItem(translate(a.lang, "menu.friend_requests"), "", 'r', func() { a.loadFriendRequests() })
	menu.AddItem(translate(a.lang, "menu.notices"), "", 'o', func() { a.loadNotices() })
	menu.AddItem(translate(a.lang, "menu.create_group"), "", 'n', func() { a.showCreateGroupForm() })
	menu.AddItem(translate(a.lang, "menu.refresh_user"), "", 'u', func() { a.refreshUser() })
	menu.AddItem(translate(a.lang, "menu.language"), "", 'y', func() { a.showLanguagePicker() })
	menu.AddItem(translate(a.lang, "menu.logout"), "", 'l', func() { a.logout() })
	menu.AddItem(translate(a.lang, "menu.quit"), "", 'q', func() { a.ui.Stop() })

	body := tview.NewFlex()
	body.AddItem(menu, 28, 0, focus == nil)
	body.AddItem(content, 0, 1, focus != nil)

	footer := a.newStatusBar()
	root := tview.NewFlex().SetDirection(tview.FlexRow)
	root.AddItem(header, 1, 0, false)
	root.AddItem(body, 0, 1, true)
	root.AddItem(footer, 1, 0, false)

	a.replacePage("main", root)
	if focus != nil {
		a.ui.SetFocus(focus)
	} else {
		a.ui.SetFocus(menu)
	}
	a.refreshUnreadSummary()
}

func (a *App) headerText(title string) string {
	user := translate(a.lang, "status.not_logged_in")
	if a.user != nil {
		user = fmt.Sprintf("%s / UID %d", tview.Escape(a.user.Nickname), a.user.UID)
	}
	return fmt.Sprintf("[::b]CsAC-Terminal[::-]  [gray]%s[-]  [teal]%s[-]", title, user)
}

func (a *App) setLanguage(lang Language) {
	a.lang = normalizeLanguage(lang)
	if a.config != nil {
		_ = a.config.Save(AppConfig{Language: a.lang})
	}
	a.setStatus(translate(a.lang, "status.language_changed"))
	switch a.screen {
	case "auth":
		a.showAuth("")
	case "register":
		a.showRegister("")
	case "chat":
		a.chatMu.Lock()
		session := a.activeChat
		a.chatMu.Unlock()
		if session != nil {
			a.showChat(session, "")
		} else {
			a.showHome("")
		}
	case "home":
		a.showHome("")
	default:
		a.showHome("")
	}
}

func (a *App) showLanguagePicker() {
	form := tview.NewForm()
	form.AddButton(translate(a.lang, "language.english"), func() {
		a.closeModal()
		a.setLanguage(LanguageEnglish)
	})
	form.AddButton(translate(a.lang, "language.chinese"), func() {
		a.closeModal()
		a.setLanguage(LanguageChinese)
	})
	form.AddButton(translate(a.lang, "ui.close"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "language.title") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 60, 10)
}

func (a *App) refreshUnreadSummary() {
	if a.user == nil {
		return
	}
	go func() {
		conversations, err := a.conversations()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				return
			}
			total := 0
			for _, conv := range conversations {
				total += conv.UnreadCount
			}
			notices, err := a.client.Notices()
			if err == nil {
				unreadNotices := 0
				for _, notice := range notices {
					if notice.IsRead == 0 {
						unreadNotices++
					}
				}
				if unreadNotices > 0 {
					total += unreadNotices
				}
			}
			if total > 0 {
				a.setStatus(translate(a.lang, "status.unread_items", total))
			}
		})
	}()
}

func (a *App) loadConversations() {
	a.showMain(translate(a.lang, "menu.chats"), a.textPanel(translate(a.lang, "menu.chats"), translate(a.lang, "loading.chats")), nil, translate(a.lang, "loading.chats"))
	go func() {
		conversations, err := a.conversations()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.load_chats_failed"), err)
				return
			}
			a.showConversationList(translate(a.lang, "menu.chats"), conversations, translate(a.lang, "status.logged_in"))
		})
	}()
}

func (a *App) showConversationList(title string, conversations []Conversation, message string) {
	list := tview.NewList()
	list.SetBorder(true).SetTitle(" " + title + " ")
	list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyEsc:
			a.showHome("")
			return nil
		case tcell.KeyF5:
			a.loadConversations()
			return nil
		}
		return event
	})

	if len(conversations) == 0 {
		list.AddItem(translate(a.lang, "list.no_conversations"), translate(a.lang, "list.use_friends_or_groups_hint"), 0, nil)
	} else {
		for _, conv := range conversations {
			conv := conv
			label := fmt.Sprintf("[%s] %s", a.conversationTypeLabel(conv.Type), conv.Name)
			if conv.UnreadCount > 0 {
				label += fmt.Sprintf(" (%d %s)", conv.UnreadCount, translate(a.lang, "ui.unread"))
			}
			list.AddItem(label, conv.Subtitle, 0, func() { a.openChat(conv) })
		}
	}
	a.showMain(title, list, list, message)
}

func (a *App) loadFriends() {
	a.showMain(translate(a.lang, "menu.friends"), a.textPanel(translate(a.lang, "menu.friends"), translate(a.lang, "loading.friends")), nil, translate(a.lang, "loading.friends"))
	go func() {
		friends, err := a.client.Friends()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.load_friends_failed"), err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.friends") + " ")
			list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
				switch event.Key() {
				case tcell.KeyEsc:
					a.showHome("")
					return nil
				case tcell.KeyF5:
					a.loadFriends()
					return nil
				}
				return event
			})
			if len(friends) == 0 {
				list.AddItem(translate(a.lang, "list.no_friends"), translate(a.lang, "list.send_friend_request_hint"), 0, nil)
			}
			for _, friend := range friends {
				friend := friend
				label := friend.DisplayName()
				if friend.UnreadCount > 0 {
					label += fmt.Sprintf(" (%d %s)", friend.UnreadCount, translate(a.lang, "ui.unread"))
				}
				list.AddItem(label, friend.Subtitle(), 0, func() {
					a.openChat(Conversation{
						Type:        ConversationFriend,
						ID:          friend.ID(),
						Name:        friend.DisplayName(),
						Subtitle:    friend.Subtitle(),
						UnreadCount: friend.UnreadCount,
					})
				})
			}
			list.AddItem(translate(a.lang, "menu.friend_requests"), translate(a.lang, "list.open_friend_requests_hint"), 0, func() { a.loadFriendRequests() })
			a.showMain(translate(a.lang, "menu.friends"), list, list, translate(a.lang, "status.logged_in"))
		})
	}()
}

func (a *App) loadFriendRequests() {
	a.showMain(translate(a.lang, "menu.friend_requests"), a.textPanel(translate(a.lang, "menu.friend_requests"), translate(a.lang, "loading.friend_requests")), nil, translate(a.lang, "loading.friend_requests"))
	go func() {
		requests, err := a.client.FriendRequests()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.load_friend_requests_failed"), err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.friend_requests") + " ")
			list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
				switch event.Key() {
				case tcell.KeyEsc:
					a.showHome("")
					return nil
				case tcell.KeyF5:
					a.loadFriendRequests()
					return nil
				}
				return event
			})
			if len(requests) == 0 {
				list.AddItem(translate(a.lang, "list.no_friend_requests"), "", 0, nil)
			}
			for _, req := range requests {
				req := req
				label := req.DisplayName()
				if req.RID() != 0 {
					label += fmt.Sprintf(" [#%d]", req.RID())
				}
				list.AddItem(label, req.Summary(), 0, func() {
					a.showFriendRequestDetail(req)
				})
			}
			a.showMain(translate(a.lang, "menu.friend_requests"), list, list, translate(a.lang, "status.logged_in"))
		})
	}()
}

func (a *App) loadNotices() {
	a.showMain(translate(a.lang, "menu.notices"), a.textPanel(translate(a.lang, "menu.notices"), translate(a.lang, "loading.notices")), nil, translate(a.lang, "loading.notices"))
	go func() {
		notices, err := a.client.Notices()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.load_notices_failed"), err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.notices") + " ")
			list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
				switch event.Key() {
				case tcell.KeyEsc:
					a.showHome("")
					return nil
				case tcell.KeyF5:
					a.loadNotices()
					return nil
				}
				return event
			})
			if len(notices) == 0 {
				list.AddItem(translate(a.lang, "list.no_notices"), "", 0, nil)
			}
			for _, notice := range notices {
				notice := notice
				label := notice.Title
				if notice.IsRead == 0 {
					label += " [" + translate(a.lang, "ui.unread") + "]"
				}
				list.AddItem(label, notice.Summary(), 0, func() {
					a.showNoticeDetail(notice)
				})
			}
			a.showMain(translate(a.lang, "menu.notices"), list, list, translate(a.lang, "status.logged_in"))
		})
	}()
}

func (a *App) loadGroups() {
	a.showMain(translate(a.lang, "menu.groups"), a.textPanel(translate(a.lang, "menu.groups"), translate(a.lang, "loading.groups")), nil, translate(a.lang, "loading.groups"))
	go func() {
		groups, err := a.client.Groups()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.load_groups_failed"), err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.groups") + " ")
			list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
				switch event.Key() {
				case tcell.KeyEsc:
					a.showHome("")
					return nil
				case tcell.KeyF5:
					a.loadGroups()
					return nil
				}
				return event
			})
			if len(groups) == 0 {
				list.AddItem(translate(a.lang, "list.no_groups"), translate(a.lang, "list.create_or_join_group_hint"), 0, nil)
			}
			for _, group := range groups {
				group := group
				label := fmt.Sprintf("%s [Room %d]", group.DisplayName(), group.Room())
				if group.UnreadCount > 0 {
					label += fmt.Sprintf(" (%d %s)", group.UnreadCount, translate(a.lang, "ui.unread"))
				}
				list.AddItem(label, group.Subtitle(), 0, func() {
					a.openChat(Conversation{
						Type:        ConversationGroup,
						ID:          group.Room(),
						Name:        group.DisplayName(),
						Subtitle:    group.Subtitle(),
						UnreadCount: group.UnreadCount,
					})
				})
			}
			a.showMain(translate(a.lang, "menu.groups"), list, list, translate(a.lang, "status.logged_in"))
		})
	}()
}

func (a *App) loadPublicGroups() {
	a.showMain(translate(a.lang, "menu.public_groups"), a.textPanel(translate(a.lang, "menu.public_groups"), translate(a.lang, "loading.public_groups")), nil, translate(a.lang, "loading.public_groups"))
	go func() {
		groups, err := a.client.PublicGroups()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.load_public_groups_failed"), err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.public_groups") + " ")
			list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
				switch event.Key() {
				case tcell.KeyEsc:
					a.showHome("")
					return nil
				case tcell.KeyF5:
					a.loadPublicGroups()
					return nil
				}
				return event
			})
			if len(groups) == 0 {
				list.AddItem(translate(a.lang, "list.no_public_groups"), "", 0, nil)
			}
			for _, group := range groups {
				group := group
				label := fmt.Sprintf("%s [Room %d]", group.DisplayName(), group.Room())
				list.AddItem(label, group.Subtitle(), 0, func() {
					a.showJoinGroupForm(group)
				})
			}
			a.showMain(translate(a.lang, "menu.public_groups"), list, list, translate(a.lang, "status.logged_in"))
		})
	}()
}

func (a *App) openChat(conv Conversation) {
	a.stopActiveChat()
	session := &ChatSession{
		Conv: conv,
		Stop: make(chan struct{}),
	}
	a.showChat(session, translate(a.lang, "loading.messages"))
	go func() {
		messages, err := a.loadMessages(conv)
		a.ui.QueueUpdateDraw(func() {
			if !a.isActiveChat(session) {
				return
			}
			if err != nil {
				a.showError(translate(a.lang, "error.load_messages_failed"), err)
				return
			}
			session.Messages = mergeMessages(nil, messages)
			session.LastID = maxMessageID(session.Messages)
			a.renderChatMessages(session)
			a.setStatus(translate(a.lang, "status.messages_loaded_auto_refresh"))
			go a.pollChat(session)
		})
	}()
}

func (a *App) showChat(session *ChatSession, message string) {
	a.screen = "chat"
	if message != "" {
		a.statusText = message
	}
	conv := session.Conv

	header := tview.NewTextView()
	header.SetDynamicColors(true)
	header.SetTextAlign(tview.AlignCenter)
	header.SetText(fmt.Sprintf("[::b]%s[::-]  [gray]%s | %s[-]", tview.Escape(conv.Name), a.conversationTypeLabel(conv.Type), translate(a.lang, "chat.shortcuts")))

	view := tview.NewTextView()
	view.SetDynamicColors(true)
	view.SetScrollable(true)
	view.SetWrap(true)
	view.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.messages") + " ")
	session.View = view
	a.renderChatMessages(session)
	view.ScrollToEnd()

	input := tview.NewInputField()
	input.SetLabel("> ")
	input.SetFieldWidth(0)
	session.Input = input
	input.SetDoneFunc(func(key tcell.Key) {
		if key != tcell.KeyEnter {
			return
		}
		text := strings.TrimSpace(input.GetText())
		if text == "" {
			return
		}
		input.SetText("")
		switch text {
		case "/b":
			a.showHome("")
		case "/r":
			a.refreshChat(session, true)
		case "/q":
			a.ui.Stop()
		case "/clear":
			session.Messages = nil
			session.LastID = 0
			a.renderChatMessages(session)
			a.setStatus(translate(a.lang, "status.local_message_view_cleared"))
		case "/img":
			a.showImageLinks(session)
		default:
			if strings.HasPrefix(text, "/") {
				a.setStatus(translate(a.lang, "status.unknown_chat_command"))
				return
			}
			a.sendChatMessage(conv, text)
		}
	})

	footer := a.newStatusBar()
	root := tview.NewFlex().SetDirection(tview.FlexRow)
	root.AddItem(header, 1, 0, false)
	root.AddItem(view, 0, 1, false)
	root.AddItem(input, 1, 0, true)
	root.AddItem(footer, 1, 0, false)
	root.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyEsc:
			a.showHome("")
			return nil
		case tcell.KeyF5:
			a.refreshChat(session, true)
			return nil
		}
		return event
	})

	a.setActiveChat(session)
	a.replacePage("chat", root)
	a.ui.SetFocus(input)
}

func (a *App) sendChatMessage(conv Conversation, content string) {
	a.setStatus(translate(a.lang, "action.sending_message"))
	go func() {
		err := a.sendMessage(conv, content)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.send_failed"), err)
				return
			}
			a.chatMu.Lock()
			session := a.activeChat
			a.chatMu.Unlock()
			if session != nil && session.Conv.Type == conv.Type && session.Conv.ID == conv.ID {
				a.refreshChat(session, true)
				return
			}
			a.setStatus(translate(a.lang, "action.message_sent"))
		})
	}()
}

func (a *App) showFriendRequestForm() {
	uid := tview.NewInputField().SetLabel(translate(a.lang, "form.target_uid") + ": ").SetFieldWidth(18)
	msg := tview.NewInputField().SetLabel(translate(a.lang, "form.message") + ":    ").SetFieldWidth(40)
	form := tview.NewForm()
	form.AddFormItem(uid)
	form.AddFormItem(msg)
	form.AddButton(translate(a.lang, "ui.send"), func() {
		target, err := strconv.Atoi(strings.TrimSpace(uid.GetText()))
		if err != nil || target <= 0 {
			a.setStatus(translate(a.lang, "status.invalid_uid"))
			return
		}
		message := msg.GetText()
		a.closeModal()
		a.setStatus(translate(a.lang, "action.send_request"))
		go func() {
			err := a.client.SendFriendRequest(target, message)
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError(translate(a.lang, "error.send_friend_request_failed"), err)
					return
				}
				a.setStatus(translate(a.lang, "status.friend_request_sent"))
			})
		}()
	})
	form.AddButton(translate(a.lang, "ui.cancel"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.add_friend") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 64, 11)
}

func (a *App) showCreateGroupForm() {
	name := tview.NewInputField().SetLabel(translate(a.lang, "form.room_name") + ": ").SetFieldWidth(40)
	form := tview.NewForm()
	form.AddFormItem(name)
	form.AddButton(translate(a.lang, "ui.create"), func() {
		roomName := strings.TrimSpace(name.GetText())
		if roomName == "" {
			a.setStatus(translate(a.lang, "status.room_name_required"))
			return
		}
		a.closeModal()
		a.setStatus(translate(a.lang, "action.create_group"))
		go func() {
			group, err := a.client.CreateGroup(roomName)
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError(translate(a.lang, "error.create_group_failed"), err)
					return
				}
				message := translate(a.lang, "status.group_created", group.Room())
				if group.InviteCode != "" {
					message += translate(a.lang, "status.invite_code_suffix", group.InviteCode)
				}
				a.setStatus(message)
			})
		}()
	})
	form.AddButton(translate(a.lang, "ui.cancel"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "menu.create_group") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 64, 10)
}

func (a *App) showJoinGroupForm(group Group) {
	code := tview.NewInputField().SetLabel(translate(a.lang, "form.invite_code") + ": ").SetFieldWidth(32)
	answer := tview.NewInputField().SetLabel(translate(a.lang, "form.answer") + ":      ").SetFieldWidth(40)
	form := tview.NewForm()
	form.AddFormItem(code)
	form.AddFormItem(answer)
	form.AddButton(translate(a.lang, "ui.join_apply"), func() {
		a.closeModal()
		a.setStatus(translate(a.lang, "action.send_group_request"))
		go func() {
			err := a.client.ApplyJoinGroup(group.Room(), strings.TrimSpace(code.GetText()), strings.TrimSpace(answer.GetText()))
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
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.join") + " " + group.DisplayName() + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 68, 11)
}

func (a *App) showFriendRequestDetail(req FriendRequest) {
	form := tview.NewForm()
	details := tview.NewTextView()
	details.SetDynamicColors(true)
	details.SetWrap(true)
	details.SetText(fmt.Sprintf(
		"[::b]%s[::-] %s\n[::b]UID[::-] %d\n[::b]%s[::-] %d\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s",
		translate(a.lang, "field.from"),
		tview.Escape(req.DisplayName()),
		req.FromUID,
		translate(a.lang, "field.request_id"),
		req.RID(),
		translate(a.lang, "field.type"),
		req.KindLabel(),
		translate(a.lang, "field.status"),
		req.StatusLabel(),
		translate(a.lang, "field.message"),
		tview.Escape(req.Text()),
		translate(a.lang, "field.time"),
		tview.Escape(req.Timestamp()),
	))
	form.AddFormItem(details)
	form.AddButton(translate(a.lang, "ui.agree"), func() {
		a.closeModal()
		a.setStatus(translate(a.lang, "action.accepting_friend_request"))
		go func() {
			err := a.client.HandleFriendRequest(req.RID(), "agree")
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError(translate(a.lang, "error.accept_friend_request_failed"), err)
					return
				}
				a.setStatus(translate(a.lang, "status.friend_request_accepted"))
				a.loadFriendRequests()
			})
		}()
	})
	form.AddButton(translate(a.lang, "ui.refuse"), func() {
		a.closeModal()
		a.setStatus(translate(a.lang, "action.refusing_friend_request"))
		go func() {
			err := a.client.HandleFriendRequest(req.RID(), "refuse")
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError(translate(a.lang, "error.refuse_friend_request_failed"), err)
					return
				}
				a.setStatus(translate(a.lang, "status.friend_request_refused"))
				a.loadFriendRequests()
			})
		}()
	})
	form.AddButton(translate(a.lang, "ui.copy"), func() {
		text := fmt.Sprintf("%s: %s\nUID: %d\n%s: %d\n%s: %s\n%s: %s",
			translate(a.lang, "field.from"), req.DisplayName(),
			req.FromUID,
			translate(a.lang, "field.request_id"), req.RID(),
			translate(a.lang, "field.message"), req.Text(),
			translate(a.lang, "field.time"), req.Timestamp())
		if err := copyToClipboard(text); err != nil {
			a.setStatus(translate(a.lang, "error.copy_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.copied_request_details"))
	})
	form.AddButton(translate(a.lang, "ui.back"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.friend_request") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 90, 16)
}

func (a *App) showNoticeDetail(notice Notice) {
	form := tview.NewForm()
	details := tview.NewTextView()
	details.SetDynamicColors(true)
	details.SetWrap(true)
	details.SetText(fmt.Sprintf(
		"[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n[::b]%s[::-] %s\n\n%s",
		translate(a.lang, "field.title"),
		tview.Escape(notice.Title),
		translate(a.lang, "field.status"),
		notice.StatusLabel(),
		translate(a.lang, "field.time"),
		tview.Escape(notice.Timestamp()),
		translate(a.lang, "field.route"),
		tview.Escape(notice.Route),
		translate(a.lang, "field.link"),
		tview.Escape(notice.Link),
		tview.Escape(notice.Content),
	))
	form.AddFormItem(details)
	form.AddButton(translate(a.lang, "ui.copy"), func() {
		text := fmt.Sprintf("%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n\n%s",
			translate(a.lang, "field.title"), notice.Title,
			translate(a.lang, "field.time"), notice.Timestamp(),
			translate(a.lang, "field.status"), notice.StatusLabel(),
			translate(a.lang, "field.route"), notice.Route,
			translate(a.lang, "field.link"), notice.Link,
			notice.Content)
		if err := copyToClipboard(text); err != nil {
			a.setStatus(translate(a.lang, "error.copy_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.copied_notice_text"))
	})
	form.AddButton(translate(a.lang, "ui.open_link"), func() {
		if notice.Link == "" {
			a.setStatus(translate(a.lang, "status.notice_no_link"))
			return
		}
		if err := openExternalURL(notice.Link); err != nil {
			a.setStatus(translate(a.lang, "error.open_link_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.opened_notice_link"))
	})
	form.AddButton(translate(a.lang, "ui.mark_read"), func() {
		a.closeModal()
		go func() {
			err := a.client.MarkNoticeRead(notice.NoticeID(), false)
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError(translate(a.lang, "error.mark_notice_read_failed"), err)
					return
				}
				a.setStatus(translate(a.lang, "status.notice_marked_read"))
				a.loadNotices()
			})
		}()
	})
	form.AddButton(translate(a.lang, "ui.back"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.notice") + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 96, 18)
}

func (a *App) refreshUser() {
	a.setStatus(translate(a.lang, "action.refreshing_user"))
	go func() {
		user, err := a.client.CurrentUser()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError(translate(a.lang, "error.refresh_user_failed"), err)
				return
			}
			a.user = user
			a.showHome(translate(a.lang, "status.user_refreshed"))
		})
	}()
}

func (a *App) logout() {
	a.setStatus(translate(a.lang, "action.logging_out"))
	go func() {
		err := a.client.Logout()
		clearErr := a.clearSession()
		a.ui.QueueUpdateDraw(func() {
			if clearErr != nil {
				a.showError(translate(a.lang, "error.clear_saved_session_failed"), clearErr)
				return
			}
			if err != nil {
				a.showError(translate(a.lang, "error.logout_failed"), err)
				a.user = nil
				a.statusText = translate(a.lang, "status.local_session_cleared_server_logout_failed")
				a.showAuth("")
				return
			}
			a.user = nil
			a.statusText = translate(a.lang, "status.logged_out")
			a.showAuth("")
		})
	}()
}

func (a *App) saveSession() error {
	if a.session == nil {
		return nil
	}
	return a.session.Save(a.client, a.user)
}

func (a *App) clearSession() error {
	if a.session == nil {
		return nil
	}
	return a.session.Clear()
}

func (a *App) loadMessages(conv Conversation) ([]Message, error) {
	var (
		messages []Message
		err      error
	)
	if conv.Type == ConversationGroup {
		messages, err = a.client.GroupMessages(conv.ID, 0, 0, 80)
	} else {
		messages, err = a.client.PrivateMessages(conv.ID, 0, 0, 0)
	}
	if err != nil {
		return nil, err
	}
	sort.SliceStable(messages, func(i, j int) bool {
		return messages[i].MessageID() < messages[j].MessageID()
	})
	if len(messages) > 0 {
		_ = a.client.MarkRead(conv, maxMessageID(messages))
	}
	return messages, nil
}

func (a *App) sendMessage(conv Conversation, content string) error {
	if conv.Type == ConversationGroup {
		return a.client.SendGroupMessage(conv.ID, content)
	}
	return a.client.SendPrivateMessage(conv.ID, content)
}

func (a *App) writeMessages(view *tview.TextView, messages []Message) {
	if len(messages) == 0 {
		fmt.Fprintf(view, "[gray]%s[-]\n", tview.Escape(translate(a.lang, "chat.no_messages")))
		return
	}
	start := 0
	if len(messages) > 120 {
		start = len(messages) - 120
		fmt.Fprintf(view, "[gray]%s[-]\n\n", tview.Escape(translate(a.lang, "chat.earlier_messages_hidden", start)))
	}
	for _, msg := range messages[start:] {
		ts := msg.Timestamp()
		if ts != "" {
			fmt.Fprintf(view, "[gray][%s][-] ", tview.Escape(ts))
		}
		sender := msg.Sender()
		if a.user != nil && msg.SenderID() == a.user.UID {
			sender = translate(a.lang, "chat.me")
		}
		flags := ""
		if msg.IsMentioned {
			flags += " @"
		}
		if msg.IsEssence {
			flags += " *"
		}
		fmt.Fprintf(view, "[green]%s%s[-]: %s\n", tview.Escape(sender), flags, tview.Escape(msg.Body()))
	}
}

func (a *App) renderChatMessages(session *ChatSession) {
	if session == nil || session.View == nil {
		return
	}
	session.View.Clear()
	session.ImageLinks = nil
	if len(session.Messages) == 0 {
		fmt.Fprintf(session.View, "[gray]%s[-]\n", tview.Escape(translate(a.lang, "chat.no_messages")))
		return
	}
	start := 0
	if len(session.Messages) > 120 {
		start = len(session.Messages) - 120
		fmt.Fprintf(session.View, "[gray]%s[-]\n\n", tview.Escape(translate(a.lang, "chat.earlier_messages_hidden", start)))
	}
	for _, msg := range session.Messages[start:] {
		ts := msg.Timestamp()
		if ts != "" {
			fmt.Fprintf(session.View, "[gray][%s][-] ", tview.Escape(ts))
		}
		sender := msg.Sender()
		if a.user != nil && msg.SenderID() == a.user.UID {
			sender = translate(a.lang, "chat.me")
		}
		flags := ""
		if msg.IsMentioned {
			flags += " @"
		}
		if msg.IsEssence {
			flags += " *"
		}
		body := msg.Body()
		if img := msg.ImageLink(); img != "" {
			session.ImageLinks = append(session.ImageLinks, normalizeAPIURL(img))
			body = body + " " + translate(a.lang, "chat.image_ref", len(session.ImageLinks))
		}
		fmt.Fprintf(session.View, "[green]%s%s[-]: %s\n", tview.Escape(sender), flags, tview.Escape(body))
	}
	session.View.ScrollToEnd()
}

func (a *App) pollChat(session *ChatSession) {
	ticker := time.NewTicker(4 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-session.Stop:
			return
		case <-ticker.C:
			a.refreshChat(session, false)
		}
	}
}

func (a *App) refreshChat(session *ChatSession, manual bool) {
	if session == nil {
		return
	}
	if manual {
		a.setStatus(translate(a.lang, "action.refreshing_messages"))
	}
	go func() {
		messages, err := a.loadMessagesAfter(session.Conv, session.LastID)
		a.ui.QueueUpdateDraw(func() {
			if !a.isActiveChat(session) {
				return
			}
			if err != nil {
				if manual {
					a.showError(translate(a.lang, "error.refresh_messages_failed"), err)
				} else {
					a.setStatus(translate(a.lang, "error.auto_refresh_failed") + ": " + err.Error())
				}
				return
			}
			before := len(session.Messages)
			session.Messages = mergeMessages(session.Messages, messages)
			session.LastID = maxMessageID(session.Messages)
			after := len(session.Messages)
			a.renderChatMessages(session)
			if after > before {
				count := after - before
				a.setStatus(translate(a.lang, "status.new_messages", count, session.Conv.Name))
				_ = a.client.MarkRead(session.Conv, session.LastID)
			} else if manual {
				a.setStatus(translate(a.lang, "action.no_new_messages"))
			}
		})
	}()
}

func (a *App) loadMessagesAfter(conv Conversation, lastID int) ([]Message, error) {
	var (
		messages []Message
		err      error
	)
	if conv.Type == ConversationGroup {
		messages, err = a.client.GroupMessagesAfter(conv.ID, lastID)
	} else {
		messages, err = a.client.PrivateMessagesAfter(conv.ID, lastID)
	}
	if err != nil {
		return nil, err
	}
	sort.SliceStable(messages, func(i, j int) bool {
		return messages[i].MessageID() < messages[j].MessageID()
	})
	return messages, nil
}

func (a *App) showImageLinks(session *ChatSession) {
	if session == nil || len(session.ImageLinks) == 0 {
		a.setStatus(translate(a.lang, "status.no_image_links"))
		return
	}
	list := tview.NewList()
	list.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.images") + " ")
	for i, link := range session.ImageLinks {
		link := link
		list.AddItem(fmt.Sprintf("#%d", i+1), link, 0, func() {
			a.showImageAction(link)
		})
	}
	list.AddItem(translate(a.lang, "ui.close"), "", 'q', func() { a.closeModal() })
	list.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEsc {
			a.closeModal()
			return nil
		}
		return event
	})
	a.showModal(list, 96, 18)
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

func (a *App) setActiveChat(session *ChatSession) {
	a.chatMu.Lock()
	defer a.chatMu.Unlock()
	a.activeChat = session
}

func (a *App) stopActiveChat() {
	a.chatMu.Lock()
	session := a.activeChat
	a.activeChat = nil
	a.chatMu.Unlock()
	if session != nil {
		close(session.Stop)
	}
}

func (a *App) isActiveChat(session *ChatSession) bool {
	a.chatMu.Lock()
	defer a.chatMu.Unlock()
	return a.activeChat == session
}

func mergeMessages(existing, incoming []Message) []Message {
	if len(incoming) == 0 {
		return existing
	}
	seen := make(map[int]struct{}, len(existing)+len(incoming))
	merged := make([]Message, 0, len(existing)+len(incoming))
	for _, msg := range existing {
		id := msg.MessageID()
		if id != 0 {
			seen[id] = struct{}{}
		}
		merged = append(merged, msg)
	}
	for _, msg := range incoming {
		id := msg.MessageID()
		if id != 0 {
			if _, ok := seen[id]; ok {
				continue
			}
			seen[id] = struct{}{}
		}
		merged = append(merged, msg)
	}
	sort.SliceStable(merged, func(i, j int) bool {
		return merged[i].MessageID() < merged[j].MessageID()
	})
	return merged
}

func (a *App) conversations() ([]Conversation, error) {
	friends, err := a.client.Friends()
	if err != nil {
		return nil, err
	}
	groups, err := a.client.Groups()
	if err != nil {
		return nil, err
	}
	conversations := make([]Conversation, 0, len(friends)+len(groups))
	for _, friend := range friends {
		conversations = append(conversations, Conversation{
			Type:        ConversationFriend,
			ID:          friend.ID(),
			Name:        friend.DisplayName(),
			Subtitle:    friend.Subtitle(),
			UnreadCount: friend.UnreadCount,
		})
	}
	for _, group := range groups {
		conversations = append(conversations, Conversation{
			Type:        ConversationGroup,
			ID:          group.Room(),
			Name:        group.DisplayName(),
			Subtitle:    group.Subtitle(),
			UnreadCount: group.UnreadCount,
		})
	}
	return conversations, nil
}

func (a *App) conversationTypeLabel(convType ConversationType) string {
	switch convType {
	case ConversationGroup:
		return translate(a.lang, "conversation.group")
	case ConversationFriend:
		return translate(a.lang, "conversation.private")
	default:
		return string(convType)
	}
}

func maxMessageID(messages []Message) int {
	maxID := 0
	for _, msg := range messages {
		if id := msg.MessageID(); id > maxID {
			maxID = id
		}
	}
	return maxID
}

func (a *App) textPanel(title, text string) *tview.TextView {
	panel := tview.NewTextView()
	panel.SetDynamicColors(true)
	panel.SetWrap(true)
	panel.SetBorder(true).SetTitle(" " + title + " ")
	panel.SetText(tview.Escape(text))
	return panel
}

func (a *App) newStatusBar() *tview.TextView {
	status := tview.NewTextView()
	status.SetDynamicColors(true)
	status.SetTextColor(tcell.ColorGray)
	status.SetText(a.statusText)
	a.status = status
	return status
}

func (a *App) setStatus(message string) {
	a.statusText = message
	if a.status != nil {
		a.status.SetText(message)
	}
}

func (a *App) showError(title string, err error) {
	message := title
	if err != nil {
		message += ": " + err.Error()
	}
	a.setStatus(message)

	body := tview.NewTextView()
	body.SetDynamicColors(true)
	body.SetWrap(true)
	body.SetScrollable(true)
	body.SetText(tview.Escape(message))

	form := tview.NewForm()
	form.AddFormItem(body)
	form.AddButton(translate(a.lang, "ui.copy"), func() {
		if err := copyToClipboard(message); err != nil {
			a.setStatus(translate(a.lang, "error.copy_failed") + ": " + err.Error())
			return
		}
		a.setStatus(translate(a.lang, "status.copied_error_message"))
	})
	form.AddButton(translate(a.lang, "ui.close"), func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" " + translate(a.lang, "ui.error") + " ").SetTitleAlign(tview.AlignLeft)
	form.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		if event.Key() == tcell.KeyEsc {
			a.closeModal()
			return nil
		}
		return event
	})

	a.showModal(form, 88, 14)
}

func copyToClipboard(text string) error {
	if runtime.GOOS != "windows" {
		return fmt.Errorf("clipboard copy is only implemented for Windows")
	}
	cmd := exec.Command("powershell", "-NoProfile", "-Command", "Set-Clipboard -Value $input")
	cmd.Stdin = strings.NewReader(text)
	output, err := cmd.CombinedOutput()
	if err != nil {
		detail := strings.TrimSpace(string(output))
		if detail != "" {
			return fmt.Errorf("%w: %s", err, detail)
		}
		return err
	}
	return nil
}

func openExternalURL(rawURL string) error {
	rawURL = normalizeAPIURL(rawURL)
	if rawURL == "" {
		return fmt.Errorf("empty URL")
	}
	switch runtime.GOOS {
	case "windows":
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", rawURL).Start()
	case "darwin":
		return exec.Command("open", rawURL).Start()
	default:
		return exec.Command("xdg-open", rawURL).Start()
	}
}

func normalizeAPIURL(rawURL string) string {
	rawURL = strings.TrimSpace(rawURL)
	if rawURL == "" {
		return ""
	}
	u, err := url.Parse(rawURL)
	if err == nil && u.IsAbs() {
		return rawURL
	}
	base, err := url.Parse(DefaultBaseURL)
	if err != nil {
		return rawURL
	}
	root := &url.URL{Scheme: base.Scheme, Host: base.Host, Path: "/"}
	rel, err := url.Parse(strings.TrimLeft(rawURL, "/"))
	if err != nil {
		return rawURL
	}
	return root.ResolveReference(rel).String()
}

func (a *App) showModal(primitive tview.Primitive, width, height int) {
	a.pages.RemovePage("modal")
	a.pages.AddPage("modal", centerPrimitive(primitive, width, height), true, true)
	a.ui.SetFocus(primitive)
}

func (a *App) closeModal() {
	a.pages.RemovePage("modal")
}

func centerPrimitive(primitive tview.Primitive, width, height int) tview.Primitive {
	row := tview.NewFlex()
	row.AddItem(nil, 0, 1, false)
	row.AddItem(primitive, width, 0, true)
	row.AddItem(nil, 0, 1, false)

	root := tview.NewFlex().SetDirection(tview.FlexRow)
	root.AddItem(nil, 0, 1, false)
	root.AddItem(row, height, 0, true)
	root.AddItem(nil, 0, 1, false)
	return root
}
