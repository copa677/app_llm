import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';

void main() {
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma Local Chat',
      debugShowCheckedModeBanner: false,
      // Configuración de temas
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      // Forzamos modo oscuro por solicitud del usuario
      themeMode: ThemeMode.dark, 
      home: const ChatScreen(),
    );
  }
}
