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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: kBlTeal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Balades ludiques',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: 'Classement',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassementPage())),
          ),
          if (uid != null)
            IconButton(
              icon: const Icon(Icons.workspace_premium_outlined),
              tooltip: 'Mes badges',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesBadgesPage())),
            ),
          if (uid != null)
            IconButton(
              icon: const Icon(Icons.list_alt_outlined),
              tooltip: 'Mes parcours',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesParcoursPage())),
            ),
        ],
      ),
      floatingActionButton: uid == null ? null : FloatingActionButton.extended(
        backgroundColor: kBlOrange,
        icon: const Icon(Icons.add),
        label: const Text('Créer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        onPressed: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const CreationFlowPage()));
          if (created == true) _load();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBlTeal))
          : RefreshIndicator(
              onRefresh: _load,
              color: kBlTeal,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _search = v),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Rechercher un parcours, une ville...',
                          hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true, fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _openFiltres,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _activeFilterCount > 0 ? kBlTeal : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Stack(clipBehavior: Clip.none, children: [
                          Icon(Icons.tune, size: 20, color: _activeFilterCount > 0 ? Colors.white : kBlDark),
                          if (_activeFilterCount > 0)
                            Positioned(
                              top: -4, right: -4,
                              child: CircleAvatar(radius: 8, backgroundColor: kBlOrange,
                                  child: Text('$_activeFilterCount', style: const TextStyle(fontSize: 10, color: Colors.white))),
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _mapView = !_mapView),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                        child: Icon(_mapView ? Icons.view_list_outlined : Icons.map_outlined, size: 20, color: kBlDark),
                      ),
                    ),
                  ]),
                ),
                if (_evenementsOfficiels.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [kBlOrange, Color(0xFFEA580C)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(children: [
                        const Text('🏆', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_evenementsOfficiels.length} chasse(s) au trésor officielle(s) en cours !',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ]),
                    ),
                  ),
                Expanded(
                  child: _mapView
                      ? BaladesLudiquesMapView(
                          balades: _filtered,
                          onTap: (b) => _openDetail(b['id'] as String),
                        )
                      : _filtered.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 80),
                              Center(child: Text('Aucun parcours trouvé',
                                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) => _BaladeCard(
                                balade: _filtered[i],
                                onTap: () => _openDetail(_filtered[i]['id'] as String),
                              ),
                            ),
                ),
              ]),
            ),
    );
  }

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: SizedBox(
              width: 96, height: 96,
              child: cover.isNotEmpty
                  ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: const Color(0xFFEEF5EA), child: const Icon(Icons.map_outlined, color: kBlGreen)))
                  : Container(color: const Color(0xFFEEF5EA), child: const Icon(Icons.map_outlined, color: kBlGreen)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (isOfficiel) const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Text('🏆', style: TextStyle(fontSize: 12)),
                  ),
                  Expanded(
                    child: Text(balade['titre']?.toString() ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('${blEspeceEmoji(balade['espece_cible']?.toString() ?? 'tous')}  ${balade['ville'] ?? ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _chip(blDifficulteLabel(balade['difficulte']?.toString() ?? 'facile'), blDifficulteColor(balade['difficulte']?.toString() ?? 'facile')),
                  if (balade['duree_min'] != null) _chip(blDureeLabel(balade['duree_min'] as int?), Colors.grey.shade600),
                  _chip(balade['gratuit'] == true ? 'Gratuit' : '${balade['prix'] ?? ''} €', kBlTeal),
                  if (balade['note_moyenne'] != null) _chip('⭐ ${balade['note_moyenne']}', Colors.amber.shade700),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      );
}
