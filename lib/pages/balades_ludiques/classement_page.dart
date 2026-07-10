import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'balades_ludiques_shared.dart';

class ClassementPage extends StatefulWidget {
  const ClassementPage({super.key});

  @override
  State<ClassementPage> createState() => _ClassementPageState();
}

class _ClassementPageState extends State<ClassementPage> with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _loading = true;
  List<Map<String, dynamic>> _explorateurs = [];
  List<Map<String, dynamic>> _createurs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final explorateurs = await _supa.from('joueurs_xp').select().order('xp_total', ascending: false).limit(50);
    final createurs = await _supa.from('balades_ludiques').select('createur_uid, nb_completions, note_moyenne')
        .eq('statut', 'publie');

    final parCreateur = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(createurs as List)) {
      final uid = row['createur_uid'] as String;
      final agg = parCreateur.putIfAbsent(uid, () => {'createur_uid': uid, 'nb_completions': 0, 'notes': <double>[]});
      agg['nb_completions'] = (agg['nb_completions'] as int) + ((row['nb_completions'] as int?) ?? 0);
      if (row['note_moyenne'] != null) (agg['notes'] as List<double>).add((row['note_moyenne'] as num).toDouble());
    }
    final createursTries = parCreateur.values.toList()
      ..sort((a, b) => (b['nb_completions'] as int).compareTo(a['nb_completions'] as int));

    if (mounted) {
      setState(() {
        _explorateurs = List<Map<String, dynamic>>.from(explorateurs as List);
        _createurs = createursTries;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: kBlTeal, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Classement', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
          tabs: const [Tab(text: 'Explorateurs'), Tab(text: 'Créateurs')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBlTeal))
          : TabBarView(controller: _tabs, children: [
              _buildListe(_explorateurs, (i, r) => _ExplorateurTile(rang: i + 1, row: r)),
              _buildListe(_createurs, (i, r) => _CreateurTile(rang: i + 1, row: r)),
            ]),
    );
  }

  Widget _buildListe(List<Map<String, dynamic>> data, Widget Function(int, Map<String, dynamic>) builder) {
    if (data.isEmpty) return const Center(child: Text('Aucun classement disponible pour le moment', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: data.length,
      itemBuilder: (_, i) => builder(i, data[i]),
    );
  }
}

class _ExplorateurTile extends StatelessWidget {
  final int rang;
  final Map<String, dynamic> row;
  const _ExplorateurTile({required this.rang, required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        _RangBadge(rang: rang),
        const SizedBox(width: 12),
        Expanded(child: Text('Explorateur ${(row['user_uid'] as String).substring(0, 6)}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13))),
        Text('${row['xp_total']} XP', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, color: kBlOrange)),
      ]),
    );
  }
}

class _CreateurTile extends StatelessWidget {
  final int rang;
  final Map<String, dynamic> row;
  const _CreateurTile({required this.rang, required this.row});

  @override
  Widget build(BuildContext context) {
    final notes = (row['notes'] as List<double>);
    final moyenne = notes.isEmpty ? null : notes.reduce((a, b) => a + b) / notes.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        _RangBadge(rang: rang),
        const SizedBox(width: 12),
        Expanded(child: Text('Créateur ${(row['createur_uid'] as String).substring(0, 6)}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13))),
        if (moyenne != null) Text('⭐ ${moyenne.toStringAsFixed(1)}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
        const SizedBox(width: 8),
        Text('${row['nb_completions']} complétions', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: kBlGreen, fontSize: 12)),
      ]),
    );
  }
}

class _RangBadge extends StatelessWidget {
  final int rang;
  const _RangBadge({required this.rang});

  @override
  Widget build(BuildContext context) {
    final medaille = switch (rang) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => null };
    return CircleAvatar(
      radius: 16,
      backgroundColor: rang <= 3 ? Colors.amber.shade50 : kBlTeal.withOpacity(0.08),
      child: medaille != null
          ? Text(medaille, style: const TextStyle(fontSize: 16))
          : Text('$rang', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: kBlTeal, fontSize: 12)),
    );
  }
}
