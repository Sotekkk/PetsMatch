// Contacter un client par le moyen de son choix : messagerie PetsMatch (s'il
// a un compte), appel, SMS, WhatsApp, e-mail. Chaque bouton n'apparaît que
// si la coordonnée existe. Miroir site : website/src/components/ContactCanaux.tsx.
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';

const _teal = Color(0xFF0C5C6C);

/// Numéro au format international pour WhatsApp (06… → 336…).
String waNumero(String brut) {
  var d = brut.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0')) d = '33${d.substring(1)}';
  return d;
}

class ContactCanaux extends StatelessWidget {
  final String? clientUid;
  final String? tel;
  final String? email;
  /// Profil actif de l'expéditeur (conversation rattachée au bon profil pro).
  final String? monProfilId;
  /// Objet pré-rempli de l'e-mail.
  final String? sujet;
  /// Appelé avant d'ouvrir la messagerie (ex. fermer une feuille).
  final VoidCallback? avantMessage;
  const ContactCanaux({super.key, this.clientUid, this.tel, this.email, this.monProfilId, this.sujet, this.avantMessage});

  Future<void> _ouvrir(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Impossible d'ouvrir ${uri.scheme}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (tel ?? '').trim(), m = (email ?? '').trim();
    final chiffres = t.replaceAll(RegExp(r'[^0-9+]'), '');
    final boutons = <(Widget, String, Future<void> Function())>[
      if ((clientUid ?? '').isNotEmpty)
        (const Icon(Icons.chat_bubble_outline, size: 16), 'Message', () async {
          final nav = Navigator.of(context);
          avantMessage?.call();
          final conv = await MessagingHelper.openOrCreateConversation(
              otherUid: clientUid!, categorie: 'services', myProfileId: (monProfilId ?? '').isNotEmpty ? monProfilId : null);
          await nav.push(MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conv, eleveurId: clientUid!)));
        }),
      if (chiffres.isNotEmpty) ...[
        (const Icon(Icons.call_outlined, size: 16), 'Appeler', () => _ouvrir(context, Uri(scheme: 'tel', path: chiffres))),
        (const Icon(Icons.sms_outlined, size: 16), 'SMS', () => _ouvrir(context, Uri(scheme: 'sms', path: chiffres))),
        (const FaIcon(FontAwesomeIcons.whatsapp, size: 16), 'WhatsApp', () => _ouvrir(context, Uri.parse('https://wa.me/${waNumero(t)}'))),
      ],
      if (m.isNotEmpty)
        (const Icon(Icons.mail_outline, size: 16), 'E-mail', () => _ouvrir(context, Uri(scheme: 'mailto', path: m,
            query: (sujet ?? '').isNotEmpty ? 'subject=${Uri.encodeComponent(sujet!)}' : null))),
    ];
    if (boutons.isEmpty) {
      return Text('Aucune coordonnée pour ce client.', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade500));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final b in boutons)
        OutlinedButton.icon(
          onPressed: b.$3,
          icon: b.$1,
          label: Text(b.$2, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _teal, side: const BorderSide(color: Color(0xFFE0E3E0)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: const Size(0, 36),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
    ]);
  }
}
