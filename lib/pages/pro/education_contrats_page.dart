import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ── Contrats de prestation d'éducation ────────────────────────────────────────
// Un contrat par CLIENT + ANIMAL (pas par séance). Réutilise `documents_animaux`
// (type='contrat_education') + ContratSignaturePage / /signer-contrat.
// Les contrats issus d'un devis accepté apparaissent aussi ici (rattachés via
// metadata.devis_id).

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
      var q = _supa.from('documents_animaux').select().eq('uid_eleveur', uid).eq('type', 'contrat_education');
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

  Future<void> _nouveauContrat() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Paires (client, animal) issues des RDV confirmés/terminés, sans contrat existant.
    final pid = User_Info.activeProfileId;
    var rq = _supa.from('rdv').select('animal_id, client_uid, client_profile_id, date_heure').eq('pro_uid', uid);
    if (pid.isNotEmpty) rq = rq.eq('pro_profile_id', pid);
    final rdvRows = await rq.inFilter('statut', ['confirme', 'termine']).order('date_heure', ascending: false);
    final rdvs = List<Map<String, dynamic>>.from(rdvRows as List);

    // Déduplique par (client_uid, animal_id)
    final seen = <String>{};
    final paires = <Map<String, dynamic>>[];
    for (final r in rdvs) {
      final key = '${r['client_uid']}|${r['animal_id']}';
      if (r['client_uid'] == null || !seen.add(key)) continue;
      paires.add(r);
    }
    // Retire les paires déjà couvertes par un contrat (via animal_id présent)
    final animauxAvecContrat = _contrats
        .map((c) => c['animal_id']?.toString())
        .whereType<String>()
        .toSet();
    final candidats = paires.where((p) {
      final aid = p['animal_id']?.toString();
      return aid == null || !animauxAvecContrat.contains(aid);
    }).toList();

    if (candidats.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Aucun nouveau client / animal à contractualiser. '
                'Les contrats se créent depuis vos RDV confirmés.')));
      }
      return;
    }

    final clientUids = candidats.map((p) => p['client_uid'] as String).toSet().toList();
    final animalIds = candidats
        .map((p) => p['animal_id']?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    final res = await Future.wait([
      _supa.from('user_profiles')
          .select('uid, firstname, lastname, nom, email_contact')
          .inFilter('uid', clientUids).eq('is_main', true),
      animalIds.isNotEmpty
          ? _supa.from('animaux').select('id, nom').inFilter('id', animalIds)
          : Future.value(<Map<String, dynamic>>[]),
    ]);
    final clientInfo = <String, Map<String, String>>{};
    for (final c in (res[0] as List)) {
      final nom = (c['nom'] as String?)?.trim();
      final full = nom?.isNotEmpty == true
          ? nom!
          : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
      clientInfo[c['uid'] as String] = {
        'nom': full.isNotEmpty ? full : 'Client',
        'email': (c['email_contact'] as String?) ?? '',
      };
    }
    final animalNames = <String, String>{
      for (final a in (res[1] as List)) a['id'].toString(): a['nom']?.toString() ?? '',
    };

    if (!mounted) return;
    final choix = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nouveau contrat — choisissez le client',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: candidats.map((p) {
                final cu = p['client_uid'] as String;
                final ci = clientInfo[cu] ?? {'nom': 'Client', 'email': ''};
                final an = animalNames[p['animal_id']?.toString()] ?? '';
                return ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE0F2F1),
                      child: Icon(Icons.person_outline, color: _teal, size: 20)),
                  title: Text(ci['nom']!,
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(an.isNotEmpty ? 'Animal : $an' : 'Sans animal spécifié',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, {
                    'client_uid': cu,
                    'client_profile_id': p['client_profile_id'],
                    'animal_id': p['animal_id'],
                    'client_nom': ci['nom'],
                    'client_email': ci['email'],
                  }),
                );
              }).toList(),
            ),
          ),
        ]),
      ),
    );
    if (choix == null) return;

    try {
      final inserted = await _supa.from('documents_animaux').insert({
        'animal_id': choix['animal_id'],
        'uid_eleveur': uid,
        'pro_profile_id': pid.isNotEmpty ? pid : null,
        'type': 'contrat_education',
        'titre': 'Contrat de prestation d\'éducation — ${choix['client_nom']}',
        'statut': 'brouillon',
        'metadata': {
          'acquereur_nom': choix['client_nom'],
          if ((choix['client_email'] ?? '').toString().isNotEmpty)
            'acquereur_email': choix['client_email'],
          'prestation': 'Prestation d\'éducation canine',
        },
      }).select('token').single();
      final token = inserted['token'] as String?;
      if (token != null) await _ouvrir(token);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nouveauContrat,
        backgroundColor: _teal,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau contrat',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
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
                        'Créez un contrat pour un client + son animal, ou envoyez un devis : '
                        'il devient un contrat dès que le client le signe.',
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
                    itemCount: _contrats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = _contrats[i];
                      final meta = (c['metadata'] as Map?) ?? {};
                      final sm = _statutMeta(c['statut'] as String?);
                      final dt = DateTime.tryParse(c['created_at']?.toString() ?? '');
                      final issuDevis = meta['devis_id'] != null;
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
                                  (meta['acquereur_nom'] ?? 'Client').toString(),
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
                              if (issuDevis) 'issu d\'un devis',
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
