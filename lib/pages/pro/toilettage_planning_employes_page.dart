import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Planning par employé (toiletteur, Premium) — vue jour, RDV colorés par
/// employé, filtrable. Pas de glisser-déposer (décision validée : confort
/// d'usage, pas un besoin fonctionnel pour la V1) — réassignation via
/// pro_agenda.dart (modification du RDV).
class ToilettagePlanningEmployesPage extends StatefulWidget {
  const ToilettagePlanningEmployesPage({super.key});

  @override
  State<ToilettagePlanningEmployesPage> createState() => _ToilettagePlanningEmployesPageState();
}

class _ToilettagePlanningEmployesPageState extends State<ToilettagePlanningEmployesPage> {
  static const _orange = Color(0xFFFFB74D);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _employes = [];
  List<Map<String, dynamic>> _rdvs = [];
  Object? _filterEmployeId; // null = tous ; type brut de employes.id (bigint)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final start = DateTime(_date.year, _date.month, _date.day).toUtc();
      final end = DateTime(_date.year, _date.month, _date.day, 23, 59, 59).toUtc();
      final results = await Future.wait([
        pid.isNotEmpty
            ? _supa.from('employes').select('id, prenom, nom, couleur_planning')
                .eq('eleveur_profile_id', pid).eq('actif', true).neq('type', 'benevole')
            : Future.value(<Map<String, dynamic>>[]),
        _supa.from('rdv').select('id, date_heure, duree_minutes, motif, employe_id, client_uid, statut')
            .eq('pro_uid', uid).eq('pro_profile_id', pid)
            .inFilter('statut', ['confirme', 'demande', 'termine'])
            .gte('date_heure', start.toIso8601String()).lte('date_heure', end.toIso8601String())
            .order('date_heure'),
      ]);
      final employes = List<Map<String, dynamic>>.from(results[0] as List);
      final rdvs = List<Map<String, dynamic>>.from(results[1] as List);

      final clientUids = rdvs.map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      if (clientUids.isNotEmpty) {
        final profiles = await _supa.from('user_profiles')
            .select('uid, firstname, lastname, nom').inFilter('uid', clientUids).eq('is_main', true);
        final names = <String, String>{};
        for (final c in profiles as List) {
          final n = (c['nom'] as String?)?.trim();
          final full = n?.isNotEmpty == true ? n! : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
          names[c['uid'] as String] = full.isNotEmpty ? full : 'Client';
        }
        for (final r in rdvs) { r['_client_nom'] = names[r['client_uid']] ?? 'Client'; }
      }

      if (mounted) setState(() { _employes = employes; _rdvs = rdvs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _couleurEmploye(Object? employeId) {
    if (employeId == null) return Colors.grey;
    final e = _employes.firstWhere((e) => e['id'] == employeId, orElse: () => {});
    final hex = e['couleur_planning'] as String? ?? '#FFB74D';
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  String _nomEmploye(Object? employeId) {
    if (employeId == null) return 'Non assigné';
    final e = _employes.firstWhere((e) => e['id'] == employeId, orElse: () => {});
    return '${e['prenom'] ?? ''} ${e['nom'] ?? ''}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _filterEmployeId == null
        ? _rdvs
        : _rdvs.where((r) => r['employe_id'] == _filterEmployeId).toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        title: Text(DateFormat('EEEE d MMMM', 'fr_FR').format(_date), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () { setState(() => _date = _date.subtract(const Duration(days: 1))); _load(); }),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () { setState(() => _date = _date.add(const Duration(days: 1))); _load(); }),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : Column(children: [
              if (_employes.length > 1)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: Colors.white,
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    ChoiceChip(
                      label: const Text('Tous', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                      selected: _filterEmployeId == null,
                      onSelected: (_) => setState(() => _filterEmployeId = null),
                    ),
                    ..._employes.map((e) {
                      final selected = _filterEmployeId == e['id'];
                      final couleur = _couleurEmploye(e['id']);
                      return ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: couleur, radius: 6),
                        label: Text('${e['prenom'] ?? ''}'.trim(), style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        selected: selected,
                        onSelected: (_) => setState(() => _filterEmployeId = e['id']),
                      );
                    }),
                  ]),
                ),
              Expanded(
                child: displayed.isEmpty
                    ? const Center(child: Text('Aucun RDV ce jour.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: displayed.length,
                        itemBuilder: (_, i) {
                          final r = displayed[i];
                          final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal();
                          final heure = dh != null ? DateFormat('HH:mm').format(dh) : '';
                          final couleur = _couleurEmploye(r['employe_id']);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border(left: BorderSide(color: couleur, width: 4)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(children: [
                              Text(heure, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${r['motif'] ?? ''} — ${r['_client_nom'] ?? ''}',
                                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(_nomEmploye(r['employe_id']),
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                              ])),
                              Text('${r['duree_minutes'] ?? 0} min', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                            ]),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}
