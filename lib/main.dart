import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize JustAudioBackground for notifications + lock screen controls
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.mujic.audio',
    androidNotificationChannelName: 'Mujic Playback',
    androidNotificationOngoing: true,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mujic',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory, // disable ripple splash
      highlightColor: Colors.transparent, // disable highlight color
      ).copyWith(
        platform: TargetPlatform.android,
      ),
      home: const HomePage(),
    );
  }
}
  