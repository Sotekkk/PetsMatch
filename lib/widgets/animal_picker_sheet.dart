import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Shared animal picker bottom sheet ────────────────────────────────────────
// multiSelect=true  → returns List<Map> (checkboxes + Confirmer button)
// multiSelect=false → returns Map immediately on tap (single select)
//
// Pass [uid] to load animals, or [preloaded] to skip the DB fetch.

class AnimalPickerSheet extends StatefulWidget {
  final String? uid;
  final String? profileId;
  final List<Map<String, dynamic>>? preloaded;
  final bool multiSelect;
  final List<Map<String, dynamic>> initialSelected;
  final Color accentColor;
  final bool showPortees;

  const AnimalPickerSheet({
    super.key,
    this.uid,
    this.profileId,
    this.preloaded,
    this.multiSelect = false,
    this.initialSelected = const [],
    this.accentColor = const Color(0xFF0C5C6C),
    this.showPortees = true,
  }) : assert(uid != null || preloaded != null, 'Provide uid or preloaded');

  /// Single-select convenience: opens sheet and returns the chosen animal or null.
  static Future<Map<String, dynamic>?> pickOne(
    BuildContext context, {
    String? uid,
    String? profileId,
    List<Map<String, dynamic>>? preloaded,
    Map<String, dynamic>? current,
    Color accentColor = const Color(0xFF0C5C6C),
    bool showPortees = true,
  }) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnimalPickerSheet(
        uid: uid,
        profileId: profileId,
        preloaded: preloaded,
        multiSelect: false,
        initialSelected: current != null ? [current] : [],
        accentColor: accentColor,
        showPortees: showPortees,
      ),
    );
    if (result is Map<String, dynamic>) return result;
    return null;
  }

  /// Multi-select convenience: opens sheet and returns the chosen list or null.
  static Future<List<Map<String, dynamic>>?> pickMany(
    BuildContext context, {
    String? uid,
    String? profileId,
    List<Map<String, dynamic>>? preloaded,
    List<Map<String, dynamic>> current = const [],
    Color accentColor = const Color(0xFF0C5C6C),
    bool showPortees = true,
  }) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnimalPickerSheet(
        uid: uid,
        profileId: profileId,
        preloaded: preloaded,
        multiSelect: true,
        initialSelected: current,
        accentColor: accentColor,
        showPortees: showPortees,
      ),
    );
    if (result is List) return List<Map<String, dynamic>>.from(result);
    return null;
  }

  @override
  State<AnimalPickerSheet> createState() => _AnimalPickerSheetState();
}

class _AnimalPickerSheetState extends State<AnimalPickerSheet> {
  List<Map<String, dynamic>> _animaux = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    for (final a in widget.initialSelected) {
      final id = a['id']?.toString();
      if (id != null) _selectedIds.add(id);
    }
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredAnimaux {
    if (_query.isEmpty) return _animaux;
    return _animaux.where((a) => (a['nom']?.toString() ?? '').toLowerCase().contains(_query)).toList();
  }

  Future<void> _load() async {
    if (widget.preloaded != null) {
      if (mounted) setState(() { _animaux = widget.preloaded!; _loading = false; });
      return;
    }
    try {
      final supa = Supabase.instance.client;
      final uid = widget.uid!;
      final pid = widget.profileId;

      var q = supa.from('animaux')
          .select('id, nom, espece, race, photo_url, portee_id, nom_mere')
          .or('uid_eleveur.eq.$uid,uid_proprietaire.eq.$uid');
      if (pid != null && pid.isNotEmpty) q = q.eq('profile_id', pid);
      final directRows = await q;
      final direct = List<Map<String, dynamic>>.from((directRows as List).map((e) => Map<String, dynamic>.from(e as Map)));

      // animaux_proprietes = source de vérité pour la propriété actuelle
      // (notamment après une cession — animaux.uid_proprietaire n'est pas
      // mis à jour lors d'une cession, seul animaux_proprietes l'est).
      var ownQ = supa.from('animaux_proprietes').select('animal_id').eq('uid_proprio', uid).isFilter('date_fin', null);
      if (pid != null && pid.isNotEmpty) ownQ = ownQ.eq('profile_id_proprio', pid);
      final ownRows = await ownQ;
      final cessionIds = (ownRows as List).map((r) => r['animal_id']?.toString()).whereType<String>().toSet();
      final missingIds = cessionIds.difference(direct.map((a) => a['id']?.toString() ?? '').toSet());

      List<Map<String, dynamic>> viaCession = [];
      if (missingIds.isNotEmpty) {
        final rows2 = await supa.from('animaux')
            .select('id, nom, espece, race, photo_url, portee_id, nom_mere')
            .inFilter('id', missingIds.toList());
        viaCession = List<Map<String, dynamic>>.from((rows2 as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }

      final rows = [...direct, ...viaCession]..sort((a, b) => (a['nom']?.toString() ?? '').compareTo(b['nom']?.toString() ?? ''));
      if (mounted) {
        setState(() {
          _animaux = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleId(String id) => setState(() {
    if (_selectedIds.contains(id)) _selectedIds.remove(id); else _selectedIds.add(id);
  });

  List<Map<String, dynamic>> get _selectedAnimaux =>
      _animaux.where((a) => _selectedIds.contains(a['id']?.toString())).toList();

  // Groupes de portées (multi-select uniquement) — clé = portee_id.
  Map<String, List<Map<String, dynamic>>> get _porteeGroups {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final a in _animaux) {
      final pid = a['portee_id']?.toString();
      if (pid == null || pid.isEmpty) continue;
      map.putIfAbsent(pid, () => []).add(a);
    }
    return map;
  }

  String _porteeLabel(String porteeId, List<Map<String, dynamic>> membres) {
    final nomMere = membres.map((a) => a['nom_mere']?.toString() ?? '').firstWhere((n) => n.isNotEmpty, orElse: () => '');
    if (nomMere.isNotEmpty) return 'Portée de $nomMere';
    final msStr = porteeId.replaceFirst('portee_', '');
    final ms = int.tryParse(msStr);
    if (ms == null) return 'Portée';
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    return 'Portée du ${DateFormat('d MMM yyyy', 'fr').format(date)}';
  }

  // Bascule toute la portée : si tous ses membres sont déjà sélectionnés, on
  // les retire (permet de se rattraper après un clic par erreur), sinon on
  // les ajoute à la sélection existante.
  void _togglePortee(List<Map<String, dynamic>> membres) => setState(() {
    final ids = membres.map((a) => a['id']?.toString()).whereType<String>().toList();
    final allSelected = ids.every(_selectedIds.contains);
    if (allSelected) {
      _selectedIds.removeAll(ids);
    } else {
      _selectedIds.addAll(ids);
    }
  });

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios, size: 20),
              color: const Color(0xFF1F2A2E),
            ),
            Expanded(
              child: Text(
                widget.multiSelect ? 'Sélectionner des animaux' : 'Sélectionner un animal',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1F2A2E)),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 48),
          ]),
        ),
        const Divider(height: 1),
        if (!_loading && _animaux.length > 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher un animal…',
                hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, color: Colors.grey.shade500, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      ),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: color, width: 1.5)),
              ),
            ),
          ),
        if (widget.multiSelect && _selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Wrap(
              spacing: 6, runSpacing: 6,
              children: _selectedAnimaux.map((a) {
                final id = a['id']?.toString() ?? '';
                return GestureDetector(
                  onTap: () => _toggleId(id),
                  child: Container(
                    padding: const EdgeInsets.only(left: 10, right: 6, top: 5, bottom: 5),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(a['nom']?.toString() ?? '—',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                      const SizedBox(width: 4),
                      const Icon(Icons.close, size: 14, color: Colors.white),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        if (widget.multiSelect && widget.showPortees && _query.isEmpty && !_loading && _porteeGroups.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: _porteeGroups.entries.map((e) {
                final allSelected = e.value
                    .map((a) => a['id']?.toString())
                    .whereType<String>()
                    .every(_selectedIds.contains);
                return GestureDetector(
                  onTap: () => _togglePortee(e.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: allSelected ? color : color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: allSelected ? color : color.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      allSelected
                          ? '✓ ${_porteeLabel(e.key, e.value)} (${e.value.length})'
                          : '${_porteeLabel(e.key, e.value)} (${e.value.length}) — tout sélectionner',
                      style: TextStyle(
                        fontFamily: 'Galey', fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: allSelected ? Colors.white : color,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
        ],
        // List
        Flexible(
          child: _loading
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              : _animaux.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Aucun animal enregistré', style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey)),
                    )
                  : _filteredAnimaux.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('Aucun animal pour « ${_searchCtrl.text.trim()} »',
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey)),
                        )
                      : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _filteredAnimaux.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (_, i) {
                        final a = _filteredAnimaux[i];
                        final id = a['id']?.toString() ?? '';
                        final photoUrl = a['photo_url'] as String? ?? '';
                        final selected = _selectedIds.contains(id);
                        return ListTile(
                          tileColor: selected ? color.withValues(alpha: 0.12) : null,
                          onTap: () {
                            if (widget.multiSelect) {
                              _toggleId(id);
                            } else {
                              Navigator.pop(context, a);
                            }
                          },
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF5EA),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: photoUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: photoUrl,
                                      width: 44, height: 44, fit: BoxFit.cover,
                                      placeholder: (_, __) => const Center(child: Text('🐾', style: TextStyle(fontSize: 16))),
                                      errorWidget: (_, __, ___) => const Center(child: Text('🐾', style: TextStyle(fontSize: 16))),
                                    )
                                  : const Center(child: Text('🐾', style: TextStyle(fontSize: 16))),
                            ),
                          ),
                          title: Text(
                            a['nom']?.toString() ?? '—',
                            style: TextStyle(
                              fontFamily: 'Galey', fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? color : const Color(0xFF1F2A2E),
                            ),
                          ),
                          subtitle: Text(
                            [a['espece'], a['race']].where((s) => s?.toString().isNotEmpty == true).join(' · '),
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF888888)),
                          ),
                          trailing: widget.multiSelect
                              ? Checkbox(
                                  value: selected,
                                  activeColor: color,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  onChanged: (_) => _toggleId(id),
                                )
                              : Icon(Icons.chevron_right, color: color, size: 20),
                        );
                      },
                    ),
        ),
        // Confirm button (multi-select only)
        if (widget.multiSelect) ...[
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selectedAnimaux),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _selectedIds.isEmpty
                      ? 'Aucun animal'
                      : 'Confirmer (${_selectedIds.length})',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ),
        ] else
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ]),
    );
  }
}

// ── Tappable field showing selected animals ───────────────────────────────────
class AnimalPickerField extends StatelessWidget {
  final List<Map<String, dynamic>> selected;
  final VoidCallback onTap;
  final String label;
  final Color accentColor;

  const AnimalPickerField({
    super.key,
    required this.selected,
    required this.onTap,
    this.label = 'Animal concerné (optionnel)',
    this.accentColor = const Color(0xFF0C5C6C),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Row(children: [
          Expanded(
            child: selected.isEmpty
                ? Text('Choisir un animal…',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500))
                : Wrap(
                    spacing: 6, runSpacing: 4,
                    children: selected.map((a) {
                      final photoUrl = a['photo_url'] as String? ?? '';
                      return Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF5EA),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: photoUrl.isNotEmpty
                                ? CachedNetworkImage(imageUrl: photoUrl, width: 24, height: 24, fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Center(child: Text('🐾', style: TextStyle(fontSize: 11))))
                                : const Center(child: Text('🐾', style: TextStyle(fontSize: 11))),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(a['nom']?.toString() ?? '—',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: accentColor)),
                      ]);
                    }).toList(),
                  ),
          ),
          Icon(Icons.expand_more, color: Colors.grey.shade500, size: 20),
        ]),
      ),
    );
  }
}
