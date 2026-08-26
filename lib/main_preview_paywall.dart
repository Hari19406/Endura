import 'package:flutter/material.dart';
import 'screens/paywall_screen.dart';
import 'services/revenue_cat_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RevenueCatService.init('audit-test-user');
  runApp(const _PaywallPreviewApp());
}

class _PaywallPreviewApp extends StatelessWidget {
  const _PaywallPreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const PaywallScreen(),
    );
  }
}
