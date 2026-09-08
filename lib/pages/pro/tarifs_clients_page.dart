import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ── Tarifs clients personnalisés — permet de surcharger, pour un client
// donné, le tarif standard (tarifs_garde) d'un type de prestation. Les
// clients éligibles sont dérivés des RDV existants (même source que
// registre_visites_page.dart / cles_clients_page.dart).

// Doit rester identique à _prestationsGarde dans pro_profile_edit.dart
// (constantes privées non partagées entre fichiers, même convention que
// _prestationsEducation).
const prestationsGarde = [
  ('promenade_30min', 'Promenade (30 min)'),
  ('promenade_1h',    'Promenade (1h)'),
  ('promenade_2h',    'Promenade (2h)'),
  ('garde_journee',   'Garde à domicile (journée)'),
  ('autre',           'Autre prestation'),
];

class TarifsClientsPage extends StatefulWidget {
  const TarifsClientsPage({super.key});

  @override
  State<TarifsClientsPage> createState() => _TarifsClientsPageState();
}

class _TarifsClientsPageState extends State<TarifsClientsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  Map<String, int> _tarifsBase = {};
  List<Map<String, dynamic>> _clients = [];
  Map<String, Map<String, num>> _overridesByProfile = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null || pid.isEmpty) { setState(() => _loading = false); return; }
    try {
      final profileRowFuture = _supa.from('user_profiles').select('tarifs_garde').eq('id', pid).maybeSingle();
      final rdvRowsFuture = _supa.from('rdv').select('client_uid, client_profile_id, animal_id')
          .eq('pro_uid', uid).eq('pro_profile_id', pid)
          .inFilter('statut', ['confirme', 'termine'])
          .not('client_profile_id', 'is', null);
      final overrideRowsFuture = _supa.from('tarifs_clients_garde').select().eq('pro_uid', uid).eq('pro_profile_id', pid);

      final profileRow = await profileRowFuture;
      final rdvRowsRaw = await rdvRowsFuture;
      final overrideRowsRaw = await overrideRowsFuture;

      final tarifsBase = <String, int>{};
      if (profileRow?['tarifs_garde'] is Map) {
        for (final e in (profileRow!['tarifs_garde'] as Map).entries) {
          tarifsBase[e.key.toString()] = (e.value as num?)?.toInt() ?? 0;
        }
      }

      final rdvRows = List<Map<String, dynamic>>.from(rdvRowsRaw as List);
      final seenClients = <String, Map<String, dynamic>>{};
      for (final r in rdvRows) {
        final cpid = r['client_profile_id']?.toString();
        if (cpid == null || cpid.isEmpty) continue;
        seenClients[cpid] = {
          'client_profile_id': cpid,
          'client_uid': r['client_uid'],
          'animal_id': r['animal_id'],
        };
      }

      final overrideRows = List<Map<String, dynamic>>.from(overrideRowsRaw as List);
      final overridesByProfile = <String, Map<String, num>>{};
      for (final o in overrideRows) {
        final cpid = o['owner_profile_id']?.toString();
        if (cpid == null) continue;
        overridesByProfile.putIfAbsent(cpid, () => {})[o['prestation_type'] as String] = (o['prix'] as num?) ?? 0;
      }

      final clientProfileIds = seenClients.keys.toList();
      Map<String, String> clientNames = {};
      if (clientProfileIds.isNotEmpty) {
        final profiles = await _supa.from('user_profiles')
            .select('id, firstname, lastname, nom').inFilter('id', clientProfileIds);
        for (final p in List<Map<String, dynamic>>.from(profiles as List)) {
          final nom = (p['nom'] as String?)?.trim();
          final full = nom?.isNotEmpty == true ? nom! : '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          clientNames[p['id'] as String] = full.isNotEmpty ? full : 'Client';
        }
      }

      final clients = seenClients.values.map((c) => {
        ...c,
        'client_nom': clientNames[c['client_profile_id']] ?? 'Client',
      }).toList()
        ..sort((a, b) => (a['client_nom'] as String).compareTo(b['client_nom'] as String));

      if (mounted) {
        setState(() {
          _tarifsBase = tarifsBase;
          _clients = clients;
          _overridesByProfile = overridesByProfile;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Édite la grille tarifaire **standard** (`tarifs_garde`) — celle qui
  /// s'affiche sur la fiche publique. Miroir `users` si profil principal.
  Future<void> _editStandardTarifs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null) return;
    final ctrls = <String, TextEditingController>{
      for (final t in prestationsGarde)
        t.$1: TextEditingController(text: (_tarifsBase[t.$1] ?? 0).toString()),
    };
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const Text('Tarifs standard',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Affichés sur votre fiche publique. Laissez à 0 les prestations non proposées.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ...prestationsGarde.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Text(t.$2,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600))),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: ctrls[t.$1],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: InputDecoration(
                      suffixText: '€',
                      filled: true, fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
                    ),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : () async {
                  setSheetState(() => saving = true);
                  final grille = <String, int>{
                    for (final t in prestationsGarde)
                      t.$1: int.tryParse(ctrls[t.$1]!.text) ?? 0,
                  };
                  try {
                    if (pid.isNotEmpty) {
                      await _supa.from('user_profiles').update({'tarifs_garde': grille}).eq('id', pid);
                    } else {
                      await _supa.from('user_profiles')
                          .update({'tarifs_garde': grille}).eq('uid', uid).eq('is_main', true);
                      await _supa.from('users').update({'tarifs_garde': grille}).eq('uid', uid);
                      await FirebaseFirestore.instance.collection('users').doc(uid)
                          .set({'tarifsGarde': grille}, SetOptions(merge: true));
                    }
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _editClientTarifs(Map<String, dynamic> client) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null || pid.isEmpty) return;
    final cpid = client['client_profile_id'] as String;
    final current = Map<String, num>.from(_overridesByProfile[cpid] ?? {});
    final ctrls = <String, TextEditingController>{
      for (final t in prestationsGarde)
        t.$1: TextEditingController(text: (current[t.$1] ?? _tarifsBase[t.$1] ?? 0).toString()),
    };
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            Text('Tarifs — ${client['client_nom']}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Laissez le tarif standard si aucune remise particulière.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ...prestationsGarde.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('Standard : ${_tarifsBase[t.$1] ?? 0} €',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                ])),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: ctrls[t.$1],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: InputDecoration(
                      suffixText: '€',
                      filled: true, fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
                    ),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : () async {
                  setSheetState(() => saving = true);
                  await _saveOverrides(uid, pid, client, ctrls);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _saveOverrides(String uid, String pid, Map<String, dynamic> client, Map<String, TextEditingController> ctrls) async {
    final cpid = client['client_profile_id'] as String;
    final cuid = client['client_uid']?.toString();
    try {
      for (final t in prestationsGarde) {
        final val = int.tryParse(ctrls[t.$1]!.text) ?? 0;
        final base = _tarifsBase[t.$1] ?? 0;
        if (val == base) {
          await _supa.from('tarifs_clients_garde').delete()
              .eq('pro_profile_id', pid).eq('owner_profile_id', cpid).eq('prestation_type', t.$1);
        } else {
          await _supa.from('tarifs_clients_garde').upsert({
            'pro_uid': uid,
            'pro_profile_id': pid,
            'owner_uid': cuid,
            'owner_profile_id': cpid,
            'prestation_type': t.$1,
            'prix': val,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'pro_profile_id,owner_profile_id,prestation_type');
        }
      }
      await _load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Tarifs clients', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _clients.length + 2,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        final nb = _tarifsBase.values.where((v) => v > 0).length;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            onTap: _editStandardTarifs,
                            leading: const Icon(Icons.sell_outlined, color: _teal),
                            title: const Text('Tarifs standard',
                                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: Text(
                              nb > 0
                                  ? '$nb prestation${nb > 1 ? 's' : ''} tarifée${nb > 1 ? 's' : ''} · visible sur votre fiche'
                                  : 'À renseigner — s\'affiche sur votre fiche publique',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                  color: nb > 0 ? const Color(0xFF6E9E57) : Colors.orange.shade700)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          ),
                        );
                      }
                      if (i == 1) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                          child: Text(
                            _clients.isEmpty
                                ? 'Tarifs par client : disponible dès votre premier RDV confirmé.'
                                : 'Tarifs personnalisés par client',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                        );
                      }
                      final c = _clients[i - 2];
                      final nbOverrides = _overridesByProfile[c['client_profile_id']]?.length ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          onTap: () => _editClientTarifs(c),
                          title: Text(c['client_nom']?.toString() ?? 'Client',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: nbOverrides > 0
                              ? Text('$nbOverrides tarif${nbOverrides > 1 ? 's' : ''} personnalisé${nbOverrides > 1 ? 's' : ''}',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57)))
                              : const Text('Tarifs standards', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
