import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart' show speciesIcon, speciesLabel;
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/particulier/user_feed.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/particulier/animal_fiche_particulier.dart';
import 'package:PetsMatch/pages/eleveur/post/trouver_compagnon_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';

class ParticulierHomePage extends StatefulWidget {
  const ParticulierHomePage({super.key});

  @override
  State<ParticulierHomePage> createState() => _ParticulierHomePageState();
}

class _ParticulierHomePageState extends State<ParticulierHomePage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _tealLight = Color(0xFF5F9EAA);

  final _supa = Supabase.instance.client;

  String? _photoUrl;
  int _nbAnimaux = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _animaux = [];
  List<Map<String, dynamic>> _mesAlertes = [];
  List<Map<String, dynamic>> _alertesPubliques = [];
  bool _loadingAlertes = false;
  List<Map<String, dynamic>> _annonces = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = User_Info.uid;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final animaux = await _supa
          .from('animaux')
          .select()
          .or('uid_eleveur.eq.$uid,uid_proprietaire.eq.$uid');
      final alertesMes = await _supa
          .from('alertes_perdus')
          .select()
          .eq('uid_proprietaire', uid)
          .eq('statut', 'perdu');
      final annonces = await _supa
          .from('annonces')
          .select('id, titre, espece, race, photos, prix, prix_min_portee, prix_max_portee, type, type_vente, ville_eleveur')
          .eq('statut', 'disponible')
          .order('created_at', ascending: false)
          .limit(6);

      if (!mounted) return;
      setState(() {
        _photoUrl = (doc.data())?['profilePictureUrl'];
        _animaux = List<Map<String, dynamic>>.from(animaux as List);
        _nbAnimaux = _animaux.length;
        _mesAlertes = List<Map<String, dynamic>>.from(alertesMes as List);
        _annonces = List<Map<String, dynamic>>.from(annonces as List);
        _loading = false;
      });
      _loadAlertesPubliques();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAlertesPubliques() async {
    if (!mounted) return;
    setState(() => _loadingAlertes = true);
    try {
      final rows = await _supa
          .from('alertes_perdus')
          .select()
          .eq('statut', 'perdu')
          .order('created_at', ascending: false)
          .limit(6);
      if (mounted) setState(() {
        _alertesPubliques = List<Map<String, dynamic>>.from(rows as List);
        _loadingAlertes = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAlertes = false);
    }
  }

  void _shareAlerte(Map<String, dynamic> a) {
    final nom = (a['nom_animal'] ?? 'Animal') as String;
    final espece = (a['espece'] ?? '') as String;
    final ville = (a['derniere_localisation'] ?? '') as String;
    final dateStr = a['date_perte'] as String?;
    final date = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';
    final desc = (a['description'] as String?) ?? '';
    final text = [
      'ANIMAL PERDU — $nom ($espece)',
      if (ville.isNotEmpty) 'Dernière localisation : $ville',
      if (date.isNotEmpty) 'Disparu le $date',
      if (desc.isNotEmpty) desc,
      'Si vous l\'avez vu, signalez-le sur l\'app PetsMatch',
    ].join('\n');
    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: _teal,
              expandedHeight: 180,
              floating: false,
              pinned: true,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_teal, _tealLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const UserParticulierFeed(initialTab: 0))),
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: const Color(0xFF5B9EAA),
                                  backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                                      ? CachedNetworkImageProvider(_photoUrl!)
                                      : null,
                                  child: (_photoUrl == null || _photoUrl!.isEmpty)
                                      ? const Icon(Icons.person, color: Colors.white, size: 24)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Bonjour, ${User_Info.firstname} !',
                                        style: const TextStyle(
                                            fontFamily: 'Galey',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 18,
                                            color: Colors.white)),
                                    if (User_Info.ville.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on,
                                              color: Color(0xFFB2D8DE), size: 13),
                                          const SizedBox(width: 3),
                                          Text(User_Info.ville,
                                              style: const TextStyle(
                                                  fontFamily: 'Galey',
                                                  fontSize: 12,
                                                  color: Color(0xFFCCE8EE))),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (!_loading) _buildStatsRow(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (!User_Info.isProfileComplete()) ...[
                    _buildProfileIncompleteBanner(),
                    const SizedBox(height: 16),
                  ],
                  if (_animaux.isNotEmpty) ...[
                    _buildMesAnimauxSection(),
                    const SizedBox(height: 20),
                  ],
                  _buildQuickAccess(),
                  if (_mesAlertes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildAlerteBanner(),
                  ],
                  const SizedBox(height: 24),
                  _buildAnnoncesSection(),
                  const SizedBox(height: 24),
                  _buildAnimauxPerdusSection(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileIncompleteBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const InfoUserSettings())),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.shade400, width: 1.5),
        ),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: Colors.amber.shade100,
            child: Icon(Icons.person_outline, color: Colors.amber.shade800, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Complétez votre profil',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.amber.shade900),
              ),
              Text(
                'Téléphone, ville et code postal manquants',
                style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, color: Colors.amber.shade700)),
            ]),
          ),
          Icon(Icons.chevron_right, color: Colors.amber.shade400),
        ]),
      ),
    );
  }

  Widget _buildStatsRow() {
    final nb = _mesAlertes.length;
    return Row(
      children: [
        _StatCard(value: '$_nbAnimaux', label: 'Animal${_nbAnimaux > 1 ? 'x' : ''}', icon: Icons.pets),
        const SizedBox(width: 12),
        _StatCard(
          value: '$nb',
          label: 'Alerte${nb > 1 ? 's' : ''} active${nb > 1 ? 's' : ''}',
          icon: Icons.location_searching,
          highlight: nb > 0,
        ),
      ],
    );
  }

  Widget _buildQuickAccess() {
    return Column(children: [
      _QuickTileWide(
        icon: Icons.location_searching,
        label: 'Mes Alertes',
        subtitle: 'Animaux déclarés perdus',
        color: Colors.orange.shade700,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MesAlertesPage())),
      ),
      const SizedBox(height: 10),
      _QuickTileWide(
        icon: Icons.pets,
        label: 'Trouver un compagnon',
        subtitle: 'Feed · Recherche · Carte',
        color: _teal,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TrouverCompagnonPage())),
      ),
      const SizedBox(height: 10),
      _QuickTileWide(
        icon: Icons.nfc_outlined,
        label: 'Recherche par puce',
        subtitle: 'Perdus · Trouvés · Élevage',
        color: const Color(0xFF374151),
        onTap: () => showModalBottomSheet(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const ChipSearchSheet(),
        ),
      ),
    ]);
  }

  Widget _buildMesAnimauxSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.pets, color: _teal, size: 18),
              const SizedBox(width: 6),
              const Text('Mes Animaux',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 16, color: Color(0xFF1F2A2E))),
            ]),
            TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const UserParticulierFeed(initialTab: 1))),
              child: Text('Voir tout',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 185,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _animaux.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final a = _animaux[i];
              return _AnimalMiniCard(
                animal: a,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnimalFicheParticulierPage(
                    animalId: a['id'] as String?,
                    initialData: a,
                  ),
                )),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnnoncesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.campaign_outlined, color: _teal, size: 18),
              const SizedBox(width: 6),
              const Text('Trouver un compagnon',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 16, color: Color(0xFF1F2A2E))),
            ]),
            TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AnnoncesPublicPage())),
              child: Text('Voir tout',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_annonces.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text('Aucune annonce disponible',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    color: Colors.grey.shade500))),
          )
        else
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _annonces.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _AnnonceMiniCard(
                annonce: _annonces[i],
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnnonceDetailPage(
                    annonceId: _annonces[i]['id'] as String,
                    initialData: _annonces[i],
                  ),
                )),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAnimauxPerdusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(Icons.location_searching, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 6),
              const Text('Perdus & Trouvés',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF1F2A2E))),
            ]),
            TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AnimauxPerdusPage())),
              child: Text('Voir tout',
                  style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13, color: Colors.orange.shade700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingAlertes)
          const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2),
          ))
        else if (_alertesPubliques.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Center(
              child: Text('Aucun animal perdu signalé',
                  style: TextStyle(
                      fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
            ),
          )
        else
          SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _alertesPubliques.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) =>
                  _PerduMiniCard(alerte: _alertesPubliques[i],
                      onShare: () => _shareAlerte(_alertesPubliques[i]),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => AnimauxPerdusPage(
                              initialAlertId: _alertesPubliques[i]['id'] as String?)))),
            ),
          ),
      ],
    );
  }

  Widget _buildAlerteBanner() {
    final nb = _mesAlertes.length;
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MesAlertesPage())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade300, width: 1.5),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: Icon(Icons.location_searching,
                  color: Colors.orange.shade700, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.orange.shade400),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool highlight;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: highlight ? Colors.orange.shade200 : Colors.white,
                size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: Colors.white)),
                Text(label,
                    style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 11, color: Colors.white70)),
              ],
            ),
          ],
        ),
      );
}

class _QuickTileData {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickTileData(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
}

class _QuickTile extends StatelessWidget {
  final _QuickTileData data;
  const _QuickTile({required this.data});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.10),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                ),
                child: Icon(data.icon, color: data.color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(data.label,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ],
          ),
        ),
      );
}

class _AnimalMiniCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final VoidCallback onTap;
  const _AnimalMiniCard({required this.animal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nom = (animal['nom'] ?? 'Sans nom') as String;
    final espece = (animal['espece'] ?? '') as String;
    final race = (animal['race'] ?? '') as String;
    final sexe = ((animal['sexe'] ?? '') as String).toLowerCase();
    final photoUrl = animal['photo_url'] as String?;
    final isMale = sexe.startsWith('m');
    final isFemale = sexe.startsWith('f');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 135,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photoUrl != null && photoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _placeholder(espece),
                          errorWidget: (_, __, ___) => _placeholder(espece))
                      : _placeholder(espece),
                  // Sex badge top-right
                  if (isMale || isFemale)
                    Positioned(
                      top: 5, right: 5,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isMale ? Colors.blue.shade100 : Colors.pink.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isMale ? Icons.male : Icons.female,
                          size: 12,
                          color: isMale ? Colors.blue.shade700 : Colors.pink.shade700,
                        ),
                      ),
                    ),
                  // Species icon bottom-left
                  if (espece.isNotEmpty)
                    Positioned(
                      bottom: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: speciesIcon(espece, 12, const Color(0xFF6E9E57)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 12, color: Color(0xFF1F2A2E)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 1),
              Text(race.isNotEmpty ? race : speciesLabel(espece),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF6F767B)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder(String espece) => Container(
        color: const Color(0xFFEAF4EC),
        child: Center(child: speciesIcon(espece.isNotEmpty ? espece : 'autre', 32, const Color(0xFF6E9E57))),
      );
}

class _PerduMiniCard extends StatelessWidget {
  final Map<String, dynamic> alerte;
  final VoidCallback onShare;
  final VoidCallback onTap;
  const _PerduMiniCard(
      {required this.alerte, required this.onShare, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nom = (alerte['nom_animal'] ?? '') as String;
    final espece = (alerte['espece'] ?? '') as String;
    final ville = (alerte['derniere_localisation'] ?? '') as String;
    final photoUrl = alerte['photo_url'] as String?;
    final dateStr = alerte['date_perte'] as String?;
    final date = dateStr != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))
        : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade200, width: 1.2),
          boxShadow: [
            BoxShadow(
                color: Colors.orange.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            child: SizedBox(
              height: 80,
              width: double.infinity,
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text(nom,
                style: const TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF1F2A2E)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$espece${ville.isNotEmpty ? ' · $ville' : ''}',
              style: const TextStyle(
                  fontFamily: 'Galey', fontSize: 10, color: Color(0xFF6F767B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (date.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(date,
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 10,
                      color: Colors.orange.shade700)),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: SizedBox(
              width: double.infinity,
              height: 26,
              child: OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share, size: 11),
                label: const Text('Partager',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade700,
                  side: BorderSide(color: Colors.orange.shade300, width: 0.8),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.orange.shade50,
        child: Center(
            child: Icon(Icons.pets, color: Colors.orange.shade200, size: 28)),
      );
}

// ── Bouton accès rapide pleine largeur ────────────────────────────────────────

class _QuickTileWide extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _QuickTileWide({
    required this.icon, required this.label, required this.subtitle,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(
              fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
          Text(subtitle, style: TextStyle(
              fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
        ])),
        Icon(Icons.play_arrow_rounded, color: color, size: 22),
      ]),
    ),
  );
}

// ── Mini-carte annonce ────────────────────────────────────────────────────────

class _AnnonceMiniCard extends StatelessWidget {
  final Map<String, dynamic> annonce;
  final VoidCallback onTap;
  const _AnnonceMiniCard({required this.annonce, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final titre    = (annonce['titre'] as String?) ?? '';
    final espece   = (annonce['espece'] as String?) ?? '';
    final race     = (annonce['race'] as String?) ?? '';
    final photos   = List<String>.from(annonce['photos'] ?? []);
    final isSaillie = annonce['type_vente'] == 'saillie';
    final isPortee  = annonce['type'] == 'portee';
    final ville    = (annonce['ville_eleveur'] as String?) ?? '';

    final prixRaw = isPortee
        ? (annonce['prix_min_portee'] ?? annonce['prix_max_portee'])
        : annonce['prix'];
    final prix = prixRaw != null ? '${(prixRaw as num).toInt()} €' : null;

    final displayTitle = titre.isNotEmpty ? titre
        : (race.isNotEmpty ? race : speciesLabel(espece));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                photos.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photos.first, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: const Color(0xFFEEF5EA)),
                        errorWidget: (_, __, ___) => Container(color: const Color(0xFFEEF5EA)))
                    : Container(color: const Color(0xFFEEF5EA),
                        child: Center(child: speciesIcon(espece, 32, const Color(0xFF6E9E57)))),
                Positioned(top: 5, left: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSaillie
                          ? const Color(0xFF8B5CF6)
                          : isPortee ? const Color(0xFFF59E0B) : const Color(0xFF6E9E57),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isSaillie ? 'Saillie' : isPortee ? 'Portée' : 'Compagnon',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 8,
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(displayTitle,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 11, color: Color(0xFF1F2A2E)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (prix != null)
                Text(prix, style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF0C5C6C))),
              if (ville.isNotEmpty)
                Text('ðŸ“ $ville',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 9,
                        color: Color(0xFF9CA3AF)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}
