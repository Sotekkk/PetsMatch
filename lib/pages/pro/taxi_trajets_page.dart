import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/geocoding_helper.dart';
import 'package:PetsMatch/pages/pro/taxi_factures_page.dart';

// ── Mes trajets (taxi animalier) — historique des courses, sur le modèle
// événementiel de registre_visites_page.dart (garde) : chaque course est un
// RDV existant dans la table générique `rdv`, pas de table dédiée. Pas de
// rapport de visite ni de contrat de prestation (hors scope taxi — "pas de
// contrat, simple réservation").

class TaxiTrajetsPage extends StatefulWidget {
  const TaxiTrajetsPage({super.key});

  @override
  State<TaxiTrajetsPage> createState() => _TaxiTrajetsPageState();
}

class _TaxiTrajetsPageState extends State<TaxiTrajetsPage> {
  static const _teal = Color(0xFF00838F);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _trajets = [];
  bool _showPassees = false;
  Set<String> _facturedRdvIds = {};

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
      var q = _supa.from('rdv').select().eq('pro_uid', uid);
      final pid = User_Info.activeProfileId;
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final rows = await q
          .inFilter('statut', ['confirme', 'termine'])
          .order('date_heure', ascending: true);

      final list = List<Map<String, dynamic>>.from(rows as List);

      final clientUids = list.map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      final clientNames = <String, String>{};
      if (clientUids.isNotEmpty) {
        final profiles = await _supa.from('user_profiles')
            .select('uid, firstname, lastname, nom').inFilter('uid', clientUids).eq('is_main', true);
        for (final c in profiles as List) {
          final nom = (c['nom'] as String?)?.trim();
          final full = nom?.isNotEmpty == true ? nom! : '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
          clientNames[c['uid'] as String] = full.isNotEmpty ? full : 'Client';
        }
      }
      for (final r in list) {
        r['_client_nom'] = clientNames[r['client_uid']] ?? 'Client';
      }

      final rdvIds = list.map((r) => r['id'].toString()).toList();
      final facturedIds = <String>{};
      if (rdvIds.isNotEmpty) {
        final factures = await _supa.from('taxi_factures').select('rdv_id').inFilter('rdv_id', rdvIds);
        for (final f in factures as List) {
          final rid = f['rdv_id']?.toString();
          if (rid != null) facturedIds.add(rid);
        }
      }

      if (mounted) setState(() { _trajets = list; _facturedRdvIds = facturedIds; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _marquerTermine(Map<String, dynamic> rdv) async {
    try {
      await _supa.from('rdv').update({'statut': 'termine'}).eq('id', rdv['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _facturer(Map<String, dynamic> rdv) async {
    final montantCtrl = TextEditingController();
    final montant = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Facturer la course', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: montantCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontFamily: 'Galey'),
          decoration: const InputDecoration(hintText: 'Montant en €', suffixText: '€'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(montantCtrl.text.trim().replaceAll(',', '.'))),
            child: const Text('Facturer'),
          ),
        ],
      ),
    );
    if (montant == null || montant <= 0) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final now = DateTime.now();
      await _supa.from('taxi_factures').insert({
        'pro_uid': uid,
        'pro_profile_id': User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
        'rdv_id': rdv['id'],
        'client_uid': rdv['client_uid'],
        if (rdv['client_profile_id'] != null) 'client_profile_id': rdv['client_profile_id'],
        'numero': 'TAXI-${DateFormat('yyyyMMdd-HHmm').format(now)}',
        'client_nom': rdv['_client_nom'],
        'montant': montant,
        'statut': 'envoyee',
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Course facturée.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final aVenir = _trajets.where((r) {
      final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '');
      return r['statut'] != 'termine' && (dh == null || dh.isAfter(now));
    }).toList();
    final passees = _trajets.where((r) => !aVenir.contains(r)).toList().reversed.toList();
    final displayed = _showPassees ? passees : aVenir;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes trajets', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Mes factures',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaxiFacturesPage())),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Expanded(
                child: _TabChip(label: 'À venir (${aVenir.length})', selected: !_showPassees,
                    onTap: () => setState(() => _showPassees = false)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TabChip(label: 'Passés (${passees.length})', selected: _showPassees,
                    onTap: () => setState(() => _showPassees = true)),
              ),
            ]),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : displayed.isEmpty
              ? Center(child: Text(_showPassees ? 'Aucun trajet passé' : 'Aucun trajet à venir',
                  style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: displayed.length,
                    itemBuilder: (_, i) => _TrajetCard(
                      rdv: displayed[i],
                      onTerminer: () => _marquerTermine(displayed[i]),
                      isFactured: _facturedRdvIds.contains(displayed[i]['id'].toString()),
                      onFacturer: () => _facturer(displayed[i]),
                    ),
                  ),
                ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF00838F) : Colors.white)),
        ),
      );
}

class _TrajetCard extends StatelessWidget {
  final Map<String, dynamic> rdv;
  final VoidCallback onTerminer;
  final bool isFactured;
  final VoidCallback onFacturer;
  static const _teal = Color(0xFF00838F);

  const _TrajetCard({
    required this.rdv,
    required this.onTerminer,
    required this.isFactured,
    required this.onFacturer,
  });

  @override
  Widget build(BuildContext context) {
    final dh = DateTime.tryParse(rdv['date_heure']?.toString() ?? '');
    final dateStr = dh != null ? DateFormat('EEE d MMM · HH:mm', 'fr_FR').format(dh) : '';
    final isTermine = rdv['statut'] == 'termine';
    final nbAnimaux = rdv['nombre_animaux'] as int? ?? 1;

    double? distanceKm;
    if (rdv['lat_depart'] != null && rdv['lng_depart'] != null &&
        rdv['lat_arrivee'] != null && rdv['lng_arrivee'] != null) {
      distanceKm = GeocodingHelper.distanceKm(
        (rdv['lat_depart'] as num).toDouble(), (rdv['lng_depart'] as num).toDouble(),
        (rdv['lat_arrivee'] as num).toDouble(), (rdv['lng_arrivee'] as num).toDouble(),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rdv['_client_nom']?.toString() ?? '',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(dateStr, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isTermine ? const Color(0xFFEEF5EA) : const Color(0xFFE0F2F4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(isTermine ? 'Terminé' : 'Confirmé',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                      color: isTermine ? const Color(0xFF6E9E57) : _teal)),
            ),
          ]),
          const SizedBox(height: 8),
          if ((rdv['adresse_depart'] as String?)?.isNotEmpty == true) Row(children: [
            const Icon(Icons.trip_origin, size: 13, color: Colors.green),
            const SizedBox(width: 6),
            Expanded(child: Text(rdv['adresse_depart'].toString(),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12), overflow: TextOverflow.ellipsis)),
          ]),
          if ((rdv['adresse_arrivee'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 13, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(child: Text(rdv['adresse_arrivee'].toString(),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12), overflow: TextOverflow.ellipsis)),
            ]),
          ],
          const SizedBox(height: 6),
          Row(children: [
            if (distanceKm != null)
              Text('${distanceKm.toStringAsFixed(1)} km', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
            if (distanceKm != null && nbAnimaux > 1) Text('  ·  ', style: TextStyle(color: Colors.grey.shade400)),
            if (nbAnimaux > 1) Text('$nbAnimaux animaux', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ]),
          if (!isTermine) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onTerminer,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                child: const Text('Marquer terminé', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
              ),
            ),
          ],
          if (isTermine && !isFactured) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onFacturer,
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text('Facturer', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
