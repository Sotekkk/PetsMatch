import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/search/quick_search_page.dart';
import 'package:PetsMatch/pages/association/animaux/mes_animaux_asso.dart';
import 'package:PetsMatch/pages/association/equipe/equipe_page.dart';
import 'package:PetsMatch/pages/association/profil_association_edit.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AssociationHomePage extends StatefulWidget {
  const AssociationHomePage({super.key});
  @override
  State<AssociationHomePage> createState() => _AssociationHomePageState();
}

class _AssociationHomePageState extends State<AssociationHomePage> with RouteAware {
  final _supa = Supabase.instance.client;

  int _nbAnimaux = 0;
  int _nbDisponibles = 0;
  int _nbEnSoin = 0;
  int _nbEnFa = 0;
  int _nbAdoptes = 0;
  int _nbBenevoles = 0;
  List<Map<String, dynamic>> _recentAnimaux = [];
  List<Map<String, dynamic>> _disponibles = [];
  List<Map<String, dynamic>> _annonces = [];
  bool _loading = true;

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Recharge les stats quand on revient sur l'accueil après avoir modifié
  // quelque chose sur un autre écran (ex. placer un animal en FA ou en
  // enclos) — sans ça, les compteurs restaient figés à l'état du dernier
  // chargement (même bug déjà corrigé sur EleveurHomePage).
  @override
  void didPopNext() {
    _loadStats();
  }

  Future<void> _loadStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Queries indépendantes — une erreur n'annule pas les autres
    final animauxRes = await _supa
        .from('animaux')
        .select('statut, fa_id')
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

    // Équipe : mêmes membres que la page Équipe (employés + bénévoles actifs
    // du profil association) — avant : bénévoles seuls, sur tout le compte.
    List<dynamic> benevoles = [];
    try {
      final asso = await _supa.from('user_profiles_complet')
          .select('id').eq('uid', uid).eq('profile_type', 'association').maybeSingle();
      var q = _supa.from('employes').select('id')
          .eq('actif', true).eq('profil_source', 'association');
      q = asso?['id'] != null ? q.eq('eleveur_profile_id', asso!['id']) : q.eq('uid_eleveur', uid);
      benevoles = await q;
    } catch (_) {}

    // Animaux disponibles à l'adoption
    final disponiblesRes = await _supa
        .from('animaux')
        .select('id, nom, espece, race, photo_url, date_naissance')
        .eq('uid_eleveur', uid)
        .eq('is_association', true)
        .eq('statut', 'disponible')
        .order('created_at', ascending: false)
        .limit(10)
        .catchError((_) => <dynamic>[]);

    // Annonces d'adoption de l'association
    final annoncesRes = await _supa
        .from('annonces')
        .select('id, titre, espece, race, photos, prix, statut')
        .eq('uid_eleveur', uid)
        .eq('profil_source', 'association')
        .eq('statut', 'disponible')
        .order('created_at', ascending: false)
        .limit(6)
        .catchError((_) => <dynamic>[]);

    final list = animauxRes as List;
    if (mounted) {
      setState(() {
        _nbAnimaux    = list.length;
        _nbDisponibles = list.where((a) => a['statut'] == 'disponible').length;
        _nbEnSoin     = list.where((a) => a['statut'] == 'en_soin').length;
        _nbEnFa       = list.where((a) => a['fa_id'] != null).length;
        _nbAdoptes    = list.where((a) => a['statut'] == 'adopte').length;
        _nbBenevoles  = benevoles.length;
        _recentAnimaux = List<Map<String, dynamic>>.from(recentRes as List);
        _disponibles  = List<Map<String, dynamic>>.from(disponiblesRes as List);
        _annonces     = List<Map<String, dynamic>>.from(annoncesRes as List);
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

  Future<void> _modifierProfil() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilAssociationEditPage()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final nom = User_Info.nameElevage.isNotEmpty
        ? User_Info.nameElevage
        : '${User_Info.firstname} ${User_Info.lastname}'.trim();

    return Scaffold(
      backgroundColor: kDashFond,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            pinned: true,
            backgroundColor: _teal,
            surfaceTintColor: _teal,
            actions: [QuickSearchButton()],
          ),
          // Bannière officielle PetsMatch, comme l'accueil éleveur (non personnalisable).
          const SliverToBoxAdapter(child: DashBanniere()),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: dashMargeLaterale(context), vertical: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                DashEnteteAccueil(
                  nom: nom,
                  photoUrl: User_Info.profilePictureUrlElevage.isNotEmpty ? User_Info.profilePictureUrlElevage : null,
                  onAvatarTap: _modifierProfil,
                  lignes: const ['Association / Refuge'],
                  lieu: User_Info.ville.isNotEmpty ? User_Info.ville : User_Info.villeElevage,
                  action: DashBoutonPilule(label: 'Modifier', icon: Icons.settings_outlined, onTap: _modifierProfil),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  // Non bloquant : un dossier en attente garde l'accès normal
                  // à l'appli (cf. AuthWrapper, lib/main.dart) — seule sa
                  // visibilité auprès des autres est restreinte tant qu'il
                  // n'a pas été examiné par un admin.
                  if (!User_Info.isValidate) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.orange.shade200),
                        boxShadow: kDashOmbre,
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: Colors.orange.shade50,
                          child: Icon(Icons.hourglass_empty, color: Colors.orange.shade800, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Dossier en cours d\'examen',
                                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                    fontSize: 14, color: Colors.orange.shade900)),
                            Text(
                              'Vous pouvez utiliser votre compte normalement, mais votre profil n\'est pas encore visible par les autres.',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade800),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // Stats — 3 colonnes × 2 lignes
                  Row(
                    children: [
                      _StatCard('Total', _nbAnimaux, Icons.pets, _teal, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const MesAnimauxAssoPage()))),
                      const SizedBox(width: 12),
                      _StatCard('Disponibles', _nbDisponibles, Icons.favorite_border, _green, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const MesAnimauxAssoPage(initialFilterStatut: 'disponible')))),
                      const SizedBox(width: 12),
                      _StatCard('En soin', _nbEnSoin, Icons.medical_services_outlined, Colors.orange, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const MesAnimauxAssoPage(initialFilterStatut: 'en_soin')))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatCard('En FA', _nbEnFa, Icons.home_outlined, Colors.purple, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const MesAnimauxAssoPage(initialFilterStatut: 'en_fa')))),
                      const SizedBox(width: 12),
                      _StatCard('Adoptés', _nbAdoptes, Icons.celebration_outlined, const Color(0xFF00695C), onTap: () =>
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const MesAnimauxAssoPage(initialFilterStatut: 'adopte')))),
                      const SizedBox(width: 12),
                      _StatCard('Équipe', _nbBenevoles, Icons.volunteer_activism_outlined, _teal, onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const EquipePage()))),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Animaux récents
                  if (_recentAnimaux.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Animaux récents',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 17, color: kDashInk)),
                        TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const MesAnimauxAssoPage())),
                          child: Text('Voir tous →',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600, color: _teal)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Même présentation que « Dernières annonces » de l'accueil éleveur.
                    for (final a in _recentAnimaux) _ligneAnimal(a),
                    const SizedBox(height: 20),
                  ],

                  // Disponibles à l'adoption
                  if (_disponibles.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Disponibles à l\'adoption',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 17, color: kDashInk)),
                        TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const MesAnimauxAssoPage())),
                          child: Text('Voir tous →',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600, color: _teal)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _disponibles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final a = _disponibles[i];
                          return GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => MesAnimauxAssoPage())),
                            child: Container(
                              width: 110,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: kDashBorder),
                                boxShadow: kDashOmbre,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                                    child: a['photo_url'] != null
                                        ? CachedNetworkImage(imageUrl: a['photo_url'] as String,
                                            width: 110, height: 80, fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) => Container(height: 80,
                                                color: _teal.withValues(alpha: 0.08),
                                                child: const Icon(Icons.pets, color: Colors.grey)))
                                        : Container(height: 80, color: _teal.withValues(alpha: 0.08),
                                            child: const Icon(Icons.pets, color: Colors.grey)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(a['nom'] as String? ?? '',
                                          style: const TextStyle(fontFamily: 'Galey',
                                              fontWeight: FontWeight.w700, fontSize: 12),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text(a['race'] as String? ?? a['espece'] as String? ?? '',
                                          style: const TextStyle(fontFamily: 'Galey',
                                              fontSize: 10, color: Colors.grey),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ]),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Annonces d'adoption
                  if (_annonces.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Mes annonces d\'adoption',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 17, color: kDashInk)),
                        TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => MesAnnoncesPage(isAssociation: true))),
                          child: Text('Voir toutes →',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600, color: _teal)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kDashBorder),
                        boxShadow: kDashOmbre,
                      ),
                      child: Column(
                        children: _annonces.asMap().entries.map((entry) {
                          final i = entry.key;
                          final ann = entry.value;
                          final photos = List<String>.from(ann['photos'] ?? []);
                          return Column(children: [
                            ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: photos.isNotEmpty
                                    ? CachedNetworkImage(imageUrl: photos.first,
                                        width: 44, height: 44, fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => Container(width: 44, height: 44,
                                            color: Colors.grey.shade100,
                                            child: const Icon(Icons.pets, size: 18, color: Colors.grey)))
                                    : Container(width: 44, height: 44, color: Colors.grey.shade100,
                                        child: const Icon(Icons.pets, size: 18, color: Colors.grey)),
                              ),
                              title: Text(ann['titre'] as String? ?? '${ann['espece']} ${ann['race'] ?? ''}'.trim(),
                                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                ann['prix'] != null && (ann['prix'] as num) > 0
                                    ? '${ann['prix']}€ — Adoption'
                                    : 'Gratuit — Adoption',
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('Disponible',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                        color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                              ),
                            ),
                            if (i < _annonces.length - 1)
                              Divider(height: 1, indent: 60, color: Colors.grey.shade200),
                          ]);
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligneAnimal(Map<String, dynamic> a) {
    final cfg = _statutConfig[a['statut'] as String?];
    final photo = (a['photo_url'] ?? '').toString();
    final espece = (a['espece'] ?? '').toString();
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesAnimauxAssoPage())),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kDashBorder),
          boxShadow: kDashOmbre,
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 56, height: 56,
              child: photo.isNotEmpty
                  ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: const Color(0xFFE8F4F6)),
                      errorWidget: (_, __, ___) => Container(color: const Color(0xFFE8F4F6),
                          child: const Icon(Icons.pets_outlined, color: _teal, size: 24)))
                  : Container(color: const Color(0xFFE8F4F6),
                      child: const Icon(Icons.pets_outlined, color: _teal, size: 24)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((a['nom'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15, color: kDashInk)),
            const SizedBox(height: 6),
            Row(children: [
              if (cfg != null) DashPuce(cfg.$1, fg: cfg.$3, bg: cfg.$2, point: true),
              if (espece.isNotEmpty) ...[
                const SizedBox(width: 10),
                Flexible(child: Text(espece[0].toUpperCase() + espece.substring(1), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted))),
              ],
            ]),
          ])),
          const Icon(Icons.chevron_right, color: kDashMuted),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard(this.label, this.value, this.icon, this.color, {this.onTap});

  @override
  Widget build(BuildContext context) =>
      Expanded(child: DashStat(valeur: '$value', label: label, icon: icon, teinte: color, onTap: onTap));
}
