import 'package:PetsMatch/pages/pro/garde_facture_helper.dart' show estGardeJournee;

/// Regroupement des lignes `rdv` de type garde-journée en "séjours" (garde à
/// domicile chez le prestataire, hébergement) — pour la tournée et le
/// registre légal. Une ligne `rdv` = un jour ; un séjour = une suite de jours
/// consécutifs (même client + même animal). Les promenades/visites à
/// domicile client ne sont jamais des séjours (l'animal reste chez lui,
/// non soumis au registre légal — cf. supabase/migration_garde_presence.sql).
class GardeSejour {
  final String? animalId;
  final String? clientUid;
  final String? clientProfileId;
  final List<Map<String, dynamic>> jours; // triés par date croissante
  final DateTime dateEntree;
  final DateTime dateSortiePrevue;
  final DateTime? arriveeValideeLe;
  final DateTime? departValideLe;

  GardeSejour({
    required this.animalId,
    required this.clientUid,
    required this.clientProfileId,
    required this.jours,
  })  : dateEntree = DateTime.parse(jours.first['date_heure'].toString()),
        dateSortiePrevue = DateTime.parse(jours.last['date_heure'].toString()),
        arriveeValideeLe = DateTime.tryParse(jours.first['arrivee_validee_le']?.toString() ?? ''),
        departValideLe = DateTime.tryParse(jours.last['depart_valide_le']?.toString() ?? '');

  /// 'a_venir' (aucune validation) → 'en_garde' (arrivée validée) → 'termine' (départ validé).
  String get statut {
    if (departValideLe != null) return 'termine';
    if (arriveeValideeLe != null) return 'en_garde';
    return 'a_venir';
  }

  String get animalNom => (jours.first['_animal_nom'] ?? jours.first['animal_nom'] ?? 'Animal').toString();
  String get clientNom => (jours.first['_client_nom'] ?? jours.first['_client_name'] ?? 'Client').toString();

  Map<String, dynamic> get premierJour => jours.first;
  Map<String, dynamic> get dernierJour => jours.last;
  bool get unSeulJour => jours.length == 1;
}

/// Regroupe une liste de `rdv` (déjà filtrée sur le statut voulu, avec
/// `_animal_nom`/`_client_nom` déjà résolus par l'appelant) en séjours
/// garde-journée. Les autres motifs (promenade/visite) sont ignorés — à
/// afficher séparément par l'appelant, en cartes individuelles.
List<GardeSejour> groupeGardeSejours(List<Map<String, dynamic>> rdvRows) {
  final joursGarde = rdvRows.where(estGardeJournee).toList()
    ..sort((a, b) {
      final da = DateTime.tryParse(a['date_heure']?.toString() ?? '') ?? DateTime(0);
      final db = DateTime.tryParse(b['date_heure']?.toString() ?? '') ?? DateTime(0);
      return da.compareTo(db);
    });

  final sejours = <GardeSejour>[];
  var courant = <Map<String, dynamic>>[];
  String? courantClient;
  String? courantAnimal;
  DateTime? dernierJourDate;

  void cloture() {
    if (courant.isNotEmpty) {
      sejours.add(GardeSejour(
        animalId: courantAnimal,
        clientUid: courantClient,
        clientProfileId: courant.first['client_profile_id']?.toString(),
        jours: courant,
      ));
    }
  }

  for (final r in joursGarde) {
    final clientUid = r['client_uid']?.toString();
    final animalId = r['animal_id']?.toString();
    final date = DateTime.tryParse(r['date_heure']?.toString() ?? '');
    if (date == null) continue;
    final jourSeul = DateTime(date.year, date.month, date.day);

    final memeChaine = courant.isNotEmpty &&
        clientUid == courantClient &&
        animalId == courantAnimal &&
        dernierJourDate != null &&
        jourSeul.difference(dernierJourDate).inDays <= 1;

    if (!memeChaine) {
      cloture();
      courant = [];
      courantClient = clientUid;
      courantAnimal = animalId;
    }
    courant.add(r);
    dernierJourDate = jourSeul;
  }
  cloture();

  return sejours;
}
