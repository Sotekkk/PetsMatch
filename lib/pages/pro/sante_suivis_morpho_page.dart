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

  /// Profil pro actif — un même uid peut porter plusieurs profils pro (ex :
  /// ostéo + éducateur) ; sans ce repli sur le premier profil non-particulier,
  /// `User_Info.activeProfileId` vide fait échouer la résolution des vrais
  /// patients (animal_access est scopé par profil). Même pattern que
  /// pro_clients_page.dart.
  String _resolveProProfileId() {
    if (User_Info.activeProfileId.isNotEmpty) return User_Info.activeProfileId;
    if (User_Info.availableProfiles.isEmpty) return '';
    final proProfile = User_Info.availableProfiles.firstWhere(
      (p) => p['profile_type'] != 'particulier',
      orElse: () => User_Info.availableProfiles.first,
    );
    return proProfile['id']?.toString() ?? '';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final pid = _resolveProProfileId();
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

  /// Tous les vrais patients du pro : accès accordés (animal_access) UNION
  /// animaux d'un RDV confirmé/terminé — même requête que pro_clients_page.dart
  /// (« Mes patients »), pour que « Mes suivis » propose la liste complète et
  /// pas seulement les patients déjà venus en RDV.
  Future<List<Map<String, dynamic>>> _loadVraisPatients(String uid, String pid) async {
    final grants = await _supa.from('animal_access').select('animal_id, granted_by_profile_id')
        .eq('pro_profile_id', pid).inFilter('statut', ['active', 'write_requested', 'active_write']);
    final rdvAnimals = await _supa.from('rdv').select('animal_id, client_uid')
        .eq('pro_uid', uid).eq('pro_profile_id', pid)
        .inFilter('statut', ['confirme', 'termine']).not('animal_id', 'is', null);

    final seen = <String, Map<String, dynamic>>{};
    for (final g in (grants as List)) {
      final id = g['animal_id']?.toString();
      if (id != null) seen[id] = {'granted_by_profile_id': g['granted_by_profile_id']};
    }
    for (final r in (rdvAnimals as List)) {
      final id = r['animal_id']?.toString();
      if (id != null && !seen.containsKey(id)) seen[id] = {'owner_uid': r['client_uid']};
    }
    if (seen.isEmpty) return [];

    final animaux = await _supa.from('animaux').select('id, nom, espece')
        .inFilter('id', seen.keys.toList());

    final ownerProfileIds = seen.values.map((e) => e['granted_by_profile_id'] as String?)
        .whereType<String>().toSet().toList();
    final ownerNames = <String, String>{};
    if (ownerProfileIds.isNotEmpty) {
      final profiles = await _supa.from('user_profiles').select('id, firstname, lastname, nom')
          .inFilter('id', ownerProfileIds);
      for (final u in (profiles as List)) {
        final name = (u['nom'] as String?)?.isNotEmpty == true
            ? u['nom'] as String
            : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
        ownerNames[u['id'] as String] = name.isNotEmpty ? name : 'Propriétaire';
      }
    }

    return (animaux as List).map<Map<String, dynamic>>((a) {
      final extra = seen[a['id']?.toString()] ?? {};
      final ownerPid = extra['granted_by_profile_id'] as String?;
      return {...a, '_owner_name': ownerNames[ownerPid] ?? ''};
    }).toList()
      ..sort((a, b) => (a['nom']?.toString() ?? '').compareTo(b['nom']?.toString() ?? ''));
  }

  Future<void> _nouveauSuivi() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pid = _resolveProProfileId();
    final animauxList = pid.isNotEmpty ? await _loadVraisPatients(uid, pid) : <Map<String, dynamic>>[];

    if (!mounted) return;
    final searchCtrl = TextEditingController();
    final choix = await showModalBottomSheet<Object>(
      context: context, backgroundColor: Colors.white, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (context, setSheetState) {
        final query = searchCtrl.text.trim().toLowerCase();
        final filtered = query.isEmpty
            ? animauxList
            : animauxList.where((a) =>
                (a['nom']?.toString() ?? '').toLowerCase().contains(query) ||
                (a['_owner_name']?.toString() ?? '').toLowerCase().contains(query)).toList();
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Align(alignment: Alignment.centerLeft, child: Text('Nouveau suivi', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
              ),
              const SizedBox(height: 12),
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
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un patient ou un propriétaire…',
                      hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true, filled: true, fillColor: const Color(0xFFF5F5F5),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Flexible(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Aucun patient trouvé', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
                        )
                      : ListView(shrinkWrap: true, children: filtered.map((a) {
                          final supported = morphoSpeciesSupported(a['espece']?.toString());
                          final owner = a['_owner_name']?.toString() ?? '';
                          return ListTile(
                            enabled: supported,
                            leading: CircleAvatar(backgroundColor: const Color(0xFFE0F2F1),
                                child: Icon(Icons.pets, color: supported ? kMorphoTeal : Colors.grey, size: 20)),
                            title: Text(a['nom']?.toString() ?? 'Animal', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(
                                !supported
                                    ? 'Espèce non disponible pour le suivi morphologique'
                                    : owner.isNotEmpty ? '${a['espece'] ?? ''} · $owner' : (a['espece']?.toString() ?? ''),
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
      }),
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
                            builder: (_) => MorphoDetailPage(suivi: s, espece: s['_animal_espece']?.toString() ?? 'chien', readOnly: false),
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
