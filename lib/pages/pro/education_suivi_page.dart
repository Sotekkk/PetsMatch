import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/exercices_progression.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/education_shared.dart';
import 'package:PetsMatch/pages/pro/education_bibliotheque_page.dart';
import 'package:PetsMatch/pages/pro/education_devis_page.dart';
import 'package:PetsMatch/pages/pro/education_attestation.dart';
import 'package:PetsMatch/pages/pro/education_exercices_pdf.dart';
import 'package:PetsMatch/pages/pro/suivi_partage_sheet.dart';
import 'package:PetsMatch/widgets/rich_text_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:PetsMatch/widgets/animal/pro_animal_entete.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart' show AnimalFichePage;
import 'package:PetsMatch/utils/document_pro.dart' show showDocumentProSheet;
import 'package:PetsMatch/utils/rdv_animaux.dart' show animauxDetailRdv, choisirAnimalRdv;
import 'package:PetsMatch/utils/fin_seance_education.dart' show devisDepuisRdv, factureDepuisRdv, finSeanceEducation;

/// Fiche éducative (éducateur / comportementaliste) — vue métier unique de
/// l'animal : en-tête commun (identité + propriétaire), onglets Synthèse ·
/// Programme (objectifs, exercices, forfait) · Séances (comptes rendus,
/// brouillon ou finalisé) · Documents. Identité et carnet de santé restent
/// consultables depuis la Synthèse (AnimalFichePage en lecture seule).
class EducationSuiviPage extends StatefulWidget {
  final String animalId;
  final String animalNom;
  final String? ownerProfileId;
  final String ownerName;
  /// Séance (rdv) dont on rédige le compte rendu — ouvre le formulaire pré-rempli.
  final String? rdvId;
  final int initialTab;
  /// Dossier de la séance [rdvId] (miroir site DossierEducationModal) : barre
  /// d'actions (compte rendu, exercices, programme, forfait, devis, facture,
  /// mon compte rendu / contrat, terminer et envoyer) ; on revient ici après
  /// chaque action. Sans dossier, [rdvId] ouvre directement le compte rendu.
  final bool dossier;

  const EducationSuiviPage({
    super.key,
    required this.animalId,
    required this.animalNom,
    this.ownerProfileId,
    this.ownerName = 'La famille',
    this.rdvId,
    this.initialTab = 0,
    this.dossier = false,
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
  /// Prochaine séance confirmée de ce profil pour l'animal.
  Map<String, dynamic>? _prochainRdv;
  /// Motif de l'accompagnement saisi depuis la Synthèse (education_suivis).
  String? _motifSuivi;
  /// Vue de l'onglet Programme : objectifs / exercices / forfait.
  String _programmeVue = 'objectifs';
  bool _rdvTraite = false;
  /// Mode dossier : le RDV de la séance.
  Map<String, dynamic>? _rdvDossier;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));
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
            .order('ordre', ascending: true).order('created_at', ascending: true),
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
          _ownerInfo = await _supa.from('user_profiles_complet')
              .select('firstname, lastname, email_contact')
              .eq('uid', ownerUid).eq('is_main', true).maybeSingle();
          if (_ownerInfo?['email_contact'] == null || '${_ownerInfo?['email_contact']}'.isEmpty) {
            final u = await _supa.from('users_complet').select('email').eq('uid', ownerUid).maybeSingle();
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
      // Prochaine séance (agenda de ce profil, jamais l'uid seul).
      final pid = User_Info.activeProfileId;
      if (pid.isNotEmpty) {
        try {
          final m = await _supa.from('education_suivis').select('motif')
              .eq('pro_profile_id', pid).eq('animal_id', widget.animalId).maybeSingle();
          if (mounted) setState(() => _motifSuivi = m?['motif']?.toString());
        } catch (_) {} // migration_education_suivi_motif.sql pas encore passée
        try {
          final r = await _supa.from('rdv').select()
              .eq('pro_profile_id', pid).eq('animal_id', widget.animalId).eq('statut', 'confirme')
              .gte('date_heure', DateTime.now().toUtc().toIso8601String())
              .order('date_heure').limit(1).maybeSingle();
          if (mounted) setState(() => _prochainRdv = r);
        } catch (_) {}
      }
      // Compte rendu d'une séance précise (depuis le tableau de bord / l'agenda).
      if (widget.dossier && widget.rdvId != null && _rdvDossier == null) {
        try {
          final r = await _supa.from('rdv').select().eq('id', widget.rdvId!).maybeSingle();
          if (mounted) setState(() => _rdvDossier = r);
        } catch (_) {}
      }
      if (widget.rdvId != null && !widget.dossier && !_rdvTraite && mounted) {
        _rdvTraite = true;
        final deja = _seances.where((x) => x['rdv_id']?.toString() == widget.rdvId).firstOrNull;
        Map<String, dynamic>? rdv;
        try {
          rdv = await _supa.from('rdv').select().eq('id', widget.rdvId!).maybeSingle();
        } catch (_) {}
        if (mounted) {
          _tab.animateTo(2);
          await _editSeance(existing: deja, rdv: rdv);
        }
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
    bool prioritaire = existing?['prioritaire'] == true;
    final difficultesCtrl = TextEditingController(text: existing?['difficultes']?.toString() ?? '');

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
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final st in _kStatuts)
                ChoiceChip(
                  label: Text(_kStatutLabels[st]!, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: statut == st ? Colors.white : const Color(0xFF1F2A2E))),
                  selected: statut == st, showCheckmark: false,
                  selectedColor: _statutColor(st), backgroundColor: const Color(0xFFF1F4F3), side: BorderSide.none,
                  onSelected: (_) => setSheet(() => statut = st),
                ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero, dense: true,
              value: prioritaire, activeThumbColor: _kOrange,
              onChanged: (v) => setSheet(() => prioritaire = v),
              title: const Text('Objectif prioritaire', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            ),
            TextField(
              controller: difficultesCtrl,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Difficultés rencontrées (facultatif)',
                labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
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
    // Colonnes de migration_education_fiche.sql (repli sans si pas encore passée).
    final extra = {
      'prioritaire': prioritaire,
      'difficultes': difficultesCtrl.text.trim().isEmpty ? null : difficultesCtrl.text.trim(),
    };

    try {
      Future<void> ecrire(Map<String, dynamic> champs) async {
        if (existing == null) {
          await _supa.from('education_objectifs').insert({
            ...champs,
            'pro_uid': proUid,
            if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
            'animal_id': widget.animalId,
            'owner_uid': _ownerUid,
            if (widget.ownerProfileId != null) 'owner_profile_id': widget.ownerProfileId,
            'ordre': _objectifs.length,
          });
        } else {
          await _supa.from('education_objectifs').update(champs).eq('id', existing['id']);
        }
      }
      try {
        await ecrire({...payload, ...extra});
      } on PostgrestException {
        await ecrire(payload);
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

  /// Compte rendu de séance (ou bilan) : rapide ou détaillé, brouillon ou
  /// finalisé (seul le finalisé est envoyé à la famille). [existing] reprend
  /// un brouillon, [rdv] pré-remplit depuis la séance de l'agenda.
  Future<void> _editSeance({Map<String, dynamic>? existing, Map<String, dynamic>? rdv}) async {
    String typeSeance = existing?['type_seance']?.toString() ??
        (existing?['type'] == 'bilan' ? 'bilan' : null) ??
        ((rdv?['lieu']?.toString().trim() ?? '').isNotEmpty ? 'domicile' : 'individuelle');
    final contenuCtrl = TextEditingController(text: richTextToPlain(existing?['contenu']?.toString() ?? ''));
    final exercicesCtrl = TextEditingController(text: existing?['exercices_conseilles']?.toString() ?? '');
    final motifCtrl = TextEditingController(text: existing?['bilan_motif']?.toString() ?? rdv?['motif']?.toString() ?? '');
    final recoCtrl = TextEditingController(text: richTextToPlain(existing?['bilan_recommandation']?.toString() ?? ''));
    final nbCtrl = TextEditingController(text: existing?['bilan_nb_seances_estime']?.toString() ?? '');
    final lieuCtrl = TextEditingController(text: existing?['lieu']?.toString() ?? rdv?['lieu']?.toString() ?? '');
    final dureeCtrl = TextEditingController(
        text: (existing?['duree_minutes'] ?? rdv?['duree_minutes'])?.toString() ?? '');
    final comportementsCtrl = TextEditingController(text: existing?['comportements']?.toString() ?? '');
    final difficultesCtrl = TextEditingController(text: existing?['difficultes']?.toString() ?? '');
    final prochaineCtrl = TextEditingController(text: existing?['prochaine_etape']?.toString() ?? '');
    final travailles = <String>{
      for (final x in (existing?['objectifs_travailles'] as List? ?? const [])) x.toString(),
    };
    String? forfaitId = existing?['bilan_forfait_conseille_id']?.toString();
    bool detaille = existing != null &&
        ((existing['comportements'] ?? existing['difficultes'] ?? existing['prochaine_etape']) != null);
    final fActif = _forfaitActif;
    bool imputer = fActif != null && existing == null;
    final List<Map<String, dynamic>> joints = [];
    final dateSeance = (existing?['date_seance']?.toString()) ??
        (DateTime.tryParse(rdv?['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime.now())
            .toIso8601String().substring(0, 10);

    InputDecoration deco(String label, [String? hint]) => InputDecoration(
          labelText: label, hintText: hint,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
          hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.all(12),
        );
    Widget champ(TextEditingController c, String label, {String? hint, int min = 1, int max = 4}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: c, minLines: min, maxLines: max,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14), decoration: deco(label, hint)),
        );

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final isBilan = typeSeance == 'bilan';
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                Text(existing != null ? 'Compléter le compte rendu' : 'Nouvelle séance — ${widget.animalNom}',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in kEduTypesSeance.entries)
                    ChoiceChip(
                      label: Text(t.value, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: typeSeance == t.key ? Colors.white : const Color(0xFF1F2A2E))),
                      selected: typeSeance == t.key, showCheckmark: false,
                      selectedColor: _kOrange, backgroundColor: const Color(0xFFF1F4F3), side: BorderSide.none,
                      onSelected: (_) => setSheet(() => typeSeance = t.key),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(flex: 3, child: TextField(controller: lieuCtrl,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14), decoration: deco('Lieu', 'Domicile, parc, terrain…'))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: TextField(controller: dureeCtrl, keyboardType: TextInputType.number,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14), decoration: deco('Durée (min)'))),
                ]),
                const SizedBox(height: 10),
                if (isBilan) champ(motifCtrl, 'Motif de la demande', hint: 'Ex : aboiements, tirage en laisse, réactivité…'),
                if (_objectifs.isNotEmpty) ...[
                  const Text('Objectifs travaillés', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final o in _objectifs)
                      FilterChip(
                        label: Text(o['libelle']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        selected: travailles.contains(o['id'].toString()),
                        selectedColor: _kOrange.withValues(alpha: 0.18), checkmarkColor: _kOrange,
                        onSelected: (v) => setSheet(() => v ? travailles.add(o['id'].toString()) : travailles.remove(o['id'].toString())),
                      ),
                  ]),
                  const SizedBox(height: 10),
                ],
                champ(contenuCtrl, isBilan ? 'Observations' : 'Déroulement de la séance',
                    hint: isBilan ? 'Comportement observé, contexte de vie, relation au maître…'
                        : 'Exercices réalisés, progrès constatés…', min: 4, max: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero, dense: true,
                  value: detaille, activeThumbColor: _kOrange,
                  onChanged: (v) => setSheet(() => detaille = v),
                  title: const Text('Compte rendu détaillé', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ),
                if (detaille) ...[
                  champ(comportementsCtrl, 'Comportements observés'),
                  champ(difficultesCtrl, 'Difficultés'),
                  champ(prochaineCtrl, 'Prochaine étape'),
                ],
                if (isBilan) ...[
                  champ(recoCtrl, 'Recommandation', hint: 'Programme conseillé, priorités de travail…', min: 3, max: 8),
                  Row(children: [
                    SizedBox(width: 110, child: TextField(controller: nbCtrl, keyboardType: TextInputType.number,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14), decoration: deco('Nb séances'))),
                    const SizedBox(width: 10),
                    Expanded(child: DropdownButtonFormField<String?>(
                      initialValue: forfaitId,
                      isExpanded: true,
                      decoration: deco('Forfait conseillé'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Aucun', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
                        ..._forfaits.map((f) => DropdownMenuItem(
                          value: f['id'].toString(),
                          child: Text('${f['nom']} · ${f['nb_seances']}× · ${(f['prix'] as num?)?.toStringAsFixed(0) ?? 0}€',
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        )),
                      ],
                      onChanged: (v) => setSheet(() => forfaitId = v),
                    )),
                  ]),
                  const SizedBox(height: 10),
                ] else ...[
                  champ(exercicesCtrl, 'Recommandations / travail avant la prochaine séance',
                      hint: 'À faire à la maison d\'ici la prochaine séance…'),
                  if (fActif != null && existing == null)
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
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, 'brouillon'),
                    style: OutlinedButton.styleFrom(foregroundColor: _kOrange, side: const BorderSide(color: _kOrange),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Brouillon', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                  )),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, 'finalise'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kOrange, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13), elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(isBilan ? 'Finaliser et envoyer le bilan' : 'Finaliser et envoyer',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                  )),
                ]),
              ]),
            ),
          );
        },
      ),
    );

    if (action == null || contenuCtrl.text.trim().isEmpty || !mounted) return;
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    if (proUid == null) return;
    final isBilan = typeSeance == 'bilan';
    final finalise = action == 'finalise';
    final etaitFinalise = existing?['statut'] != 'brouillon' && existing != null;
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final base = <String, dynamic>{
      'pro_uid': proUid,
      'animal_id': widget.animalId,
      'owner_uid': _ownerUid,
      'date_seance': dateSeance,
      'type': isBilan ? 'bilan' : 'seance',
      'contenu': contenuCtrl.text.trim(),
      'exercices_conseilles': isBilan ? null : t(exercicesCtrl),
      'bilan_motif': isBilan ? t(motifCtrl) : null,
      'bilan_observations': isBilan ? contenuCtrl.text.trim() : null,
      'bilan_recommandation': isBilan ? t(recoCtrl) : null,
      'bilan_nb_seances_estime': isBilan ? int.tryParse(nbCtrl.text.trim()) : null,
      'bilan_forfait_conseille_id': isBilan ? forfaitId : null,
      if (!isBilan && imputer && fActif != null) 'forfait_souscrit_id': fActif['id'],
    };
    // migration_education_fiche.sql (repli sur le format d'origine si absente).
    final extra = <String, dynamic>{
      'statut': finalise ? 'finalise' : 'brouillon',
      if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
      if ((rdv?['id'] ?? existing?['rdv_id']) != null) 'rdv_id': rdv?['id'] ?? existing?['rdv_id'],
      'type_seance': typeSeance,
      'lieu': t(lieuCtrl),
      'duree_minutes': int.tryParse(dureeCtrl.text.trim()),
      'objectifs_travailles': travailles.toList(),
      'comportements': detaille ? t(comportementsCtrl) : null,
      'difficultes': detaille ? t(difficultesCtrl) : null,
      'prochaine_etape': detaille ? t(prochaineCtrl) : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      Future<String> ecrire(Map<String, dynamic> champs) async {
        if (existing != null) {
          await _supa.from('education_progression').update(champs).eq('id', existing['id']);
          return existing['id'].toString();
        }
        final r = await _supa.from('education_progression').insert(champs).select('id').single();
        return r['id'].toString();
      }
      String id;
      try {
        id = await ecrire({...base, ...extra});
      } on PostgrestException {
        if (!finalise) {
          _snack('Brouillon indisponible : migration_education_fiche.sql à passer.', err: true);
          return;
        }
        id = await ecrire(base);
      }
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
          'progression_id': id,
          'titre_snapshot': e['titre'],
          'description_snapshot': e['description'],
          'media_snapshot': e['media'] ?? [],
        }).toList());
      }
      // Seul un compte rendu finalisé est partagé avec la famille.
      if (finalise && !etaitFinalise) {
        await _notifyOwner(isBilan ? 'education_bilan' : 'education_rapport',
            isBilan ? 'Bilan comportemental — ${widget.animalNom}' : 'Rapport de séance — ${widget.animalNom}',
            '${_proNom.isNotEmpty ? _proNom : 'Votre éducateur'} a envoyé ${isBilan ? 'le bilan' : 'un rapport de séance'}'
            '${joints.isNotEmpty ? ' + ${joints.length} exercice${joints.length > 1 ? 's' : ''}' : ''}.');
      }
      await _load();
      if (mounted && isBilan && finalise) {
        _proposerDevis(recoCtrl.text.trim(),
            int.tryParse(nbCtrl.text.trim()),
            forfaitId == null ? null : _forfaits.firstWhere((f) => f['id'].toString() == forfaitId, orElse: () => {}));
      } else if (mounted) {
        _snack(finalise ? 'Compte rendu envoyé à la famille.' : 'Brouillon enregistré.');
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
    // Durée : 2 semaines par défaut ; null = jusqu'à validation.
    DateTime? echeance = DateTime.now().add(const Duration(days: kDureeDefautJours));
    int? dureeJours = kDureeDefautJours;
    // Réussites à obtenir (exercices sans étapes).
    int nbValidations = 1;
    final sansEtapes = picked.where((e) => ((e['etapes'] as List?) ?? const []).isEmpty).length;
    final avecEtapes = picked.length - sansEtapes;
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
            const SizedBox(height: 12),
            const Text('Durée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in kDureesExercice)
                ChoiceChip(
                  label: Text(d.$1, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                  selected: dureeJours == d.$2 && (d.$2 != null || echeance == null),
                  selectedColor: _kOrange.withValues(alpha: 0.18),
                  onSelected: (_) => setSheet(() {
                    dureeJours = d.$2;
                    echeance = d.$2 == null ? null : DateTime.now().add(Duration(days: d.$2!));
                  }),
                ),
              ActionChip(
                avatar: const Icon(Icons.event_outlined, size: 16),
                label: Text(dureeJours == -1 && echeance != null
                    ? "Jusqu'au ${echeance!.day}/${echeance!.month}"
                    : 'Date…', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx, initialDate: echeance ?? DateTime.now().add(const Duration(days: 14)),
                    firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setSheet(() { echeance = d; dureeJours = -1; });
                },
              ),
            ]),
            Text(echeance == null
                ? 'Rappels jusqu\'à ce que la famille valide l\'exercice.'
                : 'Rappels jusqu\'au ${echeance!.day}/${echeance!.month}/${echeance!.year} ou jusqu\'à validation.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
            if (sansEtapes > 0) ...[
              const SizedBox(height: 12),
              Text(avecEtapes > 0 ? 'Réussites à obtenir (exercices sans étapes)' : 'Réussites à obtenir',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final n in const [1, 2, 3, 5, 7])
                  ChoiceChip(
                    label: Text(n == 1 ? '1 (une fois)' : '$n jours', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                    selected: nbValidations == n,
                    selectedColor: _kOrange.withValues(alpha: 0.18),
                    onSelected: (_) => setSheet(() => nbValidations = n),
                  ),
              ]),
              Text('La famille valide une réussite par jour ; l\'exercice est terminé au total atteint.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
            ],
            if (avecEtapes > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${avecEtapes == 1 && picked.length == 1 ? 'Cet exercice a' : '$avecEtapes exercice${avecEtapes > 1 ? 's ont' : ' a'}'} des étapes : la famille les valide une à une.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
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
              subtitle: Text('Une notif chaque matin tant que l\'exercice n\'est pas terminé, pendant la durée choisie',
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
        'echeance': echeance?.toIso8601String().substring(0, 10),
        'etapes_snapshot': e['etapes'] ?? [],
        'nb_validations': ((e['etapes'] as List?) ?? const []).isEmpty ? nbValidations : 1,
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
          .update({'rappels_actifs': next, 'updated_at': DateTime.now().toUtc().toIso8601String()})
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
          tabs: const [Tab(text: 'Synthèse'), Tab(text: 'Programme'), Tab(text: 'Séances'), Tab(text: 'Documents')],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (_, __) {
          if (_tab.index == 3) return const SizedBox.shrink();
          final prog = _tab.index == 1;
          return FloatingActionButton.extended(
            backgroundColor: _kOrange,
            foregroundColor: Colors.white,
            onPressed: prog
                ? switch (_programmeVue) {
                    'exercices' => _attribuerExercices,
                    'forfait' => _enregistrerForfait,
                    _ => () => _editObjectif(),
                  }
                : () => _editSeance(),
            icon: const Icon(Icons.add),
            label: Text(prog
                ? switch (_programmeVue) { 'exercices' => 'Attribuer', 'forfait' => 'Forfait', _ => 'Objectif' }
                : 'Nouvelle séance',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          );
        },
      ),
      body: Column(children: [
        // En-tête commun : identité + propriétaire (appeler, message, urgence).
        ProAnimalEntete(animalId: widget.animalId, catPro: 'education', statut: _statutSuivi),
        if (_rdvDossier != null) _barreDossier(_rdvDossier!),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kOrange))
            : TabBarView(controller: _tab, children: [_syntheseTab(), _programmeTab(), _seancesTab(), _documentsTab()])),
      ]),
    );
  }

  /// Dossier de la séance : chaque action revient sur cet écran (rechargé).
  Widget _barreDossier(Map<String, dynamic> rdv) {
    final d = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
    final crRdv = _seances.where((x) => x['rdv_id']?.toString() == rdv['id'].toString()).firstOrNull;
    final proNom = _proNom;
    Future<void> puis(Future<void> Function() action) async { await action(); if (mounted) await _load(); }
    Widget chip(IconData icone, String label, Future<void> Function() action) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ActionChip(
            avatar: Icon(icone, size: 16, color: const Color(0xFF0C5C6C)),
            label: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600)),
            backgroundColor: Colors.white, side: const BorderSide(color: Color(0xFFE0E4E2)),
            onPressed: () => puis(action),
          ),
        );
    return Container(
      width: double.infinity,
      color: const Color(0xFFF1F6F7),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Séance${d == null ? '' : ' du ${_dateFr(rdv['date_heure']?.toString())} à ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}'}'
            '${animauxDetailRdv(rdv).isNotEmpty ? ' · ${widget.animalNom}' : ''}'
            '${crRdv == null ? ' · compte rendu à rédiger' : crRdv['statut'] == 'brouillon' ? ' · compte rendu en brouillon' : ' · compte rendu rédigé'}',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 6),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          // Plusieurs animaux (comme véto / ostéo) : un compte rendu par animal.
          if (animauxDetailRdv(rdv).isNotEmpty)
            chip(Icons.pets_outlined, 'Autre animal', () async {
              final a = await choisirAnimalRdv(context, rdv, table: 'education_progression',
                  color: const Color(0xFF0C5C6C), titre: 'Dossier de quel animal ?');
              if (a == null || !mounted || a['id'] == widget.animalId) return;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EducationSuiviPage(
                animalId: a['id'].toString(), animalNom: a['nom']?.toString() ?? 'Animal',
                ownerProfileId: widget.ownerProfileId, ownerName: widget.ownerName,
                rdvId: widget.rdvId, dossier: true)));
            }),
          chip(Icons.edit_note_outlined, crRdv == null ? 'Compte rendu' : 'Modifier le compte rendu', () async {
            _tab.animateTo(2);
            await _editSeance(existing: crRdv, rdv: rdv);
          }),
          chip(Icons.fitness_center_outlined, 'Exercices', () async { _tab.animateTo(1); await _attribuerExercices(); }),
          chip(Icons.track_changes_outlined, 'Programme', () async { _tab.animateTo(1); await _editObjectif(); }),
          chip(Icons.confirmation_number_outlined, 'Forfait', () async { _tab.animateTo(1); await _enregistrerForfait(); }),
          chip(Icons.request_quote_outlined, 'Devis', () => devisDepuisRdv(context, rdv, animalNom: widget.animalNom)),
          chip(Icons.receipt_long_outlined, 'Facture', () => factureDepuisRdv(context, rdv, animalNom: widget.animalNom)),
          chip(Icons.upload_file_outlined, 'Mon compte rendu', () async {
            await showDocumentProSheet(context, rdv: rdv, mode: 'compte_rendu', clientNom: widget.ownerName,
                animalNom: widget.animalNom, proNom: proNom, catPro: 'education');
          }),
          chip(Icons.draw_outlined, 'Mon contrat', () async {
            await showDocumentProSheet(context, rdv: rdv, mode: 'contrat', clientNom: widget.ownerName,
                animalNom: widget.animalNom, proNom: proNom, catPro: 'education');
          }),
        ])),
        const SizedBox(height: 6),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () => puis(() => finSeanceEducation(context, rdv, animalNom: widget.animalNom, clientNom: widget.ownerName)),
          icon: const Icon(Icons.send_outlined, size: 18),
          label: const Text('Terminer et envoyer au client', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0C5C6C), foregroundColor: Colors.white),
        )),
      ]),
    );
  }

  /// Statut métier affiché dans l'en-tête.
  String? get _statutSuivi {
    if (_forfaitActif != null || _objectifs.any((o) => o['statut'] != 'acquis')) return 'Suivi actif';
    return _seances.isEmpty ? null : 'Suivi terminé';
  }

  String _dateFr(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _carte({required String titre, IconData? icone, required Widget child, Widget? action}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E8E6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icone != null) ...[Icon(icone, size: 17, color: const Color(0xFF0C5C6C)), const SizedBox(width: 8)],
            Expanded(child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E)))),
            if (action != null) action,
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _texteDiscret(String t) =>
      Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600));

  // ── Synthèse ───────────────────────────────────────────────────────────────

  Widget _syntheseTab() {
    final bilans = _seances.where((x) => x['type'] == 'bilan').toList();
    final motifBilan = bilans.map((b) => b['bilan_motif']?.toString() ?? '').firstWhere((m) => m.isNotEmpty, orElse: () => '');
    final motif = (_motifSuivi ?? '').trim().isNotEmpty ? _motifSuivi!.trim() : motifBilan;
    final finalisees = _seances.where((x) => x['statut'] != 'brouillon').toList();
    final derniere = finalisees.isEmpty ? null : finalisees.first;
    final prioritaires = [
      ..._objectifs.where((o) => o['prioritaire'] == true && o['statut'] != 'acquis'),
      ..._objectifs.where((o) => o['prioritaire'] != true && o['statut'] != 'acquis'),
    ].take(3).toList();
    final reco = (bilans.isNotEmpty ? richTextToPlain(bilans.first['bilan_recommandation']?.toString() ?? '') : '').trim();
    final travail = (derniere?['exercices_conseilles']?.toString() ?? '').trim();
    final f = _forfaitActif;
    final brouillons = _seances.where((x) => x['statut'] == 'brouillon').length;
    final prochain = _prochainRdv;
    return RefreshIndicator(
      onRefresh: _load,
      color: _kOrange,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        if (brouillons > 0)
          InkWell(
            onTap: () => _tab.animateTo(2),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(12)),
              child: Text('$brouillons compte${brouillons > 1 ? 's' : ''} rendu${brouillons > 1 ? 's' : ''} à finaliser',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00))),
            ),
          ),
        _carte(titre: "Motif de l'accompagnement", icone: Icons.flag_outlined,
            action: TextButton(onPressed: () => _modifierMotif(motif),
                child: Text(motif.isEmpty ? 'Renseigner' : 'Modifier', style: const TextStyle(fontFamily: 'Galey'))),
            child: InkWell(
              onTap: () => _modifierMotif(motif),
              child: motif.isEmpty ? _texteDiscret('Non renseigné.') : Text(motif,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
            )),
        _carte(titre: 'Programme actif', icone: Icons.assignment_outlined,
            action: TextButton(onPressed: () { setState(() => _programmeVue = 'forfait'); _tab.animateTo(1); },
                child: const Text('Voir', style: TextStyle(fontFamily: 'Galey'))),
            child: f == null
                ? _texteDiscret('Aucun forfait en cours.')
                : Text('${f['nom_snapshot'] ?? 'Forfait'} — séance ${(f['nb_seances_utilisees'] as num?)?.toInt() ?? 0}/${(f['nb_seances_total'] as num?)?.toInt() ?? 0}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5))),
        _carte(titre: 'Objectifs prioritaires', icone: Icons.track_changes_outlined,
            action: TextButton(onPressed: () { setState(() => _programmeVue = 'objectifs'); _tab.animateTo(1); },
                child: const Text('Programme', style: TextStyle(fontFamily: 'Galey'))),
            child: prioritaires.isEmpty
                ? _texteDiscret('Aucun objectif en cours.')
                : Column(children: [
                    for (final o in prioritaires)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: _statutColor(o['statut']?.toString() ?? ''), shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(o['libelle']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5))),
                          Text(_kStatutLabels[o['statut']] ?? '', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _statutColor(o['statut']?.toString() ?? ''))),
                        ]),
                      ),
                  ])),
        _carte(titre: 'Dernière séance', icone: Icons.history,
            child: derniere == null
                ? _texteDiscret('Aucune séance enregistrée.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_dateFr(derniere['date_seance']?.toString())} · ${kEduTypesSeance[derniere['type_seance']] ?? (derniere['type'] == 'bilan' ? 'Bilan' : 'Séance')}',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(richTextToPlain(derniere['contenu']?.toString() ?? ''), maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.35)),
                  ])),
        _carte(titre: 'Prochain rendez-vous', icone: Icons.event_outlined,
            child: prochain == null
                ? _texteDiscret('Aucune séance planifiée.')
                : Text('${_dateFr(prochain['date_heure']?.toString())} à ${DateTime.parse(prochain['date_heure'].toString()).toLocal().hour.toString().padLeft(2, '0')}h${DateTime.parse(prochain['date_heure'].toString()).toLocal().minute.toString().padLeft(2, '0')}'
                    '${(prochain['motif']?.toString() ?? '').isNotEmpty ? ' · ${prochain['motif']}' : ''}'
                    '${(prochain['lieu']?.toString() ?? '').isNotEmpty ? '\n${prochain['lieu']}' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5))),
        _carte(titre: 'Recommandations en cours', icone: Icons.tips_and_updates_outlined,
            child: reco.isEmpty && travail.isEmpty
                ? _texteDiscret('Aucune recommandation partagée.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (reco.isNotEmpty) Text(reco, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.35)),
                    if (travail.isNotEmpty) ...[
                      if (reco.isNotEmpty) const SizedBox(height: 6),
                      Text('Travail à la maison : $travail', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.35)),
                    ],
                  ])),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalFichePage(
              animalId: widget.animalId, readOnly: true, educationMode: true))),
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: const Text('Identité et carnet de santé (lecture)', style: TextStyle(fontFamily: 'Galey')),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0C5C6C),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ]),
    );
  }

  /// Saisie du motif directement depuis la Synthèse (sans bilan).
  Future<void> _modifierMotif(String actuel) async {
    final ctrl = TextEditingController(text: actuel);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Motif de l'accompagnement", style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(controller: ctrl, autofocus: true, minLines: 2, maxLines: 5,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: const InputDecoration(hintText: 'Ex : réactivité envers les congénères, tirage en laisse…',
                border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w700, color: _kOrange))),
        ],
      ),
    );
    final texte = ctrl.text.trim();
    ctrl.dispose();
    final pid = User_Info.activeProfileId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (ok != true || pid.isEmpty || uid == null) return;
    try {
      await _supa.from('education_suivis').upsert({
        'pro_uid': uid, 'pro_profile_id': pid, 'animal_id': widget.animalId,
        'motif': texte.isEmpty ? null : texte,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'pro_profile_id,animal_id');
      if (mounted) setState(() => _motifSuivi = texte);
    } catch (e) {
      _snack('Motif non enregistré (migration_education_suivi_motif.sql à passer) : $e', err: true);
    }
  }

  // ── Programme (objectifs · exercices · forfait) ────────────────────────────

  Widget _programmeTab() {
    Widget seg(String v, String label) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600,
                color: _programmeVue == v ? Colors.white : const Color(0xFF1F2A2E))),
            selected: _programmeVue == v, showCheckmark: false,
            selectedColor: const Color(0xFF0C5C6C), backgroundColor: const Color(0xFFF1F4F3), side: BorderSide.none,
            onSelected: (_) => setState(() => _programmeVue = v),
          ),
        );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Row(children: [seg('objectifs', 'Objectifs'), seg('exercices', 'Exercices'), seg('forfait', 'Forfait')]),
      ),
      Expanded(child: switch (_programmeVue) {
        'exercices' => _exercicesTab(),
        'forfait' => _forfaitTab(),
        _ => _objectifsTab(),
      }),
    ]);
  }

  // ── Documents ──────────────────────────────────────────────────────────────

  Widget _documentsTab() {
    final bilans = _seances.where((x) => x['type'] == 'bilan' && x['statut'] != 'brouillon').toList();
    final crs = _seances.where((x) => x['type'] != 'bilan' && x['statut'] != 'brouillon').toList();
    Widget ligneDoc(Map<String, dynamic> x, String type) => ListTile(
          contentPadding: EdgeInsets.zero, dense: true,
          leading: const Icon(Icons.description_outlined, color: Color(0xFF0C5C6C)),
          title: Text('$type — ${_dateFr(x['date_seance']?.toString())}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: Text(richTextToPlain(x['contenu']?.toString() ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
          onTap: () => _tab.animateTo(2),
        );
    Widget actionDoc(IconData ic, String titre, String sous, VoidCallback onTap) => ListTile(
          contentPadding: EdgeInsets.zero, dense: true,
          leading: Icon(ic, color: _kOrange),
          title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: Text(sous, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    return RefreshIndicator(
      onRefresh: _load,
      color: _kOrange,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        _carte(titre: 'Bilans comportementaux', icone: Icons.psychology_outlined,
            child: bilans.isEmpty ? _texteDiscret('Aucun bilan finalisé.')
                : Column(children: [for (final b in bilans) ligneDoc(b, 'Bilan')])),
        _carte(titre: 'Comptes rendus de séance', icone: Icons.article_outlined,
            child: crs.isEmpty ? _texteDiscret('Aucun compte rendu finalisé.')
                : Column(children: [for (final c in crs.take(10)) ligneDoc(c, kEduTypesSeance[c['type_seance']] ?? 'Séance')])),
        _carte(titre: 'Supports et documents partagés', icone: Icons.folder_shared_outlined,
            child: Column(children: [
              actionDoc(Icons.picture_as_pdf_outlined, 'Exercices en PDF', 'Envoyer le programme d\'exercices à la famille', _envoyerExercicesPdf),
              actionDoc(Icons.link, 'Lien de suivi', 'Partager le suivi avec une famille sans compte', _partagerSuiviLien),
              actionDoc(Icons.workspace_premium_outlined, 'Attestation de fin', 'Générer l\'attestation de suivi', _genererAttestation),
            ])),
      ]),
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
                    // Progression (étapes / réussites) et durée.
                    if (progressionExercice(ex).total > 1)
                      _pill(progressionExercice(ex).etapes.isNotEmpty
                          ? 'Étape ${progressionExercice(ex).faites}/${progressionExercice(ex).total}'
                          : '${progressionExercice(ex).faites}/${progressionExercice(ex).total} réussites', _kOrange),
                    if (libelleDureeExercice(ex) != null)
                      _pill(libelleDureeExercice(ex)!, progressionExercice(ex).echue ? Colors.grey.shade500 : const Color(0xFFD5573B)),
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
                if (o['prioritaire'] == true) _pill('Prioritaire', const Color(0xFF0C5C6C)),
                _pill(_kStatutLabels[statut] ?? statut, _statutColor(statut)),
                if (cat != null && _kCategories[cat] != null) _pill(_kCategories[cat]!, Colors.grey.shade500),
              ]),
              if ((o['note']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                RichTextView(o['note'].toString(),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ],
              if ((o['difficultes']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Difficultés : ${o['difficultes']}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
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
          final brouillon = s['statut'] == 'brouillon';
          final infos = [
            if (kEduTypesSeance[s['type_seance']] != null) kEduTypesSeance[s['type_seance']]!,
            if ((s['lieu']?.toString() ?? '').isNotEmpty) s['lieu'].toString(),
            if (s['duree_minutes'] != null) '${s['duree_minutes']} min',
          ].join(' · ');
          final objs = [
            for (final id in (s['objectifs_travailles'] as List? ?? const []))
              _objectifs.where((o) => o['id'].toString() == id.toString()).map((o) => o['libelle']?.toString() ?? '').firstOrNull,
          ].whereType<String>().where((x) => x.isNotEmpty).toList();
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
                Text(_dateFr(s['date_seance']?.toString()),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                const Spacer(),
                if (brouillon) ...[
                  _pill('BROUILLON', const Color(0xFF8A5A00)),
                  TextButton(onPressed: () => _editSeance(existing: s),
                      child: const Text('Compléter', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
                ],
              ]),
              if (infos.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(infos, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
              ],
              if (objs.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Objectifs travaillés : ${objs.join(', ')}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
              ],
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
                    const Text('Recommandation',
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
              for (final e in [('Comportements observés', 'comportements'), ('Difficultés', 'difficultes'), ('Prochaine étape', 'prochaine_etape')])
                if ((s[e.$2]?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('${e.$1} : ${s[e.$2]}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, height: 1.35)),
                ],
              if ((s['exercices_conseilles']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Recommandations / travail à la maison',
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
