import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/home_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YouTube Music Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        // Disable button click sounds
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ).copyWith(
        // Additional sound disabling
        platform: TargetPlatform.android,
      ),
      home: const HomePage(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            // Disable system sounds
            platformBrightness: Theme.of(context).brightness,
          ),
          child: child!,
        );
      },
    );
  }
}