import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:PetsMatch/utils/plan_template_labels.dart';

// PLN05 — impression protocole template
// PLN06 — impression planning du jour avec cases à cocher

class PlanningPdfService {
  // 0x0C5C6C
  static const _teal      = PdfColor(12 / 255, 92 / 255, 108 / 255);
  static const _tealLight = PdfColor(1, 1, 1, 0.85);   // blanc 85% sur fond teal
  static const _tealFaint = PdfColor(1, 1, 1, 0.65);   // blanc 65% sur fond teal
  static const _grey      = PdfColors.grey600;
  static const _lightGrey = PdfColors.grey200;

  // ── Helpers ─────────────────────────────────────────────────────────────────
  // Libellés d'acte/tranche/fréquence/timing partagés avec
  // plan_template_view_page.dart — voir utils/plan_template_labels.dart.
  static String _acteLabel(String? v) => planTemplateActeLabel(v);
  static String _trancheLabel(String? v) => planTemplateTrancheLabel(v);
  static String _freqLabel(Map<String, dynamic> e) => planTemplateFreqLabel(e);
  static String _timingLabel(Map<String, dynamic> e) => planTemplateTimingLabel(e);

  static String _footerDate() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static String _weekday(int w) =>
    const ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'][w - 1];

  static String _month(int m) =>
    const ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
           'septembre', 'octobre', 'novembre', 'décembre'][m - 1];

  static pw.Widget _footer(pw.Context ctx) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text('Imprimé le ${_footerDate()} • PetsMatch',
          style: pw.TextStyle(fontSize: 8, color: _grey)),
      pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: _grey)),
    ],
  );

  // ── PLN05 — Protocole template ───────────────────────────────────────────────

  static Future<void> printProtocole(Map<String, dynamic> template) async {
    final doc = pw.Document();
    final etapes = (template['plan_template_etapes'] as List?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList() ?? [];
    final nom       = template['nom'] as String? ?? '';
    final type      = template['type'] as String? ?? '';
    final espece    = template['espece'] as String? ?? '';
    final desc      = template['description'] as String? ?? '';

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: _footer,
      build: (ctx) => [
        // ── En-tête coloré
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(14),
          decoration: const pw.BoxDecoration(
            color: _teal,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(nom,
                style: pw.TextStyle(fontSize: 18, color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(
              [
                if (type.isNotEmpty) _acteLabel(type),
                if (espece.isNotEmpty) espece,
                '${etapes.length} étape${etapes.length > 1 ? 's' : ''}',
              ].join(' • '),
              style: pw.TextStyle(fontSize: 10, color: _tealLight),
            ),
            if (desc.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Text(desc, style: pw.TextStyle(fontSize: 9, color: _tealFaint)),
            ],
          ]),
        ),
        pw.SizedBox(height: 14),

        // ── Étapes, en cartes numérotées — même visuel que la fiche de
        // lecture dans l'appli (plan_template_view_page.dart).
        if (etapes.isEmpty)
          pw.Text('Aucune étape définie.', style: pw.TextStyle(color: _grey))
        else
          ...etapes.asMap().entries.map((en) => _etapeCard(en.key + 1, en.value)),
      ],
    ));

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'Routine_$nom',
    );
  }

  static pw.Widget _etapeCard(int index, Map<String, dynamic> e) {
    final produit = e['produit'] as String? ?? '';
    final dosage  = e['dosage']  as String? ?? '';
    final prodDos = [if (produit.isNotEmpty) produit,
                     if (dosage.isNotEmpty) '($dosage)'].join(' ');
    final notes   = e['description'] as String? ?? '';

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _lightGrey, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          width: 18, height: 18,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: PdfColor(_teal.red, _teal.green, _teal.blue, 0.12),
            shape: pw.BoxShape.circle,
          ),
          child: pw.Text('$index',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _teal)),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(_acteLabel(e['type_acte'] as String?),
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text(_timingLabel(e), style: pw.TextStyle(fontSize: 8.5, color: _grey)),
              ],
            ),
            if (prodDos.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(prodDos, style: const pw.TextStyle(fontSize: 9)),
            ],
            pw.SizedBox(height: 4),
            pw.Wrap(spacing: 5, runSpacing: 3, children: [
              _chip(_freqLabel(e)),
              _chip(_trancheLabel(e['tranche_horaire'] as String?)),
            ]),
            if (notes.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(notes, style: pw.TextStyle(fontSize: 8.5, color: _grey, fontStyle: pw.FontStyle.italic)),
            ],
          ]),
        ),
      ]),
    );
  }

  static pw.Widget _chip(String label) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: pw.BoxDecoration(color: _lightGrey, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
    child: pw.Text(label, style: pw.TextStyle(fontSize: 7.5, color: _grey, fontWeight: pw.FontWeight.bold)),
  );

  // ── PLN06 — Planning du jour ─────────────────────────────────────────────────

  static Future<void> printJour(
    List<Map<String, dynamic>> taches,
    DateTime date,
  ) async {
    final doc = pw.Document();

    // Grouper par etape_id
    final Map<String, List<Map<String, dynamic>>> byKey = {};
    for (final t in taches) {
      final key = t['etape_id'] as String? ?? 'solo_${t['id']}';
      byKey.putIfAbsent(key, () => []).add(t);
    }
    const trancheOrder = {'matin': 0, 'midi': 1, 'apres_midi': 2, 'soir': 3};
    final groupes = byKey.values.toList()
      ..sort((a, b) {
        final ta = trancheOrder[a.first['tranche_horaire']] ?? 99;
        final tb = trancheOrder[b.first['tranche_horaire']] ?? 99;
        return ta.compareTo(tb);
      });

    final dateStr = '${_weekday(date.weekday)} ${date.day} ${_month(date.month)} ${date.year}';
    final total = taches.length;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: _footer,
      build: (ctx) => [
        // ── En-tête
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text('Planning — $dateStr',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text('$total tâche${total > 1 ? 's' : ''}',
                style: pw.TextStyle(fontSize: 10, color: _grey)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: _lightGrey),
        pw.SizedBox(height: 8),

        // ── Tâches groupées
        ..._buildJourWidgets(groupes),

        // ── Signature
        pw.SizedBox(height: 32),
        pw.Row(children: [
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Effectué par :', style: pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 22),
              pw.Divider(color: _grey),
            ],
          )),
          pw.SizedBox(width: 40),
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Signature :', style: pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 22),
              pw.Divider(color: _grey),
            ],
          )),
        ]),
      ],
    ));

    final tag = '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'Planning_$tag',
    );
  }

  static List<pw.Widget> _buildJourWidgets(
    List<List<Map<String, dynamic>>> groupes,
  ) {
    final widgets = <pw.Widget>[];
    String? lastTranche = '__sentinel__';

    for (final group in groupes) {
      final tranche = group.first['tranche_horaire'] as String?;
      final trancheKey = tranche ?? '__none__';

      // Section header si tranche change
      if (trancheKey != lastTranche) {
        lastTranche = trancheKey;
        if (tranche != null) {
          widgets.add(pw.SizedBox(height: 10));
          widgets.add(pw.Row(children: [
            pw.Text(_trancheLabel(tranche),
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _teal)),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Divider(color: _lightGrey)),
          ]));
          widgets.add(pw.SizedBox(height: 4));
        }
      }

      final first = group.first;
      final rawLabel = first['label'] as String? ?? '';
      final label = rawLabel.split(' — ').first;
      final lieu  = first['lieu'] as String? ?? '';
      final jour  = first['jour_traitement'] as int? ?? 1;
      final total = first['total_jours'] as int? ?? 1;
      final animaux = group
          .map((t) => t['animal_nom'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      widgets.add(pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _lightGrey, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          // Case à cocher
          pw.Container(
            width: 14, height: 14,
            margin: const pw.EdgeInsets.only(top: 1),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500, width: 1),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label + (lieu.isNotEmpty ? ' — $lieu' : ''),
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              if (animaux.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(animaux.join(', '),
                    style: pw.TextStyle(fontSize: 9, color: _grey)),
              ],
              if (total > 1) ...[
                pw.SizedBox(height: 2),
                pw.Text('Jour $jour / $total',
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey400)),
              ],
            ],
          )),
        ]),
      ));
    }

    return widgets;
  }
}
