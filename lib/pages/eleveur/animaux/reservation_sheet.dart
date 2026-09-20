import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;

const _teal  = Color(0xFF0C5C6C);
const _amber = Color(0xFFD97706);
const _dark  = Color(0xFF1F2A2E);

const _especesDelaiLegal = {'chien', 'chat'};

/// Choix pour chaque document (contrat de réservation / certificat
/// d'engagement) — jamais imposé : toujours possible de passer l'étape,
/// générer dans l'app, ou apporter son propre document déjà signé.
enum _DocChoice { skip, generate, upload }

({String prenom, String nom}) _splitNom(String nomComplet) {
  final parts = nomComplet.trim().split(RegExp(r'\s+'));
  if (parts.length <= 1) return (prenom: parts.isEmpty ? '' : parts.first, nom: '');
  return (prenom: parts.first, nom: parts.skip(1).join(' '));
}

// ── Feuille de réservation (avant cession) ─────────────────────────────────────

class ReservationSheet extends StatefulWidget {
  final Map<String, dynamic> animal;
  final String uid;
  final VoidCallback onReserved;

  const ReservationSheet({
    super.key,
    required this.animal,
    required this.uid,
    required this.onReserved,
  });

  @override
  State<ReservationSheet> createState() => _ReservationSheetState();
}

class _ReservationSheetState extends State<ReservationSheet> {
  final _supa = Supabase.instance.client;

  int _step = 0; // 0 = futur propriétaire, 1 = détails, 2 = documents

  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _foundUser;
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  bool _searchDone = false;

  String _qualite = 'particulier';
  final _nomCtrl     = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _telCtrl     = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _acompteCtrl = TextEditingController();
  final _notesCtrl   = TextEditingController();
  late DateTime _dateReservation;

  // Documents optionnels — contrat de réservation et/ou certificat
  // d'engagement (légal, chien/chat). Chacun : passer l'étape, générer dans
  // l'app, ou apporter son propre document déjà signé. Si les deux restent
  // sur "passer", la réservation reste simple (papier hors application).
  _DocChoice _contratChoice = _DocChoice.skip;
  PlatformFile? _contratFile;
  _DocChoice _certifChoice = _DocChoice.skip;
  PlatformFile? _certifFile;
  final _certifPrenomCtrl = TextEditingController();
  final _certifNomCtrl    = TextEditingController();
  bool _certifNameTouched = false;

  bool _generatingContrat = false;
  bool _certifSaving = false;
  String? _certifError;
  String? _certifToken;

  bool _saving = false;
  String? _error;

  static const _cpFields = 'uid, firstname, lastname, nom, profile_type, avatar_url, phone_number, adresse, rue, ville, code_postal, numero_elevage, email_contact';

  bool get _needsDelaiLegal => _especesDelaiLegal.contains((widget.animal['espece'] as String? ?? '').toLowerCase());

  @override
  void initState() {
    super.initState();
    _dateReservation = DateTime.now();
    _nomCtrl.addListener(_syncCertifName);
  }

  void _syncCertifName() {
    if (_certifNameTouched) return;
    final split = _splitNom(_nomCtrl.text);
    _certifPrenomCtrl.text = split.prenom;
    _certifNomCtrl.text = split.nom;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nomCtrl.removeListener(_syncCertifName);
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    _adresseCtrl.dispose();
    _acompteCtrl.dispose();
    _notesCtrl.dispose();
    _certifPrenomCtrl.dispose();
    _certifNomCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _mapProfile(Map<String, dynamic> cp, {String? email}) => {
    'uid': cp['uid'],
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
        final cpList = List<Map<String, dynamic>>.from(cps as List);
        // email_contact est souvent vide alors que le compte a bien un email
        // de connexion (table users) — sans ce complément, un utilisateur
        // pourtant déjà inscrit ressort sans email pré-rempli.
        final uids = cpList.map((c) => c['uid'] as String).toSet().toList();
        final loginEmails = uids.isEmpty
            ? <Map<String, dynamic>>[]
            : List<Map<String, dynamic>>.from(
                await _supa.from('users').select('uid, email').inFilter('uid', uids) as List);
        final emailByUid = { for (final u in loginEmails) u['uid'] as String: u['email'] as String? };
        rows = cpList.map((cp) => _mapProfile(cp, email: emailByUid[cp['uid']])).toList();
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

  void _selectUser(Map<String, dynamic> r) {
    final isElv = r['is_elevage'] == true;
    final adresse = isElv
        ? (r['adress_elevage'] as String? ?? [r['rue'], r['ville'], r['code_postal']].where((e) => e != null).join(', '))
        : (r['adress'] as String? ?? [r['rue'], r['ville'], r['code_postal']].where((e) => e != null).join(', '));
    final tel = isElv
        ? '${r['code_iso_elevage'] ?? '+33'} ${r['numero_elevage'] ?? ''}'.trim()
        : '${r['code_iso'] ?? '+33'} ${r['phone_number'] ?? ''}'.trim();
    setState(() {
      _foundUser = r;
      _nomCtrl.text    = r['nom'] as String;
      _emailCtrl.text  = (r['email'] as String? ?? '');
      _telCtrl.text    = tel;
      _adresseCtrl.text = adresse;
      _searchResults   = [];
      if (isElv) _qualite = 'eleveur';
      if (!isElv) {
        _certifNameTouched = true;
        _certifPrenomCtrl.text = (r['firstname'] as String?) ?? '';
        _certifNomCtrl.text    = (r['lastname'] as String?) ?? '';
      }
    });
  }

  Future<void> _pickContratFile() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    final f = res?.files.single;
    if (f?.path == null) return;
    setState(() => _contratFile = f);
  }

  Future<void> _pickCertifFile() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    final f = res?.files.single;
    if (f?.path == null) return;
    setState(() => _certifFile = f);
  }

  // Insère directement le document (comme cession_sheet.dart pour contrat_vente/
  // certificat_cession) — signer-contrat/[token] génère le HTML à la volée à
  // partir de ces métadonnées, pas besoin d'un formulaire interactif ici.
  Future<void> _creerContratReservation() async {
    setState(() { _generatingContrat = true; _error = null; });
    try {
      final animalId = widget.animal['id'] as String;
      final nomAnimal = widget.animal['nom'] as String? ?? '';
      final pid = User_Info.activeProfileId;

      String? uploadedUrl;
      if (_contratChoice == _DocChoice.upload && _contratFile?.path != null) {
        uploadedUrl = await storage.uploadDocument(
          File(_contratFile!.path!),
          'contrats_reservation/${widget.uid}/${DateTime.now().millisecondsSinceEpoch}_${_contratFile!.name}',
        );
      }

      final res = await _supa.from('documents_animaux').insert({
        'animal_id':   animalId,
        'uid_eleveur': widget.uid,
        if (pid.isNotEmpty) 'pro_profile_id': pid,
        'type':        'contrat_reservation',
        'titre':       'Contrat de réservation — $nomAnimal',
        'statut':      uploadedUrl != null ? 'signe' : 'brouillon',
        if (uploadedUrl != null) 'pdf_signe_url': uploadedUrl,
        'metadata': {
          'acquereur_nom':     _nomCtrl.text.trim(),
          'acquereur_email':   _emailCtrl.text.trim(),
          'acquereur_tel':     _telCtrl.text.trim(),
          'acquereur_adresse': _adresseCtrl.text.trim(),
          'prix':              _acompteCtrl.text.trim(),
          'date_cession':      _dateReservation.toIso8601String().split('T').first,
          'notes':             _notesCtrl.text.trim(),
        },
      }).select('token').single();

      final token = res['token'] as String;
      if (uploadedUrl == null && mounted) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ContratSignaturePage(token: token),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Document ajouté au contrat')));
      }
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      setState(() => _generatingContrat = false);
    }
  }

  /// Certificat apporté par l'éleveur (déjà signé hors app) — insertion
  /// directe dans `certificats_engagement`, pas besoin de signature dans
  /// l'appli ni de passer par l'API de création.
  Future<void> _importerCertificatEngagement() async {
    if (_certifPrenomCtrl.text.trim().isEmpty || _certifNomCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) {
      setState(() => _certifError = 'Prénom, nom et email du futur propriétaire sont requis pour le certificat.');
      return;
    }
    if (_certifFile?.path == null) return;
    setState(() { _certifSaving = true; _certifError = null; });
    try {
      final uploadedUrl = await storage.uploadDocument(
        File(_certifFile!.path!),
        'certificats_engagement/${widget.uid}/${DateTime.now().millisecondsSinceEpoch}_${_certifFile!.name}',
      );
      final now = DateTime.now();
      final res = await _supa.from('certificats_engagement').insert({
        'cedant_uid':            widget.uid,
        'animal_id':             widget.animal['id'],
        'espece':                widget.animal['espece'] ?? '',
        'race':                  widget.animal['race'],
        'nom_animal':            widget.animal['nom'] ?? '',
        'date_naissance_animal': widget.animal['date_naissance'],
        'num_identification':    widget.animal['identification'],
        'acquereur_uid':         _foundUser?['uid'],
        'acquereur_nom':         _certifNomCtrl.text.trim(),
        'acquereur_prenom':      _certifPrenomCtrl.text.trim(),
        'acquereur_email':       _emailCtrl.text.trim(),
        'acquereur_telephone':   _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'acquereur_adresse':     _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'modalite_cession':      _qualite == 'autre' ? 'gratuit' : 'vente',
        'prix':                  _acompteCtrl.text.trim().isEmpty ? null : double.tryParse(_acompteCtrl.text.replaceAll(',', '.')),
        'date_remise':           now.toIso8601String(),
        'notes':                 _notesCtrl.text.trim(),
        'profil_source':         User_Info.isAssociation ? 'association' : 'eleveur',
        'pdf_url':               uploadedUrl,
        'statut':                'signe',
      }).select('token_signature').single();
      setState(() => _certifToken = res['token_signature'] as String?);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Certificat ajouté')));
      }
    } catch (e) {
      setState(() => _certifError = 'Erreur : $e');
    } finally {
      setState(() => _certifSaving = false);
    }
  }

  Future<void> _creerCertificatEngagement() async {
    if (_certifPrenomCtrl.text.trim().isEmpty || _certifNomCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty) {
      setState(() => _certifError = 'Prénom, nom et email du futur propriétaire sont requis pour le certificat.');
      return;
    }
    setState(() { _certifSaving = true; _certifError = null; });
    try {
      final dateRemise = DateTime.now();
      final dateLimite = _needsDelaiLegal ? dateRemise.add(const Duration(days: 7)) : null;
      final res = await http.post(
        Uri.parse('$kSiteBaseUrl/api/certificat/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid':                    widget.uid,
          'animal_id':              widget.animal['id'],
          'espece':                 widget.animal['espece'] ?? '',
          'race':                   widget.animal['race'],
          'nom_animal':             widget.animal['nom'] ?? '',
          'date_naissance_animal':  widget.animal['date_naissance'],
          'num_identification':     widget.animal['identification'],
          'acquereur_uid':          _foundUser?['uid'],
          'acquereur_nom':          _certifNomCtrl.text.trim(),
          'acquereur_prenom':       _certifPrenomCtrl.text.trim(),
          'acquereur_email':        _emailCtrl.text.trim(),
          'acquereur_telephone':    _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
          'acquereur_adresse':      _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
          'modalite_cession':       _qualite == 'autre' ? 'gratuit' : 'vente',
          'prix':                   _acompteCtrl.text.trim().isEmpty ? null : double.tryParse(_acompteCtrl.text.replaceAll(',', '.')),
          'date_remise':            dateRemise.toIso8601String(),
          'date_limite_signature':  dateLimite?.toIso8601String(),
          'notes':                  _notesCtrl.text.trim(),
        }),
      );
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        setState(() => _certifError = json['error'] as String? ?? 'Erreur serveur');
        return;
      }
      final token = json['token'] as String?;
      setState(() => _certifToken = token);
      // Ouvre le certificat dans l'appli (lecture + « Envoyer au futur
      // propriétaire ») — comme _creerContratReservation pour le contrat.
      if (token != null && mounted) {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ContratSignaturePage(certificatEngagementToken: token),
        ));
      }
    } catch (e) {
      setState(() => _certifError = 'Erreur : $e');
    } finally {
      setState(() => _certifSaving = false);
    }
  }

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Le nom du futur propriétaire est requis.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final profileId = User_Info.activeProfileId;
      await _supa.from('reservations_animaux').insert({
        'animal_id':   widget.animal['id'],
        'uid_eleveur': widget.uid,
        if (profileId.isNotEmpty) 'eleveur_profile_id': profileId,
        'statut':      'active',
        'qualite':     _qualite,
        'nom':         _nomCtrl.text.trim(),
        'email':       _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'tel':         _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'adresse':     _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'uid_acquereur': _foundUser?['uid'],
        'date_reservation': _dateReservation.toIso8601String().split('T').first,
        'notes':       _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      });
      await _supa.from('animaux').update({'statut': 'reserve'}).eq('id', widget.animal['id']);
      if (mounted) {
        Navigator.pop(context);
        widget.onReserved();
      }
    } catch (e) {
      setState(() { _saving = false; _error = 'Erreur : $e'; });
    }
  }

  String get _stepLabel => _step == 0 ? 'Étape 1/2 — Futur propriétaire'
      : _step == 1 ? 'Étape 2/2 — Détails'
      : 'Documents';

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
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🔖 Réserver ${widget.animal['nom'] ?? 'cet animal'}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _dark)),
              Text(_stepLabel, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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

          // ── Étape 0 : Futur propriétaire ─────────────────────
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
            if (_searchDone && _searchResults.isEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _foundUser != null ? _teal.withValues(alpha: 0.06) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _foundUser != null ? _teal.withValues(alpha: 0.2) : Colors.grey.shade200),
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
              decoration: BoxDecoration(color: _teal.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.verified_user_outlined, color: _teal, size: 16),
                const SizedBox(width: 6),
                Text(_foundUser!['nom'] as String,
                    style: const TextStyle(color: _teal, fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
            _FieldBlock('Date de réservation', child: GestureDetector(
              onTap: () async {
                final d = await showDatePicker(context: context,
                    initialDate: _dateReservation, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _dateReservation = d);
              },
              child: Container(
                height: 48,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${_dateReservation.day.toString().padLeft(2, '0')}/${_dateReservation.month.toString().padLeft(2, '0')}/${_dateReservation.year}',
                    style: const TextStyle(fontSize: 13)),
              ),
            )),
            const SizedBox(height: 10),
            _FieldBlock('Qualité', child: DropdownButtonFormField<String>(
              value: _qualite,
              items: const [
                DropdownMenuItem(value: 'particulier', child: Text('Particulier')),
                DropdownMenuItem(value: 'eleveur',     child: Text('Éleveur')),
                DropdownMenuItem(value: 'refuge',      child: Text('Refuge / Association')),
                DropdownMenuItem(value: 'autre',       child: Text('Autre')),
              ],
              onChanged: (v) => setState(() => _qualite = v!),
              decoration: _inputDec('Qualité'),
            )),
            const SizedBox(height: 10),
            _FieldBlock('Nom du futur propriétaire *', child: TextField(
              controller: _nomCtrl,
              decoration: _inputDec('Nom complet'),
            )),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _FieldBlock('Email', child: TextField(
                controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                decoration: _inputDec('email@exemple.fr'),
              ))),
              const SizedBox(width: 8),
              Expanded(child: _FieldBlock('Téléphone', child: TextField(
                controller: _telCtrl, keyboardType: TextInputType.phone,
                decoration: _inputDec('06 XX XX XX XX'),
              ))),
            ]),
            const SizedBox(height: 10),
            _FieldBlock('Adresse', child: TextField(
              controller: _adresseCtrl,
              decoration: _inputDec('Adresse du futur propriétaire'),
            )),
            const SizedBox(height: 10),
            _FieldBlock('Acompte / arrhes versé (€) — optionnel', child: TextField(
              controller: _acompteCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDec('0'),
            )),
            const SizedBox(height: 10),
            _FieldBlock('Notes', child: TextField(
              controller: _notesCtrl, maxLines: 2,
              decoration: _inputDec('Conditions, remarques…'),
            )),
            const SizedBox(height: 14),

            // Documents optionnels — pour chacun : passer, générer dans
            // l'app, ou apporter son propre document déjà signé.
            _DocChoiceBlock(
              title: 'Contrat de réservation',
              subtitle: 'Arrhes, conditions d\'annulation, engagement des deux parties.',
              value: _contratChoice,
              onChanged: (v) {
                setState(() => _contratChoice = v);
                if (v == _DocChoice.upload) _pickContratFile();
              },
              fileName: _contratFile?.name,
              onPickFile: _pickContratFile,
            ),
            const SizedBox(height: 10),
            _DocChoiceBlock(
              title: 'Certificat d\'engagement',
              subtitle: _needsDelaiLegal
                  ? 'Obligatoire pour chien/chat (loi du 30/11/2021) — délai légal de 7 jours avant signature.'
                  : "Attestation d'engagement et de connaissance de l'acquéreur.",
              value: _certifChoice,
              onChanged: (v) {
                setState(() => _certifChoice = v);
                if (v == _DocChoice.upload) _pickCertifFile();
              },
              fileName: _certifFile?.name,
              onPickFile: _pickCertifFile,
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _nomCtrl.text.trim().isNotEmpty && !_saving
                  ? ((_contratChoice != _DocChoice.skip || _certifChoice != _DocChoice.skip) ? () => setState(() => _step = 2) : _save)
                  : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: (_contratChoice != _DocChoice.skip || _certifChoice != _DocChoice.skip) ? _teal : _amber,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text((_contratChoice != _DocChoice.skip || _certifChoice != _DocChoice.skip) ? 'Documents →' : '🔖 Réserver',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
          ],

          // ── Étape 2 : Documents ──────────────────────────────
          if (_step == 2) ...[
            if (_contratChoice != _DocChoice.skip) ...[
              const Text('🐾 Contrat de réservation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _dark)),
              const SizedBox(height: 8),
              if (_contratChoice == _DocChoice.upload && _contratFile != null)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                  const Icon(Icons.description_outlined, size: 16, color: Color(0xFF6E9E57)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_contratFile!.name, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57)), overflow: TextOverflow.ellipsis)),
                  TextButton(onPressed: _pickContratFile, child: const Text('Changer', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
                ])),
              OutlinedButton.icon(
                onPressed: _generatingContrat ? null : _creerContratReservation,
                icon: _generatingContrat
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_circle_outline, size: 16),
                label: Text(_generatingContrat ? 'Création…' : (_contratChoice == _DocChoice.upload ? 'Ajouter le document' : 'Créer le contrat'), style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal, side: const BorderSide(color: _teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_contratChoice != _DocChoice.skip && _certifChoice != _DocChoice.skip) const Divider(height: 1),
            if (_contratChoice != _DocChoice.skip && _certifChoice != _DocChoice.skip) const SizedBox(height: 16),
            if (_certifChoice != _DocChoice.skip) ...[
              const Text('📜 Certificat d\'engagement', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _dark)),
              if (_needsDelaiLegal && _certifChoice == _DocChoice.generate) ...[
                const SizedBox(height: 4),
                const Text('⚠ Signature possible par l\'acquéreur seulement 7 jours après la remise (loi 30/11/2021).',
                    style: TextStyle(fontSize: 11, color: _amber)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _FieldBlock('Prénom *', child: TextField(
                  controller: _certifPrenomCtrl,
                  onChanged: (_) => _certifNameTouched = true,
                  decoration: _inputDec('Prénom'),
                ))),
                const SizedBox(width: 8),
                Expanded(child: _FieldBlock('Nom *', child: TextField(
                  controller: _certifNomCtrl,
                  onChanged: (_) => _certifNameTouched = true,
                  decoration: _inputDec('Nom'),
                ))),
              ]),
              const SizedBox(height: 8),
              if (_certifError != null)
                Container(margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Text(_certifError!, style: TextStyle(fontSize: 12, color: Colors.red.shade700))),
              if (_certifToken != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF6E9E57).withValues(alpha: 0.3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_certifChoice == _DocChoice.upload ? '✅ Certificat ajouté — lien :' : '✅ Certificat créé — partagez ce lien :',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF3D6B2E))),
                    const SizedBox(height: 6),
                    Text('$kSiteBaseUrl/certificat/$_certifToken',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF3D6B2E))),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Clipboard.setData(ClipboardData(text: '$kSiteBaseUrl/certificat/$_certifToken')),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text('📋 Copier le lien', style: TextStyle(fontSize: 12, color: Color(0xFF3D6B2E), fontFamily: 'Galey')),
                    ),
                  ]),
                )
              else ...[
                if (_certifChoice == _DocChoice.upload && _certifFile != null)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                    const Icon(Icons.description_outlined, size: 16, color: Color(0xFF6E9E57)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_certifFile!.name, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57)), overflow: TextOverflow.ellipsis)),
                    TextButton(onPressed: _pickCertifFile, child: const Text('Changer', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
                  ])),
                OutlinedButton.icon(
                  onPressed: _certifSaving ? null : (_certifChoice == _DocChoice.upload ? _importerCertificatEngagement : _creerCertificatEngagement),
                  icon: _certifSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_circle_outline, size: 16),
                  label: Text(_certifSaving ? 'Création…' : (_certifChoice == _DocChoice.upload ? 'Ajouter le document' : 'Créer le certificat'), style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal, side: const BorderSide(color: _teal),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    minimumSize: const Size(double.infinity, 0),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving || _nomCtrl.text.trim().isEmpty ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('🔖 Terminer la réservation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            const Center(child: Text('Les documents sont optionnels. Vous pouvez les ajouter plus tard.',
                style: TextStyle(fontSize: 11, color: Colors.grey))),
          ],
        ]),
      ),
    );
  }
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

/// Choix à 3 options pour un document (contrat/certificat) : passer,
/// générer dans l'app, ou apporter son propre document déjà signé.
class _DocChoiceBlock extends StatelessWidget {
  final String title;
  final String subtitle;
  final _DocChoice value;
  final ValueChanged<_DocChoice> onChanged;
  final String? fileName;
  final VoidCallback onPickFile;

  const _DocChoiceBlock({
    required this.title, required this.subtitle, required this.value,
    required this.onChanged, required this.fileName, required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 13, fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _dark)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 8),
        for (final opt in [
          (_DocChoice.skip, 'Je m’en occupe autrement'),
          (_DocChoice.generate, 'Générer et faire signer dans l’app'),
          (_DocChoice.upload, 'J’ai déjà mon document'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GestureDetector(
              onTap: () => onChanged(opt.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: value == opt.$1 ? _teal.withValues(alpha: 0.06) : Colors.white,
                  border: Border.all(color: value == opt.$1 ? _teal : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(value == opt.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 16, color: value == opt.$1 ? _teal : Colors.grey),
                  const SizedBox(width: 8),
                  Text(opt.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                ]),
              ),
            ),
          ),
        if (value == _DocChoice.upload && fileName != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              const Icon(Icons.description_outlined, size: 14, color: Color(0xFF6E9E57)),
              const SizedBox(width: 6),
              Expanded(child: Text(fileName!, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6E9E57)), overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: onPickFile, child: const Text('Changer', style: TextStyle(fontFamily: 'Galey', fontSize: 11))),
            ]),
          ),
      ]),
    );
  }
}
