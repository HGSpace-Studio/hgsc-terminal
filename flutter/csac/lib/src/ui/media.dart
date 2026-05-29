part of '../../main.dart';

class _MessageImage extends StatelessWidget {
  const _MessageImage({required this.url, this.heroTag, this.onTap});

  final String url;
  final Object? heroTag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final image = Image.network(
      url,
      width: 260,
      height: 180,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: 260,
          height: 120,
          color: colors.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(
            Icons.broken_image_outlined,
            size: 42,
            color: colors.onSurfaceVariant,
          ),
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return Container(
          width: 260,
          height: 120,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: heroTag == null
            ? image
            : Hero(
                tag: heroTag!,
                child: Material(type: MaterialType.transparency, child: image),
              ),
      ),
    );
  }
}

class _ImageCaptionDialog extends StatefulWidget {
  const _ImageCaptionDialog({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;

  @override
  State<_ImageCaptionDialog> createState() => _ImageCaptionDialogState();
}

class _ImageCaptionDialogState extends State<_ImageCaptionDialog> {
  final caption = TextEditingController();

  @override
  void dispose() {
    caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        strings.format('Send image: {fileName}', {'fileName': widget.fileName}),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 260,
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: colors.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(
              widget.bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
                Icons.image_outlined,
                size: 48,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: caption,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: strings.text('Caption'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(caption.text),
          icon: const Icon(Icons.send),
          label: Text(strings.text('Send')),
        ),
      ],
    );
  }
}

void showImagePreview(BuildContext context, String url, {Object? heroTag}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: 260.ms,
      reverseTransitionDuration: 220.ms,
      pageBuilder: (_, animation, _) =>
          _ImagePreviewRoute(url: url, heroTag: heroTag, animation: animation),
    ),
  );
}

class _ImagePreviewRoute extends StatelessWidget {
  const _ImagePreviewRoute({
    required this.url,
    required this.animation,
    this.heroTag,
  });

  final String url;
  final Object? heroTag;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final image = Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Icon(
        Icons.broken_image_outlined,
        size: 64,
        color: Colors.white70,
      ),
    );
    return FadeTransition(
      opacity: animation,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.7,
                  maxScale: 5,
                  child: heroTag == null
                      ? image
                      : Hero(
                          tag: heroTag!,
                          child: Material(
                            type: MaterialType.transparency,
                            child: image,
                          ),
                        ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: strings.text('Copy link'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: url));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(strings.text('Image link copied')),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: strings.text('Open'),
                      onPressed: () => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: strings.text('Download'),
                      onPressed: () => downloadImage(context, url),
                      icon: const Icon(Icons.download_outlined),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> downloadImage(BuildContext context, String url) async {
  await downloadUrl(
    context,
    url,
    suggestedName:
        'csac_${DateTime.now().millisecondsSinceEpoch}${normalizedImageExtension(Uri.parse(url).path)}',
    typeLabel: context.strings.text('Images'),
    extensions: imageExtensions,
  );
}

Future<void> downloadUrl(
  BuildContext context,
  String url, {
  String suggestedName = '',
  String typeLabel = '',
  List<String> extensions = const <String>[],
}) async {
  final strings = context.strings;
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final uri = Uri.parse(url);
    final fallbackExt = extensions.isEmpty
        ? p.extension(uri.path)
        : '.${extensions.first}';
    final fileName = suggestedName.trim().isEmpty
        ? defaultDownloadName(url, fallbackExtension: fallbackExt)
        : suggestedName.trim();
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: extensions.isEmpty
          ? const <XTypeGroup>[]
          : <XTypeGroup>[XTypeGroup(label: typeLabel, extensions: extensions)],
    );
    if (location == null) {
      return;
    }
    var path = location.path;
    if (p.extension(path).isEmpty) {
      final activeExt = location.activeFilter?.extensions?.firstOrNull;
      final ext = activeExt ?? fallbackExt.replaceFirst('.', '');
      if (ext.isNotEmpty) {
        path = '$path.$ext';
      }
    }
    final file = XFile.fromData(
      response.bodyBytes,
      name: p.basename(path),
      mimeType: mimeTypeForExtension(p.extension(path)),
    );
    await file.saveTo(path);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.format('Saved to {path}', {'path': path})),
      ),
    );
  } catch (err) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.format('Download failed: {error}', {'error': err}),
        ),
      ),
    );
  }
}

const imageExtensions = <String>['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];

const voiceExtensions = <String>[
  'mp3',
  'm4a',
  'aac',
  'wav',
  'ogg',
  'webm',
  'amr',
  'flac',
];

String normalizedImageExtension(String path) {
  final ext = p.extension(path).toLowerCase();
  if (ext.isEmpty) {
    return '.jpg';
  }
  final bare = ext.replaceFirst('.', '');
  if (imageExtensions.contains(bare)) {
    return ext;
  }
  return '.jpg';
}

String defaultDownloadName(String url, {String fallbackExtension = ''}) {
  final fromUrl = fileNameFromUrl(url);
  if (fromUrl.isNotEmpty && p.extension(fromUrl).isNotEmpty) {
    return fromUrl;
  }
  final extension = fallbackExtension.isEmpty ? '.bin' : fallbackExtension;
  return 'csac_${DateTime.now().millisecondsSinceEpoch}$extension';
}

String mimeTypeForExtension(String extension) {
  switch (extension.toLowerCase().replaceFirst('.', '')) {
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
      return 'audio/mp4';
    case 'aac':
      return 'audio/aac';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
      return 'audio/ogg';
    case 'webm':
      return 'audio/webm';
    case 'amr':
      return 'audio/amr';
    case 'flac':
      return 'audio/flac';
    case 'pdf':
      return 'application/pdf';
    case 'zip':
      return 'application/zip';
    case 'json':
      return 'application/json';
    case 'txt':
    case 'md':
    case 'csv':
      return 'text/plain';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    default:
      return 'application/octet-stream';
  }
}
