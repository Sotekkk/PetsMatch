// « Mon abonnement » dans l'appli (13/11/2026) — miroir du site
// (/mon-abonnement) : formule, mensuel / annuel, prochaine échéance, montant,
// état ; pause du mensuel (1 à 3 mois, pas d'annuel), reprise, résiliation en
// fin de période et son annulation. Changer de formule, carte et factures :
// sur le site (paiement jamais dans l'appli — règles Apple / Google).
// API : website/src/app/api/stripe/abonnement/route.ts.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/site_api.dart' show siteApiHeaders;

const _teal = Color(0xFF0C5C6C);
const _vert = Color(0xFF5B8648);

class MonAbonnementPage extends StatefulWidget {
  const MonAbonnementPage({super.key});
  @override
  State<MonAbonnementPage> createState() => _MonAbonnementPageState();
}

class _MonAbonnementPageState extends State<MonAbonnementPage> {
  bool _loading = true;
  String _busy = '';
  Map<String, dynamic>? _a;
  String _pageFormule = '/abonnement';
  String? _msg;
  bool _msgOk = true;

  @override
  void initState() {
    super.initState();
    _appel('infos');
  }

  Future<void> _appel(String action, {Map<String, dynamic> extra = const {}, String? ok}) async {
    setState(() { _busy = action; _msg = null; });
    try {
      final r = await http.post(Uri.parse('$kSiteBaseUrl/api/stripe/abonnement'),
          headers: {...await siteApiHeaders(), 'Content-Type': 'application/json'},
          body: jsonEncode({'action': action,
            'profile_id': User_Info.activeProfileId.isEmpty ? null : User_Info.activeProfileId, ...extra}));
      Map<String, dynamic> j;
      try { j = jsonDecode(r.body) as Map<String, dynamic>; } on FormatException { j = {'error': 'Service momentanément indisponible.'}; }
      if (r.statusCode != 200) throw Exception(j['error'] ?? 'Erreur');
      if (!mounted) return;
      setState(() {
        _a = j['abonnement'] is Map ? Map<String, dynamic>.from(j['abonnement'] as Map) : null;
        _pageFormule = (_a?['page_formule'] ?? j['page_formule'] ?? '/abonnement').toString();
        if (ok != null) { _msg = ok; _msgOk = true; }
      });
    } catch (e) {
      if (mounted) setState(() { _msg = e.toString().replaceFirst('Exception: ', ''); _msgOk = false; });
    } finally {
      if (mounted) setState(() { _busy = ''; _loading = false; });
    }
  }

  Future<void> _site(String path) async {
    if (!await launchUrl(Uri.parse('$kSiteBaseUrl$path'), mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir le navigateur")));
    }
  }

  String _date(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return '—';
    const m = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _pause() async {
    var mois = 1;
    final max = (_a?['pause_max_mois'] as num?)?.toInt() ?? 3;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Mettre en pause', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: _teal)),
          const SizedBox(height: 10),
          Row(children: [
            for (var n = 1; n <= max; n++) ...[
              Expanded(child: ChoiceChip(
                label: Center(child: Text('$n mois', style: TextStyle(fontFamily: 'Galey', color: mois == n ? Colors.white : const Color(0xFF1F2A2E)))),
                selected: mois == n, showCheckmark: false, selectedColor: _teal,
                onSelected: (_) => setM(() => mois = n),
              )),
              if (n < max) const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 10),
          Text("Aucun prélèvement pendant la pause. Votre profil passe en formule Découverte, toutes vos données sont conservées, "
              "et l'abonnement reprend automatiquement à la fin de la pause.",
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
            child: const Text('Confirmer la pause', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ]),
      ))),
    );
    if (ok == true) await _appel('pause', extra: {'mois': mois}, ok: 'Abonnement en pause pour $mois mois.');
  }

  Future<void> _resilier() async {
    final fin = _date(_a?['prochaine_echeance']);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Résilier ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: Text('Votre abonnement ${_a?['plan']} ne sera pas renouvelé. Vous gardez vos fonctionnalités jusqu\'au $fin.',
          style: const TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Résilier', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok == true) await _appel('resilier', ok: 'Résiliation enregistrée : accès jusqu\'au $fin.');
  }

  Widget _bouton(String label, VoidCallback onTap, String cle, {bool principal = false, bool danger = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(width: double.infinity, child: principal
            ? ElevatedButton(onPressed: _busy.isNotEmpty ? null : onTap,
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(_busy == cle ? '…' : label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)))
            : OutlinedButton(onPressed: _busy.isNotEmpty ? null : onTap,
                style: OutlinedButton.styleFrom(foregroundColor: danger ? Colors.red : const Color(0xFF1F2A2E), padding: const EdgeInsets.symmetric(vertical: 13),
                    side: BorderSide(color: danger ? Colors.red.shade200 : Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(_busy == cle ? '…' : label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)))),
      );

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final statut = a?['statut']?.toString() ?? '';
    final mensuel = a?['periodicite'] != 'annuel';
    final resilie = a?['resiliation_prevue'] == true;
    final (etat, couleur) = switch (statut) {
      'pause' => ('En pause jusqu\'au ${_date(a?['pause_jusquau'])}', Colors.orange.shade800),
      'grace' => ('Prélèvement refusé — mettez à jour votre carte avant le ${_date(a?['grace_jusquau'])}', Colors.red.shade700),
      'suspendu' => ('Suspendu : paiement à régulariser', Colors.red.shade700),
      _ => resilie ? ('Résilié — accès jusqu\'au ${_date(a?['prochaine_echeance'])}', Colors.grey.shade700) : ('Actif', _vert),
    };
    final carte = a?['carte'] is Map ? a!['carte'] as Map : null;
    final montant = (a?['montant'] as num?)?.toDouble();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F5),
      appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white,
          title: const Text('Mon abonnement', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: () => _appel('infos'),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (a == null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: const Text('Ce profil est en formule Découverte (gratuite).', style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
                  ),
                  const SizedBox(height: 12),
                  _bouton('Voir les formules sur le site', () => _site(_pageFormule), 'formule', principal: true),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a['plan']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('${mensuel ? 'Abonnement mensuel' : 'Abonnement annuel'} · prélèvement automatique',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      Text(etat, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: couleur)),
                      const Divider(height: 22),
                      Text('${resilie ? 'Fin de l\'accès' : 'Prochaine échéance'} : ${_date(a['prochaine_echeance'])}',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
                      if (montant != null)
                        Text('Montant : ${montant.toStringAsFixed(2).replaceAll('.', ',')} € TTC ${mensuel ? '/ mois' : '/ an'}',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
                      if (carte != null)
                        Text('Carte : ${carte['marque']} •••• ${carte['fin']} — expire ${carte['expire']}',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
                    ]),
                  ),
                  if (_msg != null) Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_msg!, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _msgOk ? _vert : Colors.red)),
                  ),
                  const SizedBox(height: 16),
                  if (a['en_ligne'] == true) ...[
                    if (statut == 'pause')
                      _bouton("Reprendre l'abonnement maintenant", () => _appel('reprendre', ok: 'Abonnement repris.'), 'reprendre', principal: true),
                    if (statut == 'grace' || statut == 'suspendu')
                      _bouton('Mettre à jour ma carte (site)', () => _site('/mon-abonnement'), 'carte', principal: true),
                    _bouton('Changer de formule (site)', () => _site(_pageFormule), 'formule'),
                    if (mensuel && statut == 'actif' && !resilie) _bouton('Mettre en pause (1 à 3 mois)', _pause, 'pause'),
                    _bouton('Carte et factures (site)', () => _site('/mon-abonnement'), 'portail'),
                    if (resilie)
                      _bouton('Annuler la résiliation', () => _appel('annuler_resiliation', ok: 'Résiliation annulée : votre abonnement continue.'), 'annuler_resiliation')
                    else if (statut != 'pause')
                      _bouton('Résilier', _resilier, 'resilier', danger: true),
                    Text(mensuel ? 'Abonnement mensuel : reçu par e-mail à chaque prélèvement.'
                        : 'Abonnement annuel : rappel par e-mail et notification 30 jours et 7 jours avant le renouvellement. Pas de pause en cours d\'année.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ] else
                    Text("Cet abonnement n'est pas prélevé automatiquement : il se renouvelle depuis la page de votre formule.",
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
                ],
              ]),
            ),
    );
  }
}
