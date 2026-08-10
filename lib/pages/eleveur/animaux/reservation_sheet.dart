import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/main.dart' show User_Info;

const _teal  = Color(0xFF0C5C6C);
const _amber = Color(0xFFD97706);
const _dark  = Color(0xFF1F2A2E);

const _especesDelaiLegal = {'chien', 'chat'};

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

  // Documents optionnels — contrat de réservation (app) et/ou certificat
  // d'engagement (légal, chien/chat). Si aucun n'est coché, la réservation
  // reste simple : le formulaire papier de l'éleveur reste possible en
  // dehors de l'application.
  bool _wantContrat = false;
  bool _wantCertificat = false;
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

  // Insère directement le document (comme cession_sheet.dart pour contrat_vente/
  // certificat_cession) — signer-contrat/[token] génère le HTML à la volée à
  // partir de ces métadonnées, pas besoin d'un formulaire interactif ici.
  Future<void> _creerContratReservation() async {
    setState(() { _generatingContrat = true; _error = null; });
    try {
      final animalId = widget.animal['id'] as String;
      final nomAnimal = widget.animal['nom'] as String? ?? '';
      final pid = User_Info.activeProfileId;
      final res = await _supa.from('documents_animaux').insert({
        'animal_id':   animalId,
        'uid_eleveur': widget.uid,
        if (pid.isNotEmpty) 'pro_profile_id': pid,
        'type':        'contrat_reservation',
        'titre':       'Contrat de réservation — $nomAnimal',
        'statut':      'brouillon',
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
      final url = Uri.parse('$kSiteBaseUrl/signer-contrat/$token');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: url.toString()));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lien copié — ouvrez-le dans votre navigateur')),
          );
        }
      }
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      setState(() => _generatingContrat = false);
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
      setState(() => _certifToken = json['token'] as String?);
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

            // Documents optionnels — laisse le choix entre gérer le papier
            // soi-même ou générer les documents depuis l'application.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Documents (optionnel)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: _wantContrat,
                  onChanged: (v) => setState(() => _wantContrat = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('Générer un contrat de réservation', style: TextStyle(fontSize: 13, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  subtitle: const Text('Arrhes, conditions d\'annulation, engagement des deux parties.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
                CheckboxListTile(
                  value: _wantCertificat,
                  onChanged: (v) => setState(() => _wantCertificat = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('Générer un certificat d\'engagement', style: TextStyle(fontSize: 13, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _needsDelaiLegal
                        ? 'Obligatoire pour chien/chat (loi du 30/11/2021) — délai légal de 7 jours avant signature.'
                        : "Attestation d'engagement et de connaissance de l'acquéreur.",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                const Text('Rien à cocher si vous gérez ces documents vous-même en dehors de l\'application.',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _nomCtrl.text.trim().isNotEmpty && !_saving
                  ? (_wantContrat || _wantCertificat ? () => setState(() => _step = 2) : _save)
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: _wantContrat || _wantCertificat ? _teal : _amber, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_wantContrat || _wantCertificat ? 'Documents →' : '🔖 Réserver',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
          ],

          // ── Étape 2 : Documents ──────────────────────────────
          if (_step == 2) ...[
            if (_wantContrat) ...[
              const Text('🐾 Contrat de réservation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _dark)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _generatingContrat ? null : _creerContratReservation,
                icon: _generatingContrat
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_circle_outline, size: 16),
                label: Text(_generatingContrat ? 'Création…' : 'Créer le contrat', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal, side: const BorderSide(color: _teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_wantContrat && _wantCertificat) const Divider(height: 1),
            if (_wantContrat && _wantCertificat) const SizedBox(height: 16),
            if (_wantCertificat) ...[
              const Text('📜 Certificat d\'engagement', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _dark)),
              if (_needsDelaiLegal) ...[
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
                    const Text('✅ Certificat créé — partagez ce lien :',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF3D6B2E))),
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
              else
                OutlinedButton.icon(
                  onPressed: _certifSaving ? null : _creerCertificatEngagement,
                  icon: _certifSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_circle_outline, size: 16),
                  label: Text(_certifSaving ? 'Création…' : 'Créer le certificat', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal, side: const BorderSide(color: _teal),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    minimumSize: const Size(double.infinity, 0),
                  ),
                ),
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
