import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ── Gestion des clés — traçabilité des clés client détenues par un profil
// garde (petsitter/promeneur). Les clients éligibles sont dérivés des RDV
// existants (même source que registre_visites_page.dart), pas de nouvelle
// notion de "client" à part entière.

class ClesClientsPage extends StatefulWidget {
  const ClesClientsPage({super.key});

  @override
  State<ClesClientsPage> createState() => _ClesClientsPageState();
}

class _ClesClientsPageState extends State<ClesClientsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _cles = [];
  List<Map<String, dynamic>> _clients = [];
  bool _showRendues = false;

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
      final pid = User_Info.activeProfileId;

      var clesQ = _supa.from('cles_clients').select().eq('pro_uid', uid);
      if (pid.isNotEmpty) clesQ = clesQ.eq('pro_profile_id', pid);
      final clesRows = await clesQ.order('created_at', ascending: false);
      final cles = List<Map<String, dynamic>>.from(clesRows as List);

      var rdvQ = _supa.from('rdv').select('client_uid, animal_id').eq('pro_uid', uid);
      if (pid.isNotEmpty) rdvQ = rdvQ.eq('pro_profile_id', pid);
      final rdvRows = await rdvQ
          .inFilter('statut', ['confirme', 'termine'])
          .not('animal_id', 'is', null);

      final seenAnimals = <String, String?>{};
      for (final r in (rdvRows as List)) {
        final aid = r['animal_id']?.toString();
        if (aid != null && aid.isNotEmpty) seenAnimals[aid] = r['client_uid'] as String?;
      }

      final animalIds = {
        ...seenAnimals.keys,
        ...cles.map((c) => c['animal_id']?.toString()).whereType<String>(),
      }.toList();
      final clientUids = {
        ...seenAnimals.values.whereType<String>(),
        ...cles.map((c) => c['owner_uid']?.toString()).whereType<String>(),
      }.toList();

      final results = await Future.wait([
        animalIds.isNotEmpty
            ? _supa.from('animaux').select('id, nom').inFilter('id', animalIds)
            : Future.value(<Map<String, dynamic>>[]),
        clientUids.isNotEmpty
            ? _supa.from('user_profiles').select('uid, firstname, lastname, nom').inFilter('uid', clientUids).eq('is_main', true)
            : Future.value(<Map<String, dynamic>>[]),
      ]);

      final animalNames = <String, String>{
        for (final a in (results[0] as List)) a['id'].toString(): a['nom']?.toString() ?? 'Animal',
      };
      final clientNames = <String, String>{};
      for (final c in (results[1] as List)) {
        final nom = (c['nom'] as String?)?.trim();
        final full = nom?.isNotEmpty == true ? nom! : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
        clientNames[c['uid'] as String] = full.isNotEmpty ? full : 'Client';
      }

      for (final c in cles) {
        final aid = c['animal_id']?.toString();
        c['_animal_nom'] = aid != null ? (animalNames[aid] ?? 'Animal') : 'Animal';
        final ouid = c['owner_uid']?.toString();
        c['_client_nom'] = ouid != null ? (clientNames[ouid] ?? 'Client') : 'Client';
      }

      final clients = seenAnimals.entries.map((e) => {
        'animal_id': e.key,
        'animal_nom': animalNames[e.key] ?? 'Animal',
        'client_uid': e.value,
        'client_nom': e.value != null ? (clientNames[e.value] ?? 'Client') : 'Client',
      }).toList()
        ..sort((a, b) => (a['animal_nom'] as String).compareTo(b['animal_nom'] as String));

      if (mounted) setState(() { _cles = cles; _clients = clients; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrEditCle({Map<String, dynamic>? existing}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    Map<String, dynamic>? selectedClient = existing != null
        ? _clients.firstWhere(
            (c) => c['animal_id'] == existing['animal_id'],
            orElse: () => {'animal_id': existing['animal_id'], 'animal_nom': existing['_animal_nom'], 'client_uid': existing['owner_uid'], 'client_nom': existing['_client_nom']})
        : (_clients.isNotEmpty ? _clients.first : null);
    final descCtrl = TextEditingController(text: existing?['description']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
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
            Text(existing == null ? 'Nouvelle clé' : 'Modifier la clé',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            if (existing == null)
              _clients.isEmpty
                  ? Text('Aucun client disponible — un RDV confirmé est requis avant d\'ajouter une clé.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600))
                  : DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selectedClient,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Client / animal',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.black87),
                      items: _clients.map((c) => DropdownMenuItem(
                        value: c,
                        child: Text('${c['animal_nom']} — ${c['client_nom']}', overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (v) => setSheetState(() => selectedClient = v),
                    )
            else
              Text('${existing['_animal_nom']} — ${existing['_client_nom']}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'Ex : clé sous le paillasson, digicode 1234B…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Notes (facultatif)',
                hintText: 'Consignes particulières…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving || descCtrl.text.trim().isEmpty && descCtrl.text.isEmpty
                    ? null
                    : () async {
                        if (descCtrl.text.trim().isEmpty) return;
                        if (existing == null && selectedClient == null) return;
                        setSheetState(() => saving = true);
                        if (existing == null) {
                          await _createCle(selectedClient!, descCtrl.text.trim(), notesCtrl.text.trim());
                        } else {
                          await _updateCle(existing, descCtrl.text.trim(), notesCtrl.text.trim());
                        }
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
                    : Text(existing == null ? 'Ajouter' : 'Enregistrer',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _createCle(Map<String, dynamic> client, String description, String notes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _supa.from('cles_clients').insert({
        'pro_uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
        'animal_id': client['animal_id'],
        'owner_uid': client['client_uid'],
        'description': description,
        if (notes.isNotEmpty) 'notes': notes,
        'date_recuperation': DateTime.now().toIso8601String().substring(0, 10),
      });
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

  Future<void> _updateCle(Map<String, dynamic> cle, String description, String notes) async {
    try {
      await _supa.from('cles_clients').update({
        'description': description,
        'notes': notes.isEmpty ? null : notes,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', cle['id']);
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

  Future<void> _toggleStatut(Map<String, dynamic> cle) async {
    final rendue = cle['statut'] == 'rendue';
    try {
      await _supa.from('cles_clients').update({
        'statut': rendue ? 'en_possession' : 'rendue',
        if (!rendue) 'date_restitution': DateTime.now().toIso8601String().substring(0, 10),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', cle['id']);
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

  Future<void> _deleteCle(Map<String, dynamic> cle) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer cette clé ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('cles_clients').delete().eq('id', cle['id']);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final enPossession = _cles.where((c) => c['statut'] != 'rendue').toList();
    final rendues = _cles.where((c) => c['statut'] == 'rendue').toList();
    final displayed = _showRendues ? rendues : enPossession;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Gestion des clés', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Expanded(
                child: _TabChip(label: 'En ma possession (${enPossession.length})', selected: !_showRendues,
                    onTap: () => setState(() => _showRendues = false)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TabChip(label: 'Rendues (${rendues.length})', selected: _showRendues,
                    onTap: () => setState(() => _showRendues = true)),
              ),
            ]),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        onPressed: () => _addOrEditCle(),
        icon: const Icon(Icons.vpn_key_outlined, color: Colors.white),
        label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : displayed.isEmpty
              ? Center(child: Text(_showRendues ? 'Aucune clé rendue' : 'Aucune clé en votre possession',
                  style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: displayed.length,
                    itemBuilder: (_, i) => _CleCard(
                      cle: displayed[i],
                      onToggle: () => _toggleStatut(displayed[i]),
                      onEdit: () => _addOrEditCle(existing: displayed[i]),
                      onDelete: () => _deleteCle(displayed[i]),
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

class _CleCard extends StatelessWidget {
  final Map<String, dynamic> cle;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  static const _teal = Color(0xFF0C5C6C);

  const _CleCard({required this.cle, required this.onToggle, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final rendue = cle['statut'] == 'rendue';
    final dateRecup = DateTime.tryParse(cle['date_recuperation']?.toString() ?? '');
    final dateRestit = DateTime.tryParse(cle['date_restitution']?.toString() ?? '');
    final notes = cle['notes']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.vpn_key_outlined, size: 18, color: rendue ? Colors.grey : _teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${cle['_animal_nom']} — ${cle['_client_nom']}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: rendue ? const Color(0xFFEEF5EA) : const Color(0xFFE8F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(rendue ? 'Rendue' : 'En ma possession',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                      color: rendue ? const Color(0xFF6E9E57) : _teal)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(cle['description']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(notes, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 6),
          Text(
            rendue && dateRestit != null
                ? 'Rendue le ${DateFormat('d MMM yyyy', 'fr_FR').format(dateRestit)}'
                : dateRecup != null
                    ? 'Récupérée le ${DateFormat('d MMM yyyy', 'fr_FR').format(dateRecup)}'
                    : '',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onToggle,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                child: Text(rendue ? 'Marquer récupérée' : 'Marquer rendue',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              ),
            ),
            IconButton(onPressed: onEdit, tooltip: 'Modifier', icon: const Icon(Icons.edit_outlined, size: 18, color: _teal)),
            IconButton(onPressed: onDelete, tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red)),
          ]),
        ]),
      ),
    );
  }
}
