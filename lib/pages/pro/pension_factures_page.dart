import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Pension — historique des factures (Phase 2 item 2/4, complément).
class PensionFacturesPage extends StatefulWidget {
  const PensionFacturesPage({super.key});

  @override
  State<PensionFacturesPage> createState() => _PensionFacturesPageState();
}

class _PensionFacturesPageState extends State<PensionFacturesPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  List<Map<String, dynamic>> _factures = [];
  String? _filterStatut; // null = toutes, 'envoyee', 'payee'
  DateTimeRange? _dateRange; // export par plage de dates (Phase 2 item 3/4)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pid = User_Info.activeProfileId;
      final rows = await _supa.from('pension_factures').select()
          .eq('pro_uid', _uid).eq('pro_profile_id', pid)
          .order('date_envoi', ascending: false);
      if (mounted) setState(() { _factures = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _factures;
    if (_filterStatut != null) list = list.where((f) => f['statut'] == _filterStatut).toList();
    if (_dateRange != null) {
      final start = _dateRange!.start;
      final end = _dateRange!.end.add(const Duration(days: 1));
      list = list.where((f) {
        final d = DateTime.tryParse(f['date_envoi']?.toString() ?? '');
        return d != null && !d.isBefore(start) && d.isBefore(end);
      }).toList();
    }
    return list;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _dateRange,
      locale: const Locale('fr'),
    );
    if (picked != null) setState(() => _dateRange = picked);
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

    final headers = ['N°', 'Animal', 'Client', 'Montant', 'Statut', 'Envoyée le', 'Payée le'];
    final rows = list.map((f) {
      final dEnvoi = DateTime.tryParse(f['date_envoi']?.toString() ?? '');
      final dPaie = DateTime.tryParse(f['date_paiement']?.toString() ?? '');
      return [
        f['numero']?.toString() ?? '—',
        f['animal_nom']?.toString() ?? '—',
        f['proprietaire_nom']?.toString() ?? '—',
        '${((f['montant'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} €',
        f['statut'] == 'payee' ? 'Payée' : 'Envoyée',
        dEnvoi != null ? fmtD.format(dEnvoi) : '—',
        dPaie != null ? fmtD.format(dPaie) : '—',
      ];
    }).toList();

    final periode = _dateRange != null
        ? 'du ${fmtD.format(_dateRange!.start)} au ${fmtD.format(_dateRange!.end)}'
        : 'toute la période';

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Export facturation — $periode',
            style: pw.TextStyle(font: fontBold, fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text('${list.length} facture(s) · Total : ${total.toStringAsFixed(2)} € · Payé : ${totalPaye.toStringAsFixed(2)} € · Restant dû : ${(total - totalPaye).toStringAsFixed(2)} €',
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
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0C5C6C)),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.3),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        ),
      ],
    ));

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  Future<void> _marquerPayee(String id) async {
    await _supa.from('pension_factures').update({
      'statut': 'payee',
      'date_paiement': DateTime.now().toIso8601String(),
    }).eq('id', id);
    _load();
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
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes factures',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exporter (PDF)',
            onPressed: list.isEmpty ? null : _exportPdf,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (totalDu > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
                      child: Text('${totalDu.toStringAsFixed(2)} € en attente de paiement',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 14, color: Colors.red.shade800)),
                    ),
                  Row(children: [
                    for (final (key, label) in [
                      (null, 'Toutes'),
                      ('envoyee', 'Impayées'),
                      ('payee', 'Payées'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                          selected: _filterStatut == key,
                          onSelected: (_) => setState(() => _filterStatut = key),
                          selectedColor: _teal.withValues(alpha: 0.15),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _pickDateRange,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _dateRange != null ? _teal : Colors.grey.shade300),
                      ),
                      child: Row(children: [
                        Icon(Icons.date_range_outlined, size: 16,
                            color: _dateRange != null ? _teal : Colors.grey.shade500),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                            _dateRange == null
                                ? 'Filtrer par plage de dates'
                                : '${_fmtDate(_dateRange!.start.toIso8601String())} → ${_fmtDate(_dateRange!.end.toIso8601String())}',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                color: _dateRange != null ? _teal : Colors.grey.shade600))),
                        if (_dateRange != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => setState(() => _dateRange = null),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text('Aucune facture.',
                          style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400))),
                    ),
                  for (final f in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(
                              '${f['animal_nom'] ?? ''} — ${f['proprietaire_nom'] ?? ''}',
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
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: _teal)),
                        const SizedBox(height: 2),
                        Text(
                            f['statut'] == 'payee'
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
                              style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
                            )),
                          if ((f['pdf_url'] as String?)?.isNotEmpty == true && f['statut'] != 'payee')
                            const SizedBox(width: 8),
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
