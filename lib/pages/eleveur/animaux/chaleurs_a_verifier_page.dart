// Chaleurs à vérifier : les femelles du rappel groupé « Chaleurs à vérifier :
// N femelles », chacune avec sa photo, sa race et son échéance ; un appui ouvre
// sa fiche sur l'onglet Repro (suivi des chaleurs). Ouverte depuis la
// notification (push ou cloche). Sans liste fournie : celle du dernier rappel
// groupé de ce profil. Miroir site : NotifGroupeDialog (Header.tsx).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart' show AnimalFichePage;

const _teal = Color(0xFF0C5C6C);

class ChaleursAVerifierPage extends StatefulWidget {
  /// [{animalId, nom, detail}] — sinon, dernier rappel groupé du profil actif.
  final List<Map<String, dynamic>>? items;
  const ChaleursAVerifierPage({super.key, this.items});
  @override
  State<ChaleursAVerifierPage> createState() => _ChaleursAVerifierPageState();
}

class _ChaleursAVerifierPageState extends State<ChaleursAVerifierPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>>? _femelles;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      var items = widget.items;
      if (items == null) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        var q = _supa.from('notifications').select('data').eq('uid', uid ?? '').eq('type', 'chaleurs_groupe');
        if (User_Info.activeProfileId.isNotEmpty) q = q.eq('profile_id', User_Info.activeProfileId);
        final n = await q.order('created_at', ascending: false).limit(1).maybeSingle();
        final sections = ((n?['data'] as Map?)?['sections'] as List?) ?? const [];
        items = [for (final s in sections) for (final i in ((s as Map)['items'] as List?) ?? const []) Map<String, dynamic>.from(i as Map)];
      }
      final ids = [for (final i in items) if (i['animalId'] != null) i['animalId'].toString()];
      final anims = ids.isEmpty ? const [] : await _supa.from('animaux').select('id, nom, race, photo_url, uid_eleveur').inFilter('id', ids);
      final parId = {for (final a in anims) a['id'].toString(): a};
      if (!mounted) return;
      setState(() => _femelles = [
            for (final i in items!)
              {...i, ...?parId[i['animalId']?.toString()]?.cast<String, dynamic>()},
          ]);
    } catch (_) {
      if (mounted) setState(() => _femelles = []);
    }
  }

  Future<void> _ouvrir(Map<String, dynamic> f) async {
    final owner = f['uid_eleveur']?.toString();
    final moi = FirebaseAuth.instance.currentUser?.uid;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalFichePage(
      animalId: f['animalId'].toString(), readOnly: true, showReproTab: true, initialTabIndex: 2,
      eleveurUidOverride: owner != null && moi != null && owner != moi ? owner : null,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final l = _femelles;
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white,
        title: const Text('Chaleurs à vérifier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: l == null
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : l.isEmpty
              ? Center(child: Text('Aucune femelle à vérifier.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: l.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final f = l[i];
                    final photo = f['photo_url']?.toString() ?? '';
                    return Material(
                      color: Colors.white, borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: CircleAvatar(
                          radius: 24, backgroundColor: _teal.withValues(alpha: 0.1),
                          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                          child: photo.isEmpty ? const Icon(Icons.pets, color: _teal) : null,
                        ),
                        title: Text(f['nom']?.toString() ?? 'Femelle',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          if ((f['race']?.toString() ?? '').isNotEmpty) f['race'].toString(),
                          if ((f['detail']?.toString() ?? '').isNotEmpty) 'Chaleurs : ${f['detail']}',
                        ].join(' · '), style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                        trailing: const Icon(Icons.chevron_right, color: _teal),
                        onTap: f['animalId'] == null ? null : () => _ouvrir(f),
                      ),
                    );
                  },
                ),
    );
  }
}
