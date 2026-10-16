// « Récupérer mon animal » (appli) — appels /api/animaux/recuperer et
// fenêtre affichée quand une puce saisie correspond à un animal déjà
// enregistré (ex. acquis auprès d'un élevage). Miroir site :
// website/src/components/animaux/RecuperationAnimal.tsx.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl, kStoreAndroid, kStoreIos;
import 'package:PetsMatch/utils/site_api.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);

Future<Map<String, dynamic>> appelRecuperation(Map<String, dynamic> body) async {
  final r = await http.post(Uri.parse('$kSiteBaseUrl/api/animaux/recuperer'), headers: await siteApiHeaders(), body: jsonEncode(body));
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  if (r.statusCode != 200) throw Exception(j['error'] ?? 'Opération impossible');
  return j;
}

/// État d'une puce pour l'utilisateur : aucun | deja_a_vous | detenu | recuperable.
Future<Map<String, dynamic>> verifierPuce(String puce) => appelRecuperation({'action': 'verifier', 'puce': puce});

/// Fenêtre « animal déjà enregistré ». Renvoie l'id de l'animal rattaché
/// (récupéré directement), sinon null.
Future<String?> showRecuperationAnimal(BuildContext context, Map<String, dynamic> verif, {String? profileId}) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _RecuperationSheet(verif: verif, profileId: profileId),
  );
}

class _RecuperationSheet extends StatefulWidget {
  final Map<String, dynamic> verif;
  final String? profileId;
  const _RecuperationSheet({required this.verif, this.profileId});

  @override
  State<_RecuperationSheet> createState() => _RecuperationSheetState();
}

class _RecuperationSheetState extends State<_RecuperationSheet> {
  final _message = TextEditingController();
  bool _envoi = false;
  late bool _demandee = widget.verif['demandeEnCours'] == true;
  String? _erreur;

  Map get _a => (widget.verif['animal'] as Map?) ?? {};
  String get _nom => _a['nom']?.toString() ?? 'Cet animal';

  Future<void> _rattacher() async {
    setState(() { _envoi = true; _erreur = null; });
    try {
      await appelRecuperation({'action': 'rattacher', 'animalId': _a['id'], 'profileId': widget.profileId});
      if (mounted) Navigator.pop(context, _a['id']?.toString());
    } catch (e) {
      setState(() { _erreur = e.toString().replaceFirst('Exception: ', ''); _envoi = false; });
    }
  }

  Future<void> _demander() async {
    setState(() { _envoi = true; _erreur = null; });
    try {
      await appelRecuperation({'action': 'demander', 'animalId': _a['id'], 'profileId': widget.profileId, 'message': _message.text.trim()});
      setState(() { _demandee = true; _envoi = false; });
    } catch (e) {
      setState(() { _erreur = e.toString().replaceFirst('Exception: ', ''); _envoi = false; });
    }
  }

  Text _t(String s, {double taille = 13.5, FontWeight? w, Color? c}) =>
      Text(s, style: TextStyle(fontFamily: 'Galey', fontSize: taille, fontWeight: w, color: c ?? _ink, height: 1.4));

  @override
  Widget build(BuildContext context) {
    final etat = widget.verif['etat'];
    return SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (etat == 'deja_a_vous') ...[
          _t('$_nom est déjà dans vos animaux', taille: 16, w: FontWeight.w700),
          const SizedBox(height: 6),
          _t('Cette puce correspond à une fiche qui vous appartient déjà.', c: Colors.grey.shade700),
        ] else if (etat == 'detenu') ...[
          _t('Puce déjà enregistrée', taille: 16, w: FontWeight.w700),
          const SizedBox(height: 6),
          _t('Cette puce est enregistrée sur PetsMatch pour un animal appartenant à un autre compte. Vérifiez le numéro saisi ; '
              'si cet animal est le vôtre, contactez son propriétaire actuel ou notre équipe.', c: Colors.grey.shade700),
        ] else ...[
          Row(children: [
            if ((_a['photo_url']?.toString() ?? '').isNotEmpty)
              Padding(padding: const EdgeInsets.only(right: 12),
                  child: ClipRRect(borderRadius: BorderRadius.circular(12),
                      child: Image.network(_a['photo_url'].toString(), width: 56, height: 56, fit: BoxFit.cover))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _t('$_nom est déjà enregistré', taille: 16, w: FontWeight.w700),
              _t([if ((_a['race']?.toString() ?? '').isNotEmpty) _a['race'].toString(),
                  if ((widget.verif['elevage']?.toString() ?? '').isNotEmpty) 'par ${widget.verif['elevage']}'].join(' · '),
                  taille: 12.5, c: Colors.grey.shade600),
            ])),
          ]),
          const SizedBox(height: 10),
          if (_demandee)
            _t("Votre demande a été envoyée à l'élevage. Vous serez prévenu dès qu'il l'aura validée : "
                "l'animal apparaîtra alors dans vos animaux, avec sa fiche complète.")
          else if (widget.verif['correspondance'] == true) ...[
            _t("Vos coordonnées correspondent à celles de l'acquéreur enregistré par l'élevage. Récupérez sa fiche complète "
                "(identité, généalogie, carnet de santé, documents) plutôt que d'en créer une nouvelle."),
            const SizedBox(height: 10),
            FilledButton(onPressed: _envoi ? null : _rattacher, style: FilledButton.styleFrom(backgroundColor: _teal),
                child: Text('Rattacher $_nom à mon compte', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
          ] else ...[
            _t("Si c'est votre animal, demandez à l'élevage de vous transmettre sa fiche complète plutôt que d'en créer une nouvelle."),
            const SizedBox(height: 8),
            TextField(controller: _message, maxLines: 2, decoration: const InputDecoration(hintText: "Un mot pour l'élevage (facultatif)", border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 10),
            FilledButton(onPressed: _envoi ? null : _demander, style: FilledButton.styleFrom(backgroundColor: _teal),
                child: const Text('Demander à récupérer sa fiche', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
          ],
        ],
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 8), child: _t(_erreur!, c: const Color(0xFFB3261E))),
        const SizedBox(height: 6),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer', style: TextStyle(fontFamily: 'Galey'))),
      ]),
    ));
  }
}

/// Invitation créée pour l'acquéreur (lien + coordonnées connues).
class InvitationAcquereur {
  final String lien, prenom, nom, animalNom, proNom;
  final String? email, tel;
  const InvitationAcquereur({required this.lien, required this.prenom, required this.nom, required this.animalNom,
      required this.proNom, this.email, this.tel});

  String get message => 'Bonjour${prenom.isNotEmpty ? ' $prenom' : ''}, ${proNom.isNotEmpty ? proNom : 'votre éleveur'} '
      'vous invite à retrouver $animalNom sur PetsMatch : sa fiche (identité, généalogie, carnet de santé, documents) vous attend. '
      "Ouvrez ce lien pour la récupérer, en créant votre compte sur le site ou dans l'application PetsMatch : $lien"
      ' — Application : Android $kStoreAndroid · iPhone $kStoreIos';

  /// Numéro au format international pour WhatsApp (06… → 336…).
  String? get telInternational {
    final d = (tel ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    if (d.startsWith('00')) return d.substring(2);
    if (d.startsWith('0') && d.length == 10) return '33${d.substring(1)}';
    return d;
  }

  /// E-mail envoyé par PetsMatch (si l'adresse de l'acquéreur est connue).
  Future<bool> envoyerEmail() async {
    if (email == null || email!.isEmpty) return false;
    try {
      final r = await http.post(Uri.parse('$kSiteBaseUrl/api/animal-claim/notify-email'), headers: await siteApiHeaders(), body: jsonEncode({
        'email': email, 'nom_destinataire': '$prenom $nom'.trim(), 'animal_nom': animalNom, 'pro_nom': proNom,
        'claim_url': lien, 'contexte': 'cession',
      }));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// Élevage : crée le lien d'invitation de l'acquéreur (sans compte).
Future<InvitationAcquereur> inviterAcquereur(String animalId) async {
  final r = await appelRecuperation({'action': 'inviter', 'animalId': animalId});
  return InvitationAcquereur(
    lien: '$kSiteBaseUrl/reclamer-animal/${r['token']}',
    prenom: r['prenom']?.toString() ?? '', nom: r['nom']?.toString() ?? '',
    animalNom: r['animalNom']?.toString() ?? 'votre animal', proNom: r['proNom']?.toString() ?? '',
    email: r['email']?.toString(), tel: r['tel']?.toString(),
  );
}
