/// Valeur d'une ligne « Libellé : valeur » des PDF (race, sexe, motif…) :
/// première lettre en majuscule, et après chaque séparateur « · », « — », « / »
/// (« chien · berger allemand » → « Chien · Berger allemand »).
/// Miroir site : website/src/lib/majuscule.ts.
String majuscule(String valeur) => valeur.replaceAllMapped(
    RegExp(r'(^\s*|[·—/]\s*)(\p{Ll})', unicode: true), (m) => '${m[1]}${m[2]!.toUpperCase()}');
