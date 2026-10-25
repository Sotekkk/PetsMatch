// Confirmation de suppression d'une entrée du carnet de santé, précise :
// « Supprimer ce vaccin « Nobivac » ? » plutôt que « cette entrée ».
// Miroir site : website/src/lib/sante-libelles.ts.
import 'package:flutter/material.dart';

/// Rubrique du carnet → « ce vaccin », « ce traitement »…
const kSanteSuppressionLibelles = {
  'vaccinations': 'ce vaccin',
  'vermifuges': 'ce vermifuge',
  'antiparasitaires': 'cet antiparasitaire',
  'traitements': 'ce traitement',
  'chirurgies': 'cette chirurgie / hospitalisation',
  'allergies': 'cette allergie',
  'poids': 'cette pesée',
  'visites': 'cette visite vétérinaire',
  'radios': 'cette radio / imagerie',
  'tests_genetiques': 'ce test génétique',
};

/// true si l'utilisateur confirme la suppression.
Future<bool> confirmerSuppressionSante(BuildContext context, String table, {String? nom}) async {
  final quoi = kSanteSuppressionLibelles[table] ?? 'cette entrée du carnet';
  final n = (nom ?? '').trim();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Supprimer $quoi${n.isNotEmpty ? ' « $n »' : ''} ?',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
      content: const Text('Cette action est irréversible.', style: TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
        TextButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  return ok == true;
}
