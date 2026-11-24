import 'package:flutter/material.dart';

/// showDatePicker sans « saut » : à la fermeture du calendrier, Flutter
/// redonne le focus au dernier champ texte touché (ex. « Poids ») et fait
/// défiler la page jusqu'à lui. On retire le focus avant d'ouvrir, pour que
/// la personne reste là où elle saisit.
Future<DateTime?> choisirDate({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  TransitionBuilder? builder,
  Locale? locale,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    builder: builder,
    locale: locale,
  );
}
