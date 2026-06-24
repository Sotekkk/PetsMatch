import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/config.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);

// ── Feuille de cession ────────────────────────────────────────────────────────

class CessionSheet extends StatefulWidget {
  final Map<String, dynamic> animal;
  final String uid;
  final String nomElevage;
  final VoidCallback onCeded;

  const CessionSheet({
    super.key,
    required this.animal,
    required this.uid,
    required this.nomElevage,
    required this.onCeded,
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
  final _nomCtrl      = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _telCtrl      = TextEditingController();
  final _adresseCtrl  = TextEditingController();
  final _prixCtrl     = TextEditingController();
  final _notesCtrl    = TextEditingController();
  late DateTime _dateCession;

  // Documents uploadés manuellement
  String? _contratUrl;
  String? _certificatUrl;
  bool _uploadingContrat    = false;
  bool _uploadingCertificat = false;

  // Documents existants dans documents_animaux (sélectionnable)
  List<Map<String, dynamic>> _existingContrats     = [];
  List<Map<String, dynamic>> _existingCertificats  = [];
  Map<String, dynamic>? _selectedContrat;
  Map<String, dynamic>? _selectedCertificat;
  bool _loadingDocs = true;

  bool _saving = false;
  bool _generatingPdf  = false;
  bool _generatingCert = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dateCession = DateTime.now();
    _loadExistingDocs();
  }

  Future<void> _loadExistingDocs() async {
    final animalId = widget.animal['id'] as String?;
    if (animalId == null) { setState(() => _loadingDocs = false); return; }
    try {
      final res = await _supa
          .from('documents_animaux')
          .select('id, type, titre, url, statut, created_at, metadata')
          .eq('animal_id', animalId)
          .inFilter('type', ['contrat_vente', 'contrat_reservation', 'certificat_cession'])
          .order('created_at', ascending: false);
      if (mounted) {
        final all = List<Map<String, dynamic>>.from(res);
        setState(() {
          _existingContrats    = all.where((d) => d['type'] != 'certificat_cession').toList();
          _existingCertificats = all.where((d) => d['type'] == 'certificat_cession').toList();
          _loadingDocs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    _adresseCtrl.dispose();
    _prixCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _searchResults = [];

  Future<void> _searchUser() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _searchDone = false; _foundUser = null; _searchResults = []; });
    try {
      final isEmail = q.contains('@');
      List<Map<String, dynamic>> rows;
      if (isEmail) {
        final res = await _supa
            .from('users')
            .select('uid, firstname, lastname, name_elevage, is_elevage, profile_picture_url, phone_number, code_iso, adress, rue, ville, code_postal, numero_elevage, code_iso_elevage, adress_elevage, email')
            .eq('email', q.toLowerCase())
            .maybeSingle();
        rows = res != null ? [res] : [];
      } else {
        rows = await _supa
            .from('users')
            .select('uid, firstname, lastname, name_elevage, is_elevage, profile_picture_url, phone_number, code_iso, adress, rue, ville, code_postal, numero_elevage, code_iso_elevage, adress_elevage, email')
            .or('firstname.ilike.%$q%,lastname.ilike.%$q%,name_elevage.ilike.%$q%')
            .limit(8);
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
      final acqNom     = _nomCtrl.text.trim();

      // Créer ou récupérer le doc dans documents_animaux
      final res = await _supa.from('documents_animaux').insert({
        'animal_id':   animalId,
        'uid_eleveur': widget.uid,
        'type':        type,
        'titre':       '$titreLabel — $nomAnimal',
        'statut':      'brouillon',
        'metadata': {
          'acquereur_nom':     acqNom,
          'acquereur_email':   _emailCtrl.text.trim(),
          'acquereur_tel':     _telCtrl.text.trim(),
          'acquereur_adresse': _adresseCtrl.text.trim(),
          'prix':              _prixCtrl.text.trim(),
          'date_cession':      _dateCession.toIso8601String().split('T').first,
          'notes':             _notesCtrl.text.trim(),
        },
      }).select('token').single();

      final token = res['token'] as String;
      const baseUrl = kSiteBaseUrl;
      final url = Uri.parse('$baseUrl/signer-contrat/$token');

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        // Copier le lien dans le presse-papier si le navigateur ne s'ouvre pas
        if (mounted) {
          await Clipboard.setData(ClipboardData(text: url.toString()));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lien copié — ouvrez-le dans votre navigateur')),
          );
        }
      }
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      setState(() { _generatingPdf = false; _generatingCert = false; });
    }
  }

  Future<void> _genererPdf()       async => _ouvrirContratWeb('contrat_vente');
  Future<void> _genererCertificat() async => _ouvrirContratWeb('certificat_cession');

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

      // 1. Créer l'enregistrement de cession (sans transférer la fiche)
      final row = await _supa.from('cessions').insert({
        'animal_id':          widget.animal['id'],
        'uid_eleveur':        widget.uid,
        'uid_acquereur':      _foundUser?['uid'],
        'email_acquereur':    _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'nom_acquereur':      _nomCtrl.text.trim(),
        'tel_acquereur':      _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'adresse_acquereur':  _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'qualite':            _qualite,
        'prix':               _prixCtrl.text.isEmpty ? null : double.tryParse(_prixCtrl.text.replaceAll(',', '.')),
        'notes':              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'date_cession':       _dateCession.toIso8601String().split('T').first,
        'statut':             'en_attente_acquereur',
        'contrat_url':        contratUrl,
        'certificat_url':     certificatUrl,
      }).select('token').single();

      final token = row['token'] as String;
      const baseUrl = kSiteBaseUrl;
      final signingUrl = '$baseUrl/signer-cession/$token';

      // 2. Passer l'animal en 'cession_en_cours' (pas encore sorti)
      // uid_acquereur posé dès maintenant si compte PetsMatch → acquéreur peut voir la fiche en lecture seule
      await _supa.from('animaux').update({
        'statut':               'cession_en_cours',
        'uid_acquereur':        _foundUser?['uid'],
        'destinataire_qualite': _qualite,
        'destinataire_nom':     _nomCtrl.text.trim(),
        'destinataire_adresse': _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'cession_prix':         _prixCtrl.text.isEmpty ? null : double.tryParse(_prixCtrl.text.replaceAll(',', '.')),
        'cession_notes':        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'cession_contrat_url':  contratUrl,
        'cession_certificat_url': certificatUrl,
      }).eq('id', widget.animal['id']);

      // 3. Historique de propriété
      final dateStr = _dateCession.toIso8601String().split('T').first;
      // Clôturer la propriété du cédant
      await _supa.from('animaux_proprietes')
          .update({'date_fin': dateStr})
          .eq('animal_id', widget.animal['id'])
          .eq('uid_proprio', widget.uid)
          .isFilter('date_fin', null);
      // Ouvrir la propriété de l'acquéreur (si compte PetsMatch)
      if (_foundUser?['uid'] != null) {
        await _supa.from('animaux_proprietes').insert({
          'animal_id':  widget.animal['id'],
          'uid_proprio': _foundUser!['uid'],
          'date_debut':  dateStr,
        });
      }

      // 4. Notifier l'acquéreur
      if (_foundUser?['uid'] != null) {
        // In-app si compte PetsMatch
        await _supa.from('notifications').insert({
          'uid':   _foundUser!['uid'],
          'type':  'cession_signature_demandee',
          'title': '✍️ Signature requise — ${widget.animal['nom'] ?? 'Animal'}',
          'body':  '${widget.nomElevage} souhaite vous céder ${widget.animal['nom'] ?? 'un animal'}. Signez le contrat pour valider.',
          'data':  {'animalId': widget.animal['id'], 'token': token, 'signingUrl': signingUrl},
          'read':  false,
        });
      }
      // Email si adresse fournie (avec ou sans compte)
      if (_emailCtrl.text.trim().isNotEmpty) {
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
              'date_cession': _dateCession.toIso8601String().split('T').first,
            }),
          );
        } catch (_) {}
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onCeded();
        // Afficher le lien de signature
        showDialog(
          context: context,
          builder: (_) => _SigningLinkDialog(
            url: signingUrl,
            nomAcquereur: _nomCtrl.text.trim(),
            hasAccount: _foundUser != null,
          ),
        );
      }
    } catch (e) {
      setState(() { _saving = false; _error = 'Erreur : $e'; });
    }
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
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle + titre
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🤝 Céder ${widget.animal['nom'] ?? 'cet animal'}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _dark)),
              Text('Étape ${_step + 1}/3', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
                items: const [
                  DropdownMenuItem(value: 'particulier', child: Text('Particulier')),
                  DropdownMenuItem(value: 'eleveur',     child: Text('Éleveur')),
                  DropdownMenuItem(value: 'refuge',      child: Text('Refuge')),
                  DropdownMenuItem(value: 'autre',       child: Text('Autre')),
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
            _FieldBlock('Nom de l\'acquéreur *', child: TextField(
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
              Expanded(child: _FieldBlock('Prix (€)', child: TextField(
                controller: _prixCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _inputDec('0'),
              ))),
            ]),
            const SizedBox(height: 10),
            _FieldBlock('Adresse', child: TextField(
              controller: _adresseCtrl,
              decoration: _inputDec('Adresse de l\'acquéreur'),
            )),
            const SizedBox(height: 10),
            _FieldBlock('Notes', child: TextField(
              controller: _notesCtrl, maxLines: 2,
              decoration: _inputDec('Conditions particulières…'),
            )),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _nomCtrl.text.trim().isEmpty ? null : () => setState(() => _step = 2),
              style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Documents →', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
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
        ]),
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
}) {
  final type = doc['type'] as String? ?? '';
  final statut = doc['statut'] as String? ?? '';
  final typeLabel = type == 'certificat_cession'
      ? 'Certificat de cession'
      : type == 'contrat_reservation' ? 'Contrat de réservation' : 'Contrat de vente';
  final statutLabel = statut == 'signe'
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFECFDF5) : Colors.grey.shade50,
        border: Border.all(
            color: selected ? const Color(0xFF059669) : Colors.grey.shade200,
            width: selected ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18, color: selected ? const Color(0xFF059669) : Colors.grey.shade400),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(typeLabel, style: const TextStyle(
              fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
              color: Color(0xFF1F2A2E))),
          const SizedBox(height: 2),
          Text('$statutLabel${date.isNotEmpty ? '  ·  $date' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
        ])),
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
  final String nomAcquereur;
  final bool hasAccount;

  const _SigningLinkDialog({required this.url, required this.nomAcquereur, required this.hasAccount});

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
