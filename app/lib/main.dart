import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';

import 'firebase_options.dart';
import 'screens/home.dart';
import 'screens/sign_in.dart';
import 'services/api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const NeevUdaanApp());
}

const brandSeed = Color(0xFF0E7C86);

class NeevUdaanApp extends StatelessWidget {
  const NeevUdaanApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: brandSeed, brightness: b),
          useMaterial3: true,
          fontFamily: 'Poppins',
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        );
    return MaterialApp(
      title: 'Neev Udaan',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const AuthGate(),
    );
  }
}

/// Signed out → sign-in. Signed in without a workspace → onboarding. Otherwise → home.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, auth) {
        if (auth.connectionState == ConnectionState.waiting) return const _Loading();
        if (auth.data == null) return const SignInScreen();
        return StreamBuilder<String?>(
          stream: Api.instance.defaultWorkspaceId(),
          builder: (context, ws) {
            if (!ws.hasData && ws.connectionState == ConnectionState.waiting) return const _Loading();
            final wid = ws.data;
            return wid == null ? const _CreateWorkspace() : HomeScreen(workspaceId: wid);
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// First sign-in: create the user's workspace silently, then the setup flow takes over.
class _CreateWorkspace extends StatefulWidget {
  const _CreateWorkspace();
  @override
  State<_CreateWorkspace> createState() => _CreateWorkspaceState();
}

class _CreateWorkspaceState extends State<_CreateWorkspace> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    setState(() => _error = null);
    try {
      await Api.instance.createWorkspace();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error == null) return const _Loading();
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$_error'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _create, child: const Text('Try again')),
          TextButton(onPressed: FirebaseAuth.instance.signOut, child: const Text('Sign out')),
        ]),
      ),
    );
  }
}
