import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/widgets/app_nav_drawer.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/services/service_detail_page.dart';
import 'package:PetsMatch/utils/annuaire_filtres.dart';
import 'package:PetsMatch/widgets/annuaire_filtres_widgets.dart';
import 'package:PetsMatch/widgets/verification_badge.dart';
import 'package:url_launcher/url_launcher.dart';

/// Annuaire des professionnels — recherche par filtres combinables : mot-clé +
/// métier + lieu / rayon + animaux pris en charge (plusieurs choix). La
/// catégorie d'entrée (tuile de l'annuaire) ne fait que pré-sélectionner le
/// métier. Logique partagée : lib/utils/annuaire_filtres.dart (miroir site :
/// website/src/app/services/carte/page.tsx).
class ServiceListPage extends StatefulWidget {
  final String categoryLabel;
  final Color categoryColor;
  final IconData categoryIcon;
  final List<String> catProValues;
  final List<String>? professionValues;
  final List<String>? matchCreneauTypeGarde;
  final String? searchQuery;
  /// Ouvrir directement la vue carte (bouton carte de l'annuaire)
  final bool initialShowMap;

  const ServiceListPage({
    super.key,
    required this.categoryLabel,
    required this.categoryColor,
    required this.categoryIcon,
    required this.catProValues,
    this.professionValues,
    this.matchCreneauTypeGarde,
    this.searchQuery,
    this.initialShowMap = false,
  });

  @override
  State<ServiceListPage> createState() => _ServiceListPageState();
}

class _ServiceListPageState extends State<ServiceListPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _pros = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  bool _showMap = false;
  bool _locating = false;

  // Formulaire (brouillon) et critères appliqués (« Rechercher »)
  final _qCtrl = TextEditingController();
  String _metierForm = '';
  LieuRecherche? _lieuForm;
  int _rayonForm = 50;
  List<String> _especes = []; // appliqué directement (menu « Appliquer » / étiquettes)

  String _q = '';
  String _metier = '';
  LieuRecherche? _lieu;
  int _rayon = 50;

  /// Profils garde proposant des créneaux promenade (repli « Promeneur »)
  Set<String> _creneauOk = {};
  LieuRecherche? _maPosition;

  GoogleMapController? _mapCtrl;

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _showMap = widget.initialShowMap;
    _metier = _metierForm = metierFromLegacy(widget.catProValues, widget.professionValues).key;
    if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
      _q = widget.searchQuery!;
      _qCtrl.text = _q;
    }
    _loadPros();
    _loadMaPosition();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  /// Position du profil connecté → option « Autour de moi » du lieu.
  Future<void> _loadMaPosition() async {
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

  Future<void> _loadPros() async {
    try {
      // Tous les pros (hors éleveurs / associations, qui ont leur espace) :
      // le métier se change dans le formulaire, sans recharger.
      final rows = await _supa
          .from('user_profiles_complet')
          .select()
          .inFilter('statut_pro', ['actif', 'validated'])
          .not('profile_type', 'in', '(eleveur,association)');

      final seen = <String>{};
      final pros = <Map<String, dynamic>>[];
      for (final row in rows) {
        final key = '${row['uid']}-${row['profile_type']}';
        if (!seen.add(key)) continue;
        pros.add(_buildProEntry(row));
      }

      // Promeneurs : pet-sitters dont un créneau disponible est de type
      // promenade (type_garde nul = les deux usages → qualifiant).
      var creneauOk = <String>{};
      final gardeIds = pros.where((p) => p['cat_pro'] == 'garde')
          .map((p) => p['_profile_table_id']?.toString() ?? '')
          .where((s) => s.isNotEmpty).toList();
      if (gardeIds.isNotEmpty) {
        try {
          final cr = await _supa.from('creneaux_pro')
              .select('pro_profile_id, type_garde')
              .inFilter('pro_profile_id', gardeIds)
              .eq('statut', 'disponible');
          creneauOk = (cr as List)
              .where((c) { final tg = c['type_garde']?.toString(); return tg == null || tg.isEmpty || tg == 'prestation'; })
              .map((c) => c['pro_profile_id']?.toString() ?? '')
              .toSet();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _pros = pros;
          _creneauOk = creneauOk;
          _loading = false;
        });
        _applyFilters();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _buildProEntry(Map<String, dynamic> row) {
    final nomVal = row['nom'] ?? row['name_elevage'] ?? '';
    final villeVal = row['ville_pro'] ?? row['ville'] ?? '';
    return {
      'uid': row['uid']?.toString() ?? '',
      '_profile_table_id': row['id']?.toString(),
      'name_elevage': nomVal,
      'firstname': row['firstname'] ?? '',
      'cat_pro': row['profile_type'] ?? row['cat_pro'] ?? '',
      'profession_pro': row['profession_pro'] ?? '',
      'ville': villeVal,
      'ville_elevage': villeVal,
      'profile_picture_url': row['avatar_url'] ?? '',
      'profile_picture_url_elevage': row['avatar_url'] ?? '',
      'lat': row['latitude'] ?? row['lat'],
      'lng': row['longitude'] ?? row['lng'],
      'especes_acceptees': row['especes_acceptees'] ?? [],
      'accept_new_clients': row['accept_new_clients'] ?? true,
      'banner_url': row['banner_url'] ?? '',
      'desc_entreprise': row['desc_entreprise'] ?? row['description'] ?? '',
      'site_web': row['site_web'] ?? '',
      'instagram': row['instagram'] ?? '',
      'facebook': row['facebook'] ?? '',
      'rayon_intervention': row['rayon_intervention'] ?? 20,
      'se_deplace': row['se_deplace'],
      'region': row['region'] ?? '',
      'departement': row['departement'] ?? '',
      'region_elevage': row['region'] ?? '',
      'departement_elevage': row['departement'] ?? '',
      'horaires': row['horaires'] ?? {},
      'certifications': row['certifications'] ?? [],
      'tarifs': row['tarifs'] ?? '',
    };
  }

  // ── Markers ────────────────────────────────────────────────────────────────

  double _hueForCat(String cat) => hueMarqueurPro(cat);

  Set<Marker> _buildMarkers() => _filtered
      .where((p) => p['lat'] != null && p['lng'] != null)
      .map((p) => Marker(
            markerId: MarkerId(p['uid']?.toString() ?? p.hashCode.toString()),
            position: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
            icon: BitmapDescriptor.defaultMarkerWithHue(_hueForCat(p['cat_pro'] ?? '')),
            onTap: () => _showProSheet(p),
          ))
      .toSet();

  void _showProSheet(Map<String, dynamic> pro) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProMapSheet(
        pro: pro,
        categoryColor: widget.categoryColor,
        categoryLabel: widget.categoryLabel,
      ),
    );
  }

  // ── « Proche de moi » (vue carte) = lieu « Autour de moi » ─────────────────

  bool get _nearMe => _lieu != null && identical(_lieu, _maPosition);

  Future<void> _toggleNearMe() async {
    if (_nearMe) {
      setState(() { _lieu = _lieuForm = null; });
      _applyFilters();
      return;
    }
    if (_maPosition == null) {
      setState(() => _locating = true);
      await _loadMaPosition();
      if (mounted) setState(() => _locating = false);
    }
    if (!mounted) return;
    if (_maPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(FirebaseAuth.instance.currentUser == null
            ? 'Connectez-vous pour utiliser cette fonctionnalité.'
            : 'Position introuvable dans votre profil. Renseignez votre adresse dans les paramètres.',
            style: const TextStyle(fontFamily: 'Galey')),
      ));
      return;
    }
    setState(() { _lieu = _lieuForm = _maPosition; });
    _applyFilters();
    if (_showMap && _mapCtrl != null) {
      _mapCtrl!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_maPosition!.lat, _maPosition!.lng), 10));
    }
  }

  // ── Filtres ────────────────────────────────────────────────────────────────

  void _applyFilters() {
    final metier = metierByKey(_metier);
    final q = _q.toLowerCase();
    setState(() {
      _filtered = _pros.where((p) {
        if (!proMatchesMetier(p, metier, creneauOk: _creneauOk)) return false;
        if (!proMatchesEspeces(p['especes_acceptees'], _especes)) return false;
        if (!proDansZone(p, _lieu, _rayon)) return false;
        if (q.isNotEmpty) {
          final hay = [p['name_elevage'], p['firstname'], p['ville'], p['profession_pro']]
              .map((e) => (e ?? '').toString().toLowerCase());
          if (!hay.any((h) => h.contains(q))) return false;
        }
        return true;
      }).toList();
    });
  }

  void _rechercher() {
    FocusScope.of(context).unfocus();
    _q = _qCtrl.text.trim();
    _metier = _metierForm;
    _lieu = _lieuForm;
    _rayon = _rayonForm;
    _applyFilters();
  }

  void _setEspeces(List<String> keys) {
    _especes = keys;
    _applyFilters();
  }

  void _reinitialiser() {
    _qCtrl.clear();
    _q = ''; _metier = _metierForm = ''; _lieu = _lieuForm = null; _rayon = _rayonForm = 50; _especes = [];
    _applyFilters();
  }

  bool get _hasActiveFilters => _q.isNotEmpty || _metier.isNotEmpty || _lieu != null || _especes.isNotEmpty;

  // ── Formulaire de recherche ────────────────────────────────────────────────

  Widget _buildFiltersBar() {
    const teal = Color(0xFF0C5C6C);
    final lieuLabel = _lieuForm == null
        ? 'Toute la France'
        : identical(_lieuForm, _maPosition) && _maPosition?.ville != null
            ? 'Autour de moi (${_maPosition!.ville})'
            : _lieuForm!.label;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _qCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _rechercher(),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Nom ou mot-clé',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFFF4F4F4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          AnnuaireSelectField(
            label: 'Métier',
            value: metierByKey(_metierForm).label,
            icon: Icons.work_outline_rounded,
            placeholder: _metierForm.isEmpty,
            onTap: () async {
              final k = await showMetierSheet(context, _metierForm);
              if (k != null) setState(() => _metierForm = k);
            },
          ),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: AnnuaireSelectField(
              label: 'Lieu',
              value: lieuLabel,
              icon: Icons.location_on_outlined,
              placeholder: _lieuForm == null,
              onTap: () async {
                final c = await showLieuSheet(context, maPosition: _maPosition);
                if (c != null) setState(() => _lieuForm = c.lieu);
              },
            )),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: AnnuaireSelectField(
              label: 'Rayon',
              value: '$_rayonForm km',
              enabled: _lieuForm != null,
              onTap: () async {
                final r = await showRayonSheet(context, _rayonForm);
                if (r != null) setState(() => _rayonForm = r);
              },
            )),
          ]),
          const SizedBox(height: 10),
          AnnuaireSelectField(
            label: 'Animaux pris en charge',
            value: resumeAnimaux(_especes),
            icon: Icons.pets_outlined,
            placeholder: _especes.isEmpty,
            onTap: () async {
              final sel = await showAnimauxSheet(context, _especes);
              if (sel != null) _setEspeces(sel);
            },
          ),
          if (_especes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: _especes.map((k) => AnnuaireChipSupprimable(
              label: kGroupesEspeces.firstWhere((g) => g.key == k).label,
              onRemove: () => _setEspeces(_especes.where((x) => x != k).toList()),
            )).toList()),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              onPressed: _rechercher,
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Rechercher', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )),
            if (_hasActiveFilters) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _reinitialiser,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  // ── Bannière urgences vétérinaires ────────────────────────────────────────

  Widget _buildUrgencesVetBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFF6F00).withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6F00).withValues(alpha: 0.10),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.emergency_rounded, color: Color(0xFFE65100), size: 18),
                  SizedBox(width: 8),
                  Text('Urgences vétérinaires 24h/24',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFFE65100))),
                ],
              ),
            ),
            // Ligne n° national
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16, color: Color(0xFFE65100)),
                  const SizedBox(width: 8),
                  const Text('3115',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFFE65100))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('— Vétérinaire de garde national',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri(scheme: 'tel', path: '3115');
                      try { await _launchUri(uri); } catch (_) {}
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Appeler',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            // Lien vétérinaire de garde Paris
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
              child: GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://www.veterinaire-de-garde-paris.fr');
                  try { await _launchUri(uri); } catch (_) {}
                },
                child: Row(
                  children: [
                    const Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF0C5C6C)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Vétérinaire de garde Paris',
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0C5C6C),
                              decoration: TextDecoration.underline)),
                    ),
                    Text('veterinaire-de-garde-paris.fr',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade400)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUri(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ── Vue carte plein écran ─────────────────────────────────────────────────

  Widget _buildMapView() {
    final markers = _buildMarkers();
    final initialTarget = _lieu != null ? LatLng(_lieu!.lat, _lieu!.lng) : const LatLng(46.5, 2.5);
    final initialZoom = _lieu != null ? 10.0 : 6.0;

    return Scaffold(
      backgroundColor: const Color(0xFF1E2025),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)))
          else if (markers.isEmpty)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(widget.categoryIcon, size: 64, color: Colors.white30),
                const SizedBox(height: 12),
                Text(
                  _filtered.isEmpty ? 'Aucun professionnel trouvé' : 'Aucun professionnel\navec position GPS',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.white54),
                ),
              ]),
            )
          else
            GoogleMap(
              initialCameraPosition: CameraPosition(target: initialTarget, zoom: initialZoom),
              markers: markers,
              onMapCreated: (c) => _mapCtrl = c,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              zoomGesturesEnabled: true,
              scrollGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: false,
            ),

          // Overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                _mapIconButton(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _locating ? null : _toggleNearMe,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _nearMe ? widget.categoryColor : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_locating)
                        SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2,
                            color: _nearMe ? Colors.white : widget.categoryColor))
                      else
                        Icon(Icons.near_me_rounded, size: 14,
                          color: _nearMe ? Colors.white : widget.categoryColor),
                      const SizedBox(width: 6),
                      Text('Proche de moi', style: TextStyle(
                        fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                        color: _nearMe ? Colors.white : const Color(0xFF333333),
                      )),
                    ]),
                  ),
                ),
                const Spacer(),
                _mapIconButton(Icons.list_rounded, () => setState(() => _showMap = false)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF1E2025)),
      ),
    );
  }

  // ── Build principal ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showMap) return _buildMapView();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      endDrawer: const AppNavDrawer(),
      appBar: AppBar(
        title: const Text('Annuaire des professionnels',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Vue carte',
            onPressed: () => setState(() => _showMap = true),
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildFiltersBar()),

          // Bannière urgences vétérinaires
          if (metierByKey(_metier).cats.contains('veterinaire'))
            SliverToBoxAdapter(child: _buildUrgencesVetBanner()),

          if (!_loading)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                const Text('Résultats', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15)),
                const Spacer(),
                Text('${_filtered.length} résultat${_filtered.length > 1 ? 's' : ''}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
              ]),
            )),
          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57))))
          else if (_filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.categoryIcon, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Aucun professionnel trouvé',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  Text(_lieu != null ? 'Essayez un rayon plus large ou « Toute la France ».' : 'Essayez d\'élargir vos filtres.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
                ]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ProCard(
                      pro: _filtered[i],
                      categoryColor: widget.categoryColor,
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ServiceDetailPage(
                          proUid: _filtered[i]['uid'] ?? '',
                          profileTableId: _filtered[i]['_profile_table_id'] as String?,
                          categoryLabel: widget.categoryLabel,
                          categoryColor: widget.categoryColor,
                        ),
                      )),
                    ),
                  ),
                  childCount: _filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Bottom sheet carte ────────────────────────────────────────────────────────

class _ProMapSheet extends StatelessWidget {
  final Map<String, dynamic> pro;
  final Color categoryColor;
  final String categoryLabel;

  const _ProMapSheet({required this.pro, required this.categoryColor, required this.categoryLabel});

  @override
  Widget build(BuildContext context) {
    final nom    = pro['name_elevage'] ?? pro['firstname'] ?? 'Professionnel';
    final prof   = pro['profession_pro'] ?? '';
    final ville  = pro['ville_elevage'] ?? pro['ville'] ?? '';
    final photo  = pro['profile_picture_url_elevage'] ?? pro['profile_picture_url'] ?? '';
    final accept = pro['accept_new_clients'] ?? true;
    final especes = groupesDesEspeces(pro['especes_acceptees']).map((g) => g.label).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: categoryColor.withValues(alpha: 0.12)),
            child: photo.isNotEmpty
                ? ClipRRect(borderRadius: BorderRadius.circular(14),
                    child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(Icons.person_outline, color: categoryColor, size: 28)))
                : Icon(Icons.person_outline, color: categoryColor, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nom.toString(), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            if (prof.isNotEmpty)
              Text(prof.toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: categoryColor, fontWeight: FontWeight.w600)),
            if (ville.isNotEmpty)
              Row(children: [
                Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 2),
                Text(ville.toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
              ]),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accept ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(accept ? 'Dispo' : 'Complet',
                style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700,
                    color: accept ? const Color(0xFF388E3C) : const Color(0xFFF57C00))),
          ),
        ]),
        if (especes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4, children: especes.take(4).map((e) =>
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: categoryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(e, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: categoryColor, fontWeight: FontWeight.w600)),
            )).toList()),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: categoryColor, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => ServiceDetailPage(
                  proUid: pro['uid'] ?? '',
                  profileTableId: pro['_profile_table_id'] as String?,
                  categoryLabel: categoryLabel,
                  categoryColor: categoryColor,
                ),
              ));
            },
            child: const Text('Voir le profil', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ── Carte professionnel ───────────────────────────────────────────────────────

class _ProCard extends StatelessWidget {
  final Map<String, dynamic> pro;
  final Color categoryColor;
  final VoidCallback onTap;

  const _ProCard({required this.pro, required this.categoryColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nom        = pro['name_elevage'] ?? pro['firstname'] ?? 'Professionnel';
    final profession = pro['profession_pro'] ?? '';
    final ville      = pro['ville_elevage'] ?? pro['ville'] ?? '';
    final photo      = pro['profile_picture_url_elevage'] ?? pro['profile_picture_url'] ?? '';
    final banner     = pro['banner_url'] ?? '';
    final accept     = pro['accept_new_clients'] ?? true;
    final especeList = groupesDesEspeces(pro['especes_acceptees']).map((g) => g.label).toList();
    final urgences24h = pro['urgences_24h'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(clipBehavior: Clip.none, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 100, width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                banner.isNotEmpty
                    ? CachedNetworkImage(imageUrl: banner, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _gradient())
                    : (photo.isNotEmpty
                        ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                            color: Colors.black26, colorBlendMode: BlendMode.darken,
                            errorWidget: (_, __, ___) => _gradient())
                        : _gradient()),
                Positioned(top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accept ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(accept ? 'Disponible' : 'Complet',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700,
                        color: accept ? const Color(0xFF388E3C) : const Color(0xFFF57C00))),
                  )),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(nom.toString(),
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E2025)))),
                  if (urgences24h) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.emergency_rounded, size: 11, color: Color(0xFFE65100)),
                        SizedBox(width: 3),
                        Text('24h/24', style: TextStyle(fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFE65100))),
                      ]),
                    ),
                    const SizedBox(width: 4),
                  ],
                  VerificationBadge(
                    level: getVerificationLevel(
                      statutPro: pro['statut_pro']?.toString(),
                      siret: pro['siret']?.toString(),
                      isPremium: pro['is_premium'] == true,
                    ),
                  ),
                ]),
                if (profession.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(profession.toString(),
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: categoryColor, fontWeight: FontWeight.w600)),
                ],
                if (ville.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 2),
                    Text(ville.toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ],
                if (especeList.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 4, runSpacing: 4, children: especeList.take(4).map((e) =>
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: categoryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(e, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: categoryColor, fontWeight: FontWeight.w600)),
                    )
                  ).toList()),
                ],
              ]),
            ),
          ]),
          Positioned(
            top: 58, left: 12,
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)],
              ),
              child: ClipOval(
                child: photo.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _avatarPlaceholder())
                    : _avatarPlaceholder(),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _gradient() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [categoryColor.withValues(alpha: 0.8), const Color(0xFF1E2025)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
  );

  Widget _avatarPlaceholder() => Container(
    color: categoryColor.withValues(alpha: 0.15),
    child: Icon(Icons.store_outlined, size: 26, color: categoryColor),
  );
}


/// Teinte du marqueur d'un professionnel sur la carte de l'annuaire, selon
/// son profile_type. Partagée avec la liste (repère coloré des fiches).
double hueMarqueurPro(String cat) => switch (cat) {
  'sante' || 'veterinaire' => BitmapDescriptor.hueAzure,
  'education'              => BitmapDescriptor.hueOrange,
  'garde'                  => BitmapDescriptor.hueGreen,
  'referencement'          => BitmapDescriptor.hueYellow,
  _                        => BitmapDescriptor.hueViolet,
};

/// Couleur affichée correspondant à [hueMarqueurPro] (même teinte).
Color couleurMarqueurPro(String cat) => HSVColor.fromAHSV(1, hueMarqueurPro(cat), 0.8, 0.95).toColor();
