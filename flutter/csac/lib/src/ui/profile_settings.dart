part of '../../main.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  Widget build(BuildContext context) {
    final user = state.user;
    final counts = state.notificationCounts;
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Me'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (state.sessionExpired)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MaterialBanner(
                  content: Text(
                    strings.text(
                      'Session expired. Log in again to sync latest data.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => confirmLogout(context, state),
                      child: Text(strings.text('Login')),
                    ),
                  ],
                ),
              ),
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: ListTile(
                  leading: _Avatar(
                    url: user?.avatar ?? '',
                    fallback: Icons.person_rounded,
                  ),
                  title: Text(user?.nickname ?? strings.text('Not logged in')),
                  subtitle: Text(
                    [
                      if (user?.username.isNotEmpty == true)
                        '@${user!.username}',
                      if (user != null) 'UID ${user.uid}',
                      if (user?.onlineStatus.isNotEmpty == true)
                        user!.onlineStatus,
                    ].join(' | '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: user == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AccountSettingsScreen(state: state),
                            ),
                          );
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_none),
                    title: Text(strings.text('Unread notices')),
                    trailing: Badge(label: Text('${counts.notices}')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.alternate_email),
                    title: Text(strings.text('Mentions and replies')),
                    trailing: Badge(label: Text('${counts.mentions}')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: Text(strings.text('Friend changes')),
                    trailing: Badge(label: Text('${counts.friendChanges}')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.person_add_alt),
                    title: Text(strings.text('Friend requests')),
                    trailing: Badge(label: Text('${counts.friendRequests}')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.group_add_outlined),
                    title: Text(strings.text('Group reviews')),
                    trailing: Badge(label: Text('${counts.groupApplications}')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.refreshHome,
              icon: const Icon(Icons.sync),
              label: Text(strings.text('Refresh all')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(state: state),
                  ),
                );
              },
              icon: const Icon(Icons.settings_outlined),
              label: Text(strings.text('Settings')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => confirmLogout(context, state),
              icon: const Icon(Icons.logout),
              label: Text(strings.text('Logout')),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final imagePicker = ImagePicker();
  bool updatingNickname = false;
  bool updatingAvatar = false;
  bool updatingPassword = false;
  bool updatingPatAction = false;
  bool deletingAccount = false;

  Future<void> editNickname() async {
    final current = widget.state.user?.nickname ?? '';
    final nickname = await showDialog<String>(
      context: context,
      builder: (context) => _NicknameDialog(initialNickname: current),
    );
    if (nickname == null || !mounted) {
      return;
    }
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) {
      showSnack(context.strings.text('Please enter a nickname.'));
      return;
    }
    if (trimmed == current.trim()) {
      return;
    }
    setState(() => updatingNickname = true);
    try {
      await widget.state.updateNickname(trimmed);
      if (!mounted) {
        return;
      }
      showSnack(context.strings.text('Nickname updated.'));
      setState(() {});
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Update failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => updatingNickname = false);
      }
    }
  }

  Future<void> changeAvatar() async {
    if (updatingAvatar) {
      return;
    }
    final picked = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null || !mounted) {
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() => updatingAvatar = true);
    try {
      await widget.state.updateAvatar(bytes, picked.name);
      if (!mounted) {
        return;
      }
      showSnack(context.strings.text('Avatar updated.'));
      setState(() {});
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Update failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => updatingAvatar = false);
      }
    }
  }

  Future<void> changePassword() async {
    final result = await showDialog<_PasswordChange>(
      context: context,
      builder: (context) => const _PasswordChangeDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    if (result.oldPassword.isEmpty ||
        result.newPassword.isEmpty ||
        result.confirmPassword.isEmpty) {
      showSnack(context.strings.text('Please fill all password fields.'));
      return;
    }
    if (result.newPassword.length < 6) {
      showSnack(
        context.strings.text('New password must be at least 6 characters.'),
      );
      return;
    }
    if (result.newPassword != result.confirmPassword) {
      showSnack(context.strings.text('Passwords do not match.'));
      return;
    }
    setState(() => updatingPassword = true);
    try {
      await widget.state.updatePassword(
        result.oldPassword,
        result.newPassword,
        result.confirmPassword,
      );
      if (!mounted) {
        return;
      }
      showSnack(context.strings.text('Password updated.'));
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Update failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => updatingPassword = false);
      }
    }
  }

  Future<void> editPatAction() async {
    final current = widget.state.user?.patAction ?? defaultPatAction;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => _PatActionDialog(initialAction: current),
    );
    if (action == null || !mounted) {
      return;
    }
    final trimmed = action.trim();
    if (trimmed.isEmpty) {
      showSnack(context.strings.text('Please enter a pat action.'));
      return;
    }
    if (trimmed == current.trim()) {
      return;
    }
    setState(() => updatingPatAction = true);
    try {
      await widget.state.updatePatAction(trimmed);
      if (!mounted) {
        return;
      }
      showSnack(context.strings.text('Pat action updated.'));
      setState(() {});
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Update failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => updatingPatAction = false);
      }
    }
  }

  Future<void> deleteAccount() async {
    final strings = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => deletingAccount = true);
    try {
      await widget.state.deleteAccount();
      if (!mounted) {
        return;
      }
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.text('Account deleted.'))),
      );
    } catch (err) {
      if (mounted) {
        showSnack(
          context.strings.format('Delete failed: {error}', {'error': err}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => deletingAccount = false);
      }
    }
  }

  void showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget progressOrChevron(bool loading) {
    if (!loading) {
      return const Icon(Icons.chevron_right);
    }
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.user;
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Account settings'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _Avatar(
                      url: user?.avatar ?? '',
                      fallback: Icons.person_rounded,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.nickname ?? strings.text('Not logged in'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (user?.username.isNotEmpty == true)
                                '@${user!.username}',
                              if (user != null) 'UID ${user.uid}',
                            ].join(' | '),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(strings.text('Change nickname')),
                      subtitle: Text(user?.nickname ?? ''),
                      trailing: progressOrChevron(updatingNickname),
                      onTap: updatingNickname ? null : editNickname,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.add_a_photo_outlined),
                      title: Text(strings.text('Change avatar')),
                      subtitle: Text(
                        strings.text('Choose a new profile image'),
                      ),
                      trailing: progressOrChevron(updatingAvatar),
                      onTap: updatingAvatar ? null : changeAvatar,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.waving_hand_outlined),
                      title: Text(strings.text('Pat action')),
                      subtitle: Text(user?.patAction ?? defaultPatAction),
                      trailing: progressOrChevron(updatingPatAction),
                      onTap: updatingPatAction ? null : editPatAction,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_reset_outlined),
                      title: Text(strings.text('Change password')),
                      subtitle: Text(
                        strings.text('Update your login password'),
                      ),
                      trailing: progressOrChevron(updatingPassword),
                      onTap: updatingPassword ? null : changePassword,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              strings.text('Danger zone'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              child: _RoundedInkClip(
                child: ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    strings.text('Delete account'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: Text(
                    strings.text(
                      'Permanently delete this account and owned groups.',
                    ),
                  ),
                  trailing: deletingAccount
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: deletingAccount ? null : deleteAccount,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordChange {
  const _PasswordChange(
    this.oldPassword,
    this.newPassword,
    this.confirmPassword,
  );

  final String oldPassword;
  final String newPassword;
  final String confirmPassword;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController()..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final canDelete = controller.text.trim() == 'DELETE';
    return AlertDialog(
      title: Text(strings.text('Delete account?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.text(
              'This will permanently delete your account, messages and owned groups. This cannot be undone.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: strings.text('Type DELETE to confirm'),
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
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: canDelete ? () => Navigator.of(context).pop(true) : null,
          child: Text(strings.text('Delete account')),
        ),
      ],
    );
  }
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.initialNickname});

  final String initialNickname;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(context).pop(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Change nickname')),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 16,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: strings.text('New nickname'),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(onPressed: submit, child: Text(strings.text('Save'))),
      ],
    );
  }
}

class _PatActionDialog extends StatefulWidget {
  const _PatActionDialog({required this.initialAction});

  final String initialAction;

  @override
  State<_PatActionDialog> createState() => _PatActionDialogState();
}

class _PatActionDialogState extends State<_PatActionDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialAction);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(context).pop(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Pat action')),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 16,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: strings.text('Pat action'),
          helperText: strings.text('Used in double-tap avatar pats'),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(onPressed: submit, child: Text(strings.text('Save'))),
      ],
    );
  }
}

class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog();

  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  final oldPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();

  @override
  void dispose() {
    oldPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(context).pop(
      _PasswordChange(oldPassword.text, newPassword.text, confirmPassword.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('Change password')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPassword,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: strings.text('Old password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassword,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: strings.text('New password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassword,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: strings.text('Confirm password'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(onPressed: submit, child: Text(strings.text('Save'))),
      ],
    );
  }
}

class _ThemeColorOption {
  const _ThemeColorOption(this.label, this.color);

  final String label;
  final Color color;
}

class _CacheMetric {
  const _CacheMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
}

class _ThemeColorDot extends StatelessWidget {
  const _ThemeColorDot({required this.color, this.selected = false});

  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      child: selected
          ? Icon(
              Icons.check,
              size: 16,
              color:
                  ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            )
          : null,
    );
  }
}

class _ThemeColorButton extends StatelessWidget {
  const _ThemeColorButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ThemeColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.strings.text(option.label),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _ThemeColorDot(color: option.color, selected: selected),
        ),
      ),
    );
  }
}

class _FollowThemeColorButton extends StatelessWidget {
  const _FollowThemeColorButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.strings.text('Follow theme'),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primaryContainer, colors.surfaceContainerHigh],
              ),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check, size: 16, color: colors.onPrimaryContainer)
                : null,
          ),
        ),
      ),
    );
  }
}

class _ChatBubbleColorTrailing extends StatelessWidget {
  const _ChatBubbleColorTrailing({
    required this.colorValue,
    required this.fallback,
  });

  final int colorValue;
  final Color fallback;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ThemeColorDot(
          color: colorValue == defaultChatBubbleColorValue
              ? fallback
              : Color(colorValue),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}

class _ChatBubbleThemePreview extends StatelessWidget {
  const _ChatBubbleThemePreview({required this.preferences});

  final CsacPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.forum_outlined, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                strings.text('Chat bubble theme'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PreviewBubble(
          text: strings.text('Preview message'),
          mine: false,
          preferences: preferences,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: _PreviewBubble(
            text: strings.text('Preview message'),
            mine: true,
            preferences: preferences,
          ),
        ),
      ],
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    required this.text,
    required this.mine,
    required this.preferences,
  });

  final String text;
  final bool mine;
  final CsacPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fallback = mine
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final colorValue = mine
        ? preferences.ownChatBubbleColorValue
        : preferences.otherChatBubbleColorValue;
    final color =
        (colorValue == defaultChatBubbleColorValue
                ? fallback
                : Color(colorValue))
            .withValues(alpha: preferences.chatBubbleOpacity);
    final solidTextSource = Color.alphaBlend(
      color,
      theme.scaffoldBackgroundColor,
    );
    final textColor =
        ThemeData.estimateBrightnessForColor(solidTextSource) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: chatBubbleBorderRadius(
          preferences.chatBubbleCornerStyle,
          mine,
        ),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(text, style: TextStyle(color: textColor)),
      ),
    );
  }
}

class _CacheMetricTile extends StatelessWidget {
  const _CacheMetricTile({required this.metric});

  final _CacheMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 168,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(metric.icon, size: 20, color: colors.primary),
              const SizedBox(height: 10),
              Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                metric.detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _csacAppName = 'CsAC';
const _csacAppBranch = 'Leon';
const _csacSourceUrl =
    'https://github.com/Leonmmcoset/csac-terminal/tree/main/flutter/csac';
const _csacAuthorUrl = 'https://github.com/Leonmmcoset';

class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  int appNameTapCount = 0;
  DateTime? lastAppNameTap;

  Future<void> copySourceUrl(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copiedText = context.strings.text('Source link copied.');
    await Clipboard.setData(const ClipboardData(text: _csacSourceUrl));
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(copiedText)));
    }
  }

  Future<void> openSourceUrl(BuildContext context) async {
    final url = Uri.parse(_csacSourceUrl);
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      await copySourceUrl(context);
    }
  }

  Future<void> openAuthorUrl(BuildContext context) async {
    final url = Uri.parse(_csacAuthorUrl);
    final messenger = ScaffoldMessenger.of(context);
    final copiedText = context.strings.text('Author link copied.');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      await Clipboard.setData(const ClipboardData(text: _csacAuthorUrl));
      messenger.showSnackBar(SnackBar(content: Text(copiedText)));
    }
  }

  void handleAppNameTap(BuildContext context) {
    final now = DateTime.now();
    final previous = lastAppNameTap;
    if (previous == null ||
        now.difference(previous) > const Duration(seconds: 2)) {
      appNameTapCount = 0;
    }
    lastAppNameTap = now;
    appNameTapCount++;
    if (appNameTapCount >= 5) {
      appNameTapCount = 0;
      unawaited(openAuthorUrl(context));
    }
  }

  Widget infoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: SelectableText(value),
      trailing: trailing,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('App information'))),
      body: SafeArea(
        child: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final packageInfo = snapshot.data;
            final version = packageInfo?.version ?? '-';
            final buildNumber = packageInfo?.buildNumber ?? '-';
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            Icons.chat_bubble_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => handleAppNameTap(context),
                                child: Text(
                                  _csacAppName,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                strings.text('Third-party CsAC client'),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  child: _RoundedInkClip(
                    child: Column(
                      children: [
                        infoTile(
                          context,
                          icon: Icons.apps_outlined,
                          title: strings.text('App name'),
                          value: _csacAppName,
                        ),
                        const Divider(height: 1),
                        infoTile(
                          context,
                          icon: Icons.account_tree_outlined,
                          title: strings.text('Branch'),
                          value: _csacAppBranch,
                        ),
                        const Divider(height: 1),
                        infoTile(
                          context,
                          icon: Icons.numbers_outlined,
                          title: strings.text('Version'),
                          value: version,
                        ),
                        const Divider(height: 1),
                        infoTile(
                          context,
                          icon: Icons.build_outlined,
                          title: strings.text('Build number'),
                          value: buildNumber,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  child: _RoundedInkClip(
                    child: Column(
                      children: [
                        infoTile(
                          context,
                          icon: Icons.code,
                          title: strings.text('Source code'),
                          value: _csacSourceUrl,
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => openSourceUrl(context),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.copy),
                          title: Text(strings.text('Copy source link')),
                          onTap: () => copySourceUrl(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AppInfoSubtitle extends StatelessWidget {
  const _AppInfoSubtitle();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final packageInfo = snapshot.data;
        final version = packageInfo == null
            ? '-'
            : '${packageInfo.version}+${packageInfo.buildNumber}';
        return Text('CsAC $version | $_csacAppBranch');
      },
    );
  }
}

class OpenSourceLicensesScreen extends StatefulWidget {
  const OpenSourceLicensesScreen({super.key});

  @override
  State<OpenSourceLicensesScreen> createState() =>
      _OpenSourceLicensesScreenState();
}

class _OpenSourceLicensesScreenState extends State<OpenSourceLicensesScreen> {
  late final Future<List<_LicenseNotice>> licenses = loadLicenses();

  Future<List<_LicenseNotice>> loadLicenses() async {
    final licensesByPackage = <String, Set<String>>{};
    await for (final entry in LicenseRegistry.licenses) {
      final packages = entry.packages
          .map((package) => package.trim())
          .where((package) => package.isNotEmpty)
          .toSet();
      final body = entry.paragraphs
          .map((paragraph) => paragraph.text.trimRight())
          .where((text) => text.trim().isNotEmpty)
          .join('\n\n');
      if (body.trim().isEmpty) {
        continue;
      }
      final packageNames = packages.isEmpty
          ? const <String>{'Unknown package'}
          : packages;
      for (final package in packageNames) {
        licensesByPackage.putIfAbsent(package, () => <String>{}).add(body);
      }
    }
    final notices = licensesByPackage.entries.map((entry) {
      return _LicenseNotice(
        packages: <String>[entry.key],
        body: entry.value.join('\n\n----------\n\n'),
      );
    }).toList();
    notices.sort((a, b) => a.title.compareTo(b.title));
    return notices;
  }

  Future<void> copyLicense(_LicenseNotice license) async {
    await Clipboard.setData(
      ClipboardData(text: '${license.title}\n\n${license.body}'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('License copied.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Open-source licenses'))),
      body: SafeArea(
        child: FutureBuilder<List<_LicenseNotice>>(
          future: licenses,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(strings.text('Loading licenses...')),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return _InlineError(
                message: snapshot.error.toString(),
                onRetry: () => setState(() {}),
              );
            }
            final items = snapshot.data ?? const <_LicenseNotice>[];
            if (items.isEmpty) {
              return _EmptyPanel(message: strings.text('No licenses found.'));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    strings.format('{count} license notices', {
                      'count': items.length,
                    }),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final license in items)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: _RoundedInkClip(
                      child: ExpansionTile(
                        title: Text(license.title),
                        subtitle: Text(
                          strings.format('{count} packages', {
                            'count': license.packages.length,
                          }),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => copyLicense(license),
                              icon: const Icon(Icons.copy),
                              label: Text(strings.text('Copy')),
                            ),
                          ),
                          SelectableText(license.body),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AppLogsScreen extends StatefulWidget {
  const AppLogsScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<AppLogsScreen> createState() => _AppLogsScreenState();
}

class _AppLogsScreenState extends State<AppLogsScreen> {
  late Future<List<AppLogFile>> logs = widget.state.loadAppLogFiles();

  String formatLogBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final decimals = value >= 10 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }

  void refreshLogs() {
    setState(() => logs = widget.state.loadAppLogFiles());
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('App logs')),
        actions: [
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: refreshLogs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<AppLogFile>>(
          future: logs,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _InlineError(
                message: snapshot.error.toString(),
                onRetry: refreshLogs,
              );
            }
            final items = snapshot.data ?? const <AppLogFile>[];
            if (items.isEmpty) {
              return _EmptyPanel(message: strings.text('No app logs found.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final log = items[index];
                return Card(
                  elevation: 0,
                  child: _RoundedInkClip(
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(log.name),
                      subtitle: Text(
                        '${formatLogBytes(log.bytes)} | ${formatLocalDateTime(log.modified)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AppLogDetailScreen(
                              state: widget.state,
                              log: log,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class AppLogDetailScreen extends StatefulWidget {
  const AppLogDetailScreen({super.key, required this.state, required this.log});

  final CsacAppState state;
  final AppLogFile log;

  @override
  State<AppLogDetailScreen> createState() => _AppLogDetailScreenState();
}

class _AppLogDetailScreenState extends State<AppLogDetailScreen> {
  late Future<String> content = widget.state.readAppLogFile(widget.log);

  void refreshLog() {
    setState(() => content = widget.state.readAppLogFile(widget.log));
  }

  Future<void> copyLog(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Log copied.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.log.name),
        actions: [
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: refreshLog,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: content,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _InlineError(
                message: snapshot.error.toString(),
                onRetry: refreshLog,
              );
            }
            final text = snapshot.data ?? '';
            if (text.isEmpty) {
              return _EmptyPanel(message: strings.text('This log is empty.'));
            }
            return Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline),
                    title: SelectableText(widget.log.path),
                    subtitle: Text(
                      strings.text('Showing the latest part of this log.'),
                    ),
                    trailing: IconButton(
                      tooltip: strings.text('Copy'),
                      onPressed: () => copyLog(text),
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      text,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class NetworkDiagnosticsScreen extends StatefulWidget {
  const NetworkDiagnosticsScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<NetworkDiagnosticsScreen> createState() =>
      _NetworkDiagnosticsScreenState();
}

class _NetworkDiagnosticsScreenState extends State<NetworkDiagnosticsScreen> {
  late Future<NetworkDiagnosticReport> report = widget.state
      .runNetworkDiagnostics();

  void rerun() {
    setState(() => report = widget.state.runNetworkDiagnostics());
  }

  Future<void> copyReport(NetworkDiagnosticReport value) async {
    final buffer = StringBuffer()
      ..writeln('Server: ${value.serverUrl}')
      ..writeln('Origin: ${value.originUrl}')
      ..writeln('Started: ${formatLocalDateTime(value.startedAt)}')
      ..writeln('Total: ${value.totalMs} ms')
      ..writeln();
    for (final check in value.checks) {
      buffer.writeln(
        '[${check.ok ? 'OK' : 'FAIL'}] ${check.name} '
        '${check.elapsedMs} ms ${check.detail}',
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Diagnostic report copied.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('Connection diagnostics')),
        actions: [
          IconButton(
            tooltip: strings.text('Run again'),
            onPressed: rerun,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<NetworkDiagnosticReport>(
          future: report,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(strings.text('Running diagnostics...')),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return _InlineError(
                message: snapshot.error.toString(),
                onRetry: rerun,
              );
            }
            final value = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: value.passed
                              ? colors.primaryContainer
                              : colors.errorContainer,
                          child: Icon(
                            value.passed
                                ? Icons.check_rounded
                                : Icons.error_outline,
                            color: value.passed
                                ? colors.onPrimaryContainer
                                : colors.onErrorContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.text(
                                  value.passed
                                      ? 'Connection looks good'
                                      : 'Connection has issues',
                                ),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                strings.format('Total latency: {ms} ms', {
                                  'ms': value.totalMs,
                                }),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: strings.text('Copy'),
                          onPressed: () => copyReport(value),
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  child: _RoundedInkClip(
                    child: Column(
                      children: [
                        _DiagnosticInfoTile(
                          icon: Icons.dns_outlined,
                          label: strings.text('Server'),
                          value: value.serverUrl,
                        ),
                        const Divider(height: 1),
                        _DiagnosticInfoTile(
                          icon: Icons.public_outlined,
                          label: strings.text('Image origin'),
                          value: value.originUrl,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final check in value.checks)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        check.ok
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: check.ok ? colors.primary : colors.error,
                      ),
                      title: Text(strings.text(check.name)),
                      subtitle: SelectableText(
                        check.detail.isEmpty ? '-' : check.detail,
                      ),
                      trailing: Text('${check.elapsedMs} ms'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DiagnosticInfoTile extends StatelessWidget {
  const _DiagnosticInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: SelectableText(value),
    );
  }
}

class _LicenseNotice {
  const _LicenseNotice({required this.packages, required this.body});

  final List<String> packages;
  final String body;

  String get title =>
      packages.isEmpty ? 'Unknown package' : packages.join(', ');
}

class _PinPromptDialog extends StatefulWidget {
  const _PinPromptDialog({
    required this.title,
    required this.label,
    required this.confirm,
  });

  final String title;
  final String label;
  final bool confirm;

  @override
  State<_PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<_PinPromptDialog> {
  String pin = '';
  String pinConfirm = '';
  String? localError;
  bool confirming = false;

  String get activePin => confirming ? pinConfirm : pin;

  void updateActivePin(String value) {
    setState(() {
      if (confirming) {
        pinConfirm = value;
      } else {
        pin = value;
      }
      localError = null;
    });
    if (value.length >= 8) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && activePin.length >= 8) {
          submit();
        }
      });
    }
  }

  bool validateFirstPin() {
    if (AppLockPin.isValid(pin)) {
      return true;
    }
    setState(() {
      localError = context.strings.text('PIN must be 4-8 digits.');
    });
    return false;
  }

  void moveToConfirm() {
    if (!validateFirstPin()) {
      return;
    }
    setState(() {
      confirming = true;
      pinConfirm = '';
      localError = null;
    });
  }

  void submit() {
    if (widget.confirm && !confirming) {
      moveToConfirm();
      return;
    }
    if (!validateFirstPin()) {
      return;
    }
    if (widget.confirm && pin != pinConfirm) {
      setState(() {
        localError = context.strings.text('PINs do not match.');
        pinConfirm = '';
      });
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final activeLabel = widget.confirm && confirming
        ? strings.text('Confirm PIN')
        : strings.text(widget.label);
    return AlertDialog(
      title: Text(strings.text(widget.title)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PinEntryPad(
              value: activePin,
              onChanged: updateActivePin,
              label: activeLabel,
              helperText: strings.text(
                widget.confirm && confirming ? 'Enter PIN again' : '4-8 digits',
              ),
            ),
            if (localError != null) ...[
              const SizedBox(height: 12),
              Text(
                localError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        if (widget.confirm && confirming)
          TextButton(
            onPressed: () {
              setState(() {
                confirming = false;
                pinConfirm = '';
                localError = null;
              });
            },
            child: Text(strings.text('Back')),
          ),
        FilledButton(
          onPressed: AppLockPin.isValid(activePin) ? submit : null,
          child: Text(
            strings.text(widget.confirm && !confirming ? 'Next' : 'Save'),
          ),
        ),
      ],
    );
  }
}

class _BugReportDraft {
  const _BugReportDraft({required this.title, required this.description});

  final String title;
  final String description;
}

class _BugReportDialog extends StatefulWidget {
  const _BugReportDialog();

  @override
  State<_BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<_BugReportDialog> {
  final title = TextEditingController();
  final description = TextEditingController();

  @override
  void initState() {
    super.initState();
    title.addListener(() => setState(() {}));
    description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  void submit() {
    Navigator.of(
      context,
    ).pop(_BugReportDraft(title: title.text, description: description.text));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final canSubmit =
        title.text.trim().isNotEmpty && description.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(strings.text('Report a problem')),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: strings.text('Feedback title'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: strings.text('Feedback description'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(
          onPressed: canSubmit ? submit : null,
          child: Text(strings.text('Submit feedback')),
        ),
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.state,
    this.initialDeveloperOptionsExpanded = false,
  });

  final CsacAppState state;
  final bool initialDeveloperOptionsExpanded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController serverUrl;
  late final TextEditingController settingsSearch;
  late final ScrollController settingsScroll;
  bool clearing = false;
  bool refreshing = false;
  bool savingServer = false;
  bool loadingPerformanceStats = false;
  bool clearingPerformanceCaches = false;
  bool enablingLowPerformanceMode = false;
  bool submittingBugReport = false;
  PerformanceCacheStats? performanceStats;
  late bool developerOptionsExpanded;

  static const themeColorOptions = <_ThemeColorOption>[
    _ThemeColorOption('Emerald', Color(0xff1f8a70)),
    _ThemeColorOption('Blue', Color(0xff2563eb)),
    _ThemeColorOption('Violet', Color(0xff7c3aed)),
    _ThemeColorOption('Rose', Color(0xffe11d48)),
    _ThemeColorOption('Orange', Color(0xffea580c)),
    _ThemeColorOption('Teal', Color(0xff0f766e)),
    _ThemeColorOption('Indigo', Color(0xff4f46e5)),
    _ThemeColorOption('Slate', Color(0xff475569)),
  ];

  static const chatBubbleColorOptions = <_ThemeColorOption>[
    _ThemeColorOption('Emerald', Color(0xff1f8a70)),
    _ThemeColorOption('Blue', Color(0xff2563eb)),
    _ThemeColorOption('Teal', Color(0xff0f766e)),
    _ThemeColorOption('Indigo', Color(0xff4f46e5)),
    _ThemeColorOption('Violet', Color(0xff7c3aed)),
    _ThemeColorOption('Rose', Color(0xffe11d48)),
    _ThemeColorOption('Orange', Color(0xffea580c)),
    _ThemeColorOption('Slate', Color(0xff475569)),
    _ThemeColorOption('Mint', Color(0xff99f6e4)),
    _ThemeColorOption('Sky', Color(0xffbfdbfe)),
    _ThemeColorOption('Lavender', Color(0xffddd6fe)),
    _ThemeColorOption('Sand', Color(0xfffde68a)),
  ];

  @override
  void initState() {
    super.initState();
    settingsScroll = _desktopSmoothScrollController();
    serverUrl = TextEditingController(text: widget.state.preferences.serverUrl);
    settingsSearch = TextEditingController()..addListener(handleSearchChanged);
    developerOptionsExpanded = widget.initialDeveloperOptionsExpanded;
    unawaited(loadPerformanceStats());
  }

  @override
  void dispose() {
    settingsSearch.removeListener(handleSearchChanged);
    settingsSearch.dispose();
    serverUrl.dispose();
    settingsScroll.dispose();
    super.dispose();
  }

  void handleSearchChanged() {
    setState(() {});
  }

  bool settingMatches(String query, Iterable<String> keywords) {
    if (query.isEmpty) {
      return true;
    }
    final lowerQuery = query.toLowerCase();
    final strings = context.strings;
    return keywords.any((keyword) {
      final translated = strings.text(keyword).toLowerCase();
      return keyword.toLowerCase().contains(lowerQuery) ||
          translated.contains(lowerQuery);
    });
  }

  String get themeLabel {
    final strings = context.strings;
    switch (widget.state.preferences.themeMode) {
      case ThemeMode.system:
        return strings.text('System');
      case ThemeMode.light:
        return strings.text('Light');
      case ThemeMode.dark:
        return strings.text('Dark');
    }
  }

  String get languageLabel {
    switch (widget.state.preferences.language) {
      case CsacLanguage.en:
        return 'English';
      case CsacLanguage.zh:
        return '中文';
    }
  }

  String get fontStyleLabel {
    return fontStyleLabelFor(context, widget.state.preferences.fontStyle);
  }

  String get themeColorLabel {
    final selected = themeColorOptions.firstWhere(
      (option) =>
          option.color.toARGB32() == widget.state.preferences.themeColorValue,
      orElse: () => themeColorOptions.first,
    );
    return context.strings.text(selected.label);
  }

  String get conversationSortLabel {
    final strings = context.strings;
    switch (widget.state.preferences.conversationSortMode) {
      case ConversationSortMode.latest:
        return strings.text('Latest message');
      case ConversationSortMode.type:
        return strings.text('Conversation type');
    }
  }

  String get messageTimeFormatLabel {
    return messageTimeFormatLabelFor(
      context,
      widget.state.preferences.messageTimeFormat,
    );
  }

  String get chatBubbleCornerStyleLabel {
    return chatBubbleCornerStyleLabelFor(
      context,
      widget.state.preferences.chatBubbleCornerStyle,
    );
  }

  String chatBubbleColorLabel(int colorValue) {
    if (colorValue == defaultChatBubbleColorValue) {
      return context.strings.text('Follow theme');
    }
    final selected = chatBubbleColorOptions.firstWhere(
      (option) => option.color.toARGB32() == colorValue,
      orElse: () => _ThemeColorOption('Custom', Color(colorValue)),
    );
    return context.strings.text(selected.label);
  }

  String get chatBubbleOpacityLabel {
    final percent = (widget.state.preferences.chatBubbleOpacity * 100).round();
    return '$percent%';
  }

  String get chatBackgroundLabel {
    return widget.state.preferences.chatBackgroundPath.trim().isEmpty
        ? context.strings.text('Default background')
        : context.strings.text('Custom background');
  }

  String formatCacheBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final decimals = value >= 10 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unit]}';
  }

  List<_CacheMetric> performanceMetrics(PerformanceCacheStats stats) {
    final strings = context.strings;
    return [
      _CacheMetric(
        icon: Icons.forum_outlined,
        label: strings.text('Message cache'),
        value: formatCacheBytes(stats.messageCacheBytes),
        detail: strings.format(
          '{messages} messages, {conversations} conversations',
          {
            'messages': stats.messageCount,
            'conversations': stats.conversationCount,
          },
        ),
      ),
      _CacheMetric(
        icon: Icons.image_outlined,
        label: strings.text('Image cache'),
        value: formatCacheBytes(stats.imageCacheBytes),
        detail: strings.format('{count} cached image entries', {
          'count': stats.imageCacheEntries,
        }),
      ),
      _CacheMetric(
        icon: Icons.article_outlined,
        label: strings.text('Log files'),
        value: formatCacheBytes(stats.logBytes),
        detail: strings.text('Local diagnostic files'),
      ),
    ];
  }

  Future<void> loadPerformanceStats({bool showError = false}) async {
    if (!mounted || loadingPerformanceStats) {
      return;
    }
    setState(() => loadingPerformanceStats = true);
    try {
      final stats = await widget.state.loadPerformanceCacheStats();
      if (mounted) {
        setState(() => performanceStats = stats);
      }
    } catch (err) {
      if (!mounted || !showError) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Load cache stats failed: {error}', {
              'error': err,
            }),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => loadingPerformanceStats = false);
      }
    }
  }

  Future<void> refreshAll() async {
    setState(() => refreshing = true);
    try {
      await widget.state.refreshHome();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Refreshed.'))),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Refresh failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
      }
    }
  }

  Future<void> clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('Clear local cache?')),
        content: Text(
          context.strings.text(
            'Cached conversations and message history on this device will be removed. Your login session will be kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.strings.text('Clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => clearing = true);
    try {
      await widget.state.clearLocalCache();
      await loadPerformanceStats();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Local cache cleared.'))),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Clear cache failed: {error}', {
              'error': err,
            }),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => clearing = false);
      }
    }
  }

  Future<void> clearPerformanceCaches() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('Clear performance caches?')),
        content: Text(
          context.strings.text(
            'Message cache, image cache and log files will be removed. Your login session will be kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.strings.text('Clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => clearingPerformanceCaches = true);
    try {
      await widget.state.clearPerformanceCaches();
      await loadPerformanceStats();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Performance caches cleared.')),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Clear cache failed: {error}', {
              'error': err,
            }),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => clearingPerformanceCaches = false);
      }
    }
  }

  Future<void> enableLowPerformanceMode() async {
    setState(() => enablingLowPerformanceMode = true);
    try {
      await widget.state.enableLowPerformanceMode();
      await loadPerformanceStats();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Low performance mode enabled.')),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Save failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => enablingLowPerformanceMode = false);
      }
    }
  }

  Future<void> submitBugReport() async {
    final result = await showDialog<_BugReportDraft>(
      context: context,
      builder: (context) => const _BugReportDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    if (result.title.trim().isEmpty || result.description.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.text('Title and description are required.'),
          ),
        ),
      );
      return;
    }
    setState(() => submittingBugReport = true);
    try {
      await widget.state.submitBugReport(
        title: result.title,
        description: result.description,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Feedback submitted.'))),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Submit failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => submittingBugReport = false);
      }
    }
  }

  Future<void> logoutToLogin() async {
    await confirmLogout(context, widget.state);
  }

  Future<String?> promptPin({
    required String title,
    required String label,
    bool confirm = false,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) =>
          _PinPromptDialog(title: title, label: label, confirm: confirm),
    );
  }

  Future<bool> confirmCurrentAppLockPin() async {
    final pin = await promptPin(
      title: 'Enter current PIN',
      label: 'Current PIN',
    );
    if (pin == null) {
      return false;
    }
    if (widget.state.verifyAppLockPin(pin)) {
      return true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Incorrect PIN.'))),
      );
    }
    return false;
  }

  Future<void> enableAppLock() async {
    final pin = await promptPin(
      title: 'Set app lock PIN',
      label: 'PIN',
      confirm: true,
    );
    if (pin == null || !mounted) {
      return;
    }
    await widget.state.enableAppLock(pin: pin, biometricEnabled: false);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('App lock enabled.'))),
      );
    }
  }

  Future<void> changeAppLockPin() async {
    if (!await confirmCurrentAppLockPin() || !mounted) {
      return;
    }
    final pin = await promptPin(
      title: 'Change app lock PIN',
      label: 'New PIN',
      confirm: true,
    );
    if (pin == null || !mounted) {
      return;
    }
    await widget.state.enableAppLock(
      pin: pin,
      biometricEnabled: widget.state.preferences.appLockBiometricEnabled,
    );
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('PIN updated.'))),
      );
    }
  }

  Future<void> disableAppLock() async {
    if (!await confirmCurrentAppLockPin() || !mounted) {
      return;
    }
    await widget.state.disableAppLock();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('App lock disabled.'))),
      );
    }
  }

  Future<void> openAppLockSettings() async {
    if (!widget.state.preferences.effectiveAppLockEnabled) {
      await enableAppLock();
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: Text(context.strings.text('Biometric unlock')),
                subtitle: Text(
                  context.strings.text('Use device biometrics when available'),
                ),
                value: widget.state.preferences.appLockBiometricEnabled,
                onChanged: (value) => Navigator.of(
                  context,
                ).pop(value ? 'biometricOn' : 'biometricOff'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: Text(context.strings.text('Change PIN')),
                onTap: () => Navigator.of(context).pop('changePin'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: Text(context.strings.text('Disable app lock')),
                onTap: () => Navigator.of(context).pop('disable'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case 'biometricOn':
      case 'biometricOff':
        await widget.state.updateAppLockBiometric(action == 'biometricOn');
        if (mounted) {
          setState(() {});
        }
        break;
      case 'changePin':
        await changeAppLockPin();
        break;
      case 'disable':
        await disableAppLock();
        break;
    }
  }

  Future<void> saveServerUrl() async {
    setState(() => savingServer = true);
    try {
      final changed = await widget.state.updateServerUrl(serverUrl.text);
      if (!mounted) {
        return;
      }
      serverUrl.text = widget.state.preferences.serverUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.text(
              changed
                  ? 'Server address saved. Please log in again.'
                  : 'Server address is unchanged.',
            ),
          ),
        ),
      );
      setState(() {});
    } on FormatException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Invalid server address.')),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Save failed: {error}', {'error': err}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => savingServer = false);
      }
    }
  }

  void resetServerUrl() {
    serverUrl.clear();
  }

  Future<void> chooseTheme() async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: widget.state.preferences.themeMode == ThemeMode.system
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('System')),
                onTap: () => Navigator.of(context).pop(ThemeMode.system),
              ),
              ListTile(
                leading: widget.state.preferences.themeMode == ThemeMode.light
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Light')),
                onTap: () => Navigator.of(context).pop(ThemeMode.light),
              ),
              ListTile(
                leading: widget.state.preferences.themeMode == ThemeMode.dark
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Dark')),
                onTap: () => Navigator.of(context).pop(ThemeMode.dark),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateThemeMode(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseThemeColor() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.strings.text('Theme color'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final option in themeColorOptions)
                    _ThemeColorButton(
                      option: option,
                      selected:
                          option.color.toARGB32() ==
                          widget.state.preferences.themeColorValue,
                      onTap: () =>
                          Navigator.of(context).pop(option.color.toARGB32()),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateThemeColor(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseLanguage() async {
    final selected = await showModalBottomSheet<CsacLanguage>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: widget.state.preferences.language == CsacLanguage.en
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: const Text('English'),
                onTap: () => Navigator.of(context).pop(CsacLanguage.en),
              ),
              ListTile(
                leading: widget.state.preferences.language == CsacLanguage.zh
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: const Text('中文'),
                onTap: () => Navigator.of(context).pop(CsacLanguage.zh),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateLanguage(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseFontStyle() async {
    final selected = await showModalBottomSheet<CsacFontStyle>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in CsacFontStyle.values)
                ListTile(
                  leading: widget.state.preferences.fontStyle == style
                      ? const Icon(Icons.check)
                      : const SizedBox(width: 24),
                  title: Text(
                    fontStyleLabelFor(context, style),
                    style: TextStyle(
                      fontFamily: fontFamilyForStyle(style),
                      fontFamilyFallback: fontFamilyFallbackForStyle(style),
                    ),
                  ),
                  subtitle: Text(
                    fontStyleDescriptionFor(context, style),
                    style: TextStyle(
                      fontFamily: fontFamilyForStyle(style),
                      fontFamilyFallback: fontFamilyFallbackForStyle(style),
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(style),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateFontStyle(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseConversationSortMode() async {
    final selected = await showModalBottomSheet<ConversationSortMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    widget.state.preferences.conversationSortMode ==
                        ConversationSortMode.latest
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Latest message')),
                subtitle: Text(
                  context.strings.text('Show chats with recent activity first'),
                ),
                onTap: () =>
                    Navigator.of(context).pop(ConversationSortMode.latest),
              ),
              ListTile(
                leading:
                    widget.state.preferences.conversationSortMode ==
                        ConversationSortMode.type
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                title: Text(context.strings.text('Conversation type')),
                subtitle: Text(
                  context.strings.text('Group friends and groups separately'),
                ),
                onTap: () =>
                    Navigator.of(context).pop(ConversationSortMode.type),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateConversationSortMode(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseMessageTimeFormat() async {
    final selected = await showModalBottomSheet<MessageTimeFormat>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final format in MessageTimeFormat.values)
                ListTile(
                  leading: widget.state.preferences.messageTimeFormat == format
                      ? const Icon(Icons.check)
                      : const SizedBox(width: 24),
                  title: Text(messageTimeFormatLabelFor(context, format)),
                  subtitle: Text(messageTimeFormatExampleFor(format)),
                  onTap: () => Navigator.of(context).pop(format),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateMessageTimeFormat(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseChatBubbleCornerStyle() async {
    final selected = await showModalBottomSheet<ChatBubbleCornerStyle>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in ChatBubbleCornerStyle.values)
                ListTile(
                  leading:
                      widget.state.preferences.chatBubbleCornerStyle == style
                      ? const Icon(Icons.check)
                      : const SizedBox(width: 24),
                  title: Text(chatBubbleCornerStyleLabelFor(context, style)),
                  onTap: () => Navigator.of(context).pop(style),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.state.updateChatBubbleCornerStyle(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> chooseChatBubbleColor({required bool mine}) async {
    final title = mine ? 'Own bubble color' : 'Other bubble color';
    final current = mine
        ? widget.state.preferences.ownChatBubbleColorValue
        : widget.state.preferences.otherChatBubbleColorValue;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.strings.text(title),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _FollowThemeColorButton(
                    selected: current == defaultChatBubbleColorValue,
                    onTap: () =>
                        Navigator.of(context).pop(defaultChatBubbleColorValue),
                  ),
                  for (final option in chatBubbleColorOptions)
                    _ThemeColorButton(
                      option: option,
                      selected: option.color.toARGB32() == current,
                      onTap: () =>
                          Navigator.of(context).pop(option.color.toARGB32()),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      if (mine) {
        await widget.state.updateOwnChatBubbleColor(selected);
      } else {
        await widget.state.updateOtherChatBubbleColor(selected);
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> updateChatBubbleOpacity(double value) async {
    await widget.state.updateChatBubbleOpacity(value);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> chooseChatBackground() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _RoundedInkClip(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(context.strings.text('Choose background image')),
                onTap: () => Navigator.of(context).pop('choose'),
              ),
              if (widget.state.preferences.chatBackgroundPath.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(context.strings.text('Reset background')),
                  onTap: () => Navigator.of(context).pop('reset'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    if (action == 'reset') {
      await widget.state.updateChatBackgroundPath('');
      if (mounted) {
        setState(() {});
      }
      return;
    }
    final picked = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: context.strings.text('Images'),
          extensions: imageExtensions,
        ),
      ],
    );
    if (!mounted || picked == null) {
      return;
    }
    try {
      final path = await persistChatBackground(picked);
      await widget.state.updateChatBackgroundPath(path);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.strings.text('Chat background saved.')),
          ),
        );
      }
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Save failed: {error}', {'error': err}),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.user;
    final strings = context.strings;
    final query = settingsSearch.text.trim().toLowerCase();
    final showAccount = settingMatches(query, [
      'Account settings',
      'Username',
      'Nickname',
      'Avatar',
      'UID',
      'Profile',
    ]);
    final showInfo = settingMatches(query, [
      'App information',
      'Open-source licenses',
      'Version',
      'Source code',
      'License',
    ]);
    final showFeedback = settingMatches(query, [
      'Feedback',
      'Report a problem',
      'Bug report',
      'Problem',
      'Submit feedback',
    ]);
    final showAppearance = settingMatches(query, [
      'Theme',
      'Theme color',
      'Language',
      'Font style',
      'Font',
      'Typography',
      'Conversation sorting',
      'Message time format',
      'Chat bubble theme',
      'Own bubble color',
      'Other bubble color',
      'Bubble corner style',
      'Bubble opacity',
      'Chat background',
      'Background',
      'Show chat avatars',
      'Avatar',
      'Double tap avatar pat',
      'Pat',
      'Group member level',
      'Level',
      'Reduce motion',
      'Animation',
      'Motion',
    ]);
    final showLock = settingMatches(query, ['App lock', 'PIN', 'Security']);
    final showData = settingMatches(query, [
      'Refresh app data',
      'Connection diagnostics',
      'Network diagnostics',
      'Server latency',
      'API availability',
      'Login status',
      'Image domain',
      'Clear local cache',
      'Performance and cache',
      'Message cache',
      'Image cache',
      'Log files',
      'App logs',
      'View app logs',
      'Diagnostics',
      'Low performance mode',
      'Cache',
      'Cached conversations and message history',
    ]);
    final showDeveloper = settingMatches(query, [
      'Developer options',
      'CsAC server address',
      'Server',
      'Default server',
    ]);
    final showLogout = settingMatches(query, [
      'Logout',
      'Clear session and return to login',
      'Session',
    ]);
    final hasMatches =
        showAccount ||
        showInfo ||
        showFeedback ||
        showAppearance ||
        showLock ||
        showData ||
        showDeveloper ||
        showLogout;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Settings'))),
      body: SafeArea(
        child: ListView(
          controller: settingsScroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              controller: settingsSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: strings.text('Search settings'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: strings.text('Clear'),
                        onPressed: settingsSearch.clear,
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (showAccount) ...[
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: ListTile(
                    leading: _Avatar(
                      url: user?.avatar ?? '',
                      fallback: Icons.person_rounded,
                    ),
                    title: Text(
                      user?.nickname ?? strings.text('Not logged in'),
                    ),
                    subtitle: Text(
                      [
                        if (user?.username.isNotEmpty == true)
                          '@${user!.username}',
                        if (user != null) 'UID ${user.uid}',
                      ].join(' | '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: user == null
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AccountSettingsScreen(state: widget.state),
                              ),
                            );
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showInfo) ...[
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(strings.text('App information')),
                        subtitle: const _AppInfoSubtitle(),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AppInfoScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: Text(strings.text('Open-source licenses')),
                        subtitle: Text(
                          strings.text('View licenses for included libraries'),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const OpenSourceLicensesScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showFeedback) ...[
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: ListTile(
                    leading: const Icon(Icons.feedback_outlined),
                    title: Text(strings.text('Report a problem')),
                    subtitle: Text(
                      strings.text('Send app feedback to administrators'),
                    ),
                    trailing: submittingBugReport
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: submittingBugReport ? null : submitBugReport,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showAppearance) ...[
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.dark_mode_outlined),
                        title: Text(strings.text('Theme')),
                        subtitle: Text(themeLabel),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: chooseTheme,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.palette_outlined),
                        title: Text(strings.text('Theme color')),
                        subtitle: Text(themeColorLabel),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ThemeColorDot(
                              color: Color(
                                widget.state.preferences.themeColorValue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: chooseThemeColor,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.translate),
                        title: Text(strings.text('Language')),
                        subtitle: Text(languageLabel),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: chooseLanguage,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.text_fields),
                        title: Text(strings.text('Font style')),
                        subtitle: Text(fontStyleLabel),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: chooseFontStyle,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.sort),
                        title: Text(strings.text('Conversation sorting')),
                        subtitle: Text(conversationSortLabel),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: chooseConversationSortMode,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.schedule_outlined),
                        title: Text(strings.text('Message time format')),
                        subtitle: Text(messageTimeFormatLabel),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: chooseMessageTimeFormat,
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        child: _ChatBubbleThemePreview(
                          preferences: widget.state.preferences,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(strings.text('Own bubble color')),
                        subtitle: Text(
                          chatBubbleColorLabel(
                            widget.state.preferences.ownChatBubbleColorValue,
                          ),
                        ),
                        trailing: _ChatBubbleColorTrailing(
                          colorValue:
                              widget.state.preferences.ownChatBubbleColorValue,
                          fallback: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                        ),
                        onTap: () => chooseChatBubbleColor(mine: true),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(strings.text('Other bubble color')),
                        subtitle: Text(
                          chatBubbleColorLabel(
                            widget.state.preferences.otherChatBubbleColorValue,
                          ),
                        ),
                        trailing: _ChatBubbleColorTrailing(
                          colorValue: widget
                              .state
                              .preferences
                              .otherChatBubbleColorValue,
                          fallback: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                        ),
                        onTap: () => chooseChatBubbleColor(mine: false),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.rounded_corner),
                        title: Text(strings.text('Bubble corner style')),
                        subtitle: Text(chatBubbleCornerStyleLabel),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: chooseChatBubbleCornerStyle,
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            const Icon(Icons.opacity),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(strings.text('Bubble opacity')),
                                  Text(
                                    chatBubbleOpacityLabel,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  Slider(
                                    value: widget
                                        .state
                                        .preferences
                                        .chatBubbleOpacity,
                                    min: 0.45,
                                    max: 1,
                                    divisions: 11,
                                    label: chatBubbleOpacityLabel,
                                    onChanged: updateChatBubbleOpacity,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.wallpaper_outlined),
                        title: Text(strings.text('Chat background')),
                        subtitle: Text(chatBackgroundLabel),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: chooseChatBackground,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.account_circle_outlined),
                        title: Text(strings.text('Show chat avatars')),
                        subtitle: Text(
                          strings.text(
                            'Display sender avatars beside message bubbles',
                          ),
                        ),
                        value: widget.state.preferences.showChatAvatars,
                        onChanged: widget.state.updateShowChatAvatars,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.waving_hand_outlined),
                        title: Text(strings.text('Double tap avatar pat')),
                        subtitle: Text(
                          strings.text(
                            'Double tap a group member avatar to send a pat',
                          ),
                        ),
                        value: widget.state.preferences.enablePat,
                        onChanged: widget.state.updateEnablePat,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.military_tech_outlined),
                        title: Text(strings.text('Show group member level')),
                        subtitle: Text(
                          strings.text(
                            'Display member level beside names in group chats',
                          ),
                        ),
                        value: widget.state.preferences.showGroupMemberLevel,
                        onChanged: widget.state.updateShowGroupMemberLevel,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.motion_photos_off_outlined),
                        title: Text(strings.text('Reduce motion')),
                        subtitle: Text(
                          strings.text(
                            'Use simpler transitions and fewer decorative animations',
                          ),
                        ),
                        value: widget.state.preferences.reduceMotion,
                        onChanged: widget.state.updateReduceMotion,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showLock) ...[
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(strings.text('App lock')),
                    subtitle: Text(
                      widget.state.preferences.effectiveAppLockEnabled
                          ? strings.text('PIN required when returning to CsAC')
                          : strings.text('Off'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: openAppLockSettings,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showData) ...[
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.speed_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    strings.text('Performance and cache'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    performanceStats == null
                                        ? strings.text(
                                            'Measure local storage and memory cache',
                                          )
                                        : strings
                                              .format('Total cache: {size}', {
                                                'size': formatCacheBytes(
                                                  performanceStats!.totalBytes,
                                                ),
                                              }),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: strings.text('Refresh'),
                              onPressed: loadingPerformanceStats
                                  ? null
                                  : () => loadPerformanceStats(showError: true),
                              icon: loadingPerformanceStats
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      ),
                      if (performanceStats == null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: LinearProgressIndicator(
                            minHeight: 2,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final metric in performanceMetrics(
                                performanceStats!,
                              ))
                                _CacheMetricTile(metric: metric),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: enablingLowPerformanceMode
                                  ? null
                                  : enableLowPerformanceMode,
                              icon: enablingLowPerformanceMode
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.battery_saver_outlined),
                              label: Text(strings.text('Low performance mode')),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: clearingPerformanceCaches
                                  ? null
                                  : clearPerformanceCaches,
                              icon: clearingPerformanceCaches
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.auto_delete_outlined),
                              label: Text(
                                strings.text('Clear performance caches'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.sync),
                        title: Text(strings.text('Refresh app data')),
                        subtitle: Text(
                          strings.text('Reload conversations and counters'),
                        ),
                        trailing: refreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: refreshing ? null : refreshAll,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.network_check_outlined),
                        title: Text(strings.text('Connection diagnostics')),
                        subtitle: Text(
                          strings.text(
                            'Test server latency, API, login and image domain',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  NetworkDiagnosticsScreen(state: widget.state),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.article_outlined),
                        title: Text(strings.text('App logs')),
                        subtitle: Text(
                          strings.text('View local diagnostic logs'),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AppLogsScreen(state: widget.state),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.cleaning_services_outlined),
                        title: Text(strings.text('Clear local cache')),
                        subtitle: Text(
                          strings.text(
                            'Remove cached conversations and message history',
                          ),
                        ),
                        trailing: clearing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: clearing ? null : clearCache,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showDeveloper) ...[
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: ExpansionTile(
                    initiallyExpanded: developerOptionsExpanded,
                    onExpansionChanged: (value) {
                      setState(() => developerOptionsExpanded = value);
                    },
                    leading: const Icon(Icons.developer_mode_outlined),
                    title: Text(strings.text('Developer options')),
                    subtitle: Text(
                      strings.format('Current server: {server}', {
                        'server':
                            widget.state.preferences.serverUrl.trim().isEmpty
                            ? strings.text('Default server')
                            : widget.state.preferences.serverUrl.trim(),
                      }),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(
                        controller: serverUrl,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!savingServer) {
                            saveServerUrl();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: strings.text('CsAC server address'),
                          hintText: '192.168.1.10:8080',
                          helperText: strings.text(
                            'Leave empty to use the default server.',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 12,
                        overflowSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: savingServer ? null : resetServerUrl,
                            icon: const Icon(Icons.restart_alt),
                            label: Text(strings.text('Reset to default')),
                          ),
                          FilledButton.icon(
                            onPressed: savingServer ? null : saveServerUrl,
                            icon: savingServer
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(strings.text('Apply server')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (showLogout) ...[
              Card(
                elevation: 0,
                child: _RoundedInkClip(
                  child: ListTile(
                    leading: const Icon(Icons.logout),
                    title: Text(strings.text('Logout')),
                    subtitle: Text(
                      strings.text('Clear session and return to login'),
                    ),
                    onTap: logoutToLogin,
                  ),
                ),
              ),
            ],
            if (!hasMatches)
              _EmptyPanel(message: strings.text('No matching settings.')),
          ],
        ),
      ),
    );
  }
}
