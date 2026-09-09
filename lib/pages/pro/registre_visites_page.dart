import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/pages/pro/visite_rapport_sheet.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ── Registre visites — liste des RDV (visites/promenades) du profil garde,
// avec statut de compte-rendu. Contrairement à la pension (logements avec
// check-in/check-out), le modèle petsitter est événementiel : chaque visite
// est déjà un RDV dans le système agenda générique (table `rdv`).

class RegistreVisitesPage extends StatefulWidget {
  const RegistreVisitesPage({super.key});

  @override
  State<RegistreVisitesPage> createState() => _RegistreVisitesPageState();
}

class _RegistreVisitesPageState extends State<RegistreVisitesPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _visites = [];
  int _tab = 0; // 0 = À venir, 1 = Passées, 2 = Contrats clients
  // client_uid → {nom, email, profile_id, doc_token, doc_statut}
  Map<String, Map<String, dynamic>> _clients = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      var q = _supa.from('rdv').select().eq('pro_uid', uid);
      final pid = User_Info.activeProfileId;
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final rows = await q
          .inFilter('statut', ['confirme', 'termine'])
          .order('date_heure', ascending: true);

      final list = List<Map<String, dynamic>>.from(rows as List);

      // Résolution du client par SON profil (client_profile_id) — jamais
      // uid+is_main, qui renverrait le profil éleveur d'un compte multi-profils.
      final clientProfileIds = list.map((r) => r['client_profile_id']?.toString())
          .whereType<String>().where((s) => s.isNotEmpty).toSet().toList();
      final clientUidsNoPid = list
          .where((r) => (r['client_profile_id']?.toString() ?? '').isEmpty)
          .map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      final animalIds  = list.map((r) => r['animal_id']?.toString()).whereType<String>().where((s) => s.isNotEmpty).toSet().toList();

      final results = await Future.wait([
        clientProfileIds.isNotEmpty
            ? _supa.from('user_profiles').select('id, uid, firstname, lastname, nom, email_contact').inFilter('id', clientProfileIds)
            : Future.value(<Map<String, dynamic>>[]),
        clientUidsNoPid.isNotEmpty
            ? _supa.from('user_profiles').select('id, uid, firstname, lastname, nom, email_contact').inFilter('uid', clientUidsNoPid).eq('is_main', true)
            : Future.value(<Map<String, dynamic>>[]),
        animalIds.isNotEmpty
            ? _supa.from('animaux').select('id, nom').inFilter('id', animalIds)
            : Future.value(<Map<String, dynamic>>[]),
      ]);

      // Contrats de prestation « cadre » du profil garde actif, indexés par client.
      var docsQ = _supa.from('documents_animaux')
          .select('token, statut, metadata')
          .eq('uid_eleveur', uid)
          .eq('type', 'contrat_garde');
      if (pid.isNotEmpty) docsQ = docsQ.eq('pro_profile_id', pid);
      final docs = List<Map<String, dynamic>>.from(await docsQ as List);

      String nomOf(Map<String, dynamic> c) {
        final nom = (c['nom'] as String?)?.trim();
        final full = nom?.isNotEmpty == true ? nom! : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
        return full.isNotEmpty ? full : 'Client';
      }
      final nameByPid = <String, String>{};
      final emailByPid = <String, String>{};
      final nameByUid = <String, String>{};
      final emailByUid = <String, String>{};
      for (final c in (results[0] as List)) {
        nameByPid[c['id'] as String] = nomOf(c);
        emailByPid[c['id'] as String] = (c['email_contact'] as String?) ?? '';
      }
      for (final c in (results[1] as List)) {
        nameByUid[c['uid'] as String] = nomOf(c);
        emailByUid[c['uid'] as String] = (c['email_contact'] as String?) ?? '';
      }
      final animalNames = <String, String>{
        for (final a in (results[2] as List)) a['id'].toString(): a['nom']?.toString() ?? '',
      };

      final docByClient = <String, Map<String, dynamic>>{};
      for (final d in docs) {
        final meta = (d['metadata'] as Map?) ?? {};
        final cu = meta['client_uid']?.toString();
        if (cu != null && cu.isNotEmpty) docByClient[cu] = d;
      }

      String clientName(Map<String, dynamic> r) {
        final cp = r['client_profile_id']?.toString() ?? '';
        if (cp.isNotEmpty && nameByPid[cp] != null) return nameByPid[cp]!;
        return nameByUid[r['client_uid']?.toString() ?? ''] ?? 'Client';
      }
      String clientEmail(Map<String, dynamic> r) {
        final cp = r['client_profile_id']?.toString() ?? '';
        if (cp.isNotEmpty && (emailByPid[cp] ?? '').isNotEmpty) return emailByPid[cp]!;
        return emailByUid[r['client_uid']?.toString() ?? ''] ?? '';
      }

      final clients = <String, Map<String, dynamic>>{};
      for (final r in list) {
        r['_client_nom'] = clientName(r);
        r['_animal_nom'] = animalNames[r['animal_id']?.toString()] ?? '';
        final cu = r['client_uid']?.toString();
        if (cu != null && cu.isNotEmpty && !clients.containsKey(cu)) {
          final doc = docByClient[cu];
          clients[cu] = {
            'nom': clientName(r),
            'email': clientEmail(r),
            'profile_id': r['client_profile_id'],
            'doc_token': doc?['token'],
            'doc_statut': doc?['statut'],
          };
        }
      }

      if (mounted) setState(() { _visites = list; _clients = clients; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Ouvre (ou crée) le contrat de prestation « cadre » d'un client — un seul
  /// par (profil garde, client), réutilisé pour toutes ses gardes. Scopé
  /// `pro_profile_id` + `metadata.client_uid` (aucun mélange de profils).
  Future<void> _openClientContrat(String clientUid, [Map<String, dynamic>? rdv]) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final client = _clients[clientUid];
    if (client == null) return;
    final pid = User_Info.activeProfileId;
    final animalId  = rdv?['animal_id']?.toString();
    final animalNom = (rdv?['_animal_nom'] ?? rdv?['animal_nom'] ?? '').toString();
    try {
      var q = _supa.from('documents_animaux')
          .select('id, token, statut, animal_id, metadata')
          .eq('uid_eleveur', uid)
          .eq('type', 'contrat_garde')
          .eq('metadata->>client_uid', clientUid);
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final existing = await q.maybeSingle();

      String? token = existing?['token'] as String?;
      if (token == null) {
        final row = await _supa.from('documents_animaux').insert({
          'uid_eleveur': uid,
          if (pid.isNotEmpty) 'pro_profile_id': pid,
          'type': 'contrat_garde',
          'titre': 'Contrat de prestation — ${client['nom']}',
          'statut': 'en_attente',
          if (animalId != null && animalId.isNotEmpty) 'animal_id': animalId,
          'metadata': {
            'client_nom': client['nom'],
            'client_uid': clientUid,
            if (client['profile_id'] != null) 'client_profile_id': client['profile_id'],
            if ((client['email'] as String?)?.isNotEmpty == true) 'client_email': client['email'],
            if (animalNom.isNotEmpty) 'animal_nom': animalNom,
            if (animalNom.isNotEmpty) 'animal_noms': [animalNom],
          },
        }).select('token').single();
        token = row['token'] as String?;
      } else if (animalNom.isNotEmpty) {
        // Contrat déjà là : on rattache l'animal courant s'il manque.
        final meta = Map<String, dynamic>.from((existing!['metadata'] as Map?) ?? {});
        final noms = List<String>.from((meta['animal_noms'] as List?) ?? const []);
        final needAnimalId = (existing['animal_id'] == null) && animalId != null && animalId.isNotEmpty;
        if (!noms.contains(animalNom) || needAnimalId) {
          if (!noms.contains(animalNom)) noms.add(animalNom);
          meta['animal_noms'] = noms;
          meta['animal_nom'] ??= animalNom;
          await _supa.from('documents_animaux').update({
            'metadata': meta,
            if (needAnimalId) 'animal_id': animalId,
          }).eq('id', existing['id'] as String);
        }
      }
      if (token == null) return;
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ContratSignaturePage(token: token),
        ));
        await _load();
      }
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

  Future<void> _marquerTermine(Map<String, dynamic> rdv) async {
    try {
      await _supa.from('rdv').update({'statut': 'termine'}).eq('id', rdv['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final aVenir = _visites.where((r) {
      final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '');
      return r['statut'] != 'termine' && (dh == null || dh.isAfter(now));
    }).toList();
    final passees = _visites.where((r) => !aVenir.contains(r)).toList().reversed.toList();
    final clientsList = _clients.entries.toList()
      ..sort((a, b) => (a.value['nom'] as String).compareTo(b.value['nom'] as String));

    Widget content;
    if (_tab == 2) {
      content = clientsList.isEmpty
          ? const _Empty('Aucun client — un RDV confirmé est requis.')
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: clientsList.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
                    child: Text(
                      'Un seul contrat de prestation par client — signé une fois, il couvre toutes ses gardes.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                    ),
                  );
                }
                final e = clientsList[i - 1];
                return _ClientContratCard(
                  nom: e.value['nom'] as String,
                  statut: e.value['doc_statut'] as String?,
                  onTap: () => _openClientContrat(e.key),
                );
              },
            );
    } else {
      final displayed = _tab == 1 ? passees : aVenir;
      content = displayed.isEmpty
          ? _Empty(_tab == 1 ? 'Aucune visite passée' : 'Aucune visite à venir')
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: displayed.length,
              itemBuilder: (_, i) => _VisiteCard(
                rdv: displayed[i],
                onTerminer: () => _marquerTermine(displayed[i]),
                onRapport: () => sendGardeNews(context, displayed[i]),
                onContrat: () {
                  final cu = displayed[i]['client_uid']?.toString();
                  if (cu != null && cu.isNotEmpty) _openClientContrat(cu, displayed[i]);
                },
              ),
            );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Registre visites',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              for (final t in [
                (0, 'À venir (${aVenir.length})'),
                (1, 'Passées (${passees.length})'),
                (2, 'Contrats (${clientsList.length})'),
              ]) ...[
                Expanded(
                  child: _TabChip(label: t.$2, selected: _tab == t.$1,
                      onTap: () => setState(() => _tab = t.$1)),
                ),
                if (t.$1 != 2) const SizedBox(width: 8),
              ],
            ]),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(onRefresh: _load, child: content),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Center(
        child: Text(text, style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)),
      );
}

class _ClientContratCard extends StatelessWidget {
  final String nom;
  final String? statut;
  final VoidCallback onTap;
  static const _teal = Color(0xFF0C5C6C);
  const _ClientContratCard({required this.nom, required this.statut, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (statut) {
      'signe' => ('Signé', const Color(0xFF6E9E57)),
      'partiellement_signe' => ('Partiellement signé', const Color(0xFF3E7CB1)),
      'en_attente' => ('En attente de signature', const Color(0xFFCA8A04)),
      null => ('À générer', Colors.grey),
      _ => (statut!, Colors.grey),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.draw_outlined, color: _teal),
        title: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: color)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF0C5C6C) : Colors.white)),
        ),
      );
}

class _VisiteCard extends StatelessWidget {
  final Map<String, dynamic> rdv;
  final VoidCallback onTerminer;
  final VoidCallback onRapport;
  final VoidCallback onContrat;
  static const _teal = Color(0xFF0C5C6C);

  const _VisiteCard({required this.rdv, required this.onTerminer, required this.onRapport, required this.onContrat});

  @override
  Widget build(BuildContext context) {
    final dh = DateTime.tryParse(rdv['date_heure']?.toString() ?? '');
    final dateStr = dh != null ? DateFormat('EEE d MMM · HH:mm', 'fr_FR').format(dh) : '';
    final isTermine = rdv['statut'] == 'termine';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${rdv['_animal_nom']} — ${rdv['_client_nom']}',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(dateStr, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isTermine ? const Color(0xFFEEF5EA) : const Color(0xFFE8F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(isTermine ? 'Terminée' : 'Confirmée',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                      color: isTermine ? const Color(0xFF6E9E57) : _teal)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            if (!isTermine)
              Expanded(
                child: OutlinedButton(
                  onPressed: onTerminer,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                  child: const Text('Marquer terminée', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                ),
              ),
            if (!isTermine) const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: onRapport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 0,
                ),
                child: const Text('Rapport de visite', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
              ),
            ),
            IconButton(
              onPressed: onContrat,
              tooltip: 'Contrat de prestation',
              icon: const Icon(Icons.draw_outlined, size: 18, color: _teal),
            ),
          ]),
        ]),
      ),
    );
  }
}
