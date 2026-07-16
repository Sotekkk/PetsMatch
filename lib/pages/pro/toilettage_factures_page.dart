import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Toiletteur — factures (montant simple, pas d'acompte/solde), sur le
/// modèle de taxi_factures_page.dart. Gatée hasFacturation (formule Pro+).
class ToilettageFacturesPage extends StatefulWidget {
  const ToilettageFacturesPage({super.key});

  @override
  State<ToilettageFacturesPage> createState() => _ToilettageFacturesPageState();
}

class _ToilettageFacturesPageState extends State<ToilettageFacturesPage> {
  static const _orange = Color(0xFFFFB74D);
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  List<Map<String, dynamic>> _factures = [];
  String? _filterStatut;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pid = User_Info.activeProfileId;
      final rows = await _supa.from('toilettage_factures').select()
          .eq('pro_uid', _uid).eq('pro_profile_id', pid)
          .order('date_envoi', ascending: false);
      if (mounted) setState(() { _factures = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered =>
      _filterStatut == null ? _factures : _factures.where((f) => f['statut'] == _filterStatut).toList();

  Future<void> _marquerPayee(String id) async {
    await _supa.from('toilettage_factures').update({
      'statut': 'payee',
      'date_paiement': DateTime.now().toIso8601String(),
    }).eq('id', id);
    _load();
  }

  Future<void> _exportPdf() async {
    final list = _filtered;
    if (list.isEmpty) return;
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fmtD = DateFormat('dd/MM/yyyy');
    final total = list.fold<double>(0, (s, f) => s + ((f['montant'] as num?)?.toDouble() ?? 0));
    final totalPaye = list.where((f) => f['statut'] == 'payee')
        .fold<double>(0, (s, f) => s + ((f['montant'] as num?)?.toDouble() ?? 0));

    final headers = ['N°', 'Client', 'Montant', 'Statut', 'Envoyée le', 'Payée le'];
    final rows = list.map((f) {
      final dEnvoi = DateTime.tryParse(f['date_envoi']?.toString() ?? '');
      final dPaie = DateTime.tryParse(f['date_paiement']?.toString() ?? '');
      return [
        f['numero']?.toString() ?? '—',
        f['client_nom']?.toString() ?? '—',
        '${((f['montant'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} €',
        f['statut'] == 'payee' ? 'Payée' : 'Envoyée',
        dEnvoi != null ? fmtD.format(dEnvoi) : '—',
        dPaie != null ? fmtD.format(dPaie) : '—',
      ];
    }).toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Export facturation toiletteur', style: pw.TextStyle(font: fontBold, fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text('${list.length} facture(s) · Total : ${total.toStringAsFixed(2)} € · Payé : ${totalPaye.toStringAsFixed(2)} €',
            style: pw.TextStyle(font: font, fontSize: 11)),
        pw.SizedBox(height: 12),
      ]),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
          cellStyle: pw.TextStyle(font: font, fontSize: 9),
          cellAlignments: {for (var i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft},
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFFB74D)),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        ),
      ],
    ));

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '?';
    return '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final totalDu = _factures.where((f) => f['statut'] == 'envoyee')
        .fold<double>(0, (s, f) => s + ((f['montant'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        title: const Text('Mes factures', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Exporter (PDF)', onPressed: list.isEmpty ? null : _exportPdf),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : RefreshIndicator(
              onRefresh: _load,
              color: _orange,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (totalDu > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
                      child: Text('${totalDu.toStringAsFixed(2)} € en attente de paiement',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.red.shade800)),
                    ),
                  Row(children: [
                    for (final (key, label) in [(null, 'Toutes'), ('envoyee', 'Impayées'), ('payee', 'Payées')])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                          selected: _filterStatut == key,
                          onSelected: (_) => setState(() => _filterStatut = key),
                          selectedColor: _orange.withValues(alpha: 0.15),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text('Aucune facture.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400))),
                    ),
                  for (final f in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(f['client_nom']?.toString() ?? '',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: f['statut'] == 'payee' ? const Color(0xFF6E9E57).withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(f['statut'] == 'payee' ? 'Payée' : 'Envoyée',
                                style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                                    color: f['statut'] == 'payee' ? const Color(0xFF6E9E57) : Colors.orange.shade800)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text('${((f['montant'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} € · n° ${f['numero'] ?? ''}',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: _orange)),
                        const SizedBox(height: 2),
                        Text(f['statut'] == 'payee'
                                ? 'Envoyée le ${_fmtDate(f['date_envoi']?.toString())} · payée le ${_fmtDate(f['date_paiement']?.toString())}'
                                : 'Envoyée le ${_fmtDate(f['date_envoi']?.toString())}',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 10),
                        Row(children: [
                          if ((f['pdf_url'] as String?)?.isNotEmpty == true)
                            Expanded(child: OutlinedButton.icon(
                              onPressed: () => launchUrl(Uri.parse(f['pdf_url'] as String), mode: LaunchMode.externalApplication),
                              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                              label: const Text('PDF', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                              style: OutlinedButton.styleFrom(foregroundColor: _orange, side: const BorderSide(color: _orange)),
                            )),
                          if ((f['pdf_url'] as String?)?.isNotEmpty == true && f['statut'] != 'payee') const SizedBox(width: 8),
                          if (f['statut'] != 'payee')
                            Expanded(child: ElevatedButton.icon(
                              onPressed: () => _marquerPayee(f['id'].toString()),
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('Marquer payée', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6E9E57), foregroundColor: Colors.white),
                            )),
                        ]),
                      ]),
                    ),
                ],
              ),
            ),
    );
  }
}
