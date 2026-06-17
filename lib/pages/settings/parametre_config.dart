import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _teal = Color(0xFF0C5C6C);

class ParametreConfi extends StatelessWidget {
  const ParametreConfi({super.key});

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
        title: const Text('Confidentialité & CGU',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Section(
            icon: Icons.privacy_tip_outlined,
            title: 'Vos droits RGPD',
            body: 'Conformément au RGPD, vous disposez des droits suivants sur vos données personnelles :\n\n'
                '• Droit d\'accès — consulter les données que nous détenons\n'
                '• Droit de rectification — corriger des informations inexactes\n'
                '• Droit à l\'effacement — demander la suppression de vos données\n'
                '• Droit d\'opposition — s\'opposer au traitement marketing\n'
                '• Droit à la portabilité — récupérer vos données en format JSON\n\n'
                'Pour exercer ces droits : petsmatch.contact@gmail.com',
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.gavel_outlined,
            title: 'Conditions Générales d\'Utilisation',
            body: '• Vous devez avoir 18 ans ou plus pour utiliser PetsMatch.\n'
                '• Vous êtes responsable de l\'exactitude des informations fournies.\n'
                '• PetsMatch applique une politique de tolérance zéro contre les contenus haineux, violents ou frauduleux.\n'
                '• Tout contenu abusif signalé sera modéré sous 24h.\n'
                '• Les éléments de l\'application (textes, logos, code) sont la propriété exclusive de PetsMatch.',
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.shield_outlined,
            title: 'Données collectées',
            body: 'Nous collectons :\n'
                '• Données d\'inscription (nom, email, téléphone)\n'
                '• Données de profil (éleveur, professionnel)\n'
                '• Interactions et messages dans l\'application\n\n'
                'Ces données sont utilisées uniquement pour le fonctionnement du service et ne sont jamais revendues.',
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.balance_outlined,
            title: 'Litiges et juridiction',
            body: 'Les présentes CGU sont soumises à la loi française. Tout différend sera de la compétence des tribunaux de Rennes, France.\n\n'
                'Pour toute question : petsmatch.contact@gmail.com',
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text('Politique de confidentialité complète',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 14)),
            onPressed: () => launchUrl(Uri.parse('https://www.petsmatchapp.com/cgu'), mode: LaunchMode.externalApplication),
            style: OutlinedButton.styleFrom(
              foregroundColor: _teal,
              side: const BorderSide(color: _teal),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Section({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: _teal.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: _teal, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E)))),
        ]),
        const SizedBox(height: 10),
        Text(body, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF4B5563), height: 1.6)),
      ]),
    );
  }
}
