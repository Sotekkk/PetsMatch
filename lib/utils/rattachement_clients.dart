// Fiches créées par un professionnel pour un client sans appli (clinique,
// toiletteur, maréchal-ferrant, ostéopathe, éducateur) : à la connexion du
// propriétaire (même adresse e-mail), proposition de les rattacher à son
// compte. Route du site /api/clients/rattachement. Miroir site :
// website/src/components/RattachementClients.tsx.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/site_api.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);

bool _dejaVerifie = false;

Future<List<Map<String, dynamic>>> _propositions() async {
  final r = await http.get(Uri.parse('$kSiteBaseUrl/api/clients/rattachement'), headers: await siteApiHeaders());
  if (r.statusCode != 200) return const [];
  try {
    return ((jsonDecode(r.body) as Map)['propositions'] as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return const [];
  }
}

Future<bool> _repondre(String clientId, bool accepter) async {
  final r = await http.post(Uri.parse('$kSiteBaseUrl/api/clients/rattachement'), headers: await siteApiHeaders(),
      body: jsonEncode({'clientId': clientId, 'accepter': accepter,
        if (User_Info.activeProfileId.isNotEmpty) 'profileId': User_Info.activeProfileId}));
  return r.statusCode == 200;
}

/// Vérifie une fois par session ; s'il y a des fiches à récupérer, ouvre la
/// fenêtre. [onRattache] : recharger la liste des animaux.
Future<void> proposerRattachementClients(BuildContext context, {VoidCallback? onRattache}) async {
  if (_dejaVerifie) return;
  _dejaVerifie = true;
  final props = await _propositions();
  if (props.isEmpty || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _Rattachement(props: props, onRattache: onRattache),
  );
}

class _Rattachement extends StatefulWidget {
  final List<Map<String, dynamic>> props;
  final VoidCallback? onRattache;
  const _Rattachement({required this.props, this.onRattache});

  @override
  State<_Rattachement> createState() => _RattachementState();
}

class _RattachementState extends State<_Rattachement> {
  late final List<Map<String, dynamic>> _restantes = [...widget.props];
  String? _enCours;

  Future<void> _traiter(Map<String, dynamic> p, bool accepter) async {
    setState(() => _enCours = p['clientId']?.toString());
    final ok = await _repondre(p['clientId'].toString(), accepter);
    if (!mounted) return;
    setState(() {
      _enCours = null;
      if (ok) _restantes.remove(p);
    });
    if (ok && accepter) widget.onRattache?.call();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action impossible, réessayez plus tard.')));
    }
    if (_restantes.isEmpty && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Des fiches vous attendent', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: _ink)),
        const SizedBox(height: 4),
        Text('Ces professionnels ont créé une fiche pour votre animal avec votre adresse e-mail. Récupérez-la dans votre compte : '
            'carnet, rendez-vous et documents au même endroit. Le professionnel garde son accès.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
        const SizedBox(height: 12),
        for (final p in _restantes)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE6E8E6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((p['pro'] as Map?)?['nom']?.toString() ?? 'Un professionnel',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
              Text(((p['animaux'] as List?) ?? []).map((a) => (a as Map)['nom']?.toString() ?? '').where((x) => x.isNotEmpty).join(', '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton(
                  onPressed: _enCours != null ? null : () => _traiter(p, true),
                  style: FilledButton.styleFrom(backgroundColor: _teal),
                  child: const Text('Récupérer la fiche', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _enCours != null ? null : () => _traiter(p, false),
                  child: Text("Ce n'est pas mon animal", style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade700)),
                ),
              ]),
            ]),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Plus tard', style: TextStyle(fontFamily: 'Galey'))),
      ]),
    ));
  }
}
