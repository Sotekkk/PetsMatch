// Questionnaire de consignes avant un rendez-vous (toiletteur ; structure par
// métier pour pouvoir l'étendre) et appels à
// la route du site /api/rdv/consignes (lecture, enregistrement, demande au
// client). Miroir site : website/src/lib/consignes-rdv.ts (mêmes clés).
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/utils/site_api.dart';

class QuestionConsigne {
  final String cle, label;
  final String? aide;
  final List<String>? choix;
  const QuestionConsigne(this.cle, this.label, {this.aide, this.choix});
}

const _comportement = QuestionConsigne('comportement', 'Comportement à la manipulation',
    aide: "Peur, agressivité, muselière nécessaire, ce qui l'apaise…");

const Map<String, List<QuestionConsigne>> kQuestionnairesConsignes = {
  'toilettage': [
    QuestionConsigne('demande', 'Coupe ou soin souhaité', aide: 'Longueur, style, zones à ne pas couper…'),
    QuestionConsigne('zones_sensibles', 'Zones sensibles', aide: 'Oreilles, pattes, queue, peau irritée…'),
    QuestionConsigne('tolerance_sechoir', 'Tolérance au séchoir', choix: ['Bonne', 'Moyenne', 'Difficile', 'Je ne sais pas']),
    _comportement,
    QuestionConsigne('produits_a_eviter', 'Allergies ou produits à éviter'),
    QuestionConsigne('autre', 'Autre chose à signaler'),
  ],
};

const kMetiersConsignes = {'toilettage'};

List<QuestionConsigne> questionnaireConsignes(String? metier) =>
    kQuestionnairesConsignes[metier ?? ''] ?? const [QuestionConsigne('autre', 'Consignes pour le professionnel')];

/// Réponses non vides avec leur libellé, pour l'affichage côté professionnel.
List<(String, String)> reponsesConsignes(String? metier, Map? reponses) {
  if (reponses == null) return const [];
  return [
    for (final q in questionnaireConsignes(metier))
      if ((reponses[q.cle]?.toString() ?? '').trim().isNotEmpty) (q.label, reponses[q.cle].toString().trim()),
  ];
}

Map<String, dynamic> _json(http.Response r) {
  try {
    return jsonDecode(r.body) as Map<String, dynamic>;
  } on FormatException {
    return {'error': 'Service momentanément indisponible (${r.statusCode}).'};
  }
}

class ConsignesApi {
  /// Contexte du rendez-vous, questionnaire, réponses déjà saisies et
  /// préremplissage (consignes du rendez-vous précédent chez ce pro).
  static Future<Map<String, dynamic>> charger(String rdvId) async {
    final r = await http.get(Uri.parse('$kSiteBaseUrl/api/rdv/consignes?rdvId=${Uri.encodeComponent(rdvId)}'), headers: await siteApiHeaders());
    final j = _json(r);
    if (r.statusCode != 200) throw Exception(j['error'] ?? 'Consignes indisponibles');
    return j;
  }

  static Future<void> enregistrer(String rdvId, Map<String, String> reponses) async {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/rdv/consignes'), headers: await siteApiHeaders(),
        body: jsonEncode({'rdvId': rdvId, 'reponses': reponses}));
    if (r.statusCode != 200) throw Exception(_json(r)['error'] ?? 'Enregistrement impossible');
  }

  /// Professionnel : demande les consignes au client (notification + e-mail).
  static Future<({bool notifie, bool email})> demander(String rdvId) async {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/rdv/consignes'), headers: await siteApiHeaders(),
        body: jsonEncode({'action': 'demander', 'rdvId': rdvId}));
    final j = _json(r);
    if (r.statusCode != 200) throw Exception(j['error'] ?? 'Demande impossible');
    return (notifie: j['notifie'] == true, email: j['email_envoye'] == true);
  }
}
