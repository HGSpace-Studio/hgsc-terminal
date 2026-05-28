part of '../../main.dart';

String compactMessage(String text, {int max = 80}) {
  final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.length <= max) {
    return value;
  }
  return '${value.substring(0, max - 3)}...';
}

CsacTimestampPattern timestampPatternForPreference(MessageTimeFormat format) {
  switch (format) {
    case MessageTimeFormat.slash:
      return CsacTimestampPattern.slash;
    case MessageTimeFormat.dash:
      return CsacTimestampPattern.dash;
    case MessageTimeFormat.compact:
      return CsacTimestampPattern.compact;
    case MessageTimeFormat.timeOnly:
      return CsacTimestampPattern.timeOnly;
  }
}

String displayMessageTime(ChatMessage message, CsacPreferences preferences) {
  return formatCsacTimestamp(
    message.timeSortValue > 0 ? message.timeSortValue : message.time,
    pattern: timestampPatternForPreference(preferences.messageTimeFormat),
  );
}

String messageTimeFormatLabelFor(
  BuildContext context,
  MessageTimeFormat format,
) {
  switch (format) {
    case MessageTimeFormat.slash:
      return context.strings.text('yyyy/mm/dd hh:mm:ss');
    case MessageTimeFormat.dash:
      return context.strings.text('yyyy-mm-dd hh:mm:ss');
    case MessageTimeFormat.compact:
      return context.strings.text('mm/dd hh:mm');
    case MessageTimeFormat.timeOnly:
      return context.strings.text('hh:mm:ss');
  }
}

String messageTimeFormatExampleFor(MessageTimeFormat format) {
  final sample = DateTime(2026, 5, 28, 21, 30, 15);
  switch (format) {
    case MessageTimeFormat.slash:
      return formatLocalDateTime(sample, separator: '/');
    case MessageTimeFormat.dash:
      return formatLocalDateTime(sample, separator: '-');
    case MessageTimeFormat.compact:
      return formatCompactLocalDateTime(sample);
    case MessageTimeFormat.timeOnly:
      return formatLocalTime(sample);
  }
}

Future<String> persistChatBackground(XFile picked) async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory(p.join(support.path, 'backgrounds'));
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  final extension = p.extension(picked.name).trim().isEmpty
      ? '.jpg'
      : p.extension(picked.name);
  final target = File(
    p.join(
      directory.path,
      'chat_background_${DateTime.now().millisecondsSinceEpoch}$extension',
    ),
  );
  final bytes = await picked.readAsBytes();
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(message, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
