import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../widgets/common.dart';
import '../widgets/connect_panel.dart';

/// Connect tab: manage Facebook, Instagram and Google for the current brand.
class ConnectionsScreen extends StatelessWidget {
  final String workspaceId;
  final Brand brand;
  const ConnectionsScreen({super.key, required this.workspaceId, required this.brand});

  @override
  Widget build(BuildContext context) {
    return Constrained(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Connected accounts', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Where ${brand.name} posts and gets reviews.'),
        const SizedBox(height: 16),
        ConnectPanel(workspaceId: workspaceId, brand: brand),
      ]),
    );
  }
}
