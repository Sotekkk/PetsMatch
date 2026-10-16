// Demandes de récupération reçues par l'élevage : un acquéreur (particulier
// sans compte lors de la cession) demande à rattacher la fiche à son
// nouveau compte. L'éleveur accepte (transfert de propriété, historique
// conservé) ou refuse. Miroir site : /mes-animaux/recuperations.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/recuperation_animal.dart' show appelRecuperation;

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);

class RecuperationsPage extends StatefulWidget {
  const RecuperationsPage({super.key});

  @override
  State<RecuperationsPage> createState() => _RecuperationsPageState();
}

class _RecuperationsPageState extends State<RecuperationsPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>>? _demandes;
  String? _encours;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    var l = <Map<String, dynamic>>[];
    try {
      l = List<Map<String, dynamic>>.from(await _supa.from('animal_recuperations').select()
          .eq('eleveur_uid', uid).eq('statut', 'en_attente').order('created_at', ascending: false));
      if (l.isNotEmpty) {
        final animaux = List<Map<String, dynamic>>.from(await _supa.from('animaux')
            .select('id, nom, photo_url, destinataire_nom, date_sortie').inFilter('id', l.map((d) => d['animal_id']).toList()));
        final profils = List<Map<String, dynamic>>.from(await _supa.from('user_profiles_complet')
            .select('uid, firstname, lastname, nom, is_main').inFilter('uid', l.map((d) => d['demandeur_uid']).toList()));
        for (final d in l) {
          d['_animal'] = animaux.where((a) => a['id'].toString() == d['animal_id'].toString()).firstOrNull;
          final ps = profils.where((p) => p['uid'] == d['demandeur_uid']).toList();
          final p = ps.where((x) => x['is_main'] == true).firstOrNull ?? ps.firstOrNull;
          final n = p == null ? '' : '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          d['_demandeur'] = n.isNotEmpty ? n : (p?['nom']?.toString() ?? '');
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _demandes = l);
  }

  Future<void> _decider(Map<String, dynamic> d, bool accepter) async {
    setState(() => _encours = d['id'].toString());
    try {
      await appelRecuperation({'action': 'decider', 'demandeId': d['id'], 'accepter': accepter});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(accepter
            ? '${(d['_animal'] as Map?)?['nom'] ?? "L'animal"} est rattaché au compte de ${(d['_demandeur'] as String?)?.isNotEmpty == true ? d['_demandeur'] : 'son propriétaire'}.'
            : 'Demande refusée.')));
      }
      await _charger();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
    if (mounted) setState(() => _encours = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
          title: const Text('Demandes de récupération', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      body: _demandes == null
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _charger, color: _teal,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                Text("Des acquéreurs ont créé leur compte et demandent à récupérer la fiche de leur animal. Vérifiez qu'il s'agit bien "
                    "de la personne à qui vous l'avez cédé avant d'accepter : la fiche lui sera transférée, votre historique est conservé.",
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                if (_demandes!.isEmpty)
                  Padding(padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text('Aucune demande en attente.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)))),
                for (final d in _demandes!)
                  Builder(builder: (_) {
                    final a = (d['_animal'] as Map?) ?? {};
                    final sortie = DateTime.tryParse(a['date_sortie']?.toString() ?? '');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE6E8E6))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          if ((a['photo_url']?.toString() ?? '').isNotEmpty)
                            Padding(padding: const EdgeInsets.only(right: 10),
                                child: ClipRRect(borderRadius: BorderRadius.circular(10),
                                    child: Image.network(a['photo_url'].toString(), width: 48, height: 48, fit: BoxFit.cover))),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${(d['_demandeur'] as String?)?.isNotEmpty == true ? d['_demandeur'] : 'Un utilisateur'} demande ${a['nom'] ?? 'un animal'}',
                                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                            Text([
                              (a['destinataire_nom']?.toString() ?? '').isNotEmpty ? 'Acquéreur enregistré : ${a['destinataire_nom']}' : 'Aucun acquéreur enregistré',
                              if (sortie != null) 'cédé le ${DateFormat('dd/MM/yyyy').format(sortie)}',
                            ].join(' · '), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                          ])),
                        ]),
                        if ((d['message']?.toString() ?? '').isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 8),
                              child: Text('« ${d['message']} »', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink))),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: OutlinedButton(onPressed: _encours == d['id'].toString() ? null : () => _decider(d, false),
                              child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey')))),
                          const SizedBox(width: 8),
                          Expanded(child: FilledButton(onPressed: _encours == d['id'].toString() ? null : () => _decider(d, true),
                              style: FilledButton.styleFrom(backgroundColor: _teal),
                              child: const Text('Accepter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)))),
                        ]),
                      ]),
                    );
                  }),
              ]),
            ),
    );
  }
}
