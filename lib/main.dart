import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'services/settings_service.dart';
import 'services/llm_service.dart';
import 'services/prompt_service.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先加载持久化设置，确保 UI 启动时数据已就绪
  final settingsService = SettingsService();
  await settingsService.ensureLoaded();

  final promptService = PromptService();
  await promptService.ensureInitialized();

  final llmService = LlmService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: promptService),
        Provider.value(value: llmService),
      ],
      child: const RedPenApp(),
    ),
  );
}

class RedPenApp extends StatelessWidget {
  const RedPenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RedPen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansScTextTheme(),
        inputDecorationTheme: InputDecorationTheme(
          border: const OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.indigo.shade400, width: 2),
          ),
        ),
      ),
      routes: {
        '/': (_) => const HomePage(),
        '/settings': (_) => const SettingsPage(),
      },
    );
  }
}
