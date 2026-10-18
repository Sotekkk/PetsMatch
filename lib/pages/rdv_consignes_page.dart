// Consignes avant un rendez-vous (toiletteur) : rempli par le client (ou par
// le professionnel à sa place), préremplies avec les consignes de la fois
// précédente. Données via la route du site /api/rdv/consignes. Miroir site :
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

class _RdvConsignesPageState extends State<RdvConsignesPage> {
  Map<String, dynamic>? _ctx;
  String? _erreur;
  bool _envoi = false;
  final Map<String, TextEditingController> _c = {};
  final Map<String, String> _choix = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final c in _c.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final j = await ConsignesApi.charger(widget.rdvId);
      final rep = Map<String, dynamic>.from((j['reponses'] ?? j['prefill'] ?? {}) as Map);
      for (final q in questionnaireConsignes(j['metier']?.toString())) {
        if (q.choix != null) {
          _choix[q.cle] = rep[q.cle]?.toString() ?? '';
        } else {
          _c[q.cle] = TextEditingController(text: rep[q.cle]?.toString() ?? '');
        }
      }
      if (mounted) setState(() => _ctx = j);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _envoyer() async {
    setState(() => _envoi = true);
    try {
      await ConsignesApi.enregistrer(widget.rdvId, {
        for (final e in _c.entries) e.key: e.value.text.trim(),
        ..._choix,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Consignes envoyées — merci !', style: TextStyle(fontFamily: 'Galey'))));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _envoi = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _ctx;
    final pro = ctx?['role'] == 'pro';
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
                  if (ctx['reponses'] == null && ctx['prefill'] != null)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('Préremplies avec vos consignes de la dernière fois : vérifiez-les.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500))),
                  const SizedBox(height: 12),
                  for (final q in questionnaireConsignes(ctx['metier']?.toString())) ...[
                    Text(q.label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                    if (q.aide != null) Text(q.aide!, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    if (q.choix != null)
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final c in q.choix!)
                          ChoiceChip(
                            label: Text(c, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _choix[q.cle] == c ? Colors.white : _ink)),
                            selected: _choix[q.cle] == c, showCheckmark: false, selectedColor: _teal, backgroundColor: Colors.white,
                            onSelected: (_) => setState(() => _choix[q.cle] = _choix[q.cle] == c ? '' : c),
                          ),
                      ])
                    else
                      TextField(controller: _c[q.cle], maxLines: 3, minLines: 1,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, filled: true, fillColor: Colors.white)),
                    const SizedBox(height: 14),
                  ],
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
