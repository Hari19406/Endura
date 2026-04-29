// lib/screens/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const AuthScreen({
    super.key,
    required this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _submitLocked = false;

  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey            = GlobalKey<FormState>();

  // ── Legal URLs — replace with your actual hosted URLs ─────────────────────
  static const _termsUrl   = 'https://yourdomain.com/terms';
  static const _privacyUrl = 'https://yourdomain.com/privacy';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Auth actions ───────────────────────────────────────────────

  Future<void> _submit() async {
    if (_submitLocked) return;
    if (!_formKey.currentState!.validate()) return;
    _submitLocked = true;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email:    _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) _showEmailConfirmationDialog();
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email:    _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) widget.onAuthenticated();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e.message));
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Something went wrong. Check your connection.');
    } finally {
      _submitLocked = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your email above first.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.endura.runapp://reset-password',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('If that email exists, we sent a reset link.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEmailConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Check your email'),
        content: Text(
          'We sent a confirmation link to ${_emailController.text.trim()}. '
          'Click it to activate your account, then sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isSignUp = false);
            },
            child: const Text('OK, take me to sign in'),
          ),
        ],
      ),
    );
  }

  String _friendlyError(String message) {
    if (message.contains('Invalid login'))       return 'Wrong email or password.';
    if (message.contains('Email not confirmed')) return 'Please confirm your email before signing in.';
    if (message.contains('already registered'))  return 'An account with this email already exists.';
    if (message.contains('Password should be'))  return 'Password must be at least 6 characters.';
    return message;
  }

  Future<void> _signInWithGoogle() async {
    if (_submitLocked) return;
    _submitLocked = true;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      const webClientId = String.fromEnvironment(
        'GOOGLE_WEB_CLIENT_ID',
        defaultValue:
            '564529835415-5m1r3fknq90hkb547c1gi4an1u6gkps6.apps.googleusercontent.com',
      );

      final GoogleSignIn googleSignIn =
          GoogleSignIn(serverClientId: webClientId);
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        _submitLocked = false;
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final googleAuth  = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken     = googleAuth.idToken;

      if (idToken == null) {
        _submitLocked = false;
        if (mounted) setState(() {
          _isLoading    = false;
          _errorMessage = 'Google sign in failed. Try again.';
        });
        return;
      }

      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken:     idToken,
        accessToken: accessToken,
      );

      _submitLocked = false;
      if (mounted) widget.onAuthenticated();

    } on AuthException catch (e) {
      _submitLocked = false;
      if (mounted) setState(() {
        _isLoading    = false;
        _errorMessage = _friendlyError(e.message);
      });
    } catch (e) {
      _submitLocked = false;
      if (mounted) setState(() {
        _isLoading    = false;
        _errorMessage = 'Google sign in failed. Check your connection.';
      });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),

                // App logo row
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.directions_run,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Endura',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),

                const SizedBox(height: 48),

                Text(
                  _isSignUp ? 'Create account' : 'Welcome back',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSignUp
                      ? 'Your training history syncs to all your devices.'
                      : 'Sign in to access your training history.',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.4),
                ),

                const SizedBox(height: 36),

                // Email
                _label('Email'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration('you@example.com'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    final emailValid =
                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
                    if (!emailValid) return 'Enter a valid email';
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Password
                _label('Password'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText:
                        _isSignUp ? 'At least 6 characters' : '••••••••',
                    hintStyle: TextStyle(
                        color: Colors.grey.shade400, fontSize: 14),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Colors.black, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFFD32F2F)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (_isSignUp && v.length < 6)
                      return 'Password must be at least 6 characters';
                    return null;
                  },
                ),

                // Forgot password
                if (!_isSignUp) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _forgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                ],

                // Error banner
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3F3),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: const Color(0xFFFFCDD2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Color(0xFFD32F2F), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFD32F2F)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Primary button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _isSignUp ? 'Create account' : 'Sign in',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // OR divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400)),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                  ],
                ),

                const SizedBox(height: 16),

                // Sign in with Google
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/google_logo.png',
                          width: 22,
                          height: 22,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Continue with Google',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Toggle sign in / sign up
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignUp
                            ? 'Already have an account? '
                            : "Don't have an account? ",
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade600),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _isSignUp     = !_isSignUp;
                          _errorMessage = null;
                        }),
                        child: Text(
                          _isSignUp ? 'Sign in' : 'Sign up',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── UPDATED: Terms + Privacy with tappable links ──────────
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(text: 'By continuing, you agree to our '),
                        TextSpan(
                          text: 'Terms of Service',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _openUrl(_termsUrl),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _openUrl(_privacyUrl),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: Colors.black, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD32F2F)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}