import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'balades_ludiques_shared.dart';
import 'balade_ludique_detail_page.dart';
import 'creation/creation_flow_page.dart';

class MesParcoursPage extends StatefulWidget {
  const MesParcoursPage({super.key});

  @override
  State<MesParcoursPage> createState() => _MesParcoursPageState();
}

class _MesParcoursPageState extends State<MesParcoursPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _parcours = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    setState(() => _loading = true);
    final data = await _supa.from('balades_ludiques').select()
        .eq('createur_uid', uid).neq('statut', 'supprime').order('created_at', ascending: false);
    if (mounted) setState(() { _parcours = List<Map<String, dynamic>>.from(data as List); _loading = false; });
  }

  static const _statutLabels = {
    'brouillon': ('Brouillon', Colors.grey),
    'publie': ('Publié', kBlGreen),
    'desactive': ('Désactivé', Colors.orange),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: kBlTeal, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Mes parcours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kBlOrange,
        icon: const Icon(Icons.add),
        label: const Text('Créer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreationFlowPage()));
          _load();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBlTeal))
          : _parcours.isEmpty
              ? const Center(child: Text('Vous n\'avez pas encore créé de parcours', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _parcours.length,
                  itemBuilder: (_, i) {
                    final p = _parcours[i];
                    final statutInfo = _statutLabels[p['statut']] ?? ('?', Colors.grey);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(8),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(width: 56, height: 56,
                            child: (p['cover_url'] as String?)?.isNotEmpty == true
                                ? CachedNetworkImage(imageUrl: p['cover_url'], fit: BoxFit.cover)
                                : Container(color: const Color(0xFFEEF5EA), child: const Icon(Icons.map_outlined, color: kBlGreen)),
                          ),
                        ),
                        title: Text(p['titre']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                        subtitle: Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: statutInfo.$2.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                            child: Text(statutInfo.$1, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: statutInfo.$2)),
                          ),
                          const SizedBox(width: 8),
                          Text('${p['nb_joueurs'] ?? 0} joueur(s)', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                        ]),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => BaladeLudiqueDetailPage(baladeId: p['id'] as String)));
                          _load();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
