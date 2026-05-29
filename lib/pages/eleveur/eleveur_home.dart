import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/eleveur/profil_eleveur_edit.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/pages/eleveur/post/trouver_compagnon_page.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EleveurHomePage extends StatefulWidget {
  const EleveurHomePage({super.key});

  @override
  State<EleveurHomePage> createState() => _EleveurHomePageState();
}

class _EleveurHomePageState extends State<EleveurHomePage> {
  Map<String, dynamic>? _profile;
  int _animalCount = 0;
  int _postCount = 0;
  List<Map<String, dynamic>> _mesAlertes = [];
  bool _loading = true;
  List<Map<String, dynamic>> _recentAnnonces = [];

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profileDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final animaux = await Supabase.instance.client
          .from('animaux').select('id').eq('uid_eleveur', uid);
      final annonces = await Supabase.instance.client
          .from('annonces')
          .select('id')
          .eq('uid_eleveur', uid)
          .inFilter('statut', ['disponible', 'reserve']);
      final recent = await Supabase.instance.client
          .from('annonces')
          .select('id, titre, espece, race, photos, statut, vues, created_at')
          .eq('uid_eleveur', uid)
          .inFilter('statut', ['disponible', 'reserve', 'pause'])
          .order('created_at', ascending: false)
          .limit(3);
      final alertes = await Supabase.instance.client
          .from('alertes_perdus')
          .select()
          .eq('uid_proprietaire', uid)
          .eq('statut', 'perdu');
      if (!mounted) return;
      setState(() {
        _profile = profileDoc.data();
        _animalCount = (animaux as List).length;
        _postCount = (annonces as List).length;
        _recentAnnonces = List<Map<String, dynamic>>.from(recent);
        _mesAlertes = List<Map<String, dynamic>>.from(alertes as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _green,
              child: CustomScrollView(
                slivers: [
                  _buildSliverHeader(context),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildStatsRow(),
                        if (_mesAlertes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildAlerteBanner(context),
                        ],
                        const SizedBox(height: 24),
                        _buildSectionTitle('Accès rapide'),
                        const SizedBox(height: 12),
                        _buildQuickAccess(context),
                        const SizedBox(height: 24),
                        _buildSectionTitle('Dernières annonces'),
                        const SizedBox(height: 12),
                        _buildRecentPosts(),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliverHeader(BuildContext context) {
    final name = _profile?['nameElevage'] ?? _profile?['firstname'] ?? 'Mon élevage';
    final city = _profile?['city'] ?? '';
    final photoUrl = _profile?['profilePictureUrlElevage'] ?? _profile?['profilePictureUrl'];

    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: _teal,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C5C6C), Color(0xFF5F9EAA)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => User_Info.isPro ? const ProProfileEditPage() : const ProfilEleveurEditPage())),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: const Color(0xFFA7C79A),
                      backgroundImage: photoUrl != null
                          ? CachedNetworkImageProvider(photoUrl) : null,
                      child: photoUrl == null
                          ? const Icon(Icons.pets, color: Colors.white, size: 36) : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (city.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.location_on_outlined, color: Color(0xFFEEF5EA), size: 14),
                            const SizedBox(width: 4),
                            Text(city,
                                style: const TextStyle(color: Color(0xFFEEF5EA), fontSize: 13, fontFamily: 'Galey')),
                          ]),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => User_Info.isPro ? const ProProfileEditPage() : const ProfilEleveurEditPage())),
                          icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.white),
                          label: const Text('Modifier', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Galey')),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _StatCard(value: _animalCount.toString(), label: 'Animaux', icon: Icons.cruelty_free_outlined),
        const SizedBox(width: 12),
        _StatCard(value: _postCount.toString(), label: 'Annonces', icon: Icons.campaign_outlined),
        const SizedBox(width: 12),
        _StatCard(value: User_Info.isPro ? 'Pro' : 'Éleveur', label: 'Statut', icon: Icons.verified_outlined),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w700,
          fontSize: 17,
          color: Color(0xFF1F2A2E),
        ));
  }

  Widget _buildAlerteBanner(BuildContext context) {
    final nb = _mesAlertes.length;
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MesAlertesPage())),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade300, width: 1.5),
        ),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: Colors.orange.shade100,
            child: Icon(Icons.location_searching,
                color: Colors.orange.shade700, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '$nb alerte${nb > 1 ? 's' : ''} active${nb > 1 ? 's' : ''}',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.orange.shade800),
              ),
              Text(
                nb == 1 ? 'Appuyez pour gérer votre alerte' : 'Appuyez pour gérer vos alertes',
                style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade600)),
            ]),
          ),
          Icon(Icons.chevron_right, color: Colors.orange.shade400),
        ]),
      ),
    );
  }

  Widget _buildQuickAccess(BuildContext context) {
    final tiles = [
      _QuickTile(icon: Icons.cruelty_free_outlined, label: 'Mes\nAnimaux', color: _green,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesAnimauxPage()))),
      _QuickTile(icon: Icons.campaign_outlined, label: 'Mes\nAnnonces', color: _teal,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesAnnoncesPage()))),
      _QuickTile(icon: Icons.home_work_outlined, label: 'Élevages', color: const Color(0xFF5B8648),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EleveurListPage()))),
      _QuickTile(icon: Icons.storefront_outlined, label: 'Services', color: const Color(0xFF5F9EAA),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServicesPage()))),
      _QuickTile(icon: Icons.location_searching, label: 'Animaux\nperdus', color: Colors.orange.shade700,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnimauxPerdusPage()))),
      _QuickTile(icon: Icons.add_alert_outlined, label: 'Déclarer\nperdu', color: Colors.orange.shade800,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertePerduFormPage()))),
      _QuickTile(icon: Icons.pets, label: 'Animal\ntrouvé', color: const Color(0xFF0C5C6C),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnimalTrouveFormPage()))),
    ];

    return Column(children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: tiles,
      ),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TrouverCompagnonPage())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _teal.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.pets, color: _teal, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Trouver un compagnon',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 15, color: Color(0xFF0C5C6C))),
              SizedBox(height: 2),
              Text('Feed · Recherche · Carte',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: Color(0xFF5F9EAA))),
            ])),
            const Icon(Icons.chevron_right, color: Color(0xFF5F9EAA)),
          ]),
        ),
      ),
    ]);
  }

  Future<void> _confirmDeleteAnnonce(String annonceId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer l\'annonce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette annonce sera supprimée définitivement. Confirmer ?',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Supabase.instance.client.from('annonces').delete().eq('id', annonceId);
    _loadData();
  }

  Widget _buildRecentPosts() {
    if (_recentAnnonces.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Icon(Icons.campaign_outlined, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text('Aucune annonce publiée',
              style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey')),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreateAnnoncePage())),
            style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white),
            child: const Text('Créer une annonce',
                style: TextStyle(fontFamily: 'Galey')),
          ),
        ]),
      );
    }

    return Column(
      children: _recentAnnonces.map((data) {
        final photos = List<String>.from(data['photos'] ?? []);
        final statut = (data['statut'] as String?) ?? 'disponible';
        final espece = (data['espece'] as String?) ?? '';
        final race   = (data['race']   as String?) ?? '';
        final titre  = (data['titre']  as String?) ?? '';
        final vues   = (data['vues']   as num?)?.toInt() ?? 0;
        final createdAt = data['created_at'] as String?;

        final displayTitle = titre.isNotEmpty ? titre
            : race.isNotEmpty ? race : speciesLabel(espece);

        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => AnnonceDetailPage(
                  annonceId: data['id'] as String, initialData: data))),
          onLongPress: () => _confirmDeleteAnnonce(data['id'] as String),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 56, height: 56,
                  child: photos.isNotEmpty
                      ? CachedNetworkImage(imageUrl: photos.first,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: const Color(0xFFEEF5EA)),
                          errorWidget: (_, __, ___) => Container(color: const Color(0xFFEEF5EA)))
                      : Container(color: const Color(0xFFEEF5EA),
                          child: Center(child: speciesIcon(espece, 24, const Color(0xFFA7C79A)))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayTitle,
                      style: const TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    _Badge(
                      statut == 'pause' ? 'En pause'
                          : statut == 'reserve' ? 'Réservé' : 'En ligne',
                      statut == 'pause' ? Colors.grey
                          : statut == 'reserve' ? const Color(0xFFF59E0B)
                          : _green),
                    const SizedBox(width: 8),
                    Icon(Icons.visibility_outlined, size: 12,
                        color: Colors.grey.shade400),
                    const SizedBox(width: 2),
                    Text('$vues',
                        style: TextStyle(fontFamily: 'Galey',
                            fontSize: 11, color: Colors.grey.shade400)),
                  ]),
                ],
              )),
              if (createdAt != null)
                Text(DateFormat('dd/MM').format(DateTime.parse(createdAt)),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                        color: Colors.grey.shade400)),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatCard({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF6E9E57), size: 22),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF1F2A2E))),
            Text(label,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
          ],
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                  color: color,
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.3,
                )),
          ],
        ),
      ),
    );
  }
}


class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
    );
  }
}
