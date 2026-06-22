import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/association/admin/chenil_planning_page.dart';
import 'package:PetsMatch/pages/association/admin/contrat_adoption_page.dart';
import 'package:PetsMatch/pages/association/animaux/mes_animaux_asso.dart';
import 'package:PetsMatch/pages/association/familles_accueil/familles_accueil_page.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/certificats_engagement_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  int _nbAdoptes = 0;
  int _nbBenevoles = 0;
  List<Map<String, dynamic>> _recentAnimaux = [];
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

    // Queries indépendantes — une erreur n'annule pas les autres
    final animauxRes = await _supa
        .from('animaux')
        .select('statut')
        .eq('uid_eleveur', uid)
        .eq('is_association', true)
        .catchError((_) => <dynamic>[]);

    final recentRes = await _supa
        .from('animaux')
        .select('id, nom, espece, photo_url, statut')
        .eq('uid_eleveur', uid)
        .eq('is_association', true)
        .order('created_at', ascending: false)
        .limit(6)
        .catchError((_) => <dynamic>[]);

    // Bénévoles : la colonne 'type' peut ne pas exister — protection silencieuse
    List<dynamic> benevoles = [];
    try {
      benevoles = await _supa
          .from('employes')
          .select('id')
          .eq('uid_eleveur', uid)
          .eq('actif', true)
          .eq('type', 'benevole');
    } catch (_) {}

    final list = animauxRes as List;
    if (mounted) {
      setState(() {
        _nbAnimaux    = list.length;
        _nbDisponibles = list.where((a) => a['statut'] == 'disponible').length;
        _nbEnSoin     = list.where((a) => a['statut'] == 'en_soin').length;
        _nbEnFa       = list.where((a) => a['statut'] == 'en_fa').length;
        _nbAdoptes    = list.where((a) => a['statut'] == 'adopte').length;
        _nbBenevoles  = benevoles.length;
        _recentAnimaux = List<Map<String, dynamic>>.from(recentRes as List);
        _loading = false;
      });
    }
  }

  static const _statutConfig = {
    'en_soin':    ('En soin',    Color(0xFFFFF3E0), Color(0xFFE65100)),
    'disponible': ('Disponible', Color(0xFFE8F5E9), Color(0xFF2E7D32)),
    'en_fa':      ('En FA',      Color(0xFFF3E5F5), Color(0xFF6A1B9A)),
    'adopte':     ('Adopté',     Color(0xFFE0F2F1), Color(0xFF00695C)),
    'transfere':  ('Transféré',  Color(0xFFE3F2FD), Color(0xFF1565C0)),
    'decede':     ('Décédé',     Color(0xFFFFEBEE), Color(0xFFC62828)),
  };

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
                    child: Row(
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
                            mainAxisSize: MainAxisSize.min,
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
                  // Stats — 3 colonnes × 2 lignes
                  Row(
                    children: [
                      _StatCard('Total', _nbAnimaux, Icons.pets, _teal),
                      const SizedBox(width: 10),
                      _StatCard('Disponibles', _nbDisponibles, Icons.favorite_border, _green),
                      const SizedBox(width: 10),
                      _StatCard('En soin', _nbEnSoin, Icons.medical_services_outlined, Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatCard('En FA', _nbEnFa, Icons.home_outlined, Colors.purple),
                      const SizedBox(width: 10),
                      _StatCard('Adoptés', _nbAdoptes, Icons.celebration_outlined, const Color(0xFF00695C)),
                      const SizedBox(width: 10),
                      _StatCard('Bénévoles', _nbBenevoles, Icons.volunteer_activism_outlined, _teal),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Animaux récents
                  if (_recentAnimaux.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Animaux récents',
                            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 16, color: _teal)),
                        TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const MesAnimauxAssoPage())),
                          child: Text('Voir tous →',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                        children: _recentAnimaux.asMap().entries.map((entry) {
                          final i = entry.key;
                          final a = entry.value;
                          final cfg = _statutConfig[a['statut'] as String?] ??
                              ('Inconnu', const Color(0xFFF5F5F5), Colors.grey);
                          return Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.grey.shade100,
                                  child: a['photo_url'] != null
                                      ? ClipOval(child: CachedNetworkImage(
                                          imageUrl: a['photo_url'] as String,
                                          width: 40, height: 40, fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => const Icon(Icons.pets, size: 18),
                                        ))
                                      : const Icon(Icons.pets, size: 18, color: Colors.grey),
                                ),
                                title: Text(a['nom'] as String? ?? '',
                                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Text(a['espece'] as String? ?? '',
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: cfg.$2,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(cfg.$1,
                                      style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                          color: cfg.$3, fontWeight: FontWeight.w600)),
                                ),
                              ),
                              if (i < _recentAnimaux.length - 1)
                                const Divider(height: 1, indent: 60),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Actions rapides
                  Text('Actions rapides',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 16, color: _teal)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _QuickAction('Mes animaux', Icons.pets, _teal, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const MesAnimauxAssoPage()))),
                      _QuickAction('Familles d\'accueil', Icons.house_outlined, Colors.purple, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const FamillesAccueilPage()))),
                      _QuickAction('Déposer une annonce', Icons.campaign_outlined, _green, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateAnnonceAssoPage()))),
                      _QuickAction('Créer un certificat', Icons.edit_document, Colors.orange, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const CertificatsEngagementPage(isAssociation: true)))),
                      _QuickAction('Planning chenil', Icons.calendar_month_outlined, _teal, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ChenilPlanningPage()))),
                      _QuickAction('Contrat d\'adoption', Icons.handshake_outlined, const Color(0xFF00695C), onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const ContratAdoptionPage()))),
                      _QuickAction('Employés & Bénévoles', Icons.badge_outlined, Colors.purple, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployesPage()))),
                    ],
                  ),
                  const SizedBox(height: 24),
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

  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 8),
            Text('$value',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 20, color: color)),
            Text(label,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey),
                maxLines: 1, overflow: TextOverflow.ellipsis),
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
  final VoidCallback? onTap;

  const _QuickAction(this.label, this.icon, this.color, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }
}
