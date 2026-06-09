import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api_service.dart';
import 'launcher_state.dart';

/// Shows an AuthScreen as a full-screen dialog overlay.
/// If the user successfully authenticates, the callback is invoked.
/// If they dismiss without auth (via back button), navigates back to home.
Future<void> requireAuth(
  BuildContext context, {
  VoidCallback? onAuthenticated,
}) async {
  final token = await ApiService.getToken();
  if (token != null && token.isNotEmpty) {
    onAuthenticated?.call();
    return;
  }

  if (!context.mounted) return;

  // Import inside function to avoid circular dependency
  // We use Navigator.push with MaterialPageRoute for the auth screen
  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (ctx) => _buildAuthScreen(ctx),
      fullscreenDialog: true,
    ),
  );

  if (result == true) {
    onAuthenticated?.call();
  } else {
    // User cancelled — go back to home
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }
}

/// Check auth silently — returns true if authenticated
Future<bool> isAuthenticated() async {
  final token = await ApiService.getToken();
  return token != null && token.isNotEmpty;
}

/// Small wrapper widget that loads auth screen in dialog style
Widget _buildAuthScreen(BuildContext context) {
  // We use the AuthScreen directly with isDialog mode
  return ChangeNotifierProvider.value(
    value: Provider.of<LauncherState>(context, listen: false),
    child: const _AuthDialogWrapper(),
  );
}

class _AuthDialogWrapper extends StatelessWidget {
  const _AuthDialogWrapper();

  @override
  Widget build(BuildContext context) {
    // Lazy import the auth screen
    return const _LazyAuthScreen();
  }
}

class _LazyAuthScreen extends StatelessWidget {
  const _LazyAuthScreen();

  @override
  Widget build(BuildContext context) {
    // Dynamically load AuthScreen
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _LazyAuthBody()),
    );
  }
}

class _LazyAuthBody extends StatefulWidget {
  @override
  State<_LazyAuthBody> createState() => _LazyAuthBodyState();
}

class _LazyAuthBodyState extends State<_LazyAuthBody> {
  Widget? _screen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Use deferred import — the actual AuthScreen import
    // We'll just inline the minimal auth flow here
    setState(() {
      _screen = const _InlineAuthScreen();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _screen ??
        const Center(child: CircularProgressIndicator(color: Colors.white24));
  }
}

/// A minimal inline auth screen to avoid circular import issues.
/// This mirrors the essential parts of auth_screen.dart.
class _InlineAuthScreen extends StatefulWidget {
  const _InlineAuthScreen();

  @override
  State<_InlineAuthScreen> createState() => _InlineAuthScreenState();
}

class _InlineAuthScreenState extends State<_InlineAuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;
  String _errorMessage = '';
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = '';
      _submitting = true;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      setState(() {
        _errorMessage = 'Please fill out all fields.';
        _submitting = false;
      });
      return;
    }

    try {
      if (_isLogin) {
        final res = await ApiService.login(email, password);
        if (res['token'] != null) {
          if (mounted) {
            final state = Provider.of<LauncherState>(context, listen: false);
            await state.fetchUserProfile();
            await state.updateAIHeadline();
            if (mounted) Navigator.pop(context, true);
          }
        } else {
          setState(() {
            _errorMessage = res['message'] ?? 'Login failed.';
          });
        }
      } else {
        final res = await ApiService.register(name, email, password, 'student');
        if (res['token'] != null) {
          if (mounted) {
            final state = Provider.of<LauncherState>(context, listen: false);
            await state.fetchUserProfile();
            await state.updateAIHeadline();
            if (mounted) Navigator.pop(context, true);
          }
        } else {
          setState(() {
            _errorMessage = res['message'] ?? 'Registration failed.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'FOCUS.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w200,
              letterSpacing: 8.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'MINIMALIST LAUNCHER',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[600],
              letterSpacing: 4.0,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 64),

          if (_errorMessage.isNotEmpty) ...[
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (!_isLogin) ...[
            TextField(
              controller: _nameController,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
              ),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'NAME',
                hintStyle: TextStyle(
                  color: Colors.grey[700],
                  letterSpacing: 2.0,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          TextField(
            controller: _emailController,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
            ),
            keyboardType: TextInputType.emailAddress,
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'EMAIL',
              hintStyle: TextStyle(color: Colors.grey[700], letterSpacing: 2.0),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 24),

          TextField(
            controller: _passwordController,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
            ),
            obscureText: true,
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'PASSWORD',
              hintStyle: TextStyle(color: Colors.grey[700], letterSpacing: 2.0),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 32),

          GestureDetector(
            onTap: _submitting ? null : _submit,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: _submitting ? Colors.white24 : Colors.white,
                border: Border.all(color: Colors.white),
              ),
              child: Center(
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        _isLogin ? 'LOGIN' : 'REGISTER',
                        style: const TextStyle(
                          color: Colors.black,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          GestureDetector(
            onTap: () => setState(() {
              _isLogin = !_isLogin;
              _errorMessage = '';
            }),
            child: Text(
              _isLogin
                  ? 'DON\'T HAVE AN ACCOUNT? REGISTER'
                  : 'ALREADY HAVE AN ACCOUNT? LOGIN',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 8),

          GestureDetector(
            onTap: () => Navigator.pop(context, false),
            child: Text(
              'GO BACK',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 11,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
