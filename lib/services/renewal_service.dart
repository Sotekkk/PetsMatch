import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class RenewalService {
  static const _username = 'petsmatch.contact@gmail.com';
  static const _password = 'dppu ctgp buve bxjd';

  static Future<void> checkAndSendReminders() async {
    final now = DateTime.now();
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('verificationStatus', isEqualTo: 'approved')
        .where('isElevage', isEqualTo: true)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final validUntilTs = data['validUntil'];
      if (validUntilTs == null) continue;

      final validUntil = (validUntilTs as Timestamp).toDate();
      final daysLeft = validUntil.difference(now).inDays;
      final email = data['email'] ?? '';
      final firstname = data['firstname'] ?? 'utilisateur';
      final nameElevage = data['nameElevage'] ?? '';

      // Compte expiré → repasse en pending
      if (daysLeft < 0) {
        await doc.reference.update({
          'verificationStatus': 'pending',
          'isValidate': false,
          'reminder21Sent': false,
          'reminder15Sent': false,
        });
        if (email.isNotEmpty) {
          await _sendEmail(
            toEmail: email,
            subject: '⚠️ Votre compte PetsMatch doit être renouvelé',
            body: _expiredBody(firstname, nameElevage),
          );
        }
        continue;
      }

      // Relance J-15
      if (daysLeft <= 15 && data['reminder15Sent'] != true) {
        await doc.reference.update({'reminder15Sent': true});
        if (email.isNotEmpty) {
          await _sendEmail(
            toEmail: email,
            subject: '⏰ Rappel : votre compte PetsMatch expire dans $daysLeft jours',
            body: _reminderBody(firstname, nameElevage, daysLeft),
          );
        }
        continue;
      }

      // Relance J-21
      if (daysLeft <= 21 && data['reminder21Sent'] != true) {
        await doc.reference.update({'reminder21Sent': true});
        if (email.isNotEmpty) {
          await _sendEmail(
            toEmail: email,
            subject: '⏰ Rappel : votre compte PetsMatch expire dans $daysLeft jours',
            body: _reminderBody(firstname, nameElevage, daysLeft),
          );
        }
      }
    }
  }

  static Future<void> _sendEmail({
    required String toEmail,
    required String subject,
    required String body,
  }) async {
    final smtpServer = gmail(_username, _password);
    final message = Message()
      ..from = const Address(_username, 'PetsMatch')
      ..recipients.add(toEmail)
      ..subject = subject
      ..text = body;
    try {
      await send(message, smtpServer);
    } catch (_) {}
  }

  static String _reminderBody(
      String firstname, String nameElevage, int daysLeft) {
    return '''Bonjour $firstname,

Votre compte professionnel${nameElevage.isNotEmpty ? ' "$nameElevage"' : ''} sur PetsMatch expire dans $daysLeft jours.

Pour continuer à bénéficier de toutes les fonctionnalités, merci de mettre à jour vos documents (SIRET, KBIS ou attestation RNE) avant la date d\'expiration.

Connectez-vous à l\'application PetsMatch et accédez à votre profil pour soumettre votre dossier de renouvellement, ou contactez-nous à support@petsmatch.fr.

L\'équipe PetsMatch
petsmatch.contact@gmail.com
''';
  }

  static String _expiredBody(String firstname, String nameElevage) {
    return '''Bonjour $firstname,

La période de validité annuelle de votre compte professionnel${nameElevage.isNotEmpty ? ' "$nameElevage"' : ''} sur PetsMatch est arrivée à expiration.

Votre accès aux fonctionnalités professionnelles a été suspendu dans l\'attente du renouvellement de votre dossier.

Pour réactiver votre compte, connectez-vous à l\'application et soumettez vos documents mis à jour, ou contactez-nous à support@petsmatch.fr.

L\'équipe PetsMatch
petsmatch.contact@gmail.com
''';
  }
}
