// Consignes avant un rendez-vous (toiletteur) : rempli par le client (ou par
// le professionnel à sa place), préremplies avec les consignes de la fois
// précédente. RDV à plusieurs animaux : une fiche par animal, le client doit
// en remplir une pour CHAQUE animal (contrôlé aussi par la route). Données via
// la route du site /api/rdv/consignes. Miroir site :
// website/src/components/ConsignesRdvForm.tsx (+ page /consignes/[token]).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/utils/consignes_rdv.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);

class RdvConsignesPage extends StatefulWidget {
  final String rdvId;
  const RdvConsignesPage({super.key, required this.rdvId});

  @override
  State<RdvConsignesPage> createState() => _RdvConsignesPageState();
}

class _AnimalForm {
  final String id, nom;
  final bool prerempli;
  final Map<String, TextEditingController> c = {};
  final Map<String, String> choix = {};
  _AnimalForm(this.id, this.nom, {this.prerempli = false});

  Map<String, String> valeurs() => {for (final e in c.entries) e.key: e.value.text.trim(), ...choix};
  bool get rempli => valeurs().values.any((v) => v.trim().isNotEmpty);
  void dispose() { for (final x in c.values) { x.dispose(); } }
}

class _RdvConsignesPageState extends State<RdvConsignesPage> {
  Map<String, dynamic>? _ctx;
  String? _erreur;
  String? _manque;
  bool _envoi = false;
  final List<_AnimalForm> _animaux = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final a in _animaux) { a.dispose(); }
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final j = await ConsignesApi.charger(widget.rdvId);
      final questions = questionnaireConsignes(j['metier']?.toString());
      // Route antérieure (sans « animaux ») : un seul formulaire.
      final liste = (j['animaux'] is List && (j['animaux'] as List).isNotEmpty)
          ? [for (final a in j['animaux'] as List) Map<String, dynamic>.from(a as Map)]
          : [{'id': '', 'nom': j['animal_nom'], 'reponses': j['reponses'], 'prefill': j['prefill']}];
      for (final a in liste) {
        final rep = Map<String, dynamic>.from((a['reponses'] ?? a['prefill'] ?? {}) as Map);
        final f = _AnimalForm(a['id']?.toString() ?? '', a['nom']?.toString() ?? '',
            prerempli: a['reponses'] == null && a['prefill'] != null);
        for (final q in questions) {
          if (q.choix != null) {
            f.choix[q.cle] = rep[q.cle]?.toString() ?? '';
          } else {
            f.c[q.cle] = TextEditingController(text: rep[q.cle]?.toString() ?? '');
          }
        }
        _animaux.add(f);
      }
      if (mounted) setState(() => _ctx = j);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _reprendreDuPremier(_AnimalForm cible) {
    final source = _animaux.first;
    setState(() {
      for (final e in source.c.entries) { cible.c[e.key]?.text = e.value.text; }
      cible.choix..clear()..addAll(source.choix);
    });
  }

  Future<void> _envoyer() async {
    final client = _ctx?['role'] != 'pro';
    if (client && _animaux.length > 1) {
      final sans = [for (final a in _animaux) if (!a.rempli) a.nom];
      if (sans.isNotEmpty) {
        setState(() => _manque = 'Indiquez les consignes de chaque animal : il manque ${sans.join(', ')}.');
        return;
      }
    }
    setState(() { _envoi = true; _manque = null; });
    try {
      await ConsignesApi.enregistrer(widget.rdvId, {for (final a in _animaux) a.id: a.valeurs()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Consignes envoyées — merci !', style: TextStyle(fontFamily: 'Galey'))));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _envoi = false; _manque = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Widget _questions(_AnimalForm a, List<QuestionConsigne> questions) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final q in questions) ...[
            Text(q.label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
            if (q.aide != null) Text(q.aide!, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            if (q.choix != null)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in q.choix!)
                  ChoiceChip(
                    label: Text(c, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: a.choix[q.cle] == c ? Colors.white : _ink)),
                    selected: a.choix[q.cle] == c, showCheckmark: false, selectedColor: _teal, backgroundColor: Colors.white,
                    onSelected: (_) => setState(() => a.choix[q.cle] = a.choix[q.cle] == c ? '' : c),
                  ),
              ])
            else
              TextField(controller: a.c[q.cle], maxLines: 3, minLines: 1, onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white)),
            const SizedBox(height: 14),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final ctx = _ctx;
    final pro = ctx?['role'] == 'pro';
    final plusieurs = _animaux.length > 1;
    final questions = questionnaireConsignes(ctx?['metier']?.toString());
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
          title: Text(ctx == null || (ctx['animal_nom']?.toString() ?? '').isEmpty ? 'Consignes' : 'Consignes pour ${ctx['animal_nom']}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      body: _erreur != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erreur!, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey'))))
          : ctx == null
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Builder(builder: (_) {
                    final d = DateTime.tryParse(ctx['rdv']?['date_heure']?.toString() ?? '')?.toLocal();
                    return Text([ctx['pro_nom']?.toString() ?? '', if (d != null) DateFormat("EEEE d MMMM 'à' HH:mm", 'fr_FR').format(d)].join(' · '),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700));
                  }),
                  if (plusieurs)
                    const Padding(padding: EdgeInsets.only(top: 4), child: Text('Une fiche par animal : remplissez-les toutes.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _teal))),
                  if (_animaux.any((a) => a.prerempli))
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('Préremplies avec vos consignes de la dernière fois : vérifiez-les.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500))),
                  const SizedBox(height: 12),
                  if (!plusieurs)
                    _questions(_animaux.first, questions)
                  else
                    for (var i = 0; i < _animaux.length; i++) ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E8E6))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Flexible(child: Text(_animaux[i].nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _ink))),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: _animaux[i].rempli ? const Color(0xFFEAF5EC) : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text(_animaux[i].rempli ? 'Remplie' : 'À remplir', style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                  fontWeight: FontWeight.w700, color: _animaux[i].rempli ? const Color(0xFF2F7D3A) : const Color(0xFFB45309))),
                            ),
                          ]),
                          if (i > 0 && _animaux.first.rempli)
                            Align(alignment: Alignment.centerLeft, child: TextButton(
                              onPressed: () => _reprendreDuPremier(_animaux[i]),
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                              child: Text('Reprendre les consignes de ${_animaux.first.nom}',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _teal)),
                            )),
                          const SizedBox(height: 8),
                          _questions(_animaux[i], questions),
                        ]),
                      ),
                      const SizedBox(height: 12),
                    ],
                  if (_manque != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                      child: Text(_manque!, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFB42318))),
                    ),
                  FilledButton(
                    onPressed: _envoi ? null : _envoyer,
                    style: FilledButton.styleFrom(backgroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(_envoi ? 'Envoi…' : pro ? 'Enregistrer les consignes' : 'Envoyer mes consignes',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                  ),
                ]),
    );
  }
}
