import 'package:flutter/material.dart';

class AboutUs extends StatelessWidget {
  const AboutUs({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('À propos',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoCard(title: '🏢 Éditeur', items: const [
              ('Dénomination', 'PETSMATCH (PM)'),
              ('Forme juridique', 'SAS'),
              ('Siège social', '15 La Ville Marchand, 22210 Plumieux, France'),
              ('SIREN', '931 344 816'),
              ('SIRET', '931 344 816 00018'),
              ('TVA intracommunautaire', 'FR94 931 344 816'),
              ('Date de création', '20 juillet 2024'),
              ('Email', 'petsmatch.contact@gmail.com'),
              ('Téléphone', '07 81 03 49 84'),
            ]),
            const SizedBox(height: 12),
            _InfoCard(title: '👤 Responsables de la publication', items: const [
              ('Président', 'Nabil Ksouri'),
              ('Directeur général', 'Mevinn Allee'),
            ]),
            const SizedBox(height: 12),
            _InfoCard(title: '☁️ Hébergement', items: const [
              ('Hébergeur', 'Google Firebase (Google LLC)'),
              ('Adresse', '1600 Amphitheatre Parkway, Mountain View, CA 94043, USA'),
              ('Contact', 'support@firebase.google.com'),
            ]),
            const SizedBox(height: 12),
            _TextCard(
              title: '⚖️ Propriété intellectuelle',
              body: 'Tous les éléments de l\'application PetsMatch (textes, graphismes, logos, images, vidéos) sont protégés par des droits d\'auteur et appartiennent exclusivement à PETSMATCH SAS. Toute reproduction sans autorisation écrite préalable est strictement interdite.',
            ),
            const SizedBox(height: 12),
            _TextCard(
              title: '🔒 Données personnelles',
              body: 'Les utilisateurs disposent de droits d\'accès, de rectification, de suppression et d\'opposition sur leurs données.\n\nContact : petsmatch.contact@gmail.com',
            ),
            const SizedBox(height: 12),
            _TextCard(
              title: '⚠️ Limitation de responsabilité',
              body: 'PETSMATCH SAS agit en tant qu\'intermédiaire. Nous ne sommes pas responsables des interactions entre utilisateurs, des contenus publiés, ni des dommages liés à une mauvaise utilisation.',
            ),
            const SizedBox(height: 12),
            _TextCard(
              title: '🏛️ Litiges et juridiction',
              body: 'En cas de litige, les parties s\'efforceront de trouver une solution à l\'amiable. À défaut, la juridiction compétente est celle des tribunaux de Rennes, France.',
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<(String, String)> items;
  const _InfoCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 120, child: Text(item.$1, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6B7280)))),
                Expanded(child: Text(item.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1F2A2E)))),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  final String title;
  final String body;
  const _TextCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF4B5563), height: 1.5)),
        ],
      ),
    );
  }
}
