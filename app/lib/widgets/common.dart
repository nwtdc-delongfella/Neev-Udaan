import 'package:material_ui/material_ui.dart';

import '../models.dart';

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Centers content and caps its width so screens read well on desktop.
class Constrained extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const Constrained({super.key, required this.child, this.maxWidth = 720});
  @override
  Widget build(BuildContext context) =>
      Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

class Swatch extends StatelessWidget {
  final String hex;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;
  final double size;
  const Swatch({super.key, required this.hex, this.label, this.selected = false, this.onTap, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colorFromHex(hex),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 3 : 1),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label!, style: Theme.of(context).textTheme.labelSmall),
        ],
        Text(hex, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline)),
      ]),
    );
  }
}

/// Image from a Firebase Storage path (resolves the download URL first).
class StorageImage extends StatelessWidget {
  final String? path;
  final BoxFit fit;
  final Future<String> Function(String path) resolve;
  const StorageImage({super.key, required this.path, required this.resolve, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (path == null) return const ColoredBox(color: Colors.black12);
    return FutureBuilder<String>(
      future: resolve(path!),
      builder: (context, snap) => snap.hasData
          ? Image.network(snap.data!, fit: fit, key: ValueKey(snap.data))
          : const ColoredBox(color: Colors.black12, child: Center(child: CircularProgressIndicator())),
    );
  }
}
