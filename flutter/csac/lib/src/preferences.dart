import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum CsacLanguage { en, zh }

enum ConversationSortMode { latest, type }

enum MessageTimeFormat { slash, dash, compact, timeOnly }

const defaultThemeColorValue = 0xff1f8a70;

class CsacPreferences {
  const CsacPreferences({
    this.themeMode = ThemeMode.system,
    this.themeColorValue = defaultThemeColorValue,
    this.language = CsacLanguage.zh,
    this.conversationSortMode = ConversationSortMode.latest,
    this.messageTimeFormat = MessageTimeFormat.slash,
    this.chatBackgroundPath = '',
    this.serverUrl = '',
  });

  static const _themeKey = 'csac.theme_mode';
  static const _themeColorKey = 'csac.theme_color';
  static const _languageKey = 'csac.language';
  static const _conversationSortModeKey = 'csac.conversation_sort_mode';
  static const _messageTimeFormatKey = 'csac.message_time_format';
  static const _chatBackgroundPathKey = 'csac.chat_background_path';
  static const _serverUrlKey = 'csac.server_url';

  final ThemeMode themeMode;
  final int themeColorValue;
  final CsacLanguage language;
  final ConversationSortMode conversationSortMode;
  final MessageTimeFormat messageTimeFormat;
  final String chatBackgroundPath;
  final String serverUrl;

  CsacPreferences copyWith({
    ThemeMode? themeMode,
    int? themeColorValue,
    CsacLanguage? language,
    ConversationSortMode? conversationSortMode,
    MessageTimeFormat? messageTimeFormat,
    String? chatBackgroundPath,
    String? serverUrl,
  }) {
    return CsacPreferences(
      themeMode: themeMode ?? this.themeMode,
      themeColorValue: themeColorValue ?? this.themeColorValue,
      language: language ?? this.language,
      conversationSortMode: conversationSortMode ?? this.conversationSortMode,
      messageTimeFormat: messageTimeFormat ?? this.messageTimeFormat,
      chatBackgroundPath: chatBackgroundPath ?? this.chatBackgroundPath,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }

  static Future<CsacPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CsacPreferences(
      themeMode: _themeModeFromName(prefs.getString(_themeKey)),
      themeColorValue: _themeColorFromPrefs(prefs),
      language: _languageFromName(prefs.getString(_languageKey)),
      conversationSortMode: _conversationSortModeFromName(
        prefs.getString(_conversationSortModeKey),
      ),
      messageTimeFormat: _messageTimeFormatFromName(
        prefs.getString(_messageTimeFormatKey),
      ),
      chatBackgroundPath: prefs.getString(_chatBackgroundPathKey) ?? '',
      serverUrl: (prefs.getString(_serverUrlKey) ?? '').trim(),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, themeMode.name);
    await prefs.setInt(_themeColorKey, themeColorValue);
    await prefs.setString(_languageKey, language.name);
    await prefs.setString(_conversationSortModeKey, conversationSortMode.name);
    await prefs.setString(_messageTimeFormatKey, messageTimeFormat.name);
    if (chatBackgroundPath.trim().isEmpty) {
      await prefs.remove(_chatBackgroundPathKey);
    } else {
      await prefs.setString(_chatBackgroundPathKey, chatBackgroundPath.trim());
    }
    if (serverUrl.trim().isEmpty) {
      await prefs.remove(_serverUrlKey);
    } else {
      await prefs.setString(_serverUrlKey, serverUrl.trim());
    }
  }

  static ThemeMode _themeModeFromName(String? value) {
    for (final mode in ThemeMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return ThemeMode.system;
  }

  static int _themeColorFromPrefs(SharedPreferences prefs) {
    final value = prefs.getInt(_themeColorKey);
    if (value == null) {
      return defaultThemeColorValue;
    }
    return 0xff000000 | (value & 0x00ffffff);
  }

  static CsacLanguage _languageFromName(String? value) {
    for (final language in CsacLanguage.values) {
      if (language.name == value) {
        return language;
      }
    }
    return CsacLanguage.zh;
  }

  static ConversationSortMode _conversationSortModeFromName(String? value) {
    for (final mode in ConversationSortMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return ConversationSortMode.latest;
  }

  static MessageTimeFormat _messageTimeFormatFromName(String? value) {
    for (final format in MessageTimeFormat.values) {
      if (format.name == value) {
        return format;
      }
    }
    return MessageTimeFormat.slash;
  }
}

class ConversationDraftStore {
  const ConversationDraftStore._();

  static const _draftPrefix = 'csac.draft.';

  static String _key(Conversation conversation) {
    return '$_draftPrefix${conversation.type.name}:${conversation.id}';
  }

  static Future<String> load(Conversation conversation) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(conversation)) ?? '';
  }

  static Future<void> save(Conversation conversation, String text) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = text.trimRight();
    if (normalized.trim().isEmpty) {
      await prefs.remove(_key(conversation));
      return;
    }
    await prefs.setString(_key(conversation), normalized);
  }

  static Future<void> clear(Conversation conversation) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(conversation));
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_draftPrefix))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

class MentionNoticeStore {
  const MentionNoticeStore._();

  static const _readPrefix = 'csac.mention_notice.read.';
  static const _clearedPrefix = 'csac.mention_notice.cleared.';
  static const _summaryReadKey = 'csac.mention_notice.summary_read';
  static const _summaryClearedKey = 'csac.mention_notice.summary_cleared';

  static String _key(String prefix, MentionNotice notice) {
    return '$prefix${notice.conversation.type.name}:'
        '${notice.conversation.id}:${notice.message.id}:${notice.id}';
  }

  static Future<Set<String>> loadReadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getKeys().where((key) => key.startsWith(_readPrefix)).toSet();
  }

  static Future<Set<String>> loadClearedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((key) => key.startsWith(_clearedPrefix))
        .toSet();
  }

  static Future<bool> summaryRead() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_summaryReadKey) ?? false;
  }

  static Future<bool> summaryCleared() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_summaryClearedKey) ?? false;
  }

  static String readKey(MentionNotice notice) {
    return _key(_readPrefix, notice);
  }

  static String clearedKey(MentionNotice notice) {
    return _key(_clearedPrefix, notice);
  }

  static Future<void> markRead(MentionNotice notice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(readKey(notice), true);
  }

  static Future<void> markSummaryRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_summaryReadKey, true);
  }

  static Future<void> clear(MentionNotice notice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(readKey(notice), true);
    await prefs.setBool(clearedKey(notice), true);
  }

  static Future<void> clearSummary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_summaryReadKey, true);
    await prefs.setBool(_summaryClearedKey, true);
  }
}

class LoginAccountRecord {
  const LoginAccountRecord({
    required this.uid,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.serverUrl,
    required this.savedAt,
    this.sessionCookies = const <String, String>{},
  });

  final int uid;
  final String username;
  final String nickname;
  final String avatar;
  final String serverUrl;
  final int savedAt;
  final Map<String, String> sessionCookies;

  bool get hasSession => sessionCookies.isNotEmpty;

  String get displayName {
    if (nickname.trim().isNotEmpty) {
      return nickname.trim();
    }
    if (username.trim().isNotEmpty) {
      return username.trim();
    }
    return 'UID $uid';
  }

  String get subtitle {
    final parts = <String>[
      if (username.trim().isNotEmpty) '@${username.trim()}',
      if (uid > 0) 'UID $uid',
    ];
    return parts.join(' | ');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'uid': uid,
      'username': username,
      'nickname': nickname,
      'avatar': avatar,
      'serverUrl': serverUrl,
      'savedAt': savedAt,
      'sessionCookies': sessionCookies,
    };
  }

  factory LoginAccountRecord.fromJson(Map<String, dynamic> json) {
    final rawCookies = json['sessionCookies'];
    return LoginAccountRecord(
      uid: asInt(json['uid']),
      username: asString(json['username']),
      nickname: asString(json['nickname']),
      avatar: asString(json['avatar']),
      serverUrl: asString(json['serverUrl']),
      savedAt: asInt(json['savedAt']),
      sessionCookies: rawCookies is Map
          ? rawCookies.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }
}

class LoginAccountStore {
  const LoginAccountStore._();

  static const _accountsKey = 'csac.login_accounts';
  static const _maxAccounts = 12;

  static Future<List<LoginAccountRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <LoginAccountRecord>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <LoginAccountRecord>[];
      }
      final records = <LoginAccountRecord>[];
      for (final item in decoded) {
        if (item is Map) {
          final record = LoginAccountRecord.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (record.uid > 0 || record.username.trim().isNotEmpty) {
            records.add(record);
          }
        }
      }
      records.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return records;
    } catch (_) {
      return const <LoginAccountRecord>[];
    }
  }

  static Future<List<LoginAccountRecord>> loadForServer(
    String serverUrl,
  ) async {
    final normalized = _serverKey(serverUrl);
    final records = await loadAll();
    return records
        .where((record) => _serverKey(record.serverUrl) == normalized)
        .toList();
  }

  static Future<void> upsert({
    required CsacUser user,
    required String username,
    required String serverUrl,
    Map<String, String> sessionCookies = const <String, String>{},
  }) async {
    final normalizedUsername = username.trim().isEmpty
        ? user.username.trim()
        : username.trim();
    if (user.uid <= 0 && normalizedUsername.isEmpty) {
      return;
    }
    final records = await loadAll();
    final normalizedServer = _serverKey(serverUrl);
    final filtered = records.where((record) {
      if (_serverKey(record.serverUrl) != normalizedServer) {
        return true;
      }
      if (user.uid > 0 && record.uid == user.uid) {
        return false;
      }
      return normalizedUsername.isEmpty ||
          record.username.trim().toLowerCase() !=
              normalizedUsername.toLowerCase();
    }).toList();
    filtered.insert(
      0,
      LoginAccountRecord(
        uid: user.uid,
        username: normalizedUsername,
        nickname: user.nickname,
        avatar: user.avatar,
        serverUrl: normalizedServer,
        savedAt: DateTime.now().millisecondsSinceEpoch,
        sessionCookies: Map<String, String>.from(sessionCookies),
      ),
    );
    await _save(filtered.take(_maxAccounts).toList());
  }

  static Future<void> clearSession(LoginAccountRecord record) async {
    final records = await loadAll();
    final normalizedServer = _serverKey(record.serverUrl);
    await _save([
      for (final item in records)
        if (_sameAccount(item, record, normalizedServer))
          LoginAccountRecord(
            uid: item.uid,
            username: item.username,
            nickname: item.nickname,
            avatar: item.avatar,
            serverUrl: item.serverUrl,
            savedAt: item.savedAt,
          )
        else
          item,
    ]);
  }

  static Future<void> remove(LoginAccountRecord record) async {
    final records = await loadAll();
    final normalizedServer = _serverKey(record.serverUrl);
    await _save(
      records.where((item) {
        if (_serverKey(item.serverUrl) != normalizedServer) {
          return true;
        }
        if (record.uid > 0 && item.uid == record.uid) {
          return false;
        }
        return item.username.trim().toLowerCase() !=
            record.username.trim().toLowerCase();
      }).toList(),
    );
  }

  static Future<void> removeCurrent({
    required CsacUser user,
    required String serverUrl,
  }) async {
    await remove(
      LoginAccountRecord(
        uid: user.uid,
        username: user.username,
        nickname: user.nickname,
        avatar: user.avatar,
        serverUrl: _serverKey(serverUrl),
        savedAt: 0,
      ),
    );
  }

  static Future<void> _save(List<LoginAccountRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    if (records.isEmpty) {
      await prefs.remove(_accountsKey);
      return;
    }
    await prefs.setString(
      _accountsKey,
      jsonEncode([for (final record in records) record.toJson()]),
    );
  }

  static String _serverKey(String serverUrl) {
    return serverUrl.trim();
  }

  static bool _sameAccount(
    LoginAccountRecord item,
    LoginAccountRecord record,
    String normalizedServer,
  ) {
    if (_serverKey(item.serverUrl) != normalizedServer) {
      return false;
    }
    if (record.uid > 0 && item.uid == record.uid) {
      return true;
    }
    return item.username.trim().toLowerCase() ==
        record.username.trim().toLowerCase();
  }
}
