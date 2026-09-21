import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ── Contrats de prestation maréchalerie ───────────────────────────────────
// Un contrat par RDV (type='contrat_prestation_marechal'), généré depuis la
// carte RDV (pro_agenda.dart → _genererContratMarechal). Cette page ne fait
// que lister/rouvrir ce qui existe déjà — pas de création manuelle ici.

class MarechalContratsPage extends StatefulWidget {
  const MarechalContratsPage({super.key});

  @override
  State<MarechalContratsPage> createState() => _MarechalContratsPageState();
}

class _MarechalContratsPageState extends State<MarechalContratsPage> {
  static const _brown = Color(0xFF8D6E63);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _contrats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final pid = User_Info.activeProfileId;
      var q = _supa.from('documents_animaux').select().eq('uid_eleveur', uid).eq('type', 'contrat_prestation_marechal');
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final rows = await q.order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);

      final animalIds = list
          .map((r) => r['animal_id']?.toString())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      final animalNames = <String, String>{};
      if (animalIds.isNotEmpty) {
        final anims = await _supa.from('animaux').select('id, nom').inFilter('id', animalIds);
        for (final a in (anims as List)) {
          animalNames[a['id'].toString()] = a['nom']?.toString() ?? '';
        }
      }
      for (final r in list) {
        r['_animal_nom'] = animalNames[r['animal_id']?.toString()] ?? '';
      }

      if (mounted) setState(() { _contrats = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  ({String label, Color color}) _statutMeta(String? s) {
    switch (s) {
      case 'signe':
        return (label: '✅ Signé', color: const Color(0xFF2E7D32));
      case 'partiellement_signe':
        return (label: '✍️ Partiel', color: const Color(0xFF1565C0));
      case 'en_attente':
        return (label: '⏳ En attente', color: const Color(0xFFEF6C00));
      case 'refuse':
      case 'annule':
        return (label: '🚫 Refusé', color: Colors.red);
      default:
        return (label: 'Brouillon', color: Colors.grey);
    }
  }

  Future<void> _ouvrir(String token) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ContratSignaturePage(token: token),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _brown,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mes Contrats',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brown))
          : _contrats.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 14),
                    const Text('Aucun contrat',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 15)),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Un contrat se génère depuis un RDV (icône « Contrat de prestation »).',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _brown,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
                    itemCount: _contrats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = _contrats[i];
                      final meta = (c['metadata'] as Map?) ?? {};
                      final sm = _statutMeta(c['statut'] as String?);
                      final dt = DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal();
                      return InkWell(
                        onTap: () => _ouvrir(c['token'] as String),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 6, offset: const Offset(0, 2)),
                            ],
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  (meta['client_nom'] ?? 'Client').toString(),
                                  style: const TextStyle(
                                      fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                      fontSize: 14, color: Color(0xFF1F2A2E)),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: sm.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(sm.label,
                                    style: TextStyle(
                                        fontFamily: 'Galey', fontSize: 10.5,
                                        fontWeight: FontWeight.w700, color: sm.color)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Text([
                              if ((c['_animal_nom'] as String?)?.isNotEmpty == true) 'Animal : ${c['_animal_nom']}',
                              if (dt != null) DateFormat('d MMM yyyy', 'fr_FR').format(dt),
                            ].join(' · '),
                                style: const TextStyle(
                                    fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
