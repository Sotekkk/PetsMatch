import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;

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
  bool _showPassees = false;

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

      final clientUids = list.map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      final animalIds  = list.map((r) => r['animal_id']?.toString()).whereType<String>().where((s) => s.isNotEmpty).toSet().toList();

      final results = await Future.wait([
        clientUids.isNotEmpty
            ? _supa.from('user_profiles').select('uid, firstname, lastname, nom').inFilter('uid', clientUids).eq('is_main', true)
            : Future.value(<Map<String, dynamic>>[]),
        animalIds.isNotEmpty
            ? _supa.from('animaux').select('id, nom').inFilter('id', animalIds)
            : Future.value(<Map<String, dynamic>>[]),
      ]);

      final clientNames = <String, String>{};
      for (final c in (results[0] as List)) {
        final nom = (c['nom'] as String?)?.trim();
        final full = nom?.isNotEmpty == true ? nom! : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
        clientNames[c['uid'] as String] = full.isNotEmpty ? full : 'Client';
      }
      final animalNames = <String, String>{
        for (final a in (results[1] as List)) a['id'].toString(): a['nom']?.toString() ?? '',
      };

      for (final r in list) {
        r['_client_nom'] = clientNames[r['client_uid']] ?? 'Client';
        r['_animal_nom'] = animalNames[r['animal_id']?.toString()] ?? '';
      }

      if (mounted) setState(() { _visites = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _openRapport(Map<String, dynamic> rdv) async {
    final noteCtrl = TextEditingController();
    File? photoFile;
    bool posting = false;

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
            Text('Rapport de visite — ${rdv['_animal_nom']}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Comment s\'est passée la visite/promenade…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                  if (file == null) return;
                  setSheetState(() => photoFile = File(file.path));
                },
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(photoFile == null ? 'Ajouter une photo' : 'Photo ajoutée ✓',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: posting ? null : () async {
                  setSheetState(() => posting = true);
                  await _envoyerRapport(rdv, noteCtrl.text.trim(), photoFile);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: posting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Envoyer au propriétaire',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _envoyerRapport(Map<String, dynamic> rdv, String note, File? photoFile) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || (note.isEmpty && photoFile == null)) return;
    try {
      String? photoUrl;
      if (photoFile != null) {
        final path = 'visite_rapports/${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        photoUrl = await storage.uploadPhoto(photoFile, path, quality: 75);
      }
      await _supa.from('pension_updates').insert({
        'animal_id': rdv['animal_id'],
        'pro_uid':   uid,
        'photo_url': photoUrl,
        'note':      note.isEmpty ? null : note,
      });
      final ownerUid = rdv['client_uid']?.toString();
      if (ownerUid != null && ownerUid.isNotEmpty) {
        final proNom = User_Info.nameElevage.isNotEmpty
            ? User_Info.nameElevage
            : '${User_Info.firstname} ${User_Info.lastname}'.trim();
        try {
          await _supa.from('notifications').insert({
            'uid':   ownerUid,
            'type':  'visite_rapport',
            'title': 'Rapport de visite — ${rdv['_animal_nom']}',
            'body':  '${proNom.isNotEmpty ? proNom : 'Votre pet sitter'} a envoyé un rapport pour ${rdv['_animal_nom']}.',
            'data':  <String, dynamic>{
              'animalId': rdv['animal_id']?.toString() ?? '',
              'animalNom': rdv['_animal_nom'],
            },
            'read':  false,
          });
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rapport envoyé au propriétaire.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57),
          behavior: SnackBarBehavior.floating,
        ));
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final aVenir = _visites.where((r) {
      final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '');
      return r['statut'] != 'termine' && (dh == null || dh.isAfter(now));
    }).toList();
    final passees = _visites.where((r) => !aVenir.contains(r)).toList().reversed.toList();
    final displayed = _showPassees ? passees : aVenir;

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
              Expanded(
                child: _TabChip(label: 'À venir (${aVenir.length})', selected: !_showPassees,
                    onTap: () => setState(() => _showPassees = false)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TabChip(label: 'Passées (${passees.length})', selected: _showPassees,
                    onTap: () => setState(() => _showPassees = true)),
              ),
            ]),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : displayed.isEmpty
              ? Center(child: Text(_showPassees ? 'Aucune visite passée' : 'Aucune visite à venir',
                  style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: displayed.length,
                    itemBuilder: (_, i) => _VisiteCard(
                      rdv: displayed[i],
                      onTerminer: () => _marquerTermine(displayed[i]),
                      onRapport: () => _openRapport(displayed[i]),
                    ),
                  ),
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
  static const _teal = Color(0xFF0C5C6C);

  const _VisiteCard({required this.rdv, required this.onTerminer, required this.onRapport});

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
          ]),
        ]),
      ),
    );
  }
}
