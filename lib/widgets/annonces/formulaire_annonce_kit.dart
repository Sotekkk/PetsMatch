// Mise en page commune des formulaires « Modifier l'annonce » (adoption,
// cheval, matériel). Purement visuelle : chaque page garde ses champs,
// validations et règles d'enregistrement. Miroir site :
// components/annonces/FormulaireAnnonce.tsx.

import 'package:flutter/material.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

/// Section blanche du formulaire (titre + champs).
class FormSection extends StatelessWidget {
  final String titre;
  final String? description;
  final List<Widget> children;
  const FormSection({super.key, required this.titre, this.description, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kDashBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700, color: kDashInk)),
          if (description != null) ...[
            const SizedBox(height: 2),
            Text(description!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: kDashMuted)),
          ],
          const SizedBox(height: 12),
          ...children,
        ]),
      );
}

/// Champ : libellé au-dessus (mention obligatoire), puis le contrôle.
class FormChamp extends StatelessWidget {
  final String label;
  final bool requis;
  final String? aide;
  final Widget child;
  const FormChamp({super.key, required this.label, this.requis = false, this.aide, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: label),
            if (requis) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFB91C1C))),
          ]), style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600, color: kDashInk)),
          const SizedBox(height: 6),
          child,
          if (aide != null) ...[
            const SizedBox(height: 4),
            Text(aide!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
          ],
        ]),
      );
}

/// Décoration commune des champs de saisie.
InputDecoration formDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF9CA3AF)),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDashBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDashBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDashTeal, width: 1.5)),
    );

/// Zone d'actions unique (Annuler + Enregistrer), en bas de l'écran : reste
/// derrière le clavier, sans recouvrir les champs.
class FormActions extends StatelessWidget {
  final bool saving;
  final String libelle;
  final VoidCallback onEnregistrer;
  const FormActions({super.key, required this.saving, required this.libelle, required this.onEnregistrer});

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kDashBorder))),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: kDashInk, side: const BorderSide(color: kDashBorder),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: ElevatedButton(
              onPressed: saving ? null : onEnregistrer,
              style: ElevatedButton.styleFrom(
                backgroundColor: kDashTeal, foregroundColor: Colors.white, elevation: 0,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(libelle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      );
}
