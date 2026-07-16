import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Tableau de bord toiletteur — agrégats calculés à la volée : nombre de
/// RDV terminés, CA (factures payées), temps moyen par prestation, nombre
/// de clients fidèles (≥ 3 RDV), note moyenne (avis_pro).
class ToilettageDashboardPage extends StatefulWidget {
  const ToilettageDashboardPage({super.key});

  @override
  State<ToilettageDashboardPage> createState() => _ToilettageDashboardPageState();
}

class _ToilettageDashboardPageState extends State<ToilettageDashboardPage> {
  static const _orange = Color(0xFFFFB74D);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  int _nbRdv = 0;
  double _ca = 0;
  double _dureeMoyenne = 0;
  int _clientsFideles = 0;
  double _noteMoyenne = 0;
  int _nbAvis = 0;

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
      final results = await Future.wait<dynamic>([
        _supa.from('rdv').select('client_uid, duree_minutes')
            .eq('pro_uid', uid).eq('pro_profile_id', pid).eq('statut', 'termine'),
        _supa.from('toilettage_factures').select('montant').eq('pro_uid', uid).eq('pro_profile_id', pid).eq('statut', 'payee'),
        pid.isNotEmpty
            ? _supa.from('user_profiles').select('note_moyenne, nb_avis').eq('id', pid).maybeSingle()
            : Future<Map<String, dynamic>?>.value(null),
      ]);

      final rdvsTermines = results[0] as List;
      final factures = results[1] as List;
      final profil = results[2] as Map<String, dynamic>?;

      final ca = factures.fold<double>(0, (s, f) => s + ((f['montant'] as num?)?.toDouble() ?? 0));

      final durees = rdvsTermines
          .map((r) => (r['duree_minutes'] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      final dureeMoyenne = durees.isEmpty ? 0.0 : durees.reduce((a, b) => a + b) / durees.length;

      final compteParClient = <String, int>{};
      for (final r in rdvsTermines) {
        final clientUid = r['client_uid']?.toString();
        if (clientUid == null || clientUid.isEmpty) {
          continue;
        }
        compteParClient[clientUid] = (compteParClient[clientUid] ?? 0) + 1;
      }
      final clientsFideles = compteParClient.values.where((n) => n >= 3).length;

      if (mounted) setState(() {
        _nbRdv = rdvsTermines.length;
        _ca = ca;
        _dureeMoyenne = dureeMoyenne;
        _clientsFideles = clientsFideles;
        _noteMoyenne = (profil?['note_moyenne'] as num?)?.toDouble() ?? 0;
        _nbAvis = (profil?['nb_avis'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _statCard(String label, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: _orange, size: 22),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        title: const Text('Tableau de bord', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : RefreshIndicator(
              onRefresh: _load,
              color: _orange,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    _statCard('RDV terminés', '$_nbRdv', Icons.content_cut),
                    const SizedBox(width: 12),
                    _statCard('CA encaissé', '${_ca.toStringAsFixed(0)} €', Icons.euro_outlined),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _statCard('Temps moyen', _dureeMoyenne > 0 ? '${_dureeMoyenne.toStringAsFixed(0)} min' : '—', Icons.timer_outlined),
                    const SizedBox(width: 12),
                    _statCard('Clients fidèles', '$_clientsFideles', Icons.favorite_outline),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _statCard('Note moyenne',
                        _nbAvis > 0 ? '${_noteMoyenne.toStringAsFixed(1)} ★ ($_nbAvis)' : '—',
                        Icons.star_outline),
                    const SizedBox(width: 12),
                    const Expanded(child: SizedBox()),
                  ]),
                ],
              ),
            ),
    );
  }
}
