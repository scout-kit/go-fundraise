import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_fundraise/core/database/database.dart';
import 'package:go_fundraise/shared/theme/app_theme.dart';
import 'package:go_fundraise/core/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database
  final database = AppDatabase();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
      ],
      child: const GoFundraiseApp(),
    ),
  );
}

class GoFundraiseApp extends StatelessWidget {
  const GoFundraiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final router = ref.watch(routerProvider);

        return MaterialApp.router(
          title: 'Go Fundraise',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
