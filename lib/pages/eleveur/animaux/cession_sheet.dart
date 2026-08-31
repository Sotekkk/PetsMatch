import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/contrat_pdf.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);

String _uuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  return '${h(b[0])}${h(b[1])}${h(b[2])}${h(b[3])}'
      '-${h(b[4])}${h(b[5])}-${h(b[6])}${h(b[7])}-${h(b[8])}${h(b[9])}'
      '-${h(b[10])}${h(b[11])}${h(b[12])}${h(b[13])}${h(b[14])}${h(b[15])}';
}

// ── Feuille de cession ────────────────────────────────────────────────────────

class CessionSheet extends StatefulWidget {
  final Map<String, dynamic> animal;
  final String uid;
  final String nomElevage;
  final VoidCallback onCeded;
  /// true = l'utilisateur est l'acquéreur qui re-cède (pas l'éleveur d'origine)
  final bool isReCession;
  /// Réservation active à préremplir — l'étape "Acquéreur" est alors sautée
  final Map<String, dynamic>? reservation;

  const CessionSheet({
    super.key,
    required this.animal,
    required this.uid,
    required this.nomElevage,
    required this.onCeded,
    this.isReCession = false,
    this.reservation,
  });

  @override
  State<CessionSheet> createState() => _CessionSheetState();
}

class _CessionSheetState extends State<CessionSheet> {
  final _supa = Supabase.instance.client;

  // Étapes
  int _step = 0; // 0 = acquéreur, 1 = détails, 2 = documents

  // Recherche utilisateur PetsMatch
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _foundUser;
  bool _searching = false;
  bool _searchDone = false;

  // Champs acquéreur
  String _qualite = 'particulier';
  final _prenomCtrl   = TextEditingController();
  final _nomCtrl      = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _telCtrl      = TextEditingController();
  final _adresseCtrl  = TextEditingController();
  final _prixCtrl     = TextEditingController();
  final _notesCtrl    = TextEditingController();
  late DateTime _dateCession;

  // Condition de stérilisation (cession éleveur uniquement)
  bool _sterilisationRequise = false;
  final _sterilAgeCtrl = TextEditingController(text: '12');

  DateTime? get _dateNaissanceAnimal {
    final raw = widget.animal['date_naissance'];
    if (raw == null || (raw is String && raw.isEmpty)) return null;
    return DateTime.tryParse(raw.toString());
  }

  DateTime? get _sterilisationEcheance {
    final dn = _dateNaissanceAnimal;
    final mois = int.tryParse(_sterilAgeCtrl.text.trim());
    if (dn == null || mois == null || mois <= 0) return null;
    return DateTime(dn.year, dn.month + mois, dn.day);
  }

  // Documents uploadés manuellement
  String? _contratUrl;
  String? _certificatUrl;
  bool _uploadingContrat    = false;
  bool _uploadingCertificat = false;

  // Documents existants dans documents_animaux (sélectionnable)
  List<Map<String, dynamic>> _existingContrats     = [];
  List<Map<String, dynamic>> _existingCertificats  = [];
  List<Map<String, dynamic>> _existingFactures      = [];
  Map<String, dynamic>? _selectedContrat;
  Map<String, dynamic>? _selectedCertificat;
  bool _loadingDocs = true;

  // Profil éleveur (pour la facture)
  Map<String, dynamic>? _eleveurProfile;

  bool _saving = false;
  bool _generatingPdf  = false;
  bool _generatingCert = false;
  bool _generatingFacture = false;
  String? _error;

  // Contrats créés pendant cette session de cession. Si la cession n'est pas
  // validée (feuille fermée sans `_save`), on supprime ceux restés à l'état
  // brouillon / en attente — inutile de les garder.
  final Set<String> _createdDocIds = {};
  bool _cessionSaved = false;

  @override
  void initState() {
    super.initState();
    _dateCession = DateTime.now();
    _loadExistingDocs();
    final r = widget.reservation;
    if (r != null) {
      _step = 1;
      _qualite = r['qualite'] as String? ?? 'particulier';
      _nomCtrl.text     = r['nom'] as String? ?? '';
      _emailCtrl.text   = r['email'] as String? ?? '';
      _telCtrl.text     = r['tel'] as String? ?? '';
      _adresseCtrl.text = r['adresse'] as String? ?? '';
      _notesCtrl.text   = r['notes'] as String? ?? '';
      final acqUid = r['uid_acquereur'] as String?;
      if (acqUid != null && acqUid.isNotEmpty) {
        _foundUser = {'uid': acqUid, 'nom': r['nom'] as String? ?? 'Utilisateur PetsMatch'};
      }
    }
  }

  Future<void> _loadExistingDocs() async {
    final animalId = widget.animal['id'] as String?;
    if (animalId == null) { setState(() => _loadingDocs = false); return; }
    try {
      final res = await _supa
          .from('documents_animaux')
          .select('id, token, type, titre, url, statut, created_at, metadata')
          .eq('animal_id', animalId)
          .eq('uid_eleveur', widget.uid)
          .inFilter('type', ['contrat_vente', 'contrat_reservation', 'certificat_cession', 'facture'])
          .order('created_at', ascending: false);
      if (mounted) {
        final all = List<Map<String, dynamic>>.from(res);
        setState(() {
          _existingContrats    = all.where((d) => d['type'] == 'contrat_vente' || d['type'] == 'contrat_reservation').toList();
          _existingCertificats = all.where((d) => d['type'] == 'certificat_cession').toList();
          _existingFactures    = all.where((d) => d['type'] == 'facture').toList();
          _loadingDocs = false;
        });
      }
      _supa.from('user_profiles')
          .select('nom, firstname, lastname, adresse, rue, ville, ville_pro, code_postal, siret, numero_elevage, phone_number, email_contact')
          .eq('uid', widget.uid).eq('is_main', true).maybeSingle()
          .then((up) { if (mounted && up != null) _eleveurProfile = Map<String, dynamic>.from(up); });
    } catch (_) {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  /// Supprime les contrats créés ici mais restés non signés quand la cession
  /// n'a pas été validée. Fire-and-forget (appelé depuis `dispose`).
  void _cleanupDrafts() {
    if (_cessionSaved || _createdDocIds.isEmpty) return;
    final ids = _createdDocIds.toList();
    _supa
        .from('documents_animaux')
        .delete()
        .inFilter('id', ids)
        .inFilter('statut', ['brouillon', 'en_attente', 'genere'])
        .then((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    _cleanupDrafts();
    _searchCtrl.dispose();
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _sterilAgeCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    _adresseCtrl.dispose();
    _prixCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _searchResults = [];

  static const _cpFields = 'uid, id, is_main, firstname, lastname, nom, profile_type, avatar_url, phone_number, adresse, rue, ville, code_postal, numero_elevage, email_contact';

  /// Résout le `user_profiles.id` de l'acquéreur selon la qualité choisie :
  /// particulier → profil particulier, éleveur → profil éleveur, refuge →
  /// association. Repli sur `is_main` puis n'importe quel profil.
  Future<String?> _resolveAcqProfileId(String uid, String qualite) async {
    final wanted = qualite == 'eleveur'
        ? 'eleveur'
        : qualite == 'refuge' ? 'association' : 'particulier';
    try {
      final byType = await _supa.from('user_profiles')
          .select('id').eq('uid', uid).eq('profile_type', wanted).maybeSingle();
      if (byType?['id'] != null) return byType!['id'] as String;
      final main = await _supa.from('user_profiles')
          .select('id').eq('uid', uid).eq('is_main', true).maybeSingle();
      if (main?['id'] != null) return main!['id'] as String;
      final any = await _supa.from('user_profiles')
          .select('id').eq('uid', uid).limit(1).maybeSingle();
      return any?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _mapProfile(Map<String, dynamic> cp, {String? email}) => {
    'uid': cp['uid'],
    'profile_id': cp['id'], 'is_main': cp['is_main'], 'profile_type': cp['profile_type'],
    'firstname': cp['firstname'], 'lastname': cp['lastname'],
    'name_elevage': cp['nom'], 'is_elevage': cp['profile_type'] == 'eleveur',
    'profile_picture_url': cp['avatar_url'], 'phone_number': cp['phone_number'],
    'code_iso': '+33', 'code_iso_elevage': '+33',
    'adress': cp['adresse'], 'adress_elevage': cp['adresse'],
    'rue': cp['rue'], 'ville': cp['ville'], 'code_postal': cp['code_postal'],
    'numero_elevage': cp['numero_elevage'],
    // email_contact est le champ fiable pour tous les types de profil
    // (éleveur y compris) — email (login, table users) n'est fourni que si
    // la recherche s'est faite par email.
    'email': cp['email_contact'] ?? email,
  };

  Future<void> _searchUser() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _searchDone = false; _foundUser = null; _searchResults = []; });
    try {
      final isEmail = q.contains('@');
      List<Map<String, dynamic>> rows;
      if (isEmail) {
        final userRow = await _supa.from('users').select('uid, email')
            .eq('email', q.toLowerCase()).maybeSingle();
        if (userRow == null) {
          rows = [];
        } else {
          final cp = await _supa.from('user_profiles').select(_cpFields)
              .eq('uid', userRow['uid'] as String).eq('is_main', true).maybeSingle();
          rows = cp != null ? [_mapProfile(cp, email: userRow['email'] as String?)] : [];
        }
      } else {
        final cps = await _supa
            .from('user_profiles')
            .select(_cpFields)
            .or('firstname.ilike.%$q%,lastname.ilike.%$q%,nom.ilike.%$q%')
            .eq('is_main', true)
            .limit(8);
        rows = (cps as List).map((cp) => _mapProfile(Map<String, dynamic>.from(cp))).toList();
      }
      final mapped = rows.map((r) {
        final isElv = r['is_elevage'] == true;
        final nom = isElv
            ? (r['name_elevage'] as String? ?? '${r['firstname'] ?? ''} ${r['lastname'] ?? ''}'.trim())
            : '${r['firstname'] ?? ''} ${r['lastname'] ?? ''}'.trim();
        return {...r, 'nom': nom.isEmpty ? 'Utilisateur PetsMatch' : nom};
      }).toList();
      if (mapped.length == 1) {
        _selectUser(mapped.first);
      } else {
        setState(() { _searchResults = mapped; });
      }
    } finally {
      setState(() { _searching = false; _searchDone = true; });
    }
  }

  Future<void> _selectUser(Map<String, dynamic> r) async {
    final isElv = r['is_elevage'] == true;
    final uid = r['uid'] as String?;

    // Cession à un particulier → prendre les coordonnées du **profil
    // particulier** (pas le profil pro/pension qui est souvent `is_main`).
    Map<String, dynamic> contact = r;
    if (!isElv && uid != null) {
      try {
        final part = await _supa.from('user_profiles')
            .select('id, firstname, lastname, adresse, rue, ville, code_postal, phone_number, email_contact')
            .eq('uid', uid).eq('profile_type', 'particulier').maybeSingle();
        if (part != null) {
          contact = {...r, ...Map<String, dynamic>.from(part), 'adress': part['adresse'], 'email': part['email_contact']};
        }
      } catch (_) {}
    }

    final adresse = isElv
        ? (r['adress_elevage'] as String? ?? [r['rue'], r['ville'], r['code_postal']].where((e) => e != null).join(', '))
        : ((contact['adresse'] ?? contact['adress']) as String? ??
            [contact['rue'], contact['code_postal'], contact['ville']].where((e) => e != null && '$e'.isNotEmpty).join(', '));
    final tel = isElv
        ? '${r['code_iso_elevage'] ?? '+33'} ${r['numero_elevage'] ?? ''}'.trim()
        : '${contact['code_iso'] ?? '+33'} ${contact['phone_number'] ?? ''}'.trim();
    if (!mounted) return;
    setState(() {
      _foundUser = contact;
      if (isElv) {
        _prenomCtrl.text = '';
        _nomCtrl.text    = r['nom'] as String;
      } else {
        _prenomCtrl.text = (contact['firstname'] as String? ?? '').trim();
        _nomCtrl.text    = (contact['lastname'] as String? ?? '').trim();
        if (_prenomCtrl.text.isEmpty && _nomCtrl.text.isEmpty) {
          _nomCtrl.text = r['nom'] as String? ?? '';
        }
      }
      _emailCtrl.text  = (contact['email'] ?? contact['email_contact'] ?? '') as String;
      _telCtrl.text    = tel.replaceFirst(RegExp(r'^\+33\s*$'), '');
      _adresseCtrl.text = adresse;
      _searchResults   = [];
    });
  }

  Future<void> _uploadDoc(String type) async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (res == null || res.files.isEmpty) return;
    final file = File(res.files.first.path!);
    final ext  = res.files.first.extension ?? 'pdf';
    final setter = type == 'contrat' ? (v) => _contratUrl = v : (v) => _certificatUrl = v;
    final loadSetter = type == 'contrat'
        ? (v) => setState(() => _uploadingContrat = v)
        : (v) => setState(() => _uploadingCertificat = v);
    loadSetter(true);
    try {
      final path = 'cessions/${widget.uid}/${widget.animal['id']}/${type}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final snap = await FirebaseStorage.instance.ref(path).putFile(file);
      final url  = await snap.ref.getDownloadURL();
      setState(() { setter(url); });
    } catch (e) {
      setState(() => _error = 'Erreur upload : $e');
    } finally {
      loadSetter(false);
    }
  }

  /// « 12 rue X, 75001 Paris » → (rue, cp, ville). Repli propre.
  (String, String, String) _splitAdresse(String full) {
    final s = full.trim();
    if (s.isEmpty) return ('', '', '');
    final m = RegExp(r'\b(\d{5})\b').firstMatch(s);
    if (m == null) return (s, '', '');
    final cp = m.group(1)!;
    var ville = s.substring(m.end).replaceFirst(RegExp(r'^[\s,]+'), '').trim();
    var rue = s.substring(0, m.start).replaceFirst(RegExp(r'[\s,]+$'), '').trim();
    return (rue, cp, ville);
  }

  // Crée un doc dans documents_animaux et ouvre le lien dans le navigateur
  Future<void> _ouvrirContratWeb(String type) async {
    final isCert = type == 'certificat_cession';
    if (isCert) {
      setState(() { _generatingCert = true; _error = null; });
    } else {
      setState(() { _generatingPdf = true; _error = null; });
    }
    try {
      final animalId = widget.animal['id'] as String;
      final titreLabel = isCert ? 'Certificat de cession' : 'Contrat de vente';
      final nomAnimal  = widget.animal['nom'] as String? ?? '';
      final nomComplet = [_prenomCtrl.text.trim(), _nomCtrl.text.trim()]
          .where((s) => s.isNotEmpty).join(' ');
      final acqNom     = nomComplet.isEmpty ? _nomCtrl.text.trim() : nomComplet;
      final acqUid     = _foundUser?['uid'] as String?;
      final acqProfileId = acqUid != null
          ? await _resolveAcqProfileId(acqUid, _qualite) : null;

      // Rue / CP / ville : profil particulier si dispo, sinon découpe de l'adresse
      final profCp    = '${_foundUser?['code_postal'] ?? ''}'.trim();
      final profVille = '${_foundUser?['ville'] ?? ''}'.trim();
      final (splitRue, splitCp, splitVille) = _splitAdresse(_adresseCtrl.text.trim());
      final acqCp    = profCp.isNotEmpty ? profCp : splitCp;
      final acqVille = profVille.isNotEmpty ? profVille : splitVille;
      final acqRue   = (profCp.isNotEmpty && '${_foundUser?['rue'] ?? ''}'.trim().isNotEmpty)
          ? '${_foundUser!['rue']}'.trim()
          : (splitRue.isNotEmpty ? splitRue : _adresseCtrl.text.trim());

      final pid = User_Info.activeProfileId;
      // Créer ou récupérer le doc dans documents_animaux
      final res = await _supa.from('documents_animaux').insert({
        'animal_id':   animalId,
        'uid_eleveur': widget.uid,
        if (acqUid != null) 'uid_acquereur': acqUid,
        if (acqProfileId != null) 'acquereur_profile_id': acqProfileId,
        if (pid.isNotEmpty) 'pro_profile_id': pid,
        'type':        type,
        'titre':       '$titreLabel — $nomAnimal',
        'statut':      'brouillon',
        'metadata': {
          'acquereur_nom':         acqNom,
          'acquereur_prenom':      _prenomCtrl.text.trim(),
          'acquereur_nom_famille': _nomCtrl.text.trim(),
          if (acqUid != null) 'acquereur_uid': acqUid,
          if (acqProfileId != null) 'acquereur_profile_id': acqProfileId,
          'qualite':           _qualite,
          'acquereur_email':   _emailCtrl.text.trim(),
          'acquereur_tel':     _telCtrl.text.trim(),
          'acquereur_adresse': acqRue,
          if (acqCp.isNotEmpty) 'acquereur_cp': acqCp,
          if (acqVille.isNotEmpty) 'acquereur_ville': acqVille,
          // Filiation animale (préremplie, modifiable dans le contrat)
          if ('${widget.animal['nom_pere'] ?? ''}'.isNotEmpty) 'animal_nom_pere': '${widget.animal['nom_pere']}',
          if ('${widget.animal['nom_mere'] ?? ''}'.isNotEmpty) 'animal_nom_mere': '${widget.animal['nom_mere']}',
          if ('${widget.animal['puce_pere'] ?? ''}'.isNotEmpty) 'animal_puce_pere': '${widget.animal['puce_pere']}',
          if ('${widget.animal['puce_mere'] ?? ''}'.isNotEmpty) 'animal_puce_mere': '${widget.animal['puce_mere']}',
          if ('${widget.animal['identification'] ?? ''}'.isNotEmpty) 'animal_identification': '${widget.animal['identification']}',
          'prix':              _prixCtrl.text.trim(),
          'date_cession':      _dateCession.toIso8601String().split('T').first,
          'notes':             _notesCtrl.text.trim(),
        },
      }).select('token, id').single();

      final token = res['token'] as String;
      _createdDocIds.add(res['id'] as String);
      await _loadExistingDocs();
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ContratSignaturePage(token: token),
        ));
        await _loadExistingDocs();
      }
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() { _generatingPdf = false; _generatingCert = false; });
    }
  }

  Future<void> _genererPdf()       async => _ouvrirContratWeb('contrat_vente');
  Future<void> _genererCertificat() async => _ouvrirContratWeb('certificat_cession');

  /// Génère une facture PDF (montant = prix), l'enregistre dans documents_animaux
  /// (type `facture`) et la partage. TVA reprise du contrat sélectionné si
  /// « assujetti à la TVA » y est coché.
  Future<void> _genererFacture() async {
    final montant = double.tryParse(_prixCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (montant <= 0) {
      setState(() => _error = 'Renseignez d\'abord le prix pour générer une facture.');
      return;
    }
    setState(() { _generatingFacture = true; _error = null; });
    try {
      // TVA : contrat sélectionné en priorité, sinon n'importe quel contrat
      // « assujetti à la TVA » lié à cet animal.
      Map<String, dynamic> tvaMeta =
          (_selectedContrat?['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
      if (tvaMeta['tva_assujetti'] != true) {
        for (final c in _existingContrats) {
          final cm = (c['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
          if (cm['tva_assujetti'] == true) { tvaMeta = cm; break; }
        }
      }
      final tvaTaux = (tvaMeta['tva_assujetti'] == true)
          ? (double.tryParse('${tvaMeta['tva_taux'] ?? 20}'.replaceAll(',', '.')) ?? 20.0)
          : 0.0;
      final ht = tvaTaux > 0 ? montant / (1 + tvaTaux / 100) : montant;
      final tvaMontant = montant - ht;
      final eleveur = _eleveurProfile ?? {'nom': widget.nomElevage};
      final numero = 'F${_dateCession.year}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      final bytes = await factureVentePdfBytes(
        eleveur: {
          'name_elevage': eleveur['nom'],
          'firstname': eleveur['firstname'], 'lastname': eleveur['lastname'],
          'adress_elevage': (eleveur['adresse'] as String?) ??
              [eleveur['rue'], eleveur['code_postal'], eleveur['ville']]
                  .where((e) => e != null && '$e'.isNotEmpty).join(', '),
          'siret': eleveur['siret'],
          'email_contact': eleveur['email_contact'],
          'code_iso_elevage': '+33',
          'numero_elevage': eleveur['numero_elevage'] ?? eleveur['phone_number'],
        },
        animal: widget.animal,
        numero: numero,
        montantTtc: montant,
        tvaTaux: tvaTaux,
        acquereurNom: [_prenomCtrl.text.trim(), _nomCtrl.text.trim()].where((s) => s.isNotEmpty).join(' '),
        acquereurAdresse: _adresseCtrl.text.trim(),
        acquereurEmail: _emailCtrl.text.trim(),
        acquereurTel: _telCtrl.text.trim(),
        date: _dateCession,
      );

      final animalId = widget.animal['id'] as String;
      final path = 'cessions/${widget.uid}/$animalId/facture_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final snap = await FirebaseStorage.instance.ref(path).putData(bytes);
      final url = await snap.ref.getDownloadURL();

      final pid = User_Info.activeProfileId;
      final row = await _supa.from('documents_animaux').insert({
        'animal_id': animalId,
        'uid_eleveur': widget.uid,
        if (pid.isNotEmpty) 'pro_profile_id': pid,
        'type': 'facture',
        'titre': 'Facture $numero — ${widget.animal['nom'] ?? ''}'.trim(),
        'statut': 'genere',
        'url': url,
        'metadata': {'numero': numero, 'montant': montant, 'tva_taux': tvaTaux},
      }).select('id').single();
      _createdDocIds.add(row['id'] as String);

      // Enregistrer aussi dans « Mes factures » (table factures)
      try {
        final numRows = await _supa.from('factures').select('numero_facture')
            .eq('uid_eleveur', widget.uid)
            .order('numero_facture', ascending: false).limit(1);
        final rawNum = numRows.isEmpty ? null : numRows.first['numero_facture'];
        final nextNum = (rawNum is num
            ? rawNum.toInt()
            : int.tryParse('${rawNum ?? ''}') ?? 0) + 1;
        final adr = _adresseCtrl.text.trim();
        final cpMatch = RegExp(r'\b(\d{5})\b').firstMatch(adr);
        await _supa.from('factures').insert({
          'uid_eleveur': widget.uid,
          if (pid.isNotEmpty) 'profile_id': pid,
          'profil_source': 'eleveur',
          'token': _uuid(),
          'numero_facture': nextNum,
          'date_facture': _dateCession.toIso8601String().split('T').first,
          'date_prestation': _dateCession.toIso8601String().split('T').first,
          'lignes': [
            {
              'description': 'Cession — ${widget.animal['nom'] ?? 'animal'}'
                  '${widget.animal['espece'] != null ? ' (${widget.animal['espece']})' : ''}',
              'quantite': 1,
              // clés app (facturation.dart) + clés site (elevage/facturation)
              'prixUnitaireHT': double.parse(ht.toStringAsFixed(2)),
              'prixUnitaire': double.parse(ht.toStringAsFixed(2)),
              'tauxTVA': tvaTaux,
              'tva': tvaTaux,
              'totalHT': double.parse(ht.toStringAsFixed(2)),
              'montantTVA': double.parse(tvaMontant.toStringAsFixed(2)),
            }
          ],
          'total_ht': double.parse(ht.toStringAsFixed(2)),
          'total_tva': double.parse(tvaMontant.toStringAsFixed(2)),
          'total_ttc': montant,
          'regime_tva': tvaTaux > 0 ? 'normal' : 'franchise',
          'nom_client': _nomCtrl.text.trim(),
          'prenom_client': _prenomCtrl.text.trim(),
          'email_client': _emailCtrl.text.trim(),
          'telephone_client': _telCtrl.text.trim(),
          'rue_client': cpMatch != null ? adr.substring(0, cpMatch.start).trim() : adr,
          'cp_client': cpMatch?.group(1),
          'ville_client': cpMatch != null
              ? adr.substring(cpMatch.end).replaceFirst(RegExp(r'^[\s,]+'), '').trim() : null,
          'nom_emetteur': eleveur['nom'],
          'rue_emetteur': eleveur['rue'] ?? eleveur['adresse'],
          'cp_emetteur': eleveur['code_postal'],
          'ville_emetteur': eleveur['ville'] ?? eleveur['ville_pro'],
          'siret_emetteur': eleveur['siret'],
          'email_emetteur': eleveur['email_contact'],
          'statut': 'emise',
        });
      } catch (e) {
        // La facture PDF reste attachée à l'animal même si l'insert échoue,
        // mais on prévient l'utilisatrice qu'elle n'est pas dans « Mes factures ».
        debugPrint('[cession] insert factures échoué : $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Facture créée, mais non ajoutée à « Mes factures » : $e'),
            duration: const Duration(seconds: 5),
          ));
        }
      }

      await _loadExistingDocs();
      await Printing.sharePdf(bytes: bytes, filename: '$numero.pdf');
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur facture : $e');
    } finally {
      if (mounted) setState(() => _generatingFacture = false);
    }
  }

  Future<void> _ouvrirFacture(Map<String, dynamic> d) async {
    final url = d['url'] as String?;
    if (url == null) return;
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        await Printing.sharePdf(bytes: resp.bodyBytes, filename: '${d['titre'] ?? 'facture'}.pdf');
      }
    } catch (_) {}
  }

  Future<void> _ouvrirDoc(Map<String, dynamic> d) async {
    final token = (d['token'] as String?)?.trim();
    final id = d['id'] as String?;
    if ((token == null || token.isEmpty) && id == null) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ContratSignaturePage(
        token: (token != null && token.isNotEmpty) ? token : null,
        documentId: (token == null || token.isEmpty) ? id : null,
      ),
    ));
    await _loadExistingDocs();
  }

  Future<void> _supprimerDoc(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce document ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        content: const Text('Il sera définitivement supprimé pour les deux parties.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('documents_animaux').delete().eq('id', d['id']);
      _createdDocIds.remove(d['id']);
      if (_selectedContrat?['id'] == d['id']) _selectedContrat = null;
      if (_selectedCertificat?['id'] == d['id']) _selectedCertificat = null;
      await _loadExistingDocs();
    } catch (e) {
      if (mounted) setState(() => _error = 'Erreur suppression : $e');
    }
  }

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Le nom de l\'acquéreur est requis.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      // Utiliser le doc sélectionné ou uploadé manuellement
      final contratUrl     = _contratUrl ?? _selectedContrat?['url'] as String?;
      final certificatUrl  = _certificatUrl ?? _selectedCertificat?['url'] as String?;

      // Aucun document à signer → cession directe (animal cédé tout de suite).
      final hasDocuments = contratUrl != null || certificatUrl != null
          || _selectedContrat != null || _selectedCertificat != null
          || _existingContrats.any((d) => d['type'] != 'facture')
          || _existingCertificats.isNotEmpty;
      final finaliseNow = !widget.isReCession && !hasDocuments;
      final dateCessionStr = _dateCession.toIso8601String().split('T').first;

      final cedantProfileId = User_Info.activeProfileId;
      final acqUidForProfile = _foundUser?['uid'] as String?;
      final acqProfileId = acqUidForProfile != null
          ? await _resolveAcqProfileId(acqUidForProfile, _qualite) : null;
      final sterilOn = !widget.isReCession && _sterilisationRequise && _sterilisationEcheance != null;
      final sterilAgeMois = int.tryParse(_sterilAgeCtrl.text.trim());
      final sterilEcheanceStr = _sterilisationEcheance?.toIso8601String().split('T').first;
      final nomComplet = [_prenomCtrl.text.trim(), _nomCtrl.text.trim()]
          .where((s) => s.isNotEmpty).join(' ');
      // 1. Créer l'enregistrement de cession (sans transférer la fiche)
      final row = await _supa.from('cessions').insert({
        'animal_id':          widget.animal['id'],
        'uid_eleveur':        widget.uid,
        if (cedantProfileId.isNotEmpty) 'pro_profile_id': cedantProfileId,
        'uid_acquereur':      _foundUser?['uid'],
        if (acqProfileId != null) 'acquereur_profile_id': acqProfileId,
        'email_acquereur':    _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'prenom_acquereur':   _prenomCtrl.text.trim().isEmpty ? null : _prenomCtrl.text.trim(),
        'nom_acquereur':      nomComplet.isEmpty ? _nomCtrl.text.trim() : nomComplet,
        'tel_acquereur':      _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'adresse_acquereur':  _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'qualite':            _qualite,
        'prix':               _prixCtrl.text.isEmpty ? null : double.tryParse(_prixCtrl.text.replaceAll(',', '.')),
        'notes':              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'date_cession':       dateCessionStr,
        'statut':             finaliseNow ? 'confirme' : 'en_attente_acquereur',
        if (finaliseNow) 'confirmed_at': DateTime.now().toIso8601String(),
        'contrat_url':        contratUrl,
        'certificat_url':     certificatUrl,
        'sterilisation_requise':  sterilOn,
        if (sterilOn) 'sterilisation_age_mois': sterilAgeMois,
        if (sterilOn) 'sterilisation_echeance': sterilEcheanceStr,
      }).select('token, id').single();

      final token = row['token'] as String;
      _cessionSaved = true; // cession validée → on garde les contrats
      const baseUrl = kSiteBaseUrl;
      final signingUrl = '$baseUrl/signer-cession/$token';

      // 2. Passer l'animal en 'cession_en_cours' (ou 'sorti' si cession directe
      // sans document). uid_acquereur posé pour que l'acquéreur voie la fiche.
      await _supa.from('animaux').update({
        'statut':               finaliseNow ? 'sorti' : 'cession_en_cours',
        if (finaliseNow) 'date_sortie': dateCessionStr,
        'uid_acquereur':        _foundUser?['uid'],
        if (acqProfileId != null) 'profile_id_acquereur': acqProfileId,
        'destinataire_qualite': _qualite,
        'destinataire_nom':     nomComplet.isEmpty ? _nomCtrl.text.trim() : nomComplet,
        'destinataire_adresse': _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'cession_prix':         _prixCtrl.text.isEmpty ? null : double.tryParse(_prixCtrl.text.replaceAll(',', '.')),
        'cession_notes':        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'cession_contrat_url':  contratUrl,
        'cession_certificat_url': certificatUrl,
        'sterilisation_requise':  sterilOn,
        if (sterilOn) 'sterilisation_echeance': sterilEcheanceStr,
        if (sterilOn) 'sterilisation_validee': false,
        if (sterilOn) 'sterilisation_eleveur_uid': widget.uid,
        if (sterilOn && cedantProfileId.isNotEmpty) 'sterilisation_eleveur_profile_id': cedantProfileId,
      }).eq('id', widget.animal['id']);

      // 3. Résoudre le profil (is_main) de l'acquéreur — utilisé pour la
      // notification ci-dessous. Le transfert de propriété dans
      // animaux_proprietes (clôture cédant + ouverture acquéreur,
      // date_debut/date_fin) n'a lieu qu'à la cession DÉFINITIVE, une fois
      // confirmée par l'éleveur — voir confirmerCession() côté web
      // (mes-animaux/[id]/page.tsx). Le faire ici, dès 'cession_en_cours',
      // ferait apparaître l'animal comme "ancien" dans la liste alors que la
      // fiche permet encore de révoquer la cession.
      // 4. Notifier l'acquéreur (sur le profil qui recevra l'animal).
      // Si un contrat de vente a été créé, la notif pointe dessus (lecture +
      // signature) ; sinon sur le récap de cession.
      final contratDoc = _selectedContrat ??
          (_existingContrats.isNotEmpty ? _existingContrats.first : null);
      final contratToken = contratDoc?['token'] as String?;
      final contratId = contratDoc?['id'] as String?;
      final contratUrlSign = contratToken != null
          ? '$kSiteBaseUrl/signer-contrat/$contratToken' : null;
      if (finaliseNow && _foundUser?['uid'] != null) {
        // Cession directe : transfert de propriété tout de suite.
        final acqUid = _foundUser!['uid'] as String;
        try {
          await _supa.from('animaux_proprietes')
              .update({'date_fin': dateCessionStr})
              .eq('animal_id', widget.animal['id'])
              .eq('uid_proprio', widget.uid)
              .isFilter('date_fin', null);
          await _supa.from('animaux_proprietes').upsert({
            'animal_id':   widget.animal['id'],
            'uid_proprio': acqUid,
            'date_debut':  dateCessionStr,
            'date_fin':    null,
            if (acqProfileId != null) 'profile_id_proprio': acqProfileId,
          }, onConflict: 'animal_id,uid_proprio');
        } catch (_) {}
        await _supa.from('notifications').insert({
          'uid':   acqUid,
          'type':  'cession_confirmee',
          'title': '🐾 Animal reçu : ${widget.animal['nom'] ?? 'Animal'}',
          'body':  '${widget.nomElevage} vous a cédé ${widget.animal['nom'] ?? 'un animal'}. Il apparaît dans votre compte.',
          if (acqProfileId != null) 'profile_id': acqProfileId,
          'data':  {'animalId': widget.animal['id']},
          'read':  false,
        });
      } else if (_foundUser?['uid'] != null) {
        await _supa.from('notifications').insert({
          'uid':   _foundUser!['uid'],
          'type':  contratToken != null ? 'contrat_signe_eleveur' : 'cession_signature_demandee',
          'title': '✍️ Signature requise — ${widget.animal['nom'] ?? 'Animal'}',
          'body':  '${widget.nomElevage} souhaite vous céder ${widget.animal['nom'] ?? 'un animal'}. Vérifiez et signez le contrat.',
          if (acqProfileId != null) 'profile_id': acqProfileId,
          'data':  {
            'animalId': widget.animal['id'],
            'token': contratToken ?? token,
            if (contratId != null) 'documentId': contratId,
            'url': contratUrlSign ?? signingUrl,
            'signingUrl': contratUrlSign ?? signingUrl,
          },
          'read':  false,
        });
      }
      // Email si adresse fournie (avec ou sans compte)
      if (!finaliseNow && _emailCtrl.text.trim().isNotEmpty) {
        try {
          await http.post(
            Uri.parse('$kSiteBaseUrl/api/cession/notify-email'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email':        _emailCtrl.text.trim(),
              'nom_acquereur': _nomCtrl.text.trim(),
              'animal_nom':   widget.animal['nom'] ?? 'Animal',
              'eleveur_nom':  widget.nomElevage,
              'signing_url':  signingUrl,
              'prix':         _prixCtrl.text.trim().isEmpty ? null : _prixCtrl.text.trim(),
              'date_cession': dateCessionStr,
            }),
          );
        } catch (_) {}
      }

      // Clôturer la réservation d'origine s'il y en avait une
      if (widget.reservation != null) {
        await _supa.from('reservations_animaux')
            .update({'statut': 'transformee', 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', widget.reservation!['id']);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onCeded();
        if (finaliseNow) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Cession finalisée — animal cédé'),
            backgroundColor: Color(0xFF6E9E57),
          ));
        } else {
          showDialog(
            context: context,
            builder: (_) => _SigningLinkDialog(
              url: signingUrl,
              token: token,
              nomAcquereur: _nomCtrl.text.trim(),
              hasAccount: _foundUser != null,
            ),
          );
        }
      }
    } catch (e) {
      setState(() { _saving = false; _error = 'Erreur : $e'; });
    }
  }

  // ── Validation / helpers formulaire ───────────────────────────────────────
  // Pour une cession éleveur, prénom + nom + email + téléphone + adresse sont
  // obligatoires (nécessaires pour joindre l'acquéreur, notamment pour les
  // rappels de stérilisation). Pour une re-cession particulier, seul le nom.
  String _req(String label) => widget.isReCession && label != 'Nom' ? label : '$label *';

  bool _detailsValid() {
    if (_nomCtrl.text.trim().isEmpty) return false;
    if (widget.isReCession) return true;
    if (_prenomCtrl.text.trim().isEmpty) return false;
    if (_emailCtrl.text.trim().isEmpty) return false;
    if (_telCtrl.text.trim().isEmpty) return false;
    if (_adresseCtrl.text.trim().isEmpty) return false;
    if (_sterilisationRequise &&
        (int.tryParse(_sterilAgeCtrl.text.trim()) ?? 0) <= 0) return false;
    return true;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _sterilisationBlock() {
    final dn = _dateNaissanceAnimal;
    final echeance = _sterilisationEcheance;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeThumbColor: _green,
          title: const Text('Condition de stérilisation',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _dark)),
          subtitle: Text(
            dn == null
                ? 'Renseignez la date de naissance de l\'animal pour activer cette condition.'
                : 'Le nouveau propriétaire devra faire stériliser l\'animal avant l\'âge fixé.',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          value: _sterilisationRequise,
          onChanged: dn == null ? null : (v) => setState(() => _sterilisationRequise = v),
        ),
        if (_sterilisationRequise) ...[
          const SizedBox(height: 6),
          Row(children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: _sterilAgeCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: _inputDec('12'),
              ),
            ),
            const SizedBox(width: 8),
            const Text('mois maximum', style: TextStyle(fontSize: 12, color: _dark)),
          ]),
          const SizedBox(height: 8),
          Text(
            echeance != null
                ? '📅 Échéance : ${_fmtDate(echeance)}'
                : 'Saisissez un âge en mois valide.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _teal),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle + titre
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                widget.isReCession
                  ? '🔄 Transférer ${widget.animal['nom'] ?? 'cet animal'}'
                  : '🤝 Céder ${widget.animal['nom'] ?? 'cet animal'}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _dark),
              ),
              Text(
                widget.isReCession ? 'Don / Abandon' : 'Étape ${_step + 1}/3',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ])),
            if (_step > 0)
              GestureDetector(
                onTap: () => setState(() => _step--),
                child: const Icon(Icons.chevron_left, color: _teal),
              ),
          ]),
          const SizedBox(height: 16),

          if (_error != null)
            Container(margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                child: Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700))),

          // ── Étape 0 : Acquéreur ─────────────────────────────
          if (_step == 0) ...[
            const Text('Rechercher sur PetsMatch',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextField(
                controller: _searchCtrl,
                onSubmitted: (_) => _searchUser(),
                decoration: InputDecoration(
                  hintText: 'Nom, prénom ou email…',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _teal, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _searching ? null : _searchUser,
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _searching ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Chercher'),
              ),
            ]),
            // Résultats multiples
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...(_searchResults.map((r) => GestureDetector(
                onTap: () => _selectUser(r),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    const Icon(Icons.person_outline, color: _teal, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['nom'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Galey')),
                      if (r['email'] != null) Text(r['email'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ])),
                    const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                  ]),
                ),
              ))),
            ],
            // Résultat unique trouvé
            if (_searchDone && _searchResults.isEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _foundUser != null ? _teal.withOpacity(0.06) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _foundUser != null ? _teal.withOpacity(0.2) : Colors.grey.shade200),
                ),
                child: _foundUser != null
                    ? Row(children: [
                        const Icon(Icons.verified_user_outlined, color: _teal, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_foundUser!['nom'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: _teal, fontFamily: 'Galey'))),
                      ])
                    : const Text('Aucun utilisateur trouvé.', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Divider()),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('ou', style: TextStyle(color: Colors.grey, fontSize: 12))),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() { _step = 1; }),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Saisie manuelle', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _dark,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
            if (_foundUser != null) ...[
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => setState(() => _step = 1),
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Continuer →', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ],
          ],

          // ── Étape 1 : Détails ────────────────────────────────
          if (_step == 1) ...[
            if (_foundUser != null) Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _teal.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.verified_user_outlined, color: _teal, size: 16),
                const SizedBox(width: 6),
                Text(_foundUser!['nom'] as String,
                    style: const TextStyle(color: _teal, fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
            Row(children: [
              Expanded(child: _FieldBlock('Qualité', child: DropdownButtonFormField<String>(
                value: _qualite,
                items: [
                  const DropdownMenuItem(value: 'particulier', child: Text('Particulier / Famille')),
                  const DropdownMenuItem(value: 'refuge',      child: Text('Association / Refuge')),
                  // Options réservées aux éleveurs d'origine
                  if (!widget.isReCession) ...[
                    const DropdownMenuItem(value: 'eleveur', child: Text('Éleveur')),
                    const DropdownMenuItem(value: 'autre',   child: Text('Autre')),
                  ],
                ],
                onChanged: (v) => setState(() => _qualite = v!),
                decoration: _inputDec('Qualité'),
              ))),
              const SizedBox(width: 8),
              Expanded(child: _FieldBlock('Date de cession', child: GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(context: context,
                      initialDate: _dateCession, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) setState(() => _dateCession = d);
                },
                child: Container(
                  height: 48,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${_dateCession.day.toString().padLeft(2, '0')}/${_dateCession.month.toString().padLeft(2, '0')}/${_dateCession.year}',
                      style: const TextStyle(fontSize: 13)),
                ),
              ))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _FieldBlock(_req('Prénom'), child: TextField(
                controller: _prenomCtrl,
                onChanged: (_) => setState(() {}),
                decoration: _inputDec('Prénom'),
              ))),
              const SizedBox(width: 8),
              Expanded(child: _FieldBlock(_req('Nom'), child: TextField(
                controller: _nomCtrl,
                onChanged: (_) => setState(() {}),
                decoration: _inputDec('Nom'),
              ))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _FieldBlock(_req('Email'), child: TextField(
                controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                decoration: _inputDec('email@exemple.fr'),
              ))),
              const SizedBox(width: 8),
              Expanded(child: _FieldBlock(_req('Téléphone'), child: TextField(
                controller: _telCtrl, keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: _inputDec('06 XX XX XX XX'),
              ))),
            ]),
            const SizedBox(height: 10),
            _FieldBlock(_req('Adresse postale'), child: TextField(
              controller: _adresseCtrl,
              onChanged: (_) => setState(() {}),
              decoration: _inputDec('Adresse de l\'acquéreur'),
            )),
            if (!widget.isReCession) ...[
              const SizedBox(height: 10),
              _FieldBlock('Prix (€)', child: TextField(
                controller: _prixCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _inputDec('0'),
              )),
            ],
            const SizedBox(height: 10),
            _FieldBlock('Notes', child: TextField(
              controller: _notesCtrl, maxLines: 2,
              decoration: _inputDec('Conditions particulières…'),
            )),

            // ── Condition de stérilisation (cession éleveur) ──
            if (!widget.isReCession) ...[
              const SizedBox(height: 14),
              _sterilisationBlock(),
            ],

            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: !_detailsValid() ? null : () {
                if (widget.isReCession) {
                  // Particulier qui re-cède : pas de documents, valider directement
                  _save();
                } else {
                  setState(() => _step = 2);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(
                widget.isReCession ? 'Confirmer le transfert' : 'Documents →',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600),
              ),
            ),
            if (!widget.isReCession) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: (!_detailsValid() || _saving) ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Valider sans document (remise en main propre)',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal)),
              ),
            ],
          ],

          // ── Étape 2 : Documents ──────────────────────────────
          if (_step == 2) ...[
            if (_loadingDocs)
              const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: CircularProgressIndicator()))
            else ...[
              // ── Certificat de cession ───────────────────────
              _docSectionHeader('📜 Certificat de cession / engagement'),
              const SizedBox(height: 8),
              if (_existingCertificats.isEmpty)
                _docEmptyHint('Aucun certificat existant')
              else
                for (final d in _existingCertificats)
                  _docPickerTile(
                    doc: d,
                    selected: _selectedCertificat?['id'] == d['id'],
                    onTap: () => setState(() =>
                      _selectedCertificat = _selectedCertificat?['id'] == d['id'] ? null : Map.from(d)),
                    onOpen: () => _ouvrirDoc(d),
                    onDelete: () => _supprimerDoc(d),
                  ),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(
                  onPressed: _generatingCert ? null : _genererCertificat,
                  icon: _generatingCert
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_circle_outline, size: 14),
                  label: Text(_generatingCert ? 'Création…' : 'Créer nouveau',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: _uploadingCertificat ? null : () => _uploadDoc('certificat'),
                  icon: _uploadingCertificat
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_outlined, size: 14),
                  label: Text(_uploadingCertificat ? 'Upload…' : 'Importer PDF',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
                ),
                if (_certificatUrl != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, color: _green, size: 14),
                  const Text(' importé', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green)),
                ],
              ]),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // ── Contrat de vente / réservation ───────────────
              _docSectionHeader('🤝 Contrat de vente / réservation'),
              const SizedBox(height: 8),
              if (_existingContrats.isEmpty)
                _docEmptyHint('Aucun contrat existant')
              else
                for (final d in _existingContrats)
                  _docPickerTile(
                    doc: d,
                    selected: _selectedContrat?['id'] == d['id'],
                    onTap: () => setState(() =>
                      _selectedContrat = _selectedContrat?['id'] == d['id'] ? null : Map.from(d)),
                    onOpen: () => _ouvrirDoc(d),
                    onDelete: () => _supprimerDoc(d),
                  ),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(
                  onPressed: _generatingPdf ? null : _genererPdf,
                  icon: _generatingPdf
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_circle_outline, size: 14),
                  label: Text(_generatingPdf ? 'Création…' : 'Créer nouveau',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: _uploadingContrat ? null : () => _uploadDoc('contrat'),
                  icon: _uploadingContrat
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_outlined, size: 14),
                  label: Text(_uploadingContrat ? 'Upload…' : 'Importer PDF',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
                ),
                if (_contratUrl != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, color: _green, size: 14),
                  const Text(' importé', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green)),
                ],
              ]),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // ── Facture (optionnel) ─────────────────────────
              _docSectionHeader('🧾 Facture (optionnel)'),
              const SizedBox(height: 8),
              if (_existingFactures.isEmpty)
                _docEmptyHint('Aucune facture générée')
              else
                for (final d in _existingFactures)
                  _docPickerTile(
                    doc: d,
                    selected: false,
                    onTap: () => _ouvrirFacture(d),
                    onOpen: () => _ouvrirFacture(d),
                    onDelete: () => _supprimerDoc(d),
                    openLabel: 'Ouvrir / partager',
                  ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _generatingFacture ? null : _genererFacture,
                icon: _generatingFacture
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.receipt_long_outlined, size: 14),
                label: Text(_generatingFacture ? 'Génération…' : 'Générer la facture (montant = prix)',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('✓ Valider la cession', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            const Center(child: Text('Les documents sont optionnels.',
                style: TextStyle(fontSize: 11, color: Colors.grey))),
          ],
        ])),
      ),
    );
  }
}

// ── Helpers UI ────────────────────────────────────────────────────────────────

Widget _docSectionHeader(String title) => Text(title,
    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
        fontSize: 13, color: Color(0xFF1F2A2E)));

Widget _docEmptyHint(String msg) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(msg, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)));

// Tuile de sélection d'un document existant
Widget _docPickerTile({
  required Map<String, dynamic> doc,
  required bool selected,
  required VoidCallback onTap,
  VoidCallback? onOpen,
  VoidCallback? onDelete,
  String openLabel = 'Lire / modifier / signer',
}) {
  final type = doc['type'] as String? ?? '';
  final statut = doc['statut'] as String? ?? '';
  final typeLabel = type == 'certificat_cession'
      ? 'Certificat de cession'
      : type == 'facture'
          ? (doc['titre'] as String? ?? 'Facture')
          : type == 'contrat_reservation' ? 'Contrat de réservation' : 'Contrat de vente';
  final statutLabel = type == 'facture'
      ? '🧾 Facture générée'
      : statut == 'signe'
          ? '✅ Signé'
          : statut == 'partiellement_signe' ? '✍️ Partiellement signé'
          : statut == 'en_attente' ? '⏳ En attente signature' : '📝 Brouillon';
  final rawDate = doc['created_at'] as String?;
  final date = rawDate != null
      ? '${DateTime.parse(rawDate).day.toString().padLeft(2, '0')}/${DateTime.parse(rawDate).month.toString().padLeft(2, '0')}/${DateTime.parse(rawDate).year}'
      : '';

  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6, right: 4),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFECFDF5) : Colors.grey.shade50,
        border: Border.all(
            color: selected ? const Color(0xFF059669) : Colors.grey.shade200,
            width: selected ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18, color: selected ? const Color(0xFF059669) : Colors.grey.shade400),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(typeLabel, style: const TextStyle(
              fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
              color: Color(0xFF1F2A2E))),
          const SizedBox(height: 2),
          Text('$statutLabel${date.isNotEmpty ? '  ·  $date' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
        ])),
        if (onOpen != null || (onDelete != null && statut != 'signe'))
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF6F767B)),
            tooltip: 'Actions',
            onSelected: (v) {
              if (v == 'open') onOpen?.call();
              if (v == 'delete') onDelete?.call();
            },
            itemBuilder: (_) => [
              if (onOpen != null)
                PopupMenuItem(
                  value: 'open',
                  child: Row(children: [
                    const Icon(Icons.draw_outlined, size: 18, color: _teal),
                    const SizedBox(width: 10),
                    Text(openLabel, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  ]),
                ),
              if (onDelete != null && statut != 'signe')
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                    const SizedBox(width: 10),
                    const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.red)),
                  ]),
                ),
            ],
          ),
      ]),
    ),
  );
}

InputDecoration _inputDec(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 2)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
);

class _FieldBlock extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldBlock(this.label, {required this.child});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
    const SizedBox(height: 4),
    child,
  ]);
}


// ── Dialogue lien de signature ────────────────────────────────────────────────

class _SigningLinkDialog extends StatelessWidget {
  final String url;
  final String token;
  final String nomAcquereur;
  final bool hasAccount;

  const _SigningLinkDialog({required this.url, required this.token, required this.nomAcquereur, required this.hasAccount});

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text('✅ Cession en cours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (hasAccount)
        const Text('Une notification a été envoyée à l\'acquéreur. L\'animal reste dans votre compte jusqu\'à votre confirmation finale.')
      else ...[
        Text('Partagez ce lien de signature à $nomAcquereur :',
            style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF0C5C6C).withOpacity(0.3))),
          child: Text(url, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF0C5C6C))),
        ),
      ],
      const SizedBox(height: 10),
      const Text('L\'animal restera dans votre compte. Une fois l\'acquéreur signé, vous recevrez une notification pour confirmer ou révoquer la cession.',
          style: TextStyle(fontSize: 11, color: Colors.grey)),
    ]),
    actions: [
      TextButton(
        onPressed: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => ContratSignaturePage(cessionToken: token),
          ));
        },
        child: const Text('✍️ Signer dans l\'appli', style: TextStyle(color: Color(0xFF0C5C6C), fontFamily: 'Galey')),
      ),
      TextButton(
        onPressed: () { Clipboard.setData(ClipboardData(text: url)); Navigator.pop(context); },
        child: const Text('📋 Copier le lien', style: TextStyle(color: Color(0xFF0C5C6C), fontFamily: 'Galey')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer', style: TextStyle(color: Colors.grey)),
      ),
    ],
  );
}
