import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/widgets/conge_date_range_sheet.dart';

/// Section congés réutilisable — ajout direct par l'employeur (statut
/// "approuvé" immédiat) + validation/refus des demandes faites par
/// l'employé lui-même (statut "en_attente"). Utilisée par les fiches
/// employé enrichies (toilettage/garde/pension) — même logique que l'onglet
/// Congés générique (EmployesPage) et le miroir web (EmployesAvancesPage).
class EmployeCongesSection extends StatefulWidget {
  final dynamic employeId;
  final String? employeUidEmploye;
  final String? employeProfileId;
  final Color color;
  const EmployeCongesSection({
    super.key, required this.employeId, this.employeUidEmploye, this.employeProfileId, required this.color,
  });

  @override
  State<EmployeCongesSection> createState() => _EmployeCongesSectionState();
}

class _EmployeCongesSectionState extends State<EmployeCongesSection> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _conges = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final rows = await _supa.from('employe_conges').select()
          .eq('employe_id', widget.employeId).order('date_debut', ascending: false);
      if (mounted) setState(() { _conges = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _ajouter() async {
    final range = await pickCongeDateRange(context, teal: widget.color);
    if (range == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _supa.from('employe_conges').insert({
      'employe_id':      widget.employeId,
      'date_debut':      range.start.toIso8601String().substring(0, 10),
      'date_fin':        range.end.toIso8601String().substring(0, 10),
      'statut':          'approuve',
      'demande_par_uid': uid,
    });
    _load();
  }

  Future<void> _supprimer(String id) async {
    await _supa.from('employe_conges').delete().eq('id', id);
    _load();
  }

  Future<void> _repondre(Map<String, dynamic> conge, bool approuve) async {
    await _supa.from('employe_conges')
        .update({'statut': approuve ? 'approuve' : 'refuse'}).eq('id', conge['id']);
    final employeUid = widget.employeUidEmploye;
    if (employeUid != null) {
      await _supa.from('notifications').insert({
        'uid':   employeUid,
        'type':  'conge_reponse',
        'title': approuve ? 'Congé approuvé' : 'Congé refusé',
        'body':  approuve
            ? 'Votre demande de congé du ${_fmt(conge['date_debut'] as String?)} au ${_fmt(conge['date_fin'] as String?)} a été approuvée.'
            : 'Votre demande de congé du ${_fmt(conge['date_debut'] as String?)} au ${_fmt(conge['date_fin'] as String?)} a été refusée.',
        if ((widget.employeProfileId ?? '').isNotEmpty) 'profile_id': widget.employeProfileId,
        'data':  {'congeId': conge['id'].toString(), 'approved': approuve},
        'read':  false,
      });
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Congés', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
        const Spacer(),
        TextButton.icon(
          onPressed: _ajouter,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: widget.color),
        ),
      ]),
      if (_loading)
        const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else if (_conges.isEmpty)
        Text('Aucun congé programmé.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500))
      else
        ..._conges.map((c) {
          final statut = c['statut'] as String? ?? 'approuve';
          final style = switch (statut) {
            'en_attente' => (label: 'En attente', color: const Color(0xFFC2740B), bg: const Color(0xFFFFF3E0)),
            'refuse'     => (label: 'Refusé',     color: const Color(0xFFC62828), bg: const Color(0xFFFFEBEE)),
            _            => (label: 'Approuvé',   color: const Color(0xFF2E7D32), bg: const Color(0xFFE8F5E9)),
          };
          final motif = c['motif'] as String?;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.event_busy_outlined, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${_fmt(c['date_debut'] as String?)} → ${_fmt(c['date_fin'] as String?)}',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(8)),
                    child: Text(style.label, style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600, color: style.color)),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => _supprimer(c['id'].toString())),
                ]),
                if (motif != null && motif.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(motif, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                  ),
                if (statut == 'en_attente')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Expanded(child: OutlinedButton(
                        onPressed: () => _repondre(c, false),
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828), side: const BorderSide(color: Color(0xFFC62828))),
                        child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey', fontSize: 11)),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: ElevatedButton(
                        onPressed: () => _repondre(c, true),
                        style: ElevatedButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white),
                        child: const Text('Approuver', style: TextStyle(fontFamily: 'Galey', fontSize: 11)),
                      )),
                    ]),
                  ),
              ]),
            ),
          );
        }),
    ]);
  }
}
