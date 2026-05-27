import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page Registre Entrées / Sorties
// ─────────────────────────────────────────────────────────────────────────────

class RegistreEntreeSortiePage extends StatefulWidget {
  const RegistreEntreeSortiePage({super.key});

  @override
  State<RegistreEntreeSortiePage> createState() =>
      _RegistreEntreeSortiePageState();
}

class _RegistreEntreeSortiePageState extends State<RegistreEntreeSortiePage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg    = Color(0xFFF8F8F6);

  String? _filterEspece;
  String? _filterStatut; // null = tous

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  final _supa = Supabase.instance.client;

  int get _activeFilters =>
      (_filterEspece != null ? 1 : 0) + (_filterStatut != null ? 1 : 0);

  Future<void> _openFilterSheet(List<Map<String, dynamic>> docs) async {
    final availableEspeces = docs
        .map((d) => d['espece'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toSet();

    if (!mounted) return;
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
                  style: TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w700, fontSize: 17)),
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
            Wrap(spacing: 8, runSpacing: 8,
                children: kSpeciesData.where((sp) =>
                    sp.value == 'tous' || availableEspeces.contains(sp.value))
                    .map((sp) {
                  final sel = sp.value == 'tous' ? tmpEspece == null : tmpEspece == sp.value;
                  return GestureDetector(
                    onTap: () {
                      final v = sp.value == 'tous' ? null : sp.value;
                      setSheet(() => tmpEspece = v);
                      setState(() => _filterEspece = v);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? sp.color : Colors.transparent,
                        border: Border.all(color: sel ? sp.color : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (sp.value != 'tous') ...[
                          speciesIcon(sp.value, 13, sel ? Colors.white : sp.color),
                          const SizedBox(width: 5),
                        ],
                        Text(sp.label,
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                color: sel ? Colors.white : Colors.black87,
                                fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                      ]),
                    ),
                  );
                }).toList()),
            const SizedBox(height: 18),
            const Text('Statut', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6F767B))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8,
                children: [
                  (null, 'Tous', Icons.list, Colors.grey.shade300),
                  ('present', 'Présents', Icons.home_outlined, const Color(0xFF6E9E57)),
                  ('sorti', 'Sortis', Icons.logout_outlined, const Color(0xFF0C5C6C)),
                  ('decede', 'Décédés', Icons.close, Colors.redAccent),
                ].map((t) {
                  final sel = tmpStatut == t.$1;
                  final color = sel
                      ? (t.$1 == null ? Colors.grey.shade700 : t.$3 == Icons.home_outlined
                          ? const Color(0xFF6E9E57)
                          : t.$1 == 'sorti' ? const Color(0xFF0C5C6C) : Colors.redAccent)
                      : Colors.grey.shade700;
                  return GestureDetector(
                    onTap: () {
                      setSheet(() => tmpStatut = t.$1);
                      setState(() => _filterStatut = t.$1);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? t.$4.withValues(alpha: 0.15) : Colors.transparent,
                        border: Border.all(color: sel ? t.$4 : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(t.$3, size: 13, color: color),
                        const SizedBox(width: 4),
                        Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                            color: color,
                            fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                      ]),
                    ),
                  );
                }).toList()),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _exportPdf(List<Map<String, dynamic>> docs) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fmt = DateFormat('dd/MM/yyyy');
    final logo = pw.MemoryImage(
        (await rootBundle.load('assets/Logo_petsmatch_fond_blanc.png')).buffer.asUint8List());

    final headers = ['Nom', 'Espèce', 'Sexe', 'Identification', 'Né(e) le',
      'Date entrée', 'Provenance', 'Statut', 'Date sortie', 'Destination'];

    final rows = docs.map((d) {
      String fmtIso(String key) {
        final iso = d[key] as String?;
        if (iso == null || iso.isEmpty) return '—';
        final dt = DateTime.tryParse(iso);
        return dt != null ? fmt.format(dt) : '—';
      }
      final statut = d['statut'] as String? ?? 'present';
      return [
        d['nom'] ?? '—',
        _espLabel(d['espece'] ?? ''),
        d['sexe'] ?? '—',
        d['identification'] ?? '—',
        fmtIso('date_naissance'),
        fmtIso('date_entree'),
        [d['provenance_nom'], d['provenance_qualite']].where((v) => v != null && v.toString().isNotEmpty).join(' / '),
        statut == 'present' ? 'Présent' : statut == 'sorti' ? 'Sorti' : 'Décédé',
        fmtIso('date_sortie'),
        [d['destinataire_nom'], d['destinataire_adresse']].where((v) => v != null && v.toString().isNotEmpty).join(' / '),
      ];
    }).toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Image(logo, width: 32, height: 32),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('REGISTRE DES ENTRÉES ET SORTIES',
                style: pw.TextStyle(font: fontBold, fontSize: 12)),
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
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(0.8),
            2: const pw.FlexColumnWidth(0.6),
            3: const pw.FlexColumnWidth(1.0),
            4: const pw.FlexColumnWidth(0.8),
            5: const pw.FlexColumnWidth(0.8),
            6: const pw.FlexColumnWidth(1.4),
            7: const pw.FlexColumnWidth(0.7),
            8: const pw.FlexColumnWidth(0.8),
            9: const pw.FlexColumnWidth(1.5),
          },
        ),
      ],
    ));

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supa
          .from('animaux')
          .stream(primaryKey: ['id'])
          .eq('uid_eleveur', _uid),
      builder: (ctx, snap) {
        var allDocs = snap.data ?? [];
        allDocs = List.from(allDocs)..sort((a, b) {
          final ta = DateTime.tryParse(a['date_entree'] as String? ?? '')?.millisecondsSinceEpoch ?? 0;
          final tb = DateTime.tryParse(b['date_entree'] as String? ?? '')?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });

        var docs = allDocs;
        if (_filterEspece != null) {
          docs = docs.where((d) => d['espece'] == _filterEspece).toList();
        }
        if (_filterStatut != null) {
          docs = docs.where((d) {
            final st = d['statut'] as String? ?? 'present';
            return st == _filterStatut;
          }).toList();
        }

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            title: const Text('Registre Entrées / Sorties',
                style: TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 17)),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Exporter PDF',
                onPressed: allDocs.isEmpty
                    ? null
                    : () => _exportPdf(docs.isEmpty ? allDocs : docs),
              ),
              Stack(alignment: Alignment.topRight, children: [
                IconButton(
                  icon: const Icon(Icons.tune_outlined),
                  onPressed: () => _openFilterSheet(allDocs),
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
          body: snap.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : docs.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                      itemCount: docs.length,
                      itemBuilder: (_, i) => _EntreeCard(
                        data: docs[i],
                        onTap: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => _RegistreEditSheet(
                            animalId: docs[i]['id'] as String,
                            animalData: docs[i],
                          ),
                        ),
                        onFicheTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AnimalFichePage(
                            animalId: docs[i]['id'] as String,
                            initialData: docs[i],
                          ),
                        )),
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.swap_horiz_outlined, size: 56, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      const Text('Aucun animal dans le registre',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
              fontSize: 15, color: Color(0xFF1F2A2E))),
      const SizedBox(height: 4),
      Text('Remplissez la section "Registre Entrée / Sortie"\ndans la fiche de chaque animal.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
    ]),
  );
}

// ── Carte animal dans le registre ─────────────────────────────────────────────

class _EntreeCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onFicheTap;
  const _EntreeCard({required this.data, required this.onTap, required this.onFicheTap});

  static const _statutColors = {
    'present': Color(0xFFE8F5E9),
    'sorti':   Color(0xFFE3F2FD),
    'decede':  Color(0xFFFFEBEE),
  };
  static const _statutLabels = {
    'present': 'Présent',
    'sorti':   'Sorti',
    'decede':  'Décédé',
  };
  static const _statutIcons = {
    'present': Icons.home_outlined,
    'sorti':   Icons.logout_outlined,
    'decede':  Icons.close,
  };

  @override
  Widget build(BuildContext context) {
    final nom      = data['nom'] as String? ?? '—';
    final espece   = data['espece'] as String? ?? '';
    final sexe     = data['sexe'] as String? ?? '';
    final ident    = data['identification'] as String? ?? '';
    final statut   = data['statut'] as String? ?? 'present';
    final fmt      = DateFormat('dd/MM/yyyy');
    String fmtIso(String key) {
      final iso = data[key] as String?;
      if (iso == null || iso.isEmpty) return '—';
      final dt = DateTime.tryParse(iso);
      return dt != null ? fmt.format(dt) : '—';
    }

    final bgColor = _statutColors[statut] ?? const Color(0xFFE8F5E9);

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
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: bgColor, borderRadius: BorderRadius.circular(10)),
                child: speciesIcon(espece, 22, const Color(0xFF0C5C6C)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(nom,
                      style: const TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w700, fontSize: 14,
                          color: Color(0xFF1F2A2E)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                        color: bgColor, borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_statutIcons[statut] ?? Icons.circle, size: 10,
                          color: const Color(0xFF0C5C6C)),
                      const SizedBox(width: 3),
                      Text(_statutLabels[statut] ?? statut,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 10,
                              fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 4),
                // Row 1: espèce + sexe + ident
                Text(
                  [_espLabel(espece), if (sexe.isNotEmpty) sexe, if (ident.isNotEmpty) ident].join(' · '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 4),
                // Row 2: dates
                Row(children: [
                  _dateChip(Icons.login_outlined, 'Entrée', fmtIso('date_entree')),
                  if (statut != 'present') ...[
                    const SizedBox(width: 10),
                    _dateChip(
                      statut == 'decede' ? Icons.close : Icons.logout_outlined,
                      statut == 'decede' ? 'Décès' : 'Sortie',
                      fmtIso('date_sortie'),
                    ),
                  ],
                ]),
                // Provenance
                if ((data['provenance_nom'] ?? '').isNotEmpty ||
                    (data['provenance_qualite'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Provenance : ${[data['provenance_nom'], data['provenance_qualite']].where((v) => v != null && v.toString().isNotEmpty).join(' / ')}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade400),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ])),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF6F767B)),
                onPressed: onFicheTap,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Fiche complète',
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

String _espLabel(String e) {
  const m = {
    'chien': 'Chien', 'chat': 'Chat', 'cheval': 'Cheval', 'lapin': 'Lapin',
    'ovin': 'Ovin', 'caprin': 'Caprin', 'porcin': 'Porcin', 'nac': 'NAC',
    'oiseau': 'Oiseau', 'autre': 'Autre',
  };
  return m[e] ?? e;
}

// ── Bottom sheet édition registre ─────────────────────────────────────────────

class _RegistreEditSheet extends StatefulWidget {
  final String animalId;
  final Map<String, dynamic> animalData;
  const _RegistreEditSheet({required this.animalId, required this.animalData});

  @override
  State<_RegistreEditSheet> createState() => _RegistreEditSheetState();
}

class _RegistreEditSheetState extends State<_RegistreEditSheet> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  late String  _statut;
  DateTime?    _dateEntree;
  String       _provenanceQualite = '';
  late final TextEditingController _provenanceNomCtrl;
  late final TextEditingController _provenanceAdresseCtrl;
  late final TextEditingController _importationRefCtrl;
  DateTime?    _dateSortie;
  String       _destinataireQualite = '';
  late final TextEditingController _destinataireNomCtrl;
  late final TextEditingController _destinataireAdresseCtrl;
  String       _causeMort = '';
  bool _saving = false;
  String? _nomElevage;
  String? _adresseElevage;

  final _fmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    final d = widget.animalData;
    _statut             = d['statut'] as String? ?? 'present';
    _dateEntree         = DateTime.tryParse(d['date_entree'] as String? ?? '');
    _provenanceQualite  = d['provenance_qualite'] as String? ?? '';
    _provenanceNomCtrl  = TextEditingController(text: d['provenance_nom'] as String? ?? '');
    _provenanceAdresseCtrl = TextEditingController(text: d['provenance_adresse'] as String? ?? '');
    _importationRefCtrl = TextEditingController(text: d['importation_ref'] as String? ?? '');
    _dateSortie         = DateTime.tryParse(d['date_sortie'] as String? ?? '');
    _destinataireQualite= d['destinataire_qualite'] as String? ?? '';
    _destinataireNomCtrl= TextEditingController(text: d['destinataire_nom'] as String? ?? '');
    _destinataireAdresseCtrl = TextEditingController(text: d['destinataire_adresse'] as String? ?? '');
    _causeMort          = d['cause_mort'] as String? ?? '';
    _loadEleveurProfile();
  }

  @override
  void dispose() {
    _provenanceNomCtrl.dispose();
    _provenanceAdresseCtrl.dispose();
    _importationRefCtrl.dispose();
    _destinataireNomCtrl.dispose();
    _destinataireAdresseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEleveurProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profil = await Supabase.instance.client
          .from('users')
          .select('name_elevage, rue_elevage, ville_elevage')
          .eq('uid', uid)
          .maybeSingle();
      if (profil != null && mounted) {
        final rue    = profil['rue_elevage']   as String? ?? '';
        final ville  = profil['ville_elevage'] as String? ?? '';
        final adresse = [rue, ville].where((s) => s.isNotEmpty).join(', ');
        setState(() {
          _nomElevage     = profil['name_elevage'] as String?;
          _adresseElevage = adresse.isNotEmpty ? adresse : null;
        });
      }
    } catch (_) {}
  }

  Widget _buildMereInfo() {
    final nomMere  = widget.animalData['nom_mere']  as String? ?? '';
    final puceMere = widget.animalData['puce_mere'] as String? ?? '';
    if (nomMere.isEmpty && puceMere.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F8EE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFA7C79A)),
      ),
      child: Row(children: [
        const Icon(Icons.female, size: 16, color: Color(0xFF6E9E57)),
        const SizedBox(width: 8),
        Expanded(child: Text(
          'Mère : ${nomMere.isNotEmpty ? nomMere : '—'}'
          '${puceMere.isNotEmpty ? ' · Puce $puceMere' : ''}',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF4A7A3A)),
        )),
      ]),
    );
  }

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime> onPicked) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: _teal)),
        child: child!,
      ),
    );
    if (d != null) onPicked(d);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('animaux').update({
        'statut':               _statut,
        'date_entree':          _dateEntree?.toIso8601String(),
        'provenance_qualite':   _provenanceQualite,
        'provenance_nom':       _provenanceNomCtrl.text.trim(),
        'provenance_adresse':   _provenanceAdresseCtrl.text.trim(),
        'importation_ref':      _importationRefCtrl.text.trim(),
        'date_sortie':          _dateSortie?.toIso8601String(),
        'destinataire_qualite': _statut == 'sorti' ? _destinataireQualite : '',
        'destinataire_nom':     _statut == 'sorti' ? _destinataireNomCtrl.text.trim() : '',
        'destinataire_adresse': _statut == 'sorti' ? _destinataireAdresseCtrl.text.trim() : '',
        'cause_mort':           _statut == 'decede' ? _causeMort : '',
        'updated_at':           DateTime.now().toIso8601String(),
      }).eq('id', widget.animalId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur : $e',
                style: const TextStyle(fontFamily: 'Galey'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom = widget.animalData['nom'] as String? ?? '—';
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
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.white38,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom,
                    style: const TextStyle(fontFamily: 'Galey',
                        fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const Text('Registre Entrée / Sortie',
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

          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [

                // ── Statut ────────────────────────────────────────────────────
                _sectionTitle('Statut'),
                const SizedBox(height: 10),
                _card([
                  Row(children: [
                    _statutChip('present', 'Présent', _green),
                    const SizedBox(width: 8),
                    _statutChip('sorti',   'Sorti',   _teal),
                    const SizedBox(width: 8),
                    _statutChip('decede',  'Décédé',  Colors.redAccent),
                  ]),
                ]),
                const SizedBox(height: 16),

                // ── Entrée ────────────────────────────────────────────────────
                _sectionTitle('Entrée'),
                const SizedBox(height: 10),
                _card([
                  _datePicker('Date d\'entrée', _dateEntree, (d) => setState(() => _dateEntree = d)),
                  const SizedBox(height: 12),
                  _dropdownField(
                    'Qualité du fournisseur',
                    _provenanceQualite,
                    const ['', 'naissance', 'eleveur', 'particulier', 'refuge', 'importation', 'autre'],
                    const ['—', 'Naissance dans l\'élevage', 'Éleveur', 'Particulier',
                        'Refuge / Association', 'Importation', 'Autre'],
                    (v) {
                      setState(() => _provenanceQualite = v ?? '');
                      if (v == 'naissance') {
                        if (_provenanceNomCtrl.text.isEmpty && (_nomElevage?.isNotEmpty ?? false)) {
                          _provenanceNomCtrl.text = _nomElevage!;
                        }
                        if (_provenanceAdresseCtrl.text.isEmpty && (_adresseElevage?.isNotEmpty ?? false)) {
                          _provenanceAdresseCtrl.text = _adresseElevage!;
                        }
                        if (_dateEntree == null) {
                          final dn = widget.animalData['date_naissance'] as String?;
                          final parsed = dn != null ? DateTime.tryParse(dn) : null;
                          if (parsed != null) setState(() => _dateEntree = parsed);
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _textField('Nom / Élevage du fournisseur', _provenanceNomCtrl),
                  const SizedBox(height: 10),
                  _textField('Adresse du fournisseur', _provenanceAdresseCtrl),
                  if (_provenanceQualite == 'naissance') _buildMereInfo(),
                  if (_provenanceQualite == 'importation') ...[
                    const SizedBox(height: 10),
                    _textField('Référence justificatif importation', _importationRefCtrl),
                  ],
                ]),
                const SizedBox(height: 16),

                // ── Sortie / Décès ────────────────────────────────────────────
                if (_statut != 'present') ...[
                  _sectionTitle(_statut == 'decede' ? 'Décès' : 'Sortie'),
                  const SizedBox(height: 10),
                  _card([
                    _datePicker(
                      _statut == 'decede' ? 'Date de décès' : 'Date de sortie',
                      _dateSortie,
                      (d) => setState(() => _dateSortie = d),
                    ),
                    if (_statut == 'sorti') ...[
                      const SizedBox(height: 12),
                      _dropdownField(
                        'Qualité du destinataire',
                        _destinataireQualite,
                        const ['', 'eleveur', 'particulier', 'animalerie', 'refuge', 'autre'],
                        const ['—', 'Éleveur', 'Particulier', 'Animalerie', 'Refuge', 'Autre'],
                        (v) => setState(() => _destinataireQualite = v ?? ''),
                      ),
                      const SizedBox(height: 10),
                      _textField('Nom / Élevage du destinataire', _destinataireNomCtrl),
                      const SizedBox(height: 10),
                      _textField('Adresse du destinataire', _destinataireAdresseCtrl),
                    ],
                    if (_statut == 'decede') ...[
                      const SizedBox(height: 12),
                      _dropdownField(
                        'Cause du décès',
                        _causeMort,
                        const ['', 'maladie', 'accident', 'naturelle', 'euthanasie', 'autre'],
                        const ['—', 'Maladie', 'Accident', 'Mort naturelle', 'Euthanasie', 'Autre'],
                        (v) => setState(() => _causeMort = v ?? ''),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),
                ],

                // ── Bouton enregistrer ─────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Enregistrer',
                            style: TextStyle(fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 15, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
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
          child: Center(
            child: Text(label,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                    color: active ? Colors.white : Colors.black87)),
          ),
        ),
      ),
    );
  }

  Widget _datePicker(String label, DateTime? value, ValueChanged<DateTime> onPicked) {
    return GestureDetector(
      onTap: () => _pickDate(value, onPicked),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
              color: value != null ? _teal : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 15,
              color: value != null ? _teal : Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value != null ? _fmt.format(value) : label,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: value != null ? const Color(0xFF1F2A2E) : Colors.grey),
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: () => onPicked(value), // re-tap to clear handled elsewhere
              child: const Icon(Icons.edit_outlined, size: 14, color: Colors.grey),
            ),
        ]),
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl) => TextFormField(
    controller: ctrl,
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

  Widget _dropdownField(String label, String value, List<String> values,
      List<String> labels, ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String>(
        value: value.isEmpty ? '' : value,
        isExpanded: true,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
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
        items: List.generate(values.length, (i) => DropdownMenuItem(
          value: values[i],
          child: Text(labels[i],
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
        )),
        onChanged: onChanged,
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
