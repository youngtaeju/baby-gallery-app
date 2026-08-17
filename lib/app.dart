import 'package:flutter/material.dart';

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
      home: const _PlaceholderPage(),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('가족 갤러리')),
      body: const Center(child: Text('가족 갤러리')),
    );
  }
}
