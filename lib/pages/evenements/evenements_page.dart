import 'package:flutter/material.dart';

class EvenementsPage extends StatelessWidget {
  const EvenementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2025),
        title: const Text('Événements', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.event_outlined, size: 72, color: Color(0xFF6E9E57)),
          SizedBox(height: 16),
          Text('Événements', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
          SizedBox(height: 8),
          Text('Bientôt disponible', style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey)),
        ]),
      ),
    );
  }
}
