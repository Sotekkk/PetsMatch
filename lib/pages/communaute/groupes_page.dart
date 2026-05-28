import 'package:flutter/material.dart';

class GroupesPage extends StatelessWidget {
  const GroupesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00ACC1),
        title: const Text('Groupes', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.group_outlined, size: 72, color: Color(0xFF00ACC1)),
          SizedBox(height: 16),
          Text('Groupes', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
          SizedBox(height: 8),
          Text('Bientôt disponible', style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey)),
        ]),
      ),
    );
  }
}
