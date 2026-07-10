import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'balades_ludiques_shared.dart';

class ParcoursStatsPage extends StatefulWidget {
  final String baladeId;
  const ParcoursStatsPage({super.key, required this.baladeId});

  @override
  State<ParcoursStatsPage> createState() => _ParcoursStatsPageState();
}

class _ParcoursStatsPageState extends State<ParcoursStatsPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _balade;
  List<Map<String, dynamic>> _avis = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final balade = await _supa.from('balades_ludiques').select().eq('id', widget.baladeId).single();
    final avis = await _supa.from('balades_ludiques_avis').select().eq('balade_id', widget.baladeId).order('created_at', ascending: false);
    if (mounted) {
      setState(() {
        _balade = balade;
        _avis = List<Map<String, dynamic>>.from(avis as List);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kBlTeal)));
    final b = _balade!;
    final nbJoueurs = (b['nb_joueurs'] as int?) ?? 0;
    final nbCompletions = (b['nb_completions'] as int?) ?? 0;
    final tauxReussite = nbJoueurs == 0 ? 0.0 : (nbCompletions / nbJoueurs * 100);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: kBlTeal, foregroundColor: Colors.white, elevation: 0,
        title: Text(b['titre']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.5,
          children: [
            _statCard('Joueurs', '$nbJoueurs', Icons.people_outline, kBlTeal),
            _statCard('Complétions', '$nbCompletions', Icons.flag_outlined, kBlGreen),
            _statCard('Taux de réussite', '${tauxReussite.toStringAsFixed(0)}%', Icons.trending_up, kBlOrange),
            _statCard('Note moyenne', b['note_moyenne'] != null ? '⭐ ${b['note_moyenne']}' : '—', Icons.star_border, Colors.amber.shade700),
            _statCard('Avis', '${b['nb_avis'] ?? 0}', Icons.rate_review_outlined, Colors.purple),
            _statCard('Favoris', '${b['nb_favoris'] ?? 0}', Icons.favorite_border, Colors.pink),
          ],
        ),
        const SizedBox(height: 20),
        if (_avis.isNotEmpty) ...[
          const Text('Avis des joueurs', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          ..._avis.map((a) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: List.generate(5, (i) => Icon(i < (a['note'] as num).toInt() ? Icons.star : Icons.star_border, size: 14, color: Colors.amber))),
              if ((a['commentaire'] as String?)?.isNotEmpty == true)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(a['commentaire'], style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
            ]),
          )),
        ],
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          Text(value, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: color)),
          Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
        ]),
      );
}
