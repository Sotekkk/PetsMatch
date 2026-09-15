import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/animaux/morpho/morpho_constants.dart';
import 'package:PetsMatch/pages/animaux/morpho/morpho_form_page.dart';
import 'package:PetsMatch/pages/animaux/morpho/morpho_detail_page.dart';

/// « Mes suivis » — accès direct depuis le menu santé/véto à tous les
/// suivis morphologiques réalisés, tous patients confondus (l'onglet
/// "Morphologie" de la fiche animal reste le point d'entrée par patient ;
/// cette page évite d'avoir à rouvrir la fiche pour retrouver un suivi).
class SanteSuivisMorphoPage extends StatefulWidget {
  const SanteSuivisMorphoPage({super.key});

  @override
  State<SanteSuivisMorphoPage> createState() => _SanteSuivisMorphoPageState();
}

class _SanteSuivisMorphoPageState extends State<SanteSuivisMorphoPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _suivis = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final pid = User_Info.activeProfileId;
      var q = _supa.from('suivis_morpho').select().eq('uid_auteur', uid);
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final rows = await q.order('date', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);

      final animalIds = list.map((r) => r['animal_id']?.toString()).whereType<String>().toSet().toList();
      final byId = <String, Map<String, dynamic>>{};
      if (animalIds.isNotEmpty) {
        final animaux = await _supa.from('animaux').select('id, nom, espece').inFilter('id', animalIds);
        for (final a in (animaux as List)) { byId[a['id'].toString()] = a; }
      }
      for (final r in list) {
        final a = byId[r['animal_id']?.toString()];
        r['_animal_nom'] = a?['nom'] ?? r['animal_nom_libre'] ?? 'Animal';
        r['_animal_espece'] = a?['espece'] ?? r['espece_libre'] ?? '';
        r['_saisie_libre'] = r['animal_id'] == null;
      }
      if (mounted) setState(() { _suivis = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _nouveauSuivi() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pid = User_Info.activeProfileId;
    var rq = _supa.from('rdv').select('animal_id, date_heure').eq('pro_uid', uid);
    if (pid.isNotEmpty) rq = rq.eq('pro_profile_id', pid);
    final rows = await rq.inFilter('statut', ['confirme', 'termine']).not('animal_id', 'is', null).order('date_heure', ascending: false);
    final animalIds = <String>[];
    for (final r in (rows as List)) {
      final id = r['animal_id']?.toString();
      if (id != null && !animalIds.contains(id)) animalIds.add(id);
    }
    List<Map<String, dynamic>> animauxList = [];
    if (animalIds.isNotEmpty) {
      final animaux = await _supa.from('animaux').select('id, nom, espece').inFilter('id', animalIds);
      animauxList = List<Map<String, dynamic>>.from(animaux as List)
        ..sort((a, b) => animalIds.indexOf(a['id'].toString()).compareTo(animalIds.indexOf(b['id'].toString())));
    }

    if (!mounted) return;
    final choix = await showModalBottomSheet<Object>(
      context: context, backgroundColor: Colors.white, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Nouveau suivi', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE0F2F1),
                child: Icon(Icons.person_add_alt_1, color: kMorphoTeal, size: 20)),
            title: const Text('Client occasionnel (sans compte)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text('Nom de l\'animal saisi à la main', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
            onTap: () => Navigator.pop(context, 'libre'),
          ),
          if (animauxList.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text('Ou un patient existant', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: animauxList.map((a) {
                final supported = morphoSpeciesSupported(a['espece']?.toString());
                return ListTile(
                  enabled: supported,
                  leading: CircleAvatar(backgroundColor: const Color(0xFFE0F2F1),
                      child: Icon(Icons.pets, color: supported ? kMorphoTeal : Colors.grey, size: 20)),
                  title: Text(a['nom']?.toString() ?? 'Animal', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(supported ? (a['espece']?.toString() ?? '') : 'Espèce non disponible pour le suivi morphologique',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  onTap: supported ? () => Navigator.pop(context, a) : null,
                );
              }).toList()),
            ),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choix == null) return;

    if (choix == 'libre') {
      await _nouveauSuiviLibre(pid);
      return;
    }

    final a = choix as Map<String, dynamic>;
    if (!mounted) return;
    final created = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => MorphoFormPage(
        animalId: a['id'].toString(),
        espece: a['espece']?.toString() ?? 'chien',
        proProfileId: pid.isNotEmpty ? pid : null,
      ),
    ));
    if (created == true) _load();
  }

  Future<void> _nouveauSuiviLibre(String pid) async {
    String espece = 'chien';
    final result = await showModalBottomSheet<String>(
      context: context, backgroundColor: Colors.white, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Espèce de l\'animal', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final e in ['chien', 'chat', 'cheval'])
              ChoiceChip(
                label: Text(e[0].toUpperCase() + e.substring(1), style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                selected: espece == e, showCheckmark: false,
                selectedColor: kMorphoTeal.withValues(alpha: 0.2),
                onSelected: (_) => setSheetState(() => espece = e),
              ),
          ]),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, espece),
            style: ElevatedButton.styleFrom(backgroundColor: kMorphoTeal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Continuer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ]),
      )),
    );
    if (result == null || !mounted) return;
    final created = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => MorphoFormPage(
        espece: result,
        proProfileId: pid.isNotEmpty ? pid : null,
      ),
    ));
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kMorphoBg,
      appBar: AppBar(
        backgroundColor: kMorphoTeal, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Mes suivis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nouveauSuivi,
        backgroundColor: kMorphoTeal,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau suivi', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kMorphoTeal))
          : _suivis.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.accessibility_new, size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Aucun suivi pour l\'instant', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: kMorphoTeal,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: _suivis.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final s = _suivis[i];
                      final date = DateTime.tryParse(s['date']?.toString() ?? '');
                      return InkWell(
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => MorphoDetailPage(suivi: s, espece: s['_animal_espece']?.toString() ?? 'chien'),
                          ));
                          _load();
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(14),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2))],
                          ),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.accessibility_new, color: kMorphoTeal),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${s['_animal_nom'] ?? 'Animal'} — ${labelTypeSuivi(s['type_suivi']?.toString())}',
                                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: kMorphoDark)),
                                const SizedBox(height: 2),
                                if (date != null)
                                  Text(DateFormat('d MMM yyyy', 'fr_FR').format(date),
                                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                              ]),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
