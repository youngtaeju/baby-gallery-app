import 'package:flutter/material.dart';

import 'features/auth/auth_gate.dart';

class FamilyGalleryApp extends StatelessWidget {
  const FamilyGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '가족 갤러리',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthGate(),
    );
  }
}
