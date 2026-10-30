import 'package:flutter/material.dart';

// Motif obligatoire pour refuser ou annuler un RDV : liste + « Autre » à
// préciser. Miroir site : components/rdv/MotifAnnulationChamp.tsx.
const kMotifsAnnulation = [
  'Aucune disponibilité à ce créneau',
  'Empêchement ou urgence de ma part',
  'Fermeture exceptionnelle',
  'À la demande du client',
  'Hors de ma spécialité / espèce non prise en charge',
  'Hors de mon secteur d’intervention',
  'Autre',
];

/// Motifs du client qui annule ou déplace son RDV.
const kMotifsClient = [
  'Empêchement de ma part',
  'Mon animal est malade',
  'Changement d’horaire souhaité',
  'Rendez-vous pris par erreur',
  'Autre',
];

/// [onChanged] reçoit le motif complet, ou '' tant qu'il n'est pas choisi / précisé.
class MotifAnnulationField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  /// Liste proposée (par défaut : motifs du professionnel).
  final List<String> motifs;
  const MotifAnnulationField({super.key, required this.onChanged, this.motifs = kMotifsAnnulation});

  @override
  State<MotifAnnulationField> createState() => _MotifAnnulationFieldState();
}

class _MotifAnnulationFieldState extends State<MotifAnnulationField> {
  String? _choix;
  final _autre = TextEditingController();

  @override
  void dispose() {
    _autre.dispose();
    super.dispose();
  }

  void _maj() => widget.onChanged(_choix == null ? '' : _choix == 'Autre' ? _autre.text.trim() : _choix!);

  @override
  Widget build(BuildContext context) {
    final deco = InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        initialValue: _choix,
        isExpanded: true,
        decoration: deco.copyWith(labelText: 'Motif *'),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1E2025)),
        items: [for (final m in widget.motifs) DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))],
        onChanged: (v) { setState(() => _choix = v); _maj(); },
      ),
      if (_choix == 'Autre') ...[
        const SizedBox(height: 10),
        TextField(
          controller: _autre, autofocus: true, maxLines: 2,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: deco.copyWith(hintText: 'Précisez le motif…'),
          onChanged: (_) => _maj(),
        ),
      ],
    ]);
  }
}
