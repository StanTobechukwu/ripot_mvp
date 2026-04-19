import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

Future<void> openAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _AccountSheet(),
  );
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              auth.isSignedIn
                  ? 'Signed in as ${auth.email ?? 'your account'}'
                  : 'Use Ripot as a guest, or sign in to sync templates and keep premium access across devices.',
            ),
            const SizedBox(height: 16),
            if (!auth.isSignedIn) ...[
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SignInScreen()));
                },
                icon: const Icon(Icons.login),
                label: const Text('Sign in'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Create account'),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Sync is enabled for this signed-in account'),
                subtitle: Text(auth.email ?? ''),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: auth.busy
                    ? null
                    : () async {
                        await auth.signOut();
                        if (context.mounted) Navigator.pop(context);
                      },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await context.read<AuthProvider>().signIn(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
        );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed in successfully.')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: _AuthScaffold(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sign in to sync templates and keep access across devices.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => (v == null || v.length < 6) ? 'Password must be at least 6 characters.' : null,
              ),
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: auth.busy ? null : _submit,
                child: auth.busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign in'),
              ),
              TextButton(
                onPressed: auth.busy
                    ? null
                    : () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()));
                      },
                child: const Text('Forgot password?'),
              ),
              TextButton(
                onPressed: auth.busy
                    ? null
                    : () {
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));
                      },
                child: const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await context.read<AuthProvider>().signUp(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
        );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully.')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: _AuthScaffold(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create an account to keep synced templates and access status across platforms.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => (v == null || v.length < 6) ? 'Password must be at least 6 characters.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm password'),
                validator: (v) => v != _passwordCtrl.text ? 'Passwords do not match.' : null,
              ),
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: auth.busy ? null : _submit,
                child: auth.busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create account'),
              ),
              TextButton(
                onPressed: auth.busy
                    ? null
                    : () {
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignInScreen()));
                      },
                child: const Text('Already have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await context.read<AuthProvider>().sendPasswordReset(email: _emailCtrl.text);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: _AuthScaffold(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter your email and Ripot will send a password reset link.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email.' : null,
              ),
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: auth.busy ? null : _submit,
                child: auth.busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send reset email'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );
  }
}
