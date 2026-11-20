import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/api.dart';
import '../widgets/common.dart';
import '../widgets/connect_panel.dart';

const industrySuggestions = [
  'Dental clinic', 'Medical clinic', 'Restaurant', 'Cafe', 'Bakery', 'Salon', 'Spa', 'Gym', 'Retail store',
  'Real estate', 'Coaching institute', 'Hotel', 'Travel agency', 'Professional services',
];

/// First-run flow for a new brand: 1) connect accounts, 2) confirm business details.
class SetupFlowScreen extends StatefulWidget {
  final String workspaceId;
  final Brand brand;
  const SetupFlowScreen({super.key, required this.workspaceId, required this.brand});
  @override
  State<SetupFlowScreen> createState() => _SetupFlowScreenState();
}

class _SetupFlowScreenState extends State<SetupFlowScreen> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final b = widget.brand;
    final anyConnected = b.channels.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0 ? 'Connect your business' : 'Check your details'),
        leading: _step == 1 ? BackButton(onPressed: () => setState(() => _step = 0)) : null,
        actions: [TextButton(onPressed: FirebaseAuth.instance.signOut, child: const Text('Sign out'))],
      ),
      body: _step == 0
          ? Constrained(
              child: ListView(padding: const EdgeInsets.all(20), children: [
                _StepDots(step: 0),
                const SizedBox(height: 16),
                Text('Sign in to the accounts where you post', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text("We'll find your business, bring in your logo and details, "
                    "and post there for you. You sign in on Facebook's and Google's own pages; "
                    'Neev Udaan never sees your passwords.'),
                const SizedBox(height: 20),
                ConnectPanel(workspaceId: widget.workspaceId, brand: b),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => setState(() => _step = 1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(anyConnected ? 'Continue' : 'Skip for now'),
                  ),
                ),
                if (!anyConnected)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('You can still create and download posts, and connect later from the Connect tab.',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  ),
              ]),
            )
          : _ConfirmDetails(workspaceId: widget.workspaceId, brand: b),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int step;
  const _StepDots({required this.step});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      for (var i = 0; i < 2; i++)
        Container(
          width: i == step ? 28 : 10,
          height: 10,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: i <= step ? scheme.primary : scheme.outlineVariant,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      const SizedBox(width: 6),
      Text('Step ${step + 1} of 2', style: Theme.of(context).textTheme.labelMedium),
    ]);
  }
}

class _ConfirmDetails extends StatefulWidget {
  final String workspaceId;
  final Brand brand;
  const _ConfirmDetails({required this.workspaceId, required this.brand});
  @override
  State<_ConfirmDetails> createState() => _ConfirmDetailsState();
}

class _ConfirmDetailsState extends State<_ConfirmDetails> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.brand.name == 'My business' ? '' : widget.brand.name);
  late final _industry = TextEditingController(text: widget.brand.industry == 'Other' ? '' : widget.brand.industry);
  late final _phone = TextEditingController(text: widget.brand.phone);
  late final _website = TextEditingController(text: widget.brand.website);
  late final _location = TextEditingController(text: widget.brand.location);
  TextEditingController? _industryField; // the Autocomplete's own field
  bool _saving = false;

  Future<void> _finish() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await Api.instance.updateBrand(widget.workspaceId, widget.brand.id, {
        'name': _name.text.trim(),
        'industry': (_industryField?.text ?? _industry.text).trim(),
        'phone': _phone.text.trim(),
        'website': _website.text.trim(),
        'location': _location.text.trim(),
        'setupComplete': true,
      });
      // HomeScreen switches to the main app when setupComplete becomes true.
    } catch (e) {
      if (mounted) showError(context, e);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brand;
    final t = Theme.of(context).textTheme;
    return Form(
      key: _form,
      child: Constrained(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          _StepDots(step: 1),
          const SizedBox(height: 16),
          Text(b.channels.isEmpty ? 'Tell us about your business' : 'Does this look right?', style: t.titleLarge),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              width: 72,
              height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: b.logoPath == null
                  ? const Icon(Icons.image_outlined, color: Colors.black26)
                  : StorageImage(key: ValueKey(b.logoPath), path: b.logoPath, resolve: Api.instance.downloadUrl, fit: BoxFit.contain),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  for (final h in [b.colors.primary, b.colors.secondary, b.colors.accent])
                    Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: colorFromHex(h), borderRadius: BorderRadius.circular(8)),
                    ),
                ]),
                const SizedBox(height: 6),
                Text(b.logoPath == null ? 'Add your logo any time in the Brand tab.' : 'Logo and colors from your profile. Change them any time in the Brand tab.',
                    style: t.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Business name'),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your business name' : null,
          ),
          const SizedBox(height: 12),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _industry.text),
            optionsBuilder: (v) => industrySuggestions.where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
            fieldViewBuilder: (context, controller, focus, onSubmit) {
              _industryField = controller;
              return TextFormField(
                controller: controller,
                focusNode: focus,
                decoration: const InputDecoration(labelText: 'Type of business', hintText: 'e.g. Bakery, Dental clinic'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your type of business' : null,
              );
            },
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'City / area')),
          const SizedBox(height: 12),
          TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone (shown on posts)')),
          const SizedBox(height: 12),
          TextFormField(controller: _website, decoration: const InputDecoration(labelText: 'Website (shown on posts)')),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _finish,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_saving ? 'Saving…' : 'Start creating posts')),
          ),
        ]),
      ),
    );
  }
}
