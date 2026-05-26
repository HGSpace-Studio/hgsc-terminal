part of '../../main.dart';

class ConversationDetailScreen extends StatefulWidget {
  const ConversationDetailScreen({
    super.key,
    required this.state,
    required this.conversation,
  });

  final CsacAppState state;
  final Conversation conversation;

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  UserProfile? user;
  GroupProfile? group;
  List<GroupMember> members = const <GroupMember>[];
  List<CommonGroup> commonGroups = const <CommonGroup>[];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.conversation.type == ConversationType.private) {
        final loaded = await widget.state.loadUserProfile(
          widget.conversation.id,
        );
        if (!mounted) {
          return;
        }
        var groups = const <CommonGroup>[];
        if (loaded.isFriend) {
          try {
            groups = await widget.state.loadCommonGroups(loaded.uid);
          } catch (_) {}
        }
        if (!mounted) {
          return;
        }
        setState(() {
          user = loaded;
          commonGroups = groups;
        });
      } else {
        final results = await Future.wait<dynamic>([
          widget.state.loadGroupProfile(widget.conversation.id),
          widget.state.loadGroupMembers(widget.conversation.id),
        ]);
        if (!mounted) {
          return;
        }
        setState(() {
          group = results[0] as GroupProfile;
          members = results[1] as List<GroupMember>;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> addFriend(UserProfile profile) async {
    final controller = TextEditingController(text: '请求添加你为好友');
    final strings = context.strings;
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.format('Add {name}', {'name': profile.displayName}),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: strings.text('Request message'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(strings.text('Send')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || !mounted) {
      return;
    }
    try {
      await widget.state.sendFriendRequest(profile.uid, message);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.text('Friend request sent.'))),
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format('Request failed: {error}', {'error': err}),
            ),
          ),
        );
      }
    }
  }

  Future<void> joinGroup(GroupProfile profile) async {
    final code = TextEditingController(text: profile.code);
    final answer = TextEditingController();
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.format('Join {name}', {'name': profile.name})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (profile.question.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(profile.question),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: code,
              decoration: InputDecoration(
                labelText: strings.text('Invite code'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: answer,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: strings.text('Answer'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.text('Apply')),
          ),
        ],
      ),
    );
    final codeText = code.text;
    final answerText = answer.text;
    code.dispose();
    answer.dispose();
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.state.applyJoinGroup(
        profile.id,
        code: codeText,
        answer: answerText,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.text('Join request sent.'))),
      );
      await load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format('Join failed: {error}', {'error': err}),
            ),
          ),
        );
      }
    }
  }

  Future<void> editRemark(UserProfile profile) async {
    final controller = TextEditingController(text: profile.remark);
    final strings = context.strings;
    final remark = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('Edit remark')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: strings.text('Remark'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(strings.text('Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (remark == null || !mounted) {
      return;
    }
    try {
      await widget.state.updateFriendRemark(profile.uid, remark.trim());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('Remark updated.'))));
      await load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format('Update failed: {error}', {'error': err}),
            ),
          ),
        );
      }
    }
  }

  Future<void> deleteFriend(UserProfile profile) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.format('Delete {name}?', {'name': profile.displayName}),
        ),
        content: Text(
          strings.text('This friend will be removed from your list.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.text('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.state.deleteFriend(profile.uid);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('Friend deleted.'))));
      Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format('Delete failed: {error}', {'error': err}),
            ),
          ),
        );
      }
    }
  }

  Future<void> blockFriend(UserProfile profile) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.format('Block {name}?', {'name': profile.displayName}),
        ),
        content: Text(strings.text('This friend will be blocked.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.text('Block')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.state.blockFriend(profile.uid);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('Friend blocked.'))));
      Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format('Block failed: {error}', {'error': err}),
            ),
          ),
        );
      }
    }
  }

  Future<void> leaveGroup(GroupProfile profile) async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.format('Leave {name}?', {'name': profile.name})),
        content: Text(
          strings.text('This group will be removed from your chats.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.text('Leave')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.state.leaveGroup(profile.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('Left group.'))));
      Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format('Leave failed: {error}', {'error': err}),
            ),
          ),
        );
      }
    }
  }

  Future<void> memberAction(GroupMember member, String action) async {
    final profile = group;
    if (profile == null) {
      return;
    }
    try {
      switch (action) {
        case 'mute10':
          await widget.state.muteGroupMember(profile.id, member.uid, 10);
          break;
        case 'unmute':
          await widget.state.muteGroupMember(profile.id, member.uid, 0);
          break;
        case 'kick':
          await widget.state.kickGroupMember(profile.id, member.uid);
          break;
        case 'admin':
          await widget.state.setGroupAdmin(profile.id, member.uid, true);
          break;
        case 'removeAdmin':
          await widget.state.setGroupAdmin(profile.id, member.uid, false);
          break;
      }
      if (!mounted) {
        return;
      }
      final strings = context.strings;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.text('Member action completed.'))),
      );
      await load();
    } catch (err) {
      if (mounted) {
        final strings = context.strings;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.format('Action failed: {error}', {'error': err}),
            ),
          ),
        );
      }
    }
  }

  Future<void> showMemberActions(GroupMember member) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.volume_off_outlined),
              title: Text(context.strings.text('Mute 10 minutes')),
              onTap: () => Navigator.of(context).pop('mute10'),
            ),
            ListTile(
              leading: const Icon(Icons.volume_up_outlined),
              title: Text(context.strings.text('Unmute')),
              onTap: () => Navigator.of(context).pop('unmute'),
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(context.strings.text('Set admin')),
              onTap: () => Navigator.of(context).pop('admin'),
            ),
            ListTile(
              leading: const Icon(Icons.remove_moderator_outlined),
              title: Text(context.strings.text('Remove admin')),
              onTap: () => Navigator.of(context).pop('removeAdmin'),
            ),
            ListTile(
              leading: Icon(
                Icons.person_remove_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                context.strings.text('Kick member'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop('kick'),
            ),
          ],
        ),
      ),
    );
    if (action != null) {
      await memberAction(member, action);
    }
  }

  void copyText(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.strings.format('{label} copied.', {'label': label}),
        ),
      ),
    );
  }

  Widget infoRow(IconData icon, String title, String value) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: SelectableText(value),
    );
  }

  Widget buildUserProfile(UserProfile profile) {
    return UserProfileScreen(
      state: widget.state,
      uid: profile.uid,
      key: ValueKey(profile.uid),
    );
  }

  Widget buildGroupProfile(GroupProfile profile) {
    final strings = context.strings;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              child: Icon(
                Icons.groups_rounded,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            title: Text(profile.name),
            subtitle: Text(
              profile.subtitle.isEmpty
                  ? strings.format('Room {id}', {'id': profile.id})
                  : profile.subtitle,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.tag),
                  title: Text(strings.text('Room ID')),
                  subtitle: SelectableText('${profile.id}'),
                  trailing: IconButton(
                    tooltip: strings.text('Copy room ID'),
                    onPressed: () =>
                        copyText(strings.text('Room ID'), '${profile.id}'),
                    icon: const Icon(Icons.copy),
                  ),
                ),
                infoRow(
                  Icons.info_outline,
                  strings.text('Description'),
                  profile.description,
                ),
                infoRow(
                  Icons.campaign_outlined,
                  strings.text('Notice'),
                  profile.notice,
                ),
                if (profile.inviteCode.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: Text(strings.text('Invite code')),
                    subtitle: SelectableText(profile.inviteCode),
                    trailing: IconButton(
                      tooltip: strings.text('Copy invite code'),
                      onPressed: () => copyText(
                        strings.text('Invite code'),
                        profile.inviteCode,
                      ),
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                infoRow(
                  Icons.lock_outline,
                  strings.text('Fixed code'),
                  profile.code,
                ),
                infoRow(
                  Icons.question_answer_outlined,
                  strings.text('Question'),
                  profile.question,
                ),
              ],
            ),
          ),
          if (!profile.isInGroup) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => joinGroup(profile),
              icon: const Icon(Icons.group_add),
              label: Text(strings.text('Apply to join')),
            ),
          ] else ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => leaveGroup(profile),
              icon: const Icon(Icons.logout),
              label: Text(strings.text('Leave group')),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.text('Members'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text('${members.length}'),
            ],
          ),
          const SizedBox(height: 8),
          if (members.isEmpty)
            _EmptyPanel(message: strings.text('No members.'))
          else
            for (final member in members)
              Card(
                elevation: 0,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: _RoundedInkClip(
                  child: ListTile(
                    leading: _Avatar(
                      url: member.avatar,
                      fallback: Icons.person_rounded,
                    ),
                    title: Text(member.name),
                    subtitle: member.subtitle.isEmpty
                        ? Text('UID ${member.uid}')
                        : Text(member.subtitle),
                    onTap: () => openUserProfile(
                      context,
                      widget.state,
                      member.uid,
                      group: profile,
                      member: member,
                    ),
                    trailing: (profile.isAdmin || profile.isOwner)
                        ? IconButton(
                            tooltip: strings.text('Manage'),
                            onPressed: () => showMemberActions(member),
                            icon: const Icon(Icons.more_vert),
                          )
                        : null,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.conversation.type == ConversationType.private) {
      return UserProfileScreen(
        state: widget.state,
        uid: widget.conversation.id,
      );
    }
    final title = widget.conversation.type == ConversationType.group
        ? context.strings.text('Group details')
        : context.strings.text('User details');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: context.strings.text('Refresh'),
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? _InlineError(message: error!, onRetry: load)
            : widget.conversation.type == ConversationType.private
            ? buildUserProfile(user!)
            : buildGroupProfile(group!),
      ),
    );
  }
}
