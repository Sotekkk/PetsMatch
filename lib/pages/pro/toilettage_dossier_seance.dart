// Toiletteur — dossier d'une séance (rdv), ouvert depuis l'agenda ou le
// tableau de bord : compte rendu de toilettage (fiche de séance + conseils de
// soin du pelage, partagé au propriétaire), contrat de prestation, facture.
// Pas de compte rendu vétérinaire ni d'ordonnance. Chaque module garde son
// statut. Miroir site : website/src/components/toilettage/DossierToilettageModal.tsx.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:PetsMatch/utils/site_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show FacturationPage, CreerFacturePage, FacturePrefillLigne;
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/toilettage_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_fiche_client_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_seance_page.dart';
import 'package:PetsMatch/widgets/contact_canaux.dart';
import 'package:PetsMatch/utils/consignes_rdv.dart';
import 'package:PetsMatch/pages/rdv_consignes_page.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);
const _muted = Color(0xFF6B7280);
const _vert = Color(0xFF2E7D5E);
const _ambre = Color(0xFFD97706);

String _jour(DateTime d) => DateFormat('EEE d MMM', 'fr_FR').format(d);
String _hm(DateTime d) => DateFormat('HH:mm').format(d);

/// Coordonnées du client : son profil PetsMatch (à jour), sinon celles saisies
/// sur le rendez-vous. Clés : prenom, nom, tel, email, rue, cp, ville.
Future<Map<String, String>> coordonneesClientRdv(Map<String, dynamic> rdv) async {
  final supa = Supabase.instance.client;
  final out = <String, String>{};
  try {
    final man = await supa.from('rdv').select('client_telephone_manuel, client_email_manuel').eq('id', rdv['id']).maybeSingle();
    final cp = rdv['client_profile_id']?.toString() ?? '';
    final prof = cp.isEmpty ? null
        : await supa.from('user_profiles_complet')
            .select('firstname, lastname, phone_number, phone, email_contact, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro')
            .eq('id', cp).maybeSingle();
    String premier(List<dynamic> v) => v.map((x) => (x ?? '').toString().trim()).firstWhere((x) => x.isNotEmpty, orElse: () => '');
    out['tel'] = premier([prof?['phone_number'], prof?['phone'], man?['client_telephone_manuel']]);
    out['email'] = premier([prof?['email_contact'], man?['client_email_manuel']]);
    out['prenom'] = premier([prof?['firstname']]);
    out['nom'] = premier([prof?['lastname']]);
    out['rue'] = premier([prof?['rue'], prof?['rue_pro']]);
    out['cp'] = premier([prof?['code_postal'], prof?['code_postal_pro']]);
    out['ville'] = premier([prof?['ville'], prof?['ville_pro']]);
  } catch (_) {}
  return out;
}

/// Client sans compte : envoie le contrat à signer par e-mail (lien à jeton,
/// sans compte) via /api/contrat/notify-email. Renvoie false si aucune adresse.
Future<bool> envoyerContratParEmail(Map<String, dynamic> rdv, String token, {String? titre, String? nomClient}) async {
  final coord = await coordonneesClientRdv(rdv);
  final email = (coord['email'] ?? '').trim();
  if (email.isEmpty) return false;
  var proNom = '';
  try {
    final p = await Supabase.instance.client.from('user_profiles_complet').select('nom, firstname, lastname')
        .eq('id', rdv['pro_profile_id'] ?? '').maybeSingle();
    proNom = (p?['nom']?.toString() ?? '').trim().isNotEmpty ? p!['nom'].toString().trim() : '${p?['firstname'] ?? ''} ${p?['lastname'] ?? ''}'.trim();
  } catch (_) {}
  try {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/contrat/notify-email'), headers: await siteApiHeaders(), body: jsonEncode({
      'email': email,
      'client_nom': [coord['prenom'], coord['nom']].where((x) => (x ?? '').isNotEmpty).join(' ').isNotEmpty
          ? [coord['prenom'], coord['nom']].where((x) => (x ?? '').isNotEmpty).join(' ') : (nomClient ?? rdv['_client_name']?.toString() ?? ''),
      'pro_nom': proNom.isEmpty ? 'Votre professionnel' : proNom,
      if (titre != null) 'titre': titre,
      'signing_url': '$kSiteBaseUrl/signer-contrat/$token',
    }));
    return r.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Prix TTC de la prestation : calculé à la réservation (grille espèce /
/// gabarit), sinon prix de base de la prestation.
Future<({String nom, double? prix})> prestationToilettageRdv(Map<String, dynamic> rdv) async {
  String nom = (rdv['motif']?.toString() ?? '').trim();
  double? prix = (rdv['prix_calcule'] as num?)?.toDouble();
  final pid = rdv['prestation_id']?.toString();
  if (pid != null && pid.isNotEmpty) {
    try {
      final p = await Supabase.instance.client.from('prestations_toilettage').select('nom, prix_base').eq('id', pid).maybeSingle();
      if ((p?['nom']?.toString() ?? '').isNotEmpty) nom = p!['nom'].toString();
      prix ??= (p?['prix_base'] as num?)?.toDouble();
    } catch (_) {}
  }
  return (nom: nom.isEmpty ? 'Prestation de toilettage' : nom, prix: prix);
}

/// Génère (ou rouvre) le contrat de prestation toilettage d'une séance et
/// l'envoie au client à la création. Formule payante requise (signature).
Future<void> genererContratToilettage(BuildContext context, Map<String, dynamic> rdv,
    {required String uid, required String profileId, String? clientNom, bool ouvrir = true}) async {
  final planCode = await PlanService.getPlanCode(uid, profilType: 'toilettage');
  if (!context.mounted) return;
  if (planCode == 'free') {
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Signature — formule payante requise', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: const Text('La signature électronique des contrats est disponible avec les formules payantes.',
          style: TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        FilledButton(onPressed: () {
          Navigator.pop(ctx);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ToilettageAbonnementPage()));
        }, child: const Text('Voir les formules')),
      ],
    ));
    return;
  }
  final supa = Supabase.instance.client;
  final existing = await supa.from('documents_animaux').select('token')
      .eq('rdv_id', rdv['id']).eq('type', 'contrat_prestation_toilettage').maybeSingle();
  String? token = existing?['token'] as String?;
  if (token == null) {
    final pr = await prestationToilettageRdv(rdv);
    final coord = await coordonneesClientRdv(rdv);
    final nomClient = clientNom ?? rdv['_client_name']?.toString() ?? '';
    final row = await supa.from('documents_animaux').insert({
      'uid_eleveur': uid,
      if (profileId.isNotEmpty) 'pro_profile_id': profileId,
      'animal_id': rdv['animal_id'],
      'rdv_id': rdv['id'],
      'type': 'contrat_prestation_toilettage',
      'titre': 'Contrat de prestation toilettage — $nomClient',
      'statut': 'en_attente',
      // client_uid / client_profile_id / client_email : le contrat remonte dans
      // « Mes contrats » du client (profil destinataire uniquement).
      'metadata': {
        'client_nom': nomClient,
        'client_uid': rdv['client_uid'],
        'client_profile_id': rdv['client_profile_id'],
        if ((coord['email'] ?? '').isNotEmpty) 'client_email': coord['email'],
        'prestation_nom': pr.nom,
        if (pr.prix != null) 'prix_total': pr.prix!.toStringAsFixed(2),
      },
    }).select('token').single();
    token = row['token'] as String?;
    final clientUid = rdv['client_uid']?.toString() ?? '';
    if (clientUid.isNotEmpty && token != null) {
      try {
        await supa.from('notifications').insert({
          'uid': clientUid,
          'type': 'contrat_invite',
          'title': 'Contrat de prestation à signer',
          'body': 'Votre toiletteur vous envoie le contrat de votre rendez-vous — vérifiez et signez',
          if ((rdv['client_profile_id']?.toString() ?? '').isNotEmpty) 'profile_id': rdv['client_profile_id'],
          'data': {'token': token, 'url': '$kSiteBaseUrl/signer-contrat/$token'},
          'read': false,
        });
      } catch (_) {}
    } else if (token != null) {
      // Client sans compte : contrat à signer par e-mail (lien personnel).
      await envoyerContratParEmail(rdv, token, titre: 'Contrat de prestation toilettage', nomClient: nomClient);
    }
  }
  if (token == null || !ouvrir || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ContratSignaturePage(token: token!)));
}

/// Facture de la prestation : prix TTC affiché (HT déduit selon le régime de
/// TVA), client et animal préremplis.
Future<void> facturerToilettage(BuildContext context, Map<String, dynamic> rdv, {String? nomClient, String? animal}) async {
  final pr = await prestationToilettageRdv(rdv);
  final c = await coordonneesClientRdv(rdv);
  if (!context.mounted) return;
  final debut = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
  final animalNom = (animal ?? rdv['_animal_nom']?.toString() ?? '').trim();
  String? v(String k) => (c[k] ?? '').isEmpty ? null : c[k];
  await Navigator.push(context, MaterialPageRoute(builder: (_) => CreerFacturePage(
    clientNom: v('nom') ?? nomClient ?? rdv['_client_name']?.toString(),
    clientPrenom: v('prenom'), clientEmail: v('email'), clientTel: v('tel'),
    clientRue: v('rue'), clientCp: v('cp'), clientVille: v('ville'),
    lignesPrefill: [
      FacturePrefillLigne(
        designation: [pr.nom, if (animalNom.isNotEmpty) animalNom].join(' — ')
            + (debut != null ? ' — ${DateFormat('dd/MM/yyyy').format(debut)}' : ''),
        prixTTC: pr.prix ?? 0, quantite: 1, tauxTVA: 20),
    ],
    sourceRdvId: rdv['id']?.toString(),
    sourceAnimalId: rdv['animal_id']?.toString(),
    clientUid: rdv['client_uid']?.toString(),
    clientProfileId: rdv['client_profile_id']?.toString(),
  )));
}

/// Ouvre le dossier d'une séance de toilettage.
Future<void> showDossierToilettage(BuildContext context, Map<String, dynamic> rdv, {
  required String nomClient, required String prestation, String? animal, bool depuisAgenda = false, VoidCallback? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _DossierToilettage(rdv: rdv, nomClient: nomClient, prestation: prestation, animal: animal, depuisAgenda: depuisAgenda),
  );
  onChanged?.call();
}

class _DossierToilettage extends StatefulWidget {
  final Map<String, dynamic> rdv;
  final String nomClient, prestation;
  final String? animal;
  final bool depuisAgenda;
  const _DossierToilettage({required this.rdv, required this.nomClient, required this.prestation, this.animal, required this.depuisAgenda});

  @override
  State<_DossierToilettage> createState() => _DossierToilettageState();
}

class _DossierToilettageState extends State<_DossierToilettage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _seance, _contrat, _facture, _consignes;
  Map<String, String> _coord = {};

  Map<String, dynamic> get r => widget.rdv;
  String get _uid => r['pro_uid']?.toString() ?? '';
  String get _pid => (r['pro_profile_id']?.toString() ?? '').isNotEmpty ? r['pro_profile_id'].toString() : User_Info.activeProfileId;
  DateTime get _debut => DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime.now();
  String get _animalId => r['animal_id']?.toString() ?? '';
  String get _animalNom => (widget.animal ?? r['_animal_nom']?.toString() ?? '').trim();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final id = r['id'];
    _coord = await coordonneesClientRdv(r);
    try { _seance = await _supa.from('seances_toilettage').select().eq('rdv_id', id).maybeSingle(); } catch (_) {}
    try { _consignes = await _supa.from('rdv').select('consignes, consignes_le, consignes_demandees_le').eq('id', id).maybeSingle(); } catch (_) {}
    try {
      _contrat = await _supa.from('documents_animaux').select('id, token, statut')
          .eq('rdv_id', id).eq('type', 'contrat_prestation_toilettage').maybeSingle();
    } catch (_) {}
    try {
      _facture = await _supa.from('factures').select('id, statut, total_ttc, pdf_url, numero_affichage, numero_facture, date_paiement, mode_paiement')
          .eq('source_rdv_id', id).neq('statut', 'annulee').or('type_facture.is.null,type_facture.not.in.(acompte,avoir)')
          .order('created_at', ascending: false).limit(1).maybeSingle();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t, style: const TextStyle(fontFamily: 'Galey'))));
  }

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) { setState(() => _loading = true); _charger(); }
  }

  Future<void> _notifier(String type, String titre, String corps, Map<String, dynamic> data) async {
    final clientUid = r['client_uid']?.toString() ?? '';
    if (clientUid.isEmpty) { _snack('Client sans compte PetsMatch : transmettez par e-mail ou téléphone.'); return; }
    try {
      await _supa.from('notifications').insert({
        'uid': clientUid, 'type': type, 'title': titre, 'body': corps,
        if ((r['client_profile_id']?.toString() ?? '').isNotEmpty) 'profile_id': r['client_profile_id'],
        'data': data, 'read': false,
      });
      _snack('Transmis au client');
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  // ── Compte rendu ──
  Future<void> _ouvrirCompteRendu() async {
    if (_animalId.isEmpty) { _snack('Animal non renseigné sur le rendez-vous.'); return; }
    await _go(ToilettageSeancePage(animalId: _animalId, animalNom: _animalNom.isEmpty ? 'Animal' : _animalNom, rdv: r));
  }

  Future<void> _partagerCompteRendu() async {
    final s = _seance;
    if (s == null) return;
    if ((s['compte_rendu']?.toString() ?? '').trim().isEmpty) { _snack('Rédigez d\'abord le compte rendu.'); return; }
    try {
      await _supa.from('seances_toilettage').update({'partage_proprietaire': true, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', s['id']);
      setState(() => s['partage_proprietaire'] = true);
      await _notifier('toilettage_cr', 'Compte rendu de toilettage',
          'Le compte rendu du toilettage de ${_animalNom.isEmpty ? 'votre animal' : _animalNom} est disponible.',
          {'animalId': _animalId, 'seance_id': s['id']});
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  // ── Consignes du client ──
  Future<void> _demanderConsignes() async {
    try {
      final res = await ConsignesApi.demander(r['id'].toString());
      _snack('Consignes demandées${res.email ? ' par e-mail' : ''}${res.notifie ? '${res.email ? ' et' : ''} par notification' : ''}');
      if (mounted) { setState(() => _loading = true); _charger(); }
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _voirConsignes() {
    final rep = reponsesConsignes('toilettage', _consignes?['consignes'] as Map?);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Consignes du client${_animalNom.isNotEmpty ? ' — $_animalNom' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _ink)),
          const SizedBox(height: 10),
          for (final (label, valeur) in rep) ...[
            Text(label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal)),
            Text(valeur, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _ink)),
            const SizedBox(height: 8),
          ],
          Text('À reporter si besoin dans la fiche toilettage de l\'animal (consignes permanentes du salon).',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        ]),
      )),
    );
  }

  // ── Facture ──
  Future<void> _marquerPayee() async {
    final f = _facture;
    if (f == null) return;
    final mode = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Réglée par', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),
        for (final m in const ['Carte bancaire', 'Espèces', 'Virement bancaire', 'Chèque'])
          ListTile(title: Text(m, style: const TextStyle(fontFamily: 'Galey')), onTap: () => Navigator.pop(ctx, m)),
      ])),
    );
    if (mode == null) return;
    final maj = {'statut': 'payee', 'mode_paiement': mode, 'date_paiement': DateTime.now().toUtc().toIso8601String()};
    try {
      await _supa.from('factures').update(maj).eq('id', f['id']);
      setState(() => f.addAll(maj));
      _snack('Paiement enregistré : la facture est acquittée');
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  // Étape du dossier : état, puis de vrais boutons (Relancer, Saisir…).
  Widget _ligne(String titre, String etat, Color c, List<(String, VoidCallback)> actions) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 92, child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _ink))),
            Expanded(child: Text(etat, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: c))),
          ]),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final a in actions)
                OutlinedButton(
                  onPressed: a.$2,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal, side: const BorderSide(color: _teal),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), minimumSize: const Size(0, 34),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  child: Text(a.$1, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700)),
                ),
            ]),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = _seance, ct = _contrat, f = _facture;
    final aCompte = (r['client_uid']?.toString() ?? '').isNotEmpty;
    final passee = _debut.isBefore(DateTime.now());
    String eur(Object? v) => '${((v as num?) ?? 0).toStringAsFixed(0)} €';
    final crRedige = s != null && (s['compte_rendu']?.toString() ?? '').trim().isNotEmpty;
    final crPartage = s?['partage_proprietaire'] == true;
    final datePaie = DateTime.tryParse(f?['date_paiement']?.toString() ?? '')?.toLocal();
    return SafeArea(child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: _ink), tooltip: 'Retour', visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36), onPressed: () => Navigator.pop(context)),
          const SizedBox(width: 4),
          Expanded(child: Text(widget.prestation, style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _ink))),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${widget.nomClient} · ${_jour(_debut)} à ${_hm(_debut)}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
            if (_animalNom.isNotEmpty) Text('Animal : $_animalNom', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink)),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE6E8E6))),
          child: _loading
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: _teal)))
              : Column(children: [
                  _ligne('Compte rendu',
                      s == null ? (passee ? 'À rédiger' : 'Après la séance') : !crRedige ? 'Fiche remplie, compte rendu à rédiger'
                          : crPartage ? 'Partagé avec le client' : 'Rédigé, non partagé',
                      s == null ? (passee ? _ambre : _muted) : crPartage ? _vert : _ambre,
                      [
                        (s == null ? 'Rédiger' : 'Ouvrir', _ouvrirCompteRendu),
                        if (crRedige && !crPartage && aCompte) ('Partager', _partagerCompteRendu),
                      ]),
                  Builder(builder: (_) {
                    final recues = DateTime.tryParse(_consignes?['consignes_le']?.toString() ?? '')?.toLocal();
                    final demandees = DateTime.tryParse(_consignes?['consignes_demandees_le']?.toString() ?? '')?.toLocal();
                    return _ligne('Consignes',
                        recues != null ? 'Reçues le ${DateFormat('dd/MM').format(recues)}'
                            : demandees != null ? 'Demandées le ${DateFormat('dd/MM').format(demandees)}, en attente' : 'Non demandées',
                        recues != null ? _vert : demandees != null ? _ambre : _muted,
                        [
                          if (recues != null) ('Voir', _voirConsignes)
                          else ...[
                            (demandees != null ? 'Relancer' : 'Demander', _demanderConsignes),
                            ('Saisir', () => _go(RdvConsignesPage(rdvId: r['id'].toString()))),
                          ],
                        ]);
                  }),
                  _ligne('Contrat',
                      ct == null ? 'Non généré' : ct['statut'] == 'signe' ? 'Signé'
                          : ct['statut'] == 'partiellement_signe' ? 'Signé par une partie' : 'En attente de signature',
                      ct == null ? _muted : ct['statut'] == 'signe' ? _vert : _ambre,
                      [
                        if (ct == null)
                          ('Générer et envoyer', () async {
                            await genererContratToilettage(context, r, uid: _uid, profileId: _pid, clientNom: widget.nomClient, ouvrir: false);
                            if (mounted) { setState(() => _loading = true); _charger(); }
                          })
                        else ...[
                          ('Voir', () => _go(ContratSignaturePage(token: ct['token'].toString()))),
                          if (ct['statut'] != 'signe' && aCompte)
                            ('Renvoyer', () => _notifier('contrat_invite', 'Contrat de prestation à signer',
                                'Votre toiletteur vous envoie le contrat de votre rendez-vous — vérifiez et signez',
                                {'token': ct['token'], 'url': '$kSiteBaseUrl/signer-contrat/${ct['token']}'}))
                          else if (ct['statut'] != 'signe')
                            ('Envoyer par e-mail', () async {
                              final ok = await envoyerContratParEmail(r, ct['token'].toString(), titre: 'Contrat de prestation toilettage', nomClient: widget.nomClient);
                              _snack(ok ? 'Contrat envoyé par e-mail' : 'Adresse e-mail du client inconnue');
                            }),
                        ],
                      ]),
                  _ligne('Facture',
                      f == null ? (passee ? 'À émettre' : 'Non facturée')
                          : f['statut'] == 'payee'
                              ? 'Payée${datePaie != null ? ' le ${DateFormat('dd/MM').format(datePaie)}' : ''} · ${eur(f['total_ttc'])}'
                              : 'Émise, non payée · ${eur(f['total_ttc'])}',
                      f == null ? (passee ? _ambre : _muted) : f['statut'] == 'payee' ? _vert : _ambre,
                      [
                        if (f == null)
                          ('Facturer', () async {
                            await facturerToilettage(context, r, nomClient: widget.nomClient, animal: _animalNom);
                            if (mounted) { setState(() => _loading = true); _charger(); }
                          })
                        else ...[
                          if (f['statut'] != 'payee') ('Marquer payée', _marquerPayee),
                          ('Voir', () => _go(const FacturationPage())),
                          if (aCompte)
                            ('Transmettre', () => _notifier('facture_recue', 'Nouvelle facture — votre toiletteur',
                                'Facture n° ${f['numero_affichage'] ?? f['numero_facture'] ?? ''} · ${((f['total_ttc'] as num?) ?? 0).toStringAsFixed(2)} €',
                                {'facture_id': f['id'], if (f['pdf_url'] != null) 'url': f['pdf_url']})),
                        ],
                      ]),
                ]),
        ),
        const SizedBox(height: 4),
        Text('Le compte rendu partagé (avec vos conseils de soin du pelage) apparaît dans l\'onglet Consultations de l\'animal.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
        const Padding(padding: EdgeInsets.only(top: 10, bottom: 6),
            child: Text('Contacter le client', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink))),
        ContactCanaux(clientUid: r['client_uid']?.toString(), tel: _coord['tel'], email: _coord['email'], monProfilId: _pid,
            sujet: 'Votre rendez-vous toilettage du ${_jour(_debut)}'),
        const SizedBox(height: 6),
        if (_animalId.isNotEmpty)
          ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.pets_outlined, color: _teal),
              title: const Text('Fiche toilettage de l\'animal', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: _ink)),
              onTap: () => _go(ToilettageFicheClientPage(animalId: _animalId, animalNom: _animalNom.isEmpty ? 'Animal' : _animalNom, rdvId: r['id'].toString()))),
        if (!widget.depuisAgenda)
          ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.event_note_outlined, color: _teal),
              title: const Text("Voir le rendez-vous dans l'agenda", style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: _ink)),
              onTap: () => _go(ProAgendaPage(initialTabIndex: 1, focusRdvId: r['id']?.toString()))),
      ]),
    ));
  }
}
