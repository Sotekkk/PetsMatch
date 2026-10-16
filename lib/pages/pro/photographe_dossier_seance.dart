// Photographe — dossier d'une séance (rdv), ouvert depuis l'agenda, le
// tableau de bord ou Mes clients. Le client est le PROPRIÉTAIRE (pas
// l'animal) : pas de carnet de santé, de compte rendu ni d'ordonnance.
// Chaque module garde son statut et peut être transmis au client :
// devis, contrat, galerie, sélection du client (photos choisies), facture.
// Miroir site : website/src/components/photographe/DossierSeanceModal.tsx.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/utils/geocoding_helper.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/pages/pro/education_devis_page.dart' show DevisPage, DevisPrefill;
import 'package:PetsMatch/pages/pro/photographe_album_page.dart';
import 'package:PetsMatch/pages/pro/photographe_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show FacturationPage, CreerFacturePage, FacturePrefillLigne;
import 'package:PetsMatch/utils/galeries_api.dart' show kStatutsGalerie;
import 'package:PetsMatch/widgets/adresse_recherche_field.dart';
import 'package:PetsMatch/widgets/contact_canaux.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);
const _muted = Color(0xFF6B7280);
const _vert = Color(0xFF2E7D5E);
const _ambre = Color(0xFFD97706);
const _rouge = Color(0xFFB3261E);

String _jour(DateTime d) => DateFormat('EEE d MMM', 'fr_FR').format(d);
String _hm(DateTime d) => DateFormat('HH:mm').format(d);

/// Lieu du shooting : à domicile (adresse du client) ou proposé par le
/// photographe (à préciser, souhait éventuel du client).
String lieuSeance(Map<String, dynamic> r) {
  final adr = (r['adresse_depart']?.toString() ?? '').trim();
  final lieu = (r['lieu']?.toString() ?? '').trim();
  if (r['lieu_type'] == 'domicile') return 'À domicile : $adr';
  if (r['lieu_type'] == 'photographe') {
    return adr.isNotEmpty ? adr : 'Lieu à préciser${lieu.startsWith('Souhait') ? ' — $lieu' : ''}';
  }
  return adr.isNotEmpty ? adr : lieu;
}

/// Génère (ou rouvre) le contrat de prestation photo d'une séance et
/// l'envoie au client à la création. Formule payante requise (signature).
Future<void> genererContratPhoto(BuildContext context, Map<String, dynamic> rdv,
    {required String uid, required String profileId, String? clientNom, bool ouvrir = true}) async {
  final planCode = await PlanService.getPlanCode(uid, profilType: 'photographe');
  if (!context.mounted) return;
  if (planCode == 'free') {
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Signature — formule payante requise', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: const Text('La signature électronique des contrats est disponible avec les formules Essentiel et Premium.',
          style: TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        FilledButton(onPressed: () {
          Navigator.pop(ctx);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotographeAbonnementPage()));
        }, child: const Text('Voir les formules')),
      ],
    ));
    return;
  }
  final supa = Supabase.instance.client;
  final existing = await supa.from('documents_animaux').select('token')
      .eq('rdv_id', rdv['id']).eq('type', 'contrat_prestation_photo').maybeSingle();
  String? token = existing?['token'] as String?;
  final nomClient = clientNom ?? rdv['_client_name']?.toString() ?? '';
  if (token == null) {
    Map<String, dynamic>? prestation;
    final prestationId = rdv['prestation_id']?.toString();
    if (prestationId != null && prestationId.isNotEmpty) {
      prestation = await supa.from('prestations_photographe').select('nom, prix, acompte_pourcentage').eq('id', prestationId).maybeSingle();
    }
    if (!context.mounted) return;
    // Diffusion des images : choisie par le photographe, écrite dans le contrat.
    final diffusion = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Diffusion des photos par vous', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),
        for (final o in const [
          ('book', 'Book et portfolio PetsMatch, sauf refus du client'),
          ('book_reseaux', 'Book, site, réseaux sociaux et portfolio PetsMatch'),
          ('aucune', 'Aucune diffusion'),
        ])
          ListTile(title: Text(o.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)), onTap: () => Navigator.pop(ctx, o.$1)),
        const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text("Une personne identifiable n'est jamais diffusée sans son autorisation écrite.",
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey))),
      ])),
    );
    if (diffusion == null) return;
    final row = await supa.from('documents_animaux').insert({
      'uid_eleveur': uid,
      if (profileId.isNotEmpty) 'pro_profile_id': profileId,
      'animal_id': rdv['animal_id'],
      'rdv_id': rdv['id'],
      'type': 'contrat_prestation_photo',
      'titre': 'Contrat de prestation photo — $nomClient',
      'statut': 'en_attente',
      // client_uid / client_profile_id : le contrat remonte dans « Mes
      // contrats » du client (profil destinataire uniquement).
      'metadata': {
        'client_nom': nomClient,
        'client_uid': rdv['client_uid'],
        'client_profile_id': rdv['client_profile_id'],
        'prestation_nom': prestation?['nom'],
        'prix_total': prestation?['prix']?.toString(),
        'acompte_pourcentage': prestation?['acompte_pourcentage']?.toString(),
        'autorisation_images': diffusion,
      },
    }).select('token').single();
    token = row['token'] as String?;
    if (token != null) await transmettreContrat(rdv, token);
  }
  if (token == null || !ouvrir || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ContratSignaturePage(token: token!)));
}

/// (Ré)envoie au client l'invitation à signer le contrat.
Future<void> transmettreContrat(Map<String, dynamic> rdv, String token) async {
  final clientUid = rdv['client_uid']?.toString();
  if (clientUid == null || clientUid.isEmpty) return;
  try {
    await Supabase.instance.client.from('notifications').insert({
      'uid': clientUid,
      'type': 'contrat_invite',
      'title': 'Contrat de prestation à signer',
      'body': 'Votre photographe vous envoie le contrat de votre séance — vérifiez et signez',
      if ((rdv['client_profile_id']?.toString() ?? '').isNotEmpty) 'profile_id': rdv['client_profile_id'],
      'data': {'token': token, 'url': '$kSiteBaseUrl/signer-contrat/$token'},
      'read': false,
    });
  } catch (_) {}
}

/// Ouvre le dossier d'une séance. [nomClient] / [prestation] : libellés déjà
/// résolus par l'appelant. [depuisAgenda] masque « Voir dans l'agenda ».
Future<void> showDossierSeance(BuildContext context, Map<String, dynamic> rdv, {
  required String nomClient, required String prestation, String? animal, bool depuisAgenda = false, VoidCallback? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _DossierSeance(rdv: rdv, nomClient: nomClient, prestation: prestation, animal: animal, depuisAgenda: depuisAgenda),
  );
  onChanged?.call();
}

class _DossierSeance extends StatefulWidget {
  final Map<String, dynamic> rdv;
  final String nomClient, prestation;
  final String? animal;
  final bool depuisAgenda;
  const _DossierSeance({required this.rdv, required this.nomClient, required this.prestation, this.animal, required this.depuisAgenda});

  @override
  State<_DossierSeance> createState() => _DossierSeanceState();
}

class _DossierSeanceState extends State<_DossierSeance> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _devis, _contrat, _galerie, _facture;
  int _nbPhotos = 0, _nbChoisies = 0;
  double? _prix;
  // Coordonnées du client : son profil PetsMatch (à jour), sinon celles
  // saisies par le photographe sur le rendez-vous.
  String _tel = '', _email = '';
  String _prenom = '', _nom = '', _rue = '', _cp = '', _ville = '';
  /// Animaux de la séance (plusieurs possibles), pour les lignes de devis / facture.
  String get _animaux => (widget.animal ?? '').split('+').map((x) => x.trim()).where((x) => x.isNotEmpty).join(', ');

  Map<String, dynamic> get r => widget.rdv;
  String get _uid => r['pro_uid']?.toString() ?? '';
  String get _pid => (r['pro_profile_id']?.toString() ?? '').isNotEmpty ? r['pro_profile_id'].toString() : User_Info.activeProfileId;
  DateTime get _debut => DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final id = r['id'];
    try {
      final man = await _supa.from('rdv').select('client_telephone_manuel, client_email_manuel').eq('id', id).maybeSingle();
      final cp = r['client_profile_id']?.toString() ?? '';
      final prof = cp.isEmpty ? null
          : await _supa.from('user_profiles_complet')
              .select('firstname, lastname, phone_number, phone, email_contact, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro')
              .eq('id', cp).maybeSingle();
      String premier(List<dynamic> v) => v.map((x) => (x ?? '').toString().trim()).firstWhere((x) => x.isNotEmpty, orElse: () => '');
      _tel = premier([prof?['phone_number'], prof?['phone'], man?['client_telephone_manuel']]);
      _email = premier([prof?['email_contact'], man?['client_email_manuel']]);
      _prenom = premier([prof?['firstname']]);
      _nom = premier([prof?['lastname']]);
      _rue = premier([prof?['rue'], prof?['rue_pro']]);
      _cp = premier([prof?['code_postal'], prof?['code_postal_pro']]);
      _ville = premier([prof?['ville'], prof?['ville_pro']]);
      // Sans adresse au profil : adresse du shooting à domicile.
      if (_rue.isEmpty && r['lieu_type'] == 'domicile') _rue = (r['adresse_depart']?.toString() ?? '').trim();
    } catch (_) {}
    try { _devis = await _supa.from('devis').select().eq('rdv_id', id).order('created_at', ascending: false).limit(1).maybeSingle(); } catch (_) {}
    try {
      _contrat = await _supa.from('documents_animaux').select('id, token, statut')
          .eq('rdv_id', id).eq('type', 'contrat_prestation_photo').maybeSingle();
    } catch (_) {}
    try { _galerie = await _supa.from('albums_photo').select().eq('rdv_id', id).maybeSingle(); } catch (_) {}
    if (_galerie != null) {
      try {
        final ph = await _supa.from('album_photos').select('selectionnee').eq('album_id', _galerie!['id']);
        _nbPhotos = (ph as List).length;
        _nbChoisies = ph.where((p) => p['selectionnee'] == true).length;
      } catch (_) {}
    }
    try {
      _facture = await _supa.from('factures').select('id, statut, total_ttc, pdf_url, numero_affichage, numero_facture')
          .eq('source_rdv_id', id).neq('statut', 'annulee').order('created_at', ascending: false).limit(1).maybeSingle();
    } catch (_) {}
    if (r['prestation_id'] != null) {
      try {
        final p = await _supa.from('prestations_photographe').select('prix').eq('id', r['prestation_id']).maybeSingle();
        _prix = (p?['prix'] as num?)?.toDouble();
      } catch (_) {}
    }
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
    final clientUid = r['client_uid']?.toString();
    if (clientUid == null || clientUid.isEmpty) { _snack('Client sans compte PetsMatch : transmettez par e-mail ou téléphone.'); return; }
    await _supa.from('notifications').insert({
      'uid': clientUid, 'type': type, 'title': titre, 'body': corps,
      if ((r['client_profile_id']?.toString() ?? '').isNotEmpty) 'profile_id': r['client_profile_id'],
      'data': data, 'read': false,
    });
    _snack('Transmis au client');
  }

  // ── Devis ──
  /// Nom du client : celui du profil s'il est connu, sinon le nom affiché.
  String get _nomFacture => _nom.isNotEmpty ? _nom : widget.nomClient;
  String get _designation => [widget.prestation, if (_animaux.isNotEmpty) _animaux].join(' — ');

  // Devis : tarifs affichés TTC (le total du devis est la somme des lignes).
  void _creerDevis() => _go(DevisPage(prefill: DevisPrefill(
        rdvId: r['id'].toString(), clientUid: r['client_uid']?.toString(), clientProfileId: r['client_profile_id']?.toString(),
        clientNom: _nomFacture, clientPrenom: _prenom.isNotEmpty ? _prenom : null,
        clientEmail: _email.isNotEmpty ? _email : null, clientTel: _tel.isNotEmpty ? _tel : null,
        animalId: r['animal_id']?.toString(),
        lignes: [if (_prix != null) {'description': _designation, 'quantite': 1, 'prix_unitaire': _prix}],
      )));
  Future<void> _transmettreDevis() async {
    final d = _devis!;
    if (d['statut'] == 'brouillon') {
      await _supa.from('devis').update({'statut': 'envoye', 'updated_at': DateTime.now().toIso8601String()}).eq('id', d['id']);
    }
    await _notifier('devis_recu', 'Vous avez reçu un devis',
        'Un devis de ${((d['total_ttc'] as num?) ?? 0).toStringAsFixed(2)} € vous a été envoyé.',
        {'devis_id': d['id'], 'token': d['token_acceptation'], 'url': '/devis/${d['token_acceptation']}'});
    setState(() => d['statut'] = d['statut'] == 'brouillon' ? 'envoye' : d['statut']);
  }

  // ── Facture ──
  void _facturer() {
    final incluses = (_galerie?['nb_photos_incluses'] as num?)?.toInt();
    final prixSupp = (_galerie?['prix_photo_supp'] as num?)?.toDouble();
    final supp = incluses == null ? 0 : (_nbChoisies - incluses).clamp(0, 9999);
    // Tarifs affichés TTC : le HT est déduit selon le régime de TVA du pro.
    _go(CreerFacturePage(
      clientNom: _nomFacture,
      clientPrenom: _prenom.isNotEmpty ? _prenom : null,
      clientEmail: _email.isNotEmpty ? _email : null,
      clientTel: _tel.isNotEmpty ? _tel : null,
      clientRue: _rue.isNotEmpty ? _rue : null,
      clientCp: _cp.isNotEmpty ? _cp : null,
      clientVille: _ville.isNotEmpty ? _ville : null,
      lignesPrefill: [
        FacturePrefillLigne(designation: '$_designation — séance du ${_jour(_debut)}', prixTTC: _prix ?? 0, quantite: 1, tauxTVA: 20),
        if (supp > 0 && prixSupp != null && prixSupp > 0)
          FacturePrefillLigne(designation: 'Photos supplémentaires', prixTTC: prixSupp, quantite: supp.toDouble(), tauxTVA: 20),
      ],
      sourceRdvId: r['id'].toString(),
      sourceAnimalId: r['animal_id']?.toString(),
      clientUid: r['client_uid']?.toString(),
      clientProfileId: r['client_profile_id']?.toString(),
    ));
  }
  Future<void> _transmettreFacture() async {
    final f = _facture!;
    final numero = f['numero_affichage'] ?? f['numero_facture'] ?? '';
    await _notifier('facture_recue', 'Nouvelle facture — votre photographe',
        'Facture n° $numero · ${((f['total_ttc'] as num?) ?? 0).toStringAsFixed(2)} €',
        {'facture_id': f['id'], if (f['pdf_url'] != null) 'url': f['pdf_url']});
  }

  // ── Lieu ──
  Future<void> _preciserLieu() async {
    final ctrl = TextEditingController(text: r['lieu_type'] == 'photographe' ? (r['adresse_depart']?.toString() ?? '') : '');
    var prevenir = (r['client_uid']?.toString() ?? '').isNotEmpty;
    // Lieu choisi dans Google Maps : coordonnées connues (sinon géocodage).
    double? lat, lng;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      scrollable: true,
      title: const Text('Lieu du shooting', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if ((r['lieu']?.toString() ?? '').startsWith('Souhait'))
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(r['lieu'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
        AdresseRechercheField(
          label: 'Rechercher le lieu (Google Maps)',
          hint: 'Plage, forêt, parc, studio, adresse…',
          afficherLibelle: true,
          onSelection: (a) => setD(() { ctrl.text = a.libelle; lat = a.lat; lng = a.lng; }),
        ),
        const SizedBox(height: 10),
        TextField(controller: ctrl, maxLines: 2, minLines: 1, onChanged: (_) { lat = null; lng = null; },
            decoration: const InputDecoration(labelText: 'Lieu retenu (modifiable)', border: OutlineInputBorder())),
        if ((r['client_uid']?.toString() ?? '').isNotEmpty)
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: prevenir, onChanged: (v) => setD(() => prevenir = v == true),
              title: const Text('Prévenir le client', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
      ],
    )));
    final adr = ctrl.text.trim();
    if (ok != true || adr.isEmpty) return;
    final geo = lat != null && lng != null ? (lat: lat!, lng: lng!) : await GeocodingHelper.geocode(adr);
    await _supa.from('rdv').update({
      'adresse_depart': adr,
      if (r['lieu_type'] == null) 'lieu_type': 'photographe',
      if (geo != null) ...{'lat_depart': geo.lat, 'lng_depart': geo.lng},
    }).eq('id', r['id']);
    r['adresse_depart'] = adr;
    r['lieu_type'] ??= 'photographe';
    if (prevenir) {
      await _notifier('rdv_modifie', 'Lieu de votre séance photo', 'Votre séance du ${_jour(_debut)} à ${_hm(_debut)} aura lieu : $adr', {'rdv_id': r['id']});
    }
    if (mounted) setState(() {});
  }

  Widget _ligne(String titre, String etat, Color c, List<(String, VoidCallback)> actions) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: 74, child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _ink))),
          Expanded(child: Text(etat, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: c))),
          for (final a in actions)
            TextButton(onPressed: a.$2, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 32)),
                child: Text(a.$1, style: const TextStyle(fontFamily: 'Galey', color: _teal, fontSize: 13))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lieu = lieuSeance(r);
    final adresse = (r['adresse_depart']?.toString() ?? '').trim();
    final notes = (r['notes_client']?.toString() ?? '').trim();
    final aCompte = (r['client_uid']?.toString() ?? '').isNotEmpty;
    final passee = _debut.isBefore(DateTime.now());
    // États
    final d = _devis, ct = _contrat, g = _galerie, f = _facture;
    String eur(Object? v) => '${((v as num?) ?? 0).toStringAsFixed(0)} €';
    final incluses = (g?['nb_photos_incluses'] as num?)?.toInt();
    final statutGal = g == null ? null : kStatutsGalerie.where((s) => s.$1 == g['statut']).firstOrNull?.$2 ?? 'Brouillon';
    return SafeArea(child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.prestation, style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 2),
        Text('${widget.nomClient} · ${_jour(_debut)} à ${_hm(_debut)} · ${(r['duree_minutes'] as num?)?.toInt() ?? 60} min',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
        if (widget.animal != null && widget.animal!.isNotEmpty)
          Text('Animal${widget.animal!.contains('+') ? 'aux' : ''} : ${widget.animal}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink)),
        if (lieu.isNotEmpty)
          Text(lieu, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: lieu.startsWith('Lieu à préciser') ? _ambre : _ink)),
        if (notes.isNotEmpty) Text('Demande : $notes', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ambre)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE6E8E6))),
          child: _loading
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: _teal)))
              : Column(children: [
                  _ligne('Devis',
                      d == null ? 'Aucun' : d['statut'] == 'accepte' ? 'Accepté · ${eur(d['total_ttc'])}'
                          : d['statut'] == 'envoye' ? 'Envoyé, en attente · ${eur(d['total_ttc'])}'
                          : d['statut'] == 'refuse' ? 'Refusé' : 'Brouillon · ${eur(d['total_ttc'])}',
                      d == null ? _muted : d['statut'] == 'accepte' ? _vert : d['statut'] == 'refuse' ? _rouge : _ambre,
                      [
                        if (d == null) ('Créer', _creerDevis) else ('Voir', () => _go(const DevisPage())),
                        if (d != null && (d['statut'] == 'brouillon' || d['statut'] == 'envoye') && aCompte)
                          (d['statut'] == 'brouillon' ? 'Envoyer' : 'Relancer', _transmettreDevis),
                      ]),
                  _ligne('Contrat',
                      ct == null ? 'Non généré' : ct['statut'] == 'signe' ? 'Signé'
                          : ct['statut'] == 'partiellement_signe' ? 'Signé par une partie' : 'En attente de signature',
                      ct == null ? _muted : ct['statut'] == 'signe' ? _vert : _ambre,
                      [
                        if (ct == null)
                          ('Générer et envoyer', () async {
                            await genererContratPhoto(context, r, uid: _uid, profileId: _pid, clientNom: widget.nomClient, ouvrir: false);
                            if (mounted) { setState(() => _loading = true); _charger(); }
                          })
                        else ...[
                          ('Voir', () => _go(ContratSignaturePage(token: ct['token'].toString()))),
                          if (ct['statut'] != 'signe' && aCompte) ('Renvoyer', () async { await transmettreContrat(r, ct['token'].toString()); _snack('Transmis au client'); }),
                        ],
                      ]),
                  _ligne('Galerie',
                      g == null ? (passee ? 'À créer' : 'Après la séance') : '$statutGal · $_nbPhotos photo${_nbPhotos > 1 ? 's' : ''}',
                      g == null ? (passee ? _ambre : _muted) : g['statut'] == 'livree' ? _vert : _ink,
                      [(g == null ? 'Créer' : 'Ouvrir', () => _go(PhotographeAlbumPage(rdvId: r['id'].toString(), clientName: widget.nomClient)))]),
                  if (g != null && (_nbChoisies > 0 || g['selection_confirmee_le'] != null))
                    _ligne('Sélection',
                        '$_nbChoisies choisie${_nbChoisies > 1 ? 's' : ''}${incluses != null ? ' sur $incluses incluse${incluses > 1 ? 's' : ''}' : ''}'
                        '${g['selection_confirmee_le'] != null ? ' · confirmée' : ' · en cours'}',
                        g['selection_confirmee_le'] != null ? _ambre : _muted,
                        [('Voir les photos', () => _go(PhotographeAlbumPage(albumId: g['id'].toString(), clientName: widget.nomClient, filtreSelection: true)))]),
                  _ligne('Facture',
                      f == null ? (passee ? 'À émettre' : 'Non facturée') : f['statut'] == 'payee' ? 'Payée · ${eur(f['total_ttc'])}' : 'Émise, non payée · ${eur(f['total_ttc'])}',
                      f == null ? (passee ? _ambre : _muted) : f['statut'] == 'payee' ? _vert : _ambre,
                      [
                        if (f == null) ('Facturer', _facturer) else ('Voir', () => _go(const FacturationPage())),
                        if (f != null && aCompte) ('Transmettre', _transmettreFacture),
                      ]),
                ]),
        ),
        const SizedBox(height: 4),
        Text('Chaque élément garde son statut : une galerie livrée n\'est pas une facture payée.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.place_outlined, color: _teal),
            title: Text(r['lieu_type'] == 'domicile' ? 'Modifier le lieu' : 'Préciser le lieu du shooting',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: _ink)),
            onTap: _preciserLieu),
        const Padding(padding: EdgeInsets.only(top: 6, bottom: 6),
            child: Text('Contacter le client', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink))),
        ContactCanaux(clientUid: r['client_uid']?.toString(), tel: _tel, email: _email, monProfilId: _pid,
            sujet: 'Votre séance photo du ${_jour(_debut)}'),
        const SizedBox(height: 6),
        if (adresse.isNotEmpty)
          ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.directions_outlined, color: _teal),
              title: const Text("Itinéraire jusqu'au lieu", style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: _ink)),
              onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(adresse)}'),
                  mode: LaunchMode.externalApplication)),
        if (!widget.depuisAgenda)
          ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.event_note_outlined, color: _teal),
              title: const Text("Voir la séance dans l'agenda", style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: _ink)),
              onTap: () => _go(ProAgendaPage(initialTabIndex: 1, focusRdvId: r['id']?.toString()))),
      ]),
    ));
  }
}
