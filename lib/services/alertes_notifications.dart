import 'package:cloud_functions/cloud_functions.dart';

Future<void> runMatchLostFound({
  required String alerteId,
  required String type, // 'perdu' | 'trouve'
}) async {
  try {
    final fn = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('matchLostFound');
    await fn.call({'alerteId': alerteId, 'type': type});
  } catch (_) {}
}

Future<void> notifyNearbyUsersAboutLostAnimal({
  required double lat,
  required double lng,
  required String nomAnimal,
  String? espece,
  required String alerteId,
  required String proprietaireUid,
}) async {
  try {
    final fn = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('notifyUsersNearLostAnimal');
    await fn.call({
      'lat': lat,
      'lng': lng,
      'nomAnimal': nomAnimal,
      'espece': espece,
      'alerteId': alerteId,
      'proprietaireUid': proprietaireUid,
    });
  } catch (_) {}
}
