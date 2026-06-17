import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';

const _teal = Color(0xFF0C5C6C);

class SecuConnectionSetting extends StatefulWidget {
  const SecuConnectionSetting({super.key});

  @override
  State<SecuConnectionSetting> createState() => _SecuConnectionSettingState();
}

class _SecuConnectionSettingState extends State<SecuConnectionSetting> {
  bool _resetSent = false;

  Future<void> _sendPasswordReset() async {
    final email = User_Info.email;
    if (email.isEmpty) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _resetSent = true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email de réinitialisation envoyé !', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _teal,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}', style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Connexion et sécurité',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Email affiché
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: _teal.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.email_outlined, color: _teal, size: 20),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Email du compte', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF9CA3AF))),
                Text(User_Info.email, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1F2A2E))),
              ]),
            ]),
          ),

          // Réinitialiser mot de passe
          _SettingsTile(
            icon: Icons.lock_reset_outlined,
            title: 'Réinitialiser mon mot de passe',
            subtitle: _resetSent ? 'Email envoyé ✓' : 'Recevoir un lien par email',
            iconColor: _resetSent ? const Color(0xFF6E9E57) : _teal,
            onTap: _sendPasswordReset,
          ),
          const SizedBox(height: 10),

          // Poser une question
          _SettingsTile(
            icon: Icons.help_outline,
            title: 'Poser une question',
            subtitle: 'Contacter le support PetsMatch',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestionPage())),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.title, this.subtitle, this.iconColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: (iconColor ?? _teal).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor ?? _teal, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF1F2A2E))),
              if (subtitle != null)
                Text(subtitle!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF9CA3AF))),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios, color: Color(0xFF9CA3AF), size: 16),
        ]),
      ),
    );
  }
}

// ── Page "Poser une question" ─────────────────────────────────────────────────

class QuestionPage extends StatefulWidget {
  const QuestionPage({super.key});

  @override
  State<QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    final msg = _ctrl.text.trim();
    if (msg.isEmpty) return;
    setState(() => _sending = true);
    final subject = Uri.encodeComponent('Question Support — ${User_Info.firstname} ${User_Info.lastname}');
    final body = Uri.encodeComponent('${msg}\n\n---\nUID: ${User_Info.uid}\nEmail: ${User_Info.email}\nTéléphone: ${User_Info.phone_number}');
    final uri = Uri.parse('mailto:petsmatch.contact@gmail.com?subject=$subject&body=$body');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune application email configurée.'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Poser une question',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: _teal, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Votre question sera envoyée à notre équipe support par email.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal))),
              ]),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Décrivez votre question ou problème...',
                hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade400),
                filled: true, fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)), borderSide: BorderSide(color: _teal, width: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send_outlined, size: 18),
                label: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Envoyer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
