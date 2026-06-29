import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'groupe_detail_page.dart';

const _tealC = Color(0xFF00ACC1);

const _kGroupeTypes = ['race', 'region', 'loisir', 'autre'];
const _kGroupeTypesLabels = {
  'race': 'Race',
  'region': 'Région',
  'loisir': 'Loisir',
  'autre': 'Autre',
};

class GroupesPage extends StatefulWidget {
  const GroupesPage({super.key});

  @override
  State<GroupesPage> createState() => _GroupesPageState();
}

class _GroupesPageState extends State<GroupesPage>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _groupes = [];
  Set<String> _mesGroupes = {};
  Map<String, int> _friendCountPerGroupe = {};
  bool _loading = true;
  String? _profileId;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final groupesData = await _supa
          .from('groupes')
          .select()
          .order('created_at', ascending: false);

      Set<String> mes = {};
      List<String> friendUids = [];
      Map<String, int> friendCounts = {};

      if (_uid.isNotEmpty) {
        // Résolution profile_id (une seule fois)
        if (_profileId == null) {
          final profRow = await _supa.from('user_profiles')
              .select('id').eq('uid', _uid).eq('is_main', true).maybeSingle();
          _profileId = profRow?['id'] as String?;
        }

        // Mes appartenances
        final memData = _profileId != null
            ? await _supa.from('groupes_membres').select('groupe_id').eq('profile_id', _profileId!)
            : await _supa.from('groupes_membres').select('groupe_id').eq('user_uid', _uid);
        mes = Set<String>.from(
            (memData as List).map((e) => e['groupe_id'].toString()));

        // Mes amis
        final friendsData = await _supa
            .from('petfriends')
            .select('uid_demandeur, uid_recepteur')
            .or('uid_demandeur.eq.$_uid,uid_recepteur.eq.$_uid')
            .eq('statut', 'accepte');
        for (final f in (friendsData as List)) {
          final other = f['uid_demandeur'] == _uid ? f['uid_recepteur'] : f['uid_demandeur'];
          friendUids.add(other.toString());
        }

        // Combien d'amis dans chaque groupe
        if (friendUids.isNotEmpty) {
          final allMembers = await _supa
              .from('groupes_membres')
              .select('groupe_id, user_uid')
              .inFilter('user_uid', friendUids)
              .eq('statut', 'active');
          for (final m in (allMembers as List)) {
            final gid = m['groupe_id'].toString();
            friendCounts[gid] = (friendCounts[gid] ?? 0) + 1;
          }
        }
      }

      if (mounted) {
        setState(() {
          _groupes = List<Map<String, dynamic>>.from(groupesData);
          _mesGroupes = mes;
          _friendCountPerGroupe = friendCounts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleMembership(String groupeId) async {
    if (_uid.isEmpty) return;
    final estMembre = _mesGroupes.contains(groupeId);
    final groupe = _groupes.firstWhere((g) => g['id'].toString() == groupeId, orElse: () => {});
    final isPrive = groupe['prive'] == true;
    setState(() {
      if (estMembre) {
        _mesGroupes.remove(groupeId);
      } else if (!isPrive) {
        _mesGroupes.add(groupeId);
      }
    });
    try {
      if (estMembre) {
        await _supa
            .from('groupes_membres')
            .delete()
            .eq('groupe_id', groupeId)
            .eq('user_uid', _uid);
      } else {
        await _supa.from('groupes_membres').insert({
          'groupe_id': groupeId,
          'user_uid': _uid,
          if (_profileId != null) 'profile_id': _profileId,
          'role': 'membre',
          'statut': isPrive ? 'pending' : 'active',
          'rejoint_at': DateTime.now().toIso8601String(),
        });
        if (isPrive && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Demande envoyée — en attente d\'approbation')),
          );
        }
      }
    } catch (_) {
      setState(() {
        if (estMembre) {
          _mesGroupes.add(groupeId);
        } else {
          _mesGroupes.remove(groupeId);
        }
      });
    }
  }

  Future<void> _openCreation() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateGroupeSheet(),
    );
    if (created == true) _load();
  }

  List<Map<String, dynamic>> get _tousGroupes => _groupes;
  List<Map<String, dynamic>> get _mesGroupesList =>
      _groupes.where((g) => _mesGroupes.contains(g['id'].toString())).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Groupes',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'Tous'), Tab(text: 'Mes groupes')],
        ),
      ),
      floatingActionButton: _uid.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: _tealC,
              onPressed: _openCreation,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _tealC))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(_tousGroupes),
                _buildList(_mesGroupesList,
                    emptyMsg: 'Vous n\'avez rejoint aucun groupe'),
              ],
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items, {String? emptyMsg}) {
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.group_outlined, size: 72, color: Color(0xFFCCCCCC)),
          const SizedBox(height: 16),
          Text(
            emptyMsg ?? 'Aucun groupe pour l\'instant',
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFFAAAAAA)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text('Créez le premier !',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _tealC,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final g = items[i];
          final id = g['id'].toString();
          return _GroupeCard(
            groupe: g,
            estMembre: _mesGroupes.contains(id),
            friendCount: _friendCountPerGroupe[id] ?? 0,
            onToggle: _uid.isNotEmpty ? () => _toggleMembership(id) : null,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GroupeDetailPage(groupe: g)),
              );
              _load();
            },
          );
        },
      ),
    );
  }
}

// ─── Card groupe ──────────────────────────────────────────────────────────────

class _GroupeCard extends StatelessWidget {
  final Map<String, dynamic> groupe;
  final bool estMembre;
  final int friendCount;
  final VoidCallback? onToggle;
  final VoidCallback? onTap;

  const _GroupeCard({
    required this.groupe,
    required this.estMembre,
    this.friendCount = 0,
    this.onToggle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nom = groupe['nom']?.toString() ?? '';
    final desc = groupe['description']?.toString() ?? '';
    final type = groupe['type']?.toString() ?? 'autre';
    final prive = groupe['prive'] == true;
    final typeLabel = _kGroupeTypesLabels[type] ?? type;

    return GestureDetector(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                Text(nom,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1E2025))),
                if (prive) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                ],
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: const Color(0xFFE0F7FA),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(typeLabel,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 11,
                      color: _tealC,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc,
                style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (friendCount > 0) ...[
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.people_outline, size: 14, color: _tealC),
              const SizedBox(width: 4),
              Text(
                friendCount == 1 ? '1 ami dans ce groupe' : '$friendCount amis dans ce groupe',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _tealC, fontWeight: FontWeight.w600),
              ),
            ]),
          ],
          if (onToggle != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: estMembre ? _tealC : Colors.transparent,
                    border: Border.all(color: _tealC),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    estMembre ? 'Membre ✓' : 'Rejoindre',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: estMembre ? Colors.white : _tealC),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    ),
    );
  }
}

// ─── Sheet création ───────────────────────────────────────────────────────────

class _CreateGroupeSheet extends StatefulWidget {
  const _CreateGroupeSheet();

  @override
  State<_CreateGroupeSheet> createState() => _CreateGroupeSheetState();
}

class _CreateGroupeSheetState extends State<_CreateGroupeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _nom = '';
  String _description = '';
  String _type = 'autre';
  bool _prive = false;
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      final profRow = await _supa.from('user_profiles')
          .select('id').eq('uid', _uid).eq('is_main', true).maybeSingle();
      final profileId = profRow?['id'] as String?;

      final inserted = await _supa.from('groupes').insert({
        'createur_uid': _uid,
        if (profileId != null) 'createur_profile_id': profileId,
        'nom': _nom,
        'description': _description,
        'type': _type,
        'prive': _prive,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      // Créateur devient admin du groupe
      await _supa.from('groupes_membres').insert({
        'groupe_id': inserted['id'],
        'user_uid': _uid,
        if (profileId != null) 'profile_id': profileId,
        'role': 'admin',
        'rejoint_at': DateTime.now().toIso8601String(),
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(
                      child: Text('Créer un groupe',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 18))),
                  IconButton(
                      icon: const Icon(Icons.close, size: 22, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                ]),
                const SizedBox(height: 20),

                _lbl('Nom du groupe *'),
                TextFormField(
                  decoration: _dec('Ex : Bergers Australiens France'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _nom = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                _lbl('Type'),
                InputDecorator(
                  decoration: _dec(''),
                  child: DropdownButton<String>(
                    value: _type,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _kGroupeTypes
                        .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(_kGroupeTypesLabels[t] ?? t,
                                style: const TextStyle(
                                    fontFamily: 'Galey', fontSize: 14))))
                        .toList(),
                    onChanged: (v) => setState(() => _type = v ?? 'autre'),
                  ),
                ),
                const SizedBox(height: 12),

                _lbl('Description'),
                TextFormField(
                  decoration: _dec('Thème, règles, objectifs du groupe…'),
                  maxLines: 3,
                  onSaved: (v) => _description = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                Row(children: [
                  Switch(
                    value: _prive,
                    onChanged: (v) => setState(() => _prive = v),
                    activeThumbColor: _tealC,
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Groupe privé',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    Text('Visible uniquement par les membres',
                        style: TextStyle(
                            fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ]),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: _tealC,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Créer le groupe',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF6F767B))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _tealC, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      );
}
