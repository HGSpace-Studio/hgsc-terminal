part of '../../main.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.state});

  final CsacAppState state;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  int lastUnreadChats = 0;
  Conversation? selectedConversation;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    lastUnreadChats = totalUnreadChats();
    timer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => refreshHomeWithHint(),
    );
  }

  int totalUnreadChats() {
    return widget.state.conversations.fold<int>(
      0,
      (total, conversation) => total + conversation.unreadCount,
    );
  }

  Future<void> refreshHomeWithHint() async {
    final strings = context.strings;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.state.refreshHome();
    } catch (_) {
      return;
    }
    if (!mounted) {
      return;
    }
    final currentConversation =
        selectedConversation ?? widget.state.activeConversation;
    if (currentConversation != null) {
      final selected = currentConversation;
      final latestSelected = widget.state.conversations
          .where(
            (conversation) =>
                conversation.type == selected.type &&
                conversation.id == selected.id,
          )
          .firstOrNull;
      if (latestSelected != null) {
        if (selectedConversation != null) {
          selectedConversation = latestSelected.copyWith(unreadCount: 0);
        }
        await widget.state.markConversationRead(
          latestSelected,
          syncServer: false,
        );
      }
    }
    final after = totalUnreadChats();
    if (after > lastUnreadChats) {
      final message = strings.format('New messages: {count}', {
        'count': after - lastUnreadChats,
      });
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
    lastUnreadChats = after;
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unreadChats = totalUnreadChats();
    final noticeCount = widget.state.notificationCounts.total;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = <Widget>[
      ConversationScreen(
        state: widget.state,
        embedded: true,
        selectedConversation: selectedConversation,
        onConversationSelected: wide
            ? (conversation) {
                widget.state.markConversationRead(conversation);
                widget.state.setActiveConversation(conversation);
                setState(
                  () => selectedConversation = conversation.copyWith(
                    unreadCount: 0,
                  ),
                );
                lastUnreadChats = totalUnreadChats();
              }
            : null,
      ),
      MessageSearchScreen(state: widget.state, embedded: true),
      NoticeCenterScreen(state: widget.state),
      ProfileScreen(state: widget.state),
    ];
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (value) {
                  setState(() => index = value);
                  if (value == 0) {
                    widget.state.loadConversations();
                  }
                  if (value == 2) {
                    widget.state.refreshNotificationCounts();
                  }
                },
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 18),
                  child: Icon(
                    Icons.forum_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                destinations: [
                  NavigationRailDestination(
                    icon: _BadgeIcon(
                      icon: Icons.chat_bubble_outline,
                      count: unreadChats,
                    ),
                    selectedIcon: _BadgeIcon(
                      icon: Icons.chat_bubble,
                      count: unreadChats,
                    ),
                    label: Text(context.strings.text('Chats')),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.manage_search_outlined),
                    selectedIcon: const Icon(Icons.manage_search),
                    label: Text(context.strings.text('Search')),
                  ),
                  NavigationRailDestination(
                    icon: _BadgeIcon(
                      icon: Icons.notifications_none,
                      count: noticeCount,
                    ),
                    selectedIcon: _BadgeIcon(
                      icon: Icons.notifications,
                      count: noticeCount,
                    ),
                    label: Text(context.strings.text('Notices')),
                  ),
                  NavigationRailDestination(
                    icon: const Icon(Icons.person_outline),
                    selectedIcon: const Icon(Icons.person),
                    label: Text(context.strings.text('Me')),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: index == 0
                    ? _WideChatLayout(
                        state: widget.state,
                        conversations: pages[0],
                        selectedConversation: selectedConversation,
                      )
                    : pages[index],
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: _BottomTabSwitcher(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          setState(() => index = value);
          if (value == 0) {
            widget.state.loadConversations();
          }
          if (value == 2) {
            widget.state.refreshNotificationCounts();
          }
        },
        destinations: [
          NavigationDestination(
            icon: _BadgeIcon(
              icon: Icons.chat_bubble_outline,
              count: unreadChats,
            ),
            selectedIcon: _BadgeIcon(
              icon: Icons.chat_bubble,
              count: unreadChats,
            ),
            label: context.strings.text('Chats'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.manage_search_outlined),
            selectedIcon: const Icon(Icons.manage_search),
            label: context.strings.text('Search'),
          ),
          NavigationDestination(
            icon: _BadgeIcon(
              icon: Icons.notifications_none,
              count: noticeCount,
            ),
            selectedIcon: _BadgeIcon(
              icon: Icons.notifications,
              count: noticeCount,
            ),
            label: context.strings.text('Notices'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: context.strings.text('Me'),
          ),
        ],
      ),
    );
  }
}

class _BottomTabSwitcher extends StatefulWidget {
  const _BottomTabSwitcher({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_BottomTabSwitcher> createState() => _BottomTabSwitcherState();
}

class _BottomTabSwitcherState extends State<_BottomTabSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  int previousIndex = 0;

  @override
  void initState() {
    super.initState();
    previousIndex = widget.index;
    controller = AnimationController(duration: 280.ms, vsync: this)..value = 1;
  }

  @override
  void didUpdateWidget(covariant _BottomTabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      previousIndex = oldWidget.index;
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _MotionPreference.reduceOf(context);
    if (reduceMotion) {
      return IndexedStack(index: widget.index, children: widget.children);
    }
    final forward = widget.index >= previousIndex;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final curved = Curves.easeOutCubic.transform(controller.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _buildPage(i, curved, forward),
          ],
        );
      },
    );
  }

  Widget _buildPage(int pageIndex, double progress, bool forward) {
    final active = pageIndex == widget.index;
    final outgoing = pageIndex == previousIndex && pageIndex != widget.index;
    final direction = forward ? 1.0 : -1.0;
    final offset = active
        ? Offset(0.06 * direction * (1 - progress), 0)
        : outgoing
        ? Offset(-0.04 * direction * progress, 0)
        : Offset.zero;
    final opacity = active
        ? progress
        : outgoing
        ? 1 - progress
        : pageIndex == widget.index
        ? 1.0
        : 0.0;
    return Offstage(
      offstage: !active && !outgoing,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !active,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: FractionalTranslation(
              translation: offset,
              child: widget.children[pageIndex],
            ),
          ),
        ),
      ),
    );
  }
}

class _WideChatLayout extends StatelessWidget {
  const _WideChatLayout({
    required this.state,
    required this.conversations,
    required this.selectedConversation,
  });

  final CsacAppState state;
  final Widget conversations;
  final Conversation? selectedConversation;

  @override
  Widget build(BuildContext context) {
    final selected = selectedConversation;
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 430),
          child: conversations,
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const _WideEmptyChatPlaceholder()
              : ChatScreen(
                  key: ValueKey('${selected.type.name}:${selected.id}'),
                  state: state,
                  conversation: selected,
                  embedded: true,
                ),
        ),
      ],
    );
  }
}

class _WideEmptyChatPlaceholder extends StatelessWidget {
  const _WideEmptyChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              context.strings.text('Select a conversation'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon);
    if (count <= 0) {
      return child;
    }
    return Badge(label: Text(count > 99 ? '99+' : '$count'), child: child);
  }
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.state,
    this.embedded = false,
    this.selectedConversation,
    this.onConversationSelected,
  });

  final CsacAppState state;
  final bool embedded;
  final Conversation? selectedConversation;
  final ValueChanged<Conversation>? onConversationSelected;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final search = TextEditingController();
  late final ScrollController conversationsScroll;
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    conversationsScroll = _desktopSmoothScrollController();
  }

  @override
  void dispose() {
    conversationsScroll.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.state.loadConversations();
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
      }
    }
  }

  Future<void> openHomeAction(String action) async {
    switch (action) {
      case 'refresh':
        await refresh();
        break;
      case 'addFriend':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AddFriendScreen(state: widget.state),
          ),
        );
        break;
      case 'joinGroup':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => JoinGroupScreen(state: widget.state),
          ),
        );
        break;
      case 'createGroup':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CreateGroupScreen(state: widget.state),
          ),
        );
        break;
      case 'searchMessages':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MessageSearchScreen(state: widget.state),
          ),
        );
        break;
      case 'logout':
        await confirmLogout(context, widget.state, popToRoot: false);
        break;
    }
    if (mounted &&
        action != 'refresh' &&
        action != 'searchMessages' &&
        action != 'logout') {
      await refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.user;
    final strings = context.strings;
    final query = search.text.trim().toLowerCase();
    final conversations = query.isEmpty
        ? widget.state.conversations
        : widget.state.conversations.where((conversation) {
            final target =
                '${conversation.name} ${conversation.subtitle} ${conversation.searchText}'
                    .toLowerCase();
            return target.contains(query);
          }).toList();
    final content = RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        controller: conversationsScroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _Avatar(
                        url: user?.avatar ?? '',
                        fallback: Icons.person_rounded,
                        radius: 19,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          user == null
                              ? strings.text('Not logged in')
                              : '${user.nickname} / UID ${user.uid}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.state.offlineMode)
                  Chip(
                    avatar: const Icon(Icons.cloud_off_outlined, size: 18),
                    label: Text(strings.text('Offline')),
                  ),
                PopupMenuButton<String>(
                  tooltip: strings.text('More'),
                  onSelected: openHomeAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'addFriend',
                      child: ListTile(
                        leading: const Icon(Icons.person_add_alt),
                        title: Text(strings.text('Add friend')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'joinGroup',
                      child: ListTile(
                        leading: const Icon(Icons.group_add_outlined),
                        title: Text(strings.text('Join group')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'createGroup',
                      child: ListTile(
                        leading: const Icon(Icons.add_home_work_outlined),
                        title: Text(strings.text('Create group')),
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: strings.text('Search conversations'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: strings.text('Clear'),
                        onPressed: () {
                          search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (widget.state.conversations.isEmpty)
            _EmptyPanel(message: strings.text('No conversations yet.'))
          else if (conversations.isEmpty)
            _EmptyPanel(message: strings.text('No matching conversations.'))
          else
            for (final entry in conversations.indexed)
              _MotionListItem(
                index: entry.$1,
                child: _ConversationTile(
                  conversation: entry.$2,
                  selected:
                      widget.selectedConversation?.type == entry.$2.type &&
                      widget.selectedConversation?.id == entry.$2.id,
                  onTap: () async {
                    if (widget.onConversationSelected != null) {
                      widget.onConversationSelected!(entry.$2);
                      return;
                    }
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatScreen(
                          state: widget.state,
                          conversation: entry.$2,
                        ),
                      ),
                    );
                    if (mounted) {
                      refresh();
                    }
                  },
                ),
              ),
        ],
      ),
    );
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('CsAC'),
              actions: [
                PopupMenuButton<String>(
                  tooltip: strings.text('More'),
                  onSelected: openHomeAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: const Icon(Icons.refresh),
                        title: Text(strings.text('Refresh')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'addFriend',
                      child: ListTile(
                        leading: const Icon(Icons.person_add_alt),
                        title: Text(strings.text('Add friend')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'joinGroup',
                      child: ListTile(
                        leading: const Icon(Icons.group_add_outlined),
                        title: Text(strings.text('Join group')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'createGroup',
                      child: ListTile(
                        leading: const Icon(Icons.add_home_work_outlined),
                        title: Text(strings.text('Create group')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'searchMessages',
                      child: ListTile(
                        leading: const Icon(Icons.manage_search),
                        title: Text(strings.text('Search messages')),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: const Icon(Icons.logout),
                        title: Text(strings.text('Logout')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: SafeArea(top: widget.embedded, child: content),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    this.selected = false,
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final isGroup = conversation.type == ConversationType.group;
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: selected ? colors.secondaryContainer : null,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: _RoundedInkClip(
        child: ListTile(
          selected: selected,
          selectedColor: colors.onSecondaryContainer,
          selectedTileColor: colors.secondaryContainer,
          onTap: onTap,
          leading: _ConversationAvatarHero(
            conversation: conversation,
            radius: 22,
          ),
          title: _ConversationTitleHero(
            conversation: conversation,
            enabled: !selected,
          ),
          subtitle: Text(
            conversation.subtitle.isEmpty
                ? context.strings.text(isGroup ? 'Group chat' : 'Private chat')
                : conversation.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: conversation.unreadCount > 0
              ? Badge(label: Text('${conversation.unreadCount}'))
              : const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
