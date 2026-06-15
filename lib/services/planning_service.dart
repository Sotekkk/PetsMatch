import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';

class PlanningService {
  static final _supa = Supabase.instance.client;

  // ── Charger les templates d'un éleveur ──────────────────────────────────────
  static Future<List<Map<String, dynamic>>> loadTemplates(String uid, {String? type}) async {
    var q = _supa.from('plan_templates').select('*, plan_template_etapes(*)').eq('uid_eleveur', uid);
    if (type != null) q = q.eq('type', type);
    final rows = await q.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  // ── Créer un template + ses étapes ──────────────────────────────────────────
  static Future<String> createTemplate({
    required String uid,
    required String nom,
    required String type,
    String? espece,
    String? description,
    required List<Map<String, dynamic>> etapes,
  }) async {
    final row = await _supa.from('plan_templates').insert({
      'uid_eleveur': uid,
      'nom': nom,
      'type': type,
      if (espece != null && espece.isNotEmpty) 'espece': espece,
      if (description != null && description.isNotEmpty) 'description': description,
    }).select('id').single();

    final templateId = row['id'] as String;
    if (etapes.isNotEmpty) {
      await _supa.from('plan_template_etapes').insert(
        etapes.asMap().entries.map((e) => {
          'template_id': templateId,
          'jour_offset':  e.value['jour_offset'] ?? 0,
          'type_acte':    e.value['type_acte'],
          'produit':      e.value['produit'],
          'dosage':       e.value['dosage'],
          'duree_jours':  e.value['duree_jours'] ?? 1,
          'description':  e.value['description'],
          'ordre':        e.key,
        }).toList(),
      );
    }
    return templateId;
  }

  // ── Mettre à jour un template ────────────────────────────────────────────────
  static Future<void> updateTemplate({
    required String templateId,
    required String nom,
    String? espece,
    String? description,
    required List<Map<String, dynamic>> etapes,
  }) async {
    await _supa.from('plan_templates').update({
      'nom': nom,
      'espece': espece,
      'description': description,
    }).eq('id', templateId);

    await _supa.from('plan_template_etapes').delete().eq('template_id', templateId);
    if (etapes.isNotEmpty) {
      await _supa.from('plan_template_etapes').insert(
        etapes.asMap().entries.map((e) => {
          'template_id': templateId,
          'jour_offset':  e.value['jour_offset'] ?? 0,
          'type_acte':    e.value['type_acte'],
          'produit':      e.value['produit'],
          'dosage':       e.value['dosage'],
          'duree_jours':  e.value['duree_jours'] ?? 1,
          'description':  e.value['description'],
          'ordre':        e.key,
        }).toList(),
      );
    }
  }

  // ── Supprimer un template ────────────────────────────────────────────────────
  static Future<void> deleteTemplate(String templateId) async {
    await _supa.from('plan_templates').delete().eq('id', templateId);
  }

  // ── Appliquer un template → générer tâches ──────────────────────────────────
  static Future<String> applyTemplate({
    required String uid,
    required String templateId,
    required String typeDeclencheur,
    required DateTime dateReference,
    String? referenceId,
    String? referenceLabel,
    List<Map<String, dynamic>>? etapesOverride,
  }) async {
    // Charger les étapes si pas fournies en override
    final etapes = etapesOverride ?? await _loadEtapes(templateId);

    final planRow = await _supa.from('plans_actifs').insert({
      'template_id':      templateId,
      'uid_eleveur':      uid,
      'type_declencheur': typeDeclencheur,
      'date_reference':   dateReference.toIso8601String().split('T').first,
      if (referenceId != null)    'reference_id':    referenceId,
      if (referenceLabel != null) 'reference_label': referenceLabel,
    }).select('id').single();

    final planId = planRow['id'] as String;
    final taches = <Map<String, dynamic>>[];

    for (final etape in etapes) {
      final offset    = (etape['jour_offset'] as num? ?? 0).toInt();
      final duree     = (etape['duree_jours'] as num? ?? 1).toInt();
      final baseDate  = dateReference.add(Duration(days: offset));
      final produit   = etape['produit']?.toString() ?? '';
      final typeActe  = etape['type_acte']?.toString() ?? '';
      final dosage    = etape['dosage']?.toString() ?? '';
      final desc      = etape['description']?.toString() ?? '';

      final labelBase = [
        if (typeActe.isNotEmpty) _acteLabel(typeActe),
        if (produit.isNotEmpty) produit,
        if (dosage.isNotEmpty) '($dosage)',
      ].join(' ');

      for (int jour = 1; jour <= duree; jour++) {
        final date = baseDate.add(Duration(days: jour - 1));
        taches.add({
          'plan_id':         planId,
          'etape_id':        etape['id'],
          'uid_eleveur':     uid,
          'label':           duree > 1 ? '$labelBase — Jour $jour/$duree' : (labelBase.isNotEmpty ? labelBase : desc),
          'date_prevue':     date.toIso8601String().split('T').first,
          'jour_traitement': jour,
          'total_jours':     duree,
          if (referenceId != null && typeDeclencheur == 'naissance') 'portee_id': referenceId,
          if (referenceId != null && typeDeclencheur == 'saillie')   'animal_id': referenceId,
        });
      }
    }

    if (taches.isNotEmpty) {
      await _supa.from('plan_taches').insert(taches);
    }
    return planId;
  }

  // ── Tâches du jour ───────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getTachesJour(String uid, DateTime date) async {
    final dateStr = date.toIso8601String().split('T').first;
    final rows = await _supa
        .from('plan_taches')
        .select('*, plans_actifs(reference_label, type_declencheur)')
        .eq('uid_eleveur', uid)
        .eq('date_prevue', dateStr)
        .neq('statut', 'fait')
        .order('date_prevue');
    return List<Map<String, dynamic>>.from(rows);
  }

  // ── Tâches sur une période ───────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getTachesPeriode(
      String uid, DateTime debut, DateTime fin) async {
    final rows = await _supa
        .from('plan_taches')
        .select('*, plans_actifs(reference_label, type_declencheur)')
        .eq('uid_eleveur', uid)
        .gte('date_prevue', debut.toIso8601String().split('T').first)
        .lte('date_prevue', fin.toIso8601String().split('T').first)
        .order('date_prevue');
    return List<Map<String, dynamic>>.from(rows);
  }

  // ── Compter tâches du jour non faites ────────────────────────────────────────
  static Future<int> countTachesEnAttente(String uid) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final rows = await _supa
        .from('plan_taches')
        .select('id')
        .eq('uid_eleveur', uid)
        .eq('date_prevue', today)
        .eq('statut', 'en_attente');
    return (rows as List).length;
  }

  // ── Valider une tâche ────────────────────────────────────────────────────────
  static Future<void> validerTache(
    String tacheId, {
    required String validateurUid,
    String? notes,
    required Map<String, dynamic> tacheData,
    required String uid,
  }) async {
    await _supa.from('plan_taches').update({
      'statut':           'fait',
      'valide_par':       validateurUid,
      'valide_at':        DateTime.now().toIso8601String(),
      if (notes != null && notes.isNotEmpty) 'notes_validation': notes,
    }).eq('id', tacheId);

    // Créer l'entrée dans le registre sanitaire si c'est un acte sanitaire
    final typeActe = tacheData['type_acte']?.toString() ?? '';
    final animalId = tacheData['animal_id']?.toString();
    if (_isSanitaire(typeActe) && animalId != null && animalId.isNotEmpty) {
      final dateActe = DateTime.tryParse(tacheData['date_prevue']?.toString() ?? '') ?? DateTime.now();
      await RegistreHelper.writeActe(
        animalId: animalId,
        typeActe: typeActe,
        dateActe: dateActe,
        description: tacheData['label'] ?? '',
        intervenant: '',
      );
    }
  }

  // ── Reporter une tâche à J+1 ─────────────────────────────────────────────────
  static Future<void> reporterTache(String tacheId, DateTime dateActuelle) async {
    final newDate = dateActuelle.add(const Duration(days: 1));
    await _supa.from('plan_taches').update({
      'statut':      'reporte',
      'date_prevue': newDate.toIso8601String().split('T').first,
    }).eq('id', tacheId);
    // Créer une nouvelle tâche avec le nouveau statut en_attente
    final row = await _supa.from('plan_taches').select().eq('id', tacheId).single();
    await _supa.from('plan_taches').insert({
      ...row,
      'id':          null,
      'date_prevue': newDate.toIso8601String().split('T').first,
      'statut':      'en_attente',
      'valide_par':  null,
      'valide_at':   null,
      'notes_validation': null,
      'created_at':  null,
    }..remove('id'));
  }

  // ── Helpers internes ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> _loadEtapes(String templateId) async {
    final rows = await _supa
        .from('plan_template_etapes')
        .select()
        .eq('template_id', templateId)
        .order('ordre');
    return List<Map<String, dynamic>>.from(rows);
  }

  static bool _isSanitaire(String type) =>
      ['vermifuge', 'vaccination', 'antiparasitaire', 'traitement', 'visite'].contains(type);

  static String _acteLabel(String type) => switch (type) {
    'vermifuge'       => 'Vermifuge',
    'vaccination'     => 'Vaccination',
    'antiparasitaire' => 'Antiparasitaire',
    'traitement'      => 'Traitement',
    'visite'          => 'Visite',
    'nettoyage'       => 'Nettoyage',
    'promenade'       => 'Promenade',
    'socialisation'   => 'Socialisation',
    _                 => type,
  };
}
