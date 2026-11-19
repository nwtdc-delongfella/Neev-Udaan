import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import 'brand_setup.dart';
import 'connections.dart';
import 'create_post.dart';
import 'library.dart';

class HomeScreen extends StatefulWidget {
  final String workspaceId;
  const HomeScreen({super.key, required this.workspaceId});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  String? _brandId;

  static const _destinations = [
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Create'),
    (Icons.photo_library_outlined, Icons.photo_library, 'Library'),
    (Icons.palette_outlined, Icons.palette, 'Brand'),
    (Icons.link_outlined, Icons.link, 'Connect'),
  ];

  Future<void> _addBrand() async {
    final name = TextEditingController();
    final industry = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add a brand'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Business name')),
          const SizedBox(height: 12),
          TextField(controller: industry, decoration: const InputDecoration(labelText: 'Industry')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final id = await Api.instance.createBrand(widget.workspaceId, name: name.text.trim(), industry: industry.text.trim());
      setState(() {
        _brandId = id;
        _tab = 2;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wid = widget.workspaceId;
    return StreamBuilder<List<Brand>>(
      stream: Api.instance.brands(wid),
      builder: (context, snap) {
        final brands = snap.data ?? [];
        if (brands.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final brand = brands.firstWhere((b) => b.id == _brandId, orElse: () => brands.first);

        final pages = [
          CreatePostScreen(workspaceId: wid, brand: brand, onOpenBrand: () => setState(() => _tab = 2)),
          LibraryScreen(workspaceId: wid, brand: brand),
          BrandSetupScreen(workspaceId: wid, brand: brand),
          const ConnectionsScreen(),
        ];

        final wide = MediaQuery.sizeOf(context).width >= 840;
        final body = IndexedStack(index: _tab, children: pages);

        return Scaffold(
          appBar: AppBar(
            title: _BrandPicker(brands: brands, selected: brand, onSelect: (id) => setState(() => _brandId = id), onAdd: _addBrand),
            actions: [
              _UsageChip(workspaceId: wid),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'signout') FirebaseAuth.instance.signOut();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(enabled: false, child: Text(FirebaseAuth.instance.currentUser?.email ?? '')),
                  const PopupMenuItem(value: 'signout', child: Text('Sign out')),
                ],
              ),
            ],
          ),
          body: wide
              ? Row(children: [
                  NavigationRail(
                    selectedIndex: _tab,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ])
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
                  ],
                ),
        );
      },
    );
  }
}

class _BrandPicker extends StatelessWidget {
  final List<Brand> brands;
  final Brand selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  const _BrandPicker({required this.brands, required this.selected, required this.onSelect, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Switch brand',
      onSelected: (v) => v == '+' ? onAdd() : onSelect(v),
      itemBuilder: (_) => [
        for (final b in brands)
          PopupMenuItem(
            value: b.id,
            child: Row(children: [
              CircleAvatar(radius: 8, backgroundColor: colorFromHex(b.colors.primary)),
              const SizedBox(width: 12),
              Text(b.name),
            ]),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '+', child: Row(children: [Icon(Icons.add), SizedBox(width: 12), Text('Add brand')])),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 10, backgroundColor: colorFromHex(selected.colors.primary)),
        const SizedBox(width: 10),
        Flexible(child: Text(selected.name, overflow: TextOverflow.ellipsis)),
        const Icon(Icons.arrow_drop_down),
      ]),
    );
  }
}

const _planLimits = {'free': 15, 'starter': 60, 'pro': 200, 'agency': 1000};

class _UsageChip extends StatelessWidget {
  final String workspaceId;
  const _UsageChip({required this.workspaceId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: Api.instance.workspace(workspaceId),
      builder: (context, ws) => StreamBuilder<Map<String, dynamic>?>(
        stream: Api.instance.usageThisMonth(workspaceId),
        builder: (context, usage) {
          final plan = (ws.data?['plan'] as String?) ?? 'free';
          final used = (usage.data?['images'] as num?)?.toInt() ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Tooltip(
              message: 'AI images used this month on the $plan plan',
              child: Chip(avatar: const Icon(Icons.image_outlined, size: 18), label: Text('$used / ${_planLimits[plan] ?? '?'}')),
            ),
          );
        },
      ),
    );
  }
}
