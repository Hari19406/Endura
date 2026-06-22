import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController  = TextEditingController();
  final _formKey            = GlobalKey<FormState>();
  bool _isLoading           = false;
  bool _obscurePassword     = true;
  bool _obscureConfirm      = true;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated. Please sign in.'),
            backgroundColor: Color(0xFF388E3C),
          ),
        );
        // Sign out and let AppInitializer route to auth
        await Supabase.instance.client.auth.signOut();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                const Text(
                  'New password',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a strong password for your account.',
                  style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 36),

                // Password field
                Text(
                  'New password',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(context, 'At least 8 characters').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: c.textTertiary,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (v.length < 8)           return 'Password must be at least 8 characters';
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Confirm password field
                Text(
                  'Confirm password',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _inputDecoration(context, 'Repeat your password').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: c.textTertiary,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty)           return 'Please confirm your password';
                    if (v != _passwordController.text)    return 'Passwords do not match';
                    return null;
                  },
                ),

                // Error banner
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3F3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFCDD2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFD32F2F), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 13, color: Color(0xFFD32F2F)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.onAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      disabledBackgroundColor: c.textFaint,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                          )
                        : const Text(
                            'Update password',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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

  InputDecoration _inputDecoration(BuildContext context, String hint) {
    final c = context.colors;
    return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: c.textTertiary, fontSize: 14),
    filled: true,
    fillColor: c.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.accent, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFD32F2F)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
  }
}