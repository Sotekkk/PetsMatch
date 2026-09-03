import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/education_shared.dart';
import 'package:PetsMatch/pages/pro/education_bibliotheque_page.dart';

/// Hub de suivi d'un animal côté éducateur/comportementaliste :
/// onglets « Plan de travail » (objectifs), « Exercices » (attribués à la
/// famille depuis la bibliothèque), « Séances » (comptes rendus).
class EducationSuiviPage extends StatefulWidget {
  final String animalId;
  final String animalNom;
  final String? ownerProfileId;
  final String ownerName;

  const EducationSuiviPage({
    super.key,
    required this.animalId,
    required this.animalNom,
    this.ownerProfileId,
    this.ownerName = 'La famille',
  });

  @override
  State<EducationSuiviPage> createState() => _EducationSuiviPageState();
}

const _kOrange = kEduOrange;
const _kCategories = kEduCategories;
const _kStatuts = kEduObjectifStatuts;
const _kStatutLabels = kEduObjectifStatutLabels;
Color _statutColor(String s) => eduObjectifStatutColor(s);

class _EducationSuiviPageState extends State<EducationSuiviPage>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  late final TabController _tab;

  String? _ownerUid;
  List<Map<String, dynamic>> _objectifs = [];
  List<Map<String, dynamic>> _exercices = [];
  List<Map<String, dynamic>> _seances = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _supa.from('education_objectifs').select().eq('animal_id', widget.animalId)
            .order('ordre').order('created_at'),
        _supa.from('education_progression').select().eq('animal_id', widget.animalId)
            .order('date_seance', ascending: false),
        _supa.from('animaux').select('uid_proprietaire, uid_eleveur')
            .eq('id', widget.animalId).maybeSingle(),
        _supa.from('exercices_attribues').select().eq('animal_id', widget.animalId)
            .order('assigned_at', ascending: false),
      ]);
      final animal = results[2] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _objectifs = List<Map<String, dynamic>>.from(results[0] as List);
          _seances = List<Map<String, dynamic>>.from(results[1] as List);
          _exercices = List<Map<String, dynamic>>.from(results[3] as List);
          _ownerUid = animal?['uid_proprietaire']?.toString() ??
              animal?['uid_eleveur']?.toString();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _proNom => User_Info.nameElevage.isNotEmpty
      ? User_Info.nameElevage
      : '${User_Info.firstname} ${User_Info.lastname}'.trim();

  Future<void> _notifyOwner(String type, String title, String body) async {
    final ownerUid = _ownerUid;
    if (ownerUid == null || ownerUid.isEmpty) return;
    try {
      await _supa.from('notifications').insert({
        'uid': ownerUid,
        'type': type,
        'title': title,
        'body': body,
        if (widget.ownerProfileId != null) 'profile_id': widget.ownerProfileId,
        'data': {
          'animalId': widget.animalId,
          'animalNom': widget.animalNom,
          'url': '/mes-animaux/${widget.animalId}?tab=education',
        },
        'read': false,
      });
    } catch (_) {}
  }

  // ── Objectifs ──────────────────────────────────────────────────────────────

  Future<void> _editObjectif([Map<String, dynamic>? existing]) async {
    final libelleCtrl = TextEditingController(text: existing?['libelle']?.toString() ?? '');
    final noteCtrl = TextEditingController(text: existing?['note']?.toString() ?? '');
    String? categorie = existing?['categorie']?.toString();
    String statut = existing?['statut']?.toString() ?? 'a_travailler';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            Text(existing == null ? 'Nouvel objectif' : 'Modifier l\'objectif',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            TextField(
              controller: libelleCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ex : Revient au rappel en extérieur',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: _kCategories.entries.map((e) {
              final sel = categorie == e.key;
              return ChoiceChip(
                label: Text(e.value, style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                selected: sel,
                onSelected: (_) => setSheet(() => categorie = sel ? null : e.key),
                selectedColor: _kOrange.withValues(alpha: 0.18),
                showCheckmark: false,
              );
            }).toList()),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: _kStatuts.map((s) => ButtonSegment(
                value: s,
                label: Text(_kStatutLabels[s]!, style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
              )).toList(),
              selected: {statut},
              onSelectionChanged: (v) => setSheet(() => statut = v.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Note (facultatif)',
                labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );

    if (saved != true || libelleCtrl.text.trim().isEmpty || !mounted) return;

    final proUid = FirebaseAuth.instance.currentUser?.uid;
    final wasAcquis = existing?['statut'] == 'acquis';
    final now = DateTime.now().toIso8601String();
    final payload = {
      'libelle': libelleCtrl.text.trim(),
      'categorie': categorie,
      'statut': statut,
      'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      'updated_at': now,
      if (statut == 'acquis' && !wasAcquis) 'acquis_le': now,
      if (statut != 'acquis') 'acquis_le': null,
    };

    try {
      if (existing == null) {
        await _supa.from('education_objectifs').insert({
          ...payload,
          'pro_uid': proUid,
          if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
          'animal_id': widget.animalId,
          'owner_uid': _ownerUid,
          if (widget.ownerProfileId != null) 'owner_profile_id': widget.ownerProfileId,
          'ordre': _objectifs.length,
        });
      } else {
        await _supa.from('education_objectifs').update(payload).eq('id', existing['id']);
      }
      if (statut == 'acquis' && !wasAcquis) {
        await _notifyOwner('education_objectif_acquis',
            'Objectif atteint — ${widget.animalNom} 🎉',
            '${_proNom.isNotEmpty ? _proNom : 'Votre éducateur'} a validé « ${libelleCtrl.text.trim()} ».');
      }
      await _load();
    } catch (e) {
      _snack('Erreur : $e', err: true);
    }
  }

  Future<void> _quickStatut(Map<String, dynamic> o, String statut) async {
    final wasAcquis = o['statut'] == 'acquis';
    final now = DateTime.now().toIso8601String();
    setState(() => o['statut'] = statut);
    try {
      await _supa.from('education_objectifs').update({
        'statut': statut,
        'updated_at': now,
        if (statut == 'acquis' && !wasAcquis) 'acquis_le': now,
        if (statut != 'acquis') 'acquis_le': null,
      }).eq('id', o['id']);
      if (statut == 'acquis' && !wasAcquis) {
        await _notifyOwner('education_objectif_acquis',
            'Objectif atteint — ${widget.animalNom} 🎉',
            '${_proNom.isNotEmpty ? _proNom : 'Votre éducateur'} a validé « ${o['libelle']} ».');
      }
    } catch (_) {
      _load();
    }
  }

  Future<void> _deleteObjectif(Map<String, dynamic> o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet objectif ?', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('education_objectifs').delete().eq('id', o['id']);
      await _load();
    } catch (_) {}
  }

  // ── Séance ─────────────────────────────────────────────────────────────────

  Future<void> _addSeance() async {
    final contenuCtrl = TextEditingController();
    final exercicesCtrl = TextEditingController();
    final List<Map<String, dynamic>> joints = [];

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              Text('Compte rendu de séance — ${widget.animalNom}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              TextField(
                controller: contenuCtrl,
                maxLines: 5,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Déroulé de la séance, exercices réalisés, progrès observés…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: exercicesCtrl,
                maxLines: 2,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Exercices conseillés (note rapide)',
                  hintText: 'À faire à la maison d\'ici la prochaine séance…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await Navigator.push<List<Map<String, dynamic>>>(ctx,
                      MaterialPageRoute(builder: (_) => const EducationBibliothequePage(pickMode: true)));
                  if (picked != null) setSheet(() { joints..clear()..addAll(picked); });
                },
                icon: const Icon(Icons.fitness_center_outlined, size: 16),
                label: Text(joints.isEmpty ? 'Joindre des exercices de la bibliothèque'
                    : '${joints.length} exercice${joints.length > 1 ? 's' : ''} joint${joints.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Envoyer à la famille',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              )),
            ]),
          ),
        ),
      ),
    );

    if (ok != true || contenuCtrl.text.trim().isEmpty || !mounted) return;
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    if (proUid == null) return;
    try {
      final inserted = await _supa.from('education_progression').insert({
        'pro_uid': proUid,
        'animal_id': widget.animalId,
        'owner_uid': _ownerUid,
        'date_seance': DateTime.now().toIso8601String().substring(0, 10),
        'contenu': contenuCtrl.text.trim(),
        if (exercicesCtrl.text.trim().isNotEmpty) 'exercices_conseilles': exercicesCtrl.text.trim(),
      }).select('id').single();
      if (joints.isNotEmpty) {
        await _supa.from('exercices_attribues').insert(joints.map((e) => {
          'exercice_id': e['id'],
          'pro_uid': proUid,
          if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
          'animal_id': widget.animalId,
          'owner_uid': _ownerUid,
          if (widget.ownerProfileId != null) 'owner_profile_id': widget.ownerProfileId,
          'progression_id': inserted['id'],
          'titre_snapshot': e['titre'],
          'description_snapshot': e['description'],
          'media_snapshot': e['media'] ?? [],
        }).toList());
      }
      await _notifyOwner('education_rapport',
          'Rapport de séance — ${widget.animalNom}',
          '${_proNom.isNotEmpty ? _proNom : 'Votre éducateur'} a envoyé un rapport de séance'
          '${joints.isNotEmpty ? ' + ${joints.length} exercice${joints.length > 1 ? 's' : ''}' : ''}.');
      if (mounted) _snack('Rapport envoyé à la famille.');
      await _load();
    } catch (e) {
      _snack('Erreur : $e', err: true);
    }
  }

  // ── Exercices attribués ────────────────────────────────────────────────────

  Future<void> _attribuerExercices() async {
    final picked = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(builder: (_) => const EducationBibliothequePage(pickMode: true)),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    final cadenceCtrl = TextEditingController();
    DateTime? echeance;
    String? objectifId;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            Text('Attribuer ${picked.length} exercice${picked.length > 1 ? 's' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            TextField(
              controller: cadenceCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Cadence (facultatif)',
                hintText: 'Ex : 2 fois par jour, 5 min',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx, initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setSheet(() => echeance = d);
              },
              icon: const Icon(Icons.event_outlined, size: 16),
              label: Text(echeance == null ? 'Échéance (facultatif)'
                  : 'Échéance : ${echeance!.day}/${echeance!.month}/${echeance!.year}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            ),
            if (_objectifs.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: objectifId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Rattacher à un objectif (facultatif)',
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Aucun', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                  ..._objectifs.map((o) => DropdownMenuItem(
                    value: o['id'].toString(),
                    child: Text(o['libelle']?.toString() ?? '', overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  )),
                ],
                onChanged: (v) => setSheet(() => objectifId = v),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Envoyer à la famille',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final rows = picked.map((e) => {
        'exercice_id': e['id'],
        'pro_uid': proUid,
        if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
        'animal_id': widget.animalId,
        'owner_uid': _ownerUid,
        if (widget.ownerProfileId != null) 'owner_profile_id': widget.ownerProfileId,
        if (objectifId != null) 'objectif_id': objectifId,
        'titre_snapshot': e['titre'],
        'description_snapshot': e['description'],
        'media_snapshot': e['media'] ?? [],
        if (cadenceCtrl.text.trim().isNotEmpty) 'cadence': cadenceCtrl.text.trim(),
        if (echeance != null) 'echeance': echeance!.toIso8601String().substring(0, 10),
      }).toList();
      await _supa.from('exercices_attribues').insert(rows);
      await _notifyOwner('education_exercice_assigne',
          'Nouveaux exercices — ${widget.animalNom}',
          '${_proNom.isNotEmpty ? _proNom : 'Votre éducateur'} a ajouté ${picked.length} exercice${picked.length > 1 ? 's' : ''} à faire.');
      if (mounted) _snack('Exercices envoyés à la famille.');
      await _load();
    } catch (e) {
      _snack('Erreur : $e', err: true);
    }
  }

  Future<void> _retirerExercice(Map<String, dynamic> ex) async {
    try {
      await _supa.from('exercices_attribues').delete().eq('id', ex['id']);
      await _load();
    } catch (_) {}
  }

  void _snack(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Galey')),
      backgroundColor: err ? Colors.red : const Color(0xFF6E9E57),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _kOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Suivi — ${widget.animalNom}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Bibliothèque d\'exercices',
            icon: const Icon(Icons.fitness_center_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EducationBibliothequePage())),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12),
          tabs: const [Tab(text: 'Objectifs'), Tab(text: 'Exercices'), Tab(text: 'Séances')],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (_, __) => FloatingActionButton.extended(
          backgroundColor: _kOrange,
          foregroundColor: Colors.white,
          onPressed: switch (_tab.index) {
            0 => () => _editObjectif(),
            1 => _attribuerExercices,
            _ => _addSeance,
          },
          icon: const Icon(Icons.add),
          label: Text(switch (_tab.index) { 0 => 'Objectif', 1 => 'Attribuer', _ => 'Séance' },
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : TabBarView(controller: _tab, children: [_objectifsTab(), _exercicesTab(), _seancesTab()]),
    );
  }

  Widget _exercicesTab() {
    if (_exercices.isEmpty) {
      return _empty('Aucun exercice attribué',
          'Attribuez à ${widget.animalNom} des exercices de votre bibliothèque.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kOrange,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: _exercices.length,
        itemBuilder: (_, i) {
          final ex = _exercices[i];
          final media = (ex['media_snapshot'] is List)
              ? (ex['media_snapshot'] as List).whereType<Map>().toList() : const [];
          final statut = ex['statut']?.toString() ?? 'a_faire';
          final done = statut == 'fait';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (media.isNotEmpty)
                  Container(
                    width: 48, height: 48, margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                    clipBehavior: Clip.antiAlias,
                    child: media.first['type'] == 'video'
                        ? const Icon(Icons.play_circle_outline, color: Colors.grey)
                        : CachedNetworkImage(imageUrl: media.first['url']?.toString() ?? '', fit: BoxFit.cover),
                  ),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ex['titre_snapshot']?.toString() ?? '',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 2),
                  Wrap(spacing: 6, children: [
                    _pill(kEduExerciceStatutLabels[statut] ?? statut,
                        done ? const Color(0xFF6E9E57) : Colors.grey.shade500),
                    if ((ex['cadence']?.toString() ?? '').isNotEmpty)
                      _pill(ex['cadence'].toString(), Colors.grey.shade500),
                    if (ex['echeance'] != null)
                      _pill('avant le ${_frDate(ex['echeance'].toString())}', const Color(0xFFD5573B)),
                  ]),
                ])),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () => _retirerExercice(ex),
                ),
              ]),
              if ((ex['description_snapshot']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(ex['description_snapshot'].toString(),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ],
            ]),
          );
        },
      ),
    );
  }

  String _frDate(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
    return m == null ? iso : '${m[3]}/${m[2]}';
  }

  Widget _objectifsTab() {
    if (_objectifs.isEmpty) {
      return _empty('Aucun objectif', 'Ajoutez le premier axe de travail pour ${widget.animalNom}.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kOrange,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: _objectifs.length,
        itemBuilder: (_, i) {
          final o = _objectifs[i];
          final statut = o['statut']?.toString() ?? 'a_travailler';
          final cat = o['categorie']?.toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(
                    color: _statutColor(statut), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(o['libelle']?.toString() ?? '',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14))),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
                  onSelected: (v) {
                    if (v == 'edit') {
                      _editObjectif(o);
                    } else if (v == 'delete') {
                      _deleteObjectif(o);
                    } else {
                      _quickStatut(o, v);
                    }
                  },
                  itemBuilder: (_) => [
                    for (final s in _kStatuts)
                      if (s != statut)
                        PopupMenuItem(value: s, child: Text('→ ${_kStatutLabels[s]}',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'edit', child: Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                    const PopupMenuItem(value: 'delete', child: Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.red))),
                  ],
                ),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: [
                _pill(_kStatutLabels[statut]!, _statutColor(statut)),
                if (cat != null && _kCategories[cat] != null) _pill(_kCategories[cat]!, Colors.grey.shade500),
              ]),
              if ((o['note']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(o['note'].toString(),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ],
            ]),
          );
        },
      ),
    );
  }

  Widget _seancesTab() {
    if (_seances.isEmpty) {
      return _empty('Aucune séance', 'Le compte rendu de la première séance apparaîtra ici.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kOrange,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: _seances.length,
        itemBuilder: (_, i) {
          final s = _seances[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['date_seance']?.toString() ?? '',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 6),
              Text(s['contenu']?.toString() ?? '',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
              if ((s['exercices_conseilles']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('🏋️ Exercices conseillés',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF4A7A32))),
                    const SizedBox(height: 2),
                    Text(s['exercices_conseilles'].toString(),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF4A7A32))),
                  ]),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );

  Widget _empty(String title, String sub) => ListView(children: [
        const SizedBox(height: 90),
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.flag_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey.shade400)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(sub, textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
          ),
        ])),
      ]);
}
