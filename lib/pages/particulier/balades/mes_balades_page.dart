import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/particulier/balades/balade_recap_page.dart' show BaladeRecapPage;

/// Historique des balades trackées GPS — toutes, ou filtrées sur un animal
/// précis quand ouvert depuis sa fiche.
class MesBaladesPage extends StatefulWidget {
  final String? animalId;
  final String? animalNom;
  const MesBaladesPage({super.key, this.animalId, this.animalNom});

  @override
  State<MesBaladesPage> createState() => _MesBaladesPageState();
}

class _MesBaladesPageState extends State<MesBaladesPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _balades = [];
  Map<String, String> _animalNoms = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var q = _supa.from('balades_perso').select().eq('uid', User_Info.uid).eq('statut', 'terminee');
      if (widget.animalId != null) q = q.eq('animal_id', widget.animalId as Object);
      final rows = await q.order('started_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (widget.animalId == null) {
        final ids = list.map((r) => r['animal_id']?.toString()).whereType<String>().toSet().toList();
        if (ids.isNotEmpty) {
          final animRows = await _supa.from('animaux').select('id, nom').inFilter('id', ids);
          _animalNoms = {for (final a in (animRows as List)) (a as Map)['id'].toString(): a['nom']?.toString() ?? 'Animal'};
        }
      }
      if (mounted) setState(() { _balades = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDuree(int? s) {
    if (s == null) return '';
    final d = Duration(seconds: s);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '$m min';
  }

  String _fmtDistance(num? m) {
    if (m == null) return '';
    final v = m.toDouble();
    return v >= 1000 ? '${(v / 1000).toStringAsFixed(2)} km' : '${v.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(widget.animalNom != null ? 'Balades avec ${widget.animalNom}' : 'Mes balades',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _balades.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.directions_walk, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('Aucune balade enregistrée pour le moment.',
                          textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                    ]),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _balades.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final b = _balades[i];
                    final photos = (b['photos'] as List?)?.cast<String>() ?? const [];
                    final started = DateTime.tryParse(b['started_at']?.toString() ?? '');
                    final animalNom = widget.animalNom ?? _animalNoms[b['animal_id']?.toString()] ?? 'Animal';
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openDetail(b, animalNom),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))]),
                        child: Row(children: [
                          if (photos.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(imageUrl: photos.first, width: 56, height: 56, fit: BoxFit.cover),
                            )
                          else
                            Container(width: 56, height: 56,
                                decoration: BoxDecoration(color: const Color(0xFFEAF2F4), borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.directions_walk, color: _teal)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('🚶 $animalNom', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                '${_fmtDistance(b['distance_m'] as num?)} · ${_fmtDuree(b['duree_s'] as int?)}'
                                '${started != null ? ' · ${DateFormat('dd/MM/yyyy', 'fr').format(started)}' : ''}',
                                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600),
                              ),
                              if (b['xp_earned'] != null) ...[
                                const SizedBox(height: 2),
                                Text('⭐ +${b['xp_earned']} XP', style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _teal)),
                              ],
                            ]),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }

  void _openDetail(Map<String, dynamic> b, String animalNom) {
    final route = (b['route'] as List? ?? [])
        .map((p) => LatLng(((p as Map)['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
        .toList();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BaladeRecapPage(
        baladeId: b['id']?.toString(),
        animalId: b['animal_id']?.toString() ?? '',
        animalNom: animalNom,
        espece: '',
        distanceM: (b['distance_m'] as num?)?.toDouble() ?? 0,
        dureeSecondes: (b['duree_s'] as int?) ?? 0,
        routePoints: route,
        photoUrls: (b['photos'] as List?)?.cast<String>() ?? const [],
        alreadySaved: true,
        existingXpEarned: (b['xp_earned'] as num?)?.toInt(),
      ),
    ));
  }
}
