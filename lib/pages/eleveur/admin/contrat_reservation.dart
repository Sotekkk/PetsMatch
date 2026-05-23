import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page principale : espace contrats
// ─────────────────────────────────────────────────────────────────────────────

class ContratReservationPage extends StatelessWidget {
  const ContratReservationPage({super.key});

  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg = Color(0xFFF8F8F6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Contrats',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: const _ContratsBody(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green,
        icon: const Icon(Icons.upload_file_outlined, color: Colors.white),
        label: const Text('Ajouter',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        onPressed: () => _ContratsBody.uploadContrat(context),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Corps de la page
// ─────────────────────────────────────────────────────────────────────────────

class _ContratsBody extends StatelessWidget {
  const _ContratsBody();

  // Types de contrat modèles
  static const _modeles = [
    (type: 'reservation', label: 'Réservation', icon: Icons.pets_outlined,
     color: Color(0xFFE0F2F1), desc: 'Arrhes, conditions, disponibilité'),
    (type: 'vente', label: 'Vente', icon: Icons.handshake_outlined,
     color: Color(0xFFE8F5E9), desc: 'Transfert de propriété, garanties'),
    (type: 'saillie', label: 'Saillie extérieure', icon: Icons.favorite_border,
     color: Color(0xFFFCE4EC), desc: 'Conditions de la saillie, honoraires'),
  ];

  static String _uid() => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── Upload ────────────────────────────────────────────────────────────────

  static Future<void> uploadContrat(BuildContext context) async {
    // Sélection du fichier
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    // Choix du type via bottom sheet
    if (!context.mounted) return;
    final type = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TypePickerSheet(),
    );
    if (type == null) return;
    if (!context.mounted) return;

    // Nom du document
    String nom = file.name.replaceAll(RegExp(r'\.[^\.]+$'), '');
    final nomCtrl = TextEditingController(text: nom);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nommer le document',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: nomCtrl,
          autofocus: true,
          style: const TextStyle(fontFamily: 'Galey'),
          decoration: InputDecoration(
            hintText: 'Nom du contrat',
            hintStyle:
                const TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Color(0xFF6E9E57), width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6E9E57)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer',
                style: TextStyle(
                    fontFamily: 'Galey',
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    nom = nomCtrl.text.trim().isEmpty ? file.name : nomCtrl.text.trim();

    // Upload Firebase Storage
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ext = file.extension ?? 'pdf';
      final storagePath =
          'contrats/${_uid()}/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putData(file.bytes!);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid())
          .collection('contrats')
          .add({
        'nom': nom,
        'type': type,
        'fileName': file.name,
        'ext': ext,
        'url': url,
        'storagePath': storagePath,
        'dateUpload': FieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(const SnackBar(
          content: Text('Document enregistré',
              style: TextStyle(fontFamily: 'Galey'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Erreur : $e',
              style: const TextStyle(fontFamily: 'Galey'))));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Modèles ──────────────────────────────────────────────────────────
        const Text('Modèles de contrats',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFF1F2A2E))),
        const SizedBox(height: 4),
        Text('Générez un contrat pré-rempli depuis l\'application.',
            style: TextStyle(
                fontFamily: 'Galey',
                fontSize: 12,
                color: Colors.grey.shade500)),
        const SizedBox(height: 12),
        ..._modeles.map((m) => _ModeleCard(
              type: m.type,
              label: m.label,
              icon: m.icon,
              color: m.color,
              desc: m.desc,
            )),

        const SizedBox(height: 28),

        // ── Contrats stockés ─────────────────────────────────────────────────
        const Text('Documents stockés',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFF1F2A2E))),
        const SizedBox(height: 4),
        Text('Contrats signés, scannés ou importés.',
            style: TextStyle(
                fontFamily: 'Galey',
                fontSize: 12,
                color: Colors.grey.shade500)),
        const SizedBox(height: 12),

        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_uid())
              .collection('contrats')
              .orderBy('dateUpload', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()));
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return _EmptyState();
            }
            return Column(
              children: docs
                  .map((d) => _ContratCard(
                      doc: d,
                      onDelete: () => _deleteContrat(context, d)))
                  .toList(),
            );
          },
        ),
      ]),
    );
  }

  Future<void> _deleteContrat(
      BuildContext context, DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text('Supprimer « ${data['nom'] ?? 'ce document'} » ?',
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer',
                  style: TextStyle(
                      fontFamily: 'Galey', color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final path = data['storagePath'] as String?;
      if (path != null && path.isNotEmpty) {
        await FirebaseStorage.instance.ref().child(path).delete();
      }
      await doc.reference.delete();
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ModeleCard extends StatelessWidget {
  final String type;
  final String label;
  final IconData icon;
  final Color color;
  final String desc;

  const _ModeleCard({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
    required this.desc,
  });

  static const _teal = Color(0xFF0C5C6C);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 22, color: _teal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF1F2A2E))),
                      const SizedBox(height: 2),
                      Text(desc,
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 12,
                              color: Colors.grey.shade500)),
                    ]),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Color(0xFF6F767B)),
            ]),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    if (type == 'reservation') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const _ContratReservationFormPage()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bientôt disponible',
                style: TextStyle(fontFamily: 'Galey'))),
      );
    }
  }
}

class _ContratCard extends StatelessWidget {
  final DocumentSnapshot doc;
  final VoidCallback onDelete;

  const _ContratCard({required this.doc, required this.onDelete});

  static const _typeLabels = {
    'reservation': 'Réservation',
    'vente': 'Vente',
    'saillie': 'Saillie',
    'autre': 'Autre',
  };

  static const _typeColors = {
    'reservation': Color(0xFFE0F2F1),
    'vente': Color(0xFFE8F5E9),
    'saillie': Color(0xFFFCE4EC),
    'autre': Color(0xFFF3E5F5),
  };

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final nom = data['nom'] ?? 'Document';
    final type = data['type'] ?? 'autre';
    final ext = (data['ext'] ?? 'pdf').toLowerCase();
    final url = data['url'] as String?;
    final ts = data['dateUpload'] as Timestamp?;
    final date = ts != null
        ? DateFormat('dd/MM/yyyy').format(ts.toDate())
        : '—';

    final isPdf = ext == 'pdf';
    final isImage = ['jpg', 'jpeg', 'png'].contains(ext);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: url != null ? () => _view(context, url, nom, isPdf, isImage) : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _typeColors[type] ?? const Color(0xFFF3E5F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPdf
                      ? Icons.picture_as_pdf_outlined
                      : isImage
                          ? Icons.image_outlined
                          : Icons.insert_drive_file_outlined,
                  size: 22,
                  color: const Color(0xFF0C5C6C),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nom,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Color(0xFF1F2A2E)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _typeColors[type] ?? const Color(0xFFF3E5F5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                              _typeLabels[type] ?? 'Autre',
                              style: const TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0C5C6C))),
                        ),
                        const SizedBox(width: 8),
                        Text(date,
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 11,
                                color: Colors.grey.shade400)),
                      ]),
                    ]),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Colors.redAccent),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _view(BuildContext context, String url, String nom, bool isPdf, bool isImage) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DocumentViewer(
          url: url, nom: nom, isPdf: isPdf, isImage: isImage),
    );
  }
}

class _DocumentViewer extends StatelessWidget {
  final String url;
  final String nom;
  final bool isPdf;
  final bool isImage;

  const _DocumentViewer(
      {required this.url,
      required this.nom,
      required this.isPdf,
      required this.isImage});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Icon(
          isPdf
              ? Icons.picture_as_pdf
              : isImage
                  ? Icons.image
                  : Icons.insert_drive_file,
          size: 48,
          color: const Color(0xFF0C5C6C),
        ),
        const SizedBox(height: 12),
        Text(nom,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        const SizedBox(height: 20),
        if (isPdf)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              icon: const Icon(Icons.print_outlined,
                  color: Colors.white, size: 18),
              label: const Text('Imprimer / Partager',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final resp = await http.get(Uri.parse(url));
                  await Printing.sharePdf(
                      bytes: resp.bodyBytes, filename: '$nom.pdf');
                } catch (_) {}
              },
            ),
          ),
        if (isImage) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6E9E57),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              icon:
                  const Icon(Icons.open_in_new, color: Colors.white, size: 18),
              label: const Text('Voir l\'image',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(
                          backgroundColor: const Color(0xFF0C5C6C),
                          foregroundColor: Colors.white,
                          title: Text(nom,
                              style: const TextStyle(
                                  fontFamily: 'Galey', fontSize: 16))),
                      body: InteractiveViewer(
                        child: Center(
                          child: Image.network(url, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE4E7E2)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            icon: const Icon(Icons.copy_outlined,
                size: 16, color: Color(0xFF6F767B)),
            label: const Text('Copier le lien',
                style: TextStyle(
                    fontFamily: 'Galey',
                    color: Color(0xFF6F767B),
                    fontWeight: FontWeight.w500)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Lien copié',
                      style: TextStyle(fontFamily: 'Galey'))));
            },
          ),
        ),
      ]),
    );
  }
}

class _TypePickerSheet extends StatelessWidget {
  static const _types = [
    (value: 'reservation', label: 'Réservation', icon: Icons.pets_outlined),
    (value: 'vente', label: 'Vente', icon: Icons.handshake_outlined),
    (value: 'saillie', label: 'Saillie extérieure', icon: Icons.favorite_border),
    (value: 'autre', label: 'Autre', icon: Icons.insert_drive_file_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('Type de contrat',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        const SizedBox(height: 16),
        ..._types.map((t) => ListTile(
              leading: Icon(t.icon, color: const Color(0xFF0C5C6C)),
              title: Text(t.label,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 15)),
              onTap: () => Navigator.pop(context, t.value),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            )),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        Icon(Icons.folder_open_outlined,
            size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        const Text('Aucun document stocké',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF1F2A2E))),
        const SizedBox(height: 4),
        Text('Utilisez le bouton + pour importer\nun contrat signé ou scanné.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Galey',
                fontSize: 12,
                color: Colors.grey.shade400)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Formulaire contrat de réservation (existant, accessible depuis le modèle)
// ─────────────────────────────────────────────────────────────────────────────

class _ContratReservationFormPage extends StatefulWidget {
  const _ContratReservationFormPage();

  @override
  State<_ContratReservationFormPage> createState() =>
      _ContratReservationFormPageState();
}

class _ContratReservationFormPageState
    extends State<_ContratReservationFormPage> {
  final _formKey = GlobalKey<FormState>();

  final nomElevageController = TextEditingController();
  final adresseElevageController = TextEditingController();
  final codeISOElevageController = TextEditingController(text: '+33');
  final codeISOClientController = TextEditingController(text: '+33');
  final telephoneElevageController = TextEditingController();
  final siretController = TextEditingController();
  final numeroTVAController = TextEditingController();
  final nomClientController = TextEditingController();
  final adresseClientController = TextEditingController();
  final codePostalVilleController = TextEditingController();
  final telephoneClientController = TextEditingController();
  final emailClientController = TextEditingController();
  final siretClientController = TextEditingController();
  final numeroDossierController = TextEditingController();
  final raceController = TextEditingController();
  final apparenceRaceController = TextEditingController();
  final dateController = TextEditingController();
  final nomMediateurController = TextEditingController();
  final couleurRobeController = TextEditingController();
  final numeroPuceController = TextEditingController();
  final infoComplementaireController = TextEditingController();
  final prixHTController = TextEditingController();
  final prixTTCController = TextEditingController();
  final tvaController = TextEditingController(text: '20.0');
  final arrhesController = TextEditingController();
  final disponibiliteDebutController = TextEditingController();
  final disponibiliteFinController = TextEditingController();
  final nombreMoisController = TextEditingController();
  final lieuSignatureController = TextEditingController();
  final dateSignatureController = TextEditingController();
  final chequeNumeroController = TextEditingController();
  final chequeDateEncaissementController = TextEditingController();
  final virementDateController = TextEditingController();

  String? logoUrl;
  bool isAnimalANaitre = false;
  String? selectedAnimal;
  DateTime? selectedDate;
  bool isLOF = false;
  bool isLOOF = false;
  bool isNonInscritOrigine = false;
  bool isNonRace = false;
  bool isApparenceRace = false;
  bool _isUpdatingHT = false;
  bool _isUpdatingTTC = false;
  String? selectedSexe;
  bool isTvaApplicable = false;
  String? selectedPaymentMethod;

  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg = Color(0xFFF8F8F6);

  @override
  void initState() {
    super.initState();
    prixHTController.addListener(_onHTChanged);
    prixTTCController.addListener(_onTTCChanged);
    _loadUserData();
  }

  @override
  void dispose() {
    for (final c in [
      nomElevageController, adresseElevageController, codeISOElevageController,
      codeISOClientController, telephoneElevageController, siretController,
      numeroTVAController, nomClientController, adresseClientController,
      codePostalVilleController, telephoneClientController, emailClientController,
      siretClientController, numeroDossierController, raceController,
      apparenceRaceController, dateController, nomMediateurController,
      couleurRobeController, numeroPuceController, infoComplementaireController,
      prixHTController, prixTTCController, tvaController, arrhesController,
      disponibiliteDebutController, disponibiliteFinController,
      nombreMoisController, lieuSignatureController, dateSignatureController,
      chequeNumeroController, chequeDateEncaissementController,
      virementDateController,
    ]) c.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    setState(() {
      nomElevageController.text = data['nameElevage'] ?? '';
      adresseElevageController.text = data['adressElevage'] ?? '';
      codeISOElevageController.text = data['codeISOElevage'] ?? '+33';
      telephoneElevageController.text = data['numeroElevage'] ?? '';
      siretController.text = data['siret'] ?? '';
      numeroTVAController.text = data['numeroTVA'] ?? '';
      logoUrl = data['profilePictureUrlElevage'];
    });
  }

  void _onHTChanged() {
    if (!_isUpdatingTTC && isTvaApplicable && prixHTController.text.isNotEmpty) {
      _isUpdatingHT = true;
      final ht = double.tryParse(prixHTController.text) ?? 0;
      final tva = double.tryParse(tvaController.text) ?? 20;
      prixTTCController.text = (ht * (1 + tva / 100)).toStringAsFixed(2);
      _isUpdatingHT = false;
    }
  }

  void _onTTCChanged() {
    if (!_isUpdatingHT && isTvaApplicable && prixTTCController.text.isNotEmpty) {
      _isUpdatingTTC = true;
      final ttc = double.tryParse(prixTTCController.text) ?? 0;
      final tva = double.tryParse(tvaController.text) ?? 20;
      prixHTController.text = (ttc / (1 + tva / 100)).toStringAsFixed(2);
      _isUpdatingTTC = false;
    }
  }

  Future<void> _selectDate(TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: _teal)),
        child: child!,
      ),
    );
    if (picked != null) {
      ctrl.text = DateFormat('dd/MM/yyyy').format(picked);
    }
  }

  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    Uint8List? logoBytes;
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      try {
        final r = await http.get(Uri.parse(logoUrl!));
        if (r.statusCode == 200) logoBytes = r.bodyBytes;
      } catch (_) {}
    }
    final petsMatchLogo = pw.MemoryImage(
        (await rootBundle.load('assets/Logo_petsmatch_fond_blanc.png')).buffer.asUint8List());
    final font = await PdfGoogleFonts.robotoRegular();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context ctx) => pw.Stack(children: [
        pw.Center(child: pw.Opacity(opacity: 0.15,
            child: pw.Image(petsMatchLogo, width: 400, height: 400))),
        pw.Positioned(bottom: 0, left: 0, right: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Image(petsMatchLogo, width: 40, height: 40),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Édité par PETSMATCH', style: pw.TextStyle(fontSize: 7, font: font, fontWeight: pw.FontWeight.bold)),
                pw.Text('15 la ville marchand - 22210 PLUMIEUX - Tél 07 81 03 49 84', style: pw.TextStyle(fontSize: 6, font: font)),
                pw.Text('petsmatch.contact@gmail.com - www.petsmatchapp.com', style: pw.TextStyle(fontSize: 6, font: font)),
                pw.Text('N° SIRET 93134481600018 - NAF 7010Z', style: pw.TextStyle(fontSize: 6, font: font)),
              ]),
            ],
          ),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (logoBytes != null) pw.Image(pw.MemoryImage(logoBytes), width: 60, height: 60),
            pw.SizedBox(width: 16),
            pw.Expanded(flex: 2, child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(nomElevageController.text, style: pw.TextStyle(font: font, fontSize: 9)),
                pw.Text(adresseElevageController.text, style: pw.TextStyle(font: font, fontSize: 9)),
                pw.Text('${codeISOElevageController.text} ${telephoneElevageController.text}', style: pw.TextStyle(font: font, fontSize: 9)),
                if (siretController.text.isNotEmpty) pw.Text('SIRET: ${siretController.text}', style: pw.TextStyle(font: font, fontSize: 9)),
              ],
            )),
            pw.Expanded(flex: 1, child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('CONTRAT', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, font: font)),
                pw.Text('DE', style: pw.TextStyle(fontSize: 14, font: font)),
                pw.Text('RÉSERVATION', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: font)),
              ],
            )),
          ]),
          pw.SizedBox(height: 16),
          pw.Text('Je soussigné(e) ${nomClientController.text}', style: pw.TextStyle(font: font, fontSize: 8)),
          pw.Text('Adresse: ${adresseClientController.text}', style: pw.TextStyle(font: font, fontSize: 8)),
          pw.Text('CP/Ville: ${codePostalVilleController.text}  Tél: ${codeISOClientController.text} ${telephoneClientController.text}  Email: ${emailClientController.text}', style: pw.TextStyle(font: font, fontSize: 8)),
          pw.SizedBox(height: 10),
          pw.Text('Soumet la réservation d\'un ${selectedAnimal ?? '........'} né(e) le ${isAnimalANaitre ? "À naître" : dateController.text}', style: pw.TextStyle(font: font, fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.Text('Race: ${raceController.text}  Sexe: ${selectedSexe ?? '—'}  Couleur: ${couleurRobeController.text}  Puce: ${numeroPuceController.text}', style: pw.TextStyle(font: font, fontSize: 8)),
          pw.SizedBox(height: 10),
          isTvaApplicable
            ? pw.Text('Prix: ${prixHTController.text} € HT + TVA ${tvaController.text}% = ${prixTTCController.text} € TTC', style: pw.TextStyle(font: font, fontSize: 8))
            : pw.Text('Prix: ${prixHTController.text} € NET (TVA non applicable, art. 293B CGI)', style: pw.TextStyle(font: font, fontSize: 8)),
          pw.Text('Arrhes: ${arrhesController.text} €', style: pw.TextStyle(font: font, fontSize: 8)),
          pw.Text('Disponibilité: du ${disponibiliteDebutController.text} au ${disponibiliteFinController.text}', style: pw.TextStyle(font: font, fontSize: 8)),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(), color: PdfColors.grey200),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('CONDITIONS GÉNÉRALES DE RÉSERVATION', style: pw.TextStyle(font: font, fontSize: 7, fontWeight: pw.FontWeight.bold)),
              pw.Text('Le droit de rétractation n\'est pas applicable. Les arrhes sont conservées en cas d\'annulation par l\'acquéreur.', style: pw.TextStyle(font: font, fontSize: 6)),
              pw.Text('Report possible sur ${nombreMoisController.text.isNotEmpty ? nombreMoisController.text : "..."} mois. Validité : 8 jours après signature.', style: pw.TextStyle(font: font, fontSize: 6)),
            ]),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Médiateur: ${nomMediateurController.text}', style: pw.TextStyle(font: font, fontSize: 8)),
          pw.SizedBox(height: 20),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly, children: [
            pw.Column(children: [
              pw.Text('Signature du vendeur', style: pw.TextStyle(font: font, fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 40),
            ]),
            pw.Column(children: [
              pw.Text('Signature de l\'acquéreur', style: pw.TextStyle(font: font, fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('Mention manuscrite : « Bon pour accord. Lu, approuvé et compris »', style: pw.TextStyle(font: font, fontSize: 6)),
            ]),
          ]),
        ]),
      ]),
    ));

    // Page 2 : texte légal
    try {
      final imgData = await rootBundle.load('assets/loi-contrat-reservation.png');
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(pw.MemoryImage(imgData.buffer.asUint8List()), fit: pw.BoxFit.cover),
        ),
      ));
    } catch (_) {}

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Contrat de Réservation',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            _section('Informations éleveur', initiallyExpanded: true, children: [
              _field('Nom de l\'élevage', nomElevageController),
              _field('Adresse', adresseElevageController),
              _field('Téléphone', telephoneElevageController),
              _field('SIRET', siretController),
              _field('Numéro de TVA', numeroTVAController),
            ]),

            _section('Informations client', children: [
              _field('Nom et prénom', nomClientController),
              _field('Adresse', adresseClientController),
              _field('Code postal et ville', codePostalVilleController),
              _field('Téléphone', telephoneClientController),
              _field('Email', emailClientController),
              _field('SIRET (si professionnel)', siretClientController),
            ]),

            _section('Animal & réservation', children: [
              const SizedBox(height: 8),
              // Type animal
              Wrap(spacing: 8, children: ['chien', 'chiot', 'chat', 'chaton'].map((a) =>
                ChoiceChip(
                  label: Text(a[0].toUpperCase() + a.substring(1),
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                          color: selectedAnimal == a ? Colors.white : Colors.black87)),
                  selected: selectedAnimal == a,
                  selectedColor: _green,
                  onSelected: (_) => setState(() => selectedAnimal = a),
                ),
              ).toList()),
              const SizedBox(height: 12),
              Row(children: [
                _checkBox('Né(e) le', !isAnimalANaitre, (v) => setState(() { isAnimalANaitre = !v!; })),
                _checkBox('À naître', isAnimalANaitre, (v) => setState(() { isAnimalANaitre = v!; })),
              ]),
              if (!isAnimalANaitre) _dateField('Date de naissance', dateController),
              Row(children: [
                _checkBox('LOF', isLOF, (v) => setState(() => isLOF = v!)),
                _checkBox('LOOF', isLOOF, (v) => setState(() => isLOOF = v!)),
              ]),
              _field('N° de dossier', numeroDossierController),
              _field('Race', raceController),
              Row(children: [
                _checkBox('Mâle', selectedSexe == 'M', (v) => setState(() => selectedSexe = v! ? 'M' : null)),
                _checkBox('Femelle', selectedSexe == 'F', (v) => setState(() => selectedSexe = v! ? 'F' : null)),
              ]),
              _field('Couleur de robe', couleurRobeController),
              _field('Numéro de puce', numeroPuceController),
              _field('Informations complémentaires', infoComplementaireController),
            ]),

            _section('Prix & arrhes', children: [
              _field('Prix HT (€)', prixHTController, type: TextInputType.number),
              Row(children: [
                _checkBox('TVA applicable', isTvaApplicable, (v) {
                  setState(() {
                    isTvaApplicable = v!;
                    if (!isTvaApplicable) { prixTTCController.clear(); tvaController.text = ''; }
                    else { tvaController.text = '20.0'; _onHTChanged(); }
                  });
                }),
              ]),
              if (isTvaApplicable) ...[
                _field('Taux TVA (%)', tvaController, type: TextInputType.number),
                _field('Prix TTC (€)', prixTTCController, type: TextInputType.number),
              ],
              _field('Montant des arrhes (€)', arrhesController, type: TextInputType.number),
            ]),

            _section('Paiement & dates', children: [
              Wrap(spacing: 8, runSpacing: 4, children: [
                {'value': 'carte', 'label': 'Carte'},
                {'value': 'espece', 'label': 'Espèces'},
                {'value': 'cheque_reception', 'label': 'Chèque (réception)'},
                {'value': 'cheque_delai', 'label': 'Chèque (différé)'},
                {'value': 'virement', 'label': 'Virement'},
              ].map((m) => ChoiceChip(
                label: Text(m['label']!, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: selectedPaymentMethod == m['value'] ? Colors.white : Colors.black87)),
                selected: selectedPaymentMethod == m['value'],
                selectedColor: _teal,
                onSelected: (_) => setState(() => selectedPaymentMethod = m['value']),
              )).toList()),
              if (selectedPaymentMethod == 'cheque_reception' || selectedPaymentMethod == 'cheque_delai')
                _field('Numéro de chèque', chequeNumeroController),
              if (selectedPaymentMethod == 'cheque_delai')
                _dateField('Date d\'encaissement', chequeDateEncaissementController),
              if (selectedPaymentMethod == 'virement')
                _dateField('Date limite virement', virementDateController),
              const SizedBox(height: 8),
              _dateField('Disponibilité début', disponibiliteDebutController),
              _dateField('Date butoir', disponibiliteFinController),
              _field('Report (mois max)', nombreMoisController, type: TextInputType.number),
              _field('Médiateur', nomMediateurController),
              _field('Lieu de signature', lieuSignatureController),
              _dateField('Date de signature', dateSignatureController),
            ]),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.print_outlined, color: Colors.white),
                label: const Text('Générer le contrat PDF',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 15, color: Colors.white)),
                onPressed: _generatePdf,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(String title, {bool initiallyExpanded = false, required List<Widget> children}) =>
    Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          title: Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0C5C6C))),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: children,
        ),
      ),
    );

  Widget _field(String label, TextEditingController ctrl, {TextInputType? type}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _green, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );

  Widget _dateField(String label, TextEditingController ctrl) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        readOnly: true,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _green, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
        onTap: () => _selectDate(ctrl),
      ),
    );

  Widget _checkBox(String label, bool value, ValueChanged<bool?> onChanged) =>
    Expanded(child: Material(
      color: Colors.transparent,
      child: CheckboxListTile(
        dense: true,
        activeColor: _green,
        title: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
        value: value,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
      ),
    ));
}
