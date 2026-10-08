import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/utils/document_prive.dart';
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/certificats_engagement_page.dart';
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'package:PetsMatch/utils/user_lookup.dart';

/// Choix pour le certificat d'engagement (loi 2021-1539) — jamais imposé :
/// l'éleveur peut toujours passer l'étape ou apporter son propre document.
enum _CertMode { skip, generate, upload }

class ContratReservationPage extends StatefulWidget {
  /// Document à mettre en avant (ouvert automatiquement + carte surlignée),
  /// p. ex. quand l'éleveur clique la notif « l'acquéreur a signé ».
  final String? highlightDocId;
  final String? highlightToken;
  const ContratReservationPage({super.key, this.highlightDocId, this.highlightToken});
  @override
  State<ContratReservationPage> createState() => _ContratReservationPageState();
}

class _ContratReservationPageState extends State<ContratReservationPage> {
  static const _teal  = Color(0xFF0C5C6C);

  final _supa = Supabase.instance.client;

  List<Map<String, dynamic>> _docs    = [];
  List<Map<String, dynamic>> _animaux = [];
  Map<String, dynamic>?      _profil;
  bool _loading = true;
  bool _highlightOpened = false;
  String _recherche = '';
  String _filtreType = 'tous';

  static const _documents = [
    ('contrat_reservation', 'Contrat de réservation', 'Préparer la réservation d’un animal.'),
    ('contrat_vente',       'Contrat de vente',       'Formaliser la vente d’un animal.'),
    ('certificat_cession',  'Certificat de cession',  'Établir le document de cession.'),
    ('contrat_saillie',     'Contrat de saillie',     'Définir les conditions d’une saillie.'),
  ];
  static const _dark = Color(0xFF1F2A2E);

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Récupérer l'id du profil éleveur pour filtrer les animaux
    final profileRes = await _supa.from('user_profiles_complet')
        .select('id')
        .eq('uid', uid)
        .eq('profile_type', 'eleveur')
        .maybeSingle();
    final eleveurProfileId = profileRes?['id'] as String?;

    final [docs, animaux, profil] = await Future.wait([
      // Uniquement les documents « éleveur » (vente/réservation/cession/
      // saillie) — pas tous les documents créés par cet uid, sans quoi les
      // devis/contrats émis en tant qu'éducateur, garde, etc. s'y mélangent.
      _supa.from('documents_animaux')
          .select()
          .eq('uid_eleveur', uid)
          .inFilter('type', ['contrat_vente', 'contrat_reservation', 'certificat_cession', 'contrat_saillie'])
          .order('created_at', ascending: false),
      eleveurProfileId != null
          ? _supa.from('animaux')
              .select('id, nom, espece, race, identification, date_naissance, sexe, photo_url')
              .eq('uid_eleveur', uid)
              .eq('profile_id', eleveurProfileId)
              .not('statut', 'in', '(sorti,decede)')
              .order('nom')
          : _supa.from('animaux')
              .select('id, nom, espece, race, identification, date_naissance, sexe, photo_url')
              .eq('uid_eleveur', uid)
              .not('statut', 'in', '(sorti,decede)')
              .order('nom'),
      _supa.from('users_complet')
          .select('firstname, lastname, name_elevage, is_elevage, adress_elevage, adress, rue, ville, code_postal, siret, email, numero_elevage, code_iso_elevage, phone_number, code_iso')
          .eq('uid', uid)
          .maybeSingle(),
    ]);
    if (!mounted) return;
    setState(() {
      _docs    = List<Map<String, dynamic>>.from(docs as List);
      _animaux = List<Map<String, dynamic>>.from(animaux as List);
      _profil  = profil as Map<String, dynamic>?;
      _loading = false;
    });
    _maybeOpenHighlight();
  }

  /// Ouvre une fois le document mis en avant (notif « l'acquéreur a signé »).
  void _maybeOpenHighlight() {
    if (_highlightOpened) return;
    final wantId  = widget.highlightDocId;
    final wantTok = widget.highlightToken;
    if (wantId == null && wantTok == null) return;
    Map<String, dynamic>? doc;
    for (final d in _docs) {
      if ((wantId != null && d['id'] == wantId) ||
          (wantTok != null && d['token'] == wantTok)) { doc = d; break; }
    }
    if (doc == null) return;
    _highlightOpened = true;
    final token = doc['token'] as String?;
    final id    = doc['id'] as String?;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => ContratSignaturePage(token: token, documentId: id),
      ));
      if (mounted) _load();
    });
  }

  String get _eleveurNom {
    if (_profil == null) return '';
    final isElv = _profil!['is_elevage'] == true;
    return isElv
        ? (_profil!['name_elevage'] as String? ?? '${_profil!['firstname'] ?? ''} ${_profil!['lastname'] ?? ''}'.trim())
        : '${_profil!['firstname'] ?? ''} ${_profil!['lastname'] ?? ''}'.trim();
  }
  String get _eleveurAdresse {
    if (_profil == null) return '';
    final isElv = _profil!['is_elevage'] == true;
    return isElv
        ? (_profil!['adress_elevage'] as String? ?? [_profil!['rue'], _profil!['code_postal'], _profil!['ville']].whereType<String>().join(', '))
        : (_profil!['adress'] as String? ?? [_profil!['rue'], _profil!['code_postal'], _profil!['ville']].whereType<String>().join(', '));
  }
  String get _eleveurSiret  => _profil?['siret'] as String? ?? '';
  String get _eleveurEmail  => _profil?['email']  as String? ?? '';

  List<Map<String, dynamic>> get _docsFiltres {
    final q = _recherche.trim().toLowerCase();
    return _docs.where((d) {
      if (_filtreType != 'tous' && d['type'] != _filtreType) return false;
      if (q.isEmpty) return true;
      final meta = (d['metadata'] as Map<String, dynamic>?) ?? {};
      final typeLib = _documents.firstWhere((t) => t.$1 == d['type'], orElse: () => ('', '', '')).$2;
      return [d['titre'] ?? '', meta['acquereur_nom'] ?? '', typeLib]
          .any((v) => v.toString().toLowerCase().contains(q));
    }).toList();
  }

  void _creer(String type) {
    if (_animaux.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ajoutez d’abord un animal pour créer un document.'), behavior: SnackBarBehavior.floating));
      return;
    }
    _showCreateSheet(context, type: type);
  }

  BoxDecoration get _bloc => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.grey.shade300),
  );

  Widget _boutonContour(String label, VoidCallback onPressed) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: _teal,
      side: const BorderSide(color: _teal),
      minimumSize: const Size(88, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700)),
  );

  Widget _ligneDocument({required String titre, required String desc, required Widget action}) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
    decoration: _bloc,
    child: Row(children: [
      const Icon(Icons.description_outlined, size: 28, color: _dark),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: _dark)),
        const SizedBox(height: 3),
        Text(desc, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
      ])),
      const SizedBox(width: 10),
      action,
    ]),
  );

  InputDecoration _champDeco(String hint, {Widget? prefix}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500),
    prefixIcon: prefix,
    isDense: true,
    filled: true, fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _teal, width: 1.5)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F9),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes contrats', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              color: _teal,
              onRefresh: _load,
              child: LayoutBuilder(builder: (context, c) {
                final deuxColonnes = c.maxWidth >= 720;
                final filtres = _docsFiltres;
                final cartes = [
                  for (final t in _documents)
                    _ligneDocument(titre: t.$2, desc: t.$3, action: _boutonContour('Créer', () => _creer(t.$1))),
                ];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                  children: [
                    const Text('Créez et retrouvez les documents liés à vos animaux.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF5F6B70))),
                    const SizedBox(height: 20),
                    const Text('Créer un document', style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w800, color: _dark)),
                    const SizedBox(height: 12),
                    if (deuxColonnes)
                      for (var i = 0; i < cartes.length; i += 2) ...[
                        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(child: cartes[i]),
                          const SizedBox(width: 12),
                          Expanded(child: i + 1 < cartes.length ? cartes[i + 1] : const SizedBox()),
                        ])),
                        const SizedBox(height: 12),
                      ]
                    else
                      for (final carte in cartes) ...[carte, const SizedBox(height: 10)],
                    const SizedBox(height: 8),
                    // Certificats d'engagement : bandeau distinct
                    _ligneDocument(
                      titre: 'Certificats d’engagement',
                      desc: 'Retrouvez les documents signés par les acquéreurs.',
                      action: _boutonContour('Consulter', () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const CertificatsEngagementPage(),
                      ))),
                    ),
                    const SizedBox(height: 28),

                    // Contrats enregistrés
                    Text.rich(TextSpan(children: [
                      const TextSpan(text: 'Contrats enregistrés '),
                      TextSpan(text: '(${_docs.length})', style: TextStyle(color: Colors.grey.shade500)),
                    ]), style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w800, color: _dark)),
                    const SizedBox(height: 12),
                    Flex(
                      direction: deuxColonnes ? Axis.horizontal : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(flex: deuxColonnes ? 3 : 0, fit: FlexFit.loose, child: TextField(
                          onChanged: (v) => setState(() => _recherche = v),
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                          decoration: _champDeco('Rechercher un contrat',
                              prefix: Icon(Icons.search, size: 20, color: Colors.grey.shade500)),
                        )),
                        SizedBox(width: deuxColonnes ? 10 : 0, height: deuxColonnes ? 0 : 10),
                        Flexible(flex: deuxColonnes ? 2 : 0, fit: FlexFit.loose, child: DropdownButtonFormField<String>(
                          initialValue: _filtreType,
                          isExpanded: true,
                          decoration: _champDeco(''),
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _dark),
                          items: [
                            const DropdownMenuItem(value: 'tous', child: Text('Tous les types')),
                            for (final t in _documents) DropdownMenuItem(value: t.$1, child: Text(t.$2, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _filtreType = v ?? 'tous'),
                        )),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (filtres.isEmpty)
                      _etatVide()
                    else
                      Container(
                        decoration: _bloc,
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          for (var i = 0; i < filtres.length; i++) ...[
                            if (i > 0) Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                            _DocCard(
                              doc: filtres[i],
                              onDelete: _deleteDoc,
                              highlight: (widget.highlightDocId != null && filtres[i]['id'] == widget.highlightDocId) ||
                                         (widget.highlightToken != null && filtres[i]['token'] == widget.highlightToken),
                            ),
                          ],
                        ]),
                      ),
                  ],
                );
              }),
            ),
    );
  }

  Widget _etatVide() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(children: [
      Icon(Icons.description_outlined, size: 40, color: Colors.grey.shade400),
      const SizedBox(height: 10),
      if (_docs.isEmpty) ...[
        const Text('Aucun contrat enregistré', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: _dark)),
        const SizedBox(height: 4),
        Text('Vos documents apparaîtront ici après leur création.', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
      ] else ...[
        const Text('Aucun contrat ne correspond', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: _dark)),
        TextButton(
          onPressed: () => setState(() { _recherche = ''; _filtreType = 'tous'; }),
          style: TextButton.styleFrom(foregroundColor: _teal),
          child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ],
    ]),
  );

  Future<void> _deleteDoc(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Ce contrat sera définitivement supprimé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('documents_animaux').delete().eq('id', id);
    await _load();
  }

  Future<void> _showCreateSheet(BuildContext context, {String type = 'contrat_vente'}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateContratSheet(
        initialType: type,
        animaux: _animaux,
        eleveurNom: _eleveurNom,
        eleveurAdresse: _eleveurAdresse,
        eleveurSiret: _eleveurSiret,
        eleveurEmail: _eleveurEmail,
        supa: _supa,
        onSaved: _load,
      ),
    );
  }
}

// ── Carte document ────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final Future<void> Function(String) onDelete;
  final bool highlight;

  const _DocCard({required this.doc, required this.onDelete, this.highlight = false});

  static const _teal = Color(0xFF0C5C6C);

  static const _typeLabel = {
    'contrat_vente':       'Contrat de vente',
    'contrat_reservation': 'Contrat de réservation',
    'certificat_cession':  'Certificat de cession',
    'contrat_saillie':     'Contrat de saillie',
  };
  static const _statutColor = {
    'brouillon':          Color(0xFFEEEEEE),
    'en_attente':         Color(0xFFFEF3C7),
    'partiellement_signe':Color(0xFFDBEAFE),
    'signe':              Color(0xFFDCF5E4),
    'archive':            Color(0xFFFFF3CD),
    'annule':             Color(0xFFFEE2E2),
    'expire':             Color(0xFFFFEDD5),
    'refuse':             Color(0xFFFEE2E2),
  };
  static const _statutLabel = {
    'brouillon':          'Brouillon',
    'en_attente':         'En attente',
    'partiellement_signe':'Signature partielle',
    'signe':              'Signé',
    'archive':            'Archivé',
    'annule':             'Annulé',
    'expire':             'Expiré',
    'refuse':             'Refusé',
  };

  @override
  Widget build(BuildContext context) {
    final type        = doc['type'] as String? ?? 'contrat_vente';
    final statut      = doc['statut'] as String? ?? 'brouillon';
    final typeLib     = _typeLabel[type] ?? 'Contrat';
    final metaMap     = (doc['metadata'] as Map<String, dynamic>?) ?? {};
    final acqNom      = (metaMap['acquereur_nom'] as String?) ?? '';
    final titre       = doc['titre'] as String? ?? 'Contrat';
    final token       = doc['token'] as String?;
    final pdfSigneUrl = doc['pdf_signe_url'] as String?;
    final date   = doc['created_at'] != null
        ? DateTime.tryParse(doc['created_at'] as String)?.toLocal()
        : null;
    final signingUrl = token != null ? '$kSiteBaseUrl/signer-contrat/$token' : null;
    final isFinal    = ['signe', 'annule', 'expire', 'refuse'].contains(statut);

    final dateStr = date != null
        ? '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}' : null;

    return Container(
      padding: const EdgeInsets.all(14),
      color: highlight ? _teal.withValues(alpha: 0.05) : Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.description_outlined, size: 24, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E)), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text([typeLib, if (acqNom.isNotEmpty) acqNom, if (dateStr != null) dateStr].join(' · '),
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: _statutColor[statut] ?? const Color(0xFFEEEEEE), borderRadius: BorderRadius.circular(6)),
              child: Text(_statutLabel[statut] ?? statut, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ])),
        ]),

        if (token != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ContratSignaturePage(token: token),
                )),
                icon: const Icon(Icons.draw_outlined, size: 15),
                label: const Text('Lire et signer', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Copier lien
            if (!isFinal) ...[
              OutlinedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: signingUrl!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lien copié'), duration: Duration(seconds: 2)),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Icon(Icons.link, size: 16),
              ),
              const SizedBox(width: 8),
            ],
            // PREP07 — Télécharger PDF signé
            if (statut == 'signe' && pdfSigneUrl != null) ...[
              OutlinedButton(
                onPressed: () => ouvrirDocument(context, pdfSigneUrl),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6E9E57),
                  side: const BorderSide(color: Color(0xFF6E9E57)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Icon(Icons.download_outlined, size: 16),
              ),
              const SizedBox(width: 8),
            ],
            // PREP08 — Annuler
            if (!isFinal)
              OutlinedButton(
                onPressed: () => onDelete(doc['id'] as String),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Icon(Icons.delete_outline, size: 16),
              ),
          ]),
        ],
      ]),
    );
  }
}

// ── Bottom sheet création ─────────────────────────────────────────────────────

class _CreateContratSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animaux;
  final String eleveurNom, eleveurAdresse, eleveurSiret, eleveurEmail;
  final dynamic supa;
  final VoidCallback onSaved;
  final String initialType;

  const _CreateContratSheet({
    this.initialType = 'contrat_vente',
    required this.animaux, required this.eleveurNom, required this.eleveurAdresse,
    required this.eleveurSiret, required this.eleveurEmail,
    required this.supa, required this.onSaved,
  });

  @override
  State<_CreateContratSheet> createState() => _CreateContratSheetState();
}

class _CreateContratSheetState extends State<_CreateContratSheet> {
  static const _teal  = Color(0xFF0C5C6C);

  late String _type = widget.initialType;
  Map<String, dynamic>? _selectedAnimal;
  bool _avecSteril = true;
  // Certificat d'engagement (loi 2021-1539, obligatoire légalement pour toute
  // cession de chien/chat — mais on ne bloque jamais la création du contrat :
  // toujours possible de passer l'étape ou d'apporter son propre document).
  _CertMode _certMode = _CertMode.skip;
  PlatformFile? _certFile;

  final _acqRaisonSocialeCtrl = TextEditingController();
  final _acqSiretCtrl    = TextEditingController();
  final _acqNomCtrl      = TextEditingController();
  final _acqPrenomCtrl   = TextEditingController();
  final _acqEmailCtrl    = TextEditingController();
  final _acqTelCtrl      = TextEditingController();
  final _acqAdresseCtrl  = TextEditingController();
  final _prixCtrl        = TextEditingController();
  final _notesCtrl       = TextEditingController();
  final _searchCtrl      = TextEditingController();

  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _searchResults = [];
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_acqRaisonSocialeCtrl, _acqSiretCtrl, _acqNomCtrl, _acqPrenomCtrl, _acqEmailCtrl, _acqTelCtrl, _acqAdresseCtrl, _prixCtrl, _notesCtrl, _searchCtrl]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _searchUser(String q) async {
    if (q.length < 2) { setState(() => _searchResults = []); return; }
    final isEmail = q.contains('@');
    final supa = Supabase.instance.client;
    const fields = 'uid, firstname, lastname, name_elevage, is_elevage, email, phone_number, numero_elevage, code_iso_elevage, rue, ville, code_postal, adress_elevage, siret';
    // E-mail : correspondance EXACTE (pm_trouver_utilisateur) — l'e-mail est
    // masqué dans users_complet, plus de recherche « contient » sur les e-mails.
    final List data;
    if (isEmail) {
      final found = await trouverUtilisateurParEmail(q);
      data = found == null
          ? []
          : ((await supa.from('users_complet').select(fields).eq('uid', found['uid']).limit(1)) as List)
              .map((r) => {...Map<String, dynamic>.from(r as Map), 'email': found['email']}).toList();
    } else {
      data = await supa.from('users_complet').select(fields).or('firstname.ilike.%$q%,lastname.ilike.%$q%,name_elevage.ilike.%$q%').limit(8);
    }
    setState(() => _searchResults = List<Map<String, dynamic>>.from(data as List));
  }

  void _selectUser(Map<String, dynamic> u) {
    final isElv = u['is_elevage'] == true && (u['name_elevage'] as String? ?? '').isNotEmpty;
    _acqRaisonSocialeCtrl.text = isElv ? (u['name_elevage'] as String? ?? '') : '';
    _acqSiretCtrl.text  = isElv ? (u['siret'] as String? ?? '') : '';
    _acqPrenomCtrl.text = u['firstname'] as String? ?? '';
    _acqNomCtrl.text    = u['lastname'] as String? ?? '';
    _acqEmailCtrl.text  = u['email'] as String? ?? '';
    if (isElv && (u['numero_elevage'] as String? ?? '').isNotEmpty) {
      final iso = u['code_iso_elevage'] as String? ?? '+33';
      _acqTelCtrl.text = '$iso ${u['numero_elevage']}'.trim();
    } else {
      _acqTelCtrl.text = u['phone_number'] as String? ?? '';
    }
    if (isElv && (u['adress_elevage'] as String? ?? '').isNotEmpty) {
      _acqAdresseCtrl.text = u['adress_elevage'] as String? ?? '';
    } else {
      _acqAdresseCtrl.text = [u['rue'], u['code_postal'], u['ville']].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    }
    _searchCtrl.clear();
    setState(() => _searchResults = []);
  }

  Future<void> _showAnimalPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnimalPickerSheet(animaux: widget.animaux),
    );
    if (selected != null) {
      setState(() => _selectedAnimal = selected);
    }
  }

  Future<void> _pickCertFile() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    final f = res?.files.single;
    if (f?.path == null) return;
    setState(() => _certFile = f);
  }

  Future<void> _creer() async {
    if (_selectedAnimal == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);

    try {
      final typeLabel = _type == 'contrat_vente' ? 'Contrat de vente'
          : _type == 'contrat_reservation' ? 'Contrat de réservation'
          : _type == 'contrat_saillie' ? 'Contrat de saillie'
          : 'Certificat de cession';

      final result = await widget.supa
          .from('documents_animaux')
          .insert({
            'animal_id':   _selectedAnimal!['id'],
            'uid_eleveur': uid,
            'type':        _type,
            'titre':       '$typeLabel — ${_selectedAnimal!['nom'] ?? 'Animal'}',
            'statut':      'en_attente',
            'expires_at':  DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'metadata': {
              if (_acqRaisonSocialeCtrl.text.trim().isNotEmpty)
                'acquereur_raison_sociale': _acqRaisonSocialeCtrl.text.trim(),
              if (_acqSiretCtrl.text.trim().isNotEmpty)
                'acquereur_siret': _acqSiretCtrl.text.trim(),
              'acquereur_nom':      '${_acqPrenomCtrl.text.trim()} ${_acqNomCtrl.text.trim()}'.trim(),
              'acquereur_email':    _acqEmailCtrl.text.trim(),
              'acquereur_tel':      _acqTelCtrl.text.trim(),
              'acquereur_adresse':  _acqAdresseCtrl.text.trim(),
              'prix':               double.tryParse(_prixCtrl.text.replaceAll(',', '.')) ?? 0,
              'date_doc':           _date.toIso8601String().split('T').first,
              'notes':              _notesCtrl.text.trim(),
              if (_type == 'contrat_vente') 'avec_sterilisation': _avecSteril,
            },
          })
          .select('id, token')
          .single();

      final token = result['token'] as String?;

      // Certificat d'engagement (facultatif) — uniquement pour une cession
      // réelle de l'animal (vente/cession), pas pour une simple réservation
      // ni un contrat de saillie.
      String? certToken;
      final concerneTransfert = _type == 'contrat_vente' || _type == 'certificat_cession' || _type == 'contrat_reservation';
      if (concerneTransfert && _certMode != _CertMode.skip) {
        try {
          final animal = _selectedAnimal!;
          final espece = animal['espece'] as String? ?? '';
          final estDelai = espece == 'chien' || espece == 'chat';
          final now = DateTime.now();
          String? uploadedUrl;
          if (_certMode == _CertMode.upload && _certFile?.path != null) {
            uploadedUrl = await storage.uploadDocument(
              File(_certFile!.path!),
              'certificats_engagement/$uid/${DateTime.now().millisecondsSinceEpoch}_${_certFile!.name}',
            );
          }
          final cert = await widget.supa.from('certificats_engagement').insert({
            'cedant_uid':            uid,
            'animal_id':             animal['id'],
            'espece':                espece,
            'race':                  animal['race'] ?? '',
            'nom_animal':            animal['nom'] ?? '',
            'date_naissance_animal': animal['date_naissance'],
            'num_identification':    animal['identification'] ?? '',
            'acquereur_nom':         _acqNomCtrl.text.trim(),
            'acquereur_prenom':      _acqPrenomCtrl.text.trim(),
            'acquereur_email':       _acqEmailCtrl.text.trim(),
            'acquereur_telephone':   _acqTelCtrl.text.trim(),
            'acquereur_adresse':     _acqAdresseCtrl.text.trim(),
            'modalite_cession':      'vente',
            'prix':                  double.tryParse(_prixCtrl.text.replaceAll(',', '.')),
            'date_remise':           now.toIso8601String(),
            'date_limite_signature': (uploadedUrl == null && estDelai) ? now.add(const Duration(days: 7)).toIso8601String() : null,
            'profil_source':         'eleveur',
            if (uploadedUrl != null) 'pdf_url': uploadedUrl,
            if (uploadedUrl != null) 'statut': 'signe',
          }).select('token_signature').single();
          certToken = cert['token_signature'] as String?;
        } catch (_) {}
      }

      widget.onSaved();
      setState(() => _saving = false);

      if (mounted) Navigator.pop(context);

      if (certToken != null && _certMode == _CertMode.generate) {
        // Document apporté par le pro : rien à signer dans l'app, pas besoin
        // d'ouvrir un onglet dessus.
        await launchUrl(Uri.parse('$kSiteBaseUrl/certificat/$certToken'), mode: LaunchMode.externalApplication);
      }

      if (token != null) {
        final url = '$kSiteBaseUrl/signer-contrat/$token';

        // Notifier la contrepartie si c'est un contrat de saillie
        if (_type == 'contrat_saillie') {
          final acqEmail = _acqEmailCtrl.text.trim();
          if (acqEmail.isNotEmpty) {
            try {
              final targetRes = await trouverUtilisateurParEmail(acqEmail);
              final targetUid = targetRes?['uid'] as String?;
              if (targetUid != null) {
                final targetProfile = await widget.supa.from('user_profiles_complet')
                    .select('id').eq('uid', targetUid).eq('profile_type', 'eleveur').maybeSingle();
                await widget.supa.from('notifications').insert({
                  'uid': targetUid,
                  'type': 'contrat_saillie_invite',
                  'title': '💞 Contrat de saillie',
                  'body': 'Vous avez reçu un contrat de saillie à compléter et signer',
                  if (targetProfile?['id'] != null) 'profile_id': targetProfile!['id'],
                  'data': {'token': token, 'url': url},
                  'read': false,
                });
              }
            } catch (_) {}
          }
        }

        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 20), color: const Color(0xFF1F2A2E)),
              const Expanded(child: Text('Nouveau contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1F2A2E)), textAlign: TextAlign.center)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20), color: const Color(0xFF1F2A2E)),
            ]),
          ),
          Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [

            // Type de contrat
            const Text('Type de contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(children: [
              for (final t in [('contrat_reservation', '', 'Réservation'), ('contrat_vente', '', 'Vente'), ('certificat_cession', '', 'Cession'), ('contrat_saillie', '', 'Saillie')])
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _type = t.$1),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _type == t.$1 ? _teal : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _type == t.$1 ? _teal : const Color(0xFFE0E0E0)),
                      ),
                      child: Text(t.$3, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _type == t.$1 ? Colors.white : const Color(0xFF555555))),
                    ),
                  ),
                )),
            ]),
            const SizedBox(height: 20),

            // Sélecteur animal
            const Text('Animal concerné *', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _showAnimalPicker(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _selectedAnimal != null
                          ? '${_selectedAnimal!['nom'] ?? '—'} (${_selectedAnimal!['espece'] ?? '—'}${_selectedAnimal!['race'] != null ? ' · ${_selectedAnimal!['race']}' : ''})'
                          : 'Sélectionner un animal',
                      style: TextStyle(
                        fontFamily: 'Galey', fontSize: 13,
                        color: _selectedAnimal != null ? const Color(0xFF1F2A2E) : Colors.grey,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 20),
                ]),
              ),
            ),
            if (_selectedAnimal != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_selectedAnimal!['nom'] ?? '—'} · ${_selectedAnimal!['espece'] ?? '—'}${_selectedAnimal!['race'] != null ? ' · ${_selectedAnimal!['race']}' : ''}',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12)),
                  if (_selectedAnimal!['identification'] != null)
                    Text('Puce : ${_selectedAnimal!['identification']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF555555))),
                ]),
              ),
            const SizedBox(height: 20),

            // Recherche acquéreur
            const Text('Rechercher l\'acquéreur (PetsMatch)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            TextField(
              controller: _searchCtrl,
              onChanged: _searchUser,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Nom, prénom ou email…',
                prefixIcon: const Icon(Icons.search, size: 18),
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 1.5)),
              ),
            ),
            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(10)),
                child: Column(children: _searchResults.map((u) {
                  final isElv = u['is_elevage'] == true && (u['name_elevage'] as String? ?? '').isNotEmpty;
                  final displayName = isElv
                      ? u['name_elevage'] as String
                      : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
                  return ListTile(
                    dense: true,
                    leading: isElv ? const Text('🏠', style: TextStyle(fontSize: 16)) : null,
                    title: Text(displayName, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(u['email'] as String? ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                    onTap: () => _selectUser(u),
                  );
                }).toList()),
              ),
            const SizedBox(height: 16),

            // Infos acquéreur
            _field('Raison sociale (entreprise / élevage)', _acqRaisonSocialeCtrl),
            _field('SIRET', _acqSiretCtrl, type: TextInputType.number),
            _field('Prénom', _acqPrenomCtrl),
            _field('Nom', _acqNomCtrl),
            _field('Email', _acqEmailCtrl, type: TextInputType.emailAddress),
            _field('Téléphone', _acqTelCtrl, type: TextInputType.phone),
            _field('Adresse', _acqAdresseCtrl),
            _field('Prix (€, 0 = gratuit)', _prixCtrl, type: TextInputType.number),
            const SizedBox(height: 8),

            // Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date du contrat', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
              subtitle: Text('${_date.day.toString().padLeft(2,'0')}/${_date.month.toString().padLeft(2,'0')}/${_date.year}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.calendar_today_outlined, size: 18),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (d != null) setState(() => _date = d);
              },
            ),
            _field('Notes', _notesCtrl, maxLines: 2),
            const SizedBox(height: 8),

            // Clause stérilisation (contrat de vente uniquement)
            if (_type == 'contrat_vente')
              GestureDetector(
                onTap: () => setState(() => _avecSteril = !_avecSteril),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Checkbox(
                      value: _avecSteril,
                      onChanged: (v) => setState(() => _avecSteril = v ?? true),
                      activeColor: _teal,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Clause de stérilisation (Tranche 2)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                      SizedBox(height: 2),
                      Text('Inclure la pénalité si l\'acquéreur ne stérilise pas dans le délai légal.', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFB45309))),
                    ])),
                  ]),
                ),
              ),

            // Certificat d'engagement (vente/cession uniquement) — jamais
            // obligatoire, toujours possible de passer l'étape ou d'apporter
            // son propre document déjà signé.
            if (_type == 'contrat_vente' || _type == 'certificat_cession' || _type == 'contrat_reservation') ...[
              const Text('Certificat d\'engagement (loi 2021-1539)',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              for (final opt in [
                (_CertMode.skip, 'Je m\'en occupe autrement', 'Passer cette étape'),
                (_CertMode.generate, 'Générer et faire signer dans l\'app', 'Certificat numérique + signature tactile'),
                (_CertMode.upload, 'J\'ai déjà mon document', 'Importer un PDF déjà signé'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _certMode = opt.$1);
                      if (opt.$1 == _CertMode.upload) _pickCertFile();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _certMode == opt.$1 ? _teal.withValues(alpha: 0.06) : Colors.white,
                        border: Border.all(color: _certMode == opt.$1 ? _teal : const Color(0xFFE0E0E0)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(_certMode == opt.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            size: 18, color: _certMode == opt.$1 ? _teal : Colors.grey),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(opt.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                          Text(opt.$3, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF888888))),
                        ])),
                      ]),
                    ),
                  ),
                ),
              if (_certMode == _CertMode.upload) ...[
                if (_certFile != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      const Icon(Icons.description_outlined, size: 16, color: Color(0xFF6E9E57)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_certFile!.name, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57)), overflow: TextOverflow.ellipsis)),
                      TextButton(onPressed: _pickCertFile, child: const Text('Changer', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
                    ]),
                  ),
              ],
              const SizedBox(height: 10),
            ],

            const SizedBox(height: 6),

            // Boutons
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: (_selectedAnimal == null || _saving) ? null : _creer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Créer & ouvrir sur le web', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              )),
            ]),
          ])),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType? type, int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: type,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
        ),
      ),
    ]),
  );
}

// ── Sélecteur animal avec flèche retour ───────────────────────────────────────

class _AnimalPickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> animaux;
  const _AnimalPickerSheet({required this.animaux});

  static const _teal = Color(0xFF0C5C6C);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios, size: 20),
              color: const Color(0xFF1F2A2E),
            ),
            const Expanded(
              child: Text('Sélectionner un animal',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1F2A2E)),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ]),
        ),
        const Divider(height: 1),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: animaux.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (_, i) {
              final a = animaux[i];
              final photoUrl = a['photo_url'] as String? ?? '';
              return ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(10)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photoUrl, width: 44, height: 44, fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(child: Text('🐾', style: TextStyle(fontSize: 16))),
                            errorWidget: (_, __, ___) => const Center(child: Text('🐾', style: TextStyle(fontSize: 16))),
                          )
                        : const Center(child: Text('🐾', style: TextStyle(fontSize: 16))),
                  ),
                ),
                title: Text(
                  '${a['nom'] ?? '—'}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E)),
                ),
                subtitle: Text(
                  '${a['espece'] ?? '—'}${a['race'] != null ? ' · ${a['race']}' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF888888)),
                ),
                trailing: const Icon(Icons.chevron_right, color: _teal, size: 20),
                onTap: () => Navigator.pop(context, a),
              );
            },
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ]),
    );
  }
}
