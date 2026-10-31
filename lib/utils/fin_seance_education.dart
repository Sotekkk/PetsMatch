// Éducateur : fin de séance d'un RDV — compte rendu de séance / bilan avec
// les exercices à faire et le programme de travail (PDF signé) et facture,
// envoyés au client en un seul e-mail, facture acquittée ; devis et facture
// préparés depuis le RDV. Miroir site : FinConsultationModal (metier
// « education ») + lib/seance-education.ts + DossierEducationModal.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show CreerFacturePage, FacturePrefillLigne, facturePdfDepuisLigne;
import 'package:PetsMatch/pages/pro/education_devis_page.dart' show DevisPage, DevisPrefill;
import 'package:PetsMatch/pages/pro/ordonnance_pdf.dart' show compteRenduPdfBytes, ageAnimal, sexeAnimal;
import 'package:PetsMatch/pages/pro/transmission_document.dart' show envoyerDocumentsParEmail;
import 'package:PetsMatch/utils/rdv_animaux.dart' show animauxDetailRdv;
import 'package:PetsMatch/utils/document_pro.dart' show comptesRendusProDuRdv, lignesCrsPro, ajouterPiecesCrsPro;
import 'package:PetsMatch/utils/signature_pro.dart' show maSignaturePro, octetsSignature;
import 'package:PetsMatch/widgets/rich_text_view.dart' show richTextToPlain;

const _teal = Color(0xFF0C5C6C);
const _statutObjectif = {'a_travailler': 'à travailler', 'en_cours': 'en cours', 'acquis': 'acquis'};

String _v(dynamic x) => (x ?? '').toString().trim();

/// Coordonnées du client d'un RDV (compte : réservées au pro du RDV ; sinon saisies).
Future<Map<String, String>> _client(Map<String, dynamic> rdv) async {
  Map? cc;
  try { cc = await Supabase.instance.client.rpc('pm_contact_client_rdv', params: {'p_rdv_id': rdv['id'].toString()}) as Map?; } catch (_) {}
  String p(List<dynamic> l) => l.map(_v).firstWhere((x) => x.isNotEmpty, orElse: () => '');
  return {
    'prenom': p([cc?['prenom']]), 'nom': p([cc?['nom'], rdv['client_nom_manuel']]),
    'email': p([cc?['email'], rdv['client_email_manuel']]), 'tel': p([cc?['telephone'], rdv['client_telephone_manuel']]),
    'rue': p([cc?['rue']]), 'cp': p([cc?['code_postal']]), 'ville': p([cc?['ville']]),
  };
}

/// Devis préparé depuis le RDV (client, animal, prestation) ; retour au dossier ensuite.
Future<void> devisDepuisRdv(BuildContext context, Map<String, dynamic> rdv, {String animalNom = ''}) async {
  final c = await _client(rdv);
  if (!context.mounted) return;
  final motif = _v(rdv['motif']);
  // Plusieurs animaux : une ligne par animal (son cours, son prix).
  final detail = animauxDetailRdv(rdv);
  await Navigator.push(context, MaterialPageRoute(builder: (_) => DevisPage(prefill: DevisPrefill(
    animalId: rdv['animal_id']?.toString(), clientUid: rdv['client_uid']?.toString(), clientProfileId: rdv['client_profile_id']?.toString(),
    clientNom: c['nom'], clientPrenom: c['prenom'], clientEmail: c['email'], clientTel: c['tel'], rdvId: rdv['id'].toString(),
    lignes: detail.isNotEmpty
        ? [for (final a in detail) {
            'description': [_v(a['motif']), _v(a['nom'])].where((x) => x.isNotEmpty).join(' — '),
            'quantite': 1, 'prix_unitaire': (a['prix'] as num?)?.toDouble() ?? 0,
          }]
        : motif.isEmpty ? const [] : [{
      'description': [motif, animalNom].where((x) => x.isNotEmpty).join(' — '),
      'quantite': 1, 'prix_unitaire': (rdv['prix_calcule'] as num?)?.toDouble() ?? 0,
    }],
  ))));
}

/// Facture préparée depuis le RDV ; retour au dossier ensuite.
Future<void> factureDepuisRdv(BuildContext context, Map<String, dynamic> rdv, {String animalNom = ''}) async {
  final c = await _client(rdv);
  if (!context.mounted) return;
  final d = DateTime.tryParse(_v(rdv['date_heure']))?.toLocal();
  final seanceDu = d == null ? '' : 'Séance du ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  final detail = animauxDetailRdv(rdv);
  await Navigator.push(context, MaterialPageRoute(builder: (_) => CreerFacturePage(
    clientPrenom: c['prenom'], clientNom: c['nom'], clientEmail: c['email'], clientTel: c['tel'],
    clientRue: c['rue'], clientCp: c['cp'], clientVille: c['ville'],
    // Plusieurs animaux : une ligne par animal (son cours, son prix).
    lignesPrefill: detail.isNotEmpty
        ? [for (final a in detail) FacturePrefillLigne(
            designation: [_v(a['motif']).isEmpty ? 'Séance d’éducation' : _v(a['motif']), _v(a['nom'])].where((x) => x.isNotEmpty).join(' — '),
            description: seanceDu, prixTTC: (a['prix'] as num?)?.toDouble() ?? 0,
          )]
        : [FacturePrefillLigne(
      designation: [_v(rdv['motif']).isEmpty ? 'Séance d’éducation' : _v(rdv['motif']), animalNom].where((x) => x.isNotEmpty).join(' — '),
      description: seanceDu,
      prixTTC: (rdv['prix_calcule'] as num?)?.toDouble() ?? 0,
    )],
    sourceRdvId: rdv['id'].toString(), sourceAnimalId: rdv['animal_id']?.toString(),
    clientUid: rdv['client_uid']?.toString(), clientProfileId: rdv['client_profile_id']?.toString(),
  )));
}

/// Texte du PDF : paragraphes « Titre : … », puis exercices et programme.
Future<String> _contenu(Map<String, dynamic> s, String? proProfileId) async {
  final supa = Supabase.instance.client;
  String p(dynamic t) => richTextToPlain(t?.toString()).trim();
  final l = <String>[];
  if (s['type'] == 'bilan') {
    if (p(s['bilan_motif']).isNotEmpty) l.addAll(['Motif : ${p(s['bilan_motif'])}', '']);
    if (p(s['contenu']).isNotEmpty) l.addAll(['Observations : ${p(s['contenu'])}', '']);
    if (p(s['bilan_recommandation']).isNotEmpty) l.addAll(['Recommandation : ${p(s['bilan_recommandation'])}', '']);
    if (s['bilan_nb_seances_estime'] != null) l.addAll(['Nombre de séances estimé : ${s['bilan_nb_seances_estime']}', '']);
  } else {
    if (p(s['contenu']).isNotEmpty) l.addAll(['Compte rendu : ${p(s['contenu'])}', '']);
    if (p(s['exercices_conseilles']).isNotEmpty) l.addAll(['Exercices conseillés : ${p(s['exercices_conseilles'])}', '']);
  }
  final aid = s['animal_id']?.toString();
  try {
    final ex = await supa.from('exercices_attribues').select('titre_snapshot, cadence')
        .or('progression_id.eq.${s['id']}${aid != null ? ',and(animal_id.eq.$aid,statut.in.(a_faire,en_cours))' : ''}');
    final liste = List<Map<String, dynamic>>.from(ex as List);
    if (liste.isNotEmpty) {
      l.add('Exercices à faire : ${liste.length}');
      for (final e in liste) {
        l.add('- ${_v(e['titre_snapshot']).isEmpty ? 'Exercice' : _v(e['titre_snapshot'])}${_v(e['cadence']).isEmpty ? '' : ' (${_v(e['cadence'])})'}');
      }
      l.add('');
    }
    if (aid != null) {
      var q = supa.from('education_objectifs').select('libelle, statut').eq('animal_id', aid);
      if ((proProfileId ?? '').isNotEmpty) q = q.eq('pro_profile_id', proProfileId!);
      final ob = List<Map<String, dynamic>>.from(await q.order('ordre', ascending: true) as List);
      if (ob.isNotEmpty) {
        l.add('Programme de travail : ${ob.length} objectif${ob.length > 1 ? 's' : ''}');
        for (final o in ob) {
          l.add('- ${_v(o['libelle'])}${o['statut'] != null ? ' (${_statutObjectif[o['statut']] ?? o['statut']})' : ''}');
        }
      }
    }
  } catch (_) {}
  return l.join('\n');
}

/// PDF de fin de séance (compte rendu + exercices + programme), signé.
Future<Uint8List> pdfSeanceEducation(Map<String, dynamic> s, {String? proProfileId, String proprietaire = ''}) async {
  final supa = Supabase.instance.client;
  final pro = (proProfileId ?? '').isEmpty ? null : await supa.from('user_profiles_complet')
      .select('nom, firstname, lastname, rue_pro, code_postal_pro, ville_pro, rue, code_postal, ville, phone_number, phone, email_contact')
      .eq('id', proProfileId!).maybeSingle();
  final aid = s['animal_id']?.toString();
  final a = aid == null ? null : await supa.from('animaux')
      .select('nom, espece, race, sexe, date_naissance, age_estime, identification').eq('id', aid).maybeSingle();
  final adresse = (_v(pro?['rue_pro']).isNotEmpty || _v(pro?['ville_pro']).isNotEmpty)
      ? [_v(pro?['rue_pro']), '${_v(pro?['code_postal_pro'])} ${_v(pro?['ville_pro'])}'.trim()]
      : [_v(pro?['rue']), '${_v(pro?['code_postal'])} ${_v(pro?['ville'])}'.trim()];
  return compteRenduPdfBytes(
    cliniqueNom: _v(pro?['nom']).isNotEmpty ? _v(pro?['nom']) : 'Éducateur canin',
    cliniqueAdresse: adresse.where((x) => x.isNotEmpty).join(', '),
    cliniqueTel: _v(pro?['phone_number']).isNotEmpty ? _v(pro?['phone_number']) : _v(pro?['phone']),
    cliniqueEmail: _v(pro?['email_contact']),
    praticien: '${_v(pro?['firstname'])} ${_v(pro?['lastname'])}'.trim(),
    animalNom: _v(a?['nom']).isEmpty ? 'Animal' : _v(a?['nom']),
    animalEspeceRace: [_v(a?['espece']), _v(a?['race'])].where((x) => x.isNotEmpty).join(' · '),
    animalSexe: sexeAnimal(a?['sexe']), animalAge: ageAnimal(a?['date_naissance'], a?['age_estime']),
    animalIdentification: _v(a?['identification']), proprietaire: proprietaire,
    contenu: await _contenu(s, proProfileId),
    date: DateTime.tryParse(_v(s['date_seance']).isNotEmpty ? _v(s['date_seance']) : _v(s['created_at'])),
    signature: octetsSignature(await maSignaturePro()),
    titre: s['type'] == 'bilan' ? 'BILAN COMPORTEMENTAL' : 'COMPTE RENDU DE SÉANCE', prefixePraticien: '', libelleAnimal: 'Animal',
  );
}

/// Fenêtre de fin de séance d'un RDV éducateur.
Future<void> finSeanceEducation(BuildContext context, Map<String, dynamic> rdv, {String animalNom = '', String clientNom = ''}) async {
  final supa = Supabase.instance.client;
  final rdvId = rdv['id'].toString();
  final pid = rdv['pro_profile_id']?.toString();
  List<Map<String, dynamic>> seances = [];
  Map<String, dynamic>? facture;
  try {
    seances = List<Map<String, dynamic>>.from(await supa.from('education_progression').select().eq('rdv_id', rdvId).order('created_at', ascending: true) as List)
        .where((s) => s['statut'] != 'brouillon').toList();
  } catch (_) {}
  try {
    final f = await supa.from('factures').select().eq('source_rdv_id', rdvId).neq('statut', 'annulee')
        .order('created_at', ascending: false).limit(1);
    if ((f as List).isNotEmpty) facture = Map<String, dynamic>.from(f.first as Map);
  } catch (_) {}
  // Mes comptes rendus chargés (photo / PDF) : envoyés à la place des comptes rendus rédigés.
  final crsPro = await comptesRendusProDuRdv(rdvId);
  // Plusieurs animaux : chaque compte rendu porte le nom de son animal.
  final nomsAnimaux = {for (final a in animauxDetailRdv(rdv)) a['id'].toString(): _v(a['nom'])};
  String nomDe(Map<String, dynamic> s) => nomsAnimaux[s['animal_id']?.toString()] ?? animalNom;
  if (!context.mounted) return;
  final coches = <String, bool>{
    for (final s in seances) 'edu:${s['id']}': crsPro.isEmpty,
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
          Text('Envoyer au client par e-mail', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
          if (seances.isEmpty && facture == null && crsPro.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucun document pour ce rendez-vous : rédigez d’abord le compte rendu.', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
          for (final s in seances)
            ligne('edu:${s['id']}', '${s['type'] == 'bilan' ? 'Bilan' : 'Compte rendu de séance'}${nomDe(s).isEmpty ? '' : ' — ${nomDe(s)}'}',
                'Avec les exercices et le programme de travail, signé'),
          ...lignesCrsPro(ctx, setM, rdvId: rdvId, crsPro: crsPro, coches: coches, ligne: ligne, estGenere: (k) => k.startsWith('edu:')),
          if (facture != null)
            ligne('fac:${facture['id']}', 'Facture ${facture['numero_affichage'] ?? ''}',
                '${((facture['total_ttc'] as num?) ?? 0).toStringAsFixed(2)} € TTC${dejaPayee ? ' — acquittée' : ''}'),
          if (facture == null) ...[
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'facture'),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Préparer la facture', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
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
      await factureDepuisRdv(context, rdv, animalNom: animalNom);
      // Facture faite : la fin de séance reprend (envoi, acquittée).
      if (context.mounted) await finSeanceEducation(context, rdv, animalNom: animalNom, clientNom: clientNom);
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
    final nomA = animalNom.isEmpty ? 'animal' : animalNom;
    for (final s in seances) {
      if (coches['edu:${s['id']}'] != true) continue;
      pieces.add((type: 'compte_rendu', nomFichier: '${s['type'] == 'bilan' ? 'Bilan' : 'Compte-rendu-seance'}-$nomA.pdf',
          bytes: await pdfSeanceEducation(s, proProfileId: pid, proprietaire: clientNom)));
    }
    await ajouterPiecesCrsPro(pieces, crsPro, coches);
    if (facture != null && coches['fac:${facture['id']}'] == true) {
      pieces.add((type: 'facture', nomFichier: 'Facture-${facture['numero_affichage'] ?? ''}${facture['statut'] == 'payee' ? '-acquittee' : ''}.pdf',
          bytes: await facturePdfDepuisLigne(facture)));
    }
    if (pieces.isEmpty || !context.mounted) return;
    final c = await _client(rdv);
    if (!context.mounted) return;
    final envoye = await envoyerDocumentsParEmail(context, pieces: pieces, animalNom: animalNom, destinataireNom: clientNom,
        emailParDefaut: (c['email'] ?? '').isNotEmpty ? c['email'] : null, animalId: rdv['animal_id']?.toString());
    // La famille est prévenue dans l'appli à l'envoi (les comptes rendus d'un
    // RDV ne notifient pas à l'enregistrement).
    if (envoye) {
      final proNom = User_Info.nameElevage.isNotEmpty
          ? User_Info.nameElevage
          : [User_Info.firstname, User_Info.lastname].where((x) => x.isNotEmpty && x != 'none').join(' ');
      for (final s in seances.where((s) => coches['edu:${s['id']}'] == true)) {
        final owner = s['owner_uid']?.toString();
        final aid = s['animal_id']?.toString();
        if (owner == null || aid == null) continue;
        final bilan = s['type'] == 'bilan';
        try {
          final an = await supa.from('animaux').select('nom').eq('id', aid).maybeSingle();
          final pp = await supa.from('animaux_proprietes').select('profile_id_proprio').eq('animal_id', aid)
              .isFilter('date_fin', null).order('date_debut', ascending: false).limit(1).maybeSingle();
          final nomA = an?['nom']?.toString() ?? 'votre animal';
          await supa.from('notifications').insert({
            'uid': owner, 'type': bilan ? 'education_bilan' : 'education_rapport',
            'title': '${bilan ? 'Bilan comportemental' : 'Rapport de séance'} — $nomA',
            'body': '${proNom.isEmpty ? 'Votre éducateur' : proNom} a envoyé ${bilan ? 'le bilan' : 'le compte rendu de la séance'} pour $nomA.',
            if (pp?['profile_id_proprio'] != null) 'profile_id': pp!['profile_id_proprio'],
            'data': {'animalId': aid, 'animalNom': nomA, 'url': '/mes-animaux/$aid?tab=education'},
            'read': false,
          });
        } catch (_) {}
      }
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Impossible : $e', style: const TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating));
  }
}
