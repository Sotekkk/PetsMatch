import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/config.dart';
import 'package:http/http.dart' as http;
import 'package:PetsMatch/pages/pro/pension_journal_page.dart';
import 'dart:convert';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/services/chip_scanner_service.dart';
import 'package:PetsMatch/pages/pro/animal_fiche_pension_page.dart';
import 'package:PetsMatch/pages/pro/fiches_pension_page.dart';

class RegistrePensionPage extends StatefulWidget {
  const RegistrePensionPage({super.key});

  @override
  State<RegistrePensionPage> createState() => _RegistrePensionPageState();
}

class _RegistrePensionPageState extends State<RegistrePensionPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg    = Color(0xFFF8F8F6);

  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _entrees      = [];
  Map<String, String> _puceToAnimalId      = {}; // puce normalisée → animal_id
  Map<String, String> _puceToPhotoUrl      = {}; // puce normalisée → photo_url
  bool _loading                            = true;
  String? _filterEspece;
  String? _filterStatut;

  int get _activeFilters =>
      (_filterEspece != null ? 1 : 0) + (_filterStatut != null ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pid = User_Info.activeProfileId;
      var qEntrees = _supa.from('pension_entrees').select().eq('pro_uid', _uid);
      qEntrees = qEntrees.eq('pro_profile_id', pid);
      var qAcces = _supa.from('animal_access').select('animal_id').eq('pro_profile_id', pid).eq('statut', 'active');
      final results = await Future.wait([
        qEntrees.order('date_entree', ascending: false),
        qAcces,
      ]);

      final entrees  = List<Map<String, dynamic>>.from(results[0] as List);
      final approved = List<Map<String, dynamic>>.from(results[1] as List);
      final animalIds = approved.map((a) => a['animal_id'] as String).toList();

      // Charge les puces + photos des animaux approuvés pour le lien "Voir fiche"
      final Map<String, String> puceToId    = {};
      final Map<String, String> puceToPhoto = {};
      if (animalIds.isNotEmpty) {
        final animaux = await _supa
            .from('animaux')
            .select('id, identification, photo_url')
            .inFilter('id', animalIds);
        for (final a in animaux as List) {
          final puce = (a['identification'] ?? '').toString()
              .replaceAll(RegExp(r'[\s\-]'), '');
          if (puce.isNotEmpty) {
            puceToId[puce] = a['id'] as String;
            final photo = a['photo_url'] as String? ?? '';
            if (photo.isNotEmpty) puceToPhoto[puce] = photo;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _entrees        = entrees;
        _puceToAnimalId = puceToId;
        _puceToPhotoUrl = puceToPhoto;
        _loading        = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur chargement registre : $e'),
              duration: const Duration(seconds: 6)),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _entrees;
    if (_filterEspece != null) list = list.where((d) => d['espece'] == _filterEspece).toList();
    if (_filterStatut != null) list = list.where((d) => d['statut'] == _filterStatut).toList();
    return list;
  }

  // ── Saisie manuelle puce ──────────────────────────────────────────────────

  Future<void> _enterChipManually() async {
    final ctrl = TextEditingController();
    final chip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Saisir le numéro de puce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 15, letterSpacing: 1.2),
          decoration: InputDecoration(
            hintText: '250 269 810 000 000',
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _teal, width: 1.5)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Rechercher', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (chip == null || chip.trim().isEmpty || !mounted) return;
    await _processChip(chip.trim());
  }

  // ── Scan puce ──────────────────────────────────────────────────────────────

  Future<void> _scanChip() async {
    final chip = await ChipScannerService.showScanner(context);
    if (chip == null || chip.isEmpty || !mounted) return;
    await _processChip(chip);
  }

  Future<void> _processChip(String chip) async {
    final normalized = chip.replaceAll(RegExp(r'[\s\-]'), '');

    // 1. Déjà en pension → proposer sortie
    final inPension = _entrees.where((e) {
      final p = (e['puce'] ?? '').toString().replaceAll(RegExp(r'[\s\-]'), '');
      return p == normalized && e['statut'] == 'en_pension';
    }).toList();

    if (inPension.isNotEmpty) {
      final entree = inPension.first;
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('${entree['animal_nom'] ?? 'Cet animal'} est en pension',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          content: const Text('Voulez-vous enregistrer sa sortie ?',
              style: TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Marquer sorti', style: TextStyle(fontFamily: 'Galey')),
            ),
          ],
        ),
      );
      if (confirm == true) await _marquerSorti(entree);
      return;
    }

    // 2. Recherche dans la base + infos proprio si accès approuvé
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: _teal)),
    );

    final prefill = await _lookupAnimalByChip(chip);

    if (!mounted) return;
    Navigator.pop(context); // ferme le loader

    // 3. Ouvre directement le formulaire d'admission (pré-rempli)
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PensionEntreeSheet(
        initialNom:                 prefill['nom'] as String?,
        initialEspece:              prefill['espece'] as String?,
        initialRace:                prefill['race'] as String?,
        initialPuce:                prefill['puce'] as String? ?? chip,
        initialPhotoUrl:            prefill['photoUrl'] as String?,
        initialAnimalId:            prefill['animalId'] as String?,
        initialOwnerUid:            prefill['ownerUid'] as String?,
        initialProprietaireNom:     prefill['proprietaireNom'] as String?,
        initialProprietaireContact: prefill['proprietaireContact'] as String?,
        initialProprietaireEmail:   prefill['proprietaireEmail'] as String?,
        initialProprietaireAdresse: prefill['proprietaireAdresse'] as String?,
      ),
    );
    if (added == true && mounted) _load();
  }

  // ── Marquer sorti ──────────────────────────────────────────────────────────

  Future<void> _marquerSorti(Map<String, dynamic> entree) async {
    final now     = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    await _supa.from('pension_entrees').update({
      'statut': 'sorti',
      'date_sortie_effective': dateStr,
    }).eq('id', entree['id']);

    // Proposer de révoquer l'accès lecture
    final puce     = (entree['puce'] ?? '').toString().replaceAll(RegExp(r'[\s\-]'), '');
    final animalId = _puceToAnimalId[puce];
    if (animalId != null && mounted) {
      final revoke = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Révoquer l\'accès ?',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: Text(
            'Souhaitez-vous retirer l\'accès à la fiche de ${entree['animal_nom'] ?? 'cet animal'} ?',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Conserver', style: TextStyle(fontFamily: 'Galey'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Révoquer', style: TextStyle(fontFamily: 'Galey',
                  color: Colors.white)),
            ),
          ],
        ),
      );
      if (revoke == true && mounted) {
        final pid = User_Info.activeProfileId;
        await _supa.from('animal_access')
            .update({'statut': 'revoked', 'revoked_at': DateTime.now().toUtc().toIso8601String()})
            .eq('pro_profile_id', pid)
            .eq('animal_id', animalId);
      }
    }
    await _load();
  }

  // ── Clause spécifique par espèce ──────────────────────────────────────────

  String? _clauseSpecifique(String espece) {
    switch (espece.toLowerCase()) {
      case 'chien':
        return 'Le chien bénéficie de sorties quotidiennes adaptées à son niveau d\'activité et à son état de santé. '
               'Il est hébergé dans un espace sécurisé et ne peut être laissé sans surveillance dans les espaces collectifs. '
               'Le propriétaire fournit à l\'admission le carnet de vaccination à jour (rage obligatoire) ainsi que le certificat de primo-vaccination si l\'animal est jeune.';
      case 'chat':
        return 'Le chat est hébergé dans un espace dédié exclusivement aux félins afin de minimiser le stress. '
               'Il dispose d\'un espace privatif (cage ou box) avec griffoir, litière et cachette. '
               'L\'accès à un espace de socialisation est possible selon le tempérament de l\'animal. '
               'Le propriétaire fournit le carnet de vaccination à jour (typhus, coryza, leucose recommandée).';
      case 'cheval':
      case 'poney':
        return 'Le propriétaire certifie que l\'équidé est à jour de ferrure et de vermifugation. '
               'Une assurance équine (responsabilité civile et mortalité) est obligatoire et une attestation doit être fournie à l\'admission. '
               'Les frais de maréchal-ferrant, vétérinaire et dentiste restent à la charge exclusive du propriétaire. '
               'La pension assure le pâturage/box, le foin et l\'eau. Les concentrés et compléments sont à fournir par le propriétaire.';
      case 'lapin':
      case 'nac':
        return 'Les NAC et lapins nécessitent une alimentation spécifique. Le propriétaire est invité à fournir les aliments habituels '
               '(foin, légumes, granulés) ainsi que tout complément prescrit. '
               'La pension assure une température ambiante adaptée et un hébergement protégé de toute source de stress (prédateurs, bruits intenses). '
               'Tout traitement en cours doit être signalé et le médicament fourni avec le protocole vétérinaire.';
      case 'oiseau':
        return 'La cage, les perchoirs et les accessoires habituels de l\'animal sont fournis par le propriétaire. '
               'Le régime alimentaire (graines, fruits, légumes, granulés) doit être précisé à l\'admission. '
               'La pension assure une température ambiante stable et un ensoleillement suffisant. '
               'Les oiseaux exotiques doivent être accompagnés des documents CITES si requis.';
      default:
        return null;
    }
  }

  // ── Générer contrat PDF ───────────────────────────────────────────────────

  Future<void> _envoyerLienReclamation(Map<String, dynamic> e, String animalId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final email = (e['proprietaire_email'] as String?)?.trim();
    if (uid == null || email == null || email.isEmpty) return;
    try {
      final row = await _supa.from('animal_claims').insert({
        'animal_id': animalId,
        'created_by_uid': uid,
        'email_destinataire': email,
        'nom_destinataire': e['proprietaire_nom'],
        'tel_destinataire': e['proprietaire_contact'],
      }).select('token').single();
      final token = row['token'] as String?;
      if (token == null) return;
      final claimUrl = '$kSiteBaseUrl/reclamer-animal/$token';
      await http.post(
        Uri.parse('$kSiteBaseUrl/api/animal-claim/notify-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'nom_destinataire': e['proprietaire_nom'],
          'animal_nom': e['animal_nom'],
          'pro_nom': User_Info.nameElevage.isNotEmpty
              ? User_Info.nameElevage : '${User_Info.firstname} ${User_Info.lastname}'.trim(),
          'claim_url': claimUrl,
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Lien de réclamation envoyé par email', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: const Color(0xFF6E9E57),
        ));
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $err')));
      }
    }
  }

  Future<void> _genererContratSignature(Map<String, dynamic> e) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      // Réutilise un contrat existant pour ce séjour si déjà créé.
      final existing = await _supa
          .from('documents_animaux')
          .select('token')
          .eq('pension_entree_id', e['id'])
          .eq('type', 'contrat_hebergement')
          .maybeSingle();

      String? token = existing?['token'] as String?;
      if (token == null) {
        final row = await _supa.from('documents_animaux').insert({
          'uid_eleveur': uid,
          'pension_entree_id': e['id'],
          'type': 'contrat_hebergement',
          'titre': 'Contrat d\'hébergement — ${e['animal_nom'] ?? ''}',
          'statut': 'en_attente',
          'metadata': {
            'logement_nom': null,
          },
        }).select('token').single();
        token = row['token'] as String?;
      } else {
        await _supa.from('documents_animaux')
            .update({'statut': 'en_attente'})
            .eq('pension_entree_id', e['id'])
            .eq('type', 'contrat_hebergement');
      }
      if (token == null) return;
      final url = '$kSiteBaseUrl/signer-contrat/$token';
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Lien de signature copié — envoyez-le au propriétaire',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _teal,
        ));
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e2')));
      }
    }
  }

  Future<void> _genererContrat(Map<String, dynamic> e) async {
    final pdf      = pw.Document();
    final font     = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fmt      = DateFormat('dd/MM/yyyy');
    final logo     = pw.MemoryImage(
        (await rootBundle.load('assets/Logo_petsmatch_fond_blanc.png'))
            .buffer.asUint8List());

    final pensionNom = User_Info.nameElevage.isNotEmpty
        ? User_Info.nameElevage
        : '${User_Info.firstname} ${User_Info.lastname}'.trim();

    String fmtIso(String? iso) {
      if (iso == null || iso.isEmpty) return '—';
      final dt = DateTime.tryParse(iso);
      return dt != null ? fmt.format(dt) : '—';
    }

    pw.Widget _section(String title, List<List<String>> rows) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0C5C6C)),
          child: pw.Text(title,
              style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.white)),
        ),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Column(children: rows.map((row) => pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.3)),
            ),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: pw.Row(children: [
              pw.SizedBox(width: 120,
                  child: pw.Text(row[0], style: pw.TextStyle(font: fontBold, fontSize: 8,
                      color: PdfColors.grey700))),
              pw.Expanded(child: pw.Text(row[1],
                  style: pw.TextStyle(font: font, fontSize: 8))),
            ]),
          )).toList()),
        ),
        pw.SizedBox(height: 14),
      ],
    );

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        // En-tête
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Image(logo, width: 40, height: 40),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('CONTRAT DE PENSION',
                style: pw.TextStyle(font: fontBold, fontSize: 14, color: const PdfColor.fromInt(0xFF0C5C6C))),
            pw.Text(pensionNom,
                style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey700)),
            pw.Text('Date : ${fmt.format(DateTime.now())}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
          ]),
        ]),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF0C5C6C)),
        pw.SizedBox(height: 16),

        // Animal
        _section('ANIMAL', [
          ['Nom', e['animal_nom']?.toString() ?? '—'],
          ['Espèce', _espLabel(e['espece']?.toString() ?? '')],
          ['Race', e['race']?.toString().isNotEmpty == true ? e['race'] : '—'],
          ['N° de puce', e['puce']?.toString().isNotEmpty == true ? e['puce'] : '—'],
        ]),

        // Propriétaire
        _section('PROPRIÉTAIRE / CLIENT', [
          ['Nom', e['proprietaire_nom']?.toString().isNotEmpty == true ? e['proprietaire_nom'] : '—'],
          ['Téléphone', e['proprietaire_contact']?.toString().isNotEmpty == true ? e['proprietaire_contact'] : '—'],
          ['Email', e['proprietaire_email']?.toString().isNotEmpty == true ? e['proprietaire_email'] : '—'],
        ]),

        // Séjour
        _section('SÉJOUR', [
          ['Date d\'entrée', fmtIso(e['date_entree'] as String?)],
          ['Sortie prévue', fmtIso(e['date_sortie_prevue'] as String?)],
          ['Statut', e['statut'] == 'en_pension' ? 'En pension' : 'Sorti(e)'],
        ]),

        // Notes
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0C5C6C)),
            child: pw.Text('NOTES / CONDITIONS PARTICULIÈRES',
                style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.white)),
          ),
          pw.Container(
            width: double.infinity,
            height: 60,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            ),
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text(
              e['notes']?.toString().isNotEmpty == true ? e['notes'] : ' ',
              style: pw.TextStyle(font: font, fontSize: 8),
            ),
          ),
        ]),
        pw.SizedBox(height: 24),

        // Signatures
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Signature du propriétaire',
                style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text('(précédée de « Lu et approuvé »)',
                style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey500)),
            pw.SizedBox(height: 40),
            pw.Container(width: 180, height: 0.5, color: PdfColors.grey400),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Signature de la pension',
                style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 44),
            pw.Container(width: 180, height: 0.5, color: PdfColors.grey400),
          ]),
        ]),

        pw.Spacer(),
        pw.Divider(thickness: 0.3, color: PdfColors.grey300),
        pw.Center(child: pw.Text('Document généré via PetsMatch · petsmatchapp.com',
            style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400))),
      ]),
    ));

    // ── Page 2 : Conditions générales ────────────────────────────────────
    final espece = e['espece']?.toString() ?? '';

    final clauseSpecifique = _clauseSpecifique(espece);

    final articles = [
      ('Art. 1 – Conditions d\'admission',
       'L\'animal est admis sous réserve d\'être à jour de ses vaccinations obligatoires et traitements antiparasitaires. '
       'Le propriétaire s\'engage à fournir tout document sanitaire demandé par la pension à l\'admission. '
       'En cas de maladie contagieuse déclarée, la pension se réserve le droit de refuser l\'accueil.'),
      ('Art. 2 – Soins vétérinaires d\'urgence',
       'En cas d\'urgence médicale, la pension est autorisée à faire appel au vétérinaire de garde sans délai. '
       'Les frais vétérinaires engagés sont intégralement à la charge du propriétaire et feront l\'objet d\'une facturation. '
       'Le propriétaire sera contacté dès que possible.'),
      ('Art. 3 – Responsabilité civile',
       'La pension est couverte par une assurance responsabilité civile professionnelle. '
       'Le propriétaire demeure seul responsable des dommages causés par son animal à des tiers, à d\'autres animaux ou aux installations de la pension. '
       'Une attestation d\'assurance responsabilité civile peut être demandée.'),
      ('Art. 4 – Comportement & sécurité',
       'Le propriétaire certifie que l\'animal est sociable et ne présente pas de comportement agressif connu. '
       'Tout antécédent de morsure, d\'attaque ou de comportement dangereux doit être déclaré à l\'admission. '
       'La pension se réserve le droit de mettre fin au séjour en cas de danger avéré pour les autres animaux ou le personnel.'),
      ('Art. 5 – Alimentation',
       'L\'alimentation standard est assurée par la pension. Tout régime spécifique (pathologie, allergie, prescription vétérinaire) '
       'doit être signalé à l\'admission et accompagné des aliments nécessaires fournis par le propriétaire. '
       'La pension décline toute responsabilité en cas d\'information incomplète sur le régime de l\'animal.'),
      ('Art. 6 – Modalités financières',
       'Un acompte de 30 % du montant total peut être exigé à la réservation pour confirmer le séjour. '
       'Le solde est dû à l\'admission. En cas d\'annulation moins de 48 h avant la date d\'entrée, l\'acompte est conservé. '
       'Tout séjour commencé est dû dans son intégralité.'),
      ('Art. 7 – Prolongation & sortie',
       'Toute prolongation de séjour doit être signalée au préalable et fera l\'objet d\'une facturation complémentaire. '
       'L\'animal non récupéré dans les 72 h suivant la date de sortie prévue, sans contact du propriétaire, '
       'pourra être confié à la SPA ou à une autorité compétente aux frais du propriétaire.'),
      ('Art. 8 – Force majeure & responsabilité médicale',
       'La pension ne peut être tenue responsable du décès ou de la maladie d\'un animal survenant malgré les soins appropriés, '
       'ni en cas de force majeure (épizootie, catastrophe naturelle, panne de courant…). '
       'La pension s\'engage à mettre tout en œuvre pour assurer le bien-être et la sécurité de l\'animal confié.'),
      if (clauseSpecifique != null) ('Art. 9 – Disposition spécifique (${_espLabel(espece)})', clauseSpecifique),
    ];

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('CONDITIONS GÉNÉRALES DE PENSION',
              style: pw.TextStyle(font: fontBold, fontSize: 10, color: const PdfColor.fromInt(0xFF0C5C6C))),
          pw.Text(pensionNom,
              style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
        ]),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.5, color: const PdfColor.fromInt(0xFF0C5C6C)),
        pw.SizedBox(height: 8),
      ]),
      footer: (_) => pw.Column(children: [
        pw.Divider(thickness: 0.3, color: PdfColors.grey300),
        pw.Center(child: pw.Text('Document généré via PetsMatch · petsmatchapp.com',
            style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400))),
      ]),
      build: (_) => [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: articles.map((art) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(art.$1,
                  style: pw.TextStyle(font: fontBold, fontSize: 8,
                      color: const PdfColor.fromInt(0xFF0C5C6C))),
              pw.SizedBox(height: 3),
              pw.Text(art.$2,
                  style: pw.TextStyle(font: font, fontSize: 7.5,
                      color: PdfColors.grey800, lineSpacing: 1.5)),
            ]),
          )).toList(),
        ),
      ],
    ));

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  // ── Supprimer entrée ──────────────────────────────────────────────────────

  Future<void> _supprimerEntree(Map<String, dynamic> entree) async {
    final nom = entree['animal_nom']?.toString() ?? 'cet animal';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer cette entrée ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          'L\'entrée de $nom sera définitivement supprimée du registre.',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _supa.from('pension_entrees').delete().eq('id', entree['id']);
      await _load();
    }
  }

  // ── Filtre ─────────────────────────────────────────────────────────────────

  Future<void> _openFilter() async {
    final especes = _entrees
        .map((e) => e['espece'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();

    String? tmpEspece = _filterEspece;
    String? tmpStatut = _filterStatut;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Filtrer',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
              const Spacer(),
              if (tmpEspece != null || tmpStatut != null)
                TextButton(
                  onPressed: () {
                    setSheet(() { tmpEspece = null; tmpStatut = null; });
                    setState(() { _filterEspece = null; _filterStatut = null; });
                  },
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text('Réinitialiser',
                      style: TextStyle(fontFamily: 'Galey', color: _green)),
                ),
            ]),
            const SizedBox(height: 16),
            const Text('Espèce', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6F767B))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _filterChip('Toutes', null, tmpEspece, (v) {
                setSheet(() => tmpEspece = v);
                setState(() => _filterEspece = v);
              }),
              for (final e in especes)
                _filterChip(_espLabel(e), e, tmpEspece, (v) {
                  setSheet(() => tmpEspece = v);
                  setState(() => _filterEspece = v);
                }),
            ]),
            const SizedBox(height: 18),
            const Text('Statut', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6F767B))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _filterChip('Tous', null, tmpStatut, (v) {
                setSheet(() => tmpStatut = v);
                setState(() => _filterStatut = v);
              }),
              _filterChip('En pension', 'en_pension', tmpStatut, (v) {
                setSheet(() => tmpStatut = v);
                setState(() => _filterStatut = v);
              }),
              _filterChip('Sortis', 'sorti', tmpStatut, (v) {
                setSheet(() => tmpStatut = v);
                setState(() => _filterStatut = v);
              }),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String? value, String? current,
      void Function(String?) onTap) {
    final sel = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? _teal.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(color: sel ? _teal : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
            color: sel ? _teal : Colors.black87,
            fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  // ── Export PDF ─────────────────────────────────────────────────────────────

  Future<void> _exportPdf(List<Map<String, dynamic>> docs) async {
    final pdf     = pw.Document();
    final font    = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fmt     = DateFormat('dd/MM/yyyy');
    final logo    = pw.MemoryImage(
        (await rootBundle.load('assets/Logo_petsmatch_fond_blanc.png'))
            .buffer.asUint8List());

    final headers = [
      'Nom', 'Espèce', 'Race', 'Puce', 'Client', 'Contact',
      'Date entrée', 'Sortie prévue', 'Sortie effective', 'Statut', 'Notes',
    ];

    String fmtIso(Map d, String key) {
      final iso = d[key] as String?;
      if (iso == null || iso.isEmpty) return '—';
      final dt = DateTime.tryParse(iso);
      return dt != null ? fmt.format(dt) : '—';
    }

    final rows = docs.map((d) => [
      d['animal_nom'] ?? '—',
      _espLabel(d['espece'] ?? ''),
      d['race']?.toString().isNotEmpty == true ? d['race'] : '—',
      d['puce']?.toString().isNotEmpty == true ? d['puce'] : '—',
      d['proprietaire_nom']?.toString().isNotEmpty == true ? d['proprietaire_nom'] : '—',
      d['proprietaire_contact']?.toString().isNotEmpty == true ? d['proprietaire_contact'] : '—',
      fmtIso(d, 'date_entree'),
      fmtIso(d, 'date_sortie_prevue'),
      fmtIso(d, 'date_sortie_effective'),
      d['statut'] == 'en_pension' ? 'En pension' : 'Sorti',
      d['notes']?.toString().isNotEmpty == true ? d['notes'] : '—',
    ]).toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Image(logo, width: 32, height: 32),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('REGISTRE PENSION — ENTRÉES & SORTIES',
                style: pw.TextStyle(font: fontBold, fontSize: 11)),
            pw.Text('Édité le ${fmt.format(DateTime.now())}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
          ]),
        ]),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 4),
      ]),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0C5C6C)),
          cellStyle: pw.TextStyle(font: font, fontSize: 6.5),
          cellAlignments: {for (var i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft},
          rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          columnWidths: {
            0:  const pw.FlexColumnWidth(1.2),
            1:  const pw.FlexColumnWidth(0.8),
            2:  const pw.FlexColumnWidth(0.9),
            3:  const pw.FlexColumnWidth(1.0),
            4:  const pw.FlexColumnWidth(1.3),
            5:  const pw.FlexColumnWidth(1.1),
            6:  const pw.FlexColumnWidth(0.8),
            7:  const pw.FlexColumnWidth(0.8),
            8:  const pw.FlexColumnWidth(0.8),
            9:  const pw.FlexColumnWidth(0.7),
            10: const pw.FlexColumnWidth(1.5),
          },
        ),
      ],
    ));

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Registre pension',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sensors_rounded),
            tooltip: 'Scanner une puce',
            onPressed: _scanChip,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_outlined),
            tooltip: 'Saisir la puce manuellement',
            onPressed: _enterChipManually,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exporter PDF',
            onPressed: _entrees.isEmpty ? null : () => _exportPdf(filtered.isEmpty ? _entrees : filtered),
          ),
          Stack(alignment: Alignment.topRight, children: [
            IconButton(
              icon: const Icon(Icons.tune_outlined),
              onPressed: _openFilter,
            ),
            if (_activeFilters > 0)
              Positioned(top: 8, right: 8, child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(color: _green, shape: BoxShape.circle,
                    border: Border.all(color: _teal, width: 1.5)),
                child: Center(child: Text('$_activeFilters',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 9,
                        fontWeight: FontWeight.w700, color: Colors.white))),
              )),
          ]),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _teal,
        onPressed: _openAjout,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : filtered.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _teal,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e    = filtered[i];
                      final puce = (e['puce'] ?? '').toString().replaceAll(RegExp(r'[\s\-]'), '');
                      final animalId = (e['animal_id'] as String?) ?? _puceToAnimalId[puce];
                      return _PensionCard(
                        entree: e,
                        animalId: animalId,
                        photoUrl: _puceToPhotoUrl[puce],
                        onTap: () => _openEdit(e),
                        onLongPress: () => _supprimerEntree(e),
                        onContrat: () => _genererContrat(e),
                        onSignature: () => _genererContratSignature(e),
                        onEnvoyerLien: (animalId != null && (e['proprietaire_email']?.toString().isNotEmpty ?? false))
                            ? () => _envoyerLienReclamation(e, animalId)
                            : null,
                        onJournal: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => PensionJournalPage(
                            animalId: animalId,
                            pensionEntreeId: e['id'] as String?,
                            animalNom: e['animal_nom']?.toString() ?? 'Animal',
                          ),
                        )),
                        onFicheTap: animalId != null ? () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AnimalFichePensionPage(
                            animalId: animalId,
                            animalNom: e['animal_nom'] as String?,
                          ),
                        )) : null,
                        onSorti: e['statut'] == 'en_pension'
                            ? () => _marquerSorti(e)
                            : null,
                        onFacture: e['statut'] != 'en_pension'
                            ? () => _genererFacture(e)
                            : null,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.pets, size: 56, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      const Text('Aucun animal dans le registre',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
              fontSize: 15, color: Color(0xFF1F2A2E))),
      const SizedBox(height: 4),
      Text('Scannez une puce ou ajoutez manuellement\nvia le bouton +',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
    ]),
  );

  Future<void> _genererFacture(Map<String, dynamic> entree) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FacturationSheet(entree: entree),
    );
  }

  Future<void> _openAjout() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PensionEntreeSheet(),
    );
    if (added == true) _load();
  }

  Future<void> _openEdit(Map<String, dynamic> entree) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PensionEditSheet(entree: entree, supa: _supa),
    );
    _load();
  }
}

// ── Carte registre ─────────────────────────────────────────────────────────────

class _PensionCard extends StatelessWidget {
  final Map<String, dynamic> entree;
  final String? animalId;
  final String? photoUrl;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFicheTap;
  final VoidCallback? onSorti;
  final VoidCallback? onContrat;
  final VoidCallback? onSignature;
  final VoidCallback? onFacture;
  final VoidCallback? onEnvoyerLien;
  final VoidCallback? onJournal;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _purple = Color(0xFF7B5EA7);

  const _PensionCard({
    required this.entree,
    required this.onTap,
    this.animalId,
    this.photoUrl,
    this.onLongPress,
    this.onFicheTap,
    this.onSorti,
    this.onContrat,
    this.onSignature,
    this.onFacture,
    this.onEnvoyerLien,
    this.onJournal,
  });

  @override
  Widget build(BuildContext context) {
    final nom          = entree['animal_nom']?.toString() ?? '—';
    final espece       = entree['espece']?.toString() ?? '';
    final race         = entree['race']?.toString() ?? '';
    final puce         = entree['puce']?.toString() ?? '';
    final client       = entree['proprietaire_nom']?.toString() ?? '';
    final contact      = entree['proprietaire_contact']?.toString() ?? '';
    final inPension    = entree['statut'] == 'en_pension';
    // Photo stockée à l'admission, sinon photo live depuis pension_acces
    final effectivePhotoUrl = (entree['photo_url'] as String?)?.isNotEmpty == true
        ? entree['photo_url'] as String : photoUrl;
    final fmt          = DateFormat('dd/MM/yyyy');

    String fmtIso(String? iso) {
      if (iso == null || iso.isEmpty) return '—';
      final dt = DateTime.tryParse(iso);
      return dt != null ? fmt.format(dt) : '—';
    }

    final bgColor = inPension ? const Color(0xFFE8F5E9) : const Color(0xFFE3F2FD);
    final statusColor = inPension ? _green : _teal;
    final statusLabel = inPension ? 'En pension' : 'Sorti';
    final statusIcon  = inPension ? Icons.home_outlined : Icons.logout_outlined;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Photo ou icône espèce
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: effectivePhotoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: effectivePhotoUrl,
                        width: 52, height: 52,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 52, height: 52,
                          color: bgColor,
                          child: Center(child: _speciesIcon(espece, 22, statusColor)),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 52, height: 52,
                          color: bgColor,
                          child: Center(child: _speciesIcon(espece, 22, statusColor)),
                        ),
                      )
                    : Container(
                        width: 52, height: 52,
                        color: bgColor,
                        child: Center(child: _speciesIcon(espece, 22, statusColor)),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Ligne 1: nom + badge statut
                Row(children: [
                  Expanded(child: Text(nom,
                      style: const TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(statusIcon, size: 10, color: statusColor),
                      const SizedBox(width: 3),
                      Text(statusLabel,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                              fontWeight: FontWeight.w600, color: statusColor)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 3),
                // Espèce + race + puce
                Text(
                  [_espLabel(espece), if (race.isNotEmpty) race, if (puce.isNotEmpty) 'Puce $puce']
                      .where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 4),
                // Client
                if (client.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.person_outline, size: 11, color: Color(0xFF6F767B)),
                    const SizedBox(width: 3),
                    Expanded(child: Text(
                      [client, if (contact.isNotEmpty) contact].join(' · '),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                          color: Color(0xFF6F767B)),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                const SizedBox(height: 3),
                // Dates
                Row(children: [
                  _dateChip(Icons.login_outlined, 'Entrée',
                      fmtIso(entree['date_entree'] as String?)),
                  if (inPension && entree['date_sortie_prevue'] != null &&
                      entree['date_sortie_prevue'].toString().isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _dateChip(Icons.event_outlined, 'Prévue',
                        fmtIso(entree['date_sortie_prevue'] as String?)),
                  ],
                  if (!inPension && entree['date_sortie_effective'] != null &&
                      entree['date_sortie_effective'].toString().isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _dateChip(Icons.logout_outlined, 'Sorti le',
                        fmtIso(entree['date_sortie_effective'] as String?)),
                  ],
                ]),
                // Boutons d'action
                if (onSorti != null || onContrat != null || onSignature != null || onFacture != null || onEnvoyerLien != null || onJournal != null) ...[
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                    if (onJournal != null)
                      OutlinedButton.icon(
                        onPressed: onJournal,
                        icon: const Icon(Icons.photo_camera_back_outlined, size: 14),
                        label: const Text('Journal',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _green,
                          side: const BorderSide(color: _green),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    if (onContrat != null)
                      OutlinedButton.icon(
                        onPressed: onContrat,
                        icon: const Icon(Icons.description_outlined, size: 14),
                        label: const Text('Contrat',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7B5EA7),
                          side: const BorderSide(color: Color(0xFF7B5EA7)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    if (onSignature != null)
                      OutlinedButton.icon(
                        onPressed: onSignature,
                        icon: const Icon(Icons.draw_outlined, size: 14),
                        label: const Text('Signature en ligne',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0C5C6C),
                          side: const BorderSide(color: Color(0xFF0C5C6C)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    if (onEnvoyerLien != null)
                      OutlinedButton.icon(
                        onPressed: onEnvoyerLien,
                        icon: const Icon(Icons.link_rounded, size: 14),
                        label: const Text('Lien de réclamation',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _purple,
                          side: const BorderSide(color: _purple),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    if (onFacture != null)
                      OutlinedButton.icon(
                        onPressed: onFacture,
                        icon: const Icon(Icons.receipt_long_outlined, size: 14),
                        label: const Text('Facturer',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _teal,
                          side: const BorderSide(color: _teal),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    if (onSorti != null)
                      OutlinedButton.icon(
                        onPressed: onSorti,
                        icon: const Icon(Icons.logout_rounded, size: 14),
                        label: const Text('Marquer sorti',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _teal,
                          side: const BorderSide(color: _teal),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ]),
                ],
              ])),
              // Bouton voir fiche (si accès approuvé)
              if (onFicheTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    icon: const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF7B5EA7)),
                    onPressed: onFicheTap,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Voir la fiche',
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  static Widget _dateChip(IconData icon, String label, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 10, color: const Color(0xFF6F767B)),
      const SizedBox(width: 3),
      Text('$label : $value',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF6F767B))),
    ],
  );
}

Widget _speciesIcon(String espece, double size, Color color) {
  const emojis = {
    'chien': '🐕', 'chat': '🐈', 'lapin': '🐇',
    'oiseau': '🦜', 'cheval': '🐴', 'nac': '🐹',
    'ovin': '🐑', 'caprin': '🐐', 'porcin': '🐷',
  };
  final emoji = emojis[espece];
  if (emoji != null) {
    return Text(emoji, style: TextStyle(fontSize: size));
  }
  return Icon(Icons.pets, size: size, color: color);
}

String _espLabel(String e) {
  const m = {
    'chien': 'Chien', 'chat': 'Chat', 'cheval': 'Cheval', 'lapin': 'Lapin',
    'ovin': 'Ovin', 'caprin': 'Caprin', 'porcin': 'Porcin', 'nac': 'NAC',
    'oiseau': 'Oiseau', 'autre': 'Autre',
  };
  return m[e] ?? e;
}

// ── Sheet édition entrée ───────────────────────────────────────────────────────

class PensionEditSheet extends StatefulWidget {
  final Map<String, dynamic> entree;
  final SupabaseClient supa;
  const PensionEditSheet({required this.entree, required this.supa});

  @override
  State<PensionEditSheet> createState() => PensionEditSheetState();
}

class PensionEditSheetState extends State<PensionEditSheet> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  late String  _statut;
  DateTime?    _dateEntree;
  DateTime?    _dateSortiePrevue;
  DateTime?    _dateSortieEff;
  late final TextEditingController _especeCtrl;
  late final TextEditingController _raceCtrl;
  late final TextEditingController _clientCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;
  bool _linkingFiche = false;
  late bool _seul;
  String? _animalId;
  String? _accessStatus; // null = pas de demande, 'pending' | 'active' | 'refused'
  bool _checkingAccess = false;
  final _fmt   = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    final d = widget.entree;
    _statut           = d['statut'] as String? ?? 'en_pension';
    _dateEntree       = DateTime.tryParse(d['date_entree'] as String? ?? '');
    _dateSortiePrevue = DateTime.tryParse(d['date_sortie_prevue'] as String? ?? '');
    _dateSortieEff    = DateTime.tryParse(d['date_sortie_effective'] as String? ?? '');
    _especeCtrl  = TextEditingController(text: d['espece'] as String? ?? '');
    _raceCtrl    = TextEditingController(text: d['race'] as String? ?? '');
    _clientCtrl  = TextEditingController(text: d['proprietaire_nom'] as String? ?? '');
    _contactCtrl = TextEditingController(text: d['proprietaire_contact'] as String? ?? '');
    _emailCtrl   = TextEditingController(text: d['proprietaire_email'] as String? ?? '');
    _notesCtrl   = TextEditingController(text: d['notes'] as String? ?? '');
    _seul        = d['seul_dans_logement'] as bool? ?? false;
    _animalId    = d['animal_id'] as String?;
    if (_animalId != null) _checkAccessStatus();
  }

  Future<void> _checkAccessStatus() async {
    setState(() => _checkingAccess = true);
    try {
      final pid = User_Info.activeProfileId;
      final row = await widget.supa.from('animal_access')
          .select('statut').eq('pro_profile_id', pid).eq('animal_id', _animalId!).maybeSingle();
      if (mounted) setState(() => _accessStatus = row?['statut'] as String?);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _checkingAccess = false);
    }
  }

  Future<void> _demanderAcces() async {
    if (_animalId == null) return;
    setState(() => _checkingAccess = true);
    try {
      final propRow = await widget.supa.from('animaux_proprietes')
          .select('uid_proprio').eq('animal_id', _animalId!)
          .filter('date_fin', 'is', null).order('date_debut', ascending: false)
          .limit(1).maybeSingle();
      final ownerUid = propRow?['uid_proprio'] as String?;
      if (ownerUid == null || ownerUid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Propriétaire introuvable pour cet animal.', style: TextStyle(fontFamily: 'Galey'))));
        }
        return;
      }
      await _requestAccessTo(_animalId!, ownerUid);
      if (mounted) {
        setState(() => _accessStatus = 'pending');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Demande d\'accès envoyée au propriétaire', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _green,
        ));
      }
    } finally {
      if (mounted) setState(() => _checkingAccess = false);
    }
  }

  Future<void> _linkFiche() async {
    final prefill = await pickAnimalForAdmission(context, allowSkip: false);
    if (prefill == null || !mounted) return;
    final animalId = prefill['animalId'] as String?;
    if (animalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun animal trouvé avec cette puce.', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _linkingFiche = true);
    try {
      await widget.supa.from('pension_entrees').update({'animal_id': animalId}).eq('id', widget.entree['id']);
      final ownerUid = prefill['ownerUid'] as String?;
      if (ownerUid != null && ownerUid.isNotEmpty) {
        await _requestAccessTo(animalId, ownerUid);
      }
      if (mounted) {
        setState(() {
          _animalId = animalId;
          _accessStatus = (ownerUid != null && ownerUid.isNotEmpty) ? 'pending' : null;
          if ((prefill['proprietaireNom'] as String?)?.isNotEmpty ?? false) _clientCtrl.text = prefill['proprietaireNom'] as String;
          if ((prefill['proprietaireContact'] as String?)?.isNotEmpty ?? false) _contactCtrl.text = prefill['proprietaireContact'] as String;
          if ((prefill['proprietaireEmail'] as String?)?.isNotEmpty ?? false) _emailCtrl.text = prefill['proprietaireEmail'] as String;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fiche rattachée — demande d\'accès envoyée au propriétaire', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _green,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _linkingFiche = false);
    }
  }

  Future<void> _requestAccessTo(String animalId, String ownerUid) async {
    try {
      final pid = User_Info.activeProfileId;
      final ownerProfile = await widget.supa.from('user_profiles')
          .select('id').eq('uid', ownerUid).eq('is_main', true).maybeSingle();
      final ownerProfileId = ownerProfile?['id'] as String?;
      if (pid.isEmpty || ownerProfileId == null) return;
      final existing = await widget.supa.from('animal_access')
          .select('id').eq('pro_profile_id', pid).eq('animal_id', animalId).maybeSingle();
      if (existing != null) return;
      final pensionNom = User_Info.nameElevage.isNotEmpty
          ? User_Info.nameElevage : '${User_Info.firstname} ${User_Info.lastname}'.trim();
      await widget.supa.from('animal_access').insert({
        'pro_profile_id': pid, 'animal_id': animalId,
        'granted_by_profile_id': ownerProfileId,
        'permissions': ['read_basic', 'read_alimentation', 'write_notes'],
        'statut': 'pending',
      });
      await widget.supa.from('notifications').insert({
        'uid': ownerUid, 'type': 'pension_acces',
        'title': 'Demande d\'accès à la fiche de ${_clientCtrl.text.isEmpty ? "votre animal" : widget.entree['animal_nom']}',
        'body': '$pensionNom souhaite consulter la fiche en pension (lecture seule).',
        'data': {'pensionUid': FirebaseAuth.instance.currentUser?.uid, 'pensionNom': pensionNom, 'animalId': animalId},
        'read': false,
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _especeCtrl.dispose();
    _raceCtrl.dispose();
    _clientCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime> cb,
      {bool allowFuture = false}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: allowFuture
          ? DateTime.now().add(const Duration(days: 365))
          : DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.light()
            .copyWith(colorScheme: const ColorScheme.light(primary: _teal)),
        child: child!,
      ),
    );
    if (d != null) setState(() => cb(d));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.supa.from('pension_entrees').update({
        'statut':                _statut,
        'espece':                _especeCtrl.text.trim().toLowerCase(),
        'race':                  _raceCtrl.text.trim(),
        'proprietaire_nom':      _clientCtrl.text.trim(),
        'proprietaire_contact':  _contactCtrl.text.trim(),
        'proprietaire_email':    _emailCtrl.text.trim(),
        'notes':                 _notesCtrl.text.trim(),
        'date_entree':           _dateEntree != null
            ? DateFormat('yyyy-MM-dd').format(_dateEntree!) : null,
        'date_sortie_prevue':    _dateSortiePrevue != null
            ? DateFormat('yyyy-MM-dd').format(_dateSortiePrevue!) : null,
        'date_sortie_effective': _statut == 'sorti' && _dateSortieEff != null
            ? DateFormat('yyyy-MM-dd').format(_dateSortieEff!) : null,
        'seul_dans_logement':    _seul,
      }).eq('id', widget.entree['id']);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e')));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce séjour ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible (annulation de la réservation).',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      await widget.supa.from('pension_entrees').delete().eq('id', widget.entree['id']);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom = widget.entree['animal_nom']?.toString() ?? '—';
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, ctrl) => Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            decoration: const BoxDecoration(
              color: _teal,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white38, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom, style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const Text('Modifier l\'entrée',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white70)),
              ])),
              if (_saving)
                const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              else
                TextButton(
                  onPressed: _save,
                  child: const Text('Enregistrer',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          color: Colors.white, fontSize: 14)),
                ),
            ]),
          ),
          Expanded(child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              // Statut
              _sectionTitle('Statut'),
              const SizedBox(height: 10),
              _card([Row(children: [
                _statutChip('en_pension', 'En pension', _green),
                const SizedBox(width: 8),
                _statutChip('sorti', 'Sorti', _teal),
              ])]),
              const SizedBox(height: 16),

              // Animal
              _sectionTitle('Animal'),
              const SizedBox(height: 10),
              _card([
                _tf('Espèce', _especeCtrl),
                const SizedBox(height: 10),
                _tf('Race', _raceCtrl),
              ]),
              const SizedBox(height: 16),

              // Fiche animal
              _sectionTitle('Fiche animal'),
              const SizedBox(height: 10),
              _card([
                if (_animalId != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => AnimalFichePensionPage(
                          animalId: _animalId!,
                          animalNom: widget.entree['animal_nom']?.toString(),
                        ),
                      )),
                      icon: const Icon(Icons.badge_outlined, size: 16),
                      label: const Text('Voir la fiche', style: TextStyle(fontFamily: 'Galey')),
                      style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_accessStatus == null && !_checkingAccess)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _demanderAcces,
                        icon: const Icon(Icons.lock_open_outlined, size: 16),
                        label: const Text('Demander l\'accès à la fiche', style: TextStyle(fontFamily: 'Galey')),
                        style: OutlinedButton.styleFrom(foregroundColor: _green, side: const BorderSide(color: _green)),
                      ),
                    )
                  else if (_checkingAccess)
                    const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
                  else
                    Text(
                      _accessStatus == 'active' ? 'Accès accordé par le propriétaire'
                          : _accessStatus == 'pending' ? 'Demande d\'accès en attente'
                          : 'Accès refusé par le propriétaire',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                    ),
                ] else ...[
                  Text('Aucune fiche rattachée à ce séjour.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _linkingFiche ? null : _linkFiche,
                      icon: _linkingFiche
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Rattacher une fiche (puce)', style: TextStyle(fontFamily: 'Galey')),
                      style: OutlinedButton.styleFrom(foregroundColor: _green, side: const BorderSide(color: _green)),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: _seul,
                  onChanged: (v) => setState(() => _seul = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: _teal,
                  title: const Text('Animal doit être seul dans le logement',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 16),

              // Client
              _sectionTitle('Propriétaire / Client'),
              const SizedBox(height: 10),
              _card([
                _tf('Nom du propriétaire', _clientCtrl),
                const SizedBox(height: 10),
                _tf('Téléphone', _contactCtrl,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 10),
                _tf('Email', _emailCtrl,
                    keyboardType: TextInputType.emailAddress),
              ]),
              const SizedBox(height: 16),

              // Dates
              _sectionTitle('Séjour'),
              const SizedBox(height: 10),
              _card([
                _datePicker('Date d\'entrée', _dateEntree,
                    (d) => _dateEntree = d, allowFuture: false),
                const SizedBox(height: 10),
                _datePicker('Sortie prévue', _dateSortiePrevue,
                    (d) => _dateSortiePrevue = d, allowFuture: true),
                if (_statut == 'sorti') ...[
                  const SizedBox(height: 10),
                  _datePicker('Sortie effective', _dateSortieEff,
                      (d) => _dateSortieEff = d, allowFuture: false),
                ],
              ]),
              const SizedBox(height: 16),

              // Notes
              _sectionTitle('Notes'),
              const SizedBox(height: 10),
              _card([_tf('Alimentation, médicaments, comportement…', _notesCtrl,
                  maxLines: 3)]),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Enregistrer',
                          style: TextStyle(fontFamily: 'Galey',
                              fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('Supprimer le séjour (annulation)',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _statutChip(String value, String label, Color color) {
    final active = _statut == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _statut = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            border: Border.all(color: active ? color : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(label,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  color: active ? Colors.white : Colors.black87))),
        ),
      ),
    );
  }

  Widget _datePicker(String label, DateTime? value, ValueChanged<DateTime> cb,
      {bool allowFuture = false}) {
    return GestureDetector(
      onTap: () => _pickDate(value, cb, allowFuture: allowFuture),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: value != null ? _teal : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 15,
              color: value != null ? _teal : Colors.grey),
          const SizedBox(width: 10),
          Text(value != null ? _fmt.format(value) : label,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: value != null ? const Color(0xFF1F2A2E) : Colors.grey)),
        ]),
      ),
    );
  }

  Widget _tf(String label, TextEditingController ctrl,
      {TextInputType? keyboardType, int maxLines = 1}) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _teal, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );

  static Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
          fontSize: 14, color: Color(0xFF1F2A2E)));

  static Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

// ── Scan/saisie puce réutilisable (registre + planning) ─────────────────────

const _kChipTeal = Color(0xFF0C5C6C);

/// Propose Scanner / Saisir la puce / Sans puce, puis cherche l'animal
/// correspondant en base. Retourne les valeurs à préremplir dans
/// PensionEntreeSheet (map vide si "sans puce" ou animal non trouvé),
/// ou null si l'utilisateur annule le choix initial.
Future<Map<String, dynamic>?> pickAnimalForAdmission(BuildContext context, {bool allowSkip = true}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Align(alignment: Alignment.centerLeft, child: Text('Identifier l\'animal',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),
        ),
        ListTile(
          leading: const Icon(Icons.sensors_rounded, color: _kChipTeal),
          title: const Text('Scanner une puce', style: TextStyle(fontFamily: 'Galey')),
          onTap: () => Navigator.pop(ctx, 'scan'),
        ),
        ListTile(
          leading: const Icon(Icons.keyboard_outlined, color: _kChipTeal),
          title: const Text('Saisir le numéro de puce', style: TextStyle(fontFamily: 'Galey')),
          onTap: () => Navigator.pop(ctx, 'manual'),
        ),
        if (allowSkip)
          ListTile(
            leading: const Icon(Icons.edit_note_outlined, color: Colors.grey),
            title: const Text('Sans puce (saisie manuelle)', style: TextStyle(fontFamily: 'Galey')),
            onTap: () => Navigator.pop(ctx, 'skip'),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice == null) return null;
  if (choice == 'skip') return {};

  String? chip;
  if (choice == 'scan') {
    chip = await ChipScannerService.showScanner(context);
  } else if (context.mounted) {
    final ctrl = TextEditingController();
    chip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Saisir le numéro de puce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 15, letterSpacing: 1.2),
          decoration: InputDecoration(
            hintText: '250 269 810 000 000',
            hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kChipTeal, width: 1.5)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kChipTeal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Rechercher', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }
  if (chip == null || chip.trim().isEmpty) return {};

  return _lookupAnimalByChip(chip.trim());
}

Future<Map<String, dynamic>> _lookupAnimalByChip(String chip) async {
  final supa = Supabase.instance.client;
  final normalized = chip.replaceAll(RegExp(r'[\s\-]'), '');
  Map<String, dynamic>? found;
  String? ownerNom, ownerContact, ownerEmail, ownerAdresse, ownerUid;

  try {
    final rows = await supa
        .from('animaux')
        .select('id,nom,espece,race,identification,photo_url,uid_eleveur,uid_proprietaire')
        .not('identification', 'is', null)
        .limit(2000);
    for (final row in rows as List) {
      final id = ((row as Map)['identification'] ?? '').toString().replaceAll(RegExp(r'[\s\-]'), '');
      if (id.isNotEmpty && id == normalized) {
        found = Map<String, dynamic>.from(row);
        break;
      }
    }
    if (found != null) {
      final animalId = found['id'] as String;
      // Propriétaire actuel = animaux_proprietes (source unique, date_fin IS NULL),
      // fallback sur uid_eleveur/uid_proprietaire si jamais peuplée pour cet animal.
      try {
        final propRow = await supa.from('animaux_proprietes')
            .select('uid_proprio')
            .eq('animal_id', animalId)
            .filter('date_fin', 'is', null)
            .order('date_debut', ascending: false)
            .limit(1)
            .maybeSingle();
        ownerUid = (propRow?['uid_proprio'] as String?) ??
            (found['uid_eleveur'] ?? found['uid_proprietaire'])?.toString();
      } catch (_) {
        ownerUid = (found['uid_eleveur'] ?? found['uid_proprietaire'])?.toString();
      }

      if (ownerUid != null && ownerUid.isNotEmpty) {
        try {
          final doc = await FirebaseFirestore.instance.collection('users').doc(ownerUid).get();
          final d = doc.data();
          if (d != null) {
            // Éleveur/pro → nom d'élevage + adresse pro en priorité, sinon nom perso.
            final nameElevage = (d['name_elevage'] as String?) ?? (d['nom'] as String?);
            final firstLast = [d['firstname'] as String? ?? '', d['lastname'] as String? ?? '']
                .where((s) => s.isNotEmpty).join(' ');
            ownerNom = (nameElevage != null && nameElevage.isNotEmpty) ? nameElevage : firstLast;

            ownerContact = (d['phone_number'] as String?) ?? (d['telephone'] as String?) ?? '';
            ownerEmail   = (d['email'] as String?) ?? (d['email_contact'] as String?) ?? '';

            final ruePro   = d['rue_pro'] as String? ?? d['adress_elevage'] as String? ?? d['rue_elevage'] as String?;
            final cpPro    = d['code_postal_pro'] as String?;
            final villePro = d['ville_pro'] as String? ?? d['ville_elevage'] as String?;
            final rue      = ruePro ?? d['rue'] as String?;
            final cp       = cpPro ?? d['code_postal'] as String?;
            final ville    = villePro ?? d['ville'] as String?;
            ownerAdresse = [rue, [cp, ville].where((s) => (s ?? '').isNotEmpty).join(' ')]
                .where((s) => (s ?? '').isNotEmpty).join(', ');
          }
        } catch (_) {}
      }
    }
  } catch (_) {}

  return {
    'nom':                 found?['nom']?.toString(),
    'espece':              found?['espece']?.toString(),
    'race':                found?['race']?.toString(),
    'puce':                found?['identification']?.toString() ?? chip,
    'photoUrl':            found?['photo_url']?.toString(),
    'animalId':            found?['id']?.toString(),
    'ownerUid':            ownerUid,
    'proprietaireNom':     ownerNom,
    'proprietaireContact': ownerContact,
    'proprietaireEmail':   ownerEmail,
    'proprietaireAdresse': ownerAdresse,
  };
}

// ── Sheet ajout nouvelle entrée ────────────────────────────────────────────────

class PensionEntreeSheet extends StatefulWidget {
  final String? initialNom;
  final String? initialEspece;
  final String? initialRace;
  final String? initialPuce;
  final String? initialProprietaireNom;
  final String? initialProprietaireContact;
  final String? initialProprietaireEmail;
  final String? initialProprietaireAdresse;
  final String? initialPhotoUrl;
  final String? initialAnimalId;   // passé depuis le scan pour éviter une 2e recherche
  final String? initialOwnerUid;   // passé depuis le scan pour la notif directe
  final String? initialLogementId; // passé depuis le planning — assigne directement le logement
  final DateTime? initialDateEntree; // passé depuis le planning — jour cliqué

  const PensionEntreeSheet({
    this.initialNom,
    this.initialEspece,
    this.initialRace,
    this.initialPuce,
    this.initialProprietaireNom,
    this.initialProprietaireContact,
    this.initialProprietaireEmail,
    this.initialProprietaireAdresse,
    this.initialPhotoUrl,
    this.initialAnimalId,
    this.initialOwnerUid,
    this.initialLogementId,
    this.initialDateEntree,
  });

  @override
  State<PensionEntreeSheet> createState() => _PensionEntreeSheetState();
}

class _PensionEntreeSheetState extends State<PensionEntreeSheet> {
  static const _teal = Color(0xFF0C5C6C);
  final _formKey = GlobalKey<FormState>();
  final _supa    = Supabase.instance.client;

  late final TextEditingController _nomCtrl;
  late final TextEditingController _especeCtrl;
  late final TextEditingController _raceCtrl;
  late final TextEditingController _puceCtrl;
  late final TextEditingController _clientCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _adresseCtrl;
  final _notesCtrl    = TextEditingController();
  DateTime _dateEntree = DateTime.now();
  DateTime? _dateSortiePrevue;
  bool _seul = false;

  @override
  void initState() {
    super.initState();
    _nomCtrl    = TextEditingController(text: widget.initialNom ?? '');
    _especeCtrl = TextEditingController(text: widget.initialEspece ?? '');
    _raceCtrl   = TextEditingController(text: widget.initialRace ?? '');
    _puceCtrl   = TextEditingController(text: widget.initialPuce ?? '');
    _clientCtrl  = TextEditingController(text: widget.initialProprietaireNom ?? '');
    _contactCtrl = TextEditingController(text: widget.initialProprietaireContact ?? '');
    _emailCtrl   = TextEditingController(text: widget.initialProprietaireEmail ?? '');
    _adresseCtrl = TextEditingController(text: widget.initialProprietaireAdresse ?? '');
    if (widget.initialDateEntree != null) _dateEntree = widget.initialDateEntree!;
  }
  bool _saving = false;

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _nomCtrl.dispose(); _especeCtrl.dispose(); _raceCtrl.dispose();
    _puceCtrl.dispose(); _clientCtrl.dispose(); _contactCtrl.dispose();
    _emailCtrl.dispose(); _notesCtrl.dispose(); _adresseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isEntree) async {
    final initial = isEntree ? _dateEntree
        : (_dateSortiePrevue ?? DateTime.now().add(const Duration(days: 3)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData.light()
            .copyWith(colorScheme: const ColorScheme.light(primary: _teal)),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isEntree) _dateEntree = picked;
      else _dateSortiePrevue = picked;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      // Animal inconnu (pas trouvé via scan/recherche) → on crée sa fiche
      // complète en base tout de suite, même sans compte propriétaire.
      // uid_eleveur = la pension (gestionnaire actuel), owner_uid sera
      // renseigné si le propriétaire réclame la fiche plus tard.
      String? animalId = widget.initialAnimalId;
      final justCreatedFiche = animalId == null && _nomCtrl.text.trim().isNotEmpty;
      if (justCreatedFiche) {
        animalId = DateTime.now().millisecondsSinceEpoch.toString();
        await _supa.from('animaux').insert({
          'id':            animalId,
          'uid_eleveur':   _uid,
          'nom':           _nomCtrl.text.trim(),
          'espece':        _especeCtrl.text.trim().toLowerCase(),
          'race':          _raceCtrl.text.trim(),
          'identification': _puceCtrl.text.trim(),
          if (widget.initialPhotoUrl != null) 'photo_url': widget.initialPhotoUrl,
          'statut': 'present',
        });
      }

      await _supa.from('pension_entrees').insert({
        'pro_uid':              _uid,
        'pro_profile_id':       User_Info.activeProfileId,
        'animal_id':            animalId,
        'animal_nom':           _nomCtrl.text.trim(),
        'espece':               _especeCtrl.text.trim().toLowerCase(),
        'race':                 _raceCtrl.text.trim(),
        'puce':                 _puceCtrl.text.trim(),
        'proprietaire_nom':     _clientCtrl.text.trim(),
        'proprietaire_contact': _contactCtrl.text.trim(),
        'proprietaire_email':   _emailCtrl.text.trim(),
        'proprietaire_adresse': _adresseCtrl.text.trim(),
        if (widget.initialPhotoUrl != null) 'photo_url': widget.initialPhotoUrl,
        if (widget.initialLogementId != null) 'logement_id': widget.initialLogementId,
        'seul_dans_logement':   _seul,
        'date_entree':          DateFormat('yyyy-MM-dd').format(_dateEntree),
        if (_dateSortiePrevue != null)
          'date_sortie_prevue': DateFormat('yyyy-MM-dd').format(_dateSortiePrevue!),
        'notes':   _notesCtrl.text.trim(),
        'statut':  'en_pension',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Demande d'accès à la fiche en parallèle (silencieux si déjà accordé)
      // — inutile si on vient de créer la fiche nous-mêmes (on est déjà gestionnaire)
      if (!justCreatedFiche) _requestFicheAcces().ignore();

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  Future<void> _requestFicheAcces() async {
    try {
      String? animalId  = widget.initialAnimalId;
      String? ownerUid  = widget.initialOwnerUid;
      String  animalNom = _nomCtrl.text.trim();

      // Si on n'a pas l'animalId, chercher par puce
      if (animalId == null) {
        final puce = _puceCtrl.text.trim();
        if (puce.isEmpty) return;
        final normalized = puce.replaceAll(RegExp(r'[\s\-]'), '');
        final rows = await _supa.from('animaux')
            .select('id, nom, uid_eleveur, uid_proprietaire')
            .not('identification', 'is', null)
            .limit(2000);
        for (final row in rows as List) {
          final id = ((row as Map)['identification'] ?? '').toString()
              .replaceAll(RegExp(r'[\s\-]'), '');
          if (id.isNotEmpty && id == normalized) {
            animalId  = (row as Map)['id'] as String;
            ownerUid  = ((row)['uid_eleveur'] ?? (row)['uid_proprietaire'])
                ?.toString();
            if ((row)['nom']?.toString().isNotEmpty == true) {
              animalNom = (row)['nom'] as String;
            }
            break;
          }
        }
      }

      if (animalId == null || ownerUid == null || ownerUid.isEmpty) return;

      // Résoudre profile IDs
      final pid = User_Info.activeProfileId;
      final ownerProfile = await _supa.from('user_profiles')
          .select('id').eq('uid', ownerUid).eq('is_main', true).maybeSingle();
      final ownerProfileId = ownerProfile?['id'] as String?;
      if (pid.isEmpty || ownerProfileId == null) return;

      // Vérifier si accès déjà existant
      final existing = await _supa.from('animal_access')
          .select('id, statut')
          .eq('pro_profile_id', pid)
          .eq('animal_id', animalId)
          .maybeSingle();
      if (existing != null) return;

      final pensionNom = User_Info.nameElevage.isNotEmpty
          ? User_Info.nameElevage
          : '${User_Info.firstname} ${User_Info.lastname}'.trim();

      await _supa.from('animal_access').insert({
        'pro_profile_id':        pid,
        'animal_id':             animalId,
        'granted_by_profile_id': ownerProfileId,
        'permissions':           ['read_basic', 'read_alimentation', 'write_notes'],
        'statut':                'pending',
      });

      await _supa.from('notifications').insert({
        'uid':   ownerUid,
        'type':  'pension_acces',
        'title': 'Demande d\'accès à la fiche de $animalNom',
        'body':  '$pensionNom souhaite consulter la fiche de $animalNom en pension (lecture seule).',
        'data':  {
          'pensionUid': _uid,
          'pensionNom': pensionNom,
          'animalId':   animalId,
          'animalNom':  animalNom,
        },
        'read': false,
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Text('Nouvelle entrée',
                style: TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 18))),
            IconButton(icon: const Icon(Icons.close, size: 22, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 20),

          _lbl('Nom de l\'animal *'),
          TextFormField(
            controller: _nomCtrl,
            decoration: _dec('Ex : Médor'),
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
          ),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _lbl('Espèce'),
              TextFormField(controller: _especeCtrl, decoration: _dec('Chien')),
            ])),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _lbl('Race'),
              TextFormField(controller: _raceCtrl, decoration: _dec('Labrador')),
            ])),
          ]),
          const SizedBox(height: 10),
          _lbl('Numéro de puce'),
          TextFormField(controller: _puceCtrl, decoration: _dec('250 269 810 000 000')),
          const SizedBox(height: 20),

          _lbl('Propriétaire'),
          TextFormField(controller: _clientCtrl, decoration: _dec('Nom du propriétaire')),
          const SizedBox(height: 10),
          _lbl('Téléphone'),
          TextFormField(controller: _contactCtrl, decoration: _dec('06 XX XX XX XX'),
              keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          _lbl('Email'),
          TextFormField(controller: _emailCtrl, decoration: _dec('adresse@email.com'),
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _lbl('Adresse'),
          TextFormField(controller: _adresseCtrl, decoration: _dec('Rue, code postal, ville')),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _seul,
            onChanged: (v) => setState(() => _seul = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: _teal,
            title: const Text('Animal doit être seul dans le logement',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
          ),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(child: _DateTile(label: 'Entrée *', date: _dateEntree,
                onTap: () => _pickDate(true))),
            const SizedBox(width: 10),
            Expanded(child: _DateTile(label: 'Sortie prévue', date: _dateSortiePrevue,
                onTap: () => _pickDate(false))),
          ]),
          const SizedBox(height: 14),

          _lbl('Notes'),
          TextFormField(controller: _notesCtrl,
              decoration: _dec('Alimentation, médicaments, comportement…'), maxLines: 3),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer l\'entrée',
                      style: TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ])),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(t, style: const TextStyle(fontFamily: 'Galey',
          fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6F767B))));

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _teal, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    filled: true,
    fillColor: const Color(0xFFF8F8F8),
  );
}

// ── DateTile ──────────────────────────────────────────────────────────────────

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  static const _teal = Color(0xFF0C5C6C);

  const _DateTile({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = date != null ? DateFormat('dd/MM/yyyy').format(date!) : 'Choisir';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
              color: Color(0xFF6F767B), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 14, color: _teal),
            const SizedBox(width: 6),
            Text(fmt, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                fontWeight: FontWeight.w600,
                color: date != null ? const Color(0xFF1E2025) : Colors.grey)),
          ]),
        ]),
      ),
    );
  }
}

// ── Sheet demande d'accès fiche animal ────────────────────────────────────────

class _AccessRequestSheet extends StatefulWidget {
  final Map<String, dynamic> animal;
  final String chip;
  final String pensionUid;
  final String pensionNom;
  final SupabaseClient supa;
  final VoidCallback onSent;
  final void Function(String animalId, String animalNom) onAlreadyApproved;
  final void Function(String animalNom) onAlreadyPending;

  const _AccessRequestSheet({
    required this.animal,
    required this.chip,
    required this.pensionUid,
    required this.pensionNom,
    required this.supa,
    required this.onSent,
    required this.onAlreadyApproved,
    required this.onAlreadyPending,
  });

  @override
  State<_AccessRequestSheet> createState() => _AccessRequestSheetState();
}

class _AccessRequestSheetState extends State<_AccessRequestSheet> {
  static const _teal = Color(0xFF0C5C6C);
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final ownerUid = (widget.animal['uid_eleveur'] ??
          widget.animal['uid_proprietaire'])?.toString() ?? '';
      if (ownerUid.isEmpty) throw Exception('Propriétaire introuvable');

      final animalId  = widget.animal['id']?.toString()  ?? '';
      final animalNom = widget.animal['nom']?.toString()  ?? 'Animal';

      final proProfile = await widget.supa.from('user_profiles')
          .select('id').eq('uid', widget.pensionUid).eq('is_main', true).maybeSingle();
      final proProfileId = proProfile?['id'] as String?;
      final ownerProfile = await widget.supa.from('user_profiles')
          .select('id').eq('uid', ownerUid).eq('is_main', true).maybeSingle();
      final ownerProfileId = ownerProfile?['id'] as String?;
      if (proProfileId == null || ownerProfileId == null) throw Exception('Profils introuvables');

      final existing = await widget.supa
          .from('animal_access')
          .select('id,statut')
          .eq('pro_profile_id', proProfileId)
          .eq('animal_id', animalId)
          .maybeSingle();

      if (existing != null) {
        final statut = existing['statut'] as String? ?? '';
        if (statut == 'active')  { widget.onAlreadyApproved(animalId, animalNom); return; }
        if (statut == 'pending') { widget.onAlreadyPending(animalNom);  return; }
        await widget.supa.from('animal_access').update({
          'statut': 'pending',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', existing['id']);
      } else {
        await widget.supa.from('animal_access').insert({
          'pro_profile_id':        proProfileId,
          'animal_id':             animalId,
          'granted_by_profile_id': ownerProfileId,
          'permissions':           ['read_basic', 'read_alimentation', 'write_notes'],
          'statut':                'pending',
        });
      }

      await widget.supa.from('notifications').insert({
        'uid':   ownerUid,
        'type':  'pension_acces',
        'title': 'Demande d\'accès à la fiche de $animalNom',
        'body':  '${widget.pensionNom} souhaite consulter la fiche de $animalNom (lecture seule).',
        'data':  {
          'pensionUid': widget.pensionUid,
          'pensionNom': widget.pensionNom,
          'animalId':   animalId,
          'animalNom':  animalNom,
        },
        'read': false,
      });

      if (mounted) widget.onSent();
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom    = widget.animal['nom']?.toString() ?? 'Animal';
    final espece = widget.animal['espece']?.toString() ?? '';
    final race   = widget.animal['race']?.toString() ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _teal.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Container(width: 48, height: 48,
                decoration: BoxDecoration(color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Center(child: _speciesIcon(espece, 24, _teal))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom, style: const TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E2025))),
              Text([_espLabel(espece), if (race.isNotEmpty) race].join(' · '),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
              Text('Puce : ${widget.chip}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
            ])),
          ]),
        ),
        const SizedBox(height: 20),
        const Text(
          'Envoyer une demande au propriétaire pour consulter la fiche de cet animal en lecture seule (santé, alimentation, comportement) ?',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5, color: Color(0xFF374151)),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _sending ? null : _send,
            style: FilledButton.styleFrom(
                backgroundColor: _teal,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _sending
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Demander l\'accès à la fiche',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ── Facturation pension ───────────────────────────────────────────────────────

class _FacturationSheet extends StatefulWidget {
  final Map<String, dynamic> entree;
  const _FacturationSheet({required this.entree});

  @override
  State<_FacturationSheet> createState() => _FacturationSheetState();
}

class _FacturationSheetState extends State<_FacturationSheet> {
  static const _teal   = Color(0xFF0C5C6C);
  static const _purple = Color(0xFF7B5EA7);

  late final TextEditingController _tarifCtrl;
  late final TextEditingController _nbNuitsCtrl;
  late final TextEditingController _suppDescCtrl;
  late final TextEditingController _suppMontantCtrl;
  bool _avecTVA    = false;
  bool _generating = false;
  bool _sending    = false;

  @override
  void initState() {
    super.initState();
    final d = widget.entree;
    final dateEntree     = DateTime.tryParse(d['date_entree']            as String? ?? '');
    final dateSortieEff  = DateTime.tryParse(d['date_sortie_effective']  as String? ?? '');
    final dateSortiePrev = DateTime.tryParse(d['date_sortie_prevue']     as String? ?? '');
    final dateSortie     = dateSortieEff ?? dateSortiePrev;

    int nbNuits = 1;
    if (dateEntree != null) {
      final diff = (dateSortie ?? DateTime.now()).difference(dateEntree).inDays;
      if (diff > 0) nbNuits = diff;
    }

    _tarifCtrl       = TextEditingController();
    _nbNuitsCtrl     = TextEditingController(text: '$nbNuits');
    _suppDescCtrl    = TextEditingController();
    _suppMontantCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _tarifCtrl.dispose();
    _nbNuitsCtrl.dispose();
    _suppDescCtrl.dispose();
    _suppMontantCtrl.dispose();
    super.dispose();
  }

  double get _tarif     => double.tryParse(_tarifCtrl.text.replaceAll(',', '.'))       ?? 0;
  int    get _nbNuits   => int.tryParse(_nbNuitsCtrl.text)                             ?? 1;
  double get _supp      => double.tryParse(_suppMontantCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _sousTotal => (_tarif * _nbNuits) + _supp;
  double get _tva       => _avecTVA ? _sousTotal * 0.20 : 0;
  double get _total     => _sousTotal + _tva;

  String _fmt(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      duration: const Duration(milliseconds: 150),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 8),
          // En-tête
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.receipt_long_outlined, color: _teal, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Facturation pension', style: TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
                Text('Générer une facture PDF', style: TextStyle(fontFamily: 'Galey',
                    fontSize: 12, color: Color(0xFF6B7280))),
              ])),
              IconButton(
                icon: const Icon(Icons.close, size: 20, color: Color(0xFF6B7280)),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Résumé animal
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(children: [
                    _speciesIcon(widget.entree['espece']?.toString() ?? '', 18, _teal),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.entree['animal_nom']?.toString() ?? '—',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 13, color: Color(0xFF1F2A2E))),
                      Text(widget.entree['proprietaire_nom']?.toString() ?? '—',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                              color: Color(0xFF6B7280))),
                    ])),
                  ]),
                ),
                const SizedBox(height: 16),

                // Tarif/nuit + nb nuits
                Row(children: [
                  Expanded(child: _field(_tarifCtrl, 'Tarif par nuit (€)', '25',
                      type: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_nbNuitsCtrl, 'Nombre de nuits', '1',
                      suffix: 'nuits', type: TextInputType.number)),
                ]),
                const SizedBox(height: 12),

                // Suppléments
                _field(_suppDescCtrl, 'Suppléments (optionnel)',
                    'Ex : Frais vétérinaires, médicaments...'),
                const SizedBox(height: 8),
                _field(_suppMontantCtrl, 'Montant suppléments (€)', '0',
                    type: const TextInputType.numberWithOptions(decimal: true)),
                const SizedBox(height: 16),

                // TVA toggle
                GestureDetector(
                  onTap: () => setState(() => _avecTVA = !_avecTVA),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _avecTVA ? _teal.withValues(alpha: 0.05) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _avecTVA ? _teal.withValues(alpha: 0.3) : Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.percent_rounded, size: 16,
                          color: _avecTVA ? _teal : Colors.grey.shade400),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Assujetti à la TVA (20%)',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                              color: Color(0xFF374151)))),
                      Switch.adaptive(
                        value: _avecTVA,
                        onChanged: (v) => setState(() => _avecTVA = v),
                        activeColor: _teal,
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),

                // Récap
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _teal.withValues(alpha: 0.15)),
                  ),
                  child: Column(children: [
                    _totalRow(
                      'Pension ($_nbNuits nuit${_nbNuits > 1 ? 's' : ''} × ${_fmt(_tarif)})',
                      _fmt(_tarif * _nbNuits),
                    ),
                    if (_supp > 0) ...[
                      const SizedBox(height: 4),
                      _totalRow('Suppléments', _fmt(_supp)),
                    ],
                    const Divider(height: 16, color: Color(0xFFE5E7EB)),
                    if (_avecTVA) ...[
                      _totalRow('Sous-total HT', _fmt(_sousTotal)),
                      const SizedBox(height: 4),
                      _totalRow('TVA 20%', _fmt(_tva)),
                      const Divider(height: 12, color: Color(0xFFE5E7EB)),
                    ],
                    _totalRow(_avecTVA ? 'TOTAL TTC' : 'TOTAL', _fmt(_total), bold: true),
                  ]),
                ),
                const SizedBox(height: 20),

                // Bouton Aperçu / Imprimer
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _tarif > 0 && !_generating && !_sending ? _genererPDF : null,
                    icon: _generating
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: Text(_generating ? 'Génération...' : 'Aperçu / Imprimer',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Bouton Envoyer au propriétaire
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _tarif > 0 && !_generating && !_sending ? _envoyerAuProprietaire : null,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C5C6C)))
                        : const Icon(Icons.send_outlined, size: 18),
                    label: Text(_sending ? 'Envoi en cours...' : 'Envoyer au propriétaire',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _teal,
                      side: const BorderSide(color: Color(0xFF0C5C6C)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      {TextInputType? type, String? suffix}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
          fontWeight: FontWeight.w600, color: Color(0xFF374151))),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: type,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
          suffixText: suffix,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _teal, width: 1.5)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200)),
        ),
      ),
    ]);

  Widget _totalRow(String label, String value, {bool bold = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: bold ? 14 : 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: bold ? const Color(0xFF1F2A2E) : const Color(0xFF6B7280))),
      Text(value, style: TextStyle(fontFamily: 'Galey', fontSize: bold ? 16 : 13,
          fontWeight: FontWeight.w700,
          color: bold ? _teal : const Color(0xFF1F2A2E))),
    ],
  );

  // Construit le document PDF et retourne les bytes
  Future<Uint8List> _buildPdfBytes() async {
    final e        = widget.entree;
    final pdfDoc   = pw.Document();
    final font     = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fmt      = DateFormat('dd/MM/yyyy');
    final logo     = pw.MemoryImage(
        (await rootBundle.load('assets/Logo_petsmatch_fond_blanc.png'))
            .buffer.asUint8List());

    final now        = DateTime.now();
    final invoiceNum = 'FACT-${DateFormat('yyyyMMdd-HHmm').format(now)}';

    final pensionNom = User_Info.nameElevage.isNotEmpty
        ? User_Info.nameElevage
        : '${User_Info.firstname} ${User_Info.lastname}'.trim();

    final adressePension = [
      User_Info.rueElevage.isNotEmpty ? User_Info.rueElevage : User_Info.rue,
      User_Info.villeElevage.isNotEmpty ? User_Info.villeElevage : User_Info.ville,
      User_Info.codePostalElevage.isNotEmpty ? User_Info.codePostalElevage : User_Info.codePostal,
    ].where((s) => s.isNotEmpty).join(', ');

    String fmtIso(String? iso) {
      if (iso == null || iso.isEmpty) return '—';
      final dt = DateTime.tryParse(iso);
      return dt != null ? fmt.format(dt) : '—';
    }

    String fmtM(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

    final nbN       = _nbNuits;
    final tarif     = _tarif;
    final supp      = _supp;
    final sousTotal = _sousTotal;
    final tvaAmt    = _tva;
    final total     = _total;
    final suppDesc  = _suppDescCtrl.text.trim();
    final avecTVA   = _avecTVA;
    final dateSortie = (e['date_sortie_effective'] ?? e['date_sortie_prevue']) as String?;

    pw.Widget detailRow(String desc, String qte, String pu, String montant,
        {bool isHeader = false}) =>
      pw.Container(
        decoration: pw.BoxDecoration(
          color: isHeader ? const PdfColor.fromInt(0xFF0C5C6C) : null,
          border: const pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.3)),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Row(children: [
          pw.Expanded(flex: 5, child: pw.Text(desc,
              style: pw.TextStyle(font: isHeader ? fontBold : font, fontSize: 8,
                  color: isHeader ? PdfColors.white : PdfColors.black))),
          pw.SizedBox(width: 36, child: pw.Text(qte, textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: isHeader ? fontBold : font, fontSize: 8,
                  color: isHeader ? PdfColors.white : PdfColors.grey700))),
          pw.SizedBox(width: 60, child: pw.Text(pu, textAlign: pw.TextAlign.right,
              style: pw.TextStyle(font: isHeader ? fontBold : font, fontSize: 8,
                  color: isHeader ? PdfColors.white : PdfColors.grey700))),
          pw.SizedBox(width: 60, child: pw.Text(montant, textAlign: pw.TextAlign.right,
              style: pw.TextStyle(font: isHeader ? fontBold : font, fontSize: 8,
                  color: isHeader ? PdfColors.white : const PdfColor.fromInt(0xFF0C5C6C)))),
        ]),
      );

    pw.Widget totalLine(String label, String value,
        {bool isBold = false, bool isHighlight = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: isHighlight ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0C5C6C)) : null,
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.SizedBox(width: 130, child: pw.Text(label,
              style: pw.TextStyle(font: isBold || isHighlight ? fontBold : font, fontSize: 8,
                  color: isHighlight ? PdfColors.white : PdfColors.grey700))),
          pw.SizedBox(width: 64, child: pw.Text(value, textAlign: pw.TextAlign.right,
              style: pw.TextStyle(font: isBold || isHighlight ? fontBold : font, fontSize: 8,
                  color: isHighlight ? PdfColors.white : const PdfColor.fromInt(0xFF0C5C6C)))),
        ]),
      );

    pdfDoc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Image(logo, width: 40, height: 40),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('FACTURE', style: pw.TextStyle(font: fontBold, fontSize: 18,
                color: const PdfColor.fromInt(0xFF0C5C6C))),
            pw.Text(invoiceNum, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Date : ${fmt.format(now)}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
          ]),
        ]),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFF0C5C6C)),
        pw.SizedBox(height: 14),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('ÉMETTEUR', style: pw.TextStyle(font: fontBold, fontSize: 7,
                color: PdfColors.grey500, letterSpacing: 0.5)),
            pw.SizedBox(height: 4),
            if (pensionNom.isNotEmpty) pw.Text(pensionNom, style: pw.TextStyle(font: fontBold, fontSize: 10)),
            if (adressePension.isNotEmpty) pw.Text(adressePension, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            if (User_Info.email.isNotEmpty && User_Info.email != 'none')
              pw.Text(User_Info.email, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            if (User_Info.phone_number.isNotEmpty && User_Info.phone_number != '0000000000')
              pw.Text(User_Info.phone_number, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            if (User_Info.siret.isNotEmpty)
              pw.Text('SIRET : ${User_Info.siret}', style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey500)),
          ])),
          pw.SizedBox(width: 24),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('DESTINATAIRE', style: pw.TextStyle(font: fontBold, fontSize: 7,
                color: PdfColors.grey500, letterSpacing: 0.5)),
            pw.SizedBox(height: 4),
            pw.Text((e['proprietaire_nom'] ?? '').toString().isNotEmpty ? e['proprietaire_nom'].toString() : '—',
                style: pw.TextStyle(font: fontBold, fontSize: 10)),
            if ((e['proprietaire_contact'] ?? '').toString().isNotEmpty)
              pw.Text(e['proprietaire_contact'].toString(), style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            if ((e['proprietaire_email'] ?? '').toString().isNotEmpty)
              pw.Text(e['proprietaire_email'].toString(), style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
          ])),
        ]),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF0F7F9),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('ANIMAL', style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.grey500, letterSpacing: 0.5)),
              pw.SizedBox(height: 3),
              pw.Text('${e['animal_nom'] ?? '—'} · ${_espLabel(e['espece']?.toString() ?? '')}',
                  style: pw.TextStyle(font: fontBold, fontSize: 9)),
              if ((e['race'] ?? '').toString().isNotEmpty)
                pw.Text(e['race'].toString(), style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
              if ((e['puce'] ?? '').toString().isNotEmpty)
                pw.Text('Puce : ${e['puce']}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            ])),
            pw.SizedBox(width: 20),
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('SÉJOUR', style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.grey500, letterSpacing: 0.5)),
              pw.SizedBox(height: 3),
              pw.Text('Entrée : ${fmtIso(e['date_entree'] as String?)}', style: pw.TextStyle(font: font, fontSize: 8)),
              pw.Text('Sortie : ${fmtIso(dateSortie)}', style: pw.TextStyle(font: font, fontSize: 8)),
              pw.Text('Durée : $nbN nuit${nbN > 1 ? 's' : ''}',
                  style: pw.TextStyle(font: fontBold, fontSize: 9, color: const PdfColor.fromInt(0xFF0C5C6C))),
            ])),
          ]),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
          child: pw.Column(children: [
            detailRow('Description', 'Qté', 'P.U. HT', 'Total HT', isHeader: true),
            detailRow('Pension du ${fmtIso(e['date_entree'] as String?)} au ${fmtIso(dateSortie)}',
                '$nbN', fmtM(tarif), fmtM(tarif * nbN)),
            if (supp > 0)
              detailRow(suppDesc.isNotEmpty ? suppDesc : 'Suppléments', '1', fmtM(supp), fmtM(supp)),
          ]),
        ),
        pw.SizedBox(height: 8),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          if (avecTVA) ...[
            totalLine('Sous-total HT', fmtM(sousTotal)),
            pw.SizedBox(height: 2),
            totalLine('TVA 20%', fmtM(tvaAmt)),
            pw.SizedBox(height: 4),
          ],
          totalLine(avecTVA ? 'TOTAL TTC' : 'TOTAL', fmtM(total), isBold: true, isHighlight: true),
        ]),
        pw.SizedBox(height: 20),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('CONDITIONS DE RÈGLEMENT',
                style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.grey600, letterSpacing: 0.5)),
            pw.SizedBox(height: 4),
            pw.Text('Paiement à réception de facture. '
                'Tout retard de paiement entraîne des pénalités au taux légal en vigueur. '
                'Document généré via PetsMatch.',
                style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
          ]),
        ),
      ]),
    ));

    return Uint8List.fromList(await pdfDoc.save());
  }

  Future<void> _genererPDF() async {
    setState(() => _generating = true);
    try {
      final bytes = await _buildPdfBytes();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur PDF : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _envoyerAuProprietaire() async {
    final ownerEmail = (widget.entree['proprietaire_email'] ?? '').toString().trim();
    if (ownerEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Email du propriétaire non renseigné.',
            style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _sending = true);
    try {
      // 1 — Générer les bytes PDF
      final bytes   = await _buildPdfBytes();
      final now     = DateTime.now();
      final invNum  = 'FACT-${DateFormat('yyyyMMdd-HHmm').format(now)}';
      final uid     = FirebaseAuth.instance.currentUser?.uid ?? '';
      final animalNom = widget.entree['animal_nom']?.toString() ?? '';

      // 2 — Upload Firebase Storage
      final ref     = FirebaseStorage.instance
          .ref('factures/$uid/$invNum.pdf');
      final task    = await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: 'application/pdf'),
      );
      final dlUrl   = await task.ref.getDownloadURL();

      // 3 — Lookup uid propriétaire dans Supabase par email
      final supa = Supabase.instance.client;
      final ownerRow = await supa
          .from('users')
          .select('uid')
          .eq('email', ownerEmail)
          .maybeSingle();
      final ownerUid = ownerRow?['uid'] as String?;

      if (ownerUid == null || ownerUid.isEmpty) {
        throw Exception('Propriétaire introuvable dans PetsMatch (email : $ownerEmail)');
      }

      // 4 — Notification Supabase (déclenchera FCM via Cloud Function)
      final pensionNom = User_Info.nameElevage.isNotEmpty
          ? User_Info.nameElevage
          : '${User_Info.firstname} ${User_Info.lastname}'.trim();

      await supa.from('notifications').insert({
        'uid':   ownerUid,
        'type':  'facture_pension',
        'title': 'Votre facture de pension est disponible',
        'body':  '$pensionNom vous a envoyé la facture pour le séjour de $animalNom.',
        'data':  {
          'url':        dlUrl,
          'invoice':    invNum,
          'animal_nom': animalNom,
          'pension_nom': pensionNom,
        },
        'read': false,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Facture envoyée à $ownerEmail',
              style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: const Color(0xFF0C5C6C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur envoi : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
