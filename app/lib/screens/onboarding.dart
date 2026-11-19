import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../services/api.dart';
import '../widgets/common.dart';

const industries = [
  'Dental clinic', 'Medical clinic', 'Restaurant / Cafe', 'Salon / Spa', 'Gym / Fitness', 'Retail store',
  'Real estate', 'Education / Coaching', 'Hotel / Travel', 'Professional services', 'Other',
];

/// First run: name the business so a workspace and first brand can be created.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _business = TextEditingController();
  final _otherIndustry = TextEditingController();
  String _industry = industries.first;
  bool _agency = false;
  bool _busy = false;

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final name = _business.text.trim();
      final industry = _industry == 'Other' ? _otherIndustry.text.trim() : _industry;
      await Api.instance.createWorkspace(
        workspaceName: _agency ? '$name (agency)' : name,
        brandName: name,
        industry: industry,
      );
      // AuthGate switches to Home as soon as the user's workspace appears.
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your business'),
        actions: [TextButton(onPressed: FirebaseAuth.instance.signOut, child: const Text('Sign out'))],
      ),
      body: Constrained(
        maxWidth: 520,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Text('Welcome${user?.displayName != null ? ', ${user!.displayName}' : ''}!',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Tell us about the business you want to create posts for. You can add your logo and colors next.'),
            const SizedBox(height: 24),
            TextFormField(
              controller: _business,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the business name' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _industry,
              decoration: const InputDecoration(labelText: 'Industry'),
              items: [for (final i in industries) DropdownMenuItem(value: i, child: Text(i))],
              onChanged: (v) => setState(() => _industry = v!),
            ),
            if (_industry == 'Other') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _otherIndustry,
                decoration: const InputDecoration(labelText: 'Describe your industry'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your industry' : null,
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _agency,
              onChanged: (v) => setState(() => _agency = v),
              title: const Text('I manage several businesses (agency)'),
              subtitle: const Text('You can add more brands later on paid plans.'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continue'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
