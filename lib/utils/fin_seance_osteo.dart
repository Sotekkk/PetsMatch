// Ostéo / kiné (profil « sante ») : fin de séance d'un RDV — compte(s)
// rendu(s) de séance (suivis_morpho finalisés) et facture envoyés au
// propriétaire en un seul e-mail, facture marquée acquittée ; facture
// préparée depuis les tarifs ostéo (tarifs_sante) si elle n'existe pas.
// Miroir site : FinConsultationModal (metier « sante ») + lib/seance-osteo.ts.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/pages/animaux/morpho/morpho_pdf_service.dart' show morphoSuiviPdfBytes;
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show CreerFacturePage, FacturePrefillLigne, facturePdfDepuisLigne;
import 'package:PetsMatch/pages/pro/transmission_document.dart' show envoyerDocumentsParEmail;
import 'package:PetsMatch/utils/document_pro.dart' show comptesRendusProDuRdv, lignesCrsPro, ajouterPiecesCrsPro;

const _teal = Color(0xFF0C5C6C);

/// Séances finalisées du RDV (à défaut, celles de ses animaux ce jour-là par ce profil).
Future<List<Map<String, dynamic>>> seancesDuRdv(String rdvId) async {
  final supa = Supabase.instance.client;
  var rows = List<Map<String, dynamic>>.from(await supa.from('suivis_morpho').select().eq('rdv_id', rdvId).order('created_at'));
  if (rows.isEmpty) {
    final r = await supa.from('rdv').select('animal_id, animaux_ids, date_heure, pro_profile_id').eq('id', rdvId).maybeSingle();
    if (r != null && r['date_heure'] != null && r['pro_profile_id'] != null) {
      final ids = [
        for (final x in ((r['animaux_ids'] is List && (r['animaux_ids'] as List).isNotEmpty) ? r['animaux_ids'] as List : [r['animal_id']]))
          if (x != null) x.toString(),
      ];
      if (ids.isNotEmpty) {
        rows = List<Map<String, dynamic>>.from(await supa.from('suivis_morpho').select().inFilter('animal_id', ids)
            .eq('pro_profile_id', r['pro_profile_id']).isFilter('rdv_id', null)
            .eq('date', r['date_heure'].toString().substring(0, 10)).order('created_at'));
      }
    }
  }
  return rows.where((s) => s['statut'] == 'finalise' || (s['statut'] == null && s['notifie_a'] != null)).toList();
}

/// PDF du compte rendu de séance (même PDF que « Exporter » sur la séance).
Future<Uint8List> pdfSeance(Map<String, dynamic> suivi) async {
  final supa = Supabase.instance.client;
  final id = suivi['id'].toString();
  String s(dynamic v) => v?.toString().trim() ?? '';
  final res = await Future.wait([
    supa.from('suivis_morpho_photos').select().eq('suivi_id', id),
    supa.from('suivis_morpho_points').select().eq('suivi_id', id),
    supa.from('suivis_morpho_observations').select().eq('suivi_id', id),
    supa.from('suivis_morpho_mouvements').select().eq('suivi_id', id),
  ]);
  var exercices = <Map<String, dynamic>>[];
  try {
    exercices = List<Map<String, dynamic>>.from(await supa.from('suivis_morpho_exercices').select().eq('suivi_id', id).order('ordre'));
  } catch (_) {}
  Map<String, dynamic>? animal;
  if (suivi['animal_id'] != null) {
    animal = await supa.from('animaux').select('nom, espece, race, sexe, date_naissance, identification')
        .eq('id', suivi['animal_id']).maybeSingle();
  }
  Map<String, dynamic>? p;
  if (suivi['pro_profile_id'] != null) {
    p = await supa.from('user_profiles_complet')
        .select('nom, firstname, lastname, adresse, rue, code_postal, ville, phone, telephone, phone_number, email_contact, profession_pro')
        .eq('id', suivi['pro_profile_id']).maybeSingle();
  }
  final nomPro = s(p?['nom']).isNotEmpty ? s(p?['nom']) : '${s(p?['firstname'])} ${s(p?['lastname'])}'.trim();
  return morphoSuiviPdfBytes(
    suivi: suivi,
    animal: animal ?? {'nom': suivi['animal_nom_libre'] ?? 'Animal', 'espece': suivi['espece_libre'] ?? ''},
    pro: {
      'nom': nomPro, 'profession': s(p?['profession_pro']),
      'adresse': s(p?['adresse']).isNotEmpty ? s(p?['adresse'])
          : [p?['rue'], p?['code_postal'], p?['ville']].map(s).where((x) => x.isNotEmpty).join(' '),
      'tel': [p?['phone_number'], p?['phone'], p?['telephone']].map(s).firstWhere((x) => x.isNotEmpty, orElse: () => ''),
      'email': s(p?['email_contact']),
    },
    photos: List<Map<String, dynamic>>.from(res[0] as List),
    points: List<Map<String, dynamic>>.from(res[1] as List),
    observations: List<Map<String, dynamic>>.from(res[2] as List),
    mouvements: List<Map<String, dynamic>>.from(res[3] as List),
    exercices: exercices,
  );
}

/// Lignes de facture : « Séance », « Consultation (bilan) », « Supplément
/// déplacement » une fois si à domicile / extérieur ; nom de l'animal devant
/// chaque ligne s'ils sont plusieurs. Prix TTC de la grille ostéo.
Future<List<FacturePrefillLigne>> lignesFactureOsteo(String proProfileId, List<Map<String, dynamic>> seances, Map<String, String> noms) async {
  Map<String, dynamic> tarifs = {};
  try {
    final p = await Supabase.instance.client.from('user_profiles_complet').select('tarifs_sante').eq('id', proProfileId).maybeSingle();
    if (p?['tarifs_sante'] is Map) tarifs = Map<String, dynamic>.from(p!['tarifs_sante'] as Map);
  } catch (_) {}
  double? tarif(String k) => double.tryParse('${tarifs[k] ?? ''}'.replaceAll(',', '.'));
  FacturePrefillLigne ligne(String d, double? ttc) => FacturePrefillLigne(designation: d, prixTTC: ttc, quantite: 1);
  final plusieurs = {for (final s in seances) s['animal_id']}.length > 1;
  final lignes = [
    for (final s in seances)
      () {
        final bilan = (s['type_suivi']?.toString() ?? '').startsWith('bilan');
        final pre = plusieurs && s['animal_id'] != null ? '${noms[s['animal_id'].toString()] ?? 'Animal'} — ' : '';
        return ligne('$pre${bilan ? 'Consultation (bilan)' : 'Séance'}', tarif(bilan ? 'consultation' : 'seance'));
      }(),
  ];
  if (seances.any((s) => s['lieu'] == 'exterieur' || s['lieu'] == 'domicile')) {
    lignes.add(ligne('Supplément déplacement', tarif('deplacement')));
  }
  return lignes;
}

/// Fenêtre de fin de séance d'un RDV.
Future<void> finSeanceOsteo(BuildContext context, {required String rdvId, String? proProfileId}) async {
  final supa = Supabase.instance.client;
  final seances = await seancesDuRdv(rdvId);
  Map<String, dynamic>? facture;
  try {
    final f = await supa.from('factures').select().eq('source_rdv_id', rdvId).neq('statut', 'annulee')
        .order('created_at', ascending: false).limit(1);
    if ((f as List).isNotEmpty) facture = Map<String, dynamic>.from(f.first as Map);
  } catch (_) {}
  final ids = {for (final s in seances) if (s['animal_id'] != null) s['animal_id'].toString()}.toList();
  final noms = <String, String>{};
  if (ids.isNotEmpty) {
    for (final a in await supa.from('animaux').select('id, nom').inFilter('id', ids) as List) {
      noms[a['id'].toString()] = a['nom']?.toString() ?? '';
    }
  }
  final pro = proProfileId ?? (seances.isNotEmpty ? seances.first['pro_profile_id']?.toString() : null);
  // Mes comptes rendus chargés (photo / PDF) : envoyés à la place des comptes rendus de séance.
  final crsPro = await comptesRendusProDuRdv(rdvId);
  if (!context.mounted) return;
  final coches = <String, bool>{
    for (final s in seances) 'seance:${s['id']}': crsPro.isEmpty,
    for (final d in crsPro) 'pro:${d['id']}': true,
    if (facture != null) 'fac:${facture['id']}': true,
  };
  final dejaPayee = facture?['statut'] == 'payee';
  var acquittee = false;
  var mode = 'Carte bancaire';
  final choix = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
      Widget ligne(String cle, String titre, [String? sous]) => CheckboxListTile(
            value: coches[cle] ?? false, dense: true, activeColor: _teal, contentPadding: EdgeInsets.zero,
            onChanged: (v) => setM(() => coches[cle] = v ?? false),
            title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: sous == null ? null : Text(sous, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
          );
      final nb = coches.values.where((v) => v).length;
      return SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Fin de séance', style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Envoyer au propriétaire par e-mail', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
          if (seances.isEmpty && facture == null && crsPro.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucun document pour ce rendez-vous : finalisez d’abord la séance.', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
          for (final s in seances)
            ligne('seance:${s['id']}', 'Compte rendu de séance — ${noms[s['animal_id']?.toString()] ?? s['animal_nom_libre'] ?? 'Animal'}'),
          ...lignesCrsPro(ctx, setM, rdvId: rdvId, crsPro: crsPro, coches: coches, ligne: ligne, estGenere: (k) => k.startsWith('seance:')),
          if (facture != null)
            ligne('fac:${facture['id']}', 'Facture ${facture['numero_affichage'] ?? ''}',
                '${((facture['total_ttc'] as num?) ?? 0).toStringAsFixed(2)} € TTC${dejaPayee ? ' — acquittée' : ''}'),
          if (facture == null && seances.isNotEmpty && pro != null) ...[
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'facture'),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Préparer la facture (tarifs de séance)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(foregroundColor: _teal),
            )),
          ],
          if (facture != null && !dejaPayee) ...[
            const SizedBox(height: 6),
            SwitchListTile(
              value: acquittee, activeThumbColor: _teal, contentPadding: EdgeInsets.zero, dense: true,
              onChanged: (v) => setM(() => acquittee = v),
              title: const Text('Facture acquittée (réglée aujourd’hui)', style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (acquittee) Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in const ['Carte bancaire', 'Espèces', 'Chèque', 'Virement'])
                ChoiceChip(label: Text(m, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)), selected: mode == m,
                    selectedColor: _teal.withValues(alpha: 0.2), onSelected: (_) => setM(() => mode = m)),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Fermer', style: TextStyle(fontFamily: 'Galey')))),
            if (acquittee) ...[
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, 'acquitter'),
                  child: const Text('Acquitter seulement', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5)))),
            ],
            const SizedBox(width: 8),
            Expanded(flex: 2, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
              onPressed: nb == 0 ? null : () => Navigator.pop(ctx, 'envoyer'),
              child: Text('Envoyer ($nb)', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ]),
        ]),
      ));
    }),
  );
  if (choix == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (choix == 'facture') {
      // Facture préparée depuis les tarifs ; client du RDV (coordonnées de facturation).
      final lignes = await lignesFactureOsteo(pro!, seances, noms);
      final r = await supa.from('rdv').select('client_uid, client_profile_id, client_nom_manuel, client_email_manuel, client_telephone_manuel')
          .eq('id', rdvId).maybeSingle();
      final animalRef = ids.isNotEmpty ? ids.first : null;
      String? vide(dynamic v) => (v?.toString().trim() ?? '').isEmpty ? null : v.toString().trim();
      String? prenom, nom = vide(r?['client_nom_manuel']), email = vide(r?['client_email_manuel']), tel = vide(r?['client_telephone_manuel']), rue, cp, ville;
      if (animalRef != null) {
        try {
          final j = await supa.rpc('pm_client_facturation', params: {
            'p_animal_id': animalRef, if (r?['client_profile_id'] != null) 'p_client_profile_id': r!['client_profile_id'],
          });
          if (j is Map && (vide(j['nom']) != null || vide(j['prenom']) != null)) {
            prenom = vide(j['prenom']); nom = vide(j['nom']); email = vide(j['email']); tel = vide(j['telephone']);
            rue = vide(j['rue']); cp = vide(j['code_postal']); ville = vide(j['ville']);
          }
        } catch (_) {}
      }
      if (!context.mounted) return;
      final listeNoms = noms.values.where((n) => n.isNotEmpty).join(', ');
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CreerFacturePage(
        clientPrenom: prenom, clientNom: nom, clientEmail: email, clientTel: tel,
        clientRue: rue, clientCp: cp, clientVille: ville,
        lignesPrefill: lignes,
        noteInitiale: 'Séance${seances.length > 1 ? 's' : ''} de ${listeNoms.isEmpty ? 'votre animal' : listeNoms}',
        sourceRdvId: rdvId, sourceAnimalId: animalRef,
        clientUid: r?['client_uid']?.toString(), clientProfileId: r?['client_profile_id']?.toString(),
      )));
      // Facture faite : la fin de séance reprend (envoi, acquittée).
      if (context.mounted) await finSeanceOsteo(context, rdvId: rdvId, proProfileId: pro);
      return;
    }
    if (facture != null && acquittee && !dejaPayee) {
      final maj = {'statut': 'payee', 'mode_paiement': mode, 'date_paiement': DateTime.now().toUtc().toIso8601String()};
      await supa.from('factures').update(maj).eq('id', facture['id']);
      facture = {...facture, ...maj};
    }
    if (choix != 'envoyer') {
      messenger.showSnackBar(const SnackBar(content: Text('Facture acquittée.', style: TextStyle(fontFamily: 'Galey')),
          behavior: SnackBarBehavior.floating));
      return;
    }
    final pieces = <({String type, String nomFichier, Uint8List bytes})>[];
    for (final s in seances) {
      if (coches['seance:${s['id']}'] != true) continue;
      final nomA = noms[s['animal_id']?.toString()] ?? s['animal_nom_libre']?.toString() ?? 'animal';
      pieces.add((type: 'compte_rendu', nomFichier: 'Compte-rendu-seance-$nomA.pdf', bytes: await pdfSeance(s)));
    }
    await ajouterPiecesCrsPro(pieces, crsPro, coches);
    if (facture != null && coches['fac:${facture['id']}'] == true) {
      pieces.add((type: 'facture', nomFichier: 'Facture-${facture['numero_affichage'] ?? ''}${facture['statut'] == 'payee' ? '-acquittee' : ''}.pdf',
          bytes: await facturePdfDepuisLigne(facture)));
    }
    if (pieces.isEmpty || !context.mounted) return;
    final ok = await envoyerDocumentsParEmail(context, pieces: pieces,
        animalNom: noms.values.where((n) => n.isNotEmpty).join(', '),
        emailParDefaut: (facture?['email_client'] ?? '').toString().isEmpty ? null : facture!['email_client'].toString(),
        animalId: ids.isNotEmpty ? ids.first : null);
    // Séances envoyées : marquées comme transmises au client.
    if (ok) {
      for (final s in seances) {
        if (coches['seance:${s['id']}'] == true && s['notifie_a'] == null) {
          await supa.from('suivis_morpho').update({'notifie_a': DateTime.now().toUtc().toIso8601String()}).eq('id', s['id']);
        }
      }
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Impossible : $e', style: const TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating));
  }
}
