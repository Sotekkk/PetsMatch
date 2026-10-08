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
const _dark = Color(0xFF1F2A2E);
const _bg = Color(0xFFF8F8F8);

const _iconesCategories = <String, IconData>{
  'sante': Icons.medical_services_outlined,
  'education': Icons.school_outlined,
  'garde': Icons.home_outlined,
  'toilettage': Icons.content_cut,
  'transport': Icons.local_shipping_outlined,
  'photographe': Icons.photo_camera_outlined,
  'boutiques': Icons.shopping_bag_outlined,
  'assurance': Icons.shield_outlined,
};

/// Annuaire des professionnels — page unique, la même pour tous les profils :
/// recherche + bouton « Filtres » (animaux concernés à cases à cocher, ville
/// / code postal, rayon), catégories en cartes, types de service de la
/// catégorie choisie, filtres actifs supprimables, résultats. Critères
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
    final res = await showModalBottomSheet<(List<String>, LieuRecherche?, int)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PanneauFiltres(especes: _especes, lieu: _lieu, rayon: _rayon, maPosition: _maPosition),
    );
    if (res != null) {
      setState(() { _especes = res.$1; _lieu = res.$2; _rayon = res.$3; _q = _qCtrl.text.trim(); });
    }
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
          SliverToBoxAdapter(child: _buildCategories()),
          if (categorieByKey(_categorie)?.types.isNotEmpty ?? false) SliverToBoxAdapter(child: _buildTypes()),
          SliverToBoxAdapter(child: _buildFiltresActifs()),
          if (_categorie == 'sante') SliverToBoxAdapter(child: _buildUrgencesVet()),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Row(children: [
              const Expanded(child: Text('Professionnels correspondants',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark))),
              if (!_loading) Text('${resultats.length} résultat${resultats.length > 1 ? 's' : ''}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
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
    final nbFiltres = _especes.length + (_lieu != null ? 1 : 0);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFE6F2F1), _bg]),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Trouvez le bon professionnel pour votre animal.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: _qCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => setState(() => _q = v.trim()),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher un professionnel ou un service…',
                hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          )),
          const SizedBox(width: 8),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _ouvrirFiltres,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(nbFiltres > 0 ? 'Filtres ($nbFiltres)' : 'Filtres',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                backgroundColor: nbFiltres > 0 ? _teal.withValues(alpha: 0.08) : Colors.white,
                side: BorderSide(color: nbFiltres > 0 ? _teal : Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildCategories() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text('Catégories', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
        ),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.82,
          children: kCategoriesAnnuaire.map((c) {
            final actif = c.key == _categorie;
            final color = Color(c.color);
            return InkWell(
              onTap: () => _choisirCategorie(c.key),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  color: actif ? color.withValues(alpha: 0.07) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: actif ? color : Colors.grey.shade200, width: actif ? 2 : 1),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_iconesCategories[c.key], color: color, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(c.label, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 10.5, height: 1.15,
                          fontWeight: actif ? FontWeight.w800 : FontWeight.w600,
                          color: actif ? color : _dark)),
                ]),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _buildTypes() {
    final cat = categorieByKey(_categorie)!;
    final color = Color(cat.color);
    final types = [('', 'Tous'), ...cat.types.map((t) => (t, metierByKey(t).label))];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Type de service (${cat.label})',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _dark)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: types.map((t) {
          final actif = t.$1 == _type;
          return ChoiceChip(
            label: Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                color: actif ? Colors.white : Colors.grey.shade700)),
            selected: actif,
            showCheckmark: false,
            selectedColor: color,
            backgroundColor: Colors.white,
            side: BorderSide(color: actif ? color : Colors.grey.shade300),
            onSelected: (_) => setState(() => _type = t.$1),
          );
        }).toList()),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Filtres appliqués :', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
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
              Text('🚨', style: TextStyle(fontSize: 16)),
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
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Icon(Icons.search_off_rounded, size: 44, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Aucun professionnel ne correspond à ces critères.', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade600)),
            if (_lieu != null) ...[
              const SizedBox(height: 4),
              Text('Essayez un rayon plus large ou retirez le lieu.', textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
            ],
            TextButton(onPressed: _reinitialiser,
                child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', color: _teal))),
          ]),
        ),
      );
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
    final desc = (pro['description'] ?? '').toString();

    void ouvrir() => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailPage(
          proUid: pro['uid'] ?? '',
          profileTableId: pro['_profile_table_id'] as String?,
          categoryLabel: metierLabel,
          categoryColor: color,
        )));

    return InkWell(
      onTap: ouvrir,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 92, height: 92,
              color: color.withValues(alpha: 0.10),
              child: photo.isNotEmpty
                  ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(Icons.storefront_outlined, color: color, size: 32))
                  : Icon(Icons.storefront_outlined, color: color, size: 32),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(metierLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 14, color: _dark)),
            Text((pro['name_elevage'] ?? 'Professionnel').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Flexible(child: Text(
                  '${ville.isEmpty ? 'Ville non renseignée' : ville}'
                  '${distance != null ? ' · à ${distance! < 1 ? '< 1' : distance!.round()} km' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600))),
            ]),
            if (groupes.isNotEmpty) ...[
              const SizedBox(height: 5),
              Wrap(spacing: 4, runSpacing: 4, children: groupes.map((g) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: _teal.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                child: Text(g.label, style: const TextStyle(fontFamily: 'Galey', fontSize: 10.5,
                    fontWeight: FontWeight.w700, color: _teal)),
              )).toList()),
            ],
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 30,
                child: ElevatedButton(
                  onPressed: ouvrir,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Voir la fiche', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ])),
        ]),
      ),
    );
  }
}

// ── Panneau Filtres ───────────────────────────────────────────────────────────

class _PanneauFiltres extends StatefulWidget {
  final List<String> especes;
  final LieuRecherche? lieu;
  final int rayon;
  final LieuRecherche? maPosition;
  const _PanneauFiltres({required this.especes, required this.lieu, required this.rayon, required this.maPosition});

  @override
  State<_PanneauFiltres> createState() => _PanneauFiltresState();
}

class _PanneauFiltresState extends State<_PanneauFiltres> {
  late List<String> _e = [...widget.especes];
  late LieuRecherche? _l = widget.lieu;
  late int _r = widget.rayon;

  @override
  Widget build(BuildContext context) {
    final lieuLabel = _l == null
        ? 'Toute la France'
        : identical(_l, widget.maPosition) && widget.maPosition?.ville != null
            ? 'Autour de moi (${widget.maPosition!.ville})'
            : _l!.label;
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.82, maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(children: [
        Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const Text('Filtres', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: _dark)),
          const SizedBox(height: 14),
          Text('Animaux concernés', style: TextStyle(fontFamily: 'Galey', fontSize: 13,
              fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          Text('Plusieurs choix possibles', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          for (final g in kGroupesEspeces) CheckboxListTile(
            value: _e.contains(g.key),
            onChanged: (v) => setState(() => v == true ? _e.add(g.key) : _e.remove(g.key)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: _teal,
            title: Text(g.label, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _dark)),
            subtitle: g.detail == null ? null
                : Text(g.detail!, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ),
          const SizedBox(height: 12),
          AnnuaireSelectField(
            label: 'Ville ou code postal',
            value: lieuLabel,
            icon: Icons.location_on_outlined,
            placeholder: _l == null,
            onTap: () async {
              final c = await showLieuSheet(context, maPosition: widget.maPosition);
              if (c != null) setState(() => _l = c.lieu);
            },
          ),
          const SizedBox(height: 12),
          Text('Rayon', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
              fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Opacity(
            opacity: _l == null ? 0.45 : 1,
            child: Wrap(spacing: 6, runSpacing: 6, children: kRayonsKm.map((r) => ChoiceChip(
              label: Text('$r km', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                  color: _r == r ? Colors.white : Colors.grey.shade700)),
              selected: _r == r,
              showCheckmark: false,
              selectedColor: _teal,
              backgroundColor: Colors.white,
              side: BorderSide(color: _r == r ? _teal : Colors.grey.shade300),
              onSelected: _l == null ? null : (_) => setState(() => _r = r),
            )).toList()),
          ),
        ])),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => setState(() { _e = []; _l = null; _r = 50; }),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: () => Navigator.pop(context, (_e, _l, _r)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Appliquer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ),
      ]),
    );
  }
}
