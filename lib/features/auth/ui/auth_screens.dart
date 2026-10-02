import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../../../core/firebase/installation_activity.dart';

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
    final activity = context.watch<InstallationActivity>();
    return SafeArea(
      child: SingleChildScrollView(
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
            if (activity.available) ...[
              const Divider(height: 28),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Share basic app activity'),
                subtitle: const Text(
                  'Help us count installations and recent use. Sends app version and dates used, linked to your account when signed in. Report and patient content stays out of this data. Turning this off stops future activity sharing.',
                ),
                value: activity.enabled,
                onChanged: activity.ready ? activity.setEnabled : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.onWelcomeCompleted});
  final VoidCallback? onWelcomeCompleted;

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
      if (widget.onWelcomeCompleted != null) {
        widget.onWelcomeCompleted!();
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onWelcomeCompleted != null ? 'Ripot' : 'Sign in'),
      ),
      body: _AuthScaffold(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onWelcomeCompleted != null) ...[
                Text('Welcome to Ripot',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
              ],
              Text(
                'Sign in to use your trial or Premium access across devices. '
                'Your reports stay on this device.',
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
                    : () async {
                        if (widget.onWelcomeCompleted == null) {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));
                          return;
                        }
                        final completed = await Navigator.push<bool>(context,
                          MaterialPageRoute(builder: (_) => const SignUpScreen(welcomeFlow: true)));
                        if (mounted && completed == true) {
                          widget.onWelcomeCompleted!();
                        }
                      },
                child: const Text('Create account'),
              ),
              if (widget.onWelcomeCompleted != null) ...[
                const Divider(height: 24),
                TextButton(
                  onPressed: auth.busy ? null : widget.onWelcomeCompleted,
                  child: const Text('Continue without an account'),
                ),
                Text('You can sign in later from the account icon.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.welcomeFlow = false});
  final bool welcomeFlow;

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
      Navigator.pop(context, true);
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
                'Create an account to use your trial or Premium access across devices. '
                'Your reports stay on this device.',
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
                        if (widget.welcomeFlow) {
                          Navigator.pop(context, false);
                        } else {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignInScreen()));
                        }
                      },
                child: const Text('Already have an account? Sign in'),
              ),
              if (widget.welcomeFlow)
                TextButton(
                  onPressed: auth.busy ? null : () => Navigator.pop(context, true),
                  child: const Text('Continue without an account'),
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
