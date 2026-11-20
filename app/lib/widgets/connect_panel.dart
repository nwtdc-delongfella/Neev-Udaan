import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../guidance.dart';
import '../models.dart';
import '../services/api.dart';
import 'common.dart';

/// Cards for Facebook, Instagram and Google: connect, choose a profile, and fix problems.
class ConnectPanel extends StatelessWidget {
  final String workspaceId;
  final Brand brand;

  /// For previews and tests: supplies connection data instead of Firestore.
  final Stream<Connection?> Function(Provider)? connectionsOverride;
  const ConnectPanel({super.key, required this.workspaceId, required this.brand, this.connectionsOverride});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final p in Provider.values)
        ProviderCard(workspaceId: workspaceId, brand: brand, provider: p, connectionOverride: connectionsOverride?.call(p)),
    ]);
  }
}

class ProviderCard extends StatefulWidget {
  final String workspaceId;
  final Brand brand;
  final Provider provider;
  final Stream<Connection?>? connectionOverride;
  const ProviderCard(
      {super.key, required this.workspaceId, required this.brand, required this.provider, this.connectionOverride});
  @override
  State<ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<ProviderCard> {
  bool _busy = false;
  bool _changing = false;
  bool _autoSelected = false;
  bool _includeInstagram = true;

  Api get api => Api.instance;
  String get wid => widget.workspaceId;
  String get bid => widget.brand.id;
  Provider get p => widget.provider;

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn({Provider? provider, bool rerequest = false}) => _run(() async {
        final url = await api.startConnect(wid, bid, provider ?? p, rerequest: rerequest);
        final ok = await launchUrl(url, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
        if (!ok) throw ApiException('Could not open the sign-in page.');
      });

  Future<void> _checkAgain() => _run(() => api.refreshConnection(wid, bid, p));

  Future<void> _select(Candidate c) => _run(() async {
        final filled = await api.selectProfile(wid, bid, p, c.id, includeInstagram: _includeInstagram);
        setState(() => _changing = false);
        if (mounted && filled.isNotEmpty) {
          showInfo(context, 'Connected. We filled in your ${_describe(filled)} from ${c.name}.');
        }
      });

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Disconnect ${p.label}?'),
        content: Text('Neev Udaan will stop posting to this ${p.profileLabel}. You can connect again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok == true) await _run(() => api.disconnect(wid, bid, p));
  }

  void _act(GuidanceAction a) => switch (a) {
        GuidanceAction.signInAgain => _signIn(),
        GuidanceAction.reviewPermissions => _signIn(rerequest: true),
        GuidanceAction.checkAgain => _checkAgain(),
        GuidanceAction.instagramSignIn => _signIn(provider: Provider.instagram),
      };

  static String _describe(List<String> fields) {
    const names = {
      'name': 'business name',
      'industry': 'category',
      'phone': 'phone',
      'website': 'website',
      'location': 'address',
      'description': 'description',
      'logo': 'logo',
      'colors': 'brand colors',
    };
    final list = fields.map((f) => names[f] ?? f).toList();
    return list.length <= 1 ? list.join() : '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Connection?>(
      stream: widget.connectionOverride ?? api.connection(wid, bid, p),
      builder: (context, snap) {
        final conn = snap.data;
        final channel = widget.brand.channel(p);
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _header(context, conn, channel),
              const SizedBox(height: 12),
              ..._body(context, conn, channel),
            ]),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, Connection? conn, Map<String, dynamic>? channel) {
    final t = Theme.of(context).textTheme;
    final connected = channel != null;
    return Row(children: [
      CircleAvatar(backgroundColor: p.color, foregroundColor: Colors.white, child: Icon(p.icon)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.label, style: t.titleMedium),
          Text(
            connected ? 'Connected' : (conn?.accountName != null ? 'Signed in as ${conn!.accountName}' : 'Not connected'),
            style: t.bodySmall?.copyWith(color: connected ? Colors.green.shade700 : Theme.of(context).colorScheme.outline),
          ),
        ]),
      ),
      if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      if (conn != null && conn.status != 'waiting')
        PopupMenuButton<String>(
          onSelected: (v) => v == 'check' ? _checkAgain() : _disconnect(),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'check', child: Text('Check again')),
            const PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
          ],
        ),
    ]);
  }

  List<Widget> _body(BuildContext context, Connection? conn, Map<String, dynamic>? channel) {
    final t = Theme.of(context).textTheme;

    // Instagram is often connected through the Facebook Page; nothing more to do then.
    if (p == Provider.instagram && channel?['via'] == 'facebook' && conn == null) {
      return [
        _ProfileTile(
          name: '@${channel!['username']}',
          subtitle: 'Connected through your Facebook Page',
          pictureUrl: channel['pictureUrl'] as String?,
          selected: true,
        ),
      ];
    }

    if (conn == null) {
      final hint = switch (p) {
        Provider.facebook => 'Posts to your Facebook Page. Your Instagram connects with it automatically if it\'s linked.',
        Provider.instagram => 'Only needed if your Instagram is not linked to your Facebook Page.',
        Provider.google => 'Posts updates to your Google listing and lets you reply to reviews.',
      };
      return [
        Text(hint, style: t.bodyMedium),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: p.color),
          onPressed: _busy ? null : () => _signIn(),
          icon: Icon(p.icon),
          label: Text('Continue with ${p.label}'),
        ),
      ];
    }

    if (conn.status == 'waiting') {
      return [
        Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Text('Finish signing in to ${p.label} in your browser, then come back here.')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: _busy ? null : () => _signIn(), child: const Text('Open sign-in again')),
          TextButton(onPressed: _busy ? null : () => api.disconnect(wid, bid, p), child: const Text('Cancel')),
        ]),
      ];
    }

    final widgets = <Widget>[
      for (final code in conn.issues) GuidanceBox(code: code, onAction: _act, busy: _busy),
    ];

    final selected = conn.selected;
    if (selected != null && channel != null && !_changing) {
      final warnings = selected.issues.where((i) => !(i == 'IG_NOT_LINKED' && widget.brand.channel(Provider.instagram) != null));
      widgets.addAll([
        _ProfileTile(
          name: selected.name,
          subtitle: [
            selected.subtitle,
            if (p == Provider.facebook && widget.brand.channel(Provider.instagram)?['via'] == 'facebook')
              '+ Instagram @${widget.brand.channel(Provider.instagram)!['username']}',
          ].whereType<String>().join(' · '),
          pictureUrl: selected.pictureUrl,
          selected: true,
        ),
        for (final code in warnings) GuidanceBox(code: code, onAction: _act, busy: _busy),
        if (conn.candidates.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => setState(() => _changing = true), child: Text('Use a different ${p.profileLabel}')),
          ),
      ]);
      return widgets;
    }

    if (conn.candidates.isEmpty) return widgets;

    // Exactly one usable profile: pick it automatically to save a tap.
    final usable = conn.candidates.where((c) => !c.issues.any(blockingIssues.contains)).toList();
    if (usable.length == 1 && conn.candidates.length == 1 && !_autoSelected && !_changing && channel == null) {
      _autoSelected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _select(usable.single));
    }

    widgets.add(Text('Choose your ${p.profileLabel}', style: t.titleSmall));
    widgets.add(const SizedBox(height: 8));
    for (final c in conn.candidates) {
      final blocking = c.issues.where(blockingIssues.contains).toList();
      widgets.add(_ProfileTile(
        name: c.name,
        subtitle: [
          c.subtitle,
          if (p == Provider.facebook && c.instagramUsername != null) '+ Instagram @${c.instagramUsername}',
        ].whereType<String>().join(' · '),
        pictureUrl: c.pictureUrl,
        badges: c.issues.map(issueBadge).toList(),
        selected: c.id == conn.selectedId,
        onTap: _busy
            ? null
            : blocking.isNotEmpty
                ? () => showGuidanceSheet(context, blocking.first, _act)
                : () => _select(c),
      ));
    }
    // Only one profile and it can't be used: show how to fix it straight away.
    if (conn.candidates.length == 1) {
      for (final code in conn.candidates.single.issues.where(blockingIssues.contains)) {
        widgets.add(GuidanceBox(code: code, onAction: _act, busy: _busy));
      }
    }
    if (p == Provider.facebook && conn.candidates.any((c) => c.instagramUsername != null)) {
      widgets.add(SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _includeInstagram,
        onChanged: (v) => setState(() => _includeInstagram = v),
        title: const Text('Also post to the linked Instagram account'),
      ));
    }
    return widgets;
  }
}

class _ProfileTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final String? pictureUrl;
  final List<String> badges;
  final bool selected;
  final VoidCallback? onTap;
  const _ProfileTile({
    required this.name,
    this.subtitle,
    this.pictureUrl,
    this.badges = const [],
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: onTap,
          leading: CircleAvatar(
            backgroundImage: pictureUrl != null ? NetworkImage(pictureUrl!) : null,
            child: pictureUrl == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase()) : null,
          ),
          title: Text(name),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!),
            if (badges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final b in badges)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                      child: Text(b, style: TextStyle(fontSize: 12, color: scheme.onErrorContainer)),
                    ),
                ]),
              ),
          ]),
          trailing: selected ? Icon(Icons.check_circle, color: scheme.primary) : const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

/// A help box: what's wrong, why, numbered steps, and the button that fixes it.
class GuidanceBox extends StatelessWidget {
  final String code;
  final void Function(GuidanceAction) onAction;
  final bool busy;
  const GuidanceBox({super.key, required this.code, required this.onAction, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final g = guidanceFor(code);
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final bg = g.isWarning ? scheme.tertiaryContainer : scheme.errorContainer;
    final fg = g.isWarning ? scheme.onTertiaryContainer : scheme.onErrorContainer;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(g.isWarning ? Icons.info_outline : Icons.error_outline, color: fg),
            const SizedBox(width: 8),
            Expanded(child: Text(g.title, style: t.titleSmall?.copyWith(color: fg))),
          ]),
          const SizedBox(height: 6),
          Text(g.why),
          const SizedBox(height: 10),
          for (final (i, step) in g.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 22, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text(step)),
              ]),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton(onPressed: busy ? null : () => onAction(g.action), child: Text(g.actionLabel)),
            if (g.secondaryAction != null)
              OutlinedButton(onPressed: busy ? null : () => onAction(g.secondaryAction!), child: Text(g.secondaryLabel!)),
            if (g.helpUrl != null)
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(g.helpUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(g.helpLabel ?? 'Help'),
              ),
          ]),
        ]),
      ),
    );
  }
}

Future<void> showGuidanceSheet(BuildContext context, String code, void Function(GuidanceAction) onAction) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: GuidanceBox(
          code: code,
          onAction: (a) {
            Navigator.pop(c);
            onAction(a);
          },
        ),
      ),
    ),
  );
}
