import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/association/association_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';

class MesAssociationsBenevole extends StatefulWidget {
  const MesAssociationsBenevole({super.key});
  @override
  State<MesAssociationsBenevole> createState() => _MesAssociationsBenevoleState();
}

class _MesAssociationsBenevoleState extends State<MesAssociationsBenevole> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;

  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);
  static const _bg   = Color(0xFFF8F8F6);

  bool _loading = true;
  List<Map<String, dynamic>> _assos = [];
  final Map<String, bool> _showAnimaux = {}; // uid → true=animaux false=taches

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      // Chercher par employe_profile_id (plus fiable), fallback uid_employe
      final myProfileData = await _supa.from('user_profiles')
          .select('id').eq('uid', _uid).eq('is_main', true).maybeSingle();
      final myProfileId = myProfileData?['id'] as String?;

      List rows;
      if (myProfileId != null) {
        rows = await _supa.from('employes')
            .select('uid_eleveur, eleveur_profile_id')
            .eq('employe_profile_id', myProfileId).eq('type', 'benevole').eq('actif', true)
            .order('created_at');
      } else {
        rows = await _supa.from('employes')
            .select('uid_eleveur, eleveur_profile_id')
            .eq('uid_employe', _uid).eq('type', 'benevole').eq('actif', true)
            .order('created_at');
      }

      // Déduplique par uid_eleveur
      final seenUids = <String>{};
      final empRows = <Map<String, dynamic>>[];
      for (final r in rows as List) {
        final uid = r['uid_eleveur'] as String;
        if (seenUids.add(uid)) empRows.add(r as Map<String, dynamic>);
      }
      if (empRows.isEmpty) {
        if (mounted) setState(() { _assos = []; _loading = false; });
        return;
      }

      final uids = empRows.map((r) => r['uid_eleveur'] as String).toList();

      final pastStr   = DateTime.now().subtract(const Duration(days: 7)).toIso8601String().substring(0, 10);
      final futureStr = DateTime.now().add(const Duration(days: 90)).toIso8601String().substring(0, 10);

      // eleveur_profile_id dans employes EST le profile_id_proprio à utiliser directement
      final eleveurProfileIds = empRows
          .map((r) => r['eleveur_profile_id'] as String?)
          .whereType<String>().toList();
      // Inverse : profile_id → uid_eleveur
      final pidToUid = <String, String>{
        for (final r in empRows)
          if (r['eleveur_profile_id'] != null)
            r['eleveur_profile_id'] as String: r['uid_eleveur'] as String,
      };

      // Profils pour les noms/avatars : query par ID direct
      final profileByPid = <String, Map<String, dynamic>>{};
      if (eleveurProfileIds.isNotEmpty) {
        final pRows = await _supa.from('user_profiles')
            .select('id, uid, name_elevage, profile_label, nom, avatar_url, ville')
            .inFilter('id', eleveurProfileIds) as List;
        for (final p in pRows) {
          profileByPid[p['id'] as String] = p as Map<String, dynamic>;
        }
      }

      final tachesAssigneFilter = myProfileId != null ? 'assigne_profile_id' : 'assigne_a';
      final tachesAssigneValue  = myProfileId ?? _uid;
      final planAssigneFilter   = myProfileId != null ? 'assigned_profile_id' : 'assigned_to';
      final planAssigneValue    = myProfileId ?? _uid;

      final results = await Future.wait([
        _supa.from('user_profiles')
            .select('uid, firstname, lastname, name_elevage:nom, profile_picture_url:avatar_url, ville')
            .inFilter('uid', uids).eq('is_main', true),
        _supa.from('taches_elevage')
            .select('id, titre, date, statut, animal_id, uid_eleveur')
            .inFilter('uid_eleveur', uids).eq(tachesAssigneFilter, tachesAssigneValue).neq('statut', 'fait').order('date'),
        _supa.from('plan_taches')
            .select('id, label, date_prevue, statut, animal_id, uid_eleveur')
            .inFilter('uid_eleveur', uids).eq(planAssigneFilter, planAssigneValue).neq('statut', 'fait')
            .gte('date_prevue', pastStr).lte('date_prevue', futureStr).order('date_prevue'),
      ]);

      final primaryUsers = results[0] as List;
      final taches      = results[1] as List;
      final planTaches  = results[2] as List;

      // Animaux : animaux_proprietes WHERE profile_id_proprio = eleveur_profile_id
      final animalsByUid = <String, List<Map<String, dynamic>>>{};
      if (eleveurProfileIds.isNotEmpty) {
        final apRows = await _supa.from('animaux_proprietes')
            .select('animal_id, profile_id_proprio')
            .inFilter('profile_id_proprio', eleveurProfileIds)
            .isFilter('date_fin', null) as List;
        final animalIds = apRows.map((r) => r['animal_id']?.toString()).whereType<String>().toSet().toList();
        if (animalIds.isNotEmpty) {
          final animaux = await _supa.from('animaux')
              .select('id, nom, espece, race, photo_url')
              .inFilter('id', animalIds)
              .not('statut', 'in', '("sorti","decede")')
              .order('nom') as List;
          for (final a in animaux) {
            final animalId = a['id']?.toString();
            final ap = apRows.firstWhere(
              (r) => r['animal_id']?.toString() == animalId,
              orElse: () => <String, dynamic>{},
            );
            final ownerUid = ap.isNotEmpty ? pidToUid[ap['profile_id_proprio'] as String?] : null;
            if (ownerUid != null) {
              animalsByUid.putIfAbsent(ownerUid, () => []).add(a as Map<String, dynamic>);
            }
          }
        }
      }

      final result = <Map<String, dynamic>>[];
      for (final r in empRows) {
        final uid = r['uid_eleveur'] as String;
        final pid = r['eleveur_profile_id'] as String?;
        final sec = pid != null ? profileByPid[pid] : null;
        final pu = primaryUsers.firstWhere((u) => u['uid'] == uid, orElse: () => <String, dynamic>{}) as Map<String, dynamic>;

        final nom = ((sec?['profile_label'] as String? ?? '').trim().isNotEmpty
            ? sec!['profile_label'] as String
            : (sec?['nom'] as String? ?? '').trim().isNotEmpty
                ? sec!['nom'] as String
                : (sec?['name_elevage'] as String? ?? '').trim().isNotEmpty
                    ? sec!['name_elevage'] as String
                    : (pu['name_elevage'] as String? ?? '').trim().isNotEmpty
                        ? pu['name_elevage'] as String
                        : '${pu['firstname'] ?? ''} ${pu['lastname'] ?? ''}'.trim());
        final avatar = sec?['avatar_url'] as String? ?? pu['profile_picture_url'] as String?;
        final ville  = sec?['ville'] as String? ?? pu['ville'] as String?;

        final anims = animalsByUid[uid] ?? [];
        final allTaches = [
          ...taches.where((t) => t['uid_eleveur'] == uid).map((t) => {...t, 'source': 'manuel', 'date': t['date']}),
          ...planTaches.where((t) => t['uid_eleveur'] == uid).map((t) => {...t, 'source': 'protocole', 'titre': t['label'] ?? 'Tâche', 'date': t['date_prevue']}),
        ]..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

        result.add({
          'uid': uid, 'nom': nom.isEmpty ? 'Association' : nom,
          'avatar': avatar, 'ville': ville,
          'animaux': anims, 'taches': allTaches,
        });
      }
      if (mounted) setState(() { _assos = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _marquerFait(Map<String, dynamic> t) async {
    if (t['source'] == 'manuel') {
      await _supa.from('taches_elevage').update({'statut': 'fait'}).eq('id', t['id']);
    } else {
      await _supa.from('plan_taches').update({'statut': 'fait'}).eq('id', t['id']);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1F2A2E), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mes Associations',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF1F2A2E))),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: _assos.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('🏠', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 16),
                      Text('Aucune association',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
                      const SizedBox(height: 8),
                      Text('Vous n\'êtes bénévole dans aucune association active.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _assos.length,
                      itemBuilder: (_, i) {
                        final a = _assos[i];
                        final uid    = a['uid'] as String;
                        final nom    = a['nom'] as String;
                        final avatar = a['avatar'] as String?;
                        final ville  = a['ville'] as String?;
                        final animaux = (a['animaux'] as List).cast<Map<String, dynamic>>();
                        final taches  = (a['taches']  as List).cast<Map<String, dynamic>>();
                        final showAnim = _showAnimaux[uid] ?? true;
                        return _AssoCard(
                          uid: uid, nom: nom, avatar: avatar, ville: ville,
                          teal: _teal, dark: _dark,
                          showAnimaux: showAnim,
                          animaux: animaux, taches: taches,
                          onTabChange: (val) => setState(() => _showAnimaux[uid] = val),
                          onVoirProfil: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AssociationDetailPage(
                              uid: uid, name: nom, avatar: avatar ?? '', ville: ville ?? '',
                            ),
                          )),
                          onMarquerFait: _marquerFait,
                          onAnimalTap: (animal) => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AnimalFichePage(
                              animalId: animal['id'] as String?,
                              readOnly: true,
                              eleveurUidOverride: uid,
                              isAssociation: true,
                            ),
                          )),
                        );
                      },
                    ),
            ),
    );
  }
}

class _AssoCard extends StatelessWidget {
  final String uid, nom;
  final String? avatar, ville;
  final Color teal, dark;
  final bool showAnimaux;
  final List<Map<String, dynamic>> animaux, taches;
  final ValueChanged<bool> onTabChange;
  final VoidCallback onVoirProfil;
  final Future<void> Function(Map<String, dynamic>) onMarquerFait;
  final void Function(Map<String, dynamic>) onAnimalTap;

  const _AssoCard({
    required this.uid, required this.nom, required this.avatar, required this.ville,
    required this.teal, required this.dark, required this.showAnimaux,
    required this.animaux, required this.taches,
    required this.onTabChange, required this.onVoirProfil, required this.onMarquerFait,
    required this.onAnimalTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(children: [
            CircleAvatar(
              radius: 22, backgroundColor: teal.withOpacity(0.12),
              backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar!) : null,
              child: avatar == null ? Icon(Icons.volunteer_activism, color: teal, size: 20) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15, color: dark)),
              if (ville != null && ville!.isNotEmpty)
                Text('📍 $ville', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ])),
            GestureDetector(
              onTap: onVoirProfil,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: teal.withOpacity(0.6)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Voir', style: TextStyle(color: teal, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
        // Tabs
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
          child: Row(children: [
            _tab('🐾 Animaux (${animaux.length})', showAnimaux, () => onTabChange(true)),
            _tab('✅ Tâches (${taches.length})', !showAnimaux, () => onTabChange(false)),
          ]),
        ),
        if (showAnimaux) _buildAnimaux() else _buildTaches(),
      ]),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: active ? Border(bottom: BorderSide(color: teal, width: 2)) : null,
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                color: active ? teal : Colors.grey.shade400)),
      ),
    ),
  );

  Widget _buildAnimaux() {
    if (animaux.isEmpty) {
      return Padding(padding: const EdgeInsets.all(16),
          child: Center(child: Text('Aucun animal',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400))));
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.85),
        itemCount: animaux.length,
        itemBuilder: (_, i) {
          final a = animaux[i];
          final photoUrl = a['photo_url'] as String?;
          return GestureDetector(
            onTap: () => onAnimalTap(a),
            child: Column(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: photoUrl != null
                    ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover, width: double.infinity)
                    : Container(color: Colors.grey.shade100, child: const Icon(Icons.pets, color: Colors.grey)),
              )),
              const SizedBox(height: 4),
              Text(a['nom'] ?? '—', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(a['race'] ?? a['espece'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildTaches() {
    if (taches.isEmpty) {
      return Padding(padding: const EdgeInsets.all(16),
          child: Center(child: Text('Aucune tâche assignée',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400))));
    }
    return ListView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(10),
      itemCount: taches.length,
      itemBuilder: (_, i) {
        final t = taches[i];
        final date = t['date'] as String? ?? '';
        final dt = date.isNotEmpty ? DateTime.tryParse(date) : null;
        final dateStr = dt != null ? '${dt.day}/${dt.month}/${dt.year}' : date;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['titre'] as String? ?? 'Tâche',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: dark)),
              if (dateStr.isNotEmpty)
                Text('📅 $dateStr', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              if (t['source'] == 'protocole')
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: teal.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                  child: Text('protocole', style: TextStyle(fontSize: 10, color: teal)),
                ),
            ])),
            GestureDetector(
              onTap: () => onMarquerFait(t),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
                child: Icon(Icons.check, size: 16, color: Colors.grey.shade400),
              ),
            ),
          ]),
        );
      },
    );
  }
}
