import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:lumina_marketplace_web/src/data/session.dart';
import 'package:lumina_marketplace_web/src/platform/files.dart';
import 'package:lumina_marketplace_web/src/widgets/common.dart';

/// A centered form card.
class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PageFrame(maxWidth: 440, children: [
      const SizedBox(height: 24),
      Card(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Semantics(header: true, child: Text(title).h3()),
          const SizedBox(height: 4),
          Text(subtitle).small().muted(),
          const SizedBox(height: 20),
          ...children,
        ]),
      ),
    ]);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.next});
  final String? next;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_login.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email or username and your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MarketplaceScope.read(context).session.logIn(_login.text.trim(), _password.text);
      if (mounted) context.go(widget.next ?? '/');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthCard(title: 'Log in', subtitle: 'Welcome back to the Lumina Marketplace.', children: [
      LabeledField(label: 'Email or username', controller: _login, fieldKey: const ValueKey('login_login'), onSubmitted: (_) => _submit()),
      const SizedBox(height: 14),
      LabeledField(label: 'Password', controller: _password, fieldKey: const ValueKey('login_password'), obscure: true, onSubmitted: (_) => _submit()),
      const SizedBox(height: 18),
      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
      PrimaryButton(key: const ValueKey('login_submit'), enabled: !_busy, onPressed: _busy ? null : _submit, child: const Text('Log in')),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('New here?').small().muted(),
        LinkButton(
          size: ButtonSize.small,
          onPressed: () => context.go(Uri(path: '/signup', queryParameters: {'next': ?widget.next}).toString()),
          child: const Text('Create an account'),
        ),
      ]),
    ]);
  }
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key, this.next});
  final String? next;

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _username, _displayName, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 10) {
      setState(() => _error = 'The password needs at least 10 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MarketplaceScope.read(context).session.signUp(
            email: _email.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
            displayName: _displayName.text.trim().isEmpty ? null : _displayName.text.trim(),
          );
      if (mounted) context.go(widget.next ?? '/');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthCard(title: 'Create an account', subtitle: 'Publish your work and build your library.', children: [
      LabeledField(label: 'Email', controller: _email, fieldKey: const ValueKey('signup_email')),
      const SizedBox(height: 14),
      LabeledField(
        label: 'Username',
        controller: _username,
        fieldKey: const ValueKey('signup_username'),
        help: '3–32 letters, digits, "_", "." or "-". It names your folder in installed projects.',
      ),
      const SizedBox(height: 14),
      LabeledField(label: 'Display name', controller: _displayName, fieldKey: const ValueKey('signup_display_name'), placeholder: 'Optional'),
      const SizedBox(height: 14),
      LabeledField(
        label: 'Password',
        controller: _password,
        fieldKey: const ValueKey('signup_password'),
        obscure: true,
        help: 'At least 10 characters.',
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 18),
      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
      PrimaryButton(key: const ValueKey('signup_submit'), enabled: !_busy, onPressed: _busy ? null : _submit, child: const Text('Create account')),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Already have an account?').small().muted(),
        LinkButton(size: ButtonSize.small, onPressed: () => context.go('/login'), child: const Text('Log in')),
      ]),
    ]);
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _displayName =
      TextEditingController(text: MarketplaceScope.read(context).session.user?.displayName ?? '');
  final _current = TextEditingController();
  final _next = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;

  @override
  void dispose() {
    _displayName.dispose();
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body, String done) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await body();
      if (mounted) setState(() => _notice = done);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scope = MarketplaceScope.of(context);
    final user = scope.session.user;
    if (user == null) return const PageFrame(children: [LoadingView()]);
    final avatar = user.avatarUrl == null ? null : scope.client.resolve(user.avatarUrl!).toString();
    return PageFrame(maxWidth: 720, children: [
      Semantics(header: true, child: const Text('Profile').h3()),
      const SizedBox(height: 16),
      if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
      if (_notice != null) ...[InfoBanner(_notice!, icon: LucideIcons.circleCheck), const SizedBox(height: 12)],
      Panel(
        title: 'Account',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(32), color: const Color(0x33FB7C01)),
              clipBehavior: Clip.antiAlias,
              child: avatar == null
                  ? Center(child: Text(user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase()).h3())
                  : Image.network(avatar, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('@${user.username}').semiBold(),
                Text(user.email ?? '').small().muted(),
                Text('Role: ${user.role.wire}').xSmall().muted(),
              ]),
            ),
            OutlineButton(
              size: ButtonSize.small,
              enabled: !_busy,
              leading: const Icon(LucideIcons.image, size: 14),
              onPressed: () => _run(() async {
                final picked = await scope.fileSource.pick(extensions: const ['png', 'jpg', 'jpeg', 'webp']);
                if (picked == null) return;
                await scope.client.uploadAvatar(picked.bytes,
                    contentType: picked.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
              }, 'Avatar updated.'),
              child: const Text('Change avatar'),
            ),
          ]),
          const SizedBox(height: 16),
          LabeledField(label: 'Display name', controller: _displayName, fieldKey: const ValueKey('profile_display_name')),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(
              size: ButtonSize.small,
              enabled: !_busy,
              onPressed: () => _run(() => scope.client.updateProfile(displayName: _displayName.text.trim()), 'Profile saved.'),
              child: const Text('Save'),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Password',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabeledField(label: 'Current password', controller: _current, obscure: true),
          const SizedBox(height: 10),
          LabeledField(label: 'New password', controller: _next, obscure: true, help: 'At least 10 characters. Signs out your other sessions.'),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(
              size: ButtonSize.small,
              enabled: !_busy,
              onPressed: () => _run(() async {
                await scope.client.changePassword(currentPassword: _current.text, newPassword: _next.text);
                _current.clear();
                _next.clear();
              }, 'Password changed; your other sessions were signed out.'),
              child: const Text('Change password'),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: LinkButton(
          size: ButtonSize.small,
          onPressed: () => openExternal(scope.client.resolve('/docs').toString()),
          child: const Text('API reference'),
        ),
      ),
    ]);
  }
}
