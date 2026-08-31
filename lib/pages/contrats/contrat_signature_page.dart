import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/pages/contrats/contrat_finalize.dart';
import 'package:PetsMatch/pages/eleveur/animaux/contrat_pdf.dart';
import 'package:PetsMatch/widgets/signature_pad.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);

/// Signature d'un contrat `documents_animaux` (vente, réservation, certificat,
/// adoption, hébergement…) OU du récap de cession `cessions`, directement dans
/// l'appli. Les écritures sont identiques au site → synchro automatique.
class ContratSignaturePage extends StatefulWidget {
  /// Token du document `documents_animaux`.
  final String? token;
  /// Id du document `documents_animaux` (alternative au token).
  final String? documentId;
  /// Token d'un récap de cession `cessions` (mode « signer-cession »).
  final String? cessionToken;

  const ContratSignaturePage({super.key, this.token, this.documentId, this.cessionToken});

  bool get isCession => cessionToken != null;

  @override
  State<ContratSignaturePage> createState() => _ContratSignaturePageState();
}

class _ContratSignaturePageState extends State<ContratSignaturePage> {
  final _supa = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _doc;      // documents_animaux OU cessions
  Map<String, dynamic>? _animal;
  Map<String, dynamic>? _eleveur;  // map mise en forme pour le PDF

  Uint8List? _pdfBytes;            // null → carte récap
  int _pdfRev = 0;                 // incrémenté à chaque régénération → force PdfPreview
  bool _saving = false;
  bool _uploading = false;
  String? _importedPdfUrl;         // PDF importé par l'utilisateur (remplace le généré)

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String? get _myEmail => FirebaseAuth.instance.currentUser?.email?.toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Chargement ────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (widget.isCession) {
        await _loadCession();
      } else {
        await _loadDocument();
      }
    } catch (e) {
      _error = 'Impossible de charger le contrat : $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _mapEleveur(Map<String, dynamic>? up) {
    up ??= {};
    final adresse = (up['adresse'] as String?) ??
        [up['rue'], up['code_postal'], up['ville']].where((e) => e != null && '$e'.isNotEmpty).join(', ');
    return {
      'name_elevage': up['nom'],
      'firstname': up['firstname'], 'lastname': up['lastname'],
      'adress_elevage': adresse, 'adress': adresse,
      'ville': up['ville'], 'ville_pro': up['ville_pro'],
      'siret': up['siret'],
      'email': up['email_contact'],
      'code_iso_elevage': '+33',
      'numero_elevage': up['numero_elevage'] ?? up['phone_number'],
    };
  }

  /// Clause de stérilisation issue de la condition posée à la cession
  /// (`animaux.sterilisation_requise` + `sterilisation_echeance`).
  String? _sterilisationClause() {
    final a = _animal;
    if (a == null || a['sterilisation_requise'] != true) return null;
    final ech = a['sterilisation_echeance'] != null
        ? DateTime.tryParse('${a['sterilisation_echeance']}') : null;
    final dn = a['date_naissance'] != null
        ? DateTime.tryParse('${a['date_naissance']}') : null;
    int? mois;
    if (ech != null && dn != null) {
      mois = (ech.year - dn.year) * 12 + (ech.month - dn.month);
    }
    final echStr = ech != null ? DateFormat('dd/MM/yyyy').format(ech) : null;
    final buf = StringBuffer('L\'Acheteur s\'engage à faire stériliser l\'animal ');
    if (mois != null && mois > 0) {
      buf.write('avant l\'âge de $mois mois');
      if (echStr != null) buf.write(' (soit au plus tard le $echStr)');
    } else if (echStr != null) {
      buf.write('au plus tard le $echStr');
    } else {
      buf.write('dans le délai convenu entre les parties');
    }
    buf.write(' et à transmettre le certificat vétérinaire de stérilisation au Vendeur.');
    return buf.toString();
  }

  Future<void> _loadDocument() async {
    final q = _supa.from('documents_animaux').select('*');
    final res = widget.token != null
        ? await q.eq('token', widget.token!).maybeSingle()
        : await q.eq('id', widget.documentId!).maybeSingle();
    if (res == null) { _error = 'Lien invalide ou expiré.'; return; }
    _doc = Map<String, dynamic>.from(res);

    final u = (_doc!['url'] as String?)?.trim();
    if (u != null && (u.startsWith('http'))) _importedPdfUrl = u;

    final animalId = _doc!['animal_id'] as String?;
    if (animalId != null) {
      final a = await _supa.from('animaux').select('*').eq('id', animalId).maybeSingle();
      if (a != null) _animal = Map<String, dynamic>.from(a);
    }
    // Profil vendeur : celui indiqué sur le doc (pro_profile_id), sinon le
    // profil éleveur du compte, sinon is_main — pour prendre le bon
    // téléphone / adresse / email.
    const upFields = 'id, nom, firstname, lastname, adresse, rue, ville, ville_pro, code_postal, siret, numero_elevage, phone_number, email_contact';
    final elvUid = _doc!['uid_eleveur'] as String;
    final proPid = _doc!['pro_profile_id'] as String?;
    Map<String, dynamic>? up;
    if (proPid != null && proPid.isNotEmpty) {
      up = await _supa.from('user_profiles').select(upFields).eq('id', proPid).maybeSingle();
    }
    up ??= await _supa.from('user_profiles').select(upFields)
        .eq('uid', elvUid).eq('profile_type', 'eleveur').maybeSingle();
    up ??= await _supa.from('user_profiles').select(upFields)
        .eq('uid', elvUid).eq('is_main', true).maybeSingle();
    _eleveur = _mapEleveur(up != null ? Map<String, dynamic>.from(up) : null);

    await _buildPdf();
    // Pré-charger les signatures existantes dans les pads (lecture seule via existingSignature)
  }

  Future<void> _loadCession() async {
    final res = await _supa.from('cessions').select('*')
        .eq('token', widget.cessionToken!).maybeSingle();
    if (res == null) { _error = 'Lien invalide ou expiré.'; return; }
    _doc = Map<String, dynamic>.from(res);
    final animalId = _doc!['animal_id'] as String?;
    if (animalId != null) {
      final a = await _supa.from('animaux').select('*').eq('id', animalId).maybeSingle();
      if (a != null) _animal = Map<String, dynamic>.from(a);
    }
    final up = await _supa.from('user_profiles')
        .select('nom, firstname, lastname')
        .eq('uid', _doc!['uid_eleveur'] as String)
        .eq('is_main', true).maybeSingle();
    _eleveur = up != null ? Map<String, dynamic>.from(up) : {};
  }

  Future<void> _buildPdf() async {
    // PDF importé par l'utilisateur → il prime sur celui généré.
    if (_importedPdfUrl != null) {
      try {
        final resp = await http.get(Uri.parse(_importedPdfUrl!));
        _pdfBytes = (resp.statusCode == 200 &&
                (resp.headers['content-type']?.contains('pdf') ?? _importedPdfUrl!.toLowerCase().contains('.pdf')))
            ? resp.bodyBytes
            : null;
      } catch (_) {
        _pdfBytes = null;
      }
      return;
    }
    final type = _doc?['type'] as String? ?? '';
    final meta = (_doc?['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
    if (_animal == null || _eleveur == null) { _pdfBytes = null; return; }
    final sigElv = meta['signature_eleveur'] as String?;
    final sigAcq = meta['signature_acquereur'] as String?;
    String m(String k) => (meta[k]?.toString() ?? '');

    final dateCession = m('date_cession').isNotEmpty ? DateTime.tryParse(m('date_cession')) : null;
    final sterilClause = _sterilisationClause();
    final villeEleveur = (_eleveur?['ville'] as String?) ?? (_eleveur?['ville_pro'] as String?) ?? '';
    final ville = m('ville_signature').isNotEmpty ? m('ville_signature') : villeEleveur;
    final clausesOff = ((meta['clauses_off'] as List?)?.map((e) => e.toString()).toSet()) ?? <String>{};
    final tvaTaux = (meta['tva_assujetti'] == true || m('tva_assujetti') == 'true')
        ? m('tva_taux') : '';
    // Champs animal éditables dans le formulaire → priment sur la fiche animale.
    final animalPdf = <String, dynamic>{
      ..._animal!,
      if (m('animal_nom').isNotEmpty) 'nom': m('animal_nom'),
      if (m('animal_race').isNotEmpty) 'race': m('animal_race'),
      if (m('animal_couleur').isNotEmpty) 'couleur': m('animal_couleur'),
      if (m('animal_sexe').isNotEmpty) 'sexe': m('animal_sexe'),
      if (m('animal_date_naissance').isNotEmpty) 'date_naissance': m('animal_date_naissance'),
      if (m('animal_identification').isNotEmpty) 'identification': m('animal_identification'),
      if (m('animal_pedigree').isNotEmpty) 'pedigree_lof': m('animal_pedigree'),
      if (m('animal_nom_pere').isNotEmpty) 'nom_pere': m('animal_nom_pere'),
      if (m('animal_puce_pere').isNotEmpty) 'puce_pere': m('animal_puce_pere'),
      if (m('animal_nom_mere').isNotEmpty) 'nom_mere': m('animal_nom_mere'),
      if (m('animal_puce_mere').isNotEmpty) 'puce_mere': m('animal_puce_mere'),
    };

    try {
      if (type == 'contrat_vente' || type == 'contrat_reservation') {
        _pdfBytes = await contratVentePdfBytes(
          animal: animalPdf, eleveur: _eleveur!,
          acquereurNom: m('acquereur_nom'),
          acquereurAdresse: m('acquereur_adresse'),
          acquereurEmail: m('acquereur_email'),
          acquereurTel: m('acquereur_tel'),
          prix: m('prix').isEmpty ? '0' : m('prix'),
          dateCession: dateCession, notes: m('notes'),
          sigVendeur: sigElv, sigAcheteur: sigAcq,
          civiliteAcheteur: m('acquereur_civilite'),
          prenomAcheteur: m('acquereur_prenom'),
          nomAcheteur: m('acquereur_nom_famille'),
          cpAcheteur: m('acquereur_cp'),
          villeAcheteur: m('acquereur_ville'),
          villeNaissance: m('ville_naissance').isNotEmpty ? m('ville_naissance') : villeEleveur,
          acompte: m('acompte'),
          tranche1: m('tranche1').isNotEmpty ? m('tranche1') : m('prix'),
          tva: m('tva'),
          tvaTaux: tvaTaux,
          modePaiement: m('mode_paiement'),
          montantTranche2: m('montant_tranche2').isEmpty ? '2 000' : m('montant_tranche2'),
          mediateurNom: m('mediateur_nom'),
          mediateurUrl: m('mediateur_url'),
          sterilisationClause: sterilClause, villeSignature: ville,
          clausesOff: clausesOff,
        );
      } else if (type == 'certificat_cession') {
        _pdfBytes = await certificatCessionPdfBytes(
          animal: animalPdf, eleveur: _eleveur!,
          acquereurNom: m('acquereur_nom'),
          acquereurAdresse: m('acquereur_adresse'),
          acquereurEmail: m('acquereur_email'),
          acquereurTel: m('acquereur_tel'),
          prix: m('prix'), dateCession: dateCession, notes: m('notes'),
          sigVendeur: sigElv, sigAcheteur: sigAcq,
          civiliteAcheteur: m('acquereur_civilite'),
          prenomAcheteur: m('acquereur_prenom'),
          nomAcheteur: m('acquereur_nom_famille'),
          cpAcheteur: m('acquereur_cp'),
          villeAcheteur: m('acquereur_ville'),
          modePaiement: m('mode_paiement'),
          tva: m('tva'), tvaTaux: tvaTaux,
          sterilisationClause: sterilClause, villeSignature: ville,
        );
      } else {
        _pdfBytes = null; // autres types → carte récap
      }
    } catch (_) {
      _pdfBytes = null;
    }
    _pdfRev++;
  }

  // ── Rôle courant ──────────────────────────────────────────────────────────

  bool get _isEleveur => _doc != null && _myUid == (_doc!['uid_eleveur'] as String?);
  bool get _isAcquereur {
    if (_doc == null) return false;
    if (widget.isCession) {
      return _myUid == (_doc!['uid_acquereur'] as String?);
    }
    final meta = (_doc!['metadata'] as Map?) ?? {};
    final acqEmail = (meta['acquereur_email'] as String?)?.toLowerCase();
    if (acqEmail != null && acqEmail.isNotEmpty && acqEmail == _myEmail) return true;
    if (_animal != null && _myUid == (_animal!['uid_acquereur'] as String?)) return true;
    return _myUid == (_doc!['uid_acquereur'] as String?);
  }

  // ── Signature — documents_animaux ─────────────────────────────────────────

  Future<void> _signerDocument(String role, String dataUrl) async {
    setState(() => _saving = true);
    try {
      // Relire la version en base pour ne pas écraser la signature de l'autre
      // partie si elle a signé entre-temps (métadonnées locales périmées).
      final fresh = await _supa.from('documents_animaux')
          .select('metadata').eq('id', _doc!['id']).maybeSingle();
      final meta = Map<String, dynamic>.from(
          (fresh?['metadata'] as Map?) ?? (_doc!['metadata'] as Map?) ?? {});
      final now = DateTime.now().toIso8601String();
      final sigField  = role == 'eleveur' ? 'signature_eleveur' : 'signature_acquereur';
      final dateField = role == 'eleveur' ? 'signe_eleveur_le'  : 'signe_acquereur_le';
      meta[sigField] = dataUrl;
      meta[dateField] = now;
      bool notBlank(dynamic v) => v != null && '$v'.trim().isNotEmpty;
      final hasElv = notBlank(meta['signature_eleveur']);
      final hasAcq = notBlank(meta['signature_acquereur']);
      final bothSigned = hasElv && hasAcq;
      final statut = bothSigned
          ? 'signe'
          : (hasElv || hasAcq) ? 'partiellement_signe' : 'en_attente';

      await _supa.from('documents_animaux').update({
        'metadata': meta,
        'statut': statut,
        if (bothSigned) 'signe_le': now,
      }).eq('id', _doc!['id']);

      _doc!['metadata'] = meta;
      _doc!['statut'] = statut;

      // Le transfert de l'animal n'a lieu QUE lorsque le vendeur/éleveur pose la
      // dernière signature. Si c'est l'acquéreur qui signe en dernier, on
      // notifie le vendeur pour qu'il confirme (bandeau « Confirmer la cession »).
      final vendeurAFinalise = bothSigned && role == 'eleveur';
      if (vendeurAFinalise) {
        await finalizeContratSigne(doc: _doc!, animal: _animal);
      }
      await notifierContratSignature(
        doc: _doc!, role: role, bothSigned: vendeurAFinalise);

      await _buildPdf();
      if (mounted) {
        setState(() {});
        _snack(bothSigned
            ? (vendeurAFinalise
                ? '✅ Contrat signé — cession finalisée'
                : '✅ Signé. Le vendeur va confirmer la cession.')
            : '✍️ Signature enregistrée');
      }
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Signature — récap cession ────────────────────────────────────────────

  Future<void> _signerCession(String dataUrl) async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      await _supa.from('cessions').update({
        'signature_acquereur': dataUrl,
        'statut': 'signe_acquereur',
        'signed_acquereur_at': now,
      }).eq('id', _doc!['id']);
      _doc!['statut'] = 'signe_acquereur';
      _doc!['signature_acquereur'] = dataUrl;

      // Notifier l'éleveur
      final eleveurUid = _doc!['uid_eleveur'] as String?;
      if (eleveurUid != null) {
        final prof = await _supa.from('user_profiles')
            .select('id').eq('uid', eleveurUid).eq('profile_type', 'eleveur').maybeSingle();
        await _supa.from('notifications').insert({
          'uid': eleveurUid,
          'type': 'cession_signee_acquereur',
          'title': '✍️ ${_doc!['nom_acquereur'] ?? 'L\'acquéreur'} a signé — ${_animal?['nom'] ?? 'Animal'}',
          'body': 'L\'acquéreur a signé le récap de cession. Vous pouvez maintenant confirmer le transfert.',
          if (prof?['id'] != null) 'profile_id': prof!['id'],
          'data': {'animalId': _doc!['animal_id'], 'token': _doc!['token']},
          'read': false,
        });
      }
      if (mounted) { setState(() {}); _snack('✅ Signature enregistrée'); }
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Envoie (ou renvoie) le contrat à l'acquéreur : notification in-app + lien.
  Future<void> _envoyerAcquereur() async {
    setState(() => _saving = true);
    try {
      final meta = (_doc!['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
      final token = _doc!['token'] as String?;
      final url = token != null ? '$kSiteBaseUrl/signer-contrat/$token' : null;

      // Résoudre l'uid de l'acquéreur
      var acqUid = (meta['acquereur_uid'] as String?) ?? (_doc!['uid_acquereur'] as String?);
      final email = (meta['acquereur_email'] as String?)?.trim();
      if ((acqUid == null || acqUid.isEmpty) && email != null && email.isNotEmpty) {
        final u = await _supa.from('users').select('uid').eq('email', email).maybeSingle();
        acqUid = u?['uid'] as String?;
        if (acqUid != null) {
          meta['acquereur_uid'] = acqUid;
          await _supa.from('documents_animaux')
              .update({'metadata': meta, 'uid_acquereur': acqUid}).eq('id', _doc!['id']);
          _doc!['metadata'] = meta;
        }
      }

      if ((_doc!['statut'] as String?) == 'brouillon') {
        await _supa.from('documents_animaux').update({'statut': 'en_attente'}).eq('id', _doc!['id']);
        _doc!['statut'] = 'en_attente';
      }

      if (acqUid != null && acqUid.isNotEmpty) {
        final prof = await _supa.from('user_profiles')
            .select('id').eq('uid', acqUid).eq('is_main', true).maybeSingle();
        await _supa.from('notifications').insert({
          'uid': acqUid,
          'type': 'contrat_signe_eleveur',
          'title': '📄 Contrat à signer — ${_animal?['nom'] ?? 'Animal'}',
          'body': 'L\'éleveur vous a transmis ${_doc!['titre'] ?? 'un contrat'} — vérifiez et signez.',
          if (prof?['id'] != null) 'profile_id': prof!['id'],
          'data': {
            if (token != null) 'token': token,
            'documentId': _doc!['id'],
            if (url != null) 'url': url,
            if (url != null) 'signingUrl': url,
          },
          'read': false,
        });
      }

      if (email != null && email.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('$kSiteBaseUrl/api/contrat/notify-email'),
            headers: {'Content-Type': 'application/json'},
            body: '{"email":"$email","signing_url":"${url ?? ''}","titre":"${_doc!['titre'] ?? 'Contrat'}"}',
          );
        } catch (_) {}
      }

      if (mounted) {
        setState(() {});
        if (url != null) {
          await Clipboard.setData(ClipboardData(text: url));
          _snack(acqUid != null
              ? '📤 Envoyé à l\'acquéreur — lien copié'
              : '🔗 Lien copié (acquéreur non inscrit)');
        } else {
          _snack('📤 Contrat transmis');
        }
      }
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _supprimerDocument() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce contrat ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        content: const Text('Le document sera définitivement supprimé pour les deux parties.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('documents_animaux').delete().eq('id', _doc!['id']);
      if (mounted) { Navigator.pop(context); _snack('Contrat supprimé'); }
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  Future<void> _ouvrirWeb() async {
    final token = _doc?['token'] as String?;
    if (token == null) return;
    final path = widget.isCession ? 'signer-cession' : 'signer-contrat';
    final url = Uri.parse('$kSiteBaseUrl/$path/$token');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(widget.isCession ? 'Cession — signature' : 'Contrat — signature',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          if (!widget.isCession && !_loading && _error == null && _isEleveur
              && (_doc?['statut'] as String?) != 'signe')
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Supprimer ce contrat',
              onPressed: _supprimerDocument,
            ),
          if (_doc?['token'] != null)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              tooltip: 'Ouvrir sur le web',
              onPressed: _ouvrirWeb,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _error != null
              ? _errorView()
              : widget.isCession
                  ? _cessionView()
                  : _documentView(),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('❌', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _dark)),
          ]),
        ),
      );

  // ── Document ──────────────────────────────────────────────────────────────

  Widget _documentView() {
    final statut = _doc?['statut'] as String? ?? 'en_attente';
    final type = _doc?['type'] as String? ?? '';
    final isFacture = type == 'facture';
    final meta = (_doc?['metadata'] as Map?) ?? {};
    final sigElv = meta['signature_eleveur'] as String?;
    final sigAcq = meta['signature_acquereur'] as String?;
    final isFinal = statut == 'signe' || statut == 'annule' || statut == 'refuse' || statut == 'expire';
    // Modifiable uniquement tant que rien n'est transmis / signé.
    final canEdit = _isEleveur && !isFacture && statut == 'brouillon'
        && sigElv == null && sigAcq == null;

    return Column(children: [
      _statutBanner(statut),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            if (_importedPdfUrl != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.attach_file, size: 14, color: _teal),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Contrat importé (PDF)',
                      style: TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w600))),
                  if (canEdit)
                    TextButton(
                      onPressed: _uploading ? null : _retirerImport,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                      child: const Text('Utiliser celui de l\'appli', style: TextStyle(fontSize: 11)),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
            ],

            // Corps du contrat
            if (_pdfBytes != null)
              _pdfCard()
            else if (_importedPdfUrl != null)
              _pdfIndispo()
            else
              _recapCard(),

            if (canEdit) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 12, children: [
                if (_importedPdfUrl == null)
                  TextButton.icon(
                    onPressed: () { _editerInfos(); },
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Modifier les informations', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
                  ),
                TextButton.icon(
                  onPressed: _uploading ? null : _importerPdf,
                  icon: _uploading
                      ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file_outlined, size: 15),
                  label: Text(_importedPdfUrl == null ? 'Importer mon PDF' : 'Remplacer le PDF', style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
                ),
              ]),
            ] else if (_isEleveur && !isFacture) ...[
              const SizedBox(height: 6),
              Text(
                statut == 'brouillon'
                    ? 'Signé — non modifiable.'
                    : 'Transmis au client — non modifiable.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ],

            // Envoyer / relancer l'acquéreur (contrat non finalisé)
            if (_isEleveur && !isFacture && !isFinal && sigAcq == null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _envoyerAcquereur,
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: Text(
                    statut == 'brouillon' ? 'Envoyer à l\'acquéreur' : 'Relancer l\'acquéreur',
                    style: const TextStyle(fontSize: 12, fontFamily: 'Galey', fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal, side: const BorderSide(color: _teal),
                    minimumSize: const Size(0, 42),
                  ),
                ),
              ),
            ],

            if (!isFacture) ...[
              const SizedBox(height: 16),
              const Text('Signatures',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, color: _dark)),
              const SizedBox(height: 10),
              _sigZone(
                label: 'Signature de l\'éleveur / vendeur',
                existing: sigElv,
                canSign: !isFinal && _isEleveur && sigElv == null,
                signedAt: meta['signe_eleveur_le'] as String?,
                onSign: (d) => _signerDocument('eleveur', d),
              ),
              const SizedBox(height: 12),
              _sigZone(
                label: 'Signature de l\'acquéreur',
                existing: sigAcq,
                canSign: !isFinal && _isAcquereur && sigAcq == null,
                signedAt: meta['signe_acquereur_le'] as String?,
                onSign: (d) => _signerDocument('acquereur', d),
              ),
            ],

            if ((isFinal || isFacture) && _pdfBytes != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Printing.sharePdf(
                    bytes: _pdfBytes!, filename: isFacture ? 'facture.pdf' : 'contrat.pdf'),
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('Partager / Imprimer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  minimumSize: const Size(double.infinity, 44),
                  side: const BorderSide(color: _teal),
                ),
              ),
            ],
          ],
        ),
      ),
    ]);
  }

  // ── Cession ───────────────────────────────────────────────────────────────

  Widget _cessionView() {
    final statut = _doc?['statut'] as String? ?? '';
    final hasSigned = statut == 'signe_acquereur' || statut == 'confirme';
    final sig = _doc?['signature_acquereur'] as String?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _recapCard(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x33FFB300)),
          ),
          child: const Text(
            'En signant, vous confirmez :\n'
            '• avoir lu et accepté les conditions de cession\n'
            '• prendre la responsabilité de l\'animal dès la remise\n'
            '• avoir été informé des conditions légales de détention\n'
            '• disposer des moyens d\'assurer son bien-être',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF8A6D3B), height: 1.5),
          ),
        ),
        const SizedBox(height: 14),
        const Text('Votre signature',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15, color: _dark)),
        const SizedBox(height: 10),
        _sigZone(
          label: _doc?['nom_acquereur'] as String? ?? 'Acquéreur',
          existing: sig,
          canSign: !hasSigned && _isAcquereur && sig == null,
          signedAt: _doc?['signed_acquereur_at'] as String?,
          onSign: _signerCession,
        ),
        if (hasSigned) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('✅ Signature enregistrée — en attente de confirmation par le vendeur.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF2E5A1E))),
          ),
        ],
      ],
    );
  }

  // ── Widgets partagés ─────────────────────────────────────────────────────

  Widget _statutBanner(String statut) {
    final (label, color) = switch (statut) {
      'signe'                => ('✅ Contrat signé par les deux parties', _green),
      'partiellement_signe'  => ('✍️ Une signature reçue — en attente de la seconde', const Color(0xFF2563EB)),
      'refuse'               => ('❌ Contrat refusé', Colors.red),
      'annule'               => ('🚫 Contrat annulé', Colors.grey),
      'expire'               => ('⏰ Contrat expiré', Colors.orange),
      _                      => ('⏳ En attente des signatures', const Color(0xFFB45309)),
    };
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Text(label, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Widget _recapCard() {
    final meta = (_doc?['metadata'] as Map?) ?? {};
    final a = _animal ?? {};
    final elvNom = (_eleveur?['name_elevage'] as String?) ?? (_eleveur?['nom'] as String?) ??
        '${_eleveur?['firstname'] ?? ''} ${_eleveur?['lastname'] ?? ''}'.trim();
    final acqNom = widget.isCession
        ? (_doc?['nom_acquereur'] as String? ?? '—')
        : (meta['acquereur_nom'] as String? ?? '—');
    final prix = widget.isCession
        ? (_doc?['prix'] as num?)?.toString()
        : (meta['prix'] as String?);
    final dateStr = widget.isCession
        ? (_doc?['date_cession'] as String?)
        : (meta['date_cession'] as String?);
    final dn = a['date_naissance'] != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse('${a['date_naissance']}') ?? DateTime.now())
        : null;

    Widget row(String k, String? v) => (v == null || v.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 96, child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
              Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _dark))),
            ]),
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((_doc?['titre'] as String?) ?? 'Récapitulatif',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 14, color: _dark)),
        const SizedBox(height: 10),
        row('Animal', a['nom'] as String?),
        row('Espèce', a['espece'] as String?),
        row('Race', a['race'] as String?),
        row('Né le', dn),
        row('Puce', a['identification'] as String?),
        row('Vendeur', elvNom.isEmpty ? null : elvNom),
        row('Acquéreur', acqNom),
        row('Prix', prix == null || prix.isEmpty || prix == '0' ? 'Gratuit' : '$prix €'),
        row('Date', dateStr != null && dateStr.isNotEmpty
            ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(dateStr) ?? DateTime.now())
            : null),
        if ((meta['notes'] as String?)?.isNotEmpty == true) row('Notes', meta['notes'] as String?),
        if (widget.isCession && _doc?['sterilisation_requise'] == true)
          row('Stérilisation', 'Requise avant le '
              '${_doc?['sterilisation_echeance'] != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse('${_doc!['sterilisation_echeance']}')) : "l'âge fixé"}'),
        if (_pdfBytes == null && !widget.isCession && _doc?['token'] != null) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _ouvrirWeb,
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Voir la version complète (web)', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
          ),
        ],
      ]),
    );
  }

  Future<void> _ouvrirSignatureFullScreen(String label, Future<void> Function(String) onSign) async {
    final dataUrl = await Navigator.push<String?>(context, MaterialPageRoute(
      builder: (_) => SignatureFullScreen(titre: label),
    ));
    if (dataUrl != null && dataUrl.isNotEmpty) await onSign(dataUrl);
  }

  Widget _sigZone({
    required String label,
    required String? existing,
    required bool canSign,
    required String? signedAt,
    required Future<void> Function(String) onSign,
  }) {
    final signed = existing != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: signed ? _green.withValues(alpha: 0.4) : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label,
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: _dark))),
          if (signed)
            Text(signedAt != null
                ? '✅ ${DateFormat('dd/MM/yyyy').format(DateTime.tryParse(signedAt) ?? DateTime.now())}'
                : '✅ Signé', style: const TextStyle(fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        if (signed)
          SignatureView(existing)
        else if (canSign)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : () => _ouvrirSignatureFullScreen(label, onSign),
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.draw_outlined, size: 18),
              label: const Text('Signer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white, elevation: 0,
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        else
          Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              widget.isCession ? 'Réservé à l\'acquéreur' : 'En attente — cette partie signera de son côté',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
      ]),
    );
  }

  // ── Aperçu PDF ────────────────────────────────────────────────────────────

  Widget _pdfCard() => Column(children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _pdfFullScreen,
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Lire le contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          clipBehavior: Clip.antiAlias,
          child: PdfPreview(
            key: ValueKey(_pdfRev),
            build: (_) => _pdfBytes!,
            useActions: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            scrollViewDecoration: const BoxDecoration(color: Color(0xFFECEEF0)),
          ),
        ),
        const SizedBox(height: 4),
        Text('Aperçu — appuyez sur « Lire le contrat » pour zoomer',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ]);

  Widget _pdfIndispo() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(children: [
          const Icon(Icons.picture_as_pdf_outlined, size: 32, color: _teal),
          const SizedBox(height: 8),
          const Text('Contrat importé', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _dark)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              final u = _importedPdfUrl;
              if (u != null) launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Ouvrir le document'),
            style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
          ),
        ]),
      );

  void _pdfFullScreen() {
    if (_pdfBytes == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _PdfZoomViewer(
        bytes: _pdfBytes!,
        titre: (_doc?['titre'] as String?) ?? 'Contrat',
      ),
    ));
  }

  // ── Import d'un PDF existant (remplace le contrat généré) ─────────────────

  Future<void> _importerPdf() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (res == null || res.files.isEmpty || res.files.first.path == null) return;
    setState(() => _uploading = true);
    try {
      final file = File(res.files.first.path!);
      final path = 'contrats/${_doc!['uid_eleveur']}/${_doc!['id']}/import_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final snap = await FirebaseStorage.instance.ref(path).putFile(file);
      final url = await snap.ref.getDownloadURL();
      await _supa.from('documents_animaux').update({'url': url}).eq('id', _doc!['id']);
      _doc!['url'] = url;
      _importedPdfUrl = url;
      await _buildPdf();
      if (mounted) { setState(() {}); _snack('📎 PDF importé — c\'est ce document qui sera signé'); }
    } catch (e) {
      _snack('Erreur import : $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _retirerImport() async {
    setState(() => _uploading = true);
    try {
      await _supa.from('documents_animaux').update({'url': null}).eq('id', _doc!['id']);
      _doc!['url'] = null;
      _importedPdfUrl = null;
      await _buildPdf();
      if (mounted) { setState(() {}); _snack('Contrat de l\'appli réactivé'); }
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── Édition des informations du contrat (éleveur) ─────────────────────────

  Future<void> _editerInfos() async {
    try {
      final rawMeta = _doc?['metadata'];
      final meta = <String, dynamic>{};
      if (rawMeta is Map) {
        rawMeta.forEach((k, v) => meta['$k'] = v);
      }
      final villeEleveur = (_eleveur?['ville'] as String?)
          ?? (_eleveur?['ville_pro'] as String?) ?? '';
      final updated = await Navigator.of(context, rootNavigator: true)
          .push<Map<String, dynamic>?>(MaterialPageRoute(
        builder: (_) => _ContratInfosForm(
          meta: meta,
          villeEleveur: villeEleveur,
          sterilisationRequise: _animal?['sterilisation_requise'] == true,
          isCertificat: (_doc?['type'] as String?) == 'certificat_cession',
          animal: _animal ?? {},
        ),
      ));
      if (updated == null) return;
      // Clause de stérilisation calculée → stockée pour que le site affiche
      // exactement le même texte que l'appli.
      final sc = _sterilisationClause();
      if (sc != null) updated['sterilisation_clause'] = sc;
      await _supa.from('documents_animaux').update({
        'metadata': updated,
      }).eq('id', _doc!['id']);
      _doc!['metadata'] = updated;
      await _buildPdf();
      if (mounted) { setState(() {}); _snack('Contrat mis à jour'); }
    } catch (e) {
      _snack('Erreur : $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Formulaire complet des informations du contrat (éleveur, avant signature).
// ═══════════════════════════════════════════════════════════════════════════

const _kClauses = [
  ('art3', 'Article 3 — Conditions de la vente'),
  ('art4', 'Article 4 — Transfert de propriété'),
  ('art5', 'Article 5 — Garanties'),
  ('art6', 'Article 6 — Confidentialité'),
  ('art7', 'Article 7 — Droit de rétractation'),
  ('art8', 'Article 8 — Règlement amiable / médiation'),
];

class _ContratInfosForm extends StatefulWidget {
  final Map<String, dynamic> meta;
  final String villeEleveur;
  final bool sterilisationRequise;
  final bool isCertificat;
  final Map<String, dynamic> animal;

  const _ContratInfosForm({
    required this.meta,
    required this.villeEleveur,
    required this.sterilisationRequise,
    required this.isCertificat,
    required this.animal,
  });

  @override
  State<_ContratInfosForm> createState() => _ContratInfosFormState();
}

class _ContratInfosFormState extends State<_ContratInfosForm> {
  late final Map<String, TextEditingController> _c;
  late String _civilite;
  late String _modePaiement;
  late Set<String> _clausesOff;
  late bool _tvaAssujetti;
  late double _tvaTaux;
  String _sexeAnimal = '';        // 'male' | 'femelle' | ''
  DateTime? _dateNaissanceAnimal;

  static const _paiements = ['virement', 'espèces', 'chèque', 'Oney', 'autre'];
  static const _tauxTva = [20.0, 10.0, 5.5];

  double _parseNum(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9,.]'), '').replaceAll(',', '.')) ?? 0;

  /// Base TTC : acompte + tranche 1 (vente) ou prix (certificat).
  double get _baseTtc => widget.isCertificat
      ? _parseNum(_c['prix']!.text)
      : _parseNum(_c['acompte']!.text) + _parseNum(_c['tranche1']!.text);

  /// TVA incluse dans le prix TTC au taux choisi.
  double get _tvaCalculee =>
      _tvaAssujetti && _baseTtc > 0 ? _baseTtc - _baseTtc / (1 + _tvaTaux / 100) : 0;

  void _syncTva() {
    if (_tvaAssujetti) {
      _c['tva']!.text = _tvaCalculee.toStringAsFixed(2).replaceAll('.', ',');
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final m = widget.meta;
    String v(String k, [String d = '']) => m[k]?.toString().trim().isNotEmpty == true ? m[k].toString() : d;
    // Pré-remplissage prénom/nom à partir de acquereur_nom si champs séparés vides
    final full = v('acquereur_nom');
    final parts = full.split(' ');
    // Découpe l'adresse « rue … 93160 Noisy le Grand » → rue / CP / ville
    var rue = v('acquereur_adresse');
    var cp = v('acquereur_cp');
    var ville = v('acquereur_ville');
    if (cp.isEmpty && ville.isEmpty && rue.isNotEmpty) {
      final match = RegExp(r'\b(\d{5})\b').firstMatch(rue);
      if (match != null) {
        cp = match.group(1)!;
        ville = rue.substring(match.end).replaceFirst(RegExp(r'^[\s,]+'), '').trim();
        rue = rue.substring(0, match.start).replaceFirst(RegExp(r'[\s,]+$'), '').trim();
      }
    }
    _c = {
      'acquereur_prenom': TextEditingController(text: v('acquereur_prenom', parts.length > 1 ? parts.first : '')),
      'acquereur_nom_famille': TextEditingController(text: v('acquereur_nom_famille', parts.length > 1 ? parts.sublist(1).join(' ') : full)),
      'acquereur_adresse': TextEditingController(text: rue),
      'acquereur_cp': TextEditingController(text: cp),
      'acquereur_ville': TextEditingController(text: ville),
      'acquereur_tel': TextEditingController(text: v('acquereur_tel')),
      'acquereur_email': TextEditingController(text: v('acquereur_email')),
      'ville_naissance': TextEditingController(text: v('ville_naissance', widget.villeEleveur)),
      'animal_nom': TextEditingController(text: v('animal_nom', '${widget.animal['nom'] ?? ''}')),
      'animal_race': TextEditingController(text: v('animal_race', '${widget.animal['race'] ?? ''}')),
      'animal_couleur': TextEditingController(text: v('animal_couleur', '${widget.animal['couleur'] ?? ''}')),
      'animal_identification': TextEditingController(text: v('animal_identification', '${widget.animal['identification'] ?? ''}')),
      'animal_pedigree': TextEditingController(text: v('animal_pedigree',
          '${widget.animal['pedigree_lof'] ?? widget.animal['pedigree_numero'] ?? ''}')),
      'animal_nom_pere': TextEditingController(text: v('animal_nom_pere', '${widget.animal['nom_pere'] ?? ''}')),
      'animal_puce_pere': TextEditingController(text: v('animal_puce_pere', '${widget.animal['puce_pere'] ?? ''}')),
      'animal_nom_mere': TextEditingController(text: v('animal_nom_mere', '${widget.animal['nom_mere'] ?? ''}')),
      'animal_puce_mere': TextEditingController(text: v('animal_puce_mere', '${widget.animal['puce_mere'] ?? ''}')),
      'prix': TextEditingController(text: v('prix')),
      'acompte': TextEditingController(text: v('acompte')),
      'tranche1': TextEditingController(text: v('tranche1')),
      'tva': TextEditingController(text: v('tva')),
      'montant_tranche2': TextEditingController(text: v('montant_tranche2', '2 000')),
      'mediateur_nom': TextEditingController(text: v('mediateur_nom', 'Yves Legeay')),
      'mediateur_url': TextEditingController(text: v('mediateur_url', 'https://snpcc.com/')),
      'ville_signature': TextEditingController(text: v('ville_signature', widget.villeEleveur)),
      'notes': TextEditingController(text: v('notes')),
    };
    _civilite = v('acquereur_civilite');
    _modePaiement = v('mode_paiement');
    final rawClauses = m['clauses_off'];
    _clausesOff = rawClauses is List
        ? rawClauses.map((e) => e.toString()).toSet()
        : <String>{};
    _tvaAssujetti = m['tva_assujetti'] == true || v('tva_assujetti') == 'true';
    _tvaTaux = double.tryParse(v('tva_taux', '20').replaceAll(',', '.')) ?? 20;
    if (!_tauxTva.contains(_tvaTaux)) _tvaTaux = 20;
    final sx = v('animal_sexe', '${widget.animal['sexe'] ?? ''}').toLowerCase();
    _sexeAnimal = ['male', 'mâle', 'm'].contains(sx) ? 'male'
        : ['femelle', 'female', 'f'].contains(sx) ? 'femelle' : '';
    final dnStr = v('animal_date_naissance', '${widget.animal['date_naissance'] ?? ''}');
    _dateNaissanceAnimal = dnStr.isNotEmpty ? DateTime.tryParse(dnStr) : null;
  }

  @override
  void dispose() {
    for (final ctrl in _c.values) { ctrl.dispose(); }
    super.dispose();
  }

  void _enregistrer() {
    final m = Map<String, dynamic>.from(widget.meta);
    for (final e in _c.entries) { m[e.key] = e.value.text.trim(); }
    m['acquereur_civilite'] = _civilite;
    m['mode_paiement'] = _modePaiement;
    m['tva_assujetti'] = _tvaAssujetti;
    m['tva_taux'] = _tvaTaux;
    if (_tvaAssujetti) m['tva'] = _tvaCalculee.toStringAsFixed(2).replaceAll('.', ',');
    m['animal_sexe'] = _sexeAnimal;
    m['animal_date_naissance'] = _dateNaissanceAnimal?.toIso8601String().split('T').first ?? '';
    // acquereur_nom = « Prénom Nom » recomposé (cohérence listes / notifs)
    final complet = [_c['acquereur_prenom']!.text.trim(), _c['acquereur_nom_famille']!.text.trim()]
        .where((s) => s.isNotEmpty).join(' ').trim();
    if (complet.isNotEmpty) m['acquereur_nom'] = complet;
    m['clauses_off'] = _clausesOff.toList();
    Navigator.pop(context, m);
  }

  /// Champ numérique (€) — recalcule la TVA à chaque frappe.
  Widget _numField(String key, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _syncTva(),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  Widget _field(String key, String label, {TextInputType? kb, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[key],
          keyboardType: kb,
          maxLines: lines,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 13, color: _teal)),
      );

  @override
  Widget build(BuildContext context) {
    const num = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white,
        title: const Text('Informations du contrat',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _enregistrer,
            child: const Text('Enregistrer', style: TextStyle(color: Colors.white, fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _section('Acquéreur'),
          Row(children: [
            const Text('Civilité  ', style: TextStyle(fontSize: 13, color: _dark)),
            ...['M.', 'Mme'].map((c) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(c),
                selected: _civilite == c,
                onSelected: (_) => setState(() => _civilite = _civilite == c ? '' : c),
              ),
            )),
          ]),
          const SizedBox(height: 10),
          _field('acquereur_prenom', 'Prénom'),
          _field('acquereur_nom_famille', 'Nom'),
          _field('acquereur_adresse', 'Adresse'),
          Row(children: [
            SizedBox(width: 110, child: _field('acquereur_cp', 'Code postal', kb: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _field('acquereur_ville', 'Ville')),
          ]),
          _field('acquereur_tel', 'Téléphone', kb: TextInputType.phone),
          _field('acquereur_email', 'Email', kb: TextInputType.emailAddress),

          _section('Animal'),
          _field('animal_nom', 'Nom de l\'animal'),
          _field('animal_race', 'Race'),
          _field('animal_couleur', 'Couleur / robe'),
          _field('animal_identification', 'N° d\'identification (puce / transpondeur) *'),
          _field('animal_pedigree', 'N° de pedigree (LOF / LOOF / autre club) — si applicable'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              const Text('Sexe  ', style: TextStyle(fontSize: 13, color: _dark)),
              ...[('male', 'Mâle'), ('femelle', 'Femelle')].map((s) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s.$2),
                  selected: _sexeAnimal == s.$1,
                  onSelected: (_) => setState(() => _sexeAnimal = _sexeAnimal == s.$1 ? '' : s.$1),
                ),
              )),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dateNaissanceAnimal ?? DateTime.now(),
                  firstDate: DateTime(2005),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _dateNaissanceAnimal = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date de naissance',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  _dateNaissanceAnimal != null
                      ? DateFormat('dd/MM/yyyy').format(_dateNaissanceAnimal!)
                      : '—',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
          _field('ville_naissance', 'Ville de naissance de l\'animal'),
          const SizedBox(height: 2),
          Text('Filiation (parents)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(flex: 3, child: _field('animal_nom_pere', 'Nom du père')),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _field('animal_puce_pere', 'Puce père')),
          ]),
          Row(children: [
            Expanded(flex: 3, child: _field('animal_nom_mere', 'Nom de la mère')),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _field('animal_puce_mere', 'Puce mère')),
          ]),

          _section('Prix'),
          if (!widget.isCertificat) ...[
            _numField('acompte', 'Acompte déjà versé (€)'),
            _numField('tranche1', 'Tranche 1 — au départ (€)'),
          ] else
            _numField('prix', 'Prix de cession (€)'),

          // ── TVA ─────────────────────────────────────────────────────────
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Assujetti à la TVA', style: TextStyle(fontSize: 13)),
            subtitle: const Text('Le prix saisi est TTC — la TVA est calculée automatiquement',
                style: TextStyle(fontSize: 11)),
            value: _tvaAssujetti,
            onChanged: (v) { _tvaAssujetti = v; _syncTva(); },
          ),
          if (_tvaAssujetti) ...[
            Row(children: [
              const Text('Taux  ', style: TextStyle(fontSize: 13)),
              ..._tauxTva.map((t) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(t == t.roundToDouble() ? '${t.toInt()} %' : '${t.toString().replaceAll('.', ',')} %'),
                  selected: _tvaTaux == t,
                  onSelected: (_) { _tvaTaux = t; _syncTva(); },
                ),
              )),
            ]),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Base TTC : ${_baseTtc.toStringAsFixed(2).replaceAll('.', ',')} €   ·   '
                'TVA (${_tvaTaux.toString().replaceAll('.', ',')} %) : ${_tvaCalculee.toStringAsFixed(2).replaceAll('.', ',')} €   ·   '
                'HT : ${(_baseTtc - _tvaCalculee).toStringAsFixed(2).replaceAll('.', ',')} €',
                style: const TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
          ] else
            _numField('tva', 'Dont TVA (€)'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DropdownButtonFormField<String>(
              initialValue: _paiements.contains(_modePaiement) ? _modePaiement : null,
              decoration: InputDecoration(
                labelText: 'Mode de paiement', isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: _paiements.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => _modePaiement = v ?? ''),
            ),
          ),
          if (!widget.isCertificat)
            _field('montant_tranche2', 'Montant Tranche 2 — pénalité si non-stérilisation / repro (€)', kb: num),

          _section('Signature'),
          _field('ville_signature', 'Fait à (ville)'),
          _field('notes', 'Conditions particulières', lines: 3),

          if (!widget.isCertificat) ...[
            _section('Médiation (Article 8)'),
            _field('mediateur_nom', 'Médiateur'),
            _field('mediateur_url', 'Site / contact du médiateur'),
            _section('Articles à inclure'),
            for (final (key, label) in _kClauses)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: !_clausesOff.contains(key),
                title: Text(label, style: const TextStyle(fontSize: 12)),
                onChanged: (v) => setState(() {
                  if (v == true) { _clausesOff.remove(key); } else { _clausesOff.add(key); }
                }),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Visionneuse PDF plein écran avec pincer-zoom ────────────────────────────
// Rasterise chaque page en image puis l'affiche dans un PhotoViewGallery :
// pincer-zoom natif fiable (le zoom de `PdfPreview` demande un tap préalable
// que l'utilisatrice ne découvrait pas).
class _PdfZoomViewer extends StatefulWidget {
  final Uint8List bytes;
  final String titre;
  const _PdfZoomViewer({required this.bytes, required this.titre});

  @override
  State<_PdfZoomViewer> createState() => _PdfZoomViewerState();
}

class _PdfZoomViewerState extends State<_PdfZoomViewer> {
  final List<Uint8List> _pages = [];
  bool _loading = true;
  String? _error;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _raster();
  }

  Future<void> _raster() async {
    try {
      await for (final page in Printing.raster(widget.bytes, dpi: 200)) {
        final png = await page.toPng();
        if (!mounted) return;
        setState(() => _pages.add(png));
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEEF0),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white,
        title: Text(
          widget.titre,
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Partager',
            onPressed: () => Printing.sharePdf(bytes: widget.bytes, filename: 'contrat.pdf'),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Aperçu indisponible\n$_error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600)),
              ),
            )
          : _pages.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : Stack(
                  children: [
                    PhotoViewGallery.builder(
                      itemCount: _pages.length,
                      backgroundDecoration: const BoxDecoration(color: Color(0xFFECEEF0)),
                      scrollDirection: Axis.vertical,
                      onPageChanged: (i) => setState(() => _current = i),
                      builder: (context, i) => PhotoViewGalleryPageOptions(
                        imageProvider: MemoryImage(_pages[i]),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 4,
                        initialScale: PhotoViewComputedScale.contained,
                        heroAttributes: PhotoViewHeroAttributes(tag: 'pdf_page_$i'),
                      ),
                    ),
                    if (_pages.length > 1)
                      Positioned(
                        bottom: 16, left: 0, right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Page ${_current + 1} / ${_pages.length}'
                              '${_loading ? ' …' : ''}',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
