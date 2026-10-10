import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/pages/services/service_detail_page.dart';
import 'package:PetsMatch/pages/services/service_list_page.dart';
import 'package:PetsMatch/utils/annuaire_filtres.dart';
import 'package:PetsMatch/widgets/annuaire_filtres_widgets.dart';

const _teal = Color(0xFF0C5C6C);
const _dark = Color(0xFF1E2025);
const _bg = Color(0xFFF6F7F5);
const _bordure = Color(0xFFE5E8E6);

/// Annuaire des professionnels — page unique, la même pour tous les profils :
/// recherche + filtres compacts sur deux colonnes (catégorie et type de
/// service, animaux concernés à cases à cocher, ville / code postal, et
/// « Filtres » pour le rayon), filtres actifs supprimables, résultats. Critères
/// combinables (ex. Transport + Taxi animalier + Chevaux). Logique partagée :
/// lib/utils/annuaire_filtres.dart — miroir site :
/// website/src/components/annuaire/AnnuaireRecherche.tsx.
class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final _supa = Supabase.instance.client;
  final _qCtrl = TextEditingController();

  List<Map<String, dynamic>> _pros = [];
  Set<String> _creneauOk = {};
  bool _loading = true;
  LieuRecherche? _maPosition;

  String _q = '';
  String _categorie = '';
  String _type = '';
  List<String> _especes = [];
  LieuRecherche? _lieu;
  int _rayon = 50;

  @override
  void initState() {
    super.initState();
    _charger();
    _chargerMaPosition();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final rows = await _supa
          .from('user_profiles_complet')
          .select()
          .inFilter('statut_pro', ['actif', 'validated'])
          .not('profile_type', 'in', '(eleveur,association)');
      final seen = <String>{};
      final pros = <Map<String, dynamic>>[];
      for (final r in rows) {
        if (!seen.add('${r['uid']}-${r['profile_type']}')) continue;
        pros.add({
          'uid': r['uid']?.toString() ?? '',
          '_profile_table_id': r['id']?.toString(),
          'name_elevage': r['nom'] ?? '',
          'cat_pro': r['profile_type'] ?? '',
          'profession_pro': r['profession_pro'] ?? '',
          'ville': r['ville_pro'] ?? r['ville'] ?? '',
          'photo': (r['banner_url'] ?? '').toString().isNotEmpty ? r['banner_url'] : r['avatar_url'],
          'lat': r['latitude'] ?? r['lat'],
          'lng': r['longitude'] ?? r['lng'],
          'especes_acceptees': r['especes_acceptees'] ?? [],
          'rayon_intervention': r['rayon_intervention'],
          'se_deplace': r['se_deplace'],
          'description': r['desc_entreprise'] ?? r['description'] ?? '',
        });
      }
      // Promeneurs : pet-sitters dont un créneau disponible est une promenade
      var creneauOk = <String>{};
      final gardeIds = pros.where((p) => p['cat_pro'] == 'garde')
          .map((p) => p['_profile_table_id']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      if (gardeIds.isNotEmpty) {
        try {
          final cr = await _supa.from('creneaux_pro').select('pro_profile_id, type_garde')
              .inFilter('pro_profile_id', gardeIds).eq('statut', 'disponible');
          creneauOk = (cr as List)
              .where((c) { final tg = c['type_garde']?.toString(); return tg == null || tg.isEmpty || tg == 'prestation'; })
              .map((c) => c['pro_profile_id']?.toString() ?? '').toSet();
        } catch (_) {}
      }
      if (mounted) setState(() { _pros = pros; _creneauOk = creneauOk; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chargerMaPosition() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final row = await _supa.from('user_profiles_complet')
          .select('lat, lng, ville').eq('uid', uid).eq('is_main', true).maybeSingle();
      final lat = (row?['lat'] as num?)?.toDouble();
      final lng = (row?['lng'] as num?)?.toDouble();
      if (lat != null && lng != null && mounted) {
        final v = (row?['ville'] ?? '').toString();
        setState(() => _maPosition = LieuRecherche('Autour de moi', lat, lng, ville: v.isEmpty ? null : v));
      }
    } catch (_) {}
  }

  // ── Résultats ──────────────────────────────────────────────────────────────

  List<(Map<String, dynamic>, double?)> get _resultats {
    final metier = metierSelectionne(_categorie, _type);
    final q = _q.toLowerCase();
    final out = <(Map<String, dynamic>, double?)>[];
    for (final p in _pros) {
      if (!proMatchesMetier(p, metier, creneauOk: _creneauOk)) continue;
      if (!proMatchesEspeces(p['especes_acceptees'], _especes)) continue;
      if (!proDansZone(p, _lieu, _rayon)) continue;
      if (q.isNotEmpty) {
        final hay = [p['name_elevage'], p['ville'], p['profession_pro'], p['description']]
            .map((e) => (e ?? '').toString().toLowerCase());
        if (!hay.any((h) => h.contains(q))) continue;
      }
      final lat = (p['lat'] as num?)?.toDouble(), lng = (p['lng'] as num?)?.toDouble();
      out.add((p, _lieu != null && lat != null && lng != null ? haversineKm(_lieu!.lat, _lieu!.lng, lat, lng) : null));
    }
    out.sort((a, b) => (a.$2 ?? 1e9).compareTo(b.$2 ?? 1e9));
    return out;
  }

  // Changer de catégorie garde les animaux sélectionnés (et le lieu).
  void _choisirCategorie(String k) => setState(() {
        _categorie = _categorie == k ? '' : k;
        _type = '';
      });

  void _reinitialiser() => setState(() {
        _qCtrl.clear();
        _q = ''; _categorie = ''; _type = ''; _especes = []; _lieu = null; _rayon = 50;
      });

  Future<void> _ouvrirFiltres() async {
    final res = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PanneauFiltres(lieu: _lieu, rayon: _rayon),
    );
    if (res != null) setState(() { _rayon = res; _q = _qCtrl.text.trim(); });
  }

  Future<void> _ouvrirAnimaux() async {
    final res = await showAnimauxSheet(context, _especes);
    if (res != null) setState(() => _especes = res);
  }

  Future<void> _ouvrirLieu() async {
    final c = await showLieuSheet(context, maPosition: _maPosition);
    if (c != null) setState(() => _lieu = c.lieu);
  }

  /// Catégories : sélection unique (comme avant), puis type de service.
  Future<void> _ouvrirCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        Widget ligne({required bool actif, required String label, Color? repere, bool sous = false, required VoidCallback onTap}) => InkWell(
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: EdgeInsets.fromLTRB(sous ? 44 : 20, 8, 20, 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: sous ? Colors.transparent : const Color(0xFFF1F2F1)))),
                child: Row(children: [
                  if (!sous) ...[
                    Container(width: 10, height: 10, decoration: BoxDecoration(
                        color: repere, shape: BoxShape.circle,
                        border: repere == null ? Border.all(color: Colors.grey.shade400) : null)),
                    const SizedBox(width: 14),
                  ],
                  Expanded(child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: sous ? 14 : 15,
                      fontWeight: actif ? FontWeight.w700 : FontWeight.w500, color: actif ? _teal : _dark))),
                  Icon(actif ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 22, color: actif ? _teal : Colors.grey.shade400),
                ]),
              ),
            );
        final cat = categorieByKey(_categorie);
        return DraggableScrollableSheet(
          expand: false, initialChildSize: 0.75, maxChildSize: 0.95,
          builder: (ctx, scroll) => Column(children: [
            Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.only(top: 12, bottom: 8), children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(children: [
                  const Expanded(child: Text('Catégories', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: _dark))),
                  IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Fermer', onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              ligne(actif: cat == null, label: 'Toutes les catégories', onTap: () {
                setState(() { _categorie = ''; _type = ''; }); setS(() {});
              }),
              for (final c in kCategoriesAnnuaire) ...[
                ligne(actif: c.key == _categorie, label: c.label, repere: Color(c.color), onTap: () {
                  _choisirCategorie(c.key); setS(() {});
                }),
                if (c.key == _categorie && c.types.isNotEmpty)
                  for (final t in [('', 'Tous les services'), ...c.types.map((t) => (t, metierByKey(t).label))])
                    ligne(actif: t.$1 == _type, label: t.$2, sous: true, onTap: () {
                      setState(() => _type = t.$1); setS(() {});
                    }),
              ],
            ])),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: _bordure))),
                child: Row(children: [
                  Expanded(child: TextButton(
                    onPressed: () { setState(() { _categorie = ''; _type = ''; }); setS(() {}); },
                    style: TextButton.styleFrom(foregroundColor: _teal, minimumSize: const Size.fromHeight(48)),
                    child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Appliquer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                  )),
                ]),
              ),
            ),
          ]),
        );
      }),
    );
  }

  void _ouvrirCarte() {
    final m = metierSelectionne(_categorie, _type);
    Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceListPage(
      categoryLabel: m.label,
      categoryColor: _teal,
      categoryIcon: Icons.map_outlined,
      catProValues: m.cats,
      professionValues: m.professions.isEmpty ? null : m.professions,
      matchCreneauTypeGarde: m.creneauTypeGarde,
      searchQuery: _q.isEmpty ? null : _q,
      initialShowMap: true,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    final resultats = _loading ? const <(Map<String, dynamic>, double?)>[] : _resultats;
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: canPop
                ? IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: () => Navigator.pop(context))
                : null,
            title: const Text('Annuaire des professionnels',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
            actions: [
              IconButton(icon: const Icon(Icons.map_outlined), tooltip: 'Voir sur la carte', onPressed: _ouvrirCarte),
            ],
          ),
          SliverToBoxAdapter(child: _buildEntete()),
          SliverToBoxAdapter(child: _buildFiltresActifs()),
          if (_categorie == 'sante') SliverToBoxAdapter(child: _buildUrgencesVet()),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(children: [
              Expanded(child: Text(
                  _loading ? 'Recherche…' : '${resultats.length} professionnel${resultats.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: _dark))),
              TextButton.icon(
                onPressed: _ouvrirCarte,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Voir la carte', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                style: TextButton.styleFrom(foregroundColor: _teal),
              ),
            ]),
          )),
          if (_loading)
            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: _teal)),
            ))
          else if (resultats.isEmpty)
            SliverToBoxAdapter(child: _buildAucunResultat())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CarteResultat(pro: resultats[i].$1, distance: resultats[i].$2),
                ),
                childCount: resultats.length,
              )),
            ),
        ],
      ),
    );
  }

  Widget _buildEntete() {
    final cat = categorieByKey(_categorie);
    final lieuLabel = _lieu == null
        ? 'Localisation'
        : identical(_lieu, _maPosition) && _maPosition?.ville != null
            ? 'Autour de moi (${_maPosition!.ville})'
            : (_lieu!.ville ?? _lieu!.label);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Trouvez le bon professionnel pour votre animal.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _bordure),
          ),
          child: TextField(
            controller: _qCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => setState(() => _q = v.trim()),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14.5),
            decoration: InputDecoration(
              hintText: 'Rechercher un professionnel',
              hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Filtres sur deux colonnes.
        Row(children: [
          Expanded(child: _CaseFiltre(
            icon: Icons.grid_view_rounded,
            label: cat == null ? 'Catégories' : (_type.isNotEmpty ? metierByKey(_type).label : cat.label),
            actif: cat != null,
            repere: cat == null ? null : Color(cat.color),
            onTap: _ouvrirCategories,
          )),
          const SizedBox(width: 8),
          Expanded(child: _CaseFiltre(
            icon: Icons.pets_outlined,
            label: _especes.isEmpty ? 'Animaux' : resumeAnimaux(_especes),
            actif: _especes.isNotEmpty,
            onTap: _ouvrirAnimaux,
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _CaseFiltre(
            icon: Icons.location_on_outlined,
            label: lieuLabel,
            actif: _lieu != null,
            onTap: _ouvrirLieu,
          )),
          const SizedBox(width: 8),
          Expanded(child: _CaseFiltre(
            icon: Icons.tune_rounded,
            label: _lieu != null ? 'Filtres (1)' : 'Filtres',
            actif: true,
            bouton: true,
            onTap: _ouvrirFiltres,
          )),
        ]),
      ]),
    );
  }

  Widget _buildFiltresActifs() {
    final cat = categorieByKey(_categorie);
    final actifs = <(String, VoidCallback)>[
      if (_q.isNotEmpty) ('« $_q »', () => setState(() { _q = ''; _qCtrl.clear(); })),
      if (cat != null) (cat.label, () => setState(() { _categorie = ''; _type = ''; })),
      if (_type.isNotEmpty) (metierByKey(_type).label, () => setState(() => _type = '')),
      for (final k in _especes)
        (kGroupesEspeces.firstWhere((g) => g.key == k).label,
            () => setState(() => _especes = _especes.where((x) => x != k).toList())),
      if (_lieu != null) ...[
        (_lieu!.ville ?? _lieu!.label, () => setState(() => _lieu = null)),
        ('$_rayon km', () => setState(() => _lieu = null)),
      ],
    ];
    if (actifs.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final a in actifs) AnnuaireChipSupprimable(label: a.$1, onRemove: a.$2),
        TextButton.icon(
          onPressed: _reinitialiser,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: _teal, padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
      ]),
    );
  }

  Widget _buildUrgencesVet() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: InkWell(
          onTap: () => launchUrl(Uri(scheme: 'tel', path: '3115')),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.25)),
            ),
            child: const Row(children: [
              Icon(Icons.local_hospital_outlined, size: 18, color: Color(0xFFE65100)),
              SizedBox(width: 8),
              Expanded(child: Text('Urgences vétérinaires 24h/24 : 3115',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFE65100)))),
              Icon(Icons.call_rounded, size: 18, color: Color(0xFFE65100)),
            ]),
          ),
        ),
      );

  Widget _buildAucunResultat() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _bordure)),
          child: Column(children: [
            const Text('Aucun professionnel ne correspond à ces critères.', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 14.5, color: _dark)),
            if (_lieu != null) ...[
              const SizedBox(height: 4),
              Text('Essayez un rayon plus large ou retirez le lieu.', textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
            ],
            TextButton(onPressed: _reinitialiser,
                child: const Text('Réinitialiser les filtres', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _teal, decoration: TextDecoration.underline))),
          ]),
        ),
      );
}

// ── Case de filtre (grille deux colonnes) ─────────────────────────────────────

class _CaseFiltre extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool actif;
  final Color? repere;
  final bool bouton;
  final VoidCallback onTap;
  const _CaseFiltre({required this.icon, required this.label, required this.actif, required this.onTap, this.repere, this.bouton = false});

  @override
  Widget build(BuildContext context) {
    final couleur = bouton || actif ? _teal : _dark;
    return Material(
      color: bouton ? const Color(0xFFE8F4F6) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: bouton ? _teal.withValues(alpha: 0.45) : actif ? _teal : _bordure),
          ),
          child: Row(mainAxisAlignment: bouton ? MainAxisAlignment.center : MainAxisAlignment.start, children: [
            if (repere != null)
              Container(width: 10, height: 10, decoration: BoxDecoration(color: repere, shape: BoxShape.circle))
            else
              Icon(icon, size: 19, color: bouton || actif ? _teal : Colors.grey.shade600),
            const SizedBox(width: 8),
            Flexible(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.2,
                    fontWeight: bouton || actif ? FontWeight.w700 : FontWeight.w500, color: couleur))),
            if (!bouton) ...[
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.grey.shade500),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── Carte de résultat ─────────────────────────────────────────────────────────

class _CarteResultat extends StatelessWidget {
  final Map<String, dynamic> pro;
  final double? distance;
  const _CarteResultat({required this.pro, required this.distance});

  @override
  Widget build(BuildContext context) {
    final photo = (pro['photo'] ?? '').toString();
    final cat = (pro['cat_pro'] ?? '').toString();
    final categorie = kCategoriesAnnuaire.where((c) => metierByKey(c.metier).cats.contains(cat)).firstOrNull;
    final color = categorie != null ? Color(categorie.color) : _teal;
    final profession = (pro['profession_pro'] ?? '').toString();
    final metierLabel = profession.isNotEmpty ? profession : categorie?.label ?? 'Professionnel';
    final ville = (pro['ville'] ?? '').toString();
    final groupes = groupesDesEspeces(pro['especes_acceptees']);
    final gris = Colors.grey.shade600;

    void ouvrir() => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailPage(
          proUid: pro['uid'] ?? '',
          profileTableId: pro['_profile_table_id'] as String?,
          categoryLabel: metierLabel,
          categoryColor: color,
        )));

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: ouvrir,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _bordure),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 88, height: 88,
                color: const Color(0xFFF3F4F6),
                child: photo.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(Icons.person_outline_rounded, color: Colors.grey.shade400, size: 30))
                    : Icon(Icons.person_outline_rounded, color: Colors.grey.shade400, size: 30),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((pro['name_elevage'] ?? 'Professionnel').toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, height: 1.2, color: _dark)),
              const SizedBox(height: 4),
              Row(children: [
                // Repère : couleur du marqueur de ce métier sur la carte.
                Container(width: 8, height: 8, decoration: BoxDecoration(color: couleurMarqueurPro(cat), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(metierLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700))),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.location_on_outlined, size: 14, color: gris),
                const SizedBox(width: 4),
                Expanded(child: Text(
                    '${ville.isEmpty ? 'Ville non renseignée' : ville}'
                    '${distance != null ? ' · à ${distance! < 1 ? '< 1' : distance!.round()} km' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: gris))),
              ]),
              if (groupes.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.pets_outlined, size: 14, color: gris),
                  const SizedBox(width: 4),
                  Expanded(child: Text(groupes.map((g) => g.label).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: gris))),
                ]),
              ],
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('Voir la fiche', style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w700,
                    color: _teal, decoration: TextDecoration.underline)),
              ),
            ])),
          ]),
        ),
      ),
    );
  }
}

// ── Panneau Filtres : critère hors grille (rayon autour du lieu) ─────────────

class _PanneauFiltres extends StatefulWidget {
  final LieuRecherche? lieu;
  final int rayon;
  const _PanneauFiltres({required this.lieu, required this.rayon});

  @override
  State<_PanneauFiltres> createState() => _PanneauFiltresState();
}

class _PanneauFiltresState extends State<_PanneauFiltres> {
  late int _r = widget.rayon;

  @override
  Widget build(BuildContext context) {
    final actif = widget.lieu != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const Text('Filtres', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: _dark)),
          const SizedBox(height: 14),
          const Text('Rayon autour du lieu', style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            initialValue: _r,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: _dark),
            decoration: InputDecoration(
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _bordure)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _bordure)),
              disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _bordure)),
            ),
            items: [for (final r in kRayonsKm) DropdownMenuItem(value: r, child: Text('$r km'))],
            onChanged: actif ? (v) => setState(() => _r = v ?? 50) : null,
          ),
          if (!actif) ...[
            const SizedBox(height: 6),
            Text('Choisissez d\'abord une localisation.', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => setState(() => _r = 50),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal, side: const BorderSide(color: _teal),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _r),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Appliquer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            )),
          ]),
        ]),
      ),
    );
  }
}
