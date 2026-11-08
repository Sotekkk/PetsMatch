// Pension — impressions (PDF) : fiche à afficher sur le box (une page par
// pensionnaire) et feuille du jour par logement (tâches à cocher, signature).
// Miroir site : lib/pension-impressions.ts.
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/pension_protocoles.dart' show momentSejourLabel;

String _t(Object? v) => v == null ? '' : v.toString().trim();
const _tranches = {'matin': 'Matin', 'midi': 'Midi', 'apres_midi': 'Après-midi', 'soir': 'Soir'};
const _ordre = {'matin': 0, 'midi': 1, 'apres_midi': 2, 'soir': 3};
final _teal = PdfColor.fromHex('#0C5C6C');

String _jour(Object? v) {
  final d = DateTime.tryParse(_t(v));
  return d == null ? '' : DateFormat('EEE d MMMM', 'fr_FR').format(d);
}

List<String> _alim(Object? brut) {
  if (brut is! Map) return [];
  final fp = switch (brut['fournis_par']) {
    'pension' => 'Fournie par la pension', 'proprietaire' => 'Fournie par le propriétaire', 'mixte' => 'Alimentation partagée', _ => '',
  };
  return [
    if (fp.isNotEmpty) fp,
    if (_t(brut['foin']).isNotEmpty) 'Foin : ${_t(brut['foin'])}',
    if (_t(brut['granules']).isNotEmpty) 'Granulés / croquettes : ${_t(brut['granules'])}',
    if (_t(brut['complements']).isNotEmpty) 'Compléments : ${_t(brut['complements'])}',
    if (_t(brut['autres']).isNotEmpty) 'Autres : ${_t(brut['autres'])}',
    if (_t(brut['consignes']).isNotEmpty) 'Consignes : ${_t(brut['consignes'])}',
  ];
}

pw.Widget _titre(String s) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 12, bottom: 4),
      padding: const pw.EdgeInsets.only(bottom: 2),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))),
      child: pw.Text(s, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _teal, fontSize: 12)),
    );

/// Fiche à afficher sur le box : une page par pensionnaire.
Future<void> imprimerFichesBox(List<String> entreeIds, String pensionNom) async {
  if (entreeIds.isEmpty) return;
  final supa = Supabase.instance.client;
  final entrees = [for (final e in await supa.from('pension_entrees').select().inFilter('id', entreeIds)) Map<String, dynamic>.from(e)];
  final lgIds = {for (final e in entrees) if (_t(e['logement_id']).isNotEmpty) _t(e['logement_id'])}.toList();
  final lgNom = <String, String>{};
  if (lgIds.isNotEmpty) {
    for (final l in await supa.from('enclos_chenil').select('id, nom, type').inFilter('id', lgIds)) {
      lgNom[_t(l['id'])] = '${_t(l['nom'])}${_t(l['type']).isNotEmpty ? ' (${_t(l['type'])})' : ''}';
    }
  }
  List<Map<String, dynamic>> taches = [];
  try {
    taches = [for (final x in await supa.from('plan_taches')
        .select('pension_entree_id, etape_id, label, tranche_horaire, plan_template_etapes(sejour_moment, jour_offset)')
        .inFilter('pension_entree_id', entreeIds)) Map<String, dynamic>.from(x)];
  } catch (_) {}
  final doc = pw.Document();
  for (final e in entrees) {
    pw.ImageProvider? photo;
    final url = _t(e['photo_url']);
    if (url.isNotEmpty) {
      try {
        final r = await http.get(Uri.parse(url));
        if (r.statusCode == 200) photo = pw.MemoryImage(r.bodyBytes);
      } catch (_) {}
    }
    final vues = <String, List<String>>{};
    for (final x in taches.where((x) => _t(x['pension_entree_id']) == _t(e['id']))) {
      final k = _t(x['etape_id']);
      if (vues.containsKey(k)) continue;
      final et = (x['plan_template_etapes'] as Map?) ?? const {};
      vues[k] = [_t(x['label']).replaceAll(RegExp(r' — Jour \d+/\d+$'), ''),
        momentSejourLabel(_t(et['sejour_moment']), (et['jour_offset'] as num?)?.toInt() ?? 0), _tranches[_t(x['tranche_horaire'])] ?? ''];
    }
    final alim = _alim(e['alimentation_sejour']);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (photo != null) pw.Container(width: 110, height: 110, margin: const pw.EdgeInsets.only(right: 14),
              child: pw.ClipRRect(horizontalRadius: 8, verticalRadius: 8, child: pw.Image(photo, fit: pw.BoxFit.cover))),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(_t(e['animal_nom']).isEmpty ? 'Pensionnaire' : _t(e['animal_nom']), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.Text([_t(e['espece']), _t(e['race'])].where((x) => x.isNotEmpty).join(' · ')
                + (_t(e['puce']).isNotEmpty ? ' · Identification ${_t(e['puce'])}' : '')),
            pw.SizedBox(height: 4),
            pw.Text('Logement : ${lgNom[_t(e['logement_id'])] ?? 'non attribué'}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('Du ${_jour(e['date_entree'])}${_t(e['heure_arrivee_prevue']).isNotEmpty ? ' (${_t(e['heure_arrivee_prevue']).replaceAll(':', 'h')})' : ''}'
                ' au ${_jour(e['date_sortie_prevue'])}${_t(e['heure_depart_prevue']).isNotEmpty ? ' (${_t(e['heure_depart_prevue']).replaceAll(':', 'h')})' : ''}'
                '${e['essai'] == true ? ' · ESSAI' : ''}'),
          ])),
        ]),
        _titre('Propriétaire'),
        pw.Text([_t(e['proprietaire_nom']), _t(e['proprietaire_contact']), _t(e['proprietaire_email'])].where((x) => x.isNotEmpty).join(' · ')),
        if (alim.isNotEmpty) ...[_titre('Alimentation'), for (final l in alim) pw.Text(l)],
        if (_t(e['consignes_sejour']).isNotEmpty) ...[_titre('Consignes, traitements, apports'), pw.Text(_t(e['consignes_sejour']))],
        if (_t(e['effets_personnels']).isNotEmpty) ...[_titre('Effets personnels'), pw.Text(_t(e['effets_personnels']))],
        if (vues.isNotEmpty) ...[
          _titre('Protocoles du séjour'),
          pw.TableHelper.fromTextArray(
            headers: ['Soin / tâche', 'Quand', 'Créneau'], data: vues.values.toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          ),
        ],
        pw.Spacer(),
        pw.Text('$pensionNom · fiche imprimée le ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      ]),
    ));
  }
  await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'Fiche box');
}

/// Feuille du jour : pensionnaires présents par logement, repas, tâches à cocher.
Future<void> imprimerFeuilleJour({required String proUid, String? proProfileId, required DateTime date, required String pensionNom}) async {
  final supa = Supabase.instance.client;
  final jour = DateFormat('yyyy-MM-dd').format(date);
  var qe = supa.from('pension_entrees').select().eq('pro_uid', proUid).eq('statut', 'en_pension').lte('date_entree', jour);
  if ((proProfileId ?? '').isNotEmpty) qe = qe.eq('pro_profile_id', proProfileId!);
  final presents = [for (final e in await qe)
    if (_t(e['date_sortie_prevue']).isEmpty || _t(e['date_sortie_prevue']).substring(0, 10).compareTo(jour) >= 0) Map<String, dynamic>.from(e)];
  var qt = supa.from('plan_taches').select('label, tranche_horaire, animal_nom, box_id')
      .eq('uid_eleveur', proUid).eq('profil_source', 'pension').eq('date_prevue', jour);
  if ((proProfileId ?? '').isNotEmpty) qt = qt.eq('eleveur_profile_id', proProfileId!);
  final taches = [for (final x in await qt) Map<String, dynamic>.from(x)];
  final logements = [for (final l in await supa.from('enclos_chenil').select('id, nom').eq('uid_eleveur', proUid).order('nom'))
    (id: _t(l['id']), nom: _t(l['nom']))];
  final blocs = <pw.Widget>[];
  for (final l in [...logements, (id: '', nom: 'Sans logement attribué')]) {
    final animaux = presents.where((e) => _t(e['logement_id']) == l.id).toList();
    final tl = taches.where((x) => _t(x['box_id']) == l.id).toList()
      ..sort((a, b) => (_ordre[_t(a['tranche_horaire'])] ?? 9).compareTo(_ordre[_t(b['tranche_horaire'])] ?? 9));
    if (animaux.isEmpty && tl.isEmpty) continue;
    blocs.add(_titre(l.nom));
    for (final a in animaux) {
      final alim = _alim(a['alimentation_sejour']);
      blocs.add(pw.Text('${_t(a['animal_nom'])}${_t(a['consignes_sejour']).isNotEmpty ? ' — ${_t(a['consignes_sejour']).split('\n').first}' : ''}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)));
      if (alim.isNotEmpty) blocs.add(pw.Text('Repas : ${alim.join(' · ')}', style: const pw.TextStyle(fontSize: 10)));
    }
    if (tl.isNotEmpty) {
      blocs.add(pw.SizedBox(height: 4));
      blocs.add(pw.TableHelper.fromTextArray(
        headers: ['', 'Tâche', 'Animal', 'Créneau', 'Fait par'],
        data: [for (final x in tl) ['[  ]', _t(x['label']), _t(x['animal_nom']), _tranches[_t(x['tranche_horaire'])] ?? '', '']],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), cellStyle: const pw.TextStyle(fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        columnWidths: {0: const pw.FixedColumnWidth(24), 3: const pw.FixedColumnWidth(60), 4: const pw.FixedColumnWidth(70)},
      ));
    }
  }
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(24),
    build: (_) => [
      pw.Text('Feuille du jour — ${_jour(jour)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text('$pensionNom · ${presents.length} pensionnaire(s)'),
      ...blocs,
      pw.SizedBox(height: 30),
      pw.Row(children: [
        pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.only(top: 4),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey))), child: pw.Text('Employé(e)'))),
        pw.SizedBox(width: 40),
        pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.only(top: 4),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey))), child: pw.Text('Responsable'))),
      ]),
    ],
  ));
  await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'Feuille du jour $jour');
}
