import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ── Contrats de prestation d'éducation ────────────────────────────────────────
// Chaque RDV d'éducation (table `rdv`, pro_uid = éducateur) peut donner lieu à
// un contrat de prestation signé électroniquement. Réutilise `documents_animaux`
// (type='contrat_education', rdv_id) + ContratSignaturePage (carte récap
// générique, pas de PDF dédié — cf. contrat_signature_page.dart).

class EducationContratsPage extends StatefulWidget {
  const EducationContratsPage({super.key});

  @override
  State<EducationContratsPage> createState() => _EducationContratsPageState();
}

class _EducationContratsPageState extends State<EducationContratsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _rdvs = [];
  Map<String, Map<String, dynamic>> _docsParRdv = {}; // rdv_id -> document

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
      var q = _supa.from('rdv').select().eq('pro_uid', uid);
      final pid = User_Info.activeProfileId;
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final rows = await q
          .inFilter('statut', ['confirme', 'termine'])
          .order('date_heure', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);

      final clientUids = list
          .map((r) => r['client_uid'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final animalIds = list
          .map((r) => r['animal_id']?.toString())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      final results = await Future.wait([
        clientUids.isNotEmpty
            ? _supa.from('user_profiles')
                .select('uid, firstname, lastname, nom, email_contact')
                .inFilter('uid', clientUids).eq('is_main', true)
            : Future.value(<Map<String, dynamic>>[]),
        animalIds.isNotEmpty
            ? _supa.from('animaux').select('id, nom').inFilter('id', animalIds)
            : Future.value(<Map<String, dynamic>>[]),
        list.isNotEmpty
            ? _supa.from('documents_animaux')
                .select('rdv_id, token, statut, titre')
                .inFilter('rdv_id', list.map((r) => r['id']).toList())
                .eq('type', 'contrat_education')
            : Future.value(<Map<String, dynamic>>[]),
      ]);

      final clientNames = <String, String>{};
      final clientEmails = <String, String>{};
      for (final c in (results[0] as List)) {
        final nom = (c['nom'] as String?)?.trim();
        final full = nom?.isNotEmpty == true
            ? nom!
            : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
        clientNames[c['uid'] as String] = full.isNotEmpty ? full : 'Client';
        clientEmails[c['uid'] as String] = (c['email_contact'] as String?) ?? '';
      }
      final animalNames = <String, String>{
        for (final a in (results[1] as List)) a['id'].toString(): a['nom']?.toString() ?? '',
      };
      final docs = <String, Map<String, dynamic>>{
        for (final d in (results[2] as List))
          d['rdv_id'].toString(): Map<String, dynamic>.from(d),
      };

      for (final r in list) {
        r['_client_nom'] = clientNames[r['client_uid']] ?? 'Client';
        r['_client_email'] = clientEmails[r['client_uid']] ?? '';
        r['_animal_nom'] = animalNames[r['animal_id']?.toString()] ?? '';
      }

      if (mounted) {
        setState(() {
          _rdvs = list;
          _docsParRdv = docs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ouvrirContrat(Map<String, dynamic> rdv) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final existant = _docsParRdv[rdv['id'].toString()];
      String? token = existant?['token'] as String?;

      if (token == null) {
        final row = await _supa.from('documents_animaux').insert({
          'uid_eleveur': uid,
          'animal_id': rdv['animal_id'],
          'rdv_id': rdv['id'],
          'type': 'contrat_education',
          'titre': 'Contrat de prestation d\'éducation — ${rdv['_animal_nom'] ?? ''}',
          'statut': 'en_attente',
          'metadata': {
            'acquereur_nom': rdv['_client_nom'],
            if ((rdv['_client_email'] ?? '').toString().isNotEmpty)
              'acquereur_email': rdv['_client_email'],
            'date_cession': rdv['date_heure'],
            'prestation': 'Séance d\'éducation canine',
          },
        }).select('token').single();
        token = row['token'] as String?;
      }
      if (token == null || !mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => ContratSignaturePage(token: token!),
      ));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
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
      case 'annule':
      case 'refuse':
        return (label: '🚫 Annulé', color: Colors.red);
      default:
        return (label: 'Aucun contrat', color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mes Contrats',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _rdvs.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 14),
                    const Text('Aucun RDV confirmé',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 15)),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Les contrats de prestation se créent depuis vos rendez-vous d\'éducation confirmés.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _teal,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 18, 14, 90),
                    itemCount: _rdvs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final r = _rdvs[i];
                      final doc = _docsParRdv[r['id'].toString()];
                      final meta = _statutMeta(doc?['statut'] as String?);
                      final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '');
                      final dateStr = dh != null
                          ? DateFormat('EEE d MMM yyyy · HH:mm', 'fr_FR').format(dh)
                          : '';
                      return Container(
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
                                '${r['_animal_nom']?.toString().isNotEmpty == true ? r['_animal_nom'] : 'Animal'} · ${r['_client_nom']}',
                                style: const TextStyle(
                                    fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                    fontSize: 14, color: Color(0xFF1F2A2E)),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: meta.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(meta.label,
                                  style: TextStyle(
                                      fontFamily: 'Galey', fontSize: 10.5,
                                      fontWeight: FontWeight.w700, color: meta.color)),
                            ),
                          ]),
                          if (dateStr.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(dateStr,
                                style: const TextStyle(
                                    fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
                          ],
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: () => _ouvrirContrat(r),
                              icon: Icon(doc == null ? Icons.add : Icons.visibility_outlined, size: 16),
                              label: Text(doc == null ? 'Créer le contrat' : 'Voir le contrat',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: _teal,
                                  side: const BorderSide(color: _teal),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
