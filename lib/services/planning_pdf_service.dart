import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/protocoles.dart';
import 'package:PetsMatch/utils/plan_template_labels.dart';

// PLN05 — impression protocole template
// PLN06 — impression planning du jour avec cases à cocher

class PlanningPdfService {
  // 0x0C5C6C
  static const _teal      = PdfColor(12 / 255, 92 / 255, 108 / 255);
  static const _grey      = PdfColors.grey600;
  static const _lightGrey = PdfColors.grey200;

  // ── Helpers ─────────────────────────────────────────────────────────────────
  // Libellés d'acte/tranche/fréquence/timing partagés avec
  // plan_template_view_page.dart — voir utils/plan_template_labels.dart.
  static String _trancheLabel(String? v) => planTemplateTrancheLabel(v);

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

  // ── Fiche A4 d'un protocole, pour les employés ──────────────────────────────
  // Générée à partir des données (pas une capture) : noir et blanc, police
  // lisible, tableau des étapes (sauts de page propres), nom de la structure
  // et date de version ; si le protocole a été appliqué, animaux / groupes
  // concernés et dates calculées. Miroir site : src/lib/protocole-pdf.ts.

  static String _fmt(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static Future<String> _nomStructure(Map<String, dynamic> t) async {
    final pid = (t['eleveur_profile_id'] ?? '').toString();
    try {
      final supa = Supabase.instance.client;
      final row = pid.isNotEmpty
          ? await supa.from('user_profiles_complet').select('nom, firstname, lastname').eq('id', pid).maybeSingle()
          : await supa.from('user_profiles_complet').select('nom, firstname, lastname')
              .eq('uid', (t['uid_eleveur'] ?? '').toString()).eq('is_main', true).maybeSingle();
      final nom = (row?['nom'] ?? '').toString();
      return nom.isNotEmpty ? nom : '${row?['firstname'] ?? ''} ${row?['lastname'] ?? ''}'.trim();
    } catch (_) {
      return '';
    }
  }

  /// Applications en cours : libellé, date de référence, dates par étape.
  static Future<List<(String, String, List<(String, String, String, int)>)>> _applications(Map<String, dynamic> t) async {
    try {
      final supa = Supabase.instance.client;
      final plans = await supa.from('plans_actifs')
          .select('id, reference_id, reference_label, date_reference')
          .eq('template_id', t['id']).eq('statut', 'actif')
          .order('date_reference', ascending: false).limit(60);
      if ((plans as List).isEmpty) return [];
      final ids = plans.map((p) => p['id'].toString()).toList();
      final taches = await supa.from('plan_taches').select('plan_id, etape_id, date_prevue, animal_nom').inFilter('plan_id', ids);
      final out = <(String, String, List<(String, String, String, int)>)>[];
      for (final p in plans) {
        final ts = (taches as List).where((x) => x['plan_id'] == p['id']).toList();
        final parEtape = <String, List<String>>{};
        for (final x in ts) {
          parEtape.putIfAbsent((x['etape_id'] ?? '').toString(), () => []).add(x['date_prevue'].toString());
        }
        final nomTache = ts.map((x) => (x['animal_nom'] ?? '').toString()).firstWhere((n) => n.isNotEmpty, orElse: () => '');
        final libelle = (p['reference_label'] ?? '').toString().isNotEmpty ? p['reference_label'].toString()
            : nomTache.isNotEmpty ? nomTache : 'Groupe';
        out.add((libelle, (p['date_reference'] ?? '').toString(), [
          for (final e in parEtape.entries) (() {
            final tri = [...e.value]..sort();
            return (e.key, tri.first, tri.last, tri.length);
          })(),
        ]));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> printProtocole(Map<String, dynamic> template, {String? profilSource}) async {
    final doc = pw.Document();
    final etapes = ((template['plan_template_etapes'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList()
      ..sort((a, b) => ((a['ordre'] as num?) ?? 0).compareTo((b['ordre'] as num?) ?? 0));
    final nom = (template['nom'] ?? '').toString();
    final desc = (template['description'] ?? '').toString();
    final refEvent = (template['reference_event'] ?? 'manuel').toString();
    final locaux = perimetreDe(template, profilSource: profilSource) == 'locaux';
    final structure = await _nomStructure(template);
    final version = _fmt((template['updated_at'] ?? template['created_at'] ?? DateTime.now().toIso8601String()).toString());
    final apps = await _applications(template);
    pw.MemoryImage? logo;
    try {
      logo = pw.MemoryImage((await rootBundle.load('assets/logo/logo_pdf.jpg')).buffer.asUint8List());
    } catch (_) {}
    final numEtape = {for (var i = 0; i < etapes.length; i++) (etapes[i]['id'] ?? '').toString(): i + 1};

    const base = pw.TextStyle(fontSize: 10.5, color: PdfColors.black);
    final gras = pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black);
    pw.Widget cell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(t, style: bold ? gras : base, textAlign: align),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 36, 42, 36),
      header: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 6),
        margin: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.8))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          if (logo != null)
            pw.Image(logo, width: 56, height: 56)
          else
            pw.Text('PetsMatch', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(structure, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('Fiche protocole', style: const pw.TextStyle(fontSize: 9)),
          ]),
        ]),
      ),
      footer: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.6))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Version du $version${structure.isNotEmpty ? ' — $structure' : ''}', style: const pw.TextStyle(fontSize: 9.5)),
          pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 9.5)),
        ]),
      ),
      build: (ctx) => [
        pw.Center(child: pw.Text(nom.toUpperCase(), textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text(perimetreLabel(template, profilSource: profilSource),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
        if (!locaux) ...[
          pw.SizedBox(height: 3),
          pw.Center(child: pw.Text('Calcul des dates : ${refEventLabel(refEvent)}', style: const pw.TextStyle(fontSize: 10.5))),
        ],
        if (desc.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(desc, style: const pw.TextStyle(fontSize: 11)),
        ],
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 0.8),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('PROTOCOLE EMPLOYÉS', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 8),
        if (etapes.isEmpty)
          pw.Text('Aucune étape définie.', style: base)
        else
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(42), 1: pw.FlexColumnWidth(1.3), 2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.4), 4: pw.FixedColumnWidth(58), 5: pw.FlexColumnWidth(2.6),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                repeat: true,
                children: ['Étape', 'Action', 'Quand', 'Fréquence / durée', 'Créneau', 'Consignes']
                    .map((h) => cell(h, bold: true)).toList(),
              ),
              for (var i = 0; i < etapes.length; i++) (() {
                final e = etapes[i];
                final produit = (e['produit'] ?? '').toString();
                final dosage = (e['dosage'] ?? '').toString();
                final lieu = (e['lieu'] ?? '').toString();
                final consignes = [
                  if (produit.isNotEmpty) 'Produit : $produit${dosage.isNotEmpty ? ' — $dosage' : ''}'
                  else if (dosage.isNotEmpty) 'Dosage : $dosage',
                  if (lieu.isNotEmpty) 'Lieu : $lieu',
                  if ((e['description'] ?? '').toString().isNotEmpty) e['description'].toString(),
                ].join('\n');
                return pw.TableRow(verticalAlignment: pw.TableCellVerticalAlignment.top, children: [
                  cell('${i + 1}', bold: true, align: pw.TextAlign.center),
                  cell(acteLabel(e['type_acte'] as String?)),
                  cell(quandLabel(e, refEvent)),
                  cell(frequenceLabel(e)),
                  cell(kTranches[e['tranche_horaire']] ?? '—'),
                  cell(consignes.isEmpty ? '—' : consignes),
                ]);
              })(),
            ],
          ),
        if (apps.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text(locaux ? 'APPLICATION EN COURS' : 'ANIMAUX / GROUPES CONCERNÉS',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {0: pw.FlexColumnWidth(1.4), 1: pw.FixedColumnWidth(80), 2: pw.FlexColumnWidth(3)},
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                repeat: true,
                children: ['Concerné', 'Date de référence', 'Dates calculées'].map((h) => cell(h, bold: true)).toList(),
              ),
              for (final a in apps)
                pw.TableRow(verticalAlignment: pw.TableCellVerticalAlignment.top, children: [
                  cell(a.$1),
                  cell(_fmt(a.$2).isEmpty ? '—' : _fmt(a.$2)),
                  cell(([...a.$3]..sort((x, y) => (numEtape[x.$1] ?? 99).compareTo(numEtape[y.$1] ?? 99)))
                      .map((s) => 'Étape ${numEtape[s.$1] ?? '?'} : ${s.$4 > 1 ? 'du ${_fmt(s.$2)} au ${_fmt(s.$3)} (${s.$4} fois)' : 'le ${_fmt(s.$2)}'}')
                      .join('\n')),
                ]),
            ],
          ),
        ],
      ],
    ));

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'Protocole - $nom',
    );
  }

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
