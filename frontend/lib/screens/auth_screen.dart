import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/launcher_state.dart';

class AuthScreen extends StatefulWidget {
  /// If true, shown as dialog and returns true on success via Navigator.pop(context, true)
  final bool isDialog;
  const AuthScreen({super.key, this.isDialog = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  String _role = 'student'; // 'student' or 'parent'
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
            if (mounted) {
              if (widget.isDialog) {
                Navigator.pop(context, true);
              } else {
                Navigator.pushReplacementNamed(context, '/home');
              }
            }
          }
        } else {
          setState(() {
            _errorMessage = res['message'] ?? 'Login failed.';
          });
        }
      } else {
        final res = await ApiService.register(name, email, password, _role);
        if (res['token'] != null) {
          if (mounted) {
            final state = Provider.of<LauncherState>(context, listen: false);
            await state.fetchUserProfile();
            await state.updateAIHeadline();
            if (mounted) {
              if (widget.isDialog) {
                Navigator.pop(context, true);
              } else {
                Navigator.pushReplacementNamed(context, '/home');
              }
            }
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
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo/Header
                Text(
                  'FOCUS.',
                  textAlign: TextAlign.center,
                  style: textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 8.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'MINIMALIST LAUNCHER',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    letterSpacing: 4.0,
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

                // Registration Name field
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

                // Email field
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

                // Password field
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
                const SizedBox(height: 32),

                // Role selection for signup
                if (!_isLogin) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _role = 'student'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _role == 'student'
                                  ? Colors.white
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            'STUDENT',
                            style: TextStyle(
                              color: _role == 'student'
                                  ? Colors.white
                                  : Colors.grey[600],
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => setState(() => _role = 'parent'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _role == 'parent'
                                  ? Colors.white
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            'PARENT',
                            style: TextStyle(
                              color: _role == 'parent'
                                  ? Colors.white
                                  : Colors.grey[600],
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],

                // Submit button
                GestureDetector(
                  onTap: _submitting ? null : _submit,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(0),
                    ),
                    child: Center(
                      child: _submitting
                          ? const CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            )
                          : Text(
                              _isLogin ? 'ENTER' : 'CREATE ACCOUNT',
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
                const SizedBox(height: 24),

                // Toggle Auth Mode
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _errorMessage = '';
                    });
                  },
                  child: Text(
                    _isLogin
                        ? 'CREATE AN ACCOUNT'
                        : 'I ALREADY HAVE AN ACCOUNT',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
