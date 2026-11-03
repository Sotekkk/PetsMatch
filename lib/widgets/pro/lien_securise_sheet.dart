// Lien sécurisé par document (lot 6 des documents vétérinaires) : lien
// individuel (1, 7 ou 30 jours ; 7 par défaut), copié / partagé ou envoyé par
// e-mail avec un message personnalisable ; liens existants (accès,
// expiration) et révocation. « Envoyé » n'est affiché qu'après confirmation
// du service d'envoi. Routes du site : /api/liens-documents.
// Miroir site : website/src/components/pro/LienSecuriseModal.tsx.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/utils/site_api.dart';

const _teal = Color(0xFF0C5C6C);

String _messageDefaut(String animal) => 'Bonjour,\n\nVous trouverez les documents relatifs à la prise en charge de '
    '${animal.isEmpty ? 'votre animal' : animal}.\n\nIls comprennent les recommandations et les documents établis par votre vétérinaire.\n\n'
    'Nous vous invitons à les conserver et à contacter la clinique si vous avez des questions.\n\nCordialement,\n\nL’équipe vétérinaire.';

String _jj(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// [url] : PDF stocké ; [genererUrl] : le produit et le dépose (compte rendu sans PDF).
Future<void> ouvrirLienSecurise(BuildContext context, {
  String? url,
  Future<String> Function()? genererUrl,
  String? crId,
  required String type, // 'ordonnance' | 'compte_rendu' | 'consignes'
  required String titre,
  String animalNom = '',
  String expediteur = '',
  String? emailParDefaut,
  String? destinataireNom,
}) => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => _LienSecurisePage(
      url: url, genererUrl: genererUrl, crId: crId, type: type, titre: titre, animalNom: animalNom,
      expediteur: expediteur, emailParDefaut: emailParDefaut, destinataireNom: destinataireNom)));

class _LienSecurisePage extends StatefulWidget {
  final String? url, crId, emailParDefaut, destinataireNom;
  final Future<String> Function()? genererUrl;
  final String type, titre, animalNom, expediteur;
  const _LienSecurisePage({this.url, this.genererUrl, this.crId, required this.type, required this.titre,
      required this.animalNom, required this.expediteur, this.emailParDefaut, this.destinataireNom});
  @override
  State<_LienSecurisePage> createState() => _LienSecurisePageState();
}

class _LienSecurisePageState extends State<_LienSecurisePage> {
  String? _url;
  int _jours = 7;
  late final _email = TextEditingController(text: widget.emailParDefaut ?? '');
  late final _message = TextEditingController(text: _messageDefaut(widget.animalNom));
  List<Map<String, dynamic>> _liens = [];
  ({String lien, bool envoye, String expire})? _resultat;
  String? _occupe, _erreur;

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _charger();
  }

  @override
  void dispose() { _email.dispose(); _message.dispose(); super.dispose(); }

  Future<void> _charger() async {
    if (_url == null) return;
    try {
      final r = await http.get(Uri.parse('$kSiteBaseUrl/api/liens-documents?url=${Uri.encodeComponent(_url!)}'), headers: await siteApiHeaders());
      if (r.statusCode == 200 && mounted) {
        setState(() => _liens = List<Map<String, dynamic>>.from((jsonDecode(r.body)['liens'] as List?) ?? const []));
      }
    } catch (_) {}
  }

  Future<void> _creer(bool envoyer) async {
    setState(() { _occupe = envoyer ? 'envoyer' : 'creer'; _erreur = null; _resultat = null; });
    try {
      var u = _url;
      if (u == null && widget.genererUrl != null) { u = await widget.genererUrl!(); _url = u; }
      if (u == null) throw 'document indisponible';
      final r = await http.post(Uri.parse('$kSiteBaseUrl/api/liens-documents'), headers: await siteApiHeaders(), body: jsonEncode({
        'url': u, 'document_type': widget.type, 'titre': widget.titre, 'animal_nom': widget.animalNom,
        'expediteur_nom': widget.expediteur, if (widget.crId != null) 'cr_id': widget.crId, 'jours': _jours, 'envoyer': envoyer,
        if (envoyer && _email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        if (widget.destinataireNom != null) 'destinataire_nom': widget.destinataireNom,
        if (envoyer) 'message': _message.text,
      }));
      final j = jsonDecode(r.body.isEmpty ? '{}' : r.body) as Map<String, dynamic>;
      if (j['lien'] != null) {
        _resultat = (lien: j['lien'].toString(), envoye: j['envoye'] == true, expire: (j['expire_le'] ?? '').toString());
      }
      if (r.statusCode >= 300) {
        _erreur = j['code'] == 'sans_email' ? 'Aucune adresse e-mail connue pour ce propriétaire : saisissez-la.'
            : '${j['lien'] != null ? 'Lien créé, mais l’e-mail n’est pas parti' : 'Échec'} : ${j['error'] ?? r.statusCode}';
      }
      await _charger();
    } catch (e) {
      _erreur = 'Échec : $e';
    } finally {
      if (mounted) setState(() => _occupe = null);
    }
  }

  Future<void> _revoquer(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      content: const Text('Désactiver ce lien ? Il n’ouvrira plus le document.', style: TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Désactiver', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/liens-documents/revoquer'), headers: await siteApiHeaders(),
        body: jsonEncode({'id': id}));
    if (r.statusCode != 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Révocation impossible.')));
    }
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700);
    final res = _resultat;
    return Scaffold(
      appBar: AppBar(title: Text('Lien sécurisé — ${widget.titre}', style: const TextStyle(fontFamily: 'Galey', fontSize: 16)),
          backgroundColor: Colors.white, foregroundColor: const Color(0xFF1E2025), elevation: 0.5),
      backgroundColor: Colors.white,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        const Text('Le lien n’ouvre que ce document, sans compte, jusqu’à sa date d’expiration ; vous pouvez le désactiver à tout moment. Chaque ouverture est enregistrée.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF6B7280))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final n in [1, 7, 30])
            ChoiceChip(label: Text('$n jour${n > 1 ? 's' : ''}', style: const TextStyle(fontFamily: 'Galey')),
                selected: _jours == n, selectedColor: _teal.withValues(alpha: 0.15), onSelected: (_) => setState(() => _jours = n)),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(
            labelText: 'E-mail du destinataire', hintText: 'Vide : adresse du compte PetsMatch du propriétaire', isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
        const SizedBox(height: 10),
        TextField(controller: _message, minLines: 6, maxLines: null, decoration: InputDecoration(labelText: 'Message', isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _occupe != null ? null : () => _creer(false),
              style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
              child: Text(_occupe == 'creer' ? 'Création…' : 'Créer le lien', style: style))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: _occupe != null ? null : () => _creer(true),
              style: FilledButton.styleFrom(backgroundColor: _teal),
              child: Text(_occupe == 'envoyer' ? 'Envoi…' : 'Créer et envoyer', style: style))),
        ]),
        if (_erreur != null) Padding(padding: const EdgeInsets.only(top: 10),
            child: Text(_erreur!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.red))),
        if (res != null) Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF4F7F8), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (res.envoye) const Text('E-mail envoyé (confirmé par le service d’envoi).',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF2E7D32), fontWeight: FontWeight.w700)),
            Text('Lien valable jusqu’au ${_jj(res.expire)} :', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
            SelectableText(res.lien, style: const TextStyle(fontSize: 12)),
            Align(alignment: Alignment.centerRight, child: TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: res.lien));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié.')));
              },
              child: const Text('Copier le lien', style: TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700)))),
          ]),
        ),
        if (_liens.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Liens de ce document', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          for (final l in _liens) () {
            final expire = DateTime.tryParse((l['expire_le'] ?? '').toString());
            final revoque = l['revoque_le'] != null;
            final actif = !revoque && expire != null && expire.isAfter(DateTime.now());
            final nb = (l['nb_acces'] as num?)?.toInt() ?? 0;
            return ListTile(
              contentPadding: EdgeInsets.zero, dense: true,
              title: Text('${_jj((l['created_at'] ?? '').toString())}${(l['destinataire_email'] ?? '').toString().isNotEmpty ? ' → ${l['destinataire_email']}' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              subtitle: Text('${revoque ? 'Désactivé' : actif ? 'Actif jusqu’au ${_jj(l['expire_le'].toString())}' : 'Expiré'} · '
                  '$nb ouverture${nb > 1 ? 's' : ''}${l['dernier_acces_le'] != null ? ' (dernière le ${_jj(l['dernier_acces_le'].toString())})' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              trailing: actif ? TextButton(onPressed: () => _revoquer(l['id'].toString()),
                  child: const Text('Désactiver', style: TextStyle(fontFamily: 'Galey', color: Colors.red))) : null,
            );
          }(),
        ],
      ]),
    );
  }
}
