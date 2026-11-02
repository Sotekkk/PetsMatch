// Consignes postopératoires : sections modifiables (titres, listes, gras),
// ajout / suppression / ordre des sections, modèles (structure fournie ou
// modèles de la clinique), « Enregistrer comme modèle », aperçu PDF,
// brouillon ou « Valider et signer » (vétérinaire). Rien n'est appliqué
// d'office : un modèle ne remplace la saisie qu'après confirmation.
// Miroir site : website/src/components/pro/ConsignesEditeur.tsx.

import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/consignes_pdf.dart';
import 'package:PetsMatch/utils/client_document.dart';
import 'package:PetsMatch/utils/consignes_postop.dart';
import 'package:PetsMatch/utils/contexte_pro.dart';
import 'package:PetsMatch/utils/signature_pro.dart';
import 'package:PetsMatch/utils/storage_helper.dart';

const _teal = Color(0xFF0C5C6C);
const _muted = Color(0xFF6B7280);
const _amber = Color(0xFF8A5A00);

class ConsignesEditeur extends StatefulWidget {
  final Map<String, dynamic> chirurgie;
  final bool verrouille;
  final bool peutValider;
  /// Après enregistrement : fermer la page (true = quelque chose a changé).
  final VoidCallback onTermine;
  const ConsignesEditeur({super.key, required this.chirurgie, required this.verrouille, required this.peutValider, required this.onTermine});
  @override
  State<ConsignesEditeur> createState() => _ConsignesEditeurState();
}

class _Section {
  final titre = TextEditingController();
  final texte = TextEditingController();
  String aide;
  _Section(SectionConsigne s) : aide = s.aide { titre.text = s.titre; texte.text = s.texte; }
  SectionConsigne get valeur => SectionConsigne(titre: titre.text, texte: texte.text, aide: aide);
  void dispose() { titre.dispose(); texte.dispose(); }
}

class _ConsignesEditeurState extends State<ConsignesEditeur> {
  final _supa = Supabase.instance.client;
  final List<_Section> _sections = [];
  List<({String? id, String nom, List<SectionConsigne> sections})> _modeles = [];
  List<String> _coordClinique = [];
  bool _verifie = false;
  String? _occupe;

  Map get _op => widget.chirurgie['operatoire'] is Map ? widget.chirurgie['operatoire'] as Map : const {};
  String get _pro => (widget.chirurgie['pro_profile_id'] ?? AgendaContexte.profileId).toString();

  @override
  void initState() {
    super.initState();
    final c = widget.chirurgie['consignes'];
    final existantes = c is Map && c['sections'] is List
        ? [for (final s in c['sections'] as List) if (s is Map) SectionConsigne.fromJson(s)] : <SectionConsigne>[];
    _remplacer(existantes.isNotEmpty ? existantes : sectionsConsignes(), prerempli: existantes.isEmpty);
    _charger();
  }

  Future<void> _charger() async {
    try {
      if (_pro.isNotEmpty) {
        final cl = await _supa.from('user_profiles_complet')
            .select('nom, rue_pro, code_postal_pro, ville_pro, phone_number, email_contact').eq('id', _pro).maybeSingle();
        final adr = [cl?['rue_pro'], '${cl?['code_postal_pro'] ?? ''} ${cl?['ville_pro'] ?? ''}'.trim()]
            .where((x) => (x?.toString() ?? '').trim().isNotEmpty).join(', ');
        _coordClinique = [
          (cl?['nom'] ?? '').toString(), adr,
          if ((cl?['phone_number'] ?? '').toString().isNotEmpty) 'Tél. ${cl!['phone_number']}',
          (cl?['email_contact'] ?? '').toString(),
        ].where((x) => x.trim().isNotEmpty).toList();
        // Section « Coordonnées » encore vide : complétée.
        for (final s in _sections) {
          if (s.titre.text == 'Coordonnées de la clinique' && s.texte.text.trim().isEmpty && !widget.verrouille) {
            s.texte.text = _coordClinique.join('\n');
          }
        }
        final m = await _supa.from('consignes_modeles').select('id, nom, sections').eq('pro_profile_id', _pro).order('nom');
        _modeles = [
          for (final x in m as List)
            (id: x['id'].toString(), nom: (x['nom'] ?? '').toString(),
             sections: [for (final s in (x['sections'] as List? ?? const [])) if (s is Map) SectionConsigne.fromJson(s)]),
        ];
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _remplacer(List<SectionConsigne> base, {bool prerempli = true}) {
    for (final s in _sections) { s.dispose(); }
    _sections.clear();
    final src = prerempli ? prerempliConsignes(base,
        intervention: (_op['intervention'] ?? widget.chirurgie['intitule'] ?? '').toString(),
        traitements: (_op['traitements'] ?? '').toString(),
        controles: (_op['controles'] ?? '').toString(),
        prochainRdv: (_op['prochain_rdv'] ?? '').toString(),
        cliniqueCoord: _coordClinique) : base;
    for (final s in src) {
      final x = _Section(s);
      x.titre.addListener(_change); x.texte.addListener(_change);
      _sections.add(x);
    }
  }

  void _change() { if (mounted) setState(() => _verifie = false); }

  @override
  void dispose() { for (final s in _sections) { s.dispose(); } super.dispose(); }

  List<SectionConsigne> get _valeurs => [for (final s in _sections) s.valeur];

  Future<void> _appliquerModele() async {
    final tous = [..._modeles, ...modelesBaseConsignes()];
    final m = await showModalBottomSheet<({String? id, String nom, List<SectionConsigne> sections})>(
      context: context,
      builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('Partir d’un modèle', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
        for (final x in tous)
          ListTile(title: Text(x.nom, style: const TextStyle(fontFamily: 'Galey')),
              subtitle: Text(x.id != null ? 'Modèle de la clinique' : 'Structure seule, à rédiger',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              onTap: () => Navigator.pop(ctx, x)),
      ])),
    );
    if (m == null || !mounted) return;
    if (_sections.any((s) => s.texte.text.trim().isNotEmpty)) {
      final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
        content: const Text('Remplacer les consignes saisies par ce modèle ? Le texte actuel sera perdu.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remplacer')),
        ],
      ));
      if (ok != true) return;
    }
    setState(() { _remplacer([for (final s in m.sections) s.copie()]); _verifie = false; });
  }

  /// Mise en forme de la sélection : gras, liste, titre.
  void _formater(TextEditingController c, String f) {
    final t = c.text;
    final sel = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: t.length);
    final a = sel.start, b = sel.end;
    if (f == 'gras') {
      final milieu = a == b ? 'texte' : t.substring(a, b);
      c.text = '${t.substring(0, a)}**$milieu**${t.substring(b)}';
      return;
    }
    final debut = a == 0 ? 0 : t.lastIndexOf('\n', a - 1) + 1;
    final finIdx = t.indexOf('\n', b);
    final fin = finIdx == -1 ? t.length : finIdx;
    final prefixe = f == 'liste' ? '- ' : '## ';
    final lignes = t.substring(debut, fin).split('\n').map((l) => l.startsWith(prefixe)
        ? l.substring(prefixe.length) : prefixe + l.replaceFirst(RegExp(r'^(- |## )'), ''));
    c.text = t.substring(0, debut) + lignes.join('\n') + t.substring(fin);
  }

  Future<Uint8List> _pdf(List<SectionConsigne> sections, {required bool apercu}) async {
    final cl = _pro.isEmpty ? null : await _supa.from('user_profiles_complet')
        .select('nom, rue_pro, code_postal_pro, ville_pro, phone_number, email_contact').eq('id', _pro).maybeSingle();
    final a = await _supa.from('animaux').select('nom, espece, race').eq('id', widget.chirurgie['animal_id']).maybeSingle();
    ClientDocument? cli;
    try { cli = await clientDocument(widget.chirurgie['animal_id'].toString()); } catch (_) {}
    return consignesPdfBytes(
      cliniqueNom: (cl?['nom'] as String?)?.trim().isNotEmpty == true ? cl!['nom'] as String : 'Cabinet vétérinaire',
      cliniqueAdresse: [cl?['rue_pro'], '${cl?['code_postal_pro'] ?? ''} ${cl?['ville_pro'] ?? ''}'.trim()]
          .where((x) => (x?.toString() ?? '').trim().isNotEmpty).join(', '),
      cliniqueTel: (cl?['phone_number'] ?? '').toString(),
      cliniqueEmail: (cl?['email_contact'] ?? '').toString(),
      praticien: '${User_Info.firstname} ${User_Info.lastname}'.replaceAll('none', '').trim(),
      animalNom: (a?['nom'] ?? 'Animal').toString(),
      animalEspeceRace: [a?['espece'], a?['race']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · '),
      proprietaire: cli?.nom ?? '',
      dateIntervention: DateTime.tryParse((widget.chirurgie['date'] ?? '').toString()),
      sections: sections,
      signature: apercu ? null : octetsSignature(await maSignaturePro()),
      apercu: apercu,
    );
  }

  Future<void> _action(String a) async {
    setState(() => _occupe = a);
    try {
      final sections = _valeurs;
      if (a == 'apercu') {
        final bytes = await _pdf(sections, apercu: true);
        if (!mounted) return;
        await Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Aperçu des consignes', style: TextStyle(fontFamily: 'Galey', fontSize: 16)),
              backgroundColor: Colors.white, foregroundColor: const Color(0xFF1E2025), elevation: 0.5),
          body: PdfPreview(build: (_) async => bytes, allowPrinting: false, allowSharing: false,
              canChangePageFormat: false, canChangeOrientation: false, canDebug: false),
        )));
        return;
      }
      final propres = [for (final s in sections) if (s.titre.trim().isNotEmpty || s.texte.trim().isNotEmpty) s.toJson()..remove('aide')];
      if (a == 'modele') {
        final ctrl = TextEditingController();
        final nom = await showDialog<String>(context: context, builder: (d) => AlertDialog(
          title: const Text('Nom du modèle', style: TextStyle(fontFamily: 'Galey')),
          content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'ex. Stérilisation chienne')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), child: const Text('Enregistrer')),
          ],
        ));
        if (nom == null || nom.isEmpty) return;
        await _supa.from('consignes_modeles').insert({
          'pro_uid': AgendaContexte.uid, if (_pro.isNotEmpty) 'pro_profile_id': _pro, 'nom': nom,
          'type_intervention': widget.chirurgie['intitule'], 'sections': [for (final s in sections) s.toJson()],
        });
        await _charger();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Modèle enregistré : il sera proposé pour les prochaines interventions.', style: TextStyle(fontFamily: 'Galey'))));
        }
        return;
      }
      final valider = a == 'valider';
      final sansPro = (widget.chirurgie['pro_uid'] ?? '').toString().isEmpty;
      await _supa.from('chirurgies').update({
        'consignes': {'sections': propres, 'statut': valider ? 'valide' : 'brouillon'},
        if (sansPro) 'pro_uid': AgendaContexte.uid,
        if (sansPro && AgendaContexte.profileId.isNotEmpty) 'pro_profile_id': AgendaContexte.profileId,
      }).eq('id', widget.chirurgie['id']);
      if (valider) {
        try {
          final bytes = await _pdf([for (final s in propres) SectionConsigne.fromJson(s)], apercu: false);
          final moi = FirebaseAuth.instance.currentUser?.uid ?? AgendaContexte.uid;
          final url = await uploadDocumentBytes(bytes, 'chirurgies/$moi/${DateTime.now().millisecondsSinceEpoch}.pdf');
          await _supa.from('chirurgies').update({'consignes_doc_url': url}).eq('id', widget.chirurgie['id']);
        } catch (e) {
          _message('Consignes validées, mais PDF non enregistré : $e');
        }
        try {
          await FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('notifyOwnerVetEntry').call({
            'animalId': widget.chirurgie['animal_id'],
            'vetName': '${User_Info.firstname} ${User_Info.lastname}'.replaceAll('none', '').trim(), 'typeActe': 'chirurgie'});
        } catch (_) {}
      }
      widget.onTermine();
    } catch (e) {
      _message('Impossible : $e');
    } finally {
      if (mounted) setState(() => _occupe = null);
    }
  }

  void _message(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t, style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = controlerConsignes(_valeurs);
    final v = widget.verrouille;
    const lien = TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700);
    const style = TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700);
    final peutConfirmer = widget.peutValider && ctrl.bloquants.isEmpty && (ctrl.avertissements.isEmpty || _verifie);
    Widget petit(String t, VoidCallback f) => OutlinedButton(onPressed: f,
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
        child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      const Text('Document pour le propriétaire, distinct du compte rendu opératoire. Les modèles ne sont qu’une base : vérifiez et adaptez chaque consigne à cet animal.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
      if (!v) Align(alignment: Alignment.centerLeft, child: TextButton.icon(
        onPressed: _appliquerModele, icon: const Icon(Icons.library_books_outlined, size: 18, color: _teal),
        label: const Text('Partir d’un modèle', style: lien))),
      for (var i = 0; i < _sections.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE4E7E2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: TextField(controller: _sections[i].titre, enabled: !v,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none))),
              if (!v) ...[
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_upward, size: 18),
                    onPressed: i == 0 ? null : () => setState(() { final s = _sections.removeAt(i); _sections.insert(i - 1, s); })),
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_downward, size: 18),
                    onPressed: i == _sections.length - 1 ? null : () => setState(() { final s = _sections.removeAt(i); _sections.insert(i + 1, s); })),
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    onPressed: () => setState(() => _sections.removeAt(i).dispose())),
              ],
            ]),
            if (!v) Wrap(spacing: 6, children: [
              petit('Titre', () => _formater(_sections[i].texte, 'titre')),
              petit('Liste', () => _formater(_sections[i].texte, 'liste')),
              petit('Gras', () => _formater(_sections[i].texte, 'gras')),
            ]),
            const SizedBox(height: 6),
            TextField(controller: _sections[i].texte, enabled: !v, minLines: 3, maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(hintText: _sections[i].aide, isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
          ]),
        ),
      if (!v) Align(alignment: Alignment.centerLeft, child: TextButton(
        onPressed: () => setState(() {
          final s = _Section(SectionConsigne(titre: 'Nouvelle section'));
          s.titre.addListener(_change); s.texte.addListener(_change);
          _sections.add(s);
        }),
        child: const Text('Ajouter une section', style: lien))),
      if (!v && ctrl.bloquants.isNotEmpty)
        _boite(const Color(0xFFFEF2F2), const Color(0xFFFECACA), const Color(0xFFB91C1C), 'À compléter avant la validation :', ctrl.bloquants),
      if (!v && ctrl.avertissements.isNotEmpty)
        _boite(const Color(0xFFFFF8EA), const Color(0xFFF3E2BD), _amber, 'À vérifier :', ctrl.avertissements,
            fin: widget.peutValider ? CheckboxListTile(
              contentPadding: EdgeInsets.zero, dense: true, value: _verifie, activeColor: _amber,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (x) => setState(() => _verifie = x == true),
              title: const Text("J'ai vérifié ces points", style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: _amber)),
            ) : null),
      if (!v && !widget.peutValider)
        const Padding(padding: EdgeInsets.only(top: 8),
          child: Text('Vous préparez ces consignes : un vétérinaire les vérifie, les valide et les signe.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: _occupe != null ? null : () => _action('apercu'),
          style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
          child: Text(_occupe == 'apercu' ? 'Préparation…' : 'Aperçu', style: style))),
        const SizedBox(width: 10),
        Expanded(child: TextButton(onPressed: _occupe != null ? null : () => _action('modele'),
            child: const Text('Enregistrer comme modèle', style: TextStyle(fontFamily: 'Galey', color: _muted, fontWeight: FontWeight.w700), textAlign: TextAlign.center))),
      ]),
      if (!v) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _occupe != null ? null : () => _action('brouillon'),
            style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
            child: Text(_occupe == 'brouillon' ? 'Enregistrement…' : 'Enregistrer le brouillon', style: style, textAlign: TextAlign.center))),
          if (widget.peutValider) ...[
            const SizedBox(width: 10),
            Expanded(child: FilledButton(
              onPressed: _occupe != null || !peutConfirmer ? null : () => _action('valider'),
              style: FilledButton.styleFrom(backgroundColor: _teal),
              child: Text(_occupe == 'valider' ? 'Validation…' : 'Valider et signer', style: style, textAlign: TextAlign.center))),
          ],
        ]),
      ],
    ]);
  }

  Widget _boite(Color fond, Color bord, Color texte, String titre, List<String> l, {Widget? fin}) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(10), border: Border.all(color: bord)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: texte)),
          for (final m in l) Text('• $m', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: texte)),
          if (fin != null) fin,
        ]),
      );
}
