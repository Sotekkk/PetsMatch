import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/education_shared.dart';
import 'package:PetsMatch/pages/pro/education_bibliotheque_page.dart';
import 'package:PetsMatch/pages/pro/education_devis_page.dart';
import 'package:PetsMatch/pages/pro/education_attestation.dart';
import 'package:PetsMatch/pages/pro/education_exercices_pdf.dart';
import 'package:PetsMatch/pages/pro/suivi_partage_sheet.dart';
import 'package:PetsMatch/pages/pro/owner_contact.dart';
import 'package:PetsMatch/widgets/rich_text_view.dart';
import 'package:share_plus/share_plus.dart';

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
  Map<String, dynamic>? _ownerInfo; // firstname/lastname/email/nom
  List<Map<String, dynamic>> _objectifs = [];
  List<Map<String, dynamic>> _exercices = [];
  final Map<String, List<Map<String, dynamic>>> _retours = {};
  List<Map<String, dynamic>> _seances = [];
  List<Map<String, dynamic>> _forfaits = [];
  List<Map<String, dynamic>> _souscrits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  Map<String, dynamic>? get _forfaitActif {
    for (final f in _souscrits) {
      if (f['statut'] == 'actif') return f;
    }
    return null;
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
        _supa.from('forfaits_education').select('id, nom, nb_seances, prix')
            .eq('pro_uid', FirebaseAuth.instance.currentUser?.uid ?? User_Info.uid)
            .eq('actif', true).order('created_at'),
        _supa.from('forfaits_souscrits').select().eq('animal_id', widget.animalId)
            .order('souscrit_le', ascending: false),
      ]);
      final animal = results[2] as Map<String, dynamic>?;
      final ownerUid = animal?['uid_proprietaire']?.toString() ?? animal?['uid_eleveur']?.toString();
      if (ownerUid != null) {
        try {
          _ownerInfo = await _supa.from('user_profiles')
              .select('firstname, lastname, email_contact')
              .eq('uid', ownerUid).eq('is_main', true).maybeSingle();
          if (_ownerInfo?['email_contact'] == null || '${_ownerInfo?['email_contact']}'.isEmpty) {
            final u = await _supa.from('users').select('email').eq('uid', ownerUid).maybeSingle();
            if (u?['email'] != null) {
              _ownerInfo = {...?_ownerInfo, 'email_contact': u!['email']};
            }
          }
        } catch (_) {}
      }
      final exos = List<Map<String, dynamic>>.from(results[3] as List);
      _retours.clear();
      final exoIds = exos.map((e) => e['id']?.toString()).whereType<String>().toList();
      if (exoIds.isNotEmpty) {
        try {
          final rr = await _supa.from('exercices_retours').select()
              .inFilter('attribution_id', exoIds).order('created_at');
          for (final row in (rr as List)) {
            (_retours[row['attribution_id']?.toString() ?? ''] ??= []).add(Map<String, dynamic>.from(row));
          }
          // marquer les retours famille non vus comme vus
          final unseen = [
            for (final list in _retours.values)
              for (final r in list)
                if (r['from_pro'] != true && r['vu_par_pro'] != true) r['id'],
          ];
          if (unseen.isNotEmpty) {
            await _supa.from('exercices_retours').update({'vu_par_pro': true}).inFilter('id', unseen);
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _objectifs = List<Map<String, dynamic>>.from(results[0] as List);
          _seances = List<Map<String, dynamic>>.from(results[1] as List);
          _exercices = exos;
          _forfaits = List<Map<String, dynamic>>.from(results[4] as List);
          _souscrits = List<Map<String, dynamic>>.from(results[5] as List);
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
    final noteOriginal = existing?['note']?.toString() ?? '';
    final notePlain = richTextToPlain(noteOriginal);
    final noteCtrl = TextEditingController(text: notePlain);
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
            DropdownButtonFormField<String?>(
              initialValue: categorie,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Catégorie',
                labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Aucune', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                ..._kCategories.entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                    )),
              ],
              onChanged: (v) => setSheet(() => categorie = v),
            ),
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
              minLines: 3,
              maxLines: 8,
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
    final noteOut = noteCtrl.text.trim() == notePlain.trim() ? noteOriginal : noteCtrl.text.trim();
    final payload = {
      'libelle': libelleCtrl.text.trim(),
      'categorie': categorie,
      'statut': statut,
      'note': noteOut.isEmpty ? null : noteOut,
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
    final motifCtrl = TextEditingController();
    final recoCtrl = TextEditingController();
    final nbCtrl = TextEditingController();
    String? forfaitId;
    bool isBilan = false;
    final fActif = _forfaitActif;
    bool imputer = fActif != null;
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
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Séance', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
                  ButtonSegment(value: true, label: Text('Bilan', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
                ],
                selected: {isBilan},
                onSelectionChanged: (v) => setSheet(() => isBilan = v.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 14),
              if (isBilan) ...[
                TextField(
                  controller: motifCtrl,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Motif de la demande',
                    hintText: 'Ex : aboiements, tirage en laisse, réactivité congénères…',
                    hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: contenuCtrl,
                minLines: 6,
                maxLines: 16,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  labelText: isBilan ? 'Observations' : null,
                  hintText: isBilan
                      ? 'Comportement observé, contexte de vie, relation au maître…'
                      : 'Déroulé de la séance, exercices réalisés, progrès observés…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 4),
              const Text('Mise en forme (gras, couleurs, listes…) disponible sur le site.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 12),
              if (isBilan) ...[
                TextField(
                  controller: recoCtrl,
                  minLines: 3,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Recommandation',
                    hintText: 'Programme conseillé, priorités de travail…',
                    hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: nbCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Nb séances',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: forfaitId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Forfait conseillé',
                        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 11),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Aucun', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
                        ..._forfaits.map((f) => DropdownMenuItem(
                          value: f['id'].toString(),
                          child: Text('${f['nom']} · ${f['nb_seances']}× · ${(f['prix'] as num?)?.toStringAsFixed(0) ?? 0}€',
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        )),
                      ],
                      onChanged: (v) => setSheet(() => forfaitId = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
              ] else ...[
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
                if (fActif != null) ...[
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: imputer,
                    activeColor: _kOrange,
                    onChanged: (v) => setSheet(() => imputer = v ?? false),
                    title: Text(
                      'Imputer sur le forfait « ${fActif['nom_snapshot']} » '
                      '(${((fActif['nb_seances_utilisees'] as num?)?.toInt() ?? 0) + 1}/'
                      '${(fActif['nb_seances_total'] as num?)?.toInt() ?? 1})',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
              ],
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
                child: Text(isBilan ? 'Envoyer le bilan' : 'Envoyer à la famille',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
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
        'type': isBilan ? 'bilan' : 'seance',
        'contenu': isBilan ? contenuCtrl.text.trim() : contenuCtrl.text.trim(),
        if (!isBilan && exercicesCtrl.text.trim().isNotEmpty) 'exercices_conseilles': exercicesCtrl.text.trim(),
        if (isBilan) 'bilan_motif': motifCtrl.text.trim().isEmpty ? null : motifCtrl.text.trim(),
        if (isBilan) 'bilan_observations': contenuCtrl.text.trim(),
        if (isBilan) 'bilan_recommandation': recoCtrl.text.trim().isEmpty ? null : recoCtrl.text.trim(),
        if (isBilan && int.tryParse(nbCtrl.text.trim()) != null) 'bilan_nb_seances_estime': int.parse(nbCtrl.text.trim()),
        if (isBilan && forfaitId != null) 'bilan_forfait_conseille_id': forfaitId,
        if (!isBilan && imputer && fActif != null) 'forfait_souscrit_id': fActif['id'],
      }).select('id').single();
      if (!isBilan && imputer && fActif != null) {
        await _imputerSeance(fActif);
      }
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
      await _notifyOwner(isBilan ? 'education_bilan' : 'education_rapport',
          isBilan ? 'Bilan comportemental — ${widget.animalNom}' : 'Rapport de séance — ${widget.animalNom}',
          '${_proNom.isNotEmpty ? _proNom : 'Votre éducateur'} a envoyé ${isBilan ? 'le bilan' : 'un rapport de séance'}'
          '${joints.isNotEmpty ? ' + ${joints.length} exercice${joints.length > 1 ? 's' : ''}' : ''}.');
      await _load();
      if (mounted && isBilan) {
        _proposerDevis(recoCtrl.text.trim(),
            int.tryParse(nbCtrl.text.trim()),
            forfaitId == null ? null : _forfaits.firstWhere((f) => f['id'].toString() == forfaitId, orElse: () => {}));
      } else if (mounted) {
        _snack('Rapport envoyé à la famille.');
      }
    } catch (e) {
      _snack('Erreur : $e', err: true);
    }
  }

  void _proposerDevis(String reco, int? nb, Map<String, dynamic>? forfait) {
    final hasForfait = forfait != null && forfait.isNotEmpty;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bilan enregistré', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (nb != null || hasForfait)
            Text('Recommandation : ${nb != null ? '$nb séances' : ''}'
                '${hasForfait ? '${nb != null ? ' — ' : ''}forfait « ${forfait['nom']} » (${(forfait['prix'] as num?)?.toStringAsFixed(0) ?? 0} €)' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          const SizedBox(height: 8),
          const Text('Créer le devis correspondant maintenant ?',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Plus tard', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kOrange),
            onPressed: () {
              Navigator.pop(ctx);
              final objs = _objectifs.map((o) => o['libelle']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
              final note = [
                if (reco.isNotEmpty) reco,
                if (objs.isNotEmpty) 'Objectifs de travail : ${objs.join(', ')}.',
              ].join('\n\n');
              final ligne = hasForfait
                  ? {
                      'description': 'Forfait ${forfait['nom']}'
                          '${forfait['nb_seances'] != null ? ' (${forfait['nb_seances']} séances)' : ''}',
                      'quantite': 1,
                      'prix_unitaire': (forfait['prix'] as num?)?.toDouble() ?? 0,
                    }
                  : {
                      'description': 'Programme d\'éducation — ${widget.animalNom}',
                      'quantite': nb ?? 1,
                      'prix_unitaire': 0,
                    };
              Navigator.push(context, MaterialPageRoute(builder: (_) => DevisPage(
                prefill: DevisPrefill(
                  animalId: widget.animalId,
                  clientUid: _ownerUid,
                  clientProfileId: widget.ownerProfileId,
                  clientNom: _ownerInfo?['lastname']?.toString(),
                  clientPrenom: _ownerInfo?['firstname']?.toString(),
                  clientEmail: _ownerInfo?['email_contact']?.toString(),
                  lignes: [ligne],
                  note: note.isEmpty ? null : note,
                ),
              )));
            },
            child: const Text('Créer le devis', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
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
    bool rappels = false;

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
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: rappels,
              activeThumbColor: _kOrange,
              onChanged: (v) => setSheet(() => rappels = v),
              title: const Text('Rappel quotidien à la famille',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Une notif chaque matin tant que l\'exercice n\'est pas fait',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
            ),
            const SizedBox(height: 8),
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
        'rappels_actifs': rappels,
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

  Future<void> _toggleRappel(Map<String, dynamic> ex) async {
    final next = ex['rappels_actifs'] != true;
    setState(() => ex['rappels_actifs'] = next);
    try {
      await _supa.from('exercices_attribues')
          .update({'rappels_actifs': next, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', ex['id']);
    } catch (_) {
      _load();
    }
  }

  static const _kRessenti = {
    'facile': ('😊', 'Facile'), 'moyen': ('😐', 'Moyen'),
    'difficile': ('😓', 'Difficile'), 'bloque': ('🚫', 'Bloqué'),
  };

  Widget _retourBubble(Map<String, dynamic> r) {
    final fromPro = r['from_pro'] == true;
    final ressenti = r['ressenti']?.toString();
    final media = (r['media'] is List) ? (r['media'] as List).whereType<Map>().toList() : const [];
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: fromPro ? const Color(0xFFFFF3E9) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(fromPro ? '🎓 Vous' : '👪 Famille',
              style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700,
                  color: fromPro ? _kOrange : Colors.grey.shade600)),
          if (ressenti != null && _kRessenti[ressenti] != null) ...[
            const SizedBox(width: 6),
            Text('${_kRessenti[ressenti]!.$1} ${_kRessenti[ressenti]!.$2}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade600)),
          ],
        ]),
        if ((r['note']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(r['note'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
        ],
        if (media.isNotEmpty) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal, itemCount: media.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (_, i) {
                final url = media[i]['url']?.toString() ?? '';
                final isVideo = media[i]['type'] == 'video';
                return GestureDetector(
                  onTap: () => isVideo
                      ? launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
                      : showDialog(context: context, builder: (_) => Dialog(
                          backgroundColor: Colors.black,
                          child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url)))),
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                    clipBehavior: Clip.antiAlias,
                    child: isVideo
                        ? const Icon(Icons.play_circle_outline, size: 18, color: Colors.grey)
                        : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _repondreRetour(Map<String, dynamic> ex) async {
    final ctrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          Text('Répondre — ${ex['titre_snapshot'] ?? 'exercice'}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl, maxLines: 3,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Un conseil, un ajustement de l\'exercice…',
              hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13), elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Envoyer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty || !mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      await _supa.from('exercices_retours').insert({
        'attribution_id': ex['id'],
        'author_uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'author_profile_id': User_Info.activeProfileId,
        'note': ctrl.text.trim(),
        'from_pro': true,
        'vu_par_pro': true,
      });
      await _notifyOwner('education_rapport',
          'Message de l\'éducateur — ${widget.animalNom}',
          'À propos de l\'exercice « ${ex['titre_snapshot']} ».');
      await _load();
    } catch (e) {
      _snack('Erreur : $e', err: true);
    }
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
          OwnerContactButton(
            animalId: widget.animalId,
            animalNom: widget.animalNom,
            ownerUid: _ownerUid,
            color: Colors.white,
          ),
          IconButton(
            tooltip: 'Bibliothèque d\'exercices',
            icon: const Icon(Icons.fitness_center_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EducationBibliothequePage())),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'attestation') _genererAttestation();
              if (v == 'pdf_exercices') _envoyerExercicesPdf();
              if (v == 'lien_suivi') _partagerSuiviLien();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf_exercices',
                  child: Text('Envoyer les exercices en PDF', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
              PopupMenuItem(value: 'lien_suivi',
                  child: Text('Partager un lien (famille sans compte)', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
              PopupMenuItem(value: 'attestation',
                  child: Text('Générer l\'attestation de fin', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12),
          tabs: const [Tab(text: 'Objectifs'), Tab(text: 'Exercices'), Tab(text: 'Séances'), Tab(text: 'Forfait')],
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
            2 => _addSeance,
            _ => _enregistrerForfait,
          },
          icon: const Icon(Icons.add),
          label: Text(switch (_tab.index) { 0 => 'Objectif', 1 => 'Attribuer', 2 => 'Séance', _ => 'Forfait' },
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : TabBarView(controller: _tab, children: [_objectifsTab(), _exercicesTab(), _seancesTab(), _forfaitTab()]),
    );
  }

  Widget _forfaitTab() {
    if (_souscrits.isEmpty) {
      return _empty('Aucun forfait',
          'Enregistrez le forfait pris par la famille pour suivre le solde de séances.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _kOrange,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: _souscrits.length,
        itemBuilder: (_, i) {
          final f = _souscrits[i];
          final total = (f['nb_seances_total'] as num?)?.toInt() ?? 1;
          final used = (f['nb_seances_utilisees'] as num?)?.toInt() ?? 0;
          final actif = f['statut'] == 'actif';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: actif ? _kOrange : Colors.grey.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(f['nom_snapshot']?.toString() ?? 'Forfait',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14))),
                _pill(actif ? '$used / $total séances' : 'Terminé',
                    actif ? _kOrange : const Color(0xFF6E9E57)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (used / total).clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(_kOrange),
                ),
              ),
              if (actif) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _cloreForfait(f),
                    child: const Text('Clôturer', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                  ),
                ),
              ],
            ]),
          );
        },
      ),
    );
  }

  Future<void> _enregistrerForfait() async {
    final nomCtrl = TextEditingController();
    final nbCtrl = TextEditingController(text: '5');
    final prixCtrl = TextEditingController();
    String? forfaitId;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const Text('Enregistrer un forfait pris',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            if (_forfaits.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                initialValue: forfaitId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Depuis mes forfaits',
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Saisie libre', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                  ..._forfaits.map((f) => DropdownMenuItem(
                    value: f['id'].toString(),
                    child: Text('${f['nom']} · ${f['nb_seances']}× · ${(f['prix'] as num?)?.toStringAsFixed(0) ?? 0}€',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  )),
                ],
                onChanged: (v) => setSheet(() {
                  forfaitId = v;
                  if (v != null) {
                    final f = _forfaits.firstWhere((x) => x['id'].toString() == v);
                    nomCtrl.text = f['nom']?.toString() ?? '';
                    nbCtrl.text = ((f['nb_seances'] as num?)?.toInt() ?? 5).toString();
                    prixCtrl.text = ((f['prix'] as num?)?.toStringAsFixed(0) ?? '');
                  }
                }),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: nomCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Nom du forfait',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              SizedBox(width: 110, child: TextField(
                controller: nbCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Nb séances',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: prixCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Prix (€)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
              )),
            ]),
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

    if (ok != true || nomCtrl.text.trim().isEmpty || !mounted) return;
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      await _supa.from('forfaits_souscrits').insert({
        if (forfaitId != null) 'forfait_id': forfaitId,
        'pro_uid': proUid,
        if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
        'client_uid': _ownerUid,
        if (widget.ownerProfileId != null) 'client_profile_id': widget.ownerProfileId,
        'animal_id': widget.animalId,
        'nom_snapshot': nomCtrl.text.trim(),
        'nb_seances_total': int.tryParse(nbCtrl.text.trim()) ?? 1,
        if (prixCtrl.text.trim().isNotEmpty) 'prix_snapshot': double.tryParse(prixCtrl.text.trim()),
      });
      await _load();
    } catch (e) {
      _snack('Erreur : $e', err: true);
    }
  }

  Future<void> _genererAttestation() async {
    if (_seances.isEmpty && _objectifs.isEmpty) {
      _snack('Ajoutez au moins une séance ou un objectif d\'abord.', err: true);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Générer l\'attestation ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text(
          'Un PDF récapitulant le programme de ${widget.animalNom} '
          '(${_seances.length} séance${_seances.length > 1 ? 's' : ''}, '
          '${_objectifs.where((o) => o['statut'] == 'acquis').length} objectif(s) atteint(s)) '
          'sera envoyé à la famille.',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kOrange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Générer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    _snack('Génération en cours…');
    final url = await genererAttestationEducation(
      animalId: widget.animalId,
      animalNom: widget.animalNom,
      ownerUid: _ownerUid,
      ownerProfileId: widget.ownerProfileId,
      objectifs: _objectifs,
      seances: _seances,
    );
    if (!mounted) return;
    if (url == null) {
      _snack('Erreur lors de la génération.', err: true);
    } else {
      _snack('Attestation envoyée à la famille.');
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  /// PDF des exercices attribués — utile pour une famille sans compte
  /// PetsMatch : le lien peut ensuite être envoyé par n'importe quel canal
  /// (le sélecteur natif propose WhatsApp/SMS/Email/tout).
  Future<void> _envoyerExercicesPdf() async {
    if (_exercices.isEmpty) {
      _snack('Aucun exercice attribué pour l\'instant.', err: true);
      return;
    }
    _snack('Génération du PDF…');
    final url = await genererExercicesPdf(
      animalId: widget.animalId,
      animalNom: widget.animalNom,
      exercices: _exercices,
    );
    if (!mounted) return;
    if (url == null) {
      _snack('Erreur lors de la génération.', err: true);
      return;
    }
    await Share.share(
      'Programme d\'éducation de ${widget.animalNom} : $url',
      subject: 'Exercices — ${widget.animalNom}',
    );
  }

  Future<void> _partagerSuiviLien() async {
    await showSuiviPartageSheet(context, animalId: widget.animalId, animalNom: widget.animalNom);
  }

  Future<void> _cloreForfait(Map<String, dynamic> f) async {
    try {
      await _supa.from('forfaits_souscrits').update({
        'statut': 'termine', 'termine_le': DateTime.now().toIso8601String(),
      }).eq('id', f['id']);
      await _load();
    } catch (_) {}
  }

  Future<void> _imputerSeance(Map<String, dynamic> f) async {
    final total = (f['nb_seances_total'] as num?)?.toInt() ?? 1;
    final used = ((f['nb_seances_utilisees'] as num?)?.toInt() ?? 0) + 1;
    final termine = used >= total;
    try {
      await _supa.from('forfaits_souscrits').update({
        'nb_seances_utilisees': used,
        if (termine) 'statut': 'termine',
        if (termine) 'termine_le': DateTime.now().toIso8601String(),
      }).eq('id', f['id']);
      if (used == total - 1 || termine) {
        await _notifyOwner('education_forfait_bas',
            'Forfait ${termine ? 'terminé' : 'bientôt terminé'} — ${widget.animalNom}',
            termine
                ? 'Toutes les séances du forfait « ${f['nom_snapshot']} » ont été utilisées.'
                : 'Il reste 1 séance sur le forfait « ${f['nom_snapshot']} ».');
      }
    } catch (_) {}
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
                  icon: Icon(
                    ex['rappels_actifs'] == true ? Icons.notifications_active : Icons.notifications_none,
                    size: 18,
                    color: ex['rappels_actifs'] == true ? _kOrange : Colors.grey,
                  ),
                  tooltip: 'Rappel quotidien',
                  onPressed: () => _toggleRappel(ex),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  onPressed: () => _retirerExercice(ex),
                ),
              ]),
              if ((ex['description_snapshot']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                RichTextView(ex['description_snapshot'].toString(),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ],
              ...(_retours[ex['id']?.toString() ?? ''] ?? const []).map(_retourBubble),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _repondreRetour(ex),
                  icon: const Icon(Icons.reply_outlined, size: 15),
                  label: const Text('Répondre', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: _kOrange, padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
                ),
              ),
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
                RichTextView(o['note'].toString(),
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
          final isBilan = s['type'] == 'bilan';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14),
              border: isBilan ? Border.all(color: _kOrange) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (isBilan) ...[
                  _pill('BILAN', _kOrange),
                  const SizedBox(width: 6),
                ],
                Text(s['date_seance']?.toString() ?? '',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              ]),
              if (isBilan && (s['bilan_motif']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Motif : ${s['bilan_motif']}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 6),
              RichTextView(s['contenu']?.toString() ?? '',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4, color: Color(0xFF1F2A2E))),
              if (isBilan && (s['bilan_recommandation']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFFFF3E9), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('📋 Recommandation',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 11, color: _kOrange)),
                    const SizedBox(height: 2),
                    RichTextView(s['bilan_recommandation'].toString(),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E))),
                    if (s['bilan_nb_seances_estime'] != null)
                      Text('Estimation : ${s['bilan_nb_seances_estime']} séances',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
                  ]),
                ),
              ],
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
