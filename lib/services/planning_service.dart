import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/main.dart';

class PlanningService {
  static final _supa = Supabase.instance.client;

  static String get _profilSource =>
      User_Info.activeType == 'association' ? 'association' : 'eleveur';

  // ── Charger les templates ────────────────────────────────────────────────────
  // [profilSourceOverride]/[eleveurProfileIdOverride] : permettent à un
  // employé autorisé (write_protocoles) d'agir pour le compte d'un employeur
  // dont le profil actif n'est pas le sien (ex: employeur pension alors que
  // l'employé navigue depuis son profil particulier).
  static Future<List<Map<String, dynamic>>> loadTemplates(
    String uid, {
    String? type,
    String? profilSourceOverride,
    String? eleveurProfileIdOverride,
  }) async {
    final profileId = eleveurProfileIdOverride ?? User_Info.activeProfileId;
    final filterCol = profileId.isNotEmpty ? 'eleveur_profile_id' : 'uid_eleveur';
    final filterVal = profileId.isNotEmpty ? profileId : uid;
    final profilSource = profilSourceOverride ?? _profilSource;
    var q = _supa.from('plan_templates').select('*, plan_template_etapes(*)').eq(filterCol, filterVal);
    if (type != null) q = q.eq('type', type);
    if (profilSource == 'pension') {
      q = q.eq('profil_source', 'pension');
    } else if (profilSource == 'association') {
      q = q.eq('profil_source', 'association');
    } else {
      q = q.or('profil_source.is.null,profil_source.eq.eleveur');
    }
    final rows = await q.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  // ── Créer un template + ses étapes ──────────────────────────────────────────
  // [createdByUid]/[createdByProfileId] : identité réelle du créateur quand
  // ce n'est pas l'employeur lui-même (employé autorisé). [uid] reste le uid
  // de l'employeur (propriétaire du protocole, ce sur quoi les écrans de
  // l'employeur filtrent déjà).
  static Future<String> createTemplate({
    required String uid,
    required String nom,
    required String type,
    String? espece,
    String? description,
    String? lieu,
    String cibleType      = 'individuel',
    String referenceEvent = 'manuel',
    String? declencheurAuto,
    List<String>? defaultAnimalIds,
    required List<Map<String, dynamic>> etapes,
    String? profilSourceOverride,
    String? eleveurProfileIdOverride,
    String? createdByUid,
    String? createdByProfileId,
  }) async {
    final ownerProfileId = eleveurProfileIdOverride ?? User_Info.activeProfileId;
    final row = await _supa.from('plan_templates').insert({
      'uid_eleveur':     uid,
      if (ownerProfileId.isNotEmpty) 'eleveur_profile_id': ownerProfileId,
      'nom':             nom,
      'type':            type,
      'cible_type':      cibleType,
      'reference_event': referenceEvent,
      'profil_source':   profilSourceOverride ?? _profilSource,
      if (declencheurAuto != null && declencheurAuto.isNotEmpty) 'declencheur_auto': declencheurAuto,
      if (espece != null && espece.isNotEmpty) 'espece': espece,
      if (description != null && description.isNotEmpty) 'description': description,
      if (lieu != null && lieu.isNotEmpty) 'lieu': lieu,
      if (defaultAnimalIds != null && defaultAnimalIds.isNotEmpty) 'default_animal_ids': defaultAnimalIds,
      if (createdByUid != null) 'created_by_uid': createdByUid,
      if (createdByProfileId != null) 'created_by_profile_id': createdByProfileId,
    }).select('id').single();

    final templateId = row['id'] as String;
    await _insertEtapes(templateId, etapes);
    return templateId;
  }

  // ── Mettre à jour un template ────────────────────────────────────────────────
  static Future<void> updateTemplate({
    required String templateId,
    required String nom,
    String? espece,
    String? description,
    String? lieu,
    String cibleType      = 'individuel',
    String referenceEvent = 'manuel',
    String? declencheurAuto,
    List<String>? defaultAnimalIds,
    required List<Map<String, dynamic>> etapes,
  }) async {
    await _supa.from('plan_templates').update({
      'nom':              nom,
      'espece':           espece,
      'description':      description,
      'cible_type':       cibleType,
      'reference_event':  referenceEvent,
      'lieu':             lieu,
      'declencheur_auto': (declencheurAuto != null && declencheurAuto.isNotEmpty) ? declencheurAuto : null,
      'default_animal_ids': (defaultAnimalIds != null && defaultAnimalIds.isNotEmpty) ? defaultAnimalIds : null,
    }).eq('id', templateId);

    // Ne jamais supprimer/réinsérer en bloc : une étape déjà appliquée à un
    // animal a des plan_taches qui la référencent (etape_id), et la
    // contrainte de clé étrangère bloque alors le DELETE ("update or
    // delete... still referenced from table plan_taches"). On met à jour en
    // place les étapes existantes (même id -> tâches déjà générées restent
    // liées), on insère les nouvelles, et on ne supprime que les étapes
    // retirées du formulaire qui n'ont jamais généré de tâche.
    final existingRows = await _supa.from('plan_template_etapes').select('id').eq('template_id', templateId);
    final existingIds = (existingRows as List).map((r) => r['id'] as String).toSet();
    final keptIds = etapes.map((e) => e['id'] as String?).whereType<String>().toSet();
    final removedIds = existingIds.difference(keptIds).toList();

    if (removedIds.isNotEmpty) {
      final referencedRows = await _supa.from('plan_taches').select('etape_id').inFilter('etape_id', removedIds);
      final referencedIds = (referencedRows as List).map((r) => r['etape_id'] as String).toSet();
      final safeToDelete = removedIds.where((id) => !referencedIds.contains(id)).toList();
      if (safeToDelete.isNotEmpty) {
        await _supa.from('plan_template_etapes').delete().inFilter('id', safeToDelete);
      }
    }

    // L'ordre (position dans la liste) doit être préservé même pour les
    // étapes mises à jour en place, sinon un simple réordonnancement ne
    // serait jamais sauvegardé pour les étapes déjà existantes.
    final ordered = etapes.asMap().entries.map((e) => {...e.value, 'ordre': e.key}).toList();
    final toUpdate = ordered.where((e) => existingIds.contains(e['id'])).toList();
    final toInsert = ordered.where((e) => !existingIds.contains(e['id'])).toList();

    for (final e in toUpdate) {
      await _supa.from('plan_template_etapes').update({..._etapeFields(e), 'ordre': e['ordre']}).eq('id', e['id'] as String);
    }
    await _insertEtapes(templateId, toInsert);
  }

  static Map<String, dynamic> _etapeFields(Map<String, dynamic> e) => {
    'offset_direction': e['offset_direction'] ?? 'apres',
    'jour_offset':      e['jour_offset'] ?? 0,
    'age_min_semaines': e['age_min_semaines'],
    'type_acte':        e['type_acte'],
    'produit':          e['produit'],
    'dosage':           e['dosage'],
    'frequence':        e['frequence'] ?? 'ponctuel',
    'nb_fois_semaine':  e['nb_fois_semaine'] ?? 1,
    'duree_semaines':   (e['is_recurrent'] == true) ? 52 : (e['duree_semaines'] ?? 1),
    'duree_jours':      e['duree_jours'] ?? 1,
    'is_recurrent':     e['is_recurrent'] ?? false,
    'lieu':             e['lieu'],
    'description':      e['description'],
    'tranche_horaire':  e['tranche_horaire'],
  };

  static Future<void> _insertEtapes(String templateId, List<Map<String, dynamic>> etapes) async {
    if (etapes.isEmpty) return;
    await _supa.from('plan_template_etapes').insert(
      etapes.asMap().entries.map((e) => {
        'template_id': templateId,
        ..._etapeFields(e.value),
        // Respecte un ordre déjà calculé (ex: position dans la liste
        // complète lors d'une mise à jour partielle) si présent, sinon
        // retombe sur la position dans CETTE liste (création initiale).
        'ordre': e.value['ordre'] ?? e.key,
      }).toList(),
    );
  }

  // ── Supprimer un template ────────────────────────────────────────────────────
  // Ne retire que les occurrences FUTURES (date_prevue après aujourd'hui) de
  // l'agenda ; l'historique passé reste visible comme trace. On ne supprime
  // donc pas les lignes plans_actifs (ça cascaderait aussi sur l'historique
  // via plan_taches.plan_id ON DELETE CASCADE) : on les détache du template
  // et on les marque annulées à la place.
  static Future<void> deleteTemplate(String templateId) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final plans = await _supa.from('plans_actifs').select('id').eq('template_id', templateId);
    final planIds = (plans as List).map((p) => p['id'] as String).toList();
    if (planIds.isNotEmpty) {
      await _supa.from('plan_taches').delete()
          .inFilter('plan_id', planIds).gt('date_prevue', today);
      await _supa.from('plans_actifs')
          .update({'template_id': null, 'statut': 'annule'})
          .eq('template_id', templateId);
    }
    await _supa.from('plan_templates').delete().eq('id', templateId);
  }

  // ── Appliquer un template → génère les tâches ────────────────────────────────
  // Résout la cible automatiquement si cible_type != 'individuel'
  static Future<int> applyTemplate({
    required String uid,
    required Map<String, dynamic> template,
    required DateTime dateReference,
    String? referenceId,
    String? referenceLabel,
    // Pour cible individuel : liste d'animal_id sélectionnés
    List<String>? forcedAnimalIds,
    String? profilSourceOverride,
    String? eleveurProfileIdOverride,
  }) async {
    final cibleType    = template['cible_type']  as String? ?? 'individuel';
    final refEvent     = template['reference_event'] as String? ?? 'manuel';
    final etapes       = await _loadEtapes(template['id'] as String);
    final espece       = template['espece'] as String?;

    // Un protocole créé par un employé (autorisé) s'auto-attribue à ce
    // dernier sur les tâches générées, visible par l'employeur.
    final ownerProfileId = eleveurProfileIdOverride ?? User_Info.activeProfileId;
    final creatorUid        = template['created_by_uid'] as String?;
    final creatorProfileId  = template['created_by_profile_id'] as String?;
    final autoAssignUid     = (creatorUid != null && creatorUid.isNotEmpty &&
            creatorProfileId != null && creatorProfileId != ownerProfileId)
        ? creatorUid
        : null;
    final autoAssignProfileId = autoAssignUid != null ? creatorProfileId : null;

    // Résoudre la liste des animaux cibles
    final List<Map<String, dynamic>> cibles = await _resolveCibles(
      uid: uid,
      cibleType: cibleType,
      refEvent: refEvent,
      espece: espece,
      forcedAnimalIds: forcedAnimalIds,
      dateReference: dateReference,
    );

    if (cibles.isEmpty) return 0;

    // Créer un plan actif par cible (ou un seul plan si cheptel)
    int tachesCount = 0;
    final isBebes = cibleType == 'bebes';

    if (cibleType == 'cheptel' || cibleType == 'males' || cibleType == 'femelles') {
      // Un seul plan pour le groupe
      final planId = await _createPlan(
        uid: uid, template: template, dateReference: dateReference,
        referenceId: referenceId, referenceLabel: referenceLabel ?? _cibleLabel(cibleType, espece),
        profilSourceOverride: profilSourceOverride, eleveurProfileIdOverride: eleveurProfileIdOverride,
      );
      for (final cible in cibles) {
        tachesCount += await _generateTaches(
          planId: planId, uid: uid, etapes: etapes,
          dateBase: cible['date_ref'] as DateTime? ?? dateReference,
          isBebes: isBebes,
          animalId: cible['animal_id'] as String?,
          animalNom: cible['animal_nom'] as String?,
          profilSourceOverride: profilSourceOverride, eleveurProfileIdOverride: eleveurProfileIdOverride,
          assignedTo: autoAssignUid, assignedProfileId: autoAssignProfileId,
        );
      }
    } else {
      // Un plan par animal (gestantes, bébés, individuel, allaitantes)
      for (final cible in cibles) {
        final dateBase = cible['date_ref'] as DateTime? ?? dateReference;
        final planId = await _createPlan(
          uid: uid, template: template,
          dateReference: dateBase,
          referenceId: cible['animal_id'] as String?,
          referenceLabel: cible['animal_nom'] as String?,
          profilSourceOverride: profilSourceOverride, eleveurProfileIdOverride: eleveurProfileIdOverride,
        );
        tachesCount += await _generateTaches(
          planId: planId, uid: uid, etapes: etapes,
          dateBase: dateBase,
          isBebes: isBebes,
          animalId: cible['animal_id'] as String?,
          animalNom: cible['animal_nom'] as String?,
          profilSourceOverride: profilSourceOverride, eleveurProfileIdOverride: eleveurProfileIdOverride,
          assignedTo: autoAssignUid, assignedProfileId: autoAssignProfileId,
        );
      }
    }
    return tachesCount;
  }

  // ── Résoudre les animaux cibles ──────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> _resolveCibles({
    required String uid,
    required String cibleType,
    required String refEvent,
    String? espece,
    List<String>? forcedAnimalIds,
    required DateTime dateReference,
  }) async {
    switch (cibleType) {
      case 'individuel':
        if (forcedAnimalIds != null && forcedAnimalIds.isNotEmpty) {
          final rows = await _supa.from('animaux').select('id, nom').inFilter('id', forcedAnimalIds);
          return (rows as List).map((a) => {
            'animal_id': a['id'] as String?,
            'animal_nom': a['nom'] as String?,
            'date_ref': dateReference,
          }).toList();
        }
        return [{ 'animal_id': null, 'animal_nom': null, 'date_ref': dateReference }];

      case 'cheptel':
      case 'males':
      case 'femelles': {
        var q = _supa.from('animaux').select('id, nom').eq('uid_eleveur', uid);
        if (espece != null && espece.isNotEmpty) q = q.eq('espece', espece);
        if (cibleType == 'males')   q = q.eq('sexe', 'male');
        if (cibleType == 'femelles') q = q.eq('sexe', 'femelle');
        final rows = await q.order('nom');
        return (rows as List).map((a) => {
          'animal_id': a['id'] as String?,
          'animal_nom': a['nom'] as String?,
          'date_ref': dateReference,
        }).toList();
      }

      case 'gestantes': {
        // Charger toutes les gestations en cours (sans date_mise_bas)
        var q = _supa.from('gestations')
            .select('id, animal_id, date_mise_bas, date_prevue, animaux(nom, espece)')
            .eq('uid_eleveur', uid)
            .filter('date_mise_bas', 'is', null);  // gestations en cours
        final rows = await q.order('date_prevue');
        return (rows as List).map((g) {
          final datePrevue = DateTime.tryParse(g['date_prevue'] as String? ?? '') ?? dateReference;
          final anim = g['animaux'] as Map<String, dynamic>? ?? {};
          return {
            'animal_id': g['animal_id'] as String?,
            'animal_nom': anim['nom'] as String?,
            'date_ref': datePrevue,  // J0 = date prévue mise bas
          };
        }).toList();
      }

      case 'bebes': {
        // Animaux nés récemment (< 6 mois) ou selon age_min_semaines
        var q = _supa.from('animaux')
            .select('id, nom, date_naissance')
            .eq('uid_eleveur', uid)
            .not('date_naissance', 'is', null);
        if (espece != null && espece.isNotEmpty) q = q.eq('espece', espece);
        final rows = await q.order('date_naissance', ascending: false);
        final sixMoisPasse = DateTime.now().subtract(const Duration(days: 183));
        return (rows as List)
            .where((a) {
              final dn = DateTime.tryParse(a['date_naissance'] as String? ?? '');
              return dn != null && dn.isAfter(sixMoisPasse);
            })
            .map((a) {
              final dn = DateTime.tryParse(a['date_naissance'] as String? ?? '') ?? dateReference;
              return {
                'animal_id': a['id'] as String?,
                'animal_nom': a['nom'] as String?,
                'date_ref': dn,  // J0 = date de naissance
              };
            }).toList();
      }

      case 'allaitantes': {
        // Femelles dont la mise bas date de moins de 8 semaines
        final cutoff = DateTime.now().subtract(const Duration(days: 56)).toIso8601String().split('T').first;
        final gestRows = await _supa.from('gestations')
            .select('animal_id, date_mise_bas, animaux(nom, espece)')
            .eq('uid_eleveur', uid)
            .not('date_mise_bas', 'is', null)
            .gte('date_mise_bas', cutoff);
        return (gestRows as List).where((g) {
          if (espece == null || espece.isEmpty) return true;
          final anim = g['animaux'] as Map<String, dynamic>? ?? {};
          return anim['espece'] == espece;
        }).map((g) {
          final dateMiseBas = DateTime.tryParse(g['date_mise_bas'] as String? ?? '') ?? dateReference;
          final anim = g['animaux'] as Map<String, dynamic>? ?? {};
          return {
            'animal_id': g['animal_id'] as String?,
            'animal_nom': anim['nom'] as String?,
            'date_ref': dateMiseBas,
          };
        }).toList();
      }

      default:
        return [{ 'animal_id': null, 'animal_nom': null, 'date_ref': dateReference }];
    }
  }

  // ── Créer un plan actif ──────────────────────────────────────────────────────
  static Future<String> _createPlan({
    required String uid,
    required Map<String, dynamic> template,
    required DateTime dateReference,
    String? referenceId,
    String? referenceLabel,
    String? profilSourceOverride,
    String? eleveurProfileIdOverride,
  }) async {
    final ownerProfileId = eleveurProfileIdOverride ?? User_Info.activeProfileId;
    final row = await _supa.from('plans_actifs').insert({
      'template_id':      template['id'],
      'uid_eleveur':      uid,
      if (ownerProfileId.isNotEmpty) 'eleveur_profile_id': ownerProfileId,
      'type_declencheur': template['reference_event'] ?? 'manuel',
      'date_reference':   dateReference.toIso8601String().split('T').first,
      'profil_source':    profilSourceOverride ?? _profilSource,
      if (referenceId != null)    'reference_id':    referenceId,
      if (referenceLabel != null) 'reference_label': referenceLabel,
    }).select('id').single();
    return row['id'] as String;
  }

  // ── Générer les tâches pour une étape / un animal ────────────────────────────
  static Future<int> _generateTaches({
    required String planId,
    required String uid,
    required List<Map<String, dynamic>> etapes,
    required DateTime dateBase,
    required bool isBebes,
    String? animalId,
    String? animalNom,
    String? profilSourceOverride,
    String? eleveurProfileIdOverride,
    String? assignedTo,
    String? assignedProfileId,
  }) async {
    final taches = <Map<String, dynamic>>[];

    for (final etape in etapes) {
      final direction      = etape['offset_direction']?.toString() ?? 'apres';
      final offsetJours    = (etape['jour_offset'] as num? ?? 0).toInt();
      final frequence      = etape['frequence']?.toString() ?? 'ponctuel';
      final nbFoisSemaine  = (etape['nb_fois_semaine'] as num? ?? 1).toInt();
      final dureeSemanines = (etape['duree_semaines'] as num? ?? 1).toInt();
      final dureeJours     = (etape['duree_jours'] as num? ?? 1).toInt();
      final typeActe       = etape['type_acte']?.toString() ?? '';
      final produit        = etape['produit']?.toString() ?? '';
      final dosage         = etape['dosage']?.toString() ?? '';
      final lieu           = etape['lieu']?.toString();
      final desc           = etape['description']?.toString() ?? '';
      final ageSemaines    = etape['age_min_semaines'] as int?;
      final trancheHoraire = etape['tranche_horaire'] as String?;

      // Calculer la date de départ de l'étape
      final sign = direction == 'avant' ? -1 : 1;
      DateTime startDate;
      if (isBebes && ageSemaines != null) {
        // Mode bébé uniquement : offset calculé depuis la naissance par âge en semaines
        startDate = dateBase.add(Duration(days: ageSemaines * 7));
      } else {
        startDate = dateBase.add(Duration(days: sign * offsetJours));
      }

      final labelBase = _buildLabel(typeActe, produit, dosage, desc);

      switch (frequence) {
        case 'ponctuel':
          for (int jour = 1; jour <= dureeJours; jour++) {
            final date = startDate.add(Duration(days: jour - 1));
            taches.add(_tache(planId: planId, etape: etape, uid: uid, animalId: animalId, animalNom: animalNom, profilSourceOverride: profilSourceOverride, eleveurProfileIdOverride: eleveurProfileIdOverride, assignedTo: assignedTo, assignedProfileId: assignedProfileId,
              label: dureeJours > 1 ? '$labelBase — Jour $jour/$dureeJours' : labelBase,
              date: date, jour: jour, total: dureeJours, typeActe: typeActe, lieu: lieu,
              trancheHoraire: trancheHoraire));
          }

        case 'quotidien':
          final totalJours = dureeSemanines * 7;
          for (int jour = 1; jour <= totalJours; jour++) {
            final date = startDate.add(Duration(days: jour - 1));
            taches.add(_tache(planId: planId, etape: etape, uid: uid, animalId: animalId, animalNom: animalNom, profilSourceOverride: profilSourceOverride, eleveurProfileIdOverride: eleveurProfileIdOverride, assignedTo: assignedTo, assignedProfileId: assignedProfileId,
              label: '$labelBase — Jour $jour/$totalJours',
              date: date, jour: jour, total: totalJours, typeActe: typeActe, lieu: lieu,
              trancheHoraire: trancheHoraire));
          }

        case 'hebdomadaire':
          final offsets = _weekOffsets(nbFoisSemaine);
          final totalOccurrences = nbFoisSemaine * dureeSemanines;
          int occurrence = 1;
          for (int semaine = 0; semaine < dureeSemanines; semaine++) {
            for (final dayOff in offsets) {
              final date = startDate.add(Duration(days: semaine * 7 + dayOff));
              taches.add(_tache(planId: planId, etape: etape, uid: uid, animalId: animalId, animalNom: animalNom, profilSourceOverride: profilSourceOverride, eleveurProfileIdOverride: eleveurProfileIdOverride, assignedTo: assignedTo, assignedProfileId: assignedProfileId,
                label: '$labelBase (${occurrence}e/${totalOccurrences}e)',
                date: date, jour: occurrence, total: totalOccurrences, typeActe: typeActe, lieu: lieu,
                trancheHoraire: trancheHoraire));
              occurrence++;
            }
          }

        case 'mensuel':
          for (int mois = 0; mois < dureeSemanines; mois++) {
            final date = DateTime(startDate.year, startDate.month + mois, startDate.day);
            taches.add(_tache(planId: planId, etape: etape, uid: uid, animalId: animalId, animalNom: animalNom, profilSourceOverride: profilSourceOverride, eleveurProfileIdOverride: eleveurProfileIdOverride, assignedTo: assignedTo, assignedProfileId: assignedProfileId,
              label: '$labelBase (mois ${mois + 1}/$dureeSemanines)',
              date: date, jour: mois + 1, total: dureeSemanines, typeActe: typeActe, lieu: lieu,
              trancheHoraire: trancheHoraire));
          }
      }
    }

    if (taches.isEmpty) return 0;

    // Dedup : filtrer les tâches qui existent déjà (même etape_id + date_prevue + animal_id)
    try {
      final etapeIds = taches.map((t) => t['etape_id']).whereType<String>().toSet().toList();
      final dates    = taches.map((t) => t['date_prevue'] as String).toSet().toList();
      final existing = await _supa
          .from('plan_taches')
          .select('etape_id, date_prevue, animal_id')
          .eq('uid_eleveur', uid)
          .inFilter('etape_id', etapeIds)
          .inFilter('date_prevue', dates);
      final existingKeys = <String>{
        for (final e in existing as List)
          '${e['etape_id']}_${e['date_prevue']}_${e['animal_id'] ?? ''}'
      };
      final toInsert = taches.where((t) {
        final key = '${t['etape_id']}_${t['date_prevue']}_${t['animal_id'] ?? ''}';
        return !existingKeys.contains(key);
      }).toList();
      if (toInsert.isNotEmpty) await _supa.from('plan_taches').insert(toInsert);
      return toInsert.length;
    } catch (_) {
      await _supa.from('plan_taches').insert(taches);
      return taches.length;
    }
  }

  static Map<String, dynamic> _tache({
    required String planId, required Map<String, dynamic> etape, required String uid,
    String? animalId, String? animalNom, required String label, required DateTime date,
    required int jour, required int total, required String typeActe, String? lieu,
    String? trancheHoraire,
    String? profilSourceOverride, String? eleveurProfileIdOverride,
    String? assignedTo, String? assignedProfileId,
  }) {
    final ownerProfileId = eleveurProfileIdOverride ?? User_Info.activeProfileId;
    return {
      'plan_id':         planId,
      'etape_id':        etape['id'],
      'uid_eleveur':     uid,
      'profile_id': ownerProfileId.isNotEmpty ? ownerProfileId : null,
      if (ownerProfileId.isNotEmpty) 'eleveur_profile_id': ownerProfileId,
      'profil_source':   profilSourceOverride ?? _profilSource,
      if (animalId != null) 'animal_id': animalId,
      if (animalNom != null && animalNom.isNotEmpty) 'animal_nom': animalNom,
      'label':           label,
      'type_acte':       typeActe.isEmpty ? null : typeActe,
      'date_prevue':     date.toIso8601String().split('T').first,
      'jour_traitement': jour,
      'total_jours':     total,
      if (lieu != null && lieu.isNotEmpty) 'lieu': lieu,
      if (trancheHoraire != null) 'tranche_horaire': trancheHoraire,
      if (assignedTo != null) 'assigned_to': assignedTo,
      if (assignedProfileId != null) 'assigned_profile_id': assignedProfileId,
    };
  }

  // ── Déclencher automatiquement les protocoles sur un événement ──────────────
  // Cherche tous les templates avec declencheur_auto == declencheur,
  // filtre par espece, vérifie les doublons, puis applique.
  static Future<int> triggerAutoProtocoles({
    required String uid,
    required String declencheur, // 'naissance' | 'chaleurs' | 'gestation' | 'entree'
    required String animalId,
    required DateTime dateEvenement,
    String? espece,
  }) async {
    final rows = await _supa
        .from('plan_templates')
        .select('*, plan_template_etapes(*)')
        .eq('uid_eleveur', uid)
        .eq('declencheur_auto', declencheur);

    final templates = List<Map<String, dynamic>>.from(rows);
    if (templates.isEmpty) return 0;

    int total = 0;
    for (final template in templates) {
      // Filtre espece : null/vide = toutes espèces
      final tEspece = template['espece'] as String?;
      if (tEspece != null && tEspece.isNotEmpty && espece != null && tEspece != espece) continue;

      // Déduplication : si des tâches issues de ce template existent déjà pour cet animal
      final etapes = (template['plan_template_etapes'] as List?) ?? [];
      if (etapes.isEmpty) continue;
      final etapeIds = etapes.map((e) => e['id'].toString()).toList();
      final window = dateEvenement.subtract(const Duration(days: 30)).toIso8601String().split('T').first;

      final existing = await _supa
          .from('plan_taches')
          .select('id')
          .eq('uid_eleveur', uid)
          .eq('animal_id', animalId)
          .inFilter('etape_id', etapeIds)
          .gte('date_prevue', window)
          .limit(1);

      if ((existing as List).isNotEmpty) continue; // déjà appliqué

      // Forcer cible individuelle pour ne cibler que cet animal
      final mod = Map<String, dynamic>.from(template)..['cible_type'] = 'individuel';
      total += await applyTemplate(
        uid: uid,
        template: mod,
        dateReference: dateEvenement,
        forcedAnimalIds: [animalId],
      );
    }
    return total;
  }

  // ── Tâches du jour ───────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getTachesJour(
    String uid,
    DateTime date, {
    bool? isAssociation,
    String? profilSourceOverride,
  }) async {
    final dateStr = date.toIso8601String().split('T').first;
    final profil  = profilSourceOverride ??
        ((isAssociation ?? (_profilSource == 'association')) ? 'association' : 'eleveur');
    final q = _supa
        .from('plan_taches')
        .select('*, plans_actifs(reference_label, type_declencheur)')
        .eq('uid_eleveur', uid)
        .eq('date_prevue', dateStr)
        .neq('statut', 'fait');
    final rows = profil == 'pension'
        ? await q.eq('profil_source', 'pension').order('date_prevue')
        : profil == 'association'
            ? await q.eq('profil_source', 'association').order('date_prevue')
            : await q.or('profil_source.is.null,profil_source.eq.eleveur').order('date_prevue');
    return List<Map<String, dynamic>>.from(rows);
  }

  // ── Compter tâches en attente aujourd'hui ────────────────────────────────────
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
    String? validateurProfileId,
    String? notes,
    required Map<String, dynamic> tacheData,
    bool insertRegistre = false,
  }) async {
    await _supa.from('plan_taches').update({
      'statut':           'fait',
      'valide_par':       validateurUid,
      'valide_par_profile_id': validateurProfileId,
      'valide_at':        DateTime.now().toIso8601String(),
      if (notes != null && notes.isNotEmpty) 'notes_validation': notes,
    }).eq('id', tacheId);

    // Insérer dans le registre uniquement si demandé explicitement
    if (insertRegistre) {
      final typeActe = tacheData['type_acte']?.toString() ?? '';
      final animalId = tacheData['animal_id']?.toString();
      if (animalId != null && animalId.isNotEmpty) {
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
  }

  // ── Supprimer (cette occurrence / suivantes / toutes) ───────────────────────
  static Future<void> supprimerTaches({
    required List<String> tacheIds,
    required String scope, // 'cette' | 'suivantes' | 'toutes'
    String? etapeId,
    String? uid,
    String? dateRef, // YYYY-MM-DD, requis pour 'suivantes'
  }) async {
    if (scope == 'cette') {
      await _supa.from('plan_taches').delete().inFilter('id', tacheIds);
    } else if (scope == 'suivantes') {
      await _supa.from('plan_taches').delete()
          .eq('etape_id', etapeId!).eq('uid_eleveur', uid!)
          .gte('date_prevue', dateRef!).neq('statut', 'fait');
    } else {
      await _supa.from('plan_taches').delete()
          .eq('etape_id', etapeId!).eq('uid_eleveur', uid!).neq('statut', 'fait');
    }
  }

  // ── Modifier tranche_horaire (cette occurrence / suivantes / toutes) ────────
  static Future<void> modifierTranche({
    required List<String> tacheIds,
    required String scope,
    required String? tranche,
    String? etapeId,
    String? uid,
    String? dateRef,
  }) async {
    final update = {'tranche_horaire': tranche};
    if (scope == 'cette') {
      await _supa.from('plan_taches').update(update).inFilter('id', tacheIds);
    } else if (scope == 'suivantes') {
      await _supa.from('plan_taches').update(update)
          .eq('etape_id', etapeId!).eq('uid_eleveur', uid!)
          .gte('date_prevue', dateRef!);
    } else {
      await _supa.from('plan_taches').update(update)
          .eq('etape_id', etapeId!).eq('uid_eleveur', uid!);
    }
  }

  // ── Reporter une tâche à J+1 ─────────────────────────────────────────────────
  static Future<void> reporterTache(String tacheId, DateTime dateActuelle) async {
    final newDate = dateActuelle.add(const Duration(days: 1));
    final newDateStr = newDate.toIso8601String().split('T').first;

    final row = await _supa.from('plan_taches').select().eq('id', tacheId).single();
    await _supa.from('plan_taches').update({ 'statut': 'reporte' }).eq('id', tacheId);
    final newRow = Map<String, dynamic>.from(row)
      ..remove('id')
      ..remove('created_at')
      ..['date_prevue']    = newDateStr
      ..['statut']         = 'en_attente'
      ..['valide_par']     = null
      ..['valide_par_profile_id'] = null
      ..['valide_at']      = null
      ..['notes_validation'] = null;
    await _supa.from('plan_taches').insert(newRow);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _loadEtapes(String templateId) async {
    final rows = await _supa.from('plan_template_etapes').select().eq('template_id', templateId).order('ordre');
    return List<Map<String, dynamic>>.from(rows);
  }

  static List<int> _weekOffsets(int nbFois) => switch (nbFois) {
    1 => [0],
    2 => [0, 3],          // lundi + jeudi
    3 => [0, 2, 4],       // lundi + mercredi + vendredi
    _ => List.generate(nbFois, (i) => i),
  };

  static String _buildLabel(String typeActe, String produit, String dosage, String desc) {
    // Animal name stored separately in 'animal_nom' column — not embedded in label
    final parts = <String>[
      if (typeActe.isNotEmpty) _acteLabel(typeActe),
      if (produit.isNotEmpty) produit,
      if (dosage.isNotEmpty) '($dosage)',
    ];
    if (parts.isEmpty && desc.isNotEmpty) parts.add(desc);
    return parts.join(' ');
  }

  static String _cibleLabel(String cibleType, String? espece) {
    final e = espece != null && espece.isNotEmpty ? ' ($espece)' : '';
    return switch (cibleType) {
      'cheptel'  => 'Tout le cheptel$e',
      'males'    => 'Mâles$e',
      'femelles' => 'Femelles$e',
      _          => 'Protocole',
    };
  }

  static String _acteLabel(String type) => switch (type) {
    'vermifuge'       => 'Vermifuge',
    'vaccination'     => 'Vaccination',
    'antiparasitaire' => 'Antiparasitaire',
    'traitement'      => 'Traitement',
    'visite'          => 'Visite',
    'nettoyage'       => 'Nettoyage',
    'promenade'       => 'Promenade',
    'socialisation'   => 'Socialisation',
    'toilettage'      => 'Toilettage',
    'peignage'        => 'Peignage',
    _                 => type,
  };
}
