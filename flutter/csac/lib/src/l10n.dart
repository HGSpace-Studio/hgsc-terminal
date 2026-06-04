import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'preferences.dart';

Locale localeForLanguage(CsacLanguage language) {
  switch (language) {
    case CsacLanguage.en:
      return const Locale('en');
    case CsacLanguage.zh:
      return const Locale('zh', 'CN');
  }
}

class CsacStrings {
  const CsacStrings(this.locale, [this.overrides = const <String, String>{}]);

  final Locale locale;
  final Map<String, String> overrides;

  static CsacStrings of(BuildContext context) {
    return Localizations.of<CsacStrings>(context, CsacStrings) ??
        const CsacStrings(Locale('zh', 'CN'));
  }

  String text(String key) {
    final override = overrides[key];
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }
    return key;
  }

  String format(String key, Map<String, Object?> values) {
    var result = text(key);
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }
}

class CsacStringsDelegate extends LocalizationsDelegate<CsacStrings> {
  const CsacStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode == 'en' || locale.languageCode == 'zh';
  }

  @override
  Future<CsacStrings> load(Locale locale) async {
    return CsacStrings(locale, await _loadL10nOverrides(locale));
  }

  @override
  bool shouldReload(CsacStringsDelegate old) => false;
}

Future<Map<String, String>> _loadL10nOverrides(Locale locale) async {
  final candidates = <String>[
    if (locale.countryCode?.trim().isNotEmpty == true)
      '${locale.languageCode}-${locale.countryCode}',
    locale.languageCode,
  ];
  for (final name in candidates) {
    try {
      final raw = await rootBundle.loadString('lib/l10n/$name.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      return decoded.map((key, value) => MapEntry(key, '$value'));
    } catch (_) {}
  }
  return const <String, String>{};
}

extension CsacStringsContext on BuildContext {
  CsacStrings get strings => CsacStrings.of(this);
}
