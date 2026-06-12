import 'package:PetsMatch/main.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AssociationHomePage extends StatefulWidget {
  const AssociationHomePage({super.key});
  @override
  State<AssociationHomePage> createState() => _AssociationHomePageState();
}

class _AssociationHomePageState extends State<AssociationHomePage> {
  final _supa = Supabase.instance.client;

  int _nbAnimaux = 0;
  int _nbDisponibles = 0;
  int _nbEnSoin = 0;
  int _nbEnFa = 0;
  int _nbBenevoles = 0;
  bool _loading = true;

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final animaux = await _supa
          .from('animaux')
          .select('statut')
          .eq('uid_eleveur', uid);
      final list = animaux as List;
      final benevoles = await _supa
          .from('employes')
          .select('id')
          .eq('uid_eleveur', uid)
          .eq('actif', true);
      if (mounted) {
        setState(() {
          _nbAnimaux = list.length;
          _nbDisponibles = list.where((a) => a['statut'] == 'disponible').length;
          _nbEnSoin = list.where((a) => a['statut'] == 'en_soin').length;
          _nbEnFa = list.where((a) => a['statut'] == 'en_fa').length;
          _nbBenevoles = (benevoles as List).length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom = User_Info.nameElevage.isNotEmpty
        ? User_Info.nameElevage
        : '${User_Info.firstname} ${User_Info.lastname}'.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: _teal,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0C5C6C), Color(0xFF6E9E57)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundImage: User_Info.profilePictureUrlElevage.isNotEmpty
                                  ? NetworkImage(User_Info.profilePictureUrlElevage)
                                  : null,
                              backgroundColor: Colors.white24,
                              child: User_Info.profilePictureUrlElevage.isEmpty
                                  ? const Icon(Icons.favorite, color: Colors.white, size: 28)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(nom,
                                      style: const TextStyle(
                                          fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                          fontSize: 18, color: Colors.white),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const Text('Association / Refuge',
                                      style: TextStyle(fontFamily: 'Galey',
                                          fontSize: 12, color: Colors.white70)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  // Stats
                  Row(
                    children: [
                      _StatCard('Animaux\ntotal', _nbAnimaux, Icons.pets, _teal),
                      const SizedBox(width: 10),
                      _StatCard('Disponibles\nà l\'adoption', _nbDisponibles, Icons.favorite_border, _green),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatCard('En soin', _nbEnSoin, Icons.medical_services_outlined, Colors.orange),
                      const SizedBox(width: 10),
                      _StatCard('En famille\nd\'accueil', _nbEnFa, Icons.home_outlined, Colors.purple),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _StatCard('Bénévoles actifs', _nbBenevoles, Icons.volunteer_activism_outlined, _teal, full: true),
                  const SizedBox(height: 24),
                  // Accès rapides
                  Text('Accès rapide',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 16, color: _teal)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _QuickAction('Mes animaux', Icons.pets, _teal),
                      _QuickAction('Familles d\'accueil', Icons.house_outlined, Colors.purple),
                      _QuickAction('Bénévoles', Icons.volunteer_activism_outlined, _green),
                      _QuickAction('Certificats', Icons.edit_document, Colors.orange),
                    ],
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool full;

  const _StatCard(this.label, this.value, this.icon, this.color, {this.full = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: full ? 0 : 1,
      child: Container(
        width: full ? double.infinity : null,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 22, color: color)),
                Text(label,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey),
                    maxLines: 2),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _QuickAction(this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
