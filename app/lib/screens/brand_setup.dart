import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart' show ColorPicker;
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';

const tones = [
  'friendly and professional', 'warm and caring', 'fun and playful', 'premium and elegant',
  'bold and energetic', 'calm and reassuring', 'expert and informative',
];

class BrandSetupScreen extends StatefulWidget {
  final String workspaceId;
  final Brand brand;
  const BrandSetupScreen({super.key, required this.workspaceId, required this.brand});
  @override
  State<BrandSetupScreen> createState() => _BrandSetupScreenState();
}

class _BrandSetupScreenState extends State<BrandSetupScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late String _tone;
  late BrandColors _colors;
  late String _colorSource;
  List<String> _palette = [];
  bool _uploading = false;
  bool _saving = false;

  Api get api => Api.instance;

  @override
  void initState() {
    super.initState();
    _load(widget.brand);
  }

  @override
  void didUpdateWidget(BrandSetupScreen old) {
    super.didUpdateWidget(old);
    if (old.brand.id != widget.brand.id) setState(() => _load(widget.brand));
  }

  void _load(Brand b) {
    _c = {
      'name': TextEditingController(text: b.name),
      'industry': TextEditingController(text: b.industry),
      'description': TextEditingController(text: b.description),
      'location': TextEditingController(text: b.location),
      'audience': TextEditingController(text: b.audience),
      'language': TextEditingController(text: b.language),
      'website': TextEditingController(text: b.website),
      'phone': TextEditingController(text: b.phone),
    };
    _tone = tones.contains(b.tone) ? b.tone! : tones.first;
    _colors = b.colors;
    _colorSource = b.colorSource;
    _palette = b.logoPalette;
  }

  Future<void> _pickLogo() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg', 'webp']);
    final file = files.singleOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 5 * 1024 * 1024) return showError(context, 'Please choose a logo under 5 MB.');
    setState(() => _uploading = true);
    try {
      await api.uploadLogo(widget.workspaceId, widget.brand.id, bytes, file.extension ?? 'png');
      final r = await api.extractBrandColors(widget.workspaceId, widget.brand.id);
      setState(() {
        _palette = r.palette;
        _colors = r.suggested;
        _colorSource = 'logo';
      });
      if (mounted) showInfo(context, 'Logo uploaded. We picked your brand colors from it. Save to keep them.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editColor(String role) async {
    final current = switch (role) { 'primary' => _colors.primary, 'secondary' => _colors.secondary, _ => _colors.accent };
    Color picked = colorFromHex(current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Choose $role color'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_palette.isNotEmpty) ...[
              const Align(alignment: Alignment.centerLeft, child: Text('From your logo')),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final h in _palette)
                  InkWell(
                    onTap: () {
                      picked = colorFromHex(h);
                      Navigator.pop(c, true);
                    },
                    child: CircleAvatar(backgroundColor: colorFromHex(h)),
                  ),
              ]),
              const Divider(height: 32),
            ],
            ColorPicker(pickerColor: picked, onColorChanged: (v) => picked = v, enableAlpha: false, hexInputBar: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Use color')),
        ],
      ),
    );
    if (ok != true) return;
    final hex = colorToHex(picked);
    setState(() {
      _colors = switch (role) {
        'primary' => _colors.copyWith(primary: hex, onPrimary: BrandColors.readableOn(hex)),
        'secondary' => _colors.copyWith(secondary: hex),
        _ => _colors.copyWith(accent: hex),
      };
      _colorSource = 'custom';
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await api.updateBrand(widget.workspaceId, widget.brand.id, {
        for (final e in _c.entries) e.key: e.value.text.trim(),
        'tone': _tone,
        'colors': _colors.toMap(),
        'colorSource': _colorSource,
      });
      if (mounted) showInfo(context, 'Brand saved.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {String? hint, int lines = 1, bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _c[key],
          minLines: lines,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: required ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final logoPath = widget.brand.logoPath;
    return Form(
      key: _form,
      child: Constrained(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Logo', style: t.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 96,
              height: 96,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: logoPath == null
                  ? const Icon(Icons.image_outlined, size: 40, color: Colors.black26)
                  : StorageImage(key: ValueKey(logoPath), path: logoPath, resolve: api.downloadUrl, fit: BoxFit.contain),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FilledButton.tonalIcon(
                  onPressed: _uploading ? null : _pickLogo,
                  icon: _uploading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload),
                  label: Text(logoPath == null ? 'Upload logo' : 'Replace logo'),
                ),
                const SizedBox(height: 6),
                Text('PNG with a transparent background works best.', style: t.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 28),
          Text('Brand colors', style: t.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'logo', label: Text('From my logo'), icon: Icon(Icons.colorize)),
              ButtonSegment(value: 'custom', label: Text('Choose my own'), icon: Icon(Icons.tune)),
            ],
            selected: {_colorSource},
            onSelectionChanged: (s) async {
              final v = s.first;
              if (v == 'logo') {
                if (logoPath == null) return showError(context, 'Upload a logo first.');
                setState(() => _uploading = true);
                try {
                  final r = await api.extractBrandColors(widget.workspaceId, widget.brand.id);
                  setState(() {
                    _palette = r.palette;
                    _colors = r.suggested;
                  });
                } catch (e) {
                  if (context.mounted) showError(context, e);
                } finally {
                  if (mounted) setState(() => _uploading = false);
                }
              }
              setState(() => _colorSource = v);
            },
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 20, runSpacing: 12, children: [
            Swatch(hex: _colors.primary, label: 'Primary', onTap: () => _editColor('primary')),
            Swatch(hex: _colors.secondary, label: 'Secondary', onTap: () => _editColor('secondary')),
            Swatch(hex: _colors.accent, label: 'Accent', onTap: () => _editColor('accent')),
          ]),
          const SizedBox(height: 8),
          Text('Tap a color to change it.', style: t.bodySmall),
          const SizedBox(height: 28),
          Text('About the business', style: t.titleMedium),
          const SizedBox(height: 12),
          _field('name', 'Business name', required: true),
          _field('industry', 'Industry', required: true),
          _field('description', 'What you offer', hint: 'e.g. Family dental care, implants and braces', lines: 3),
          _field('location', 'City / area', hint: 'e.g. Andheri West, Mumbai'),
          _field('audience', 'Who are your customers?', hint: 'e.g. Families and working professionals'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              initialValue: _tone,
              decoration: const InputDecoration(labelText: 'Tone of voice'),
              items: [for (final x in tones) DropdownMenuItem(value: x, child: Text(x))],
              onChanged: (v) => setState(() => _tone = v!),
            ),
          ),
          _field('language', 'Caption language', hint: 'e.g. English, Hindi, Hinglish, Marathi'),
          _field('website', 'Website (shown on posts)'),
          _field('phone', 'Phone (shown on posts)'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_saving ? 'Saving…' : 'Save brand')),
          ),
        ]),
      ),
    );
  }
}
