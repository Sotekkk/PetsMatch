// « Récupérer mon animal » (appli) — appels /api/animaux/recuperer et
// fenêtre affichée quand une puce saisie correspond à un animal déjà
// enregistré (ex. acquis auprès d'un élevage). Miroir site :
// website/src/components/animaux/RecuperationAnimal.tsx.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
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

/// Élevage : invite l'acquéreur (sans compte) à récupérer la fiche. Renvoie
/// un message à afficher (e-mail envoyé ou lien à transmettre).
Future<({String message, String lien})> inviterAcquereur(String animalId) async {
  final r = await appelRecuperation({'action': 'inviter', 'animalId': animalId});
  final lien = '$kSiteBaseUrl/reclamer-animal/${r['token']}';
  final email = r['email']?.toString();
  if (email != null && email.isNotEmpty) {
    try {
      await http.post(Uri.parse('$kSiteBaseUrl/api/animal-claim/notify-email'), headers: await siteApiHeaders(), body: jsonEncode({
        'email': email, 'nom_destinataire': r['nom'], 'animal_nom': r['animalNom'], 'pro_nom': r['proNom'],
        'claim_url': lien, 'contexte': 'cession',
      }));
      return (message: 'Invitation envoyée à $email.', lien: lien);
    } catch (_) {}
  }
  return (message: "Pas d'e-mail connu pour l'acquéreur : transmettez-lui ce lien.", lien: lien);
}
