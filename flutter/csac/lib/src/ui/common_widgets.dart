part of '../../main.dart';

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.fallback, this.radius});

  final String url;
  final IconData fallback;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return CircleAvatar(radius: radius, child: Icon(fallback));
    }
    return CircleAvatar(radius: radius, backgroundImage: NetworkImage(url));
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.pending});

  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(context.strings.text(pending ? 'Pending' : 'Handled')),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RoundedInkClip extends StatelessWidget {
  const _RoundedInkClip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(12),
      child: child,
    );
  }
}

Future<void> openUserProfile(
  BuildContext context,
  CsacAppState state,
  int uid, {
  GroupProfile? group,
  GroupMember? member,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => UserProfileScreen(
        state: state,
        uid: uid,
        group: group,
        member: member,
      ),
    ),
  );
}

Future<void> confirmLogout(
  BuildContext context,
  CsacAppState state, {
  bool popToRoot = true,
}) async {
  var keepLoginRecord = true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.strings.text('Sign out')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.strings.text(
                  'Choose whether this device should keep a passwordless login shortcut for this account.',
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: keepLoginRecord,
                onChanged: (value) {
                  setState(() => keepLoginRecord = value ?? true);
                },
                title: Text(
                  context.strings.text(
                    'Keep passwordless login on this device',
                  ),
                ),
                subtitle: Text(
                  context.strings.text(
                    'This stores the session cookie for quick login, but never stores your password.',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.strings.text('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.strings.text('Sign out')),
            ),
          ],
        ),
      );
    },
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  await state.logout(keepLoginRecord: keepLoginRecord);
  if (!context.mounted || !popToRoot) {
    return;
  }
  Navigator.of(context).popUntil((route) => route.isFirst);
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: onRetry,
          child: Text(context.strings.text('Retry')),
        ),
      ],
    );
  }
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.state,
    required this.type,
    required this.targetId,
    required this.targetName,
  });

  final CsacAppState state;
  final String type;
  final int targetId;
  final String targetName;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final reason = TextEditingController();
  bool anonymous = false;
  bool submitting = false;
  String? error;

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (reason.text.trim().length < 10) {
      setState(
        () => error = context.strings.text(
          'Reason must be at least 10 characters.',
        ),
      );
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await widget.state.submitReport(
        type: widget.type,
        targetId: widget.targetId,
        targetName: widget.targetName,
        reason: reason.text,
        anonymous: anonymous,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Report submitted.'))),
      );
      Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('Report'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                widget.type == 'group'
                    ? Icons.groups_outlined
                    : Icons.person_outline,
              ),
              title: Text(widget.targetName),
              subtitle: Text('${widget.type} #${widget.targetId}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: strings.text('Report reason'),
                helperText: strings.text('At least 10 characters.'),
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: anonymous,
              onChanged: (value) => setState(() => anonymous = value),
              title: Text(strings.text('Anonymous report')),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: submitting ? null : submit,
              icon: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.flag_outlined),
              label: Text(strings.text('Submit report')),
            ),
          ],
        ),
      ),
    );
  }
}
