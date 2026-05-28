part of '../../main.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({
    super.key,
    required this.state,
    required this.onUnlocked,
  });

  final CsacAppState state;
  final VoidCallback onUnlocked;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final pin = TextEditingController();
  final pinFocus = FocusNode();
  final auth = LocalAuthentication();
  bool checkingBiometric = false;
  bool biometricAvailable = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pinFocus.requestFocus();
      checkBiometric();
    });
  }

  @override
  void dispose() {
    pin.dispose();
    pinFocus.dispose();
    super.dispose();
  }

  Future<void> checkBiometric() async {
    if (!widget.state.preferences.appLockBiometricEnabled) {
      return;
    }
    try {
      final supported = await auth.isDeviceSupported();
      final biometrics = await auth.canCheckBiometrics;
      if (!mounted) {
        return;
      }
      setState(() => biometricAvailable = supported || biometrics);
      if (supported || biometrics) {
        await unlockWithBiometric();
      }
    } catch (_) {
      if (mounted) {
        setState(() => biometricAvailable = false);
      }
    }
  }

  Future<void> unlockWithBiometric() async {
    if (checkingBiometric) {
      return;
    }
    setState(() {
      checkingBiometric = true;
      error = null;
    });
    try {
      final ok = await auth.authenticate(
        localizedReason: context.strings.text('Unlock CsAC to view chats'),
        persistAcrossBackgrounding: true,
        sensitiveTransaction: false,
      );
      if (ok && mounted) {
        widget.onUnlocked();
      }
    } catch (err) {
      if (mounted) {
        setState(() => error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => checkingBiometric = false);
      }
    }
  }

  void unlockWithPin() {
    if (widget.state.verifyAppLockPin(pin.text)) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      error = context.strings.text('Incorrect PIN.');
      pin.clear();
    });
    pinFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_rounded, size: 58, color: scheme.primary),
                  const SizedBox(height: 18),
                  Text(
                    strings.text('App locked'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.text('Enter your PIN to protect chat history.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: pin,
                    focusNode: pinFocus,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    decoration: InputDecoration(
                      labelText: strings.text('PIN'),
                      prefixIcon: const Icon(Icons.pin_outlined),
                    ),
                    onSubmitted: (_) => unlockWithPin(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: TextStyle(color: scheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: unlockWithPin,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: Text(strings.text('Unlock')),
                  ),
                  if (widget.state.preferences.appLockBiometricEnabled &&
                      biometricAvailable) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: checkingBiometric ? null : unlockWithBiometric,
                      icon: checkingBiometric
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fingerprint),
                      label: Text(strings.text('Use biometrics')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
