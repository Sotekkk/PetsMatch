// Pet-sitter — « Fin de garde » (13/11/2026), comme la fin de séance du
// comportementaliste / du toiletteur : tout envoyer au client en un seul
// e-mail — compte rendu de la garde (PDF : passages, messages et photos
// compressées), facture (acquittée au besoin), acompte, forfait ; contrat et
// devis : lien de signature / consultation par e-mail. Clients sans compte
// compris (adresse saisie). Miroir site : components/garde/FinGardeModal.tsx.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show facturePdfDepuisLigne;
import 'package:PetsMatch/pages/pro/garde_acceptation.dart' show facturerGardeAcceptee;
import 'package:PetsMatch/pages/pro/toilettage_dossier_seance.dart' show coordonneesClientRdv, envoyerContratParEmail;
import 'package:PetsMatch/pages/pro/transmission_document.dart' show envoyerDocumentsParEmail;
import 'package:PetsMatch/utils/devis_rdv.dart' show devisDuRdv, titreDevisRdv, sousTitreDevisRdv, envoyerDevisCoches;
import 'package:PetsMatch/utils/document_pro.dart' show octetsUrlDocument;
import 'package:PetsMatch/utils/forfait_garde.dart' show acomptesGarde, rattacherForfaitGarde;
import 'package:PetsMatch/utils/rdv_animaux.dart' show idsAnimauxRdv;
import 'package:PetsMatch/pages/eleveur/animaux/contrat_pdf.dart' show contratGardePdfBytes;

const _teal = Color(0xFF0C5C6C);
const _pTeal = PdfColor.fromInt(0xFF0C5C6C);
const _pDark = PdfColor.fromInt(0xFF1E2025);
/// Photos du compte rendu : nombre et taille limités (e-mail ≤ 18 Mo).
const _maxPhotos = 24;

String _v(dynamic x) => (x ?? '').toString().trim();

Future<List<Map<String, dynamic>>> _passages(Map<String, dynamic> rdv) async {
  final serie = _v(rdv['serie_id']);
  if (serie.isEmpty) return [rdv];
  try {
    final l = await Supabase.instance.client.from('rdv').select().eq('serie_id', serie)
        .not('statut', 'in', '(annule,refuse)').order('date_heure');
    if ((l as List).isNotEmpty) {
      return [for (final r in l) {...Map<String, dynamic>.from(r as Map),
        for (final k in const ['_client_name', '_animal_nom']) if (rdv[k] != null) k: rdv[k]}];
    }
  } catch (_) {}
  return [rdv];
}

/// Compte rendu de la garde en PDF : passages, messages envoyés pendant la
/// garde et leurs photos (compressées).
Future<Uint8List> compteRenduGardePdf({
  required String proNom, required String clientNom, required String animaux,
  required List<Map<String, dynamic>> rdvs, required List<Map<String, dynamic>> messages,
}) async {
  Future<pw.Font> font(String p) async => pw.Font.ttf(await rootBundle.load('assets/font/$p'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(
      base: await font('NotoSans-Regular.ttf'), bold: await font('NotoSans-Bold.ttf'), italic: await font('NotoSans-Italic.ttf')));
  final fJour = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
  final fHeure = DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR');
  final dates = [for (final r in rdvs) DateTime.tryParse(_v(r['date_heure']))?.toLocal()].whereType<DateTime>().toList()..sort();
  final periode = dates.isEmpty ? '' : dates.length == 1 ? 'Le ${fJour.format(dates.first)}'
      : 'Du ${fJour.format(dates.first)} au ${fJour.format(dates.last)}';

  // Photos : téléchargées puis compressées (900 px, qualité 55).
  var nbPhotos = 0;
  final images = <String, pw.MemoryImage>{};
  for (final m in messages) {
    final url = _v(m['photo_url']);
    if (url.isEmpty || images.containsKey(url) || nbPhotos >= _maxPhotos) continue;
    final brut = await octetsUrlDocument(url);
    if (brut == null) continue;
    try {
      final c = await FlutterImageCompress.compressWithList(brut, minWidth: 900, minHeight: 900, quality: 55);
      images[url] = pw.MemoryImage(c);
      nbPhotos++;
    } catch (_) {}
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
    header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(proNom, style: pw.TextStyle(fontSize: 14, color: _pTeal, fontWeight: pw.FontWeight.bold)),
        pw.Text('COMPTE RENDU DE GARDE', style: pw.TextStyle(fontSize: 11, color: _pTeal, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.SizedBox(height: 6),
      pw.Divider(color: PdfColors.grey300),
    ]),
    footer: (c) => pw.Align(alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
    build: (_) => [
      pw.Text(animaux.isEmpty ? 'Garde' : animaux, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _pDark)),
      if (clientNom.isNotEmpty) pw.Text('Pour $clientNom', style: const pw.TextStyle(fontSize: 10, color: _pDark)),
      if (periode.isNotEmpty) pw.Text(periode, style: const pw.TextStyle(fontSize: 10, color: _pDark)),
      pw.Text('${rdvs.length} passage${rdvs.length > 1 ? 's' : ''} · ${(rdvs.first['motif'] ?? 'Prestation')}',
          style: const pw.TextStyle(fontSize: 10, color: _pDark)),
      pw.SizedBox(height: 14),
      if (messages.isEmpty)
        pw.Text("Aucun message envoyé pendant la garde.", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      for (final m in messages) ...[
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [
              pw.Text(DateTime.tryParse(_v(m['created_at'])) == null ? '' : fHeure.format(DateTime.parse(_v(m['created_at'])).toLocal()),
                  style: pw.TextStyle(fontSize: 9, color: _pTeal, fontWeight: pw.FontWeight.bold)),
              if (m['incident'] == true) pw.Text('  —  Incident', style: pw.TextStyle(fontSize: 9, color: PdfColors.red700, fontWeight: pw.FontWeight.bold)),
            ]),
            if (_v(m['note']).isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(_v(m['note']), style: const pw.TextStyle(fontSize: 10, color: _pDark, lineSpacing: 2)),
            ],
            if (images[_v(m['photo_url'])] != null) ...[
              pw.SizedBox(height: 6),
              pw.Center(child: pw.Image(images[_v(m['photo_url'])]!, height: 260, fit: pw.BoxFit.contain)),
            ],
          ]),
        ),
      ],
      if (messages.where((m) => _v(m['photo_url']).isNotEmpty).length > nbPhotos)
        pw.Text('Toutes les photos sont visibles dans l\'application PetsMatch (fiche de l\'animal, onglet Pension & Garde).',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    ],
  ));
  return doc.save();
}

/// Contrat de garde signé par les deux parties, en PDF (même modèle que
/// l'écran du contrat). Null si introuvable.
Future<Uint8List?> pdfContratGardeSigne(String docId) async {
  final supa = Supabase.instance.client;
  try {
    final doc = await supa.from('documents_animaux').select('metadata, animal_id, pro_profile_id, signe_le').eq('id', docId).maybeSingle();
    if (doc == null) return null;
    final meta = Map<String, dynamic>.from((doc['metadata'] as Map?) ?? {});
    String m(String k) => _v(meta[k]);
    final up = _v(doc['pro_profile_id']).isEmpty ? null : await supa.from('user_profiles_complet')
        .select('nom, firstname, lastname, siret, phone_number, numero_elevage, email_contact, adresse, rue, ville, code_postal, rue_pro, ville_pro, code_postal_pro')
        .eq('id', doc['pro_profile_id']).maybeSingle();
    final u = up ?? const <String, dynamic>{};
    final adressePro = [_v(u['rue_pro']), [_v(u['code_postal_pro']), _v(u['ville_pro'])].where((e) => e.isNotEmpty).join(' ')]
        .where((e) => e.isNotEmpty).join(', ');
    final adresse = adressePro.isNotEmpty ? adressePro
        : [_v(u['rue']), _v(u['code_postal']), _v(u['ville'])].where((e) => e.isNotEmpty).join(', ');
    final prestataire = <String, dynamic>{
      'name_elevage': u['nom'], 'firstname': u['firstname'], 'lastname': u['lastname'],
      'adress_elevage': adresse, 'adress': adresse, 'ville': u['ville'], 'ville_pro': u['ville_pro'],
      'siret': u['siret'], 'email': u['email_contact'], 'code_iso_elevage': '+33',
      'numero_elevage': u['numero_elevage'], 'phone_number': u['phone_number'],
    };
    Map<String, dynamic>? animal;
    if (_v(doc['animal_id']).isNotEmpty) {
      final a = await supa.from('animaux').select('*').eq('id', doc['animal_id']).maybeSingle();
      if (a != null) animal = {...Map<String, dynamic>.from(a), if (m('animal_nom').isNotEmpty) 'nom': m('animal_nom')};
    }
    return contratGardePdfBytes(
      animal: animal, prestataire: prestataire,
      clientNom: m('client_nom'), clientAdresse: m('client_adresse'), clientEmail: m('client_email'), clientTel: m('client_tel'),
      prestation: m('prestation'),
      datePrestation: DateTime.tryParse(m('date_visite').isNotEmpty ? m('date_visite') : m('date_prestation')),
      tarif: m('tarif'), notes: m('notes'),
      sigPrestataire: meta['signature_eleveur']?.toString(), sigClient: meta['signature_acquereur']?.toString(),
      villeSignature: m('ville_signature').isNotEmpty ? m('ville_signature') : (_v(u['ville']).isNotEmpty ? _v(u['ville']) : _v(u['ville_pro'])),
    );
  } catch (_) {
    return null;
  }
}

Future<void> finDeGarde(BuildContext context, Map<String, dynamic> rdv, {VoidCallback? onChanged}) async {
  final supa = Supabase.instance.client;
  final rdvs = await _passages(rdv);
  final ids = [for (final r in rdvs) _v(r['id'])].where((x) => x.isNotEmpty).toList();
  final first = rdvs.first;
  final clientUid = _v(rdv['client_uid']);
  final pid = User_Info.activeProfileId;

  Future<dynamic> sur(Future<dynamic> f) => f.then((v) => v, onError: (_) => null);
  final res = await Future.wait([
    sur(supa.from('factures').select().inFilter('source_rdv_id', ids).neq('statut', 'annulee').order('created_at', ascending: false)),
    sur(supa.from('pension_updates').select('note, photo_url, created_at, incident, rdv_id').inFilter('rdv_id', ids).order('created_at')),
    clientUid.isEmpty ? Future.value(null) : sur(supa.from('documents_animaux').select('id, token, statut, titre')
        .eq('uid_eleveur', rdv['pro_uid'] ?? '').eq('type', 'contrat_garde').eq('metadata->>client_uid', clientUid)
        .or(pid.isNotEmpty ? 'pro_profile_id.eq.$pid,pro_profile_id.is.null' : 'pro_profile_id.is.null')
        .order('created_at', ascending: false).limit(1)),
  ]);
  final factures = res[0] is List ? [for (final f in res[0] as List) Map<String, dynamic>.from(f as Map)] : <Map<String, dynamic>>[];
  var facture = factures.where((f) => f['type_facture'] != 'acompte' && f['type_facture'] != 'avoir').firstOrNull;
  // Un même message est posté sur chaque animal gardé : une seule fois ici.
  final vus = <String>{};
  final messages = <Map<String, dynamic>>[
    if (res[1] is List)
      for (final m in res[1] as List)
        if (vus.add('${_v((m as Map)['note'])}|${_v(m['photo_url'])}|${_v(m['created_at']).substring(0, _v(m['created_at']).length.clamp(0, 16))}'))
          Map<String, dynamic>.from(m),
  ];
  final contrat = res[2] is List && (res[2] as List).isNotEmpty ? Map<String, dynamic>.from((res[2] as List).first as Map) : null;
  final acomptes = await acomptesGarde(ids);
  final acomptesComplets = <Map<String, dynamic>>[];
  for (final a in acomptes) {
    try {
      final row = await supa.from('factures').select().eq('id', a['id']).maybeSingle();
      if (row != null) acomptesComplets.add(Map<String, dynamic>.from(row));
    } catch (_) {}
  }
  final fg = await rattacherForfaitGarde(rdvs);
  Map<String, dynamic>? factureForfait;
  if (fg != null && fg.facture) {
    try {
      final row = await supa.from('factures').select().eq('id', fg.souscription['facture_id'].toString()).maybeSingle();
      if (row != null && row['statut'] != 'annulee') factureForfait = Map<String, dynamic>.from(row);
    } catch (_) {}
  }
  final devis = <Map<String, dynamic>>[];
  for (final id in ids) {
    devis.addAll(await devisDuRdv(id));
  }
  if (!context.mounted) return;

  final animalNom = _v(rdv['_animal_nom']).isNotEmpty ? _v(rdv['_animal_nom']) : _v(rdv['animal_nom_manuel']);
  final clientNom = _v(rdv['_client_name']).isNotEmpty ? _v(rdv['_client_name']) : _v(rdv['client_nom_manuel']);
  final contratSigne = contrat?['statut'] == 'signe';
  final coches = <String, bool>{
    'cr': true,
    if (facture != null) 'fac': true,
    for (final a in acomptesComplets) 'acp:${a['id']}': false,
    if (factureForfait != null) 'ff': false,
    if (contrat != null) 'ctr': true,
    for (final d in devis) 'dev:${d['id']}': d['statut'] == 'brouillon',
  };
  final dejaPayee = facture?['statut'] == 'payee';
  var acquittee = false;
  var mode = 'Carte bancaire';
  final nbPhotos = messages.where((m) => _v(m['photo_url']).isNotEmpty).length;
  String eur(dynamic v) => '${((v as num?) ?? 0).toStringAsFixed(2).replaceAll('.', ',')} €';

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
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Fin de garde', style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _teal)),
          const SizedBox(height: 4),
          Text('Tout envoyer au client en un seul e-mail${clientNom.isNotEmpty ? ' ($clientNom)' : ''}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          ligne('cr', 'Compte rendu de la garde',
              '${rdvs.length} passage${rdvs.length > 1 ? 's' : ''} · ${messages.length} message${messages.length > 1 ? 's' : ''}'
              '${nbPhotos > 0 ? ' · ${nbPhotos > _maxPhotos ? _maxPhotos : nbPhotos} photo${nbPhotos > 1 ? 's' : ''} (compressées)' : ''}'),
          if (facture != null)
            ligne('fac', 'Facture ${facture['numero_affichage'] ?? ''}', '${eur(facture['total_ttc'])} TTC${dejaPayee ? ' — acquittée' : ''}'),
          if (facture == null) ...[
            const SizedBox(height: 4),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'facture'),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Préparer la facture', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(foregroundColor: _teal),
            )),
          ],
          for (final a in acomptesComplets)
            ligne('acp:${a['id']}', 'Facture d\'acompte ${a['numero_affichage'] ?? ''}',
                '${eur(a['total_ttc'])} TTC${a['statut'] == 'payee' ? ' — payée' : ''} · déjà envoyée à son émission'),
          if (factureForfait != null)
            ligne('ff', 'Facture du forfait ${factureForfait['numero_affichage'] ?? ''}',
                '${eur(factureForfait['total_ttc'])} TTC · déjà envoyée à son émission'),
          if (contrat != null)
            ligne('ctr', 'Contrat de garde', contratSigne ? 'Signé par les deux parties — version signée en PDF' : 'Pas encore signé — lien pour le signer'),
          for (final d in devis) ligne('dev:${d['id']}', titreDevisRdv(d), sousTitreDevisRdv(d)),
          if (facture != null && !dejaPayee) ...[
            SwitchListTile(
              value: acquittee, activeThumbColor: _teal, contentPadding: EdgeInsets.zero, dense: true,
              onChanged: (v) => setM(() => acquittee = v),
              title: const Text('Facture acquittée (réglée aujourd\'hui)', style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (acquittee) Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in const ['Carte bancaire', 'Espèces', 'Chèque', 'Virement'])
                ChoiceChip(label: Text(m, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)), selected: mode == m,
                    selectedColor: _teal.withValues(alpha: 0.2), onSelected: (_) => setM(() => mode = m)),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer', style: TextStyle(fontFamily: 'Galey')))),
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
  if (choix == 'facture') {
    await facturerGardeAcceptee(context, rdvs, acompte: false);
    if (context.mounted) await finDeGarde(context, rdv, onChanged: onChanged);
    return;
  }
  try {
    if (facture != null && acquittee && !dejaPayee) {
      final maj = {'statut': 'payee', 'mode_paiement': mode, 'date_paiement': DateTime.now().toUtc().toIso8601String()};
      await supa.from('factures').update(maj).eq('id', facture['id']);
      facture = {...facture, ...maj};
    }
    messenger.showSnackBar(const SnackBar(content: Text('Préparation des documents…', style: TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)));
    // Nom du profil pet-sitter (jamais celui du compte).
    var proNom = '';
    try {
      final ppid = _v(rdv['pro_profile_id']).isNotEmpty ? _v(rdv['pro_profile_id']) : pid;
      final pp = ppid.isEmpty ? null : await supa.from('user_profiles_complet').select('nom, firstname, lastname').eq('id', ppid).maybeSingle();
      proNom = _v(pp?['nom']).isNotEmpty ? _v(pp?['nom']) : '${_v(pp?['firstname'])} ${_v(pp?['lastname'])}'.trim();
    } catch (_) {}
    final coord = await coordonneesClientRdv(first);
    final emailClient = _v(coord['email']).isNotEmpty ? _v(coord['email']) : _v(facture?['email_client']);

    final pieces = <({String type, String nomFichier, Uint8List bytes})>[];
    if (coches['cr'] == true) {
      pieces.add((type: 'compte_rendu', nomFichier: 'Compte-rendu-garde${animalNom.isNotEmpty ? '-$animalNom' : ''}.pdf',
          bytes: await compteRenduGardePdf(proNom: proNom, clientNom: clientNom, animaux: animalNom, rdvs: rdvs, messages: messages)));
    }
    if (facture != null && coches['fac'] == true) {
      pieces.add((type: 'facture', nomFichier: 'Facture-${facture['numero_affichage'] ?? ''}${facture['statut'] == 'payee' ? '-acquittee' : ''}.pdf',
          bytes: await facturePdfDepuisLigne(facture)));
    }
    for (final a in acomptesComplets) {
      if (coches['acp:${a['id']}'] != true) continue;
      pieces.add((type: 'facture', nomFichier: 'Facture-${a['numero_affichage'] ?? ''}${a['statut'] == 'payee' ? '-acquittee' : ''}.pdf',
          bytes: await facturePdfDepuisLigne(a)));
    }
    if (factureForfait != null && coches['ff'] == true) {
      pieces.add((type: 'facture', nomFichier: 'Facture-forfait-${factureForfait['numero_affichage'] ?? ''}${factureForfait['statut'] == 'payee' ? '-acquittee' : ''}.pdf',
          bytes: await facturePdfDepuisLigne(factureForfait)));
    }
    // Contrat signé par les deux parties : la version signée en PDF (pas de lien).
    Uint8List? pdfContrat;
    if (contrat != null && contratSigne && coches['ctr'] == true) {
      pdfContrat = await pdfContratGardeSigne(_v(contrat['id']));
      if (pdfContrat != null) pieces.add((type: 'contrat', nomFichier: 'Contrat-de-garde-signe.pdf', bytes: pdfContrat));
    }
    var ok = true;
    if (pieces.isNotEmpty && context.mounted) {
      ok = await envoyerDocumentsParEmail(context, pieces: pieces, animalNom: animalNom, destinataireNom: clientNom,
          expediteur: proNom, emailParDefaut: emailClient.isEmpty ? null : emailClient,
          animalId: idsAnimauxRdv(first).firstOrNull, contexte: 'garde');
    }
    // Contrat : lien (signature ou consultation) par e-mail ; devis : lien de signature.
    if (contrat != null && coches['ctr'] == true && pdfContrat == null && _v(contrat['token']).isNotEmpty) {
      final envoye = await envoyerContratParEmail(first, _v(contrat['token']), titre: _v(contrat['titre']), nomClient: clientNom);
      if (!envoye) {
        messenger.showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating,
            content: Text('Contrat : pas d\'adresse e-mail pour ce client.', style: TextStyle(fontFamily: 'Galey'))));
      }
    }
    if (devis.any((d) => coches['dev:${d['id']}'] == true)) {
      await envoyerDevisCoches(devis, coches, rdvId: ids.first, proNom: proNom, emailSecours: emailClient.isEmpty ? null : emailClient);
    }
    if (!ok || !context.mounted) return;
    try {
      await supa.from('rdv').update({'documents_envoyes_le': DateTime.now().toUtc().toIso8601String()}).inFilter('id', ids);
    } catch (_) {}
    // Garde terminée ? (passages confirmés, déjà passés).
    final aClore = [for (final r in rdvs) if (r['statut'] == 'confirme' &&
        (DateTime.tryParse(_v(r['date_heure']))?.isBefore(DateTime.now()) ?? false)) _v(r['id'])];
    if (aClore.isNotEmpty && context.mounted) {
      final clore = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Documents envoyés', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text('Marquer ${aClore.length > 1 ? 'les ${aClore.length} passages' : 'la garde'} comme terminé${aClore.length > 1 ? 's' : 'e'} ?',
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terminer', style: TextStyle(color: _teal, fontWeight: FontWeight.w700))),
        ],
      ));
      if (clore == true) {
        await supa.from('rdv').update({'statut': 'termine', 'termine_at': DateTime.now().toUtc().toIso8601String()}).inFilter('id', aClore);
      }
    }
    onChanged?.call();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Impossible : $e', style: const TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating));
  }
}
