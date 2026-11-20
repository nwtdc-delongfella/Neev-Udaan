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
  final bool setupComplete;
  final Map<String, Map<String, dynamic>> channels;

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
    this.setupComplete = true,
    this.channels = const {},
  });

  Map<String, dynamic>? channel(Provider p) => channels[p.name];

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
        // Brands created before the connect step existed count as set up.
        setupComplete: d['setupComplete'] as bool? ?? true,
        channels: ((d['channels'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
        ),
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

/// The three platforms a brand can connect.
enum Provider {
  facebook('Facebook', 'Facebook Page', Icons.facebook, Color(0xFF1877F2)),
  instagram('Instagram', 'Instagram account', Icons.camera_alt_outlined, Color(0xFFC13584)),
  google('Google', 'Google Business Profile', Icons.storefront_outlined, Color(0xFF34A853));

  final String label, profileLabel;
  final IconData icon;
  final Color color;
  const Provider(this.label, this.profileLabel, this.icon, this.color);
}

class Candidate {
  final String id, name;
  final String? subtitle, pictureUrl;
  final List<String> issues;
  final String? instagramUsername;
  Candidate.fromMap(Map m)
      : id = m['id'] as String,
        name = m['name'] as String? ?? '',
        subtitle = m['subtitle'] as String?,
        pictureUrl = m['pictureUrl'] as String?,
        issues = ((m['issues'] as List?) ?? []).cast<String>(),
        instagramUsername = (m['instagram'] as Map?)?['username'] as String?;
}

/// Server-written status of one platform connection for a brand.
class Connection {
  final Provider provider;
  final String status; // waiting | connected | problem
  final String? accountName, selectedId;
  final List<Candidate> candidates;
  final List<String> issues;
  final List<String> missingPermissions;

  Connection.fromDoc(this.provider, Map<String, dynamic> d)
      : status = d['status'] as String? ?? 'waiting',
        accountName = d['accountName'] as String?,
        selectedId = d['selectedId'] as String?,
        candidates = ((d['candidates'] as List?) ?? []).map((e) => Candidate.fromMap(e as Map)).toList(),
        issues = ((d['issues'] as List?) ?? []).cast<String>(),
        missingPermissions = ((d['missingPermissions'] as List?) ?? []).cast<String>();

  Candidate? get selected => candidates.where((c) => c.id == selectedId).firstOrNull;
}
