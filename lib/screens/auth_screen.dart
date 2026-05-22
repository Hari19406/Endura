// lib/screens/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

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
  bool _isSignUp = true; // default to sign-up to match reference
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _submitLocked = false;

  final _firstNameController = TextEditingController();
  final _lastNameController  = TextEditingController();
  final _emailController     = TextEditingController();
  final _passwordController  = TextEditingController();
  final _formKey             = GlobalKey<FormState>();

  // ── Legal URLs — replace with your actual hosted URLs ─────────────────────
  static const _termsUrl   = 'https://yourdomain.com/terms';
  static const _privacyUrl = 'https://yourdomain.com/privacy';

  // ── Theme tokens ──────────────────────────────────────────────────────────
  static const _bg            = Color(0xFF000000);
  static const _fieldFill     = Color(0xFF1A1A1A);
  static const _fieldBorder   = Color(0xFF2A2A2A);
  static const _fieldFocused  = Color(0xFFFFFFFF);
  static const _hintColor     = Color(0xFF6B6B6B);
  static const _subtleText    = Color(0xFF9A9A9A);
  static const _errorRed      = Color(0xFFFF6B6B);
  static const _errorBg       = Color(0xFF2A1414);
  static const _errorBorder   = Color(0xFF4A2020);

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
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
        final response = await Supabase.instance.client.auth.signUp(
          email:    _emailController.text.trim(),
          password: _passwordController.text,
        );

        // Save first/last name to profiles table (best-effort).
        // If a trigger creates the row, this updates it; otherwise inserts.
        final userId = response.user?.id;
        if (userId != null) {
          await _saveNameToProfile(
            userId: userId,
            firstName: _firstNameController.text.trim(),
            lastName:  _lastNameController.text.trim(),
          );
        }

        await Posthog().capture(
          eventName: 'signup',
          properties: {'method': 'email'},
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

  Future<void> _saveNameToProfile({
    required String userId,
    required String firstName,
    required String lastName,
  }) async {
    try {
      await Supabase.instance.client.from('profiles').upsert({
        'id':         userId,
        'first_name': firstName,
        'last_name':  lastName,
      });
    } catch (_) {
      // Non-fatal: profile name will be missing but auth succeeded.
      // Onboarding/profile screen can prompt for it later if needed.
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
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Check your email',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'We sent a confirmation link to ${_emailController.text.trim()}. '
          'Click it to activate your account, then sign in.',
          style: const TextStyle(color: _subtleText),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isSignUp = false);
            },
            child: const Text('OK, take me to sign in',
                style: TextStyle(color: Colors.white)),
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

      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken:     idToken,
        accessToken: accessToken,
      );

      // Save name from Google profile to profiles table (best-effort).
      final userId = response.user?.id;
      final displayName = googleUser.displayName ?? '';
      if (userId != null && displayName.isNotEmpty) {
        final parts = displayName.trim().split(RegExp(r'\s+'));
        final first = parts.isNotEmpty ? parts.first : '';
        final last  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        await _saveNameToProfile(
          userId: userId,
          firstName: first,
          lastName:  last,
        );
      }

      _submitLocked = false;
      await Posthog().capture(
        eventName: 'signup',
        properties: {'method': 'google'},
      );
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
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),

                // Title — centered
                Text(
                  _isSignUp ? 'Sign Up Account' : 'Welcome Back',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isSignUp
                      ? 'Enter your personal data to create your account.'
                      : 'Sign in to access your training history.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _subtleText,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 32),

                // Google button — full width
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _fieldBorder),
                      backgroundColor: _fieldFill,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/google_logo.png',
                          width: 20,
                          height: 20,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Google',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // OR divider
                Row(
                  children: [
                    const Expanded(child: Divider(color: _fieldBorder)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Or',
                        style: TextStyle(
                          fontSize: 13,
                          color: _hintColor,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider(color: _fieldBorder)),
                  ],
                ),

                const SizedBox(height: 20),

                // First / Last name — only in sign-up
                if (_isSignUp) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('First Name'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _firstNameController,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration('eg. John'),
                              validator: (v) {
                                if (!_isSignUp) return null;
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Last Name'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _lastNameController,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration('eg. Francisco'),
                              validator: (v) {
                                if (!_isSignUp) return null;
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                // Email
                _label('Email'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('eg. johnfrans@gmail.com'),
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
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _isSignUp
                        ? 'Enter your password'
                        : '••••••••',
                    hintStyle: const TextStyle(
                        color: _hintColor, fontSize: 14),
                    filled: true,
                    fillColor: _fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _fieldBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _fieldBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: _fieldFocused, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _errorRed),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _errorRed),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: _hintColor,
                        size: 20,
                      ),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (_isSignUp && v.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),

                // Helper / forgot password row
                if (_isSignUp) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Must be at least 6 characters.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ] else ...[
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
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(fontSize: 13, color: _subtleText),
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
                      color: _errorBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _errorBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: _errorRed, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                                fontSize: 13, color: _errorRed),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Primary button — white with black text
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      disabledBackgroundColor: Colors.grey.shade700,
                      disabledForegroundColor: Colors.grey.shade400,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : Text(
                            _isSignUp ? 'Sign Up' : 'Sign In',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // Toggle sign in / sign up
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignUp
                            ? 'Already have an account? '
                            : "Don't have an account? ",
                        style: const TextStyle(
                            fontSize: 14, color: _subtleText),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _isSignUp     = !_isSignUp;
                          _errorMessage = null;
                        }),
                        child: Text(
                          _isSignUp ? 'Log in' : 'Sign up',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Terms + Privacy
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 11,
                        color: _hintColor,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(text: 'By continuing, you agree to our '),
                        TextSpan(
                          text: 'Terms of Service',
                          style: const TextStyle(
                            color: _subtleText,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _openUrl(_termsUrl),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: const TextStyle(
                            color: _subtleText,
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
            color: Colors.white),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _hintColor, fontSize: 14),
        filled: true,
        fillColor: _fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _fieldFocused, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _errorRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _errorRed),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}