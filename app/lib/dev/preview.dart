// Development-only preview of the Connect screen with sample data (no Firebase).
// Build: flutter build web -t lib/dev/preview.dart
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../widgets/connect_panel.dart';

void main() => runApp(const _Preview());

final _brandOk = Brand(
  id: 'b1',
  name: 'Sunrise Bakery',
  industry: 'Bakery',
  colors: const BrandColors(primary: '#0E7C86', secondary: '#F28C28', accent: '#F28C28', onPrimary: '#FFFFFF'),
  colorSource: 'logo',
  channels: {
    'facebook': {'id': 'p1', 'name': 'Sunrise Bakery'},
    'instagram': {'id': 'ig1', 'username': 'sunrisebakery', 'via': 'facebook'},
    'google': {'id': 'accounts/1/locations/10', 'title': 'Sunrise Bakery', 'verified': false},
  },
);

final _brandNew = Brand(
  id: 'b2',
  name: 'My business',
  industry: 'Other',
  colors: const BrandColors(primary: '#1F4E79', secondary: '#F2A541', accent: '#2E8B57', onPrimary: '#FFFFFF'),
  colorSource: 'custom',
);

Connection _c(Provider p, Map<String, dynamic> d) => Connection.fromDoc(p, d);

final _okConnections = {
  Provider.facebook: _c(Provider.facebook, {
    'status': 'connected',
    'accountName': 'Asha Patil',
    'selectedId': 'p1',
    'candidates': [
      {'id': 'p1', 'name': 'Sunrise Bakery', 'subtitle': 'Bakery', 'issues': [], 'instagram': {'username': 'sunrisebakery'}},
      {'id': 'p2', 'name': 'Sunrise Catering', 'subtitle': 'Caterer', 'issues': ['IG_NOT_LINKED']},
    ],
  }),
  Provider.instagram: null,
  Provider.google: _c(Provider.google, {
    'status': 'connected',
    'accountName': 'asha@example.com',
    'selectedId': 'accounts/1/locations/10',
    'candidates': [
      {'id': 'accounts/1/locations/10', 'name': 'Sunrise Bakery', 'subtitle': '12 MG Road, Pune', 'issues': ['NOT_VERIFIED']},
    ],
  }),
};

final _problemConnections = {
  Provider.facebook: _c(Provider.facebook, {
    'status': 'connected',
    'accountName': 'Asha Patil',
    'candidates': [
      {'id': 'p1', 'name': 'Sunrise Bakery', 'subtitle': 'Bakery', 'issues': ['IG_NOT_LINKED']},
      {'id': 'p2', 'name': 'Old Club Page', 'subtitle': 'Community', 'issues': ['NOT_PAGE_ADMIN', 'IG_NOT_LINKED']},
    ],
  }),
  Provider.instagram: _c(Provider.instagram, {
    'status': 'connected',
    'accountName': '@asha.bakes',
    'candidates': [
      {'id': 'i1', 'name': '@asha.bakes', 'issues': ['IG_PERSONAL_ACCOUNT'], 'instagram': {'username': 'asha.bakes'}},
    ],
  }),
  Provider.google: _c(Provider.google, {'status': 'problem', 'accountName': 'asha@example.com', 'issues': ['NO_LOCATIONS']}),
};

class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) {
    final scenario = Uri.base.queryParameters['s'] ?? 'ok';
    final problems = scenario == 'problems';
    final data = problems ? _problemConnections : _okConnections;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7C86)), useMaterial3: true, fontFamily: 'Poppins'),
      home: Scaffold(
        appBar: AppBar(title: const Text('Connect your business')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ConnectPanel(
            workspaceId: 'w',
            brand: problems ? _brandNew : _brandOk,
            connectionsOverride: (p) => Stream.value(data[p]),
          ),
        ]),
      ),
    );
  }
}
