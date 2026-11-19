import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import 'post_detail.dart';

const layouts = {
  'band': ('Headline band', Icons.call_to_action_outlined),
  'top': ('Headline on top', Icons.vertical_align_top),
  'minimal': ('Logo only', Icons.crop_original),
};

const topicExamples = [
  'Monsoon offer for new customers',
  'Tips to stay healthy this festive season',
  'Meet our team',
  'Why customers choose us',
];

/// Step 1: topic → Step 2: pick an idea → Step 3: generate the image post.
class CreatePostScreen extends StatefulWidget {
  final String workspaceId;
  final Brand brand;
  final VoidCallback onOpenBrand;
  const CreatePostScreen({super.key, required this.workspaceId, required this.brand, required this.onOpenBrand});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _topic = TextEditingController();
  final _headline = TextEditingController();
  Platform _platform = Platform.instagram;
  String _layout = 'band';
  String _format = 'square';
  bool _loadingIdeas = false;
  bool _generating = false;
  String? _ideaSetId;
  List<Idea> _ideas = [];
  int? _selected;

  Api get api => Api.instance;

  @override
  void didUpdateWidget(CreatePostScreen old) {
    super.didUpdateWidget(old);
    if (old.brand.id != widget.brand.id) {
      setState(() {
        _ideas = [];
        _ideaSetId = null;
        _selected = null;
      });
    }
  }

  void _setPlatform(Platform p) => setState(() {
        _platform = p;
        _format = p == Platform.google ? 'landscape' : 'square';
      });

  Future<void> _getIdeas() async {
    if (_topic.text.trim().length < 3) return showError(context, 'Type a topic first.');
    setState(() {
      _loadingIdeas = true;
      _selected = null;
    });
    try {
      final r = await api.generateIdeas(widget.workspaceId, widget.brand.id, topic: _topic.text.trim(), platform: _platform);
      setState(() {
        _ideaSetId = r.ideaSetId;
        _ideas = r.ideas;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingIdeas = false);
    }
  }

  void _select(int i) => setState(() {
        _selected = i;
        _headline.text = _ideas[i].headline;
      });

  Future<void> _generate() async {
    if (_selected == null || _ideaSetId == null) return;
    setState(() => _generating = true);
    try {
      final postId = await api.generatePost(widget.workspaceId, widget.brand.id,
          ideaSetId: _ideaSetId!, ideaIndex: _selected!, format: _format, layout: _layout, headline: _headline.text.trim());
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(workspaceId: widget.workspaceId, brand: widget.brand, postId: postId),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final needsSetup = widget.brand.logoPath == null;

    return Constrained(
      maxWidth: 860,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        if (needsSetup)
          Card(
            color: scheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Add your logo and colors'),
              subtitle: const Text('Posts look much better with your real logo and brand colors.'),
              trailing: TextButton(onPressed: widget.onOpenBrand, child: const Text('Set up')),
            ),
          ),
        const SizedBox(height: 8),
        Text('What should the post be about?', style: t.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _topic,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _getIdeas(),
          decoration: const InputDecoration(hintText: 'e.g. Free check-up camp this Sunday'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final e in topicExamples) ActionChip(label: Text(e), onPressed: () => _topic.text = e),
        ]),
        const SizedBox(height: 16),
        Text('Where will you post it?', style: t.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<Platform>(
          segments: [for (final p in Platform.values) ButtonSegment(value: p, label: Text(p.label), icon: Icon(p.icon))],
          selected: {_platform},
          onSelectionChanged: (s) => _setPlatform(s.first),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loadingIdeas ? null : _getIdeas,
          icon: _loadingIdeas
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lightbulb_outline),
          label: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(_loadingIdeas ? 'Thinking of ideas…' : (_ideas.isEmpty ? 'Get ideas' : 'Get new ideas')),
          ),
        ),
        if (_ideas.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Pick an idea', style: t.titleLarge),
          const SizedBox(height: 8),
          for (var i = 0; i < _ideas.length; i++) _IdeaCard(idea: _ideas[i], selected: _selected == i, onTap: () => _select(i)),
        ],
        if (_selected != null) ...[
          const SizedBox(height: 28),
          Text('Design', style: t.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _headline, decoration: const InputDecoration(labelText: 'Headline on the image')),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in layouts.entries)
              ChoiceChip(
                avatar: Icon(e.value.$2, size: 18),
                label: Text(e.value.$1),
                selected: _layout == e.key,
                onSelected: (_) => setState(() => _layout = e.key),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in const {'square': 'Square 1:1', 'portrait': 'Portrait 4:5', 'landscape': 'Landscape 4:3'}.entries)
              ChoiceChip(label: Text(f.value), selected: _format == f.key, onSelected: (_) => setState(() => _format = f.key)),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_generating ? 'Creating your post… (about 20 seconds)' : 'Create image post'),
            ),
          ),
          const SizedBox(height: 6),
          Text('Uses 1 AI image from your monthly allowance.', style: t.bodySmall, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 40),
      ]),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  final Idea idea;
  final bool selected;
  final VoidCallback onTap;
  const _IdeaCard({required this.idea, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: selected ? 3 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(idea.title, style: t.titleMedium)),
              if (selected) Icon(Icons.check_circle, color: scheme.primary),
            ]),
            const SizedBox(height: 4),
            Text(idea.angle, style: t.bodySmall?.copyWith(color: scheme.outline)),
            const SizedBox(height: 10),
            Text('“${idea.headline}”', style: t.titleSmall?.copyWith(color: scheme.primary)),
            const SizedBox(height: 8),
            Text(idea.caption, maxLines: selected ? null : 3, overflow: selected ? null : TextOverflow.ellipsis),
            if (selected && idea.hashtags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(idea.hashtags.map((h) => '#$h').join(' '), style: t.bodySmall?.copyWith(color: scheme.primary)),
            ],
          ]),
        ),
      ),
    );
  }
}
