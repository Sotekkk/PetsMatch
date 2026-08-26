import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';

/// Registre pension — vue individuelle imprimable des entrées/sorties.
/// Reprend les mêmes infos que la fiche d'entrée/sortie du site web
/// (nom, race, identification, infos propriétaire, dates), à partir de
/// la table pension_entrees déjà alimentée par "Nos pensionnaires".
class PensionEntreeSortiePage extends StatefulWidget {
  const PensionEntreeSortiePage({super.key});

  @override
  State<PensionEntreeSortiePage> createState() => _PensionEntreeSortiePageState();
}

const Map<String, String> _kEspLabels = {
  'chien': 'Chien', 'chat': 'Chat', 'lapin': 'Lapin', 'oiseau': 'Oiseau',
  'cheval': 'Cheval', 'nac': 'NAC', 'ovin': 'Ovin', 'caprin': 'Caprin', 'porcin': 'Porc',
};
String _espLabel(String e) => _kEspLabels[e] ?? e;

class _PensionEntreeSortiePageState extends State<PensionEntreeSortiePage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg = Color(0xFFF8F8F6);

  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _entrees = [];
  bool _loading = true;
  bool _exporting = false;
  String _filtreStatut = 'tous'; // tous / en_pension / sorti
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pid = User_Info.activeProfileId;
      var q = _supa.from('pension_entrees').select().eq('pro_uid', _uid);
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final rows = await q.order('date_entree', ascending: false);
      if (mounted) {
        setState(() {
          _entrees = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _entrees;
    if (_filtreStatut != 'tous') {
      list = list.where((e) => e['statut'] == _filtreStatut).toList();
    }
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) {
        final nom  = (e['animal_nom'] ?? '').toString().toLowerCase();
        final race = (e['race'] ?? '').toString().toLowerCase();
        final prop = (e['proprietaire_nom'] ?? '').toString().toLowerCase();
        return nom.contains(q) || race.contains(q) || prop.contains(q);
      }).toList();
    }
    return list;
  }

  static String _fmtDate(String? s) {
    if (s == null || s.isEmpty) return '—';
    final d = DateTime.tryParse(s);
    return d != null ? DateFormat('dd/MM/yyyy').format(d) : s;
  }

  // ── Impression : fiche individuelle ─────────────────────────────────────────

  Future<void> _printFiche(Map<String, dynamic> e) async {
    try {
      final font     = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      final logo = pw.MemoryImage(
          (await rootBundle.load('assets/Logo_petsmatch_fond_blanc.png')).buffer.asUint8List());
      final statut = (e['statut'] as String?) ?? 'en_pension';

      pw.Widget infoRow(String label, String value) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
              pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 9)),
            ]),
          );

      pw.Widget section(String title, List<List<String>> rows) => pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 10, color: const PdfColor.fromInt(0xFF0C5C6C))),
              pw.SizedBox(height: 6),
              for (final r in rows) infoRow(r[0], r[1]),
            ]),
          );

      pw.Widget dateBox(String label, String value) => pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                  borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(children: [
                pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                pw.SizedBox(height: 4),
                pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 14, color: const PdfColor.fromInt(0xFF0C5C6C))),
              ]),
            ),
          );

      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Image(logo, width: 26, height: 26),
            pw.Text('Édité le ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
          ]),
          pw.SizedBox(height: 10),
          pw.Text((e['animal_nom'] as String?) ?? '', style: pw.TextStyle(font: fontBold, fontSize: 18)),
          pw.Text("Fiche d'entrée / sortie — pension",
              style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 14),
          section('Animal', [
            ['Espèce', _espLabel((e['espece'] as String?) ?? '')],
            ['Race', (e['race'] as String?)?.isNotEmpty == true ? e['race'] as String : '—'],
            ['Identification', (e['puce'] as String?)?.isNotEmpty == true ? e['puce'] as String : '—'],
          ]),
          pw.SizedBox(height: 10),
          section('Propriétaire', [
            ['Nom', (e['proprietaire_nom'] as String?)?.isNotEmpty == true ? e['proprietaire_nom'] as String : '—'],
            ['Téléphone', (e['proprietaire_contact'] as String?)?.isNotEmpty == true ? e['proprietaire_contact'] as String : '—'],
            ['Email', (e['proprietaire_email'] as String?)?.isNotEmpty == true ? e['proprietaire_email'] as String : '—'],
          ]),
          pw.SizedBox(height: 14),
          pw.Row(children: [
            dateBox("Date d'entrée", _fmtDate(e['date_entree'] as String?)),
            pw.SizedBox(width: 10),
            dateBox(
              statut == 'sorti' ? 'Date de sortie' : 'Sortie prévue',
              _fmtDate((statut == 'sorti' ? e['date_sortie_effective'] : e['date_sortie_prevue']) as String?),
            ),
          ]),
        ]),
      ));

      await Printing.layoutPdf(onLayout: (_) async => pdf.save());
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur : $err', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  // ── Export : registre complet ────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    if (_filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun animal à exporter', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _exporting = true);
    try {
      final font     = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();
      final logo = pw.MemoryImage(
          (await rootBundle.load('assets/Logo_petsmatch_fond_blanc.png')).buffer.asUint8List());

      final headers = ['Nom', 'Espèce', 'Race', 'Identification', 'Propriétaire', 'Entrée', 'Sortie', 'Statut'];
      final rows = _filtered.map((e) {
        final statut = (e['statut'] as String?) ?? 'en_pension';
        return [
          (e['animal_nom'] as String?) ?? '—',
          _espLabel((e['espece'] as String?) ?? ''),
          (e['race'] as String?) ?? '—',
          (e['puce'] as String?) ?? '—',
          (e['proprietaire_nom'] as String?) ?? '—',
          _fmtDate(e['date_entree'] as String?),
          _fmtDate((statut == 'sorti' ? e['date_sortie_effective'] : e['date_sortie_prevue']) as String?),
          statut == 'sorti' ? 'Sorti' : 'Présent',
        ];
      }).toList();

      final pdf = pw.Document();
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Image(logo, width: 32, height: 32),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('REGISTRE ENTRÉE / SORTIE', style: pw.TextStyle(font: fontBold, fontSize: 12)),
              pw.Text('Édité le ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                  style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
            ]),
          ]),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 0.5),
          pw.SizedBox(height: 4),
        ]),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0C5C6C)),
            cellStyle: pw.TextStyle(font: font, fontSize: 7),
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          ),
        ],
      ));

      await Printing.layoutPdf(onLayout: (_) async => pdf.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur export : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Entrée - Sortie',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exporter en PDF',
            onPressed: _exporting ? null : _exportPdf,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Rechercher par animal, race, propriétaire…',
                      hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _teal, width: 1.5)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    for (final f in const [['tous', 'Tous'], ['en_pension', 'Présents'], ['sorti', 'Sortis']])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f[1], style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                          selected: _filtreStatut == f[0],
                          selectedColor: _teal,
                          labelStyle: TextStyle(
                              fontFamily: 'Galey', fontSize: 12,
                              color: _filtreStatut == f[0] ? Colors.white : const Color(0xFF1F2A2E),
                              fontWeight: FontWeight.w600),
                          backgroundColor: Colors.white,
                          side: BorderSide(color: _filtreStatut == f[0] ? _teal : Colors.grey.shade300),
                          onSelected: (_) => setState(() => _filtreStatut = f[0]),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _filtered.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          Center(child: Text('Aucun animal dans ce registre',
                              style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _EntreeSortieCard(
                            entree: _filtered[i],
                            onTap: () => _showDetail(_filtered[i]),
                            onPrint: () => _printFiche(_filtered[i]),
                          ),
                        ),
                ),
              ]),
            ),
    );
  }

  void _showDetail(Map<String, dynamic> e) {
    final statut = (e['statut'] as String?) ?? 'en_pension';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text((e['animal_nom'] as String?) ?? '',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: statut == 'sorti' ? Colors.blue.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(statut == 'sorti' ? 'Sorti' : 'Présent',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700,
                      color: statut == 'sorti' ? Colors.blue.shade700 : _green)),
            ),
          ]),
          const SizedBox(height: 14),
          for (final row in [
            ['Espèce', _espLabel((e['espece'] as String?) ?? '')],
            ['Race', (e['race'] as String?) ?? ''],
            ['Identification', (e['puce'] as String?) ?? ''],
            ['Propriétaire', (e['proprietaire_nom'] as String?) ?? ''],
            ['Téléphone', (e['proprietaire_contact'] as String?) ?? ''],
            ['Email', (e['proprietaire_email'] as String?) ?? ''],
            ["Date d'entrée", _fmtDate(e['date_entree'] as String?)],
            [statut == 'sorti' ? 'Date de sortie' : 'Sortie prévue',
              _fmtDate((statut == 'sorti' ? e['date_sortie_effective'] : e['date_sortie_prevue']) as String?)],
          ])
            if (row[1].isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 130, child: Text(row[0],
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500))),
                  Expanded(child: Text(row[1],
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
                ]),
              ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); _printFiche(e); },
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Imprimer la fiche',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _EntreeSortieCard extends StatelessWidget {
  final Map<String, dynamic> entree;
  final VoidCallback onTap;
  final VoidCallback onPrint;
  const _EntreeSortieCard({required this.entree, required this.onTap, required this.onPrint});

  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  @override
  Widget build(BuildContext context) {
    final statut = (entree['statut'] as String?) ?? 'en_pension';
    final espece = (entree['espece'] as String?) ?? '';
    final race   = (entree['race'] as String?) ?? '';
    final inPension = statut != 'sorti';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: inPension ? _teal.withValues(alpha: 0.18) : const Color(0xFFE5E7EB)),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: inPension ? _teal.withValues(alpha: 0.08) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.pets, color: _teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text((entree['animal_nom'] as String?) ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: inPension ? Colors.green.shade50 : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(inPension ? 'Présent' : 'Sorti',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700,
                            color: inPension ? _green : Colors.blue.shade700)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                  [_espLabel(espece), if (race.isNotEmpty) race].join(' · '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                ),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.print_outlined, color: _teal, size: 20),
              tooltip: 'Imprimer la fiche',
              onPressed: onPrint,
            ),
          ]),
        ),
      ),
    );
  }
}
