// Profil vétérinaire : consignes avant une intervention, une par sous-type
// (détartrage, stérilisation…). Reprises à la prise d'un RDV « Intervention »
// (modifiables pour ce RDV), envoyées au propriétaire et rappelées la veille.
// Miroir site : components/pro/ConsignesPreopCard.tsx.
import 'package:flutter/material.dart';

import 'package:PetsMatch/utils/intervention.dart';

class ConsignesPreopEditor extends StatefulWidget {
  final String profileId;
  const ConsignesPreopEditor({super.key, required this.profileId});
  @override
  State<ConsignesPreopEditor> createState() => _ConsignesPreopEditorState();
}

class _ConsignesPreopEditorState extends State<ConsignesPreopEditor> {
  static const _teal = Color(0xFF0C5C6C);
  Map<String, String> _textes = {};
  String _ouvert = 'detartrage';
  final _ctrl = TextEditingController();
  String _etat = '';

  @override
  void initState() {
    super.initState();
    consignesPreopDefaut(widget.profileId).then((v) {
      if (!mounted) return;
      setState(() { _textes = v; _ctrl.text = v[_ouvert] ?? ''; });
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _choisir(String k) {
    _textes[_ouvert] = _ctrl.text;
    setState(() { _ouvert = k; _ctrl.text = _textes[k] ?? ''; });
  }

  Future<void> _enregistrer() async {
    _textes[_ouvert] = _ctrl.text;
    setState(() => _etat = '…');
    final ok = await enregistrerConsignesPreop(widget.profileId, _textes);
    if (mounted) setState(() => _etat = ok ? 'Enregistré' : 'Non enregistré, réessayez');
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Consignes avant une intervention',
            style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: _teal)),
        const SizedBox(height: 4),
        Text('Envoyées au propriétaire à la prise d’un RDV « Intervention » et rappelées la veille. Modifiables pour chaque RDV.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in kSousTypesIntervention)
            ChoiceChip(
              label: Text(t.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                  color: _ouvert == t.key ? Colors.white : const Color(0xFF1E2025))),
              selected: _ouvert == t.key, selectedColor: _teal, showCheckmark: false,
              onSelected: (_) => _choisir(t.key),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl, maxLines: 6, minLines: 4,
          onChanged: (_) { if (_etat.isNotEmpty) setState(() => _etat = ''); },
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
          decoration: InputDecoration(filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.all(10)),
        ),
        const SizedBox(height: 6),
        Row(children: [
          ElevatedButton(
            onPressed: _etat == '…' ? null : _enregistrer,
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
            child: const Text('Enregistrer les consignes', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          if (_etat.isNotEmpty && _etat != '…')
            Text(_etat, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                color: _etat == 'Enregistré' ? const Color(0xFF2E7D5E) : Colors.redAccent)),
        ]),
      ]);
}
