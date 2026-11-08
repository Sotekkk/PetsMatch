// Pension — finalisation de l'arrivée ou du départ, par étapes (comme la fin
// de RDV des autres pros) :
//  1. Arrivée / départ enregistré (logement).
//  2. Contrat d'hébergement : préparé (route /api/pension/contrat), signé
//     d'office avec la signature enregistrée de la pension (signatures_pro ;
//     à défaut elle la dessine une fois), envoyé au client (appli si compte +
//     e-mail avec lien de signature sans compte). Au départ : état, relance.
//  3. Facture : à l'arrivée (acompte ou séjour, selon le règlement réglé dans
//     Tarifs) ou au départ (séjour), via la feuille de facturation du registre.
// Miroir site : components/pension/FinalisationSejourModal.tsx.
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/site_api.dart';
import 'package:PetsMatch/utils/signature_pro.dart';
import 'package:PetsMatch/utils/pension_facture_groupee.dart' show sejoursDesFactures;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/pages/pro/pension_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart' show PensionFacturationSheet;
import 'package:PetsMatch/pages/pro/toilettage_dossier_seance.dart' show signerContratAvecSignaturePro;
import 'package:PetsMatch/utils/document_pro.dart' show choisirDocumentPdf, creerContratProSejour, kTypeContratPro;
import 'package:PetsMatch/utils/client_pension.dart' show clientDuSejour;
import 'dart:typed_data';
import 'package:PetsMatch/utils/pension_impressions.dart' show imprimerFichesBox;

const _teal = Color(0xFF0C5C6C);
const _vert = Color(0xFF2E7D5E);
const _orange = Color(0xFFB45309);

/// Ouvre la finalisation (après l'enregistrement de l'arrivée ou du départ).
Future<void> finaliserSejourPension(BuildContext context, Map<String, dynamic> entree, {required bool arrivee, List<String> autresIds = const []}) =>
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FinalisationSheet(entree: entree, arrivee: arrivee, autresIds: autresIds),
    );

class _FinalisationSheet extends StatefulWidget {
  final Map<String, dynamic> entree;
  final bool arrivee;
  /// Arrivée / départ groupé : autres séjours du même client (un seul contrat, facture groupée).
  final List<String> autresIds;
  const _FinalisationSheet({required this.entree, required this.arrivee, this.autresIds = const []});
  @override
  State<_FinalisationSheet> createState() => _FinalisationSheetState();
}

class _FinalisationSheetState extends State<_FinalisationSheet> {
  final _supa = Supabase.instance.client;
  Map<String, dynamic>? _contrat; // id, token, statut, signe_pro, signe_client, client_email, client_a_compte
  bool? _facture;
  bool _aSignature = true, _parEmail = true, _envoi = false;
  String _solde = 'arrivee';
  // Essai : facturé ou non (Tarifs).
  bool _essaiFacture = false;
  double? _essaiPrix;
  bool get _estEssai => e['essai'] == true;
  double? _arrhes;
  String? _logementNom, _message;
  bool _erreur = false;
  // Contrat de la pension : son modèle (Tarifs) ou un fichier chargé pour ce séjour.
  Map<String, dynamic>? _modele;
  String _choixContrat = 'petsmatch';
  Uint8List? _fichier;

  Map<String, dynamic> get e => widget.entree;
  List<String> get _tousIds => [e['id'].toString(), ...widget.autresIds.where((i) => i != e['id'].toString())];
  List<String> _nomsGroupe = [];
  /// Protocoles du séjour : tâches planifiées (appliquées à l'arrivée) par protocole.
  Map<String, int>? _protocoles;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final pid = User_Info.activeProfileId;
    try {
      final doc = await _supa.from('documents_animaux').select('id, token, statut, metadata')
          .inFilter('pension_entree_id', _tousIds).inFilter('type', ['contrat_hebergement', kTypeContratPro])
          .order('created_at', ascending: false).limit(1).maybeSingle();
      if (doc != null) {
        final m = (doc['metadata'] as Map?) ?? {};
        _contrat = {
          'id': doc['id'], 'token': doc['token'], 'statut': doc['statut'] ?? 'brouillon',
          'signe_pro': (m['signature_eleveur']?.toString() ?? '').isNotEmpty,
          'signe_client': (m['signature_acquereur']?.toString() ?? '').isNotEmpty,
          'client_email': m['client_email'] ?? e['proprietaire_email'], 'client_a_compte': (m['client_uid']?.toString() ?? '').isNotEmpty,
        };
      }
    } catch (_) {}
    _aSignature = await maSignaturePro() != null;
    try {
      final tp = await _supa.from('plan_taches').select('plan_id, plans_actifs(template_id, plan_templates(nom))')
          .inFilter('pension_entree_id', _tousIds).neq('statut', 'fait');
      final m = <String, int>{};
      for (final x in tp) {
        final n = (((x['plans_actifs'] as Map?)?['plan_templates'] as Map?)?['nom'])?.toString() ?? 'Protocole';
        m[n] = (m[n] ?? 0) + 1;
      }
      _protocoles = m;
    } catch (_) { _protocoles = {}; }
    if (_tousIds.length > 1) {
      try {
        final gs = await _supa.from('pension_entrees').select('animal_nom').inFilter('id', _tousIds);
        _nomsGroupe = [for (final g in gs) g['animal_nom']?.toString() ?? 'Animal'];
      } catch (_) {}
    }
    try {
      final f = await _supa.from('factures').select('source_pension_entree_id, lignes, statut, type_facture')
          .eq('profile_id', pid).not('source_pension_entree_id', 'is', null);
      final legacy = await _supa.from('pension_factures').select('id').eq('entree_id', e['id'].toString()).limit(1);
      _facture = sejoursDesFactures(List<Map<String, dynamic>>.from(f as List)).contains(e['id'].toString()) || (legacy as List).isNotEmpty;
    } catch (_) { _facture = false; }
    try {
      final p = await _supa.from('user_profiles').select('tarifs_pension').eq('id', pid).maybeSingle();
      final ec = ((p?['tarifs_pension'] as Map?)?['essai'] as Map?) ?? {};
      _essaiFacture = ec['facture'] == true;
      _essaiPrix = (ec['prix'] as num?)?.toDouble();
      final reg = ((p?['tarifs_pension'] as Map?)?['reglement'] as Map?) ?? {};
      _solde = reg['solde'] == 'depart' ? 'depart' : 'arrivee';
      final a = (reg['arrhes_pct'] as num?)?.toDouble();
      _arrhes = a != null && a > 0 ? a : null;
    } catch (_) {}
    try {
      final md = await _supa.from('user_profiles').select('pension_contrat_modele').eq('id', pid).maybeSingle();
      final m = md?['pension_contrat_modele'];
      if (m is Map && (m['url']?.toString() ?? '').isNotEmpty) {
        _modele = Map<String, dynamic>.from(m);
        if (_contrat == null) _choixContrat = 'mien';
      }
    } catch (_) {}
    if ((e['logement_id']?.toString() ?? '').isNotEmpty) {
      try {
        final l = await _supa.from('enclos_chenil').select('nom').eq('id', e['logement_id'].toString()).maybeSingle();
        _logementNom = l?['nom']?.toString();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  /// Contrat de la pension (modèle ou fichier) : rattaché au séjour, signé
  /// d'office, notifié au client (appli) et envoyé par e-mail.
  Future<void> _monContratSigneEtEnvoye() async {
    if (_fichier == null && _modele == null) {
      setState(() { _erreur = true; _message = 'Chargez votre contrat (PDF ou photo).'; });
      return;
    }
    setState(() { _envoi = true; _message = null; _erreur = false; });
    try {
      final client = await clientDuSejour(e);
      final clientNom = client.nomComplet.isNotEmpty ? client.nomComplet : (e['proprietaire_nom']?.toString() ?? '');
      final titre = "Contrat d'hébergement — ${e['animal_nom'] ?? ''}";
      final doc = await creerContratProSejour(
        entreeId: e['id'].toString(), animalId: e['animal_id']?.toString(), proProfileId: User_Info.activeProfileId,
        titre: titre, clientNom: clientNom, clientEmail: client.email.isEmpty ? null : client.email,
        clientUid: client.uid, clientProfileId: client.profileId,
        url: _fichier == null && _modele != null ? _modele!['url'].toString() : null, pdf: _fichier, entreeIds: _tousIds,
      );
      if (mounted) await signerContratAvecSignaturePro(context, doc.id);
      final d = await _supa.from('documents_animaux').select('metadata').eq('id', doc.id).maybeSingle();
      final signe = ((d?['metadata'] as Map?)?['signature_eleveur']?.toString() ?? '').isNotEmpty;
      final p = await _supa.from('user_profiles').select('nom').eq('id', User_Info.activeProfileId).maybeSingle();
      final pensionNom = p?['nom']?.toString() ?? 'La pension';
      if ((client.uid ?? '').isNotEmpty) {
        try {
          await _supa.from('notifications').insert({
            'uid': client.uid, if ((client.profileId ?? '').isNotEmpty) 'profile_id': client.profileId,
            'type': 'contrat_invite', 'title': 'Contrat à signer',
            'body': "$pensionNom vous envoie le contrat d'hébergement de ${e['animal_nom'] ?? 'votre animal'} : vérifiez et signez",
            'data': {'token': doc.token, 'url': '/signer-contrat/${doc.token}'}, 'read': false,
          });
        } catch (_) {}
      }
      var email = false;
      if (_parEmail && client.email.isNotEmpty) {
        try {
          final m = await http.post(Uri.parse('$kSiteBaseUrl/api/contrat/notify-email'), headers: await siteApiHeaders(), body: jsonEncode({
            'email': client.email, 'client_nom': clientNom, 'pro_nom': pensionNom, 'titre': titre,
            'signing_url': '$kSiteBaseUrl/signer-contrat/${doc.token}',
          }));
          email = m.statusCode == 200;
        } catch (_) {}
      }
      _contrat = {'id': doc.id, 'token': doc.token, 'statut': 'en_attente', 'signe_pro': signe, 'signe_client': false,
          'client_email': client.email, 'client_a_compte': (client.uid ?? '').isNotEmpty};
      _fichier = null;
      _message = [
        signe ? 'signé par vous' : 'à signer par vous',
        if ((client.uid ?? '').isNotEmpty) "envoyé au client dans l'appli",
        if (email) 'envoyé par e-mail à ${client.email}' else if (_parEmail && client.email.isNotEmpty) 'e-mail non envoyé',
      ].join(' · ');
      _aSignature = await maSignaturePro() != null;
    } catch (err) {
      _erreur = true;
      _message = err.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _envoi = false);
  }

  /// Prépare le contrat, le signe avec la signature enregistrée, l'envoie au client.
  Future<void> _contratSigneEtEnvoye() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Signature électronique : abonnement Premium (comme le registre).
    if (await PlanService.getPensionPlanCode(uid) != 'premium') {
      if (!mounted) return;
      await showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Signature — Plan Premium requis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text("La signature électronique de contrats est disponible avec l'abonnement Premium.", style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          FilledButton(onPressed: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const PensionAbonnementPage())); },
              child: const Text('Voir les plans')),
        ],
      ));
      return;
    }
    if (_choixContrat == 'mien' && _contrat == null) { await _monContratSigneEtEnvoye(); return; }
    setState(() { _envoi = true; _message = null; _erreur = false; });
    try {
      final r = await http.post(Uri.parse('$kSiteBaseUrl/api/pension/contrat'), headers: await siteApiHeaders(),
          body: jsonEncode({'entreeId': e['id'], 'entreeIds': _tousIds, 'transmettre': true}));
      final c = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200 || c['token'] == null) throw Exception(c['error'] ?? 'Contrat impossible');
      var signe = c['signe_pro'] == true;
      if (!signe && mounted) {
        await signerContratAvecSignaturePro(context, c['id'].toString());
        final d = await _supa.from('documents_animaux').select('metadata').eq('id', c['id'].toString()).maybeSingle();
        signe = ((d?['metadata'] as Map?)?['signature_eleveur']?.toString() ?? '').isNotEmpty;
      }
      var email = false;
      final adresse = c['client_email']?.toString() ?? '';
      if (_parEmail && adresse.isNotEmpty && c['signe_client'] != true) {
        try {
          final p = await _supa.from('user_profiles').select('nom').eq('id', User_Info.activeProfileId).maybeSingle();
          final m = await http.post(Uri.parse('$kSiteBaseUrl/api/contrat/notify-email'), headers: await siteApiHeaders(), body: jsonEncode({
            'email': adresse, 'client_nom': c['client_nom'] ?? '', 'pro_nom': p?['nom'] ?? 'Votre pension',
            'titre': "Contrat d'hébergement — ${e['animal_nom'] ?? ''}", 'signing_url': '$kSiteBaseUrl/signer-contrat/${c['token']}',
          }));
          email = m.statusCode == 200;
        } catch (_) {}
      }
      _contrat = {...c, 'signe_pro': signe};
      _message = [
        signe ? 'signé par vous' : 'à signer par vous',
        if (c['client_a_compte'] == true) "envoyé au client dans l'appli",
        if (email) 'envoyé par e-mail à $adresse' else if (_parEmail && adresse.isNotEmpty && c['signe_client'] != true) 'e-mail non envoyé',
      ].join(' · ');
      _aSignature = await maSignaturePro() != null;
    } catch (err) {
      _erreur = true;
      _message = err.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _envoi = false);
  }

  Future<void> _facturer() async {
    await showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true,
        backgroundColor: Colors.transparent, builder: (_) => PensionFacturationSheet(entree: e));
    await _charger();
  }

  Widget _etape(int n, String titre, bool ok, List<Widget> contenu) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? const Color(0xFFE8F5EE) : const Color(0xFFFFF4E5)),
            child: Icon(ok ? Icons.check : Icons.priority_high, size: 15, color: ok ? _vert : _orange),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n. $titre', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            ...contenu,
          ])),
        ]),
      );

  TextStyle get _petit => TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700);

  @override
  Widget build(BuildContext context) {
    final c = _contrat;
    final statut = c?['statut']?.toString();
    final contratFait = c != null && statut != 'brouillon';
    final libContrat = c == null ? 'À préparer'
        : statut == 'signe' ? 'Signé par les deux parties'
        : c['signe_pro'] == true && c['signe_client'] != true ? 'Signé par vous, en attente du client'
        : statut == 'brouillon' ? 'Brouillon, pas encore envoyé' : 'Envoyé, en attente de signature';
    final factureAttendue = _estEssai ? _essaiFacture : !widget.arrivee || _solde == 'arrivee' || _arrhes != null;
    final libFacture = _facture == null ? '…' : _facture! ? 'Facturé'
        : _estEssai ? (_essaiFacture ? 'Essai à facturer${_essaiPrix != null ? ' (${_essaiPrix!.toStringAsFixed(0)} €)' : ''}' : 'Essai non facturé (réglage Tarifs)')
        : widget.arrivee
            ? (_solde == 'arrivee' ? "Séjour à facturer (solde à l'arrivée)" : _arrhes != null ? 'Acompte de ${_arrhes!.toStringAsFixed(0)} % à facturer' : 'Facturation prévue au départ')
            : 'Séjour à facturer';
    final adresse = (c?['client_email'] ?? e['proprietaire_email'])?.toString() ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.arrivee ? "Finaliser l'arrivée" : 'Finaliser le départ',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18)),
        Text('${_nomsGroupe.length > 1 ? _nomsGroupe.join(', ') : e['animal_nom'] ?? 'Animal'}${(e['proprietaire_nom']?.toString() ?? '').isNotEmpty ? ' · ${e['proprietaire_nom']}' : ''}', style: _petit),
        if (_nomsGroupe.length > 1)
          Text('Un seul contrat et une facture groupée pour les ${_nomsGroupe.length} animaux.', style: _petit),
        const SizedBox(height: 16),
        _etape(1, widget.arrivee ? 'Arrivée enregistrée' : 'Départ enregistré', true, [
          Text(widget.arrivee ? (_logementNom != null ? 'Logement : $_logementNom' : 'Sans logement attribué')
              : 'Restitutions et règlement notés sur la fiche de départ.', style: _petit),
        ]),
        _etape(2, "Contrat d'hébergement", contratFait && c['signe_pro'] == true, [
          Text(libContrat, style: _petit),
          if (c == null) ...[
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final (v, lib) in [('petsmatch', 'Contrat PetsMatch'), ('mien', 'Mon contrat${_modele != null ? ' (${_modele!['nom'] ?? 'mon modèle'})' : ''}')])
                ChoiceChip(
                  label: Text(lib, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _choixContrat == v ? Colors.white : const Color(0xFF1F2A2E))),
                  selected: _choixContrat == v, showCheckmark: false, selectedColor: _teal, backgroundColor: Colors.white,
                  onSelected: (_) => setState(() => _choixContrat = v),
                ),
            ]),
            if (_choixContrat == 'petsmatch')
              Text('Rempli avec le séjour, les tarifs et le règlement.', style: _petit),
            if (_choixContrat == 'mien')
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_modele == null)
                    Text('Chargez votre contrat pour ce séjour, ou enregistrez votre modèle dans Tarifs pour ne plus avoir à le faire.', style: _petit),
                  TextButton.icon(
                    onPressed: () async {
                      final pdf = await choisirDocumentPdf(context);
                      if (pdf != null && mounted) setState(() => _fichier = pdf);
                    },
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: Text(_fichier != null ? 'Fichier chargé (changer)' : _modele != null ? 'Charger un autre fichier pour ce séjour' : 'Charger mon contrat (PDF ou photo)',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
                  ),
                ]),
              ),
          ],
          if (statut != 'signe') ...[
            if (!_aSignature)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(
                  'Aucune signature enregistrée : vous la dessinerez une fois, elle sera reprise d\'office ensuite.',
                  style: _petit.copyWith(color: _orange))),
            if (adresse.isNotEmpty && c?['signe_client'] != true)
              CheckboxListTile(
                value: _parEmail, onChanged: (v) => setState(() => _parEmail = v ?? false),
                dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: _teal,
                title: Text('Envoyer aussi par e-mail ($adresse)', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
              ),
            FilledButton(
              onPressed: _envoi ? null : _contratSigneEtEnvoye,
              style: FilledButton.styleFrom(backgroundColor: _teal),
              child: Text(_envoi ? 'Envoi…' : contratFait ? (widget.arrivee ? 'Renvoyer au client' : 'Relancer la signature') : 'Préparer, signer et envoyer',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
          ],
          if (_message != null)
            Text(_message!, style: _petit.copyWith(color: _erreur ? const Color(0xFFB3261E) : _vert)),
          if (c != null)
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContratSignaturePage(token: c['token'].toString()))),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: _teal),
              child: const Text('Voir le contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
        ]),
        if (widget.arrivee)
          _etape(3, 'Protocoles du séjour', true, [
            Text(_protocoles == null ? '…' : _protocoles!.isEmpty
                ? 'Aucun protocole de séjour ne concerne ce pensionnaire (Ma Pension > Protocoles).'
                : _protocoles!.entries.map((x) => '${x.key} (${x.value} tâche${x.value > 1 ? 's' : ''})').join(' · '), style: _petit),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () async {
                final p = await _supa.from('user_profiles').select('nom').eq('id', User_Info.activeProfileId).maybeSingle();
                await imprimerFichesBox(_tousIds, p?['nom']?.toString() ?? 'Pension');
              },
              icon: const Icon(Icons.print_outlined, size: 18),
              label: Text('Imprimer la fiche box${_tousIds.length > 1 ? 's' : ''}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(foregroundColor: _teal),
            ),
          ]),
        _etape(widget.arrivee ? 4 : 3, 'Facture', _facture == true || !factureAttendue, [
          Text(libFacture, style: _petit),
          if (_facture == false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: factureAttendue
                  ? FilledButton(onPressed: _facturer, style: FilledButton.styleFrom(backgroundColor: _teal),
                      child: Text(widget.arrivee && _solde != 'arrivee' ? "Facturer l'acompte" : 'Facturer le séjour',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)))
                  : OutlinedButton(onPressed: _facturer, style: OutlinedButton.styleFrom(foregroundColor: _teal),
                      child: const Text('Facturer maintenant', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600))),
            ),
        ]),
        OutlinedButton(onPressed: () => Navigator.pop(context),
            child: const Text('Terminer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
