import 'package:material_ui/material_ui.dart';

Color colorFromHex(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse(h.length == 6 ? 'FF$h' : h, radix: 16));
}

String colorToHex(Color c) {
  String two(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}

class BrandColors {
  final String primary, secondary, accent, onPrimary;
  const BrandColors({required this.primary, required this.secondary, required this.accent, required this.onPrimary});

  factory BrandColors.fromMap(Map<String, dynamic>? m) => BrandColors(
        primary: m?['primary'] ?? '#1F4E79',
        secondary: m?['secondary'] ?? '#F2A541',
        accent: m?['accent'] ?? '#2E8B57',
        onPrimary: m?['onPrimary'] ?? '#FFFFFF',
      );

  Map<String, dynamic> toMap() =>
      {'primary': primary, 'secondary': secondary, 'accent': accent, 'onPrimary': onPrimary};

  BrandColors copyWith({String? primary, String? secondary, String? accent, String? onPrimary}) => BrandColors(
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        accent: accent ?? this.accent,
        onPrimary: onPrimary ?? this.onPrimary,
      );

  /// White or near-black text, whichever reads better on [primary].
  static String readableOn(String hex) =>
      colorFromHex(hex).computeLuminance() > 0.4 ? '#111111' : '#FFFFFF';
}

class Brand {
  final String id;
  final String name, industry;
  final String? description, location, audience, tone, language, website, phone, logoPath;
  final BrandColors colors;
  final String colorSource;
  final List<String> logoPalette;

  Brand({
    required this.id,
    required this.name,
    required this.industry,
    this.description,
    this.location,
    this.audience,
    this.tone,
    this.language,
    this.website,
    this.phone,
    this.logoPath,
    required this.colors,
    required this.colorSource,
    this.logoPalette = const [],
  });

  factory Brand.fromDoc(String id, Map<String, dynamic> d) => Brand(
        id: id,
        name: d['name'] ?? '',
        industry: d['industry'] ?? '',
        description: d['description'],
        location: d['location'],
        audience: d['audience'],
        tone: d['tone'],
        language: d['language'],
        website: d['website'],
        phone: d['phone'],
        logoPath: d['logoPath'],
        colors: BrandColors.fromMap((d['colors'] as Map?)?.cast<String, dynamic>()),
        colorSource: d['colorSource'] ?? 'custom',
        logoPalette: ((d['logoPalette'] as List?) ?? []).map((e) => (e as Map)['hex'] as String).toList(),
      );
}

class Idea {
  final String title, angle, headline, subline, caption, imagePrompt;
  final List<String> hashtags;
  Idea.fromMap(Map m)
      : title = m['title'] ?? '',
        angle = m['angle'] ?? '',
        headline = m['headline'] ?? '',
        subline = m['subline'] ?? '',
        caption = m['caption'] ?? '',
        imagePrompt = m['imagePrompt'] ?? '',
        hashtags = ((m['hashtags'] as List?) ?? []).cast<String>();
}

enum Platform {
  instagram('Instagram', Icons.camera_alt_outlined),
  facebook('Facebook', Icons.facebook),
  google('Google Business', Icons.storefront_outlined);

  final String label;
  final IconData icon;
  const Platform(this.label, this.icon);
}

class Post {
  final String id, status, platform, format, layout, headline, caption;
  final String? subline, imagePath, error, title;
  final List<String> hashtags;
  final DateTime? createdAt;

  Post.fromDoc(this.id, Map<String, dynamic> d)
      : status = d['status'] ?? 'generating',
        platform = d['platform'] ?? 'instagram',
        format = d['format'] ?? 'square',
        layout = d['layout'] ?? 'band',
        headline = d['headline'] ?? '',
        subline = d['subline'],
        caption = d['caption'] ?? '',
        title = d['title'],
        imagePath = d['imagePath'],
        error = d['error'],
        hashtags = ((d['hashtags'] as List?) ?? []).cast<String>(),
        createdAt = (d['createdAt'] as dynamic)?.toDate();

  String get fullCaption => [caption, if (hashtags.isNotEmpty) hashtags.map((h) => '#$h').join(' ')].join('\n\n');
  double get aspect => switch (format) { 'portrait' => 4 / 5, 'landscape' => 4 / 3, _ => 1.0 };
}
