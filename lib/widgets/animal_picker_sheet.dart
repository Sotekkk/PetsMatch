import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Shared animal picker bottom sheet ────────────────────────────────────────
// multiSelect=true  → returns List<Map> (checkboxes + Confirmer button)
// multiSelect=false → returns Map immediately on tap (single select)
//
// Pass [uid] to load animals, or [preloaded] to skip the DB fetch.

class AnimalPickerSheet extends StatefulWidget {
  final String? uid;
  final List<Map<String, dynamic>>? preloaded;
  final bool multiSelect;
  final List<Map<String, dynamic>> initialSelected;
  final Color accentColor;

  const AnimalPickerSheet({
    super.key,
    this.uid,
    this.preloaded,
    this.multiSelect = false,
    this.initialSelected = const [],
    this.accentColor = const Color(0xFF0C5C6C),
  }) : assert(uid != null || preloaded != null, 'Provide uid or preloaded');

  /// Single-select convenience: opens sheet and returns the chosen animal or null.
  static Future<Map<String, dynamic>?> pickOne(
    BuildContext context, {
    String? uid,
    List<Map<String, dynamic>>? preloaded,
    Map<String, dynamic>? current,
    Color accentColor = const Color(0xFF0C5C6C),
  }) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnimalPickerSheet(
        uid: uid,
        preloaded: preloaded,
        multiSelect: false,
        initialSelected: current != null ? [current] : [],
        accentColor: accentColor,
      ),
    );
    if (result is Map<String, dynamic>) return result;
    return null;
  }

  /// Multi-select convenience: opens sheet and returns the chosen list or null.
  static Future<List<Map<String, dynamic>>?> pickMany(
    BuildContext context, {
    String? uid,
    List<Map<String, dynamic>>? preloaded,
    List<Map<String, dynamic>> current = const [],
    Color accentColor = const Color(0xFF0C5C6C),
  }) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnimalPickerSheet(
        uid: uid,
        preloaded: preloaded,
        multiSelect: true,
        initialSelected: current,
        accentColor: accentColor,
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

  @override
  void initState() {
    super.initState();
    for (final a in widget.initialSelected) {
      final id = a['id']?.toString();
      if (id != null) _selectedIds.add(id);
    }
    _load();
  }

  Future<void> _load() async {
    if (widget.preloaded != null) {
      if (mounted) setState(() { _animaux = widget.preloaded!; _loading = false; });
      return;
    }
    try {
      final uid = widget.uid!;
      final rows = await Supabase.instance.client
          .from('animaux')
          .select('id, nom, espece, race, photo_url')
          .or('uid_eleveur.eq.$uid,uid_proprietaire.eq.$uid')
          .order('nom');
      if (mounted) {
        setState(() {
          _animaux = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
        // List
        Flexible(
          child: _loading
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              : _animaux.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Aucun animal enregistré', style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _animaux.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (_, i) {
                        final a = _animaux[i];
                        final id = a['id']?.toString() ?? '';
                        final photoUrl = a['photo_url'] as String? ?? '';
                        final selected = _selectedIds.contains(id);
                        return ListTile(
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
