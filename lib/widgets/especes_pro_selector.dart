// Sélecteur des espèces prises en charge par un pro (`especes_acceptees`) :
// champ déroulant → feuille avec « Toutes les espèces », cases à cocher et
// saisie libre d'une autre espèce. Même liste que le filtre de l'annuaire
// (kEspecesPro, lib/utils/annuaire_filtres.dart) ; équivalent site :
// website/src/components/EspecesProSelect.tsx.

import 'package:flutter/material.dart';
import 'package:PetsMatch/utils/annuaire_filtres.dart';

const _green = Color(0xFF6E9E57);

class EspecesProSelector extends StatelessWidget {
  final List<String> selection;
  final ValueChanged<List<String>> onChanged;
  final String hint;

  const EspecesProSelector({
    super.key,
    required this.selection,
    required this.onChanged,
    this.hint = 'Choisir les espèces',
  });

  String get _resume {
    if (selection.isEmpty) return hint;
    final toutes = kEspecesPro.every((e) => selection.contains(e.label));
    final autres = selection.where((s) => !kEspecesPro.any((e) => e.label == s)).toList();
    if (toutes) {
      return autres.isEmpty ? 'Toutes les espèces' : 'Toutes les espèces + ${autres.join(', ')}';
    }
    return selection.join(', ');
  }

  Future<void> _ouvrir(BuildContext context) async {
    final res = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EspecesSheet(initiale: selection),
    );
    if (res != null) onChanged(res);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _ouvrir(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDDDDD)),
        ),
        child: Row(children: [
          const Icon(Icons.pets, size: 18, color: _green),
          const SizedBox(width: 10),
          Expanded(child: Text(_resume,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Galey', fontSize: 14,
              color: selection.isEmpty ? Colors.grey.shade500 : const Color(0xFF1E2025)))),
          const Icon(Icons.arrow_drop_down, color: Colors.grey),
        ]),
      ),
    );
  }
}

class _EspecesSheet extends StatefulWidget {
  final List<String> initiale;
  const _EspecesSheet({required this.initiale});

  @override
  State<_EspecesSheet> createState() => _EspecesSheetState();
}

class _EspecesSheetState extends State<_EspecesSheet> {
  late final Set<String> _sel = widget.initiale.toSet();
  late final List<String> _autres =
      widget.initiale.where((s) => !kEspecesPro.any((e) => e.label == s)).toList();
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool? get _toutes {
    final n = kEspecesPro.where((e) => _sel.contains(e.label)).length;
    if (n == 0) return false;
    return n == kEspecesPro.length ? true : null;
  }

  void _ajouterAutre() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    final dejaListe = kEspecesPro.where((e) => e.label.toLowerCase() == v.toLowerCase());
    setState(() {
      if (dejaListe.isNotEmpty) {
        _sel.add(dejaListe.first.label);
      } else {
        if (!_autres.any((a) => a.toLowerCase() == v.toLowerCase())) _autres.add(v);
        _sel.add(_autres.firstWhere((a) => a.toLowerCase() == v.toLowerCase()));
      }
      _ctrl.clear();
    });
  }

  List<String> get _resultat => [
    ...kEspecesPro.map((e) => e.label).where(_sel.contains),
    ..._autres.where(_sel.contains),
  ];

  Widget _case(String label, {String? detail}) => CheckboxListTile(
    value: _sel.contains(label),
    onChanged: (v) => setState(() => v == true ? _sel.add(label) : _sel.remove(label)),
    title: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
    subtitle: detail == null ? null
        : Text(detail, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
    activeColor: _green,
    dense: true,
    controlAffinity: ListTileControlAffinity.leading,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Espèces prises en charge',
                style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700))),
          ),
          Flexible(child: ListView(shrinkWrap: true, children: [
            CheckboxListTile(
              tristate: true,
              value: _toutes,
              onChanged: (_) => setState(() {
                final tout = _toutes == true;
                for (final e in kEspecesPro) {
                  tout ? _sel.remove(e.label) : _sel.add(e.label);
                }
              }),
              title: const Text('Toutes les espèces',
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700)),
              activeColor: _green,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(height: 1),
            for (final e in kEspecesPro) _case(e.label, detail: e.detail),
            for (final a in _autres) _case(a, detail: 'Autre espèce'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                Expanded(child: TextField(
                  controller: _ctrl,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _ajouterAutre(),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Autre espèce (ex : Alpagas)',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                )),
                const SizedBox(width: 8),
                TextButton(onPressed: _ajouterAutre,
                  child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', color: _green))),
              ]),
            ),
          ])),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(context, _resultat),
              child: const Text('Valider', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          )),
        ]),
      ),
    );
  }
}
