import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnnoncesAdmin extends StatefulWidget {
  const AnnoncesAdmin({super.key});

  @override
  State<AnnoncesAdmin> createState() => _AnnoncesAdminState();
}

class _AnnoncesAdminState extends State<AnnoncesAdmin>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  late final TabController _tabs;

  static const _statuts = ['suspectes', 'toutes', 'suspendues'];
  static const _tabLabels = ['Suspectes', 'Toutes', 'Suspendues'];

  final _data = <String, List<Map<String, dynamic>>>{
    'suspectes': [],
    'toutes': [],
    'suspendues': [],
  };
  final _loading = <String, bool>{
    'suspectes': true,
    'toutes': true,
    'suspendues': true,
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _load(_statuts[_tabs.index]);
    });
    _load('suspectes');
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load(String statut) async {
    if (!_loading[statut]! && _data[statut]!.isNotEmpty) return;
    setState(() => _loading[statut] = true);
    try {
      late final List res;
      if (statut == 'suspectes') {
        res = await _supa
            .from('annonces')
            .select('id,titre,espece,race,prix,prix_min_portee,statut,suspect_reasons,uid_eleveur,nom_eleveur,photos,created_at')
            .eq('is_suspect', true)
            .neq('statut', 'suspendu')
            .order('created_at', ascending: false)
            .limit(100);
      } else if (statut == 'suspendues') {
        res = await _supa
            .from('annonces')
            .select('id,titre,espece,race,prix,prix_min_portee,statut,suspect_reasons,uid_eleveur,nom_eleveur,photos,created_at')
            .eq('statut', 'suspendu')
            .order('created_at', ascending: false)
            .limit(100);
      } else {
        res = await _supa
            .from('annonces')
            .select('id,titre,espece,race,prix,prix_min_portee,statut,is_suspect,suspect_reasons,uid_eleveur,nom_eleveur,photos,created_at')
            .order('created_at', ascending: false)
            .limit(200);
      }
      if (mounted) setState(() {
        _data[statut] = List<Map<String, dynamic>>.from(res);
        _loading[statut] = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading[statut] = false);
    }
  }

  Future<void> _clearSuspect(String id, String statut) async {
    await _supa.from('annonces').update({'is_suspect': false, 'suspect_reasons': []}).eq('id', id);
    if (mounted) setState(() => _data[statut]!.removeWhere((a) => a['id'].toString() == id));
    _showSnack('Annonce validée ✓');
  }

  Future<void> _suspend(String id, String statut) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspendre l\'annonce ?', style: TextStyle(fontFamily: 'Galey')),
        content: const Text('L\'annonce ne sera plus visible des utilisateurs.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Suspendre', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('annonces').update({'statut': 'suspendu'}).eq('id', id);
    if (mounted) setState(() => _data[statut]!.removeWhere((a) => a['id'].toString() == id));
    _showSnack('Annonce suspendue');
  }

  Future<void> _restore(String id) async {
    await _supa.from('annonces').update({'statut': 'disponible', 'is_suspect': false, 'suspect_reasons': []}).eq('id', id);
    if (mounted) {
      setState(() => _data['suspendues']!.removeWhere((a) => a['id'].toString() == id));
      _showSnack('Annonce restaurée ✓');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: const Color(0xFF6E9E57)));
  }

  void _openDetail(Map<String, dynamic> ann) {
    final reasons = List<String>.from(ann['suspect_reasons'] ?? []);
    final photo = (List<dynamic>.from(ann['photos'] ?? []).isNotEmpty)
        ? ann['photos'][0] as String? : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8F8F6),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(controller: ctrl, padding: const EdgeInsets.all(20), children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            if (photo != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(photo, height: 180, width: double.infinity,
                    fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
              const SizedBox(height: 12),
            ],
            Text(ann['titre'] ?? '(sans titre)', style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 4),
            Text('${ann['espece'] ?? ''} · ${ann['race'] ?? ''}',
                style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)),
            const SizedBox(height: 4),
            Text('Éleveur : ${ann['nom_eleveur'] ?? ann['uid_eleveur'] ?? ''}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(height: 8),
            if (ann['prix'] != null)
              Text('Prix : ${ann['prix']}€', style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
            if (ann['prix_min_portee'] != null)
              Text('Prix portée : ${ann['prix_min_portee']}€+', style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Raisons du signalement automatique',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  ...reasons.map((r) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const Icon(Icons.warning_amber, size: 15, color: Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_reasonLabel(r),
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 12))),
                    ]),
                  )),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            Row(children: [
              if (ann['statut'] == 'suspendu') ...[
                Expanded(child: ElevatedButton.icon(
                  onPressed: () { Navigator.pop(context); _restore(ann['id'].toString()); },
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Restaurer', style: TextStyle(fontFamily: 'Galey')),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57),
                      foregroundColor: Colors.white, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                )),
              ] else ...[
                Expanded(child: ElevatedButton.icon(
                  onPressed: () { Navigator.pop(context); _clearSuspect(ann['id'].toString(), _statuts[_tabs.index]); },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Valider', style: TextStyle(fontFamily: 'Galey')),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57),
                      foregroundColor: Colors.white, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                )),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  onPressed: () { Navigator.pop(context); _suspend(ann['id'].toString(), _statuts[_tabs.index]); },
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('Suspendre', style: TextStyle(fontFamily: 'Galey')),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                      foregroundColor: Colors.white, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                )),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  String _reasonLabel(String r) => switch (r) {
    'prix_tres_bas'    => 'Prix suspect — trop bas pour l\'espèce',
    'prix_tres_eleve'  => 'Prix suspect — très élevé',
    'prix_portee_bas'  => 'Prix portée suspect — trop bas',
    _ when r.startsWith('mot_suspect:') => 'Mot suspect détecté : ${r.split(':').last}',
    _ => r,
  };

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: const Color(0xFFF8F8F6),
        child: TabBar(
          controller: _tabs,
          labelColor: const Color(0xFF6E9E57),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF6E9E57),
          tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: _statuts.map((statut) {
            if (_loading[statut]!) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)));
            }
            final items = _data[statut]!;
            if (items.isEmpty) {
              return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.campaign_outlined, size: 56, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(statut == 'suspectes' ? 'Aucune annonce suspecte' :
                     statut == 'suspendues' ? 'Aucune annonce suspendue' : 'Aucune annonce',
                    style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)),
              ]));
            }
            return RefreshIndicator(
              onRefresh: () async { setState(() => _loading[statut] = true); await _load(statut); },
              color: const Color(0xFF6E9E57),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (_, i) => _AnnonceCard(
                  ann: items[i],
                  onTap: () => _openDetail(items[i]),
                  onValidate: statut == 'suspendues' ? null : () => _clearSuspect(items[i]['id'].toString(), statut),
                  onSuspend: statut == 'suspendues' ? null : () => _suspend(items[i]['id'].toString(), statut),
                  onRestore: statut == 'suspendues' ? () => _restore(items[i]['id'].toString()) : null,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }
}

class _AnnonceCard extends StatelessWidget {
  final Map<String, dynamic> ann;
  final VoidCallback onTap;
  final VoidCallback? onValidate;
  final VoidCallback? onSuspend;
  final VoidCallback? onRestore;

  const _AnnonceCard({
    required this.ann, required this.onTap,
    this.onValidate, this.onSuspend, this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final photo = (List<dynamic>.from(ann['photos'] ?? []).isNotEmpty)
        ? ann['photos'][0] as String? : null;
    final reasons = List<String>.from(ann['suspect_reasons'] ?? []);
    final isSuspect = ann['is_suspect'] == true;
    final isSuspended = ann['statut'] == 'suspendu';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSuspended ? Colors.red.withOpacity(0.3)
              : isSuspect ? Colors.orange.withOpacity(0.3)
              : Colors.grey.withOpacity(0.15),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(photo, width: 60, height: 60,
                    fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
                    Container(width: 60, height: 60, color: Colors.grey[200],
                        child: const Icon(Icons.pets, color: Colors.grey))),
              )
            else
              Container(width: 60, height: 60, decoration: BoxDecoration(
                color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.pets, color: Colors.grey)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(ann['titre'] ?? '(sans titre)',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (isSuspended)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('Suspendu', style: TextStyle(fontFamily: 'Galey',
                          fontSize: 10, color: Colors.red, fontWeight: FontWeight.w700)))
                else if (isSuspect)
                  const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
              ]),
              const SizedBox(height: 2),
              Text('${ann['espece'] ?? ''} · ${ann['race'] ?? ''}',
                  style: const TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 12)),
              Text(ann['nom_eleveur'] ?? '',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              if (reasons.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(reasons.take(2).map((r) {
                  if (r.startsWith('mot_suspect:')) return 'Mot : ${r.split(':').last}';
                  return switch (r) {
                    'prix_tres_bas' => 'Prix trop bas',
                    'prix_tres_eleve' => 'Prix trop élevé',
                    'prix_portee_bas' => 'Prix portée bas',
                    _ => r,
                  };
                }).join(' · '),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                        color: Colors.orange[700], fontStyle: FontStyle.italic)),
              ],
            ])),
            if (onRestore != null)
              IconButton(
                icon: const Icon(Icons.restore, color: Color(0xFF6E9E57), size: 22),
                onPressed: onRestore,
                tooltip: 'Restaurer',
              )
            else if (onValidate != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, color: Color(0xFF6E9E57), size: 22),
                  onPressed: onValidate,
                  tooltip: 'Valider',
                ),
                IconButton(
                  icon: const Icon(Icons.block, color: Colors.red, size: 22),
                  onPressed: onSuspend,
                  tooltip: 'Suspendre',
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}
