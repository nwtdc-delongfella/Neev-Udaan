import 'package:material_ui/material_ui.dart';

import '../widgets/common.dart';

/// Phase 2: OAuth connections. For now, shows what each business needs to have ready.
class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  static const _platforms = [
    (
      'Instagram',
      Icons.camera_alt_outlined,
      [
        'Switch your Instagram account to a Professional account (Business or Creator): Settings → Account type and tools.',
        'You need the Instagram username and password to connect.',
      ],
    ),
    (
      'Facebook Page',
      Icons.facebook,
      [
        'Posting works for Facebook Pages, not personal profiles.',
        'You must be an admin of the Page (Page settings → Page access).',
      ],
    ),
    (
      'Google Business Profile',
      Icons.storefront_outlined,
      [
        'Your business profile must be verified on Google.',
        'Sign in with the Google account that is the Owner or Manager of the profile.',
        'Once connected, new reviews will alert you here with an AI reply ready to approve.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Constrained(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Connect your accounts', style: t.titleLarge),
        const SizedBox(height: 4),
        const Text('Direct posting and Google review replies arrive in the next update. '
            'Get these ready now so connecting takes one tap.'),
        const SizedBox(height: 16),
        for (final p in _platforms)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(p.$2),
                  const SizedBox(width: 12),
                  Expanded(child: Text(p.$1, style: t.titleMedium)),
                  const FilledButton(onPressed: null, child: Text('Connect')),
                ]),
                const SizedBox(height: 12),
                for (final step in p.$3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_circle_outline, size: 18)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(step)),
                    ]),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }
}
