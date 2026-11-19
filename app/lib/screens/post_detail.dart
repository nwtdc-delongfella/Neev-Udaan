import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import 'create_post.dart' show layouts;

class PostDetailScreen extends StatefulWidget {
  final String workspaceId;
  final Brand brand;
  final String postId;
  const PostDetailScreen({super.key, required this.workspaceId, required this.brand, required this.postId});
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  bool _busy = false;
  Api get api => Api.instance;

  Future<Uint8List?> _bytes(Post p) async => p.imagePath == null ? null : api.downloadBytes(p.imagePath!);

  String _fileName(Post p) => '${widget.brand.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-${p.id}.png';

  Future<void> _share(Post p) async {
    final bytes = await _bytes(p);
    if (bytes == null) return;
    await Clipboard.setData(ClipboardData(text: p.fullCaption));
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png', name: _fileName(p))],
      text: p.fullCaption,
    ));
    if (mounted) showInfo(context, 'Caption copied too: paste it when you post.');
  }

  Future<void> _download(Post p) async {
    final bytes = await _bytes(p);
    if (bytes == null) return;
    final uri = await FilePicker.saveFile(fileName: _fileName(p), bytes: bytes, mimeType: 'image/png');
    if (uri != null && mounted) showInfo(context, 'Image saved.');
  }

  Future<void> _relayout(Post p, {String? layout, String? headline}) async {
    setState(() => _busy = true);
    try {
      await api.relayoutPost(widget.workspaceId, widget.brand.id, p.id, layout: layout, headline: headline);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editHeadline(Post p) async {
    final c = TextEditingController(text: p.headline);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit headline'),
        content: TextField(controller: c, autofocus: true, maxLength: 80),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Update')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty && v != p.headline) await _relayout(p, headline: v);
  }

  Future<void> _delete(Post p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text('The image will be removed for everyone in this workspace.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await api.deletePost(widget.workspaceId, widget.brand.id, p.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Post?>(
      stream: api.post(widget.workspaceId, widget.brand.id, widget.postId),
      builder: (context, snap) {
        final p = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(p?.title ?? 'Post'),
            actions: [if (p != null) IconButton(onPressed: () => _delete(p), icon: const Icon(Icons.delete_outline))],
          ),
          body: p == null
              ? const Center(child: CircularProgressIndicator())
              : Constrained(
                  maxWidth: 640,
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: p.aspect,
                        child: Stack(fit: StackFit.expand, children: [
                          if (p.status == 'ready')
                            StorageImage(key: ValueKey(p.imagePath), path: p.imagePath, resolve: api.downloadUrl)
                          else if (p.status == 'failed')
                            ColoredBox(
                              color: Theme.of(context).colorScheme.errorContainer,
                              child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(p.error ?? 'Failed'))),
                            )
                          else
                            const ColoredBox(
                              color: Colors.black12,
                              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Creating your image…'),
                              ])),
                            ),
                          if (_busy) const ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator())),
                        ]),
                      ),
                    ),
                    if (p.status == 'ready') ...[
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final e in layouts.entries)
                          ChoiceChip(
                            label: Text(e.value.$1),
                            selected: p.layout == e.key,
                            onSelected: _busy ? null : (_) => _relayout(p, layout: e.key),
                          ),
                        ActionChip(avatar: const Icon(Icons.edit, size: 18), label: const Text('Edit headline'), onPressed: _busy ? null : () => _editHeadline(p)),
                      ]),
                      const SizedBox(height: 4),
                      Text('Changing the layout or headline is free: it reuses the same AI image.',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: FilledButton.icon(onPressed: () => _share(p), icon: const Icon(Icons.share), label: const Text('Share'))),
                        const SizedBox(width: 12),
                        Expanded(child: OutlinedButton.icon(onPressed: () => _download(p), icon: const Icon(Icons.download), label: const Text('Save image'))),
                      ]),
                    ],
                    const SizedBox(height: 24),
                    Row(children: [
                      Text('Caption', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: p.fullCaption));
                          if (context.mounted) showInfo(context, 'Caption copied.');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                    ]),
                    SelectableText(p.fullCaption),
                    const SizedBox(height: 24),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.schedule_send_outlined),
                        title: const Text('Post directly to Instagram, Facebook and Google'),
                        subtitle: const Text('Coming in the next update. For now, use Share or Save image.'),
                      ),
                    ),
                  ]),
                ),
        );
      },
    );
  }
}
