import 'package:flutter/material.dart';

/// Espèces proposées pour les lieux pet-friendly (choix de l'établissement et
/// filtre de recherche). Miroir site : website/src/lib/especes-lieux.ts.
const kEspecesLieux = [
  ('chien', 'Chien'), ('chat', 'Chat'), ('cheval', 'Cheval'), ('lapin', 'Lapin'),
  ('oiseau', 'Oiseau'), ('nac', 'NAC'), ('ovin', 'Ovin'), ('caprin', 'Caprin'),
  ('porcin', 'Porc'), ('autre', 'Autre'),
];

/// Liste déroulante à cases à cocher (« Tout cocher » en tête), sans icône.
class ListeEspecesACocher extends StatelessWidget {
  final Set<String> selection;
  final ValueChanged<Set<String>> onChanged;
  final List<(String, String)> especes;
  final String vide;

  const ListeEspecesACocher({
    super.key,
    required this.selection,
    required this.onChanged,
    this.especes = kEspecesLieux,
    this.vide = 'Choisir les espèces',
  });

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0C5C6C);
    final tout = especes.every((e) => selection.contains(e.$1));
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            selection.isEmpty
                ? vide
                : tout
                    ? 'Toutes les espèces'
                    : especes.where((e) => selection.contains(e.$1)).map((e) => e.$2).join(', '),
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: selection.isEmpty ? Colors.grey.shade500 : const Color(0xFF1F2A2E)),
          ),
          children: [
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: teal,
              value: tout,
              onChanged: (v) => onChanged(v == true ? especes.map((e) => e.$1).toSet() : <String>{}),
              title: const Text('Tout cocher',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            for (final e in especes)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: teal,
                value: selection.contains(e.$1),
                onChanged: (v) {
                  final s = {...selection};
                  v == true ? s.add(e.$1) : s.remove(e.$1);
                  onChanged(s);
                },
                title: Text(e.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}
