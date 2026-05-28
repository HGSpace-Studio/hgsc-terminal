part of '../../main.dart';

enum _PendingSendStatus { sending, failed }

class _PendingSend {
  const _PendingSend({
    required this.localId,
    required this.text,
    this.imageBytes,
    this.imageName = '',
    this.voiceBytes,
    this.voiceName = '',
    this.voiceDuration = 0,
    this.replyTo = 0,
    this.mentionUids = const <int>[],
    this.status = _PendingSendStatus.sending,
    this.error = '',
  });

  final int localId;
  final String text;
  final Uint8List? imageBytes;
  final String imageName;
  final Uint8List? voiceBytes;
  final String voiceName;
  final int voiceDuration;
  final int replyTo;
  final List<int> mentionUids;
  final _PendingSendStatus status;
  final String error;

  bool get hasImage => imageBytes != null;
  bool get hasVoice => voiceBytes != null;

  _PendingSend copyWith({
    String? text,
    Uint8List? imageBytes,
    String? imageName,
    Uint8List? voiceBytes,
    String? voiceName,
    int? voiceDuration,
    int? replyTo,
    List<int>? mentionUids,
    _PendingSendStatus? status,
    String? error,
  }) {
    return _PendingSend(
      localId: localId,
      text: text ?? this.text,
      imageBytes: imageBytes ?? this.imageBytes,
      imageName: imageName ?? this.imageName,
      voiceBytes: voiceBytes ?? this.voiceBytes,
      voiceName: voiceName ?? this.voiceName,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      replyTo: replyTo ?? this.replyTo,
      mentionUids: mentionUids ?? this.mentionUids,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.state,
    required this.conversation,
    this.focusMessageId,
    this.embedded = false,
  });

  final CsacAppState state;
  final Conversation conversation;
  final int? focusMessageId;
  final bool embedded;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final scroll = ScrollController();
  final imagePicker = ImagePicker();
  final voicePlayer = AudioPlayer();
  final itemKeys = <int, GlobalKey>{};
  final messages = <ChatMessage>[];
  final pendingSends = <_PendingSend>[];
  final mentionTargets = <GroupMember>[];
  final selectedMessageIds = <int>{};
  Timer? timer;
  Timer? draftTimer;
  StreamSubscription<PlayerState>? voicePlayerStateSub;
  StreamSubscription<Duration?>? voiceDurationSub;
  StreamSubscription<Duration>? voicePositionSub;
  StreamSubscription<PlaybackEvent>? voicePlaybackEventSub;
  GroupProfile? groupProfile;
  ChatMessage? replyTarget;
  int? playingVoiceMessageId;
  final voiceCachePaths = <int, String>{};
  PlayerState voicePlayerState = PlayerState(false, ProcessingState.idle);
  Duration voiceDuration = Duration.zero;
  Duration voicePosition = Duration.zero;
  double voiceSpeed = 1;
  int initialUnreadCount = 0;
  int nextPendingId = -1;
  int refreshTicks = 0;
  bool loading = true;
  bool refreshing = false;
  bool pickingImage = false;
  bool pickingVoice = false;
  bool recordingVoice = false;
  bool applyingDraft = false;
  bool mentionPickerOpening = false;
  bool offline = false;
  bool nearBottom = true;
  String? error;

  bool get selectionMode => selectedMessageIds.isNotEmpty;

  List<ChatMessage> get selectedMessages {
    return messages
        .where((message) => selectedMessageIds.contains(message.id))
        .toList();
  }

  int? get firstUnreadMessageId {
    if (initialUnreadCount <= 0 || messages.isEmpty) {
      return null;
    }
    final index = (messages.length - initialUnreadCount).clamp(
      0,
      messages.length - 1,
    );
    return messages[index].id;
  }

  @override
  void initState() {
    super.initState();
    widget.state.setActiveConversation(widget.conversation);
    initialUnreadCount = widget.conversation.unreadCount;
    widget.state.markConversationRead(widget.conversation);
    input.addListener(scheduleDraftSave);
    input.addListener(handleMentionTrigger);
    scroll.addListener(handleScroll);
    bindVoicePlayer();
    loadDraft();
    loadGroupAnnouncement();
    loadInitial();
    timer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => refresh(silent: true),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    draftTimer?.cancel();
    unawaited(ConversationDraftStore.save(widget.conversation, input.text));
    if (widget.state.isActiveConversation(widget.conversation)) {
      widget.state.setActiveConversation(null);
    }
    scroll.removeListener(handleScroll);
    input.removeListener(scheduleDraftSave);
    input.removeListener(handleMentionTrigger);
    input.dispose();
    inputFocus.dispose();
    scroll.dispose();
    voicePlayerStateSub?.cancel();
    voiceDurationSub?.cancel();
    voicePositionSub?.cancel();
    voicePlaybackEventSub?.cancel();
    unawaited(voicePlayer.dispose());
    super.dispose();
  }

  void bindVoicePlayer() {
    voicePlayerStateSub = voicePlayer.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        voicePlayerState = state;
        if (state.processingState == ProcessingState.completed) {
          playingVoiceMessageId = null;
          voicePosition = Duration.zero;
        }
      });
    });
    voiceDurationSub = voicePlayer.durationStream.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() => voiceDuration = duration ?? Duration.zero);
    });
    voicePositionSub = voicePlayer.positionStream.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() => voicePosition = position);
    });
    voicePlaybackEventSub = voicePlayer.playbackEventStream.listen(
      (_) {},
      onError: (Object err, StackTrace stackTrace) {
        if (!mounted) {
          return;
        }
        setState(() {
          playingVoiceMessageId = null;
          voicePlayerState = PlayerState(false, ProcessingState.idle);
          voicePosition = Duration.zero;
          error = context.strings.format('Voice playback failed: {error}', {
            'error': err,
          });
        });
      },
    );
  }

  void handleScroll() {
    if (!scroll.hasClients) {
      return;
    }
    final distance = scroll.position.maxScrollExtent - scroll.offset;
    final next = distance < 96;
    if (next != nearBottom && mounted) {
      setState(() => nearBottom = next);
    }
  }

  Future<void> loadDraft() async {
    final draft = await ConversationDraftStore.load(widget.conversation);
    if (!mounted || input.text.isNotEmpty) {
      return;
    }
    applyingDraft = true;
    input
      ..text = draft
      ..selection = TextSelection.collapsed(offset: draft.length);
    applyingDraft = false;
  }

  void scheduleDraftSave() {
    if (applyingDraft) {
      return;
    }
    draftTimer?.cancel();
    draftTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(ConversationDraftStore.save(widget.conversation, input.text));
    });
  }

  void handleMentionTrigger() {
    if (widget.conversation.type != ConversationType.group ||
        mentionPickerOpening ||
        applyingDraft) {
      return;
    }
    final selection = input.selection;
    if (!selection.isValid || !selection.isCollapsed || selection.start <= 0) {
      return;
    }
    final text = input.text;
    final cursor = selection.start;
    if (cursor > text.length || text[cursor - 1] != '@') {
      return;
    }
    final beforeAt = cursor == 1 ? ' ' : text[cursor - 2];
    if (beforeAt.trim().isNotEmpty) {
      return;
    }
    mentionPickerOpening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await chooseMentionTargets();
      } finally {
        mentionPickerOpening = false;
      }
    });
  }

  Future<void> clearDraft() async {
    draftTimer?.cancel();
    await ConversationDraftStore.clear(widget.conversation);
  }

  Future<void> loadGroupAnnouncement() async {
    if (widget.conversation.type != ConversationType.group) {
      return;
    }
    try {
      final loaded = await widget.state.loadGroupProfile(
        widget.conversation.id,
      );
      if (!mounted) {
        return;
      }
      setState(() => groupProfile = loaded);
    } catch (_) {
      // The chat should remain usable even when the detail request fails.
    }
  }

  Future<void> markCurrentConversationRead() async {
    final lastMsgId = messages.isEmpty ? 0 : messages.last.id;
    await widget.state.markConversationRead(
      widget.conversation,
      lastMsgId: lastMsgId,
    );
  }

  Future<void> loadInitial() async {
    setState(() {
      loading = true;
      error = null;
      offline = false;
    });
    try {
      final focusId = widget.focusMessageId;
      final cached = focusId == null
          ? await widget.state.loadCachedMessages(widget.conversation)
          : await widget.state.loadCachedMessagesAround(
              widget.conversation,
              focusId,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        messages
          ..clear()
          ..addAll(cached);
        loading = cached.isEmpty;
      });
      if (cached.isNotEmpty) {
        scrollAfterLoad();
      }
      final loaded = cached.isEmpty
          ? await widget.state.loadMessagesFromNetwork(widget.conversation)
          : await widget.state.syncMessages(
              widget.conversation,
              afterId: cached.last.id,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        messages
          ..clear()
          ..addAll(mergeChatMessages(cached, loaded));
        offline = false;
      });
      await markCurrentConversationRead();
      scrollAfterLoad();
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        offline = messages.isNotEmpty;
        error = messages.isEmpty
            ? err.toString()
            : context.strings.format('Offline cache: {error}', {'error': err});
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> reloadConversationFromNetwork({bool showLoading = false}) async {
    if (!mounted) {
      return;
    }
    if (showLoading) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final loaded = await widget.state.reloadMessagesFromNetwork(
        widget.conversation,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        messages
          ..clear()
          ..addAll(loaded);
        offline = false;
      });
      await markCurrentConversationRead();
      scrollAfterLoad();
    } catch (err) {
      if (mounted) {
        setState(() {
          error = err.toString();
          offline = messages.isNotEmpty;
        });
      }
    } finally {
      if (showLoading && mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (!mounted || refreshing) {
      return;
    }
    refreshing = true;
    try {
      refreshTicks += 1;
      if (silent && refreshTicks % 8 == 0) {
        final loaded = await widget.state.reloadMessagesFromNetwork(
          widget.conversation,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          messages
            ..clear()
            ..addAll(loaded);
          offline = false;
        });
        await markCurrentConversationRead();
        return;
      }
      final afterId = messages.isEmpty ? 0 : messages.last.id;
      final loaded = await widget.state.syncMessages(
        widget.conversation,
        afterId: afterId,
      );
      if (loaded.isEmpty) {
        if (offline && mounted) {
          setState(() => offline = false);
        }
        return;
      }
      final merged = mergeChatMessages(messages, loaded);
      setState(() {
        messages
          ..clear()
          ..addAll(merged);
        offline = false;
      });
      await markCurrentConversationRead();
      if (widget.focusMessageId == null) {
        scrollToEnd();
      }
    } catch (err) {
      if (!mounted) {
        return;
      }
      if (!silent) {
        setState(() => error = err.toString());
      }
      if (mounted) {
        setState(() => offline = messages.isNotEmpty);
      }
    } finally {
      refreshing = false;
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) {
      return;
    }
    final pending = _PendingSend(
      localId: nextPendingId--,
      text: text,
      replyTo: replyTarget?.id ?? 0,
      mentionUids: mentionTargets.map((member) => member.uid).toList(),
    );
    setState(() {
      pendingSends.add(pending);
      input.clear();
      replyTarget = null;
      mentionTargets.clear();
      error = null;
    });
    await clearDraft();
    scrollToEnd();
    unawaited(performPendingSend(pending.localId));
  }

  Future<void> pickAndSendImage() async {
    if (pickingImage) {
      return;
    }
    setState(() => pickingImage = true);
    final picked = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (!mounted) {
      return;
    }
    setState(() => pickingImage = false);
    if (picked == null) {
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }
    final caption = await showDialog<String>(
      context: context,
      builder: (context) =>
          _ImageCaptionDialog(fileName: picked.name, bytes: bytes),
    );
    if (caption == null) {
      return;
    }
    final pending = _PendingSend(
      localId: nextPendingId--,
      text: caption.trim(),
      imageBytes: bytes,
      imageName: picked.name,
      replyTo: replyTarget?.id ?? 0,
      mentionUids: mentionTargets.map((member) => member.uid).toList(),
    );
    setState(() {
      pendingSends.add(pending);
      replyTarget = null;
      mentionTargets.clear();
      error = null;
    });
    scrollToEnd();
    unawaited(performPendingSend(pending.localId));
  }

  Future<void> pickAndSendVoice() async {
    if (pickingVoice) {
      return;
    }
    setState(() => pickingVoice = true);
    try {
      final picked = await openFile(
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: context.strings.text('Audio files'),
            extensions: const <String>[
              'mp3',
              'm4a',
              'aac',
              'wav',
              'ogg',
              'webm',
              'amr',
            ],
          ),
        ],
      );
      if (!mounted || picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }
      final duration = await askVoiceDuration(picked.name);
      if (duration == null || !mounted) {
        return;
      }
      final pending = _PendingSend(
        localId: nextPendingId--,
        text: '',
        voiceBytes: bytes,
        voiceName: picked.name,
        voiceDuration: duration,
        replyTo: replyTarget?.id ?? 0,
      );
      setState(() {
        pendingSends.add(pending);
        replyTarget = null;
        mentionTargets.clear();
        error = null;
      });
      scrollToEnd();
      unawaited(performPendingSend(pending.localId));
    } finally {
      if (mounted) {
        setState(() => pickingVoice = false);
      }
    }
  }

  Future<void> recordAndSendVoice() async {
    if (recordingVoice) {
      return;
    }
    setState(() => recordingVoice = true);
    try {
      final recorded = await showDialog<_RecordedVoice>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _VoiceRecorderDialog(),
      );
      if (!mounted || recorded == null) {
        return;
      }
      final file = File(recorded.path);
      if (!await file.exists()) {
        if (mounted) {
          setState(
            () => error = context.strings.text('Recording file missing.'),
          );
        }
        return;
      }
      final bytes = await file.readAsBytes();
      final pending = _PendingSend(
        localId: nextPendingId--,
        text: '',
        voiceBytes: bytes,
        voiceName: p.basename(recorded.path),
        voiceDuration: recorded.durationSeconds,
        replyTo: replyTarget?.id ?? 0,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        pendingSends.add(pending);
        replyTarget = null;
        mentionTargets.clear();
        error = null;
      });
      scrollToEnd();
      unawaited(performPendingSend(pending.localId));
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => recordingVoice = false);
      }
    }
  }

  Future<int?> askVoiceDuration(String fileName) async {
    final controller = TextEditingController(text: '0');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.strings.format('Send voice: {fileName}', {
            'fileName': fileName,
          }),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.strings.text('Duration seconds'),
            helperText: context.strings.text('Use 0 if unknown.'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(math.max(0, int.tryParse(controller.text.trim()) ?? 0)),
            child: Text(context.strings.text('Send')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> performPendingSend(int localId) async {
    final pending = pendingSends
        .where((item) => item.localId == localId)
        .firstOrNull;
    if (pending == null) {
      return;
    }
    replacePendingSend(
      localId,
      (item) => item.copyWith(status: _PendingSendStatus.sending, error: ''),
    );
    try {
      if (pending.hasImage) {
        await widget.state.client.sendImageMessage(
          widget.conversation,
          pending.imageBytes!,
          pending.imageName,
          caption: pending.text,
          replyTo: pending.replyTo,
          mentionUids: pending.mentionUids,
        );
      } else if (pending.hasVoice) {
        await widget.state.client.sendVoiceMessage(
          widget.conversation,
          pending.voiceBytes!,
          pending.voiceName,
          duration: pending.voiceDuration,
          replyTo: pending.replyTo,
        );
      } else {
        await widget.state.client.sendMessage(
          widget.conversation,
          pending.text,
          replyTo: pending.replyTo,
          mentionUids: pending.mentionUids,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        pendingSends.removeWhere((item) => item.localId == localId);
      });
      await widget.state.markConversationRead(widget.conversation);
      await refresh(silent: true);
      scrollToEnd();
    } catch (err) {
      replacePendingSend(
        localId,
        (item) => item.copyWith(
          status: _PendingSendStatus.failed,
          error: err.toString(),
        ),
      );
    }
  }

  void replacePendingSend(
    int localId,
    _PendingSend Function(_PendingSend item) update,
  ) {
    if (!mounted) {
      return;
    }
    final index = pendingSends.indexWhere((item) => item.localId == localId);
    if (index < 0) {
      return;
    }
    setState(() => pendingSends[index] = update(pendingSends[index]));
  }

  void retryPendingSend(int localId) {
    unawaited(performPendingSend(localId));
  }

  void clearComposeTargets() {
    if (!mounted) {
      return;
    }
    setState(() {
      replyTarget = null;
      mentionTargets.clear();
    });
  }

  void setReplyTarget(ChatMessage message) {
    setState(() => replyTarget = message);
  }

  Future<void> chooseMentionTargets() async {
    if (widget.conversation.type != ConversationType.group) {
      return;
    }
    try {
      final members = await widget.state.loadGroupMembers(
        widget.conversation.id,
      );
      if (!mounted) {
        return;
      }
      final selected = await showModalBottomSheet<List<GroupMember>>(
        context: context,
        showDragHandle: true,
        builder: (context) => _MentionPickerSheet(
          members: members,
          selectedUids: mentionTargets.map((member) => member.uid).toSet(),
        ),
      );
      if (selected == null || !mounted) {
        return;
      }
      setState(() {
        mentionTargets
          ..clear()
          ..addAll(selected);
      });
      replaceMentionTriggerWithSelection(selected);
      inputFocus.requestFocus();
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    }
  }

  void replaceMentionTriggerWithSelection(List<GroupMember> selected) {
    if (selected.isEmpty) {
      return;
    }
    final selection = input.selection;
    if (!selection.isValid || selection.start <= 0) {
      return;
    }
    final cursor = selection.start;
    final text = input.text;
    if (cursor > text.length || text[cursor - 1] != '@') {
      return;
    }
    final names = selected.map((member) => '@${member.name}').join(' ');
    final replacement = '$names ';
    final nextText = text.replaceRange(cursor - 1, cursor, replacement);
    final nextOffset = cursor - 1 + replacement.length;
    input.value = input.value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  void replaceMessageLocally(ChatMessage replacement) {
    final index = messages.indexWhere(
      (message) => message.id == replacement.id,
    );
    if (index < 0) {
      return;
    }
    setState(() => messages[index] = replacement);
  }

  Future<void> recallMessage(ChatMessage message) async {
    final recalledBody = context.strings.text('[recalled]');
    try {
      await widget.state.recallMessage(widget.conversation, message.id);
      final recalled = message.copyWith(
        body: recalledBody,
        imageUrl: '',
        canRecall: false,
        isRecalled: true,
      );
      replaceMessageLocally(recalled);
      await widget.state.cache.saveMessages(widget.conversation, [recalled]);
      await reloadConversationFromNetwork();
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    }
  }

  Future<void> toggleEssence(ChatMessage message) async {
    if (widget.conversation.type != ConversationType.group) {
      return;
    }
    try {
      await widget.state.toggleEssence(widget.conversation.id, message.id);
      final updated = message.copyWith(isEssence: !message.isEssence);
      replaceMessageLocally(updated);
      await widget.state.cache.saveMessages(widget.conversation, [updated]);
      await reloadConversationFromNetwork();
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    }
  }

  Future<void> openEssenceList() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EssenceMessagesScreen(
          state: widget.state,
          conversation: widget.conversation,
        ),
      ),
    );
  }

  Future<void> showMessageActions(ChatMessage message, bool mine) async {
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => _MessageActionSheet(
        message: message,
        canRecall: message.canRecall || mine,
        canEssence: widget.conversation.type == ConversationType.group,
      ),
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _MessageAction.select:
        enterSelection(message);
        break;
      case _MessageAction.copyText:
        final time = displayMessageTime(message, widget.state.preferences);
        Clipboard.setData(
          ClipboardData(
            text: '#${message.id} ${message.sender}\n$time\n\n${message.body}',
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.text('Message copied'))),
        );
        break;
      case _MessageAction.copyImage:
        Clipboard.setData(ClipboardData(text: message.imageUrl));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.text('Image link copied'))),
        );
        break;
      case _MessageAction.openImage:
        showImagePreview(context, message.imageUrl);
        break;
      case _MessageAction.downloadImage:
        await downloadImage(context, message.imageUrl);
        break;
      case _MessageAction.reply:
        setReplyTarget(message);
        break;
      case _MessageAction.recall:
        await recallMessage(message);
        break;
      case _MessageAction.essence:
        await toggleEssence(message);
        break;
    }
  }

  void openConversationDetails() {
    if (widget.conversation.type == ConversationType.private) {
      openUserProfile(context, widget.state, widget.conversation.id);
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationDetailScreen(
              state: widget.state,
              conversation: widget.conversation,
            ),
          ),
        )
        .then((_) => loadGroupAnnouncement());
  }

  Future<void> openMediaCenter() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationMediaScreen(
          state: widget.state,
          conversation: widget.conversation,
        ),
      ),
    );
  }

  Future<void> showComposeMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(context.strings.text('Image')),
              onTap: () => Navigator.of(context).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.mic),
              title: Text(context.strings.text('Record voice')),
              onTap: () => Navigator.of(context).pop('recordVoice'),
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: Text(context.strings.text('Choose audio file')),
              onTap: () => Navigator.of(context).pop('voiceFile'),
            ),
            if (widget.conversation.type == ConversationType.group)
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: Text(context.strings.text('Mention')),
                onTap: () => Navigator.of(context).pop('mention'),
              ),
            if (widget.conversation.type == ConversationType.group)
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: Text(context.strings.text('Essence')),
                onTap: () => Navigator.of(context).pop('essence'),
              ),
            ListTile(
              leading: const Icon(Icons.perm_media_outlined),
              title: Text(context.strings.text('Media and files')),
              onTap: () => Navigator.of(context).pop('media'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case 'image':
        await pickAndSendImage();
        break;
      case 'recordVoice':
        await recordAndSendVoice();
        break;
      case 'voiceFile':
        await pickAndSendVoice();
        break;
      case 'mention':
        await chooseMentionTargets();
        break;
      case 'essence':
        await openEssenceList();
        break;
      case 'media':
        await openMediaCenter();
        break;
    }
  }

  void enterSelection(ChatMessage message) {
    setState(() {
      selectedMessageIds
        ..clear()
        ..add(message.id);
    });
  }

  void toggleMessageSelection(ChatMessage message) {
    setState(() {
      if (selectedMessageIds.contains(message.id)) {
        selectedMessageIds.remove(message.id);
      } else {
        selectedMessageIds.add(message.id);
      }
    });
  }

  void clearSelection() {
    setState(() => selectedMessageIds.clear());
  }

  Future<void> copySelectedMessages() async {
    final selected = selectedMessages..sort((a, b) => a.id.compareTo(b.id));
    if (selected.isEmpty) {
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: selected.map(formatMessageForCopy).join('\n\n')),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.strings.text('Selected messages copied.')),
      ),
    );
  }

  Future<void> deleteSelectedLocalMessages() async {
    final selected = selectedMessages;
    if (selected.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.strings.text('Delete selected local messages?')),
        content: Text(
          context.strings.text('Only local cached copies will be removed.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.strings.text('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.strings.text('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final ids = selected.map((message) => message.id).toSet();
    try {
      await widget.state.cache.deleteMessages(widget.conversation, ids);
      if (!mounted) {
        return;
      }
      setState(() {
        messages.removeWhere((message) => ids.contains(message.id));
        selectedMessageIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.text('Local messages deleted.')),
        ),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() => error = err.toString());
    }
  }

  Future<void> forwardSelectedMessages() async {
    final selected = selectedMessages..sort((a, b) => a.id.compareTo(b.id));
    if (selected.isEmpty) {
      return;
    }
    final target = await showModalBottomSheet<Conversation>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ForwardConversationSheet(
        conversations: widget.state.conversations
            .where(
              (conversation) =>
                  conversation.type != widget.conversation.type ||
                  conversation.id != widget.conversation.id,
            )
            .toList(),
      ),
    );
    if (target == null || !mounted) {
      return;
    }
    try {
      final body = selected.map(formatMessageForForward).join('\n\n');
      await widget.state.client.sendMessage(target, body);
      if (!mounted) {
        return;
      }
      setState(() => selectedMessageIds.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.text('Forwarded.'))),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.format('Forward failed: {error}', {'error': err}),
          ),
        ),
      );
    }
  }

  String formatMessageForCopy(ChatMessage message) {
    final time = displayMessageTime(message, widget.state.preferences);
    return [
      '#${message.id} ${message.sender}',
      if (time.isNotEmpty) time,
      if (message.body.trim().isNotEmpty) message.body.trim(),
      if (message.imageUrl.isNotEmpty) message.imageUrl,
      if (message.voiceUrl.isNotEmpty) message.voiceUrl,
    ].join('\n');
  }

  String formatMessageForForward(ChatMessage message) {
    return [
      '${message.sender}:',
      if (message.body.trim().isNotEmpty) message.body.trim(),
      if (message.imageUrl.isNotEmpty)
        context.strings.format('Image: {url}', {'url': message.imageUrl}),
      if (message.voiceUrl.isNotEmpty)
        context.strings.format('Voice: {url}', {'url': message.voiceUrl}),
    ].join('\n');
  }

  bool isVoicePlaying(ChatMessage message) {
    return playingVoiceMessageId == message.id &&
        voicePlayerState.playing &&
        voicePlayerState.processingState != ProcessingState.completed;
  }

  Future<void> toggleVoicePlayback(ChatMessage message) async {
    if (message.voiceUrl.isEmpty) {
      return;
    }
    try {
      if (playingVoiceMessageId == message.id) {
        if (voicePlayerState.playing) {
          await voicePlayer.pause();
        } else {
          await voicePlayer.setSpeed(voiceSpeed);
          await voicePlayer.play();
        }
        return;
      }
      await voicePlayer.stop();
      final voicePath = await cachedVoicePath(message);
      if (!mounted) {
        return;
      }
      setState(() {
        playingVoiceMessageId = message.id;
        voiceDuration = message.voiceDuration > 0
            ? Duration(seconds: message.voiceDuration)
            : Duration.zero;
        voicePosition = Duration.zero;
        voicePlayerState = PlayerState(true, ProcessingState.loading);
      });
      final loadedDuration = await voicePlayer.setFilePath(voicePath);
      await voicePlayer.setSpeed(voiceSpeed);
      if (mounted && loadedDuration != null) {
        setState(() => voiceDuration = loadedDuration);
      }
      await voicePlayer.play();
    } catch (err) {
      if (mounted) {
        setState(() {
          playingVoiceMessageId = null;
          voicePlayerState = PlayerState(false, ProcessingState.idle);
          voicePosition = Duration.zero;
          error = context.strings.format('Voice playback failed: {error}', {
            'error': err,
          });
        });
      }
    }
  }

  Future<String> cachedVoicePath(ChatMessage message) async {
    final existing = voiceCachePaths[message.id];
    if (existing != null &&
        await File(existing).exists() &&
        !await fileLooksLikeHtml(existing)) {
      return existing;
    }
    final uri = Uri.parse(message.voiceUrl);
    final extension = p.extension(uri.path).isEmpty
        ? '.m4a'
        : p.extension(uri.path);
    final directory = await getTemporaryDirectory();
    final path = p.join(directory.path, 'csac_voice_${message.id}$extension');
    final file = File(path);
    if (await file.exists() &&
        await file.length() > 0 &&
        !await fileLooksLikeHtml(file.path)) {
      voiceCachePaths[message.id] = path;
      return path;
    }
    final bytes = await widget.state.client.getBinary(
      uri.toString(),
      accept: 'audio/*, application/octet-stream, */*',
    );
    await file.writeAsBytes(bytes, flush: true);
    voiceCachePaths[message.id] = path;
    return path;
  }

  Future<bool> fileLooksLikeHtml(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }
    final stream = file.openRead(0, math.min(256, await file.length()));
    final bytes = await stream.expand((chunk) => chunk).toList();
    final text = String.fromCharCodes(bytes).trimLeft().toLowerCase();
    return text.startsWith('<!doctype html') ||
        text.startsWith('<html') ||
        text.startsWith('<script');
  }

  Future<void> seekVoice(Duration position) async {
    final duration = voiceDuration;
    if (duration <= Duration.zero) {
      return;
    }
    final clamped = position < Duration.zero
        ? Duration.zero
        : position > duration
        ? duration
        : position;
    await voicePlayer.seek(clamped);
    if (mounted) {
      setState(() => voicePosition = clamped);
    }
  }

  Future<void> cycleVoiceSpeed() async {
    const speeds = <double>[1, 1.25, 1.5, 2];
    final index = speeds.indexWhere(
      (speed) => (speed - voiceSpeed).abs() < 0.01,
    );
    final nextSpeed = speeds[(index + 1) % speeds.length];
    setState(() => voiceSpeed = nextSpeed);
    await voicePlayer.setSpeed(nextSpeed);
  }

  Duration displayVoiceDuration(ChatMessage message) {
    if (playingVoiceMessageId == message.id && voiceDuration > Duration.zero) {
      return voiceDuration;
    }
    if (message.voiceDuration > 0) {
      return Duration(seconds: message.voiceDuration);
    }
    return Duration.zero;
  }

  void scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) {
        return;
      }
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void jumpToEnd() {
    if (!scroll.hasClients) {
      return;
    }
    scroll.animateTo(
      scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void scrollAfterLoad() {
    final focusId = widget.focusMessageId;
    if (focusId == null) {
      scrollToEnd();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final keyContext = itemKeys[focusId]?.currentContext;
      if (keyContext == null) {
        scrollToEnd();
        return;
      }
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        alignment: 0.42,
      );
    });
  }

  void scrollToMessage(int messageId) {
    final keyContext = itemKeys[messageId]?.currentContext;
    if (keyContext == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.text('Referenced message is not loaded.'),
          ),
        ),
      );
      return;
    }
    Scrollable.ensureVisible(
      keyContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: 0.42,
    );
  }

  void scrollToFirstUnread() {
    final messageId = firstUnreadMessageId;
    if (messageId == null) {
      return;
    }
    scrollToMessage(messageId);
    setState(() => initialUnreadCount = 0);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final announcement = groupProfile?.notice.trim() ?? '';
    final showEmpty = !loading && messages.isEmpty && pendingSends.isEmpty;
    final unreadMessageId = firstUnreadMessageId;
    final backgroundPath = widget.state.preferences.chatBackgroundPath.trim();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded && !selectionMode,
        leading: selectionMode
            ? IconButton(
                tooltip: strings.text('Cancel selection'),
                onPressed: clearSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          selectionMode
              ? strings.format('{count} messages selected', {
                  'count': selectedMessageIds.length,
                })
              : widget.conversation.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: selectionMode
            ? [
                IconButton(
                  tooltip: strings.text('Copy selected'),
                  onPressed: copySelectedMessages,
                  icon: const Icon(Icons.copy),
                ),
                IconButton(
                  tooltip: strings.text('Forward'),
                  onPressed: forwardSelectedMessages,
                  icon: const Icon(Icons.forward_outlined),
                ),
                IconButton(
                  tooltip: strings.text('Delete local copies'),
                  onPressed: deleteSelectedLocalMessages,
                  icon: const Icon(Icons.delete_outline),
                ),
              ]
            : [
                if (offline)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.cloud_off_outlined),
                  ),
                IconButton(
                  tooltip: strings.text('Refresh'),
                  onPressed: () =>
                      reloadConversationFromNetwork(showLoading: true),
                  icon: const Icon(Icons.refresh),
                ),
                if (widget.conversation.type == ConversationType.group)
                  IconButton(
                    tooltip: strings.text('Essence'),
                    onPressed: openEssenceList,
                    icon: const Icon(Icons.star_outline),
                  ),
                IconButton(
                  tooltip: strings.text('Media and files'),
                  onPressed: openMediaCenter,
                  icon: const Icon(Icons.perm_media_outlined),
                ),
                IconButton(
                  tooltip: strings.text('Details'),
                  onPressed: openConversationDetails,
                  icon: const Icon(Icons.info_outline),
                ),
              ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Column(
          children: [
            if (error != null)
              MaterialBanner(
                content: Text(error!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => error = null),
                    child: Text(strings.text('Dismiss')),
                  ),
                ],
              ),
            if (announcement.isNotEmpty)
              _GroupAnnouncementBar(
                announcement: announcement,
                onTap: openConversationDetails,
              ),
            if (unreadMessageId != null)
              Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: InkWell(
                  onTap: scrollToFirstUnread,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mark_chat_unread_outlined,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            strings.format('Jump to {count} unread messages', {
                              'count': initialUnreadCount,
                            }),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _ChatBackground(path: backgroundPath)),
                  loading
                      ? const Center(child: CircularProgressIndicator())
                      : showEmpty
                      ? _EmptyPanel(message: strings.text('No messages.'))
                      : ListView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 76),
                          itemCount: messages.length + pendingSends.length,
                          itemBuilder: (context, index) {
                            if (index >= messages.length) {
                              final pending =
                                  pendingSends[index - messages.length];
                              return _PendingMessageBubble(
                                pending: pending,
                                onRetry: () =>
                                    retryPendingSend(pending.localId),
                              );
                            }
                            final message = messages[index];
                            final mine =
                                widget.state.user?.uid == message.senderId;
                            final selected = selectedMessageIds.contains(
                              message.id,
                            );
                            final replyMessage = messages
                                .where((item) => item.id == message.replyTo)
                                .cast<ChatMessage?>()
                                .firstOrNull;
                            return _MessageBubble(
                              key: itemKeys.putIfAbsent(
                                message.id,
                                () => GlobalKey(),
                              ),
                              message: message,
                              replyMessage: replyMessage,
                              mine: mine,
                              focused: widget.focusMessageId == message.id,
                              selected: selected,
                              selectionMode: selectionMode,
                              preferences: widget.state.preferences,
                              onTap: selectionMode
                                  ? () => toggleMessageSelection(message)
                                  : null,
                              onLongPress: selectionMode
                                  ? null
                                  : () => showMessageActions(message, mine),
                              onReplyTap: message.replyTo > 0
                                  ? () => scrollToMessage(message.replyTo)
                                  : null,
                              onImageTap: message.imageUrl.isEmpty
                                  ? null
                                  : () => showImagePreview(
                                      context,
                                      message.imageUrl,
                                    ),
                              voicePlaying: isVoicePlaying(message),
                              voiceActive: playingVoiceMessageId == message.id,
                              voicePosition: playingVoiceMessageId == message.id
                                  ? voicePosition
                                  : Duration.zero,
                              voiceDuration: displayVoiceDuration(message),
                              voiceSpeed: voiceSpeed,
                              onVoiceTap: message.voiceUrl.isEmpty
                                  ? null
                                  : () => toggleVoicePlayback(message),
                              onVoiceSeek: message.voiceUrl.isEmpty
                                  ? null
                                  : seekVoice,
                              onVoiceSpeed: message.voiceUrl.isEmpty
                                  ? null
                                  : cycleVoiceSpeed,
                            );
                          },
                        ),
                  if (!nearBottom && !loading)
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        tooltip: strings.text('Jump to bottom'),
                        onPressed: jumpToEnd,
                        child: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (replyTarget != null || mentionTargets.isNotEmpty)
                      _ComposeTargetsBar(
                        replyTarget: replyTarget,
                        mentions: mentionTargets,
                        onClearReply: () => setState(() => replyTarget = null),
                        onClearMentions: () =>
                            setState(() => mentionTargets.clear()),
                      ),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: strings.text('More'),
                          onPressed: showComposeMenu,
                          icon: const Icon(Icons.add),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: input,
                            focusNode: inputFocus,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => send(),
                            decoration: InputDecoration(
                              hintText: strings.text('Message'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 46,
                          height: 46,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: send,
                            child: const Icon(Icons.send),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    this.replyMessage,
    required this.mine,
    this.focused = false,
    this.selected = false,
    this.selectionMode = false,
    required this.preferences,
    this.onTap,
    this.onLongPress,
    this.onReplyTap,
    this.onImageTap,
    this.voicePlaying = false,
    this.voiceActive = false,
    this.voicePosition = Duration.zero,
    this.voiceDuration = Duration.zero,
    this.voiceSpeed = 1,
    this.onVoiceTap,
    this.onVoiceSeek,
    this.onVoiceSpeed,
  });

  final ChatMessage message;
  final ChatMessage? replyMessage;
  final bool mine;
  final bool focused;
  final bool selected;
  final bool selectionMode;
  final CsacPreferences preferences;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;
  final VoidCallback? onImageTap;
  final bool voicePlaying;
  final bool voiceActive;
  final Duration voicePosition;
  final Duration voiceDuration;
  final double voiceSpeed;
  final VoidCallback? onVoiceTap;
  final ValueChanged<Duration>? onVoiceSeek;
  final VoidCallback? onVoiceSpeed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = mine
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final textColor = mine ? colors.onPrimaryContainer : colors.onSurface;
    final secondaryTextColor = mine
        ? colors.onPrimaryContainer.withValues(alpha: 0.72)
        : colors.onSurfaceVariant;
    final replyColor = mine
        ? colors.primary.withValues(alpha: 0.12)
        : colors.surfaceContainerHigh;
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final strings = context.strings;
    final messageTime = displayMessageTime(message, preferences);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: align,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectionMode) ...[
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    '${message.sender}${messageTime.isEmpty ? '' : ' · $messageTime'}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected || focused
                      ? colors.primary
                      : mine
                      ? colors.primaryContainer
                      : colors.outlineVariant,
                  width: selected || focused ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.replyTo > 0) ...[
                    InkWell(
                      onTap: onReplyTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: replyColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          replyMessage == null
                              ? strings.format('Reply #{id}', {
                                  'id': message.replyTo,
                                })
                              : strings.format('Reply {sender}: {message}', {
                                  'sender': replyMessage!.sender,
                                  'message': compactMessage(replyMessage!.body),
                                }),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: secondaryTextColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (message.isMentioned || message.isEssence) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (message.isMentioned)
                          Chip(
                            avatar: const Icon(Icons.alternate_email, size: 16),
                            label: Text(strings.text('Mentioned')),
                            visualDensity: VisualDensity.compact,
                          ),
                        if (message.isEssence)
                          Chip(
                            avatar: const Icon(Icons.star, size: 16),
                            label: Text(strings.text('Essence')),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (message.imageUrl.isNotEmpty) ...[
                    _MessageImage(url: message.imageUrl, onTap: onImageTap),
                    if (message.body.isNotEmpty &&
                        !message.body.startsWith('[image]'))
                      const SizedBox(height: 8),
                  ],
                  if (message.voiceUrl.isNotEmpty) ...[
                    _VoiceMessageTile(
                      declaredDuration: message.voiceDuration,
                      position: voicePosition,
                      duration: voiceDuration,
                      playing: voicePlaying,
                      active: voiceActive,
                      speed: voiceSpeed,
                      textColor: textColor,
                      onTap: onVoiceTap,
                      onSeek: onVoiceSeek,
                      onSpeed: onVoiceSpeed,
                    ),
                    if (message.body.isNotEmpty &&
                        !message.body.startsWith('[voice]'))
                      const SizedBox(height: 8),
                  ],
                  if (message.body.isNotEmpty &&
                      !message.body.startsWith('[image]') &&
                      !message.body.startsWith('[voice]'))
                    Text(message.body, style: TextStyle(color: textColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBackground extends StatelessWidget {
  const _ChatBackground({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final overlay = colors.surface.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.78 : 0.68,
    );
    if (path.isEmpty || !File(path).existsSync()) {
      return ColoredBox(color: colors.surface);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: FileImage(File(path)),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(overlay, BlendMode.srcOver),
        ),
      ),
    );
  }
}

class _VoiceMessageTile extends StatelessWidget {
  const _VoiceMessageTile({
    required this.declaredDuration,
    required this.duration,
    required this.position,
    required this.playing,
    required this.active,
    required this.speed,
    required this.textColor,
    this.onTap,
    this.onSeek,
    this.onSpeed,
  });

  final int declaredDuration;
  final Duration duration;
  final Duration position;
  final bool playing;
  final bool active;
  final double speed;
  final Color textColor;
  final VoidCallback? onTap;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onSpeed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;
    final total = duration > Duration.zero
        ? duration
        : declaredDuration > 0
        ? Duration(seconds: declaredDuration)
        : Duration.zero;
    final clampedPosition = position > total && total > Duration.zero
        ? total
        : position;
    final totalMs = total.inMilliseconds;
    final positionMs = clampedPosition.inMilliseconds.clamp(0, totalMs);
    final canSeek = active && totalMs > 0 && onSeek != null;
    final statusLabel = playing
        ? context.strings.text('Playing')
        : active
        ? context.strings.text('Paused')
        : context.strings.text('Voice message');
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? colors.primary : textColor.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onTap,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(38, 38),
                ),
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                tooltip: context.strings.text(playing ? 'Pause' : 'Play'),
              ),
              const SizedBox(width: 8),
              Icon(Icons.graphic_eq_rounded, color: textColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: active ? onSpeed : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 32),
                ),
                child: Text(formatVoiceSpeed(speed)),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: totalMs > 0 ? positionMs.toDouble() : 0,
              min: 0,
              max: totalMs > 0 ? totalMs.toDouble() : 1,
              onChanged: canSeek
                  ? (value) => onSeek!(Duration(milliseconds: value.round()))
                  : null,
            ),
          ),
          Row(
            children: [
              Text(
                formatVoiceClock(clampedPosition),
                style: theme.textTheme.labelSmall?.copyWith(color: textColor),
              ),
              const Spacer(),
              Text(
                total > Duration.zero
                    ? formatVoiceClock(total)
                    : context.strings.text('Unknown duration'),
                style: theme.textTheme.labelSmall?.copyWith(color: textColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String formatVoiceClock(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatVoiceSpeed(double speed) {
  if ((speed - speed.roundToDouble()).abs() < 0.01) {
    return '${speed.round()}x';
  }
  return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '')}x';
}

class _RecordedVoice {
  const _RecordedVoice({required this.path, required this.durationSeconds});

  final String path;
  final int durationSeconds;
}

class _VoiceRecorderDialog extends StatefulWidget {
  const _VoiceRecorderDialog();

  @override
  State<_VoiceRecorderDialog> createState() => _VoiceRecorderDialogState();
}

class _VoiceRecorderDialogState extends State<_VoiceRecorderDialog> {
  final recorder = AudioRecorder();
  Timer? ticker;
  DateTime? startedAt;
  String? outputPath;
  bool starting = true;
  bool stopping = false;
  bool cancelled = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(startRecording());
  }

  @override
  void dispose() {
    ticker?.cancel();
    unawaited(recorder.dispose());
    super.dispose();
  }

  Future<void> startRecording() async {
    try {
      final hasPermission = await recorder.hasPermission();
      if (!mounted) {
        return;
      }
      if (!hasPermission) {
        setState(() {
          starting = false;
          error = context.strings.text('Microphone permission is required.');
        });
        return;
      }
      final directory = await getTemporaryDirectory();
      final fileName =
          'csac_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = p.join(directory.path, fileName);
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (!mounted) {
        return;
      }
      outputPath = path;
      startedAt = DateTime.now();
      ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      setState(() => starting = false);
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        starting = false;
        error = err.toString();
      });
    }
  }

  int elapsedSeconds() {
    final started = startedAt;
    if (started == null) {
      return 0;
    }
    return math.max(0, DateTime.now().difference(started).inSeconds);
  }

  String elapsedLabel() {
    final elapsed = elapsedSeconds();
    final minutes = elapsed ~/ 60;
    final seconds = elapsed % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> cancelRecording() async {
    cancelled = true;
    ticker?.cancel();
    try {
      await recorder.cancel();
    } catch (_) {
      final path = outputPath;
      if (path != null) {
        unawaited(
          File(path).delete().catchError((_) => File(path)).then((_) {}),
        );
      }
    }
    if (mounted) {
      Navigator.of(context).pop(null);
    }
  }

  Future<void> stopRecording() async {
    if (stopping || starting) {
      return;
    }
    final navigator = Navigator.of(context);
    final missingFileMessage = context.strings.text('Recording file missing.');
    setState(() => stopping = true);
    try {
      ticker?.cancel();
      final duration = math.max(1, elapsedSeconds());
      final path = await recorder.stop() ?? outputPath;
      if (!mounted || cancelled) {
        return;
      }
      if (path == null || !await File(path).exists()) {
        setState(() {
          stopping = false;
          error = missingFileMessage;
        });
        return;
      }
      navigator.pop(_RecordedVoice(path: path, durationSeconds: duration));
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        stopping = false;
        error = err.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(strings.text('Record voice')),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: error == null
                      ? colors.primaryContainer
                      : colors.errorContainer,
                ),
                child: Icon(
                  error == null ? Icons.mic : Icons.mic_off,
                  size: 42,
                  color: error == null
                      ? colors.onPrimaryContainer
                      : colors.onErrorContainer,
                ),
              ),
              const SizedBox(height: 18),
              if (starting)
                Text(strings.text('Starting recorder...'))
              else if (error != null)
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.error,
                  ),
                )
              else
                Text(
                  elapsedLabel(),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                strings.text('Tap stop to send this voice message.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: stopping ? null : cancelRecording,
            child: Text(strings.text('Cancel')),
          ),
          FilledButton.icon(
            onPressed: starting || stopping || error != null
                ? null
                : stopRecording,
            icon: stopping
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.stop_circle_outlined),
            label: Text(
              strings.text(stopping ? 'Sending...' : 'Stop and send'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingMessageBubble extends StatelessWidget {
  const _PendingMessageBubble({required this.pending, required this.onRetry});

  final _PendingSend pending;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = context.strings;
    final failed = pending.status == _PendingSendStatus.failed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            failed ? strings.text('Send failed') : strings.text('Sending...'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: failed ? colors.error : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: failed ? colors.errorContainer : colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: failed ? colors.error : colors.primaryContainer,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pending.hasImage) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 18,
                        color: failed
                            ? colors.onErrorContainer
                            : colors.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          pending.imageName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: failed
                                ? colors.onErrorContainer
                                : colors.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (pending.text.isNotEmpty) const SizedBox(height: 8),
                ],
                if (pending.hasVoice) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mic_none,
                        size: 18,
                        color: failed
                            ? colors.onErrorContainer
                            : colors.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          pending.voiceDuration > 0
                              ? '${pending.voiceName} (${pending.voiceDuration}s)'
                              : pending.voiceName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: failed
                                ? colors.onErrorContainer
                                : colors.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (pending.text.isNotEmpty) const SizedBox(height: 8),
                ],
                if (pending.text.isNotEmpty)
                  Text(
                    pending.text,
                    style: TextStyle(
                      color: failed
                          ? colors.onErrorContainer
                          : colors.onPrimaryContainer,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!failed)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimaryContainer,
                        ),
                      )
                    else
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: colors.onErrorContainer,
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        failed && pending.error.isNotEmpty
                            ? compactMessage(pending.error, max: 80)
                            : strings.text('Sending...'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: failed
                              ? colors.onErrorContainer
                              : colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                    if (failed) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(strings.text('Retry send')),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupAnnouncementBar extends StatelessWidget {
  const _GroupAnnouncementBar({
    required this.announcement,
    required this.onTap,
  });

  final String announcement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strings = context.strings;
    return Material(
      color: colors.secondaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Icon(Icons.campaign_outlined, color: colors.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.text('Group announcement'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      announcement,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colors.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MessageAction {
  select,
  copyText,
  copyImage,
  openImage,
  downloadImage,
  reply,
  recall,
  essence,
}

class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({
    required this.message,
    required this.canRecall,
    required this.canEssence,
  });

  final ChatMessage message;
  final bool canRecall;
  final bool canEssence;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.checklist),
            title: Text(strings.text('Select messages')),
            subtitle: Text(strings.text('Choose multiple messages')),
            onTap: () => Navigator.of(context).pop(_MessageAction.select),
          ),
          ListTile(
            leading: const Icon(Icons.reply),
            title: Text(strings.text('Reply')),
            subtitle: Text('#${message.id} ${message.sender}'),
            onTap: () => Navigator.of(context).pop(_MessageAction.reply),
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(strings.text('Copy text')),
            onTap: () => Navigator.of(context).pop(_MessageAction.copyText),
          ),
          if (message.imageUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(strings.text('Copy image link')),
              onTap: () => Navigator.of(context).pop(_MessageAction.copyImage),
            ),
          if (message.imageUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(strings.text('Open image')),
              onTap: () => Navigator.of(context).pop(_MessageAction.openImage),
            ),
          if (message.imageUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(strings.text('Download image')),
              onTap: () =>
                  Navigator.of(context).pop(_MessageAction.downloadImage),
            ),
          if (canRecall)
            ListTile(
              leading: const Icon(Icons.undo),
              title: Text(strings.text('Recall')),
              onTap: () => Navigator.of(context).pop(_MessageAction.recall),
            ),
          if (canEssence)
            ListTile(
              leading: Icon(
                message.isEssence ? Icons.star : Icons.star_outline,
              ),
              title: Text(
                strings.text(
                  message.isEssence ? 'Remove essence' : 'Set essence',
                ),
              ),
              onTap: () => Navigator.of(context).pop(_MessageAction.essence),
            ),
        ],
      ),
    );
  }
}

class _ComposeTargetsBar extends StatelessWidget {
  const _ComposeTargetsBar({
    required this.replyTarget,
    required this.mentions,
    required this.onClearReply,
    required this.onClearMentions,
  });

  final ChatMessage? replyTarget;
  final List<GroupMember> mentions;
  final VoidCallback onClearReply;
  final VoidCallback onClearMentions;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (replyTarget != null)
            InputChip(
              avatar: const Icon(Icons.reply, size: 18),
              label: Text(
                strings.format('Reply #{id}: {sender}', {
                  'id': replyTarget!.id,
                  'sender': replyTarget!.sender,
                }),
                overflow: TextOverflow.ellipsis,
              ),
              onDeleted: onClearReply,
            ),
          if (mentions.isNotEmpty)
            InputChip(
              avatar: const Icon(Icons.alternate_email, size: 18),
              label: Text(
                mentions.length == 1
                    ? '@${mentions.first.name}'
                    : strings.format('@ {count} members', {
                        'count': mentions.length,
                      }),
              ),
              onDeleted: onClearMentions,
            ),
        ],
      ),
    );
  }
}

class _MentionPickerSheet extends StatefulWidget {
  const _MentionPickerSheet({
    required this.members,
    required this.selectedUids,
  });

  final List<GroupMember> members;
  final Set<int> selectedUids;

  @override
  State<_MentionPickerSheet> createState() => _MentionPickerSheetState();
}

class _MentionPickerSheetState extends State<_MentionPickerSheet> {
  late final Set<int> selected = Set<int>.from(widget.selectedUids);

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return SafeArea(
      child: SizedBox(
        height: 520,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.text('Mention members'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (selected.length == widget.members.length) {
                          selected.clear();
                        } else {
                          selected
                            ..clear()
                            ..addAll(
                              widget.members.map((member) => member.uid),
                            );
                        }
                      });
                    },
                    child: Text(strings.text('Toggle all')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.members.isEmpty
                  ? _EmptyPanel(message: strings.text('No members.'))
                  : ListView.builder(
                      itemCount: widget.members.length,
                      itemBuilder: (context, index) {
                        final member = widget.members[index];
                        final checked = selected.contains(member.uid);
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: _RoundedInkClip(
                            child: CheckboxListTile(
                              value: checked,
                              onChanged: (_) {
                                setState(() {
                                  if (checked) {
                                    selected.remove(member.uid);
                                  } else {
                                    selected.add(member.uid);
                                  }
                                });
                              },
                              secondary: _Avatar(
                                url: member.avatar,
                                fallback: Icons.person_rounded,
                              ),
                              title: Text(member.name),
                              subtitle: member.subtitle.isEmpty
                                  ? null
                                  : Text(member.subtitle),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Text(
                    strings.format('{count} selected', {
                      'count': selected.length,
                    }),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(strings.text('Cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        widget.members
                            .where((member) => selected.contains(member.uid))
                            .toList(),
                      );
                    },
                    child: Text(strings.text('Done')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForwardConversationSheet extends StatelessWidget {
  const _ForwardConversationSheet({required this.conversations});

  final List<Conversation> conversations;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return SafeArea(
      child: SizedBox(
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                strings.text('Forward to'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: conversations.isEmpty
                  ? _EmptyPanel(
                      message: strings.text('No conversations available.'),
                    )
                  : ListView.builder(
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: _RoundedInkClip(
                            child: ListTile(
                              leading: Icon(
                                conversation.type == ConversationType.group
                                    ? Icons.groups_rounded
                                    : Icons.person_rounded,
                              ),
                              title: Text(
                                conversation.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: conversation.subtitle.isEmpty
                                  ? null
                                  : Text(
                                      conversation.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () =>
                                  Navigator.of(context).pop(conversation),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class EssenceMessagesScreen extends StatefulWidget {
  const EssenceMessagesScreen({
    super.key,
    required this.state,
    required this.conversation,
  });

  final CsacAppState state;
  final Conversation conversation;

  @override
  State<EssenceMessagesScreen> createState() => _EssenceMessagesScreenState();
}

class _EssenceMessagesScreenState extends State<EssenceMessagesScreen> {
  List<ChatMessage> messages = const <ChatMessage>[];
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
      final loaded = await widget.state.loadEssenceMessages(
        widget.conversation.id,
      );
      if (!mounted) {
        return;
      }
      setState(() => messages = loaded.reversed.toList());
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

  Future<void> openMessage(ChatMessage message) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          state: widget.state,
          conversation: widget.conversation,
          focusMessageId: message.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.strings.text('Essence messages')),
        actions: [
          IconButton(
            tooltip: context.strings.text('Refresh'),
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (error != null) _InlineError(message: error!, onRetry: load),
            if (!loading && messages.isEmpty)
              _EmptyPanel(message: context.strings.text('No essence messages.'))
            else
              for (final message in messages)
                _EssenceMessageTile(
                  message: message,
                  preferences: widget.state.preferences,
                  onTap: () => openMessage(message),
                ),
          ],
        ),
      ),
    );
  }
}

class _EssenceMessageTile extends StatelessWidget {
  const _EssenceMessageTile({
    required this.message,
    required this.preferences,
    required this.onTap,
  });

  final ChatMessage message;
  final CsacPreferences preferences;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = displayMessageTime(message, preferences);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.star_outline),
        title: Text(
          message.sender,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [if (time.isNotEmpty) time, message.body].join(' | '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
