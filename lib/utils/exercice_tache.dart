import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/exercices_progression.dart';

// Exercice d'éducation ↔ tâche du jour dans l'agenda du propriétaire
// (taches_elevage.notes = 'exercice:<id>', créée chaque matin par
// sendExerciceReminders). Cocher la tâche valide la réussite / l'étape du jour ;
// valider l'exercice coche la tâche. Miroir site : lib/exercice-tache.ts.

const kPrefixeTacheExercice = 'exercice:';

String _jour() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Valider l'exercice : la tâche du jour suit (faite / à faire).
Future<void> cocherTacheExercice(String exerciceId, bool fait) async {
  await Supabase.instance.client.from('taches_elevage').update({'statut': fait ? 'fait' : 'a_faire'})
      .eq('notes', '$kPrefixeTacheExercice$exerciceId').eq('date', _jour());
}

/// Tâche « Exercice : … » cochée / décochée dans l'agenda : valide (ou annule)
/// la réussite ou l'étape du jour. Renvoie un message si la base refuse.
Future<String?> validerExerciceDepuisTache(String? notes, bool fait) async {
  if (notes == null || !notes.startsWith(kPrefixeTacheExercice)) return null;
  final id = notes.substring(kPrefixeTacheExercice.length);
  final supa = Supabase.instance.client;
  final ex = await supa.from('exercices_attribues')
      .select('id, statut, validations, nb_validations, etapes_snapshot, echeance').eq('id', id).maybeSingle();
  if (ex == null) return null;
  final p = progressionExercice(ex);
  final aujourdhui = (ex['validations'] as List? ?? const []).map((e) => e.toString()).contains(_jour());
  if (fait && !p.peutValider) return null; // déjà validé aujourd'hui / terminé
  if (!fait && !aujourdhui) return null;
  try {
    await supa.from('exercices_attribues').update(majValidationExercice(ex, valider: fait)).eq('id', id);
    return null;
  } catch (_) {
    return 'L\'exercice n\'a pas pu être validé : réessayez.';
  }
}
