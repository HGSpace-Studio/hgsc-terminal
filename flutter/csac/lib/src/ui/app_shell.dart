part of '../../main.dart';

class CsacMobileApp extends StatefulWidget {
  const CsacMobileApp({
    super.key,
    this.initialPreferences = const CsacPreferences(),
  });

  final CsacPreferences initialPreferences;

  @override
  State<CsacMobileApp> createState() => _CsacMobileAppState();
}

class _CsacMobileAppState extends State<CsacMobileApp>
    with WidgetsBindingObserver {
  late final CsacAppState state;
  final localNotifications = CsacLocalNotificationService.instance;
  final backgroundRefreshChannel = const MethodChannel(
    'work.happygray.hgsc/background_refresh',
  );
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Conversation>? notificationTapSub;
  bool locked = false;
  bool wasBackgrounded = false;
  bool appLockSessionUnlocked = false;
  bool appLockStateSeen = false;
  bool lastCanUseAppLock = false;
  bool localNotificationPermissionPrimed = false;
  int appLockUserId = 0;

  Map<String, int> unreadSnapshot() {
    return <String, int>{
      for (final conversation in state.conversations)
        conversationKey(conversation): conversation.unreadCount,
    };
  }

  String conversationKey(Conversation conversation) {
    return '${conversation.type.name}:${conversation.id}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state = CsacAppState(initialPreferences: widget.initialPreferences);
    state.addListener(handleStateChanged);
    backgroundRefreshChannel.setMethodCallHandler(handleBackgroundRefreshCall);
    unawaited(state.initialize());
    unawaited(localNotifications.initialize());
    notificationTapSub = localNotifications.taps.listen(openNotificationChat);
  }

  @override
  void dispose() {
    state.removeListener(handleStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    backgroundRefreshChannel.setMethodCallHandler(null);
    notificationTapSub?.cancel();
    super.dispose();
  }

  Future<void> openNotificationChat(Conversation tapped) async {
    final context = navigatorKey.currentContext;
    if (context == null ||
        !context.mounted ||
        state.user == null ||
        state.needsEmailVerification) {
      return;
    }
    final conversation = state.conversations
        .where((item) => item.type == tapped.type && item.id == tapped.id)
        .firstOrNull;
    if (conversation == null) {
      return;
    }
    if (state.isActiveConversation(conversation)) {
      return;
    }
    await navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          state: state,
          conversation: conversation.copyWith(unreadCount: 0),
        ),
      ),
    );
  }

  Future<dynamic> handleBackgroundRefreshCall(MethodCall call) async {
    if (call.method != 'performBackgroundFetch') {
      throw MissingPluginException('Unknown method ${call.method}');
    }
    if (state.user == null ||
        state.bootstrapping ||
        state.needsEmailVerification) {
      return false;
    }
    final wasForeground = state.appInForeground;
    state.setAppInForeground(false);
    final beforeUnread = unreadSnapshot();
    try {
      await state.refreshHome();
      final newCount = await showNewMessageNotificationsFromSnapshot(
        beforeUnread,
      );
      return newCount > 0;
    } catch (_) {
      return false;
    } finally {
      state.setAppInForeground(wasForeground);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden ||
        lifecycleState == AppLifecycleState.inactive) {
      state.setAppInForeground(false);
      wasBackgrounded = true;
      if (canUseAppLock()) {
        appLockSessionUnlocked = false;
        if (!locked && mounted) {
          setState(() => locked = true);
        }
      }
      return;
    }
    if (lifecycleState == AppLifecycleState.resumed && wasBackgrounded) {
      wasBackgrounded = false;
      unawaited(refreshAfterResume());
      lockIfNeeded();
      return;
    }
    if (lifecycleState == AppLifecycleState.resumed) {
      state.setAppInForeground(true);
    }
  }

  Future<void> refreshAfterResume() async {
    if (state.user == null ||
        state.bootstrapping ||
        state.needsEmailVerification) {
      state.setAppInForeground(true);
      return;
    }
    final beforeUnread = unreadSnapshot();
    try {
      await state.refreshHome();
      await showNewMessageNotificationsFromSnapshot(beforeUnread);
    } catch (_) {
      // Resume refresh should not interrupt unlock or normal foregrounding.
    } finally {
      state.setAppInForeground(true);
    }
  }

  Future<int> showNewMessageNotificationsFromSnapshot(
    Map<String, int> beforeUnread,
  ) async {
    if (!state.preferences.localSystemNotificationsEnabled) {
      return 0;
    }
    var newCount = 0;
    for (final conversation in state.conversations) {
      if (state.isVisibleActiveConversation(conversation)) {
        continue;
      }
      final previous = beforeUnread[conversationKey(conversation)] ?? 0;
      final delta = conversation.unreadCount - previous;
      if (delta <= 0) {
        continue;
      }
      newCount += delta;
      final latestMessage = await latestNotificationMessage(conversation);
      await localNotifications.showConversationNotification(
        conversation: conversation,
        newCount: delta,
        title: notificationTitleForConversation(conversation, latestMessage),
        body: notificationBodyForConversation(
          conversation,
          delta,
          latestMessage,
          CsacStrings(localeForLanguage(state.preferences.language)),
        ),
      );
    }
    return newCount;
  }

  Future<ChatMessage?> latestNotificationMessage(
    Conversation conversation,
  ) async {
    if (conversation.type == ConversationType.group) {
      final cached = await state.loadCachedMessages(conversation);
      final afterId = cached.isEmpty ? 0 : cached.last.id;
      final previousIncomingId = latestIncomingNotificationMessageId(
        conversation,
        cached,
        currentUserId: state.user?.uid ?? 0,
      );
      final loaded = await state.syncMessages(conversation, afterId: afterId);
      final latestIncoming = latestIncomingNotificationMessage(
        conversation,
        loaded,
        currentUserId: state.user?.uid ?? 0,
      );
      if (latestIncoming != null && latestIncoming.id > previousIncomingId) {
        return latestIncoming;
      }
      return null;
    }
    final cached = await state.loadCachedMessages(conversation);
    return latestIncomingNotificationMessage(
      conversation,
      cached,
      currentUserId: state.user?.uid ?? 0,
    );
  }

  Future<ChatMessage?> latestCachedMessage(Conversation conversation) async {
    final cached = await state.loadCachedMessages(conversation);
    return latestIncomingNotificationMessage(
          conversation,
          cached,
          currentUserId: state.user?.uid ?? 0,
        ) ??
        (cached.isEmpty ? null : cached.last);
  }

  void handleStateChanged() {
    maybePrimeLocalNotificationPermission();
    final userId = state.user?.uid ?? 0;
    if (userId != appLockUserId) {
      appLockUserId = userId;
      appLockSessionUnlocked = false;
    }
    if (!canUseAppLock()) {
      if (locked) {
        setState(() => locked = false);
      }
      appLockSessionUnlocked = false;
      if (!state.bootstrapping && state.user != null) {
        appLockStateSeen = true;
      }
      lastCanUseAppLock = false;
      return;
    }
    if (!lastCanUseAppLock) {
      if (appLockStateSeen) {
        appLockSessionUnlocked = true;
      }
      appLockStateSeen = true;
      lastCanUseAppLock = true;
    }
    if (!locked && !appLockSessionUnlocked) {
      setState(() => locked = true);
    }
  }

  void maybePrimeLocalNotificationPermission() {
    if (localNotificationPermissionPrimed ||
        state.bootstrapping ||
        !state.preferences.localSystemNotificationsEnabled) {
      return;
    }
    localNotificationPermissionPrimed = true;
    unawaited(localNotifications.ensurePermissions());
  }

  bool canUseAppLock() {
    return !state.bootstrapping &&
        state.user != null &&
        !state.needsEmailVerification &&
        state.preferences.effectiveAppLockEnabled;
  }

  void lockIfNeeded() {
    if (!mounted || locked || !canUseAppLock()) {
      return;
    }
    appLockSessionUnlocked = false;
    setState(() => locked = true);
  }

  void unlock() {
    if (!mounted) {
      return;
    }
    appLockSessionUnlocked = true;
    appLockUserId = state.user?.uid ?? 0;
    setState(() => locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return MaterialApp(
          title: CsacStrings(
            localeForLanguage(state.preferences.language),
          ).text('CsAC'),
          scaffoldMessengerKey: scaffoldMessengerKey,
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          locale: localeForLanguage(state.preferences.language),
          supportedLocales: supportedCsacLocales,
          localizationsDelegates: const [
            CsacStringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          theme: buildCsacTheme(
            Brightness.light,
            Color(state.preferences.themeColorValue),
            state.preferences.fontStyle,
            compactMode: state.preferences.compactMode,
            highContrastMode: state.preferences.highContrastMode,
          ),
          darkTheme: buildCsacTheme(
            Brightness.dark,
            Color(state.preferences.themeColorValue),
            state.preferences.fontStyle,
            compactMode: state.preferences.compactMode,
            highContrastMode: state.preferences.highContrastMode,
          ),
          themeMode: state.preferences.themeMode,
          color: Colors.transparent,
          builder: (context, child) {
            final framed = _MaterialYouDesktopWindowFrame(
              title: CsacStrings(
                localeForLanguage(state.preferences.language),
              ).text('CsAC'),
              child: _DesktopCommandPaletteHost(
                state: state,
                navigatorKey: navigatorKey,
                scaffoldMessengerKey: scaffoldMessengerKey,
                enabled:
                    isDesktopPlatform &&
                    !locked &&
                    !state.bootstrapping &&
                    state.user != null,
                child: child ?? const SizedBox.shrink(),
              ),
            );
            return _InterfaceFontScale(
              scale: state.preferences.interfaceFontScale,
              child: framed,
            );
          },
          home: _MotionPreference(
            reduceMotion: state.preferences.reduceMotion,
            child: Stack(
              children: [
                _StartupTransition(
                  child: state.bootstrapping
                      ? SplashScreen(
                          key: const ValueKey<String>('bootstrap'),
                          status: state.restoreStatus,
                        )
                      : state.needsEmailVerification
                      ? EmailVerificationScreen(
                          key: const ValueKey<String>('email-verification'),
                          state: state,
                        )
                      : state.user == null
                      ? LoginScreen(
                          key: const ValueKey<String>('login'),
                          state: state,
                        )
                      : MainShell(
                          key: const ValueKey<String>('main'),
                          state: state,
                        ),
                ),
                if (locked && state.user != null)
                  Positioned.fill(
                    child: AppLockScreen(state: state, onUnlocked: unlock),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StartupTransition extends StatelessWidget {
  const _StartupTransition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _MotionPreference.reduceOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : 360.ms,
      reverseDuration: reduceMotion ? Duration.zero : 240.ms,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        if (reduceMotion) {
          return child;
        }
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final slide =
            Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        final scale = Tween<double>(begin: 0.985, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class _InterfaceFontScale extends StatelessWidget {
  const _InterfaceFontScale({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final boundedScale = scale
        .clamp(minInterfaceFontScale, maxInterfaceFontScale)
        .toDouble();
    if ((boundedScale - defaultInterfaceFontScale).abs() < 0.001) {
      return child;
    }
    final media = MediaQuery.maybeOf(context);
    if (media == null) {
      return child;
    }
    final platformScale = media.textScaler.scale(1);
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(platformScale * boundedScale),
      ),
      child: child,
    );
  }
}

class _MaterialYouDesktopWindowFrame extends StatelessWidget {
  const _MaterialYouDesktopWindowFrame({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!supportsCustomDesktopWindowChrome) {
      return child;
    }
    return buildDesktopWindowStateListener(
      builder: (context, frameState) {
        final colors = Theme.of(context).colorScheme;
        final expanded = frameState.isExpanded;
        final radius = expanded ? 0.0 : 10.0;
        final borderColor =
            (frameState.isFocused ? colors.primary : colors.outlineVariant)
                .withValues(alpha: frameState.isFocused ? 0.48 : 0.40);
        final window = DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: expanded
                ? null
                : Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              if (!expanded)
                BoxShadow(
                  color: colors.shadow.withValues(
                    alpha: frameState.isFocused ? 0.18 : 0.10,
                  ),
                  blurRadius: frameState.isFocused ? 24 : 14,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Column(
              children: [
                _MaterialYouDesktopTitleBar(
                  title: title,
                  isMaximized: frameState.isMaximized,
                  isFocused: frameState.isFocused,
                  expanded: expanded,
                ),
                Expanded(
                  child: ClipRect(
                    child: ColoredBox(color: colors.surface, child: child),
                  ),
                ),
              ],
            ),
          ),
        );
        return buildDesktopWindowResizeFrame(enabled: !expanded, child: window);
      },
    );
  }
}

class _MaterialYouDesktopTitleBar extends StatelessWidget {
  const _MaterialYouDesktopTitleBar({
    required this.title,
    required this.isMaximized,
    required this.isFocused,
    required this.expanded,
  });

  final String title;
  final bool isMaximized;
  final bool isFocused;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      color: (isFocused ? colors.onSurface : colors.onSurfaceVariant)
          .withValues(alpha: isFocused ? 1 : 0.74),
      fontWeight: FontWeight.w700,
    );
    final bar = ColoredBox(
      color: Color.alphaBlend(
        colors.primary.withValues(alpha: isFocused ? 0.025 : 0.0),
        colors.surface,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.46),
            ),
          ),
        ),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: expanded ? 12 : 14,
              end: 6,
            ),
            child: Row(
              children: [
                Expanded(
                  child: buildDesktopWindowMoveArea(
                    child: Row(
                      children: [
                        _DesktopWindowBrandMark(isFocused: isFocused),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _MaterialYouWindowControlButton(
                  tooltip: 'Minimize',
                  icon: Icons.remove_rounded,
                  onPressed: () => unawaited(minimizeDesktopWindow()),
                ),
                _MaterialYouWindowControlButton(
                  tooltip: isMaximized ? 'Restore' : 'Maximize',
                  icon: isMaximized
                      ? Icons.filter_none_rounded
                      : Icons.crop_square_rounded,
                  onPressed: () => unawaited(toggleMaximizeDesktopWindow()),
                ),
                _MaterialYouWindowControlButton(
                  tooltip: 'Close',
                  icon: Icons.close_rounded,
                  isClose: true,
                  onPressed: () => unawaited(closeDesktopWindow()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Material(color: Colors.transparent, child: bar);
  }
}

class _DesktopWindowBrandMark extends StatelessWidget {
  const _DesktopWindowBrandMark({required this.isFocused});

  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isFocused
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.44),
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.chat_bubble_rounded,
        size: 14,
        color: isFocused ? colors.onPrimaryContainer : colors.onSurfaceVariant,
      ),
    );
  }
}

class _MaterialYouWindowControlButton extends StatefulWidget {
  const _MaterialYouWindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  State<_MaterialYouWindowControlButton> createState() =>
      _MaterialYouWindowControlButtonState();
}

class _MaterialYouWindowControlButtonState
    extends State<_MaterialYouWindowControlButton> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = widget.isClose && hovering
        ? colors.onError
        : colors.onSurfaceVariant;
    final hoverBackground = widget.isClose
        ? colors.error
        : colors.secondaryContainer.withValues(alpha: 0.92);
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovering = true),
        onExit: (_) => setState(() => hovering = false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: IconButton(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon),
            iconSize: 17,
            color: foreground,
            splashRadius: 16,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(32, 32)),
              fixedSize: const WidgetStatePropertyAll(Size(32, 32)),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const WidgetStatePropertyAll(CircleBorder()),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return widget.isClose
                      ? colors.error.withValues(alpha: 0.86)
                      : colors.secondaryContainer.withValues(alpha: 0.72);
                }
                if (states.contains(WidgetState.hovered)) {
                  return hoverBackground;
                }
                return Colors.transparent;
              }),
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData buildCsacTheme(
  Brightness brightness,
  Color seedColor,
  CsacFontStyle fontStyle, {
  bool compactMode = false,
  bool highContrastMode = false,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    contrastLevel: highContrastMode ? 1.0 : 0.0,
  );
  final fontFamily = fontFamilyForStyle(fontStyle);
  final fontFamilyFallback = fontFamilyFallbackForStyle(fontStyle);
  final visualDensity = compactMode
      ? VisualDensity.compact
      : VisualDensity.standard;
  final inputBorderRadius = BorderRadius.circular(compactMode ? 10 : 12);
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    visualDensity: visualDensity,
    materialTapTargetSize: compactMode
        ? MaterialTapTargetSize.shrinkWrap
        : MaterialTapTargetSize.padded,
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    cardColor: scheme.surfaceContainerLow,
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.surfaceTint,
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      modalBackgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.labelMedium?.copyWith(color: scheme.onSurface),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: compactMode
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : null,
      border: OutlineInputBorder(borderRadius: inputBorderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: inputBorderRadius,
        borderSide: BorderSide(
          color: scheme.outline,
          width: highContrastMode ? 1.3 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: inputBorderRadius,
        borderSide: BorderSide(
          color: scheme.primary,
          width: highContrastMode ? 2 : 1.6,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.secondaryContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(color: scheme.onSecondaryContainer),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      side: BorderSide(
        color: highContrastMode ? scheme.outline : scheme.outlineVariant,
      ),
      padding: compactMode
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : null,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(
      color: highContrastMode ? scheme.outline : scheme.outlineVariant,
      thickness: highContrastMode ? 1.1 : null,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      dense: compactMode,
      minVerticalPadding: compactMode ? 4 : null,
      contentPadding: compactMode
          ? const EdgeInsets.symmetric(horizontal: 12)
          : null,
      subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
  );
}

String? fontFamilyForStyle(CsacFontStyle style) {
  switch (style) {
    case CsacFontStyle.system:
      return null;
    case CsacFontStyle.serif:
      return isApplePlatform ? 'Times New Roman' : 'serif';
    case CsacFontStyle.rounded:
      return isApplePlatform ? 'SF Pro Rounded' : null;
    case CsacFontStyle.monospace:
      return isApplePlatform ? 'Menlo' : 'monospace';
  }
}

List<String>? fontFamilyFallbackForStyle(CsacFontStyle style) {
  switch (style) {
    case CsacFontStyle.system:
      return null;
    case CsacFontStyle.serif:
      return const <String>[
        'Times New Roman',
        'Songti SC',
        'Noto Serif CJK SC',
        'serif',
      ];
    case CsacFontStyle.rounded:
      return const <String>[
        'SF Pro Rounded',
        'PingFang SC',
        'Microsoft YaHei UI',
        'Roboto',
        'sans-serif',
      ];
    case CsacFontStyle.monospace:
      return const <String>['Menlo', 'Cascadia Mono', 'Consolas', 'monospace'];
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_rounded,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              context.strings.text('CsAC'),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(status),
            const SizedBox(height: 18),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

const _legalAgreementVersion = 'v1.0';
const _privacyPolicyAsset = 'assets/legal/privacy_policy_zh.md';
const _userAgreementAsset = 'assets/legal/user_agreement_zh.md';

bool _hasAcceptedCurrentLegal(CsacPreferences preferences) {
  return preferences.acceptedLegalVersion == _legalAgreementVersion;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  final passwordFocus = FocusNode();
  final scrollController = ScrollController();
  final developerOptionsKey = GlobalKey();
  List<LoginAccountRecord> accounts = const <LoginAccountRecord>[];
  bool loadingAccounts = true;
  bool acceptedLegalAgreements = false;
  String? error;

  @override
  void initState() {
    super.initState();
    acceptedLegalAgreements = _hasAcceptedCurrentLegal(
      widget.state.preferences,
    );
    loadAccounts();
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    passwordFocus.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> setLegalAccepted(bool accepted) async {
    setState(() {
      acceptedLegalAgreements = accepted;
      if (accepted &&
          error ==
              context.strings.text(
                'Please agree to the Privacy Policy and User Agreement first.',
              )) {
        error = null;
      }
    });
    await widget.state.acceptLegalAgreements(
      accepted ? _legalAgreementVersion : '',
    );
  }

  bool ensureLegalAccepted() {
    if (acceptedLegalAgreements) {
      return true;
    }
    setState(
      () => error = context.strings.text(
        'Please agree to the Privacy Policy and User Agreement first.',
      ),
    );
    return false;
  }

  Future<void> loadAccounts() async {
    final loaded = await widget.state.loadLoginAccounts();
    if (!mounted) {
      return;
    }
    setState(() {
      accounts = loaded;
      loadingAccounts = false;
    });
  }

  Future<void> selectAccount(LoginAccountRecord account) async {
    if (!ensureLegalAccepted()) {
      return;
    }
    if (account.hasSession) {
      setState(() => error = null);
      try {
        await widget.state.loginWithSavedSession(account);
        if (mounted) {
          await loadAccounts();
        }
        return;
      } catch (_) {
        if (mounted) {
          if (widget.state.needsEmailVerification) {
            return;
          }
          await loadAccounts();
          setState(
            () => error = context.strings.text(
              'Saved session expired. Please enter password.',
            ),
          );
        }
      }
    }
    username.text = account.username.trim().isEmpty
        ? '${account.uid}'
        : account.username.trim();
    password.clear();
    setState(() => error = null);
    passwordFocus.requestFocus();
  }

  Future<void> removeAccount(LoginAccountRecord account) async {
    await widget.state.removeLoginAccount(account);
    await loadAccounts();
  }

  Future<void> submit() async {
    final name = username.text.trim();
    if (!ensureLegalAccepted()) {
      return;
    }
    if (name.isEmpty || password.text.isEmpty) {
      setState(
        () =>
            error = context.strings.text('Username and password are required.'),
      );
      return;
    }
    try {
      await widget.state.login(name, password.text);
      if (mounted) {
        await loadAccounts();
      }
    } catch (err) {
      if (!widget.state.needsEmailVerification) {
        setState(() => error = err.toString());
      }
    }
  }

  Future<void> openServerSettings() async {
    final keyContext = developerOptionsKey.currentContext;
    if (keyContext != null) {
      await Scrollable.ensureVisible(
        keyContext,
        duration: 320.ms,
        curve: Curves.easeOutCubic,
        alignment: 0.7,
      );
    } else if (scrollController.hasClients) {
      await scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: 320.ms,
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          state: widget.state,
          initialDeveloperOptionsExpanded: true,
        ),
      ),
    );
    if (mounted) {
      await loadAccounts();
      setState(() {});
    }
  }

  Future<void> openRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegisterScreen(state: widget.state),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final serverUrl = widget.state.preferences.serverUrl.trim().isEmpty
        ? strings.text('Default server')
        : widget.state.preferences.serverUrl.trim();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.forum_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.text('CsAC'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: username,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: strings.text('Username'),
                      prefixIcon: const Icon(Icons.person_outline),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    focusNode: passwordFocus,
                    obscureText: true,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: strings.text('Password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  LegalAgreementConsent(
                    accepted: acceptedLegalAgreements,
                    onChanged: widget.state.loading
                        ? null
                        : (value) => unawaited(setLegalAccepted(value)),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: widget.state.loading ? null : submit,
                    icon: widget.state.loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(strings.text('Login')),
                  ),
                  const SizedBox(height: 10),
                  if (loadingAccounts)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (accounts.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        strings.text('Recent accounts'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final account in accounts.take(3))
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: _RoundedInkClip(
                          child: ListTile(
                            leading: _Avatar(
                              url: account.avatar,
                              fallback: Icons.person_rounded,
                              radius: 20,
                            ),
                            title: Text(
                              account.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                account.subtitle,
                                if (account.hasSession)
                                  strings.text('Saved session'),
                              ].join(' | '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: strings.text('Remove login record'),
                              onPressed: () => removeAccount(account),
                              icon: const Icon(Icons.close),
                            ),
                            onTap: () => selectAccount(account),
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: widget.state.loading ? null : openRegister,
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(strings.text('Register account')),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: developerOptionsKey,
                    onPressed: openServerSettings,
                    icon: const Icon(Icons.developer_mode_outlined),
                    label: Text(strings.text('Developer options')),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.format('Current server: {server}', {
                      'server': serverUrl,
                    }),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final email = TextEditingController();
  final emailCode = TextEditingController();
  Timer? resendTimer;
  bool sendingCode = false;
  bool verifying = false;
  int resendRemaining = 0;
  int expiresIn = 600;
  String? error;
  String? message;

  @override
  void initState() {
    super.initState();
    expiresIn = widget.state.emailVerificationExpiresIn;
  }

  @override
  void dispose() {
    resendTimer?.cancel();
    email.dispose();
    emailCode.dispose();
    super.dispose();
  }

  bool get canSendCode => !sendingCode && resendRemaining <= 0;

  void startResendCountdown(int seconds) {
    resendTimer?.cancel();
    setState(() => resendRemaining = seconds <= 0 ? 60 : seconds);
    resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (resendRemaining <= 1) {
        timer.cancel();
        setState(() => resendRemaining = 0);
        return;
      }
      setState(() => resendRemaining--);
    });
  }

  Future<void> sendCode() async {
    final strings = context.strings;
    final targetEmail = email.text.trim();
    if (!_looksLikeEmail(targetEmail)) {
      setState(() => error = strings.text('Please enter a valid email.'));
      return;
    }
    setState(() {
      sendingCode = true;
      error = null;
      message = null;
    });
    try {
      final response = await widget.state.sendEmailBindCode(targetEmail);
      if (!mounted) {
        return;
      }
      setState(() {
        expiresIn = response.expiresIn <= 0 ? 600 : response.expiresIn;
        message = strings.format(
          'Code sent. It expires in {minutes} minutes.',
          {'minutes': _durationMinutesLabel(expiresIn)},
        );
      });
      startResendCountdown(response.resendAfter);
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => sendingCode = false);
      }
    }
  }

  Future<void> verify() async {
    final strings = context.strings;
    final targetEmail = email.text.trim();
    final code = emailCode.text.trim();
    if (!_looksLikeEmail(targetEmail)) {
      setState(() => error = strings.text('Please enter a valid email.'));
      return;
    }
    if (code.length != 6) {
      setState(() => error = strings.text('Please enter the 6-digit code.'));
      return;
    }
    setState(() {
      verifying = true;
      error = null;
      message = null;
    });
    try {
      await widget.state.verifyEmailBindCode(targetEmail, code);
      if (mounted) {
        setState(() => message = strings.text('Email verified.'));
      }
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => verifying = false);
      }
    }
  }

  Future<void> backToLogin() async {
    await widget.state.logout();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final busy = sendingCode || verifying || widget.state.loading;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.text('Email verification')),
        actions: [
          TextButton(
            onPressed: busy ? null : backToLogin,
            child: Text(strings.text('Back to login')),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.text('Bind email before continuing'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    strings.text(
                      'Your login session is kept for email binding.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: strings.text('Email'),
                      prefixIcon: const Icon(Icons.alternate_email),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _EmailCodeTextField(
                          controller: emailCode,
                          label: strings.text('Email code'),
                          onSubmitted: (_) => verify(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: _emailCodeControlHeight,
                        child: OutlinedButton(
                          style: _emailCodeButtonStyle(),
                          onPressed: canSendCode && !busy ? sendCode : null,
                          child: Text(
                            resendRemaining > 0
                                ? strings.format('Resend in {seconds}s', {
                                    'seconds': resendRemaining,
                                  })
                                : strings.text('Send code'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.format('Code expires in {minutes} minutes.', {
                      'minutes': _durationMinutesLabel(expiresIn),
                    }),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.text(
                      'If the code expires or fails too many times, request a new code.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: busy ? null : verify,
                    icon: verifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined),
                    label: Text(strings.text('Verify email')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.state});

  final CsacAppState state;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final username = TextEditingController();
  final nickname = TextEditingController();
  final email = TextEditingController();
  final emailCode = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  Timer? resendTimer;
  XFile? avatar;
  bool submitting = false;
  bool sendingCode = false;
  bool acceptedLegalAgreements = false;
  int resendRemaining = 0;
  int expiresIn = 600;
  String? error;
  String? message;

  @override
  void initState() {
    super.initState();
    acceptedLegalAgreements = _hasAcceptedCurrentLegal(
      widget.state.preferences,
    );
  }

  @override
  void dispose() {
    resendTimer?.cancel();
    username.dispose();
    nickname.dispose();
    email.dispose();
    emailCode.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> chooseAvatar() async {
    final picked = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: context.strings.text('Images'),
          extensions: imageExtensions,
        ),
      ],
    );
    if (picked != null && mounted) {
      setState(() => avatar = picked);
    }
  }

  bool get canSendCode => !sendingCode && resendRemaining <= 0;

  Future<void> setLegalAccepted(bool accepted) async {
    setState(() {
      acceptedLegalAgreements = accepted;
      if (accepted &&
          error ==
              context.strings.text(
                'Please agree to the Privacy Policy and User Agreement first.',
              )) {
        error = null;
      }
    });
    await widget.state.acceptLegalAgreements(
      accepted ? _legalAgreementVersion : '',
    );
  }

  void startResendCountdown(int seconds) {
    resendTimer?.cancel();
    setState(() => resendRemaining = seconds <= 0 ? 60 : seconds);
    resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (resendRemaining <= 1) {
        timer.cancel();
        setState(() => resendRemaining = 0);
        return;
      }
      setState(() => resendRemaining--);
    });
  }

  Future<void> sendCode() async {
    final strings = context.strings;
    if (!acceptedLegalAgreements) {
      setState(
        () => error = strings.text(
          'Please agree to the Privacy Policy and User Agreement first.',
        ),
      );
      return;
    }
    final targetEmail = email.text.trim();
    if (!_looksLikeEmail(targetEmail)) {
      setState(() => error = strings.text('Please enter a valid email.'));
      return;
    }
    setState(() {
      sendingCode = true;
      error = null;
      message = null;
    });
    try {
      final response = await widget.state.sendRegisterCode(targetEmail);
      if (!mounted) {
        return;
      }
      setState(() {
        expiresIn = response.expiresIn <= 0 ? 600 : response.expiresIn;
        message = strings.format(
          'Code sent. It expires in {minutes} minutes.',
          {'minutes': _durationMinutesLabel(expiresIn)},
        );
      });
      startResendCountdown(response.resendAfter);
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => sendingCode = false);
      }
    }
  }

  Future<void> submit() async {
    final strings = context.strings;
    if (!acceptedLegalAgreements) {
      setState(
        () => error = strings.text(
          'Please agree to the Privacy Policy and User Agreement first.',
        ),
      );
      return;
    }
    if (username.text.trim().isEmpty ||
        nickname.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        emailCode.text.trim().isEmpty ||
        password.text.isEmpty ||
        confirmPassword.text.isEmpty) {
      setState(() => error = strings.text('Please fill all fields.'));
      return;
    }
    if (!_looksLikeEmail(email.text.trim())) {
      setState(() => error = strings.text('Please enter a valid email.'));
      return;
    }
    if (emailCode.text.trim().length != 6) {
      setState(() => error = strings.text('Please enter the 6-digit code.'));
      return;
    }
    if (password.text.length < 6) {
      setState(
        () =>
            error = strings.text('New password must be at least 6 characters.'),
      );
      return;
    }
    if (password.text != confirmPassword.text) {
      setState(() => error = strings.text('Passwords do not match.'));
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final selectedAvatar = avatar;
      final avatarBytes = selectedAvatar == null
          ? null
          : await selectedAvatar.readAsBytes();
      await widget.state.register(
        username: username.text,
        nickname: nickname.text,
        email: email.text,
        emailCode: emailCode.text,
        password: password.text,
        confirmPassword: confirmPassword.text,
        avatarBytes: avatarBytes,
        avatarFileName: selectedAvatar?.name ?? '',
      );
      if (!mounted) {
        return;
      }
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
      appBar: AppBar(title: Text(strings.text('Register account'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              controller: username,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: strings.text('Username'),
                helperText: strings.text('3-32 letters, numbers, _@.-'),
                prefixIcon: const Icon(Icons.person_outline),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nickname,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: strings.text('Nickname'),
                prefixIcon: const Icon(Icons.badge_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: strings.text('Email'),
                prefixIcon: const Icon(Icons.alternate_email),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _EmailCodeTextField(
                    controller: emailCode,
                    label: strings.text('Email code'),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: _emailCodeControlHeight,
                  child: OutlinedButton(
                    style: _emailCodeButtonStyle(),
                    onPressed: canSendCode && !submitting && !sendingCode
                        ? sendCode
                        : null,
                    child: Text(
                      resendRemaining > 0
                          ? strings.format('Resend in {seconds}s', {
                              'seconds': resendRemaining,
                            })
                          : strings.text('Send code'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              strings.format('Code expires in {minutes} minutes.', {
                'minutes': _durationMinutesLabel(expiresIn),
              }),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              strings.text(
                'If the code expires or fails too many times, request a new code.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: strings.text('Password'),
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassword,
              obscureText: true,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: strings.text('Confirm password'),
                prefixIcon: const Icon(Icons.lock_reset),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: submitting ? null : chooseAvatar,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                avatar == null
                    ? strings.text('Choose avatar')
                    : strings.format('Selected: {name}', {
                        'name': avatar!.name,
                      }),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            LegalAgreementConsent(
              accepted: acceptedLegalAgreements,
              onChanged: submitting || sendingCode
                  ? null
                  : (value) => unawaited(setLegalAccepted(value)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: submitting ? null : submit,
              icon: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt),
              label: Text(strings.text('Register')),
            ),
          ],
        ),
      ),
    );
  }
}

class LegalAgreementConsent extends StatelessWidget {
  const LegalAgreementConsent({
    super.key,
    required this.accepted,
    required this.onChanged,
  });

  final bool accepted;
  final ValueChanged<bool>? onChanged;

  Future<void> openDocument(
    BuildContext context, {
    required String title,
    required String assetPath,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(title: title, assetPath: assetPath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: strings.text(
        'Agree to the Privacy Policy and User Agreement',
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: accepted,
                onChanged: onChanged == null
                    ? null
                    : (value) => onChanged!(value ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(strings.text('I have read and agree to the ')),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => openDocument(
                          context,
                          title: strings.text('Privacy Policy'),
                          assetPath: _privacyPolicyAsset,
                        ),
                        child: Text(strings.text('Privacy Policy')),
                      ),
                      Text(strings.text(' and ')),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => openDocument(
                          context,
                          title: strings.text('User Agreement'),
                          assetPath: _userAgreementAsset,
                        ),
                        child: Text(strings.text('User Agreement')),
                      ),
                      Text(
                        strings.format(' ({version})', {
                          'version': _legalAgreementVersion,
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  final String title;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(assetPath),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    strings.text('Unable to load legal document.'),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Markdown(
              data: snapshot.data ?? '',
              selectable: true,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              styleSheet: MarkdownStyleSheet.fromTheme(
                Theme.of(context),
              ).copyWith(
                h1: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                h2: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

const _emailCodeControlHeight = 56.0;

class _EmailCodeTextField extends StatelessWidget {
  const _EmailCodeTextField({
    required this.controller,
    required this.label,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _emailCodeControlHeight,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        maxLength: 6,
        maxLines: 1,
        textAlignVertical: TextAlignVertical.center,
        textInputAction: textInputAction,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.pin_outlined),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
          constraints: const BoxConstraints.tightFor(
            height: _emailCodeControlHeight,
          ),
          counter: const SizedBox.shrink(),
          counterText: '',
          counterStyle: const TextStyle(fontSize: 0, height: 0),
        ),
      ),
    );
  }
}

ButtonStyle _emailCodeButtonStyle() {
  return OutlinedButton.styleFrom(
    fixedSize: const Size.fromHeight(_emailCodeControlHeight),
    minimumSize: const Size(0, _emailCodeControlHeight),
    padding: const EdgeInsets.symmetric(horizontal: 14),
  );
}

bool _looksLikeEmail(String value) {
  final text = value.trim();
  if (text.length < 5 || text.length > 254) {
    return false;
  }
  final at = text.indexOf('@');
  return at > 0 &&
      at == text.lastIndexOf('@') &&
      text.indexOf('.', at) > at + 1;
}

String _durationMinutesLabel(int seconds) {
  final value = seconds <= 0 ? 600 : seconds;
  final minutes = value / 60;
  if (minutes == minutes.roundToDouble()) {
    return '${minutes.round()}';
  }
  return minutes.toStringAsFixed(1);
}
