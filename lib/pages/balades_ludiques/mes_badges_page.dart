import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'balades_ludiques_shared.dart';

class MesBadgesPage extends StatefulWidget {
  const MesBadgesPage({super.key});

  @override
  State<MesBadgesPage> createState() => _MesBadgesPageState();
}

class _MesBadgesPageState extends State<MesBadgesPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _xp;
  List<Map<String, dynamic>> _tousBadges = [];
  Set<String> _obtenusIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final xp = await _supa.from('joueurs_xp').select().eq('user_uid', uid).maybeSingle();
    final tous = await _supa.from('badges').select().eq('actif', true).order('rarete');
    final obtenus = await _supa.from('badges_obtenus').select('badge_id').eq('user_uid', uid);
    if (mounted) {
      setState(() {
        _xp = xp;
        _tousBadges = List<Map<String, dynamic>>.from(tous as List);
        _obtenusIds = List<Map<String, dynamic>>.from(obtenus as List).map((r) => r['badge_id'] as String).toSet();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: kBlTeal, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Mes badges', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBlTeal))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [kBlTeal, Color(0xFF1E7A8C)]), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Icon(Icons.bolt, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_xp?['xp_total'] ?? 0} XP', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: Colors.white)),
                    Text('${_xp?['nb_parcours_completes'] ?? 0} parcours terminés', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white70)),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.85),
                itemCount: _tousBadges.length,
                itemBuilder: (_, i) {
                  final b = _tousBadges[i];
                  final obtenu = _obtenusIds.contains(b['id']);
                  return Opacity(
                    opacity: obtenu ? 1 : 0.35,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(b['icone_url'] ?? '🏅', style: const TextStyle(fontSize: 30)),
                        const SizedBox(height: 6),
                        Text(b['nom'] ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  );
                },
              ),
            ]),
    );
  }
}
