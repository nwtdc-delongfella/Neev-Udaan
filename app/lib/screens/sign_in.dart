import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/common.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = FirebaseAuth.instance;
    try {
      if (_register) {
        final cred = await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
        await cred.user?.updateDisplayName(_name.text.trim());
        await cred.user?.sendEmailVerification();
      } else {
        await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) showError(context, _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (!email.contains('@')) return showError(context, 'Enter your email address first.');
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    if (mounted) showInfo(context, 'Password reset link sent to $email.');
  }

  String _message(FirebaseAuthException e) => switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Email or password is incorrect.',
        'email-already-in-use' => 'An account with this email already exists. Sign in instead.',
        'weak-password' => 'Use at least 8 characters for your password.',
        'invalid-email' => 'That email address does not look right.',
        _ => e.message ?? 'Sign-in failed.',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Constrained(
          maxWidth: 420,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 32),
                Icon(Icons.auto_awesome, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text('Neev Udaan', style: t.headlineMedium, textAlign: TextAlign.center),
                Text('On-brand social posts and review replies, made with AI',
                    style: t.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 32),
                if (_register) ...[
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Your name'),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? 'Create account' : 'Sign in'),
                  ),
                ),
                if (!_register) TextButton(onPressed: _reset, child: const Text('Forgot password?')),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(_register ? 'Already have an account? Sign in' : 'New here? Create an account'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
