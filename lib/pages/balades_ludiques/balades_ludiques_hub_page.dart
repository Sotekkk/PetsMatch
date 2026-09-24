import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'balades_ludiques_shared.dart';
import 'balades_ludiques_map_view.dart';
import 'balades_ludiques_filtres_sheet.dart';
import 'balade_ludique_detail_page.dart';
import 'creation/creation_flow_page.dart';
import 'mes_parcours_page.dart';
import 'classement_page.dart';
import 'mes_badges_page.dart';

const _darkC = Color(0xFF071C22);
const _bgGrad = LinearGradient(
  begin: Alignment.topCenter, end: Alignment.bottomCenter,
  colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
  stops: [0.0, 0.5, 1.0],
);

class BaladesLudiquesHubPage extends StatefulWidget {
  const BaladesLudiquesHubPage({super.key});

  @override
  State<BaladesLudiquesHubPage> createState() => _BaladesLudiquesHubPageState();
}

class _BaladesLudiquesHubPageState extends State<BaladesLudiquesHubPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  bool _mapView = false;
  List<Map<String, dynamic>> _balades = [];
  String _search = '';

  // Filtres
  String _espece = 'tous';
  bool _famille = false;
  bool _sportif = false;
  bool _pmr = false;
  bool _gratuit = false;
  String? _difficulte;
  int? _dureeMax;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _supa
          .from('balades_ludiques')
          .select()
          .eq('statut', 'publie')
          .order('created_at', ascending: false);
      if (mounted) setState(() { _balades = List<Map<String, dynamic>>.from(data as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _balades.where((b) {
      if (_espece != 'tous' && b['espece_cible'] != 'tous' && b['espece_cible'] != _espece) return false;
      if (_famille && b['famille'] != true) return false;
      if (_sportif && b['sportif'] != true) return false;
      if (_pmr && b['accessible_pmr'] != true) return false;
      if (_gratuit && b['gratuit'] != true) return false;
      if (_difficulte != null && b['difficulte'] != _difficulte) return false;
      if (_dureeMax != null && (b['duree_min'] == null || (b['duree_min'] as num) > _dureeMax!)) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final titre = (b['titre'] ?? '').toString().toLowerCase();
        final ville = (b['ville'] ?? '').toString().toLowerCase();
        if (!titre.contains(q) && !ville.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _evenementsOfficiels {
    return _balades.where((b) {
      final now = DateTime.now();
      if (b['type_evenement'] == 'communautaire') return false;
      final debut = DateTime.tryParse(b['event_debut']?.toString() ?? '');
      final fin = DateTime.tryParse(b['event_fin']?.toString() ?? '');
      if (debut == null || fin == null) return false;
      return now.isAfter(debut) && now.isBefore(fin);
    }).toList();
  }

  int get _activeFilterCount => [
        _espece != 'tous', _famille, _sportif, _pmr, _gratuit, _difficulte != null, _dureeMax != null,
      ].where((b) => b).length;

  Future<void> _openFiltres() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BaladesLudiquesFiltresSheet(
        espece: _espece, famille: _famille, sportif: _sportif,
        pmr: _pmr, gratuit: _gratuit, difficulte: _difficulte, dureeMax: _dureeMax,
      ),
    );
    if (result != null) {
      setState(() {
        _espece = result['espece'] as String;
        _famille = result['famille'] as bool;
        _sportif = result['sportif'] as bool;
        _pmr = result['pmr'] as bool;
        _gratuit = result['gratuit'] as bool;
        _difficulte = result['difficulte'] as String?;
        _dureeMax = result['dureeMax'] as int?;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _darkC,
      body: Container(
        decoration: const BoxDecoration(gradient: _bgGrad),
        child: Stack(children: [
          CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _heroSection(uid)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Search + filtres
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            child: TextField(
                              onChanged: (v) => setState(() => _search = v),
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Rechercher un parcours, une ville…',
                                hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                                prefixIcon: Icon(Icons.search, size: 18, color: Colors.white.withValues(alpha: 0.6)),
                                contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _glassButton(
                      icon: Icons.tune_rounded,
                      active: _activeFilterCount > 0,
                      badge: _activeFilterCount > 0 ? '$_activeFilterCount' : null,
                      onTap: _openFiltres,
                    ),
                    const SizedBox(width: 8),
                    _glassButton(
                      icon: _mapView ? Icons.view_list_outlined : Icons.map_outlined,
                      active: _mapView,
                      onTap: () => setState(() => _mapView = !_mapView),
                    ),
                  ]),
                  if (_evenementsOfficiels.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _openDetail(_evenementsOfficiels.first['id'] as String),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [kBlOrange, Color(0xFFEA580C)]),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(children: [
                          const Text('🏆', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            '${_evenementsOfficiels.length} chasse(s) au trésor officielle(s) en cours !',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13),
                          )),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 18),
                        ]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Parcours disponibles',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF7ED69D))))
            else if (_mapView)
              SliverFillRemaining(
                child: BaladesLudiquesMapView(balades: _filtered, onTap: (b) => _openDetail(b['id'] as String)),
              )
            else if (_filtered.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('Aucun parcours trouvé', style: TextStyle(fontFamily: 'Galey', color: Colors.white54))),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 90),
                sliver: SliverList.separated(
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _BaladeCard(
                    balade: _filtered[i],
                    onTap: () => _openDetail(_filtered[i]['id'] as String),
                  ),
                ),
              ),
          ]),
          // Bouton bas fixe
          if (uid != null)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [_darkC.withValues(alpha: 0), _darkC]),
                ),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CreationFlowPage()));
                      if (created == true) _load();
                    },
                    icon: const Icon(Icons.add, size: 18, color: Color(0xFF071C22)),
                    label: const Text('Créer un parcours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF071C22))),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7ED69D), elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _heroSection(String? uid) {
    final canPop = ModalRoute.of(context)?.isFirst == false;
    return Stack(children: [
      SizedBox(
        height: 210, width: double.infinity,
        child: Image.asset('assets/deco/communautybackground.jpg', fit: BoxFit.cover),
      ),
      Positioned(
        bottom: 0, left: 0, right: 0, height: 90,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, _darkC]),
          ),
        ),
      ),
      Positioned(
        top: 0, left: 0, right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              if (canPop)
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              if (canPop) const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Balades ludiques',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white)),
                  Text('Parcours, défis & chasses au trésor avec vos animaux',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white70)),
                ]),
              ),
              _glassAction(Icons.emoji_events_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassementPage()))),
              if (uid != null) ...[
                const SizedBox(width: 8),
                _glassAction(Icons.workspace_premium_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesBadgesPage()))),
                const SizedBox(width: 8),
                _glassAction(Icons.list_alt_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesParcoursPage()))),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _glassAction(IconData icon, VoidCallback onPressed) => GestureDetector(
    onTap: onPressed,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    ),
  );

  Widget _glassButton({required IconData icon, required VoidCallback onTap, bool active = false, String? badge}) =>
    GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF7ED69D).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: active ? const Color(0xFF7ED69D).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.20)),
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              Icon(icon, size: 20, color: active ? const Color(0xFF7ED69D) : Colors.white),
              if (badge != null)
                Positioned(
                  top: -5, right: -5,
                  child: CircleAvatar(radius: 8, backgroundColor: kBlOrange,
                    child: Text(badge, style: const TextStyle(fontSize: 10, color: Colors.white))),
                ),
            ]),
          ),
        ),
      ),
    );

  Future<void> _openDetail(String id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BaladeLudiqueDetailPage(baladeId: id)));
    _load();
  }
}

class _BaladeCard extends StatelessWidget {
  final Map<String, dynamic> balade;
  final VoidCallback onTap;
  const _BaladeCard({required this.balade, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOfficiel = balade['type_evenement'] != 'communautaire';
    final cover = (balade['cover_url'] as String?) ?? '';
    final difficulte = balade['difficulte']?.toString() ?? 'facile';
    final ville = balade['ville']?.toString() ?? '';
    final espece = balade['espece_cible']?.toString() ?? 'tous';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── Thumbnail ──
          ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
            child: SizedBox(
              width: 88,
              child: cover.isNotEmpty
                  ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
          ),
          // ── Contenu ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (isOfficiel) const Text('🏆 ', style: TextStyle(fontSize: 11)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: blDifficulteColor(difficulte).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(blDifficulteLabel(difficulte),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700, color: blDifficulteColor(difficulte))),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(balade['titre']?.toString() ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 4),
                if (ville.isNotEmpty)
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 3),
                    Text('${blEspeceEmoji(espece)}  $ville',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                const SizedBox(height: 5),
                Wrap(spacing: 5, runSpacing: 4, children: [
                  if (balade['duree_min'] != null)
                    _chip(blDureeLabel(balade['duree_min'] as int?), Colors.grey.shade500),
                  _chip(balade['gratuit'] == true ? 'Gratuit' : '${balade['prix'] ?? ''} €', const Color(0xFF2E7D5E)),
                  if (balade['note_moyenne'] != null)
                    _chip('⭐ ${balade['note_moyenne']}', Colors.amber.shade700),
                ]),
              ]),
            ),
          ),
          // ── Chevron ──
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(child: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300, size: 22)),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF2E7D5E), Color(0xFF7ED69D)]),
    ),
    child: const Center(child: Icon(Icons.route_rounded, color: Colors.white, size: 32)),
  );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
    child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600, color: color)),
  );
}
