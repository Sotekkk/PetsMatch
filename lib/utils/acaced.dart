// ACACED : valable 10 ans après l'obtention (ou la dernière formation
// d'actualisation). Miroir site : components/AcacedActualisation.tsx.

/// Fin de validité : 10 ans après la date, null si pas de date.
DateTime? acacedFinValidite(DateTime? d) =>
    d == null ? null : DateTime(d.year + 10, d.month, d.day);

/// Vrai si l'ACACED obtenu (ou actualisé) à cette date est expiré aujourd'hui.
bool acacedExpire(DateTime? d) {
  final fin = acacedFinValidite(d);
  return fin != null && fin.isBefore(DateTime.now());
}
