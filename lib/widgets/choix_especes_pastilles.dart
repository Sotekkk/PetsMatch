import 'package:flutter/material.dart';

/// Espèces proposées au particulier (espèces possédées et projet d'adoption).
/// Même liste que le site (website/src/lib/especes-particulier.ts) — codes
/// enregistrés dans user_profiles.especes_possedees / especes_projet.
const kEspecesParticulier = [
  ('chien', 'Chien'), ('chat', 'Chat'), ('lapin', 'Lapin'), ('cheval', 'Cheval'),
  ('oiseau', 'Oiseau'), ('nac', 'NAC'), ('reptile', 'Reptile'), ('autre', 'Autre'),
];

/// Choix d'espèces à cocher : une fois validé, le champ n'affiche plus que les
/// espèces retenues (pastilles) ; toucher le champ rouvre la liste
/// (« Tout cocher » en tête, sans icône) dans une feuille à valider.
class ChoixEspecesPastilles extends StatelessWidget {
  final Set<String> selection;
  final ValueChanged<Set<String>> onChanged;
  final String titre;
  final List<(String, String)> especes;

  const ChoixEspecesPastilles({
    super.key,
    required this.selection,
    required this.onChanged,
    this.titre = 'Choisir les espèces',
    this.especes = kEspecesParticulier,
  });

  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  Future<void> _ouvrir(BuildContext context) async {
    final choix = {...selection};
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: _green,
              value: especes.every((e) => choix.contains(e.$1)),
              onChanged: (v) => setSheet(() {
                choix.clear();
                if (v == true) choix.addAll(especes.map((e) => e.$1));
              }),
              title: const Text('Tout cocher', style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final e in especes)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: _green,
                    value: choix.contains(e.$1),
                    onChanged: (v) => setSheet(() => v == true ? choix.add(e.$1) : choix.remove(e.$1)),
                    title: Text(e.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.pop(c, choix),
                  child: const Text('Valider', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    if (res != null) onChanged(res);
  }

  @override
  Widget build(BuildContext context) {
    final retenues = especes.where((e) => selection.contains(e.$1)).toList();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _ouvrir(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(
            child: retenues.isEmpty
                ? Text(titre, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500))
                : Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e in retenues)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: _teal.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                        child: Text(e.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                            fontWeight: FontWeight.w600, color: _teal)),
                      ),
                  ]),
          ),
          const SizedBox(width: 8),
          Text(retenues.isEmpty ? '' : 'Modifier',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
          const Icon(Icons.keyboard_arrow_down, color: _teal),
        ]),
      ),
    );
  }
}
