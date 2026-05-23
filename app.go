package main

import (
	"fmt"
	"os/exec"
	"runtime"
	"sort"
	"strconv"
	"strings"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

type App struct {
	client *UniCsACClient
	ui     *tview.Application
	pages  *tview.Pages

	user       *User
	status     *tview.TextView
	statusText string
}

func NewApp(client *UniCsACClient) *App {
	return &App{
		client: client,
		ui:     tview.NewApplication(),
		pages:  tview.NewPages(),
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

	a.showAuth("")
	return a.ui.SetRoot(a.pages, true).Run()
}

func (a *App) showAuth(message string) {
	if message != "" {
		a.statusText = message
	}

	username := tview.NewInputField().SetLabel("Username: ").SetFieldWidth(32)
	password := tview.NewInputField().SetLabel("Password: ").SetMaskCharacter('*').SetFieldWidth(32)

	form := tview.NewForm()
	form.AddFormItem(username)
	form.AddFormItem(password)
	form.AddButton("Login", func() {
		a.login(strings.TrimSpace(username.GetText()), password.GetText())
	})
	form.AddButton("Register", func() {
		a.showRegister("")
	})
	form.AddButton("Quit", func() {
		a.ui.Stop()
	})
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" CsAC-Terminal Login ").SetTitleAlign(tview.AlignLeft)

	footer := a.newStatusBar()
	root := tview.NewFlex().SetDirection(tview.FlexRow)
	root.AddItem(nil, 0, 1, false)
	root.AddItem(centerPrimitive(form, 62, 12), 12, 0, true)
	root.AddItem(footer, 1, 0, false)

	a.pages.RemovePage("auth")
	a.pages.AddPage("auth", root, true, true)
	a.pages.SwitchToPage("auth")
	a.ui.SetFocus(form)
}

func (a *App) showRegister(message string) {
	if message != "" {
		a.statusText = message
	}

	username := tview.NewInputField().SetLabel("Username: ").SetFieldWidth(32)
	nickname := tview.NewInputField().SetLabel("Nickname: ").SetFieldWidth(32)
	password := tview.NewInputField().SetLabel("Password: ").SetMaskCharacter('*').SetFieldWidth(32)
	confirm := tview.NewInputField().SetLabel("Confirm:  ").SetMaskCharacter('*').SetFieldWidth(32)

	form := tview.NewForm()
	form.AddFormItem(username)
	form.AddFormItem(nickname)
	form.AddFormItem(password)
	form.AddFormItem(confirm)
	form.AddButton("Create", func() {
		if password.GetText() != confirm.GetText() {
			a.setStatus("Passwords do not match.")
			return
		}
		a.register(strings.TrimSpace(username.GetText()), strings.TrimSpace(nickname.GetText()), password.GetText())
	})
	form.AddButton("Back", func() {
		a.showAuth("")
	})
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" Create Account ").SetTitleAlign(tview.AlignLeft)

	footer := a.newStatusBar()
	root := tview.NewFlex().SetDirection(tview.FlexRow)
	root.AddItem(nil, 0, 1, false)
	root.AddItem(centerPrimitive(form, 62, 15), 15, 0, true)
	root.AddItem(footer, 1, 0, false)

	a.pages.RemovePage("register")
	a.pages.AddPage("register", root, true, true)
	a.pages.SwitchToPage("register")
	a.ui.SetFocus(form)
}

func (a *App) login(username, password string) {
	if username == "" || password == "" {
		a.setStatus("Username and password are required.")
		return
	}
	a.setStatus("Logging in...")
	go func() {
		user, err := a.client.Login(username, password)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Login failed", err)
				return
			}
			a.user = user
			a.showHome("Logged in.")
		})
	}()
}

func (a *App) register(username, nickname, password string) {
	if username == "" || nickname == "" || password == "" {
		a.setStatus("Username, nickname and password are required.")
		return
	}
	a.setStatus("Creating account...")
	go func() {
		user, err := a.client.Register(username, nickname, password)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Register failed", err)
				return
			}
			a.user = user
			a.showHome("Account created and logged in.")
		})
	}()
}

func (a *App) showHome(message string) {
	content := tview.NewTextView()
	content.SetDynamicColors(true)
	content.SetWrap(true)
	content.SetBorder(true).SetTitle(" Home ")

	userLine := "Not logged in"
	if a.user != nil {
		userLine = fmt.Sprintf("%s (UID %d)", tview.Escape(a.user.Nickname), a.user.UID)
	}
	fmt.Fprintf(content, "[::b]Current user[::-]\n%s\n\n", userLine)
	fmt.Fprintln(content, "Use the menu on the left to open chats, friends, groups, public groups, or action forms.")
	fmt.Fprintln(content, "Shortcuts: Ctrl+C quits, Esc returns from chat/list views, F5 refreshes lists and chats.")

	a.showMain("Home", content, nil, message)
}

func (a *App) showMain(title string, content tview.Primitive, focus tview.Primitive, message string) {
	if message != "" {
		a.statusText = message
	}
	if content == nil {
		content = a.textPanel(title, "No content.")
	}

	header := tview.NewTextView()
	header.SetDynamicColors(true)
	header.SetTextAlign(tview.AlignCenter)
	header.SetText(a.headerText(title))

	menu := tview.NewList()
	menu.ShowSecondaryText(false)
	menu.SetBorder(true).SetTitle(" Menu ")
	menu.AddItem("Chats", "", 'c', func() { a.loadConversations() })
	menu.AddItem("Friends", "", 'f', func() { a.loadFriends() })
	menu.AddItem("Groups", "", 'g', func() { a.loadGroups() })
	menu.AddItem("Public Groups", "", 'p', func() { a.loadPublicGroups() })
	menu.AddItem("Add Friend", "", 'a', func() { a.showFriendRequestForm() })
	menu.AddItem("Create Group", "", 'n', func() { a.showCreateGroupForm() })
	menu.AddItem("Refresh User", "", 'u', func() { a.refreshUser() })
	menu.AddItem("Logout", "", 'l', func() { a.logout() })
	menu.AddItem("Quit", "", 'q', func() { a.ui.Stop() })

	body := tview.NewFlex()
	body.AddItem(menu, 28, 0, focus == nil)
	body.AddItem(content, 0, 1, focus != nil)

	footer := a.newStatusBar()
	root := tview.NewFlex().SetDirection(tview.FlexRow)
	root.AddItem(header, 1, 0, false)
	root.AddItem(body, 0, 1, true)
	root.AddItem(footer, 1, 0, false)

	a.pages.RemovePage("main")
	a.pages.AddPage("main", root, true, true)
	a.pages.SwitchToPage("main")
	if focus != nil {
		a.ui.SetFocus(focus)
	} else {
		a.ui.SetFocus(menu)
	}
}

func (a *App) headerText(title string) string {
	user := "not logged in"
	if a.user != nil {
		user = fmt.Sprintf("%s / UID %d", tview.Escape(a.user.Nickname), a.user.UID)
	}
	return fmt.Sprintf("[::b]CsAC-Terminal[::-]  [gray]%s[-]  [teal]%s[-]", title, user)
}

func (a *App) loadConversations() {
	a.showMain("Chats", a.textPanel("Chats", "Loading chats..."), nil, "Loading chats...")
	go func() {
		conversations, err := a.conversations()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Load chats failed", err)
				return
			}
			a.showConversationList("Chats", conversations, "Chats loaded.")
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
		list.AddItem("No conversations", "Use friends or groups first.", 0, nil)
	} else {
		for _, conv := range conversations {
			conv := conv
			label := fmt.Sprintf("[%s] %s", conv.Type, conv.Name)
			if conv.UnreadCount > 0 {
				label += fmt.Sprintf(" (%d unread)", conv.UnreadCount)
			}
			list.AddItem(label, conv.Subtitle, 0, func() { a.openChat(conv) })
		}
	}
	a.showMain(title, list, list, message)
}

func (a *App) loadFriends() {
	a.showMain("Friends", a.textPanel("Friends", "Loading friends..."), nil, "Loading friends...")
	go func() {
		friends, err := a.client.Friends()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Load friends failed", err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" Friends ")
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
				list.AddItem("No friends", "Send a friend request from the menu.", 0, nil)
			}
			for _, friend := range friends {
				friend := friend
				label := friend.DisplayName()
				if friend.UnreadCount > 0 {
					label += fmt.Sprintf(" (%d unread)", friend.UnreadCount)
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
			a.showMain("Friends", list, list, "Friends loaded.")
		})
	}()
}

func (a *App) loadGroups() {
	a.showMain("Groups", a.textPanel("Groups", "Loading groups..."), nil, "Loading groups...")
	go func() {
		groups, err := a.client.Groups()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Load groups failed", err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" Groups ")
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
				list.AddItem("No groups", "Create or join a group first.", 0, nil)
			}
			for _, group := range groups {
				group := group
				label := fmt.Sprintf("%s [Room %d]", group.DisplayName(), group.Room())
				if group.UnreadCount > 0 {
					label += fmt.Sprintf(" (%d unread)", group.UnreadCount)
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
			a.showMain("Groups", list, list, "Groups loaded.")
		})
	}()
}

func (a *App) loadPublicGroups() {
	a.showMain("Public Groups", a.textPanel("Public Groups", "Loading public groups..."), nil, "Loading public groups...")
	go func() {
		groups, err := a.client.PublicGroups()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Load public groups failed", err)
				return
			}
			list := tview.NewList()
			list.SetBorder(true).SetTitle(" Public Groups ")
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
				list.AddItem("No public groups", "", 0, nil)
			}
			for _, group := range groups {
				group := group
				label := fmt.Sprintf("%s [Room %d]", group.DisplayName(), group.Room())
				list.AddItem(label, group.Subtitle(), 0, func() {
					a.showJoinGroupForm(group)
				})
			}
			a.showMain("Public Groups", list, list, "Public groups loaded.")
		})
	}()
}

func (a *App) openChat(conv Conversation) {
	a.showChat(conv, nil, "Loading messages...")
	go func() {
		messages, err := a.loadMessages(conv)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Load messages failed", err)
				return
			}
			a.showChat(conv, messages, "Messages loaded.")
		})
	}()
}

func (a *App) showChat(conv Conversation, messages []Message, message string) {
	if message != "" {
		a.statusText = message
	}

	header := tview.NewTextView()
	header.SetDynamicColors(true)
	header.SetTextAlign(tview.AlignCenter)
	header.SetText(fmt.Sprintf("[::b]%s[::-]  [gray]%s | Esc back | F5 refresh | Enter send[-]", tview.Escape(conv.Name), conv.Type))

	view := tview.NewTextView()
	view.SetDynamicColors(true)
	view.SetScrollable(true)
	view.SetWrap(true)
	view.SetBorder(true).SetTitle(" Messages ")
	a.writeMessages(view, messages)
	view.ScrollToEnd()

	input := tview.NewInputField()
	input.SetLabel("> ")
	input.SetFieldWidth(0)
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
			a.openChat(conv)
		case "/q":
			a.ui.Stop()
		case "/clear":
			a.showChat(conv, nil, "Local message view cleared.")
		default:
			if strings.HasPrefix(text, "/") {
				a.setStatus("Unknown chat command.")
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
			a.openChat(conv)
			return nil
		}
		return event
	})

	a.pages.RemovePage("chat")
	a.pages.AddPage("chat", root, true, true)
	a.pages.SwitchToPage("chat")
	a.ui.SetFocus(input)
}

func (a *App) sendChatMessage(conv Conversation, content string) {
	a.setStatus("Sending message...")
	go func() {
		err := a.sendMessage(conv, content)
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Send failed", err)
				return
			}
			a.openChat(conv)
		})
	}()
}

func (a *App) showFriendRequestForm() {
	uid := tview.NewInputField().SetLabel("Target UID: ").SetFieldWidth(18)
	msg := tview.NewInputField().SetLabel("Message:    ").SetFieldWidth(40)
	form := tview.NewForm()
	form.AddFormItem(uid)
	form.AddFormItem(msg)
	form.AddButton("Send", func() {
		target, err := strconv.Atoi(strings.TrimSpace(uid.GetText()))
		if err != nil || target <= 0 {
			a.setStatus("Invalid UID.")
			return
		}
		message := msg.GetText()
		a.closeModal()
		a.setStatus("Sending friend request...")
		go func() {
			err := a.client.SendFriendRequest(target, message)
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError("Send friend request failed", err)
					return
				}
				a.setStatus("Friend request sent.")
			})
		}()
	})
	form.AddButton("Cancel", func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" Add Friend ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 64, 11)
}

func (a *App) showCreateGroupForm() {
	name := tview.NewInputField().SetLabel("Room name: ").SetFieldWidth(40)
	form := tview.NewForm()
	form.AddFormItem(name)
	form.AddButton("Create", func() {
		roomName := strings.TrimSpace(name.GetText())
		if roomName == "" {
			a.setStatus("Room name is required.")
			return
		}
		a.closeModal()
		a.setStatus("Creating group...")
		go func() {
			group, err := a.client.CreateGroup(roomName)
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError("Create group failed", err)
					return
				}
				message := fmt.Sprintf("Group created. Room ID: %d", group.Room())
				if group.InviteCode != "" {
					message += ", invite code: " + group.InviteCode
				}
				a.setStatus(message)
			})
		}()
	})
	form.AddButton("Cancel", func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" Create Group ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 64, 10)
}

func (a *App) showJoinGroupForm(group Group) {
	code := tview.NewInputField().SetLabel("Invite code: ").SetFieldWidth(32)
	answer := tview.NewInputField().SetLabel("Answer:      ").SetFieldWidth(40)
	form := tview.NewForm()
	form.AddFormItem(code)
	form.AddFormItem(answer)
	form.AddButton("Join/Apply", func() {
		a.closeModal()
		a.setStatus("Sending group request...")
		go func() {
			err := a.client.ApplyJoinGroup(group.Room(), strings.TrimSpace(code.GetText()), strings.TrimSpace(answer.GetText()))
			a.ui.QueueUpdateDraw(func() {
				if err != nil {
					a.showError("Join/apply failed", err)
					return
				}
				a.setStatus("Join/apply request sent.")
			})
		}()
	})
	form.AddButton("Cancel", func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" Join " + group.DisplayName() + " ").SetTitleAlign(tview.AlignLeft)
	a.showModal(form, 68, 11)
}

func (a *App) refreshUser() {
	a.setStatus("Refreshing user...")
	go func() {
		user, err := a.client.CurrentUser()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Refresh user failed", err)
				return
			}
			a.user = user
			a.showHome("User refreshed.")
		})
	}()
}

func (a *App) logout() {
	a.setStatus("Logging out...")
	go func() {
		err := a.client.Logout()
		a.ui.QueueUpdateDraw(func() {
			if err != nil {
				a.showError("Logout failed", err)
				return
			}
			a.user = nil
			a.statusText = "Logged out."
			a.showAuth("")
		})
	}()
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
		fmt.Fprintln(view, "[gray]No messages.[-]")
		return
	}
	start := 0
	if len(messages) > 120 {
		start = len(messages) - 120
		fmt.Fprintf(view, "[gray]... %d earlier messages hidden ...[-]\n\n", start)
	}
	for _, msg := range messages[start:] {
		ts := msg.Timestamp()
		if ts != "" {
			fmt.Fprintf(view, "[gray][%s][-] ", tview.Escape(ts))
		}
		sender := msg.Sender()
		if a.user != nil && msg.SenderID() == a.user.UID {
			sender = "me"
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
	form.AddButton("Copy", func() {
		if err := copyToClipboard(message); err != nil {
			a.setStatus("Copy failed: " + err.Error())
			return
		}
		a.setStatus("Copied error message.")
	})
	form.AddButton("Close", func() { a.closeModal() })
	form.SetButtonsAlign(tview.AlignRight)
	form.SetBorder(true).SetTitle(" Error ").SetTitleAlign(tview.AlignLeft)
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
