import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/pro/animal_acces_page.dart';
import 'package:PetsMatch/pages/pro/compte_rendu_page.dart';
import 'package:PetsMatch/pages/message.dart';

class ProAgendaPage extends StatefulWidget {
  const ProAgendaPage({super.key});

  @override
  State<ProAgendaPage> createState() => _ProAgendaPageState();
}

class _ProAgendaPageState extends State<ProAgendaPage>
    with SingleTickerProviderStateMixin {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F8);
  static const _jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  static const _mois = ['jan.', 'fév.', 'mar.', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.'];

  late TabController _tabCtrl;
  bool _loading = true;
  List<Map<String, dynamic>> _rdvs = [];

  // AG08 — créneaux
  late DateTime _weekStart;
  int _selectedDayIdx = 0;
  final Map<String, bool> _blockedSlots = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    final now = DateTime.now();
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _selectedDayIdx = now.weekday - 1;
    _loadRdvs();
    _loadCreneaux();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRdvs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final rows = await Supabase.instance.client
          .from('rdv')
          .select()
          .eq('pro_uid', uid)
          .order('date_heure');

      // Load client names in batch
      final clientUids = rows
          .map((r) => r['client_uid'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      Map<String, String> clientNames = {};
      if (clientUids.isNotEmpty) {
        try {
          final users = await Supabase.instance.client
              .from('users')
              .select('uid, firstname, lastname, name_elevage')
              .inFilter('uid', clientUids);
          for (final u in users) {
            final uid = u['uid'] as String;
            final name = (u['name_elevage'] as String?)?.isNotEmpty == true
                ? u['name_elevage'] as String
                : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
            clientNames[uid] = name.isNotEmpty ? name : 'Client';
          }
        } catch (_) {}
      }

      // Load animal names in batch
      final animalIds = rows
          .map((r) => r['animal_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      Map<String, String> animalNames = {};
      if (animalIds.isNotEmpty) {
        try {
          final animaux = await Supabase.instance.client
              .from('animaux')
              .select('id, nom')
              .inFilter('id', animalIds);
          for (final a in animaux) {
            animalNames[a['id'].toString()] = a['nom']?.toString() ?? '';
          }
        } catch (_) {}
      }

      // Compter les visites précédentes par client (confirme + terminé)
      Map<String, int> visitCounts = {};
      if (clientUids.isNotEmpty) {
        try {
          final history = await Supabase.instance.client
              .from('rdv')
              .select('client_uid')
              .eq('pro_uid', uid)
              .inFilter('client_uid', clientUids)
              .inFilter('statut', ['confirme', 'termine']);
          for (final h in history) {
            final cUid = h['client_uid'] as String? ?? '';
            if (cUid.isNotEmpty) visitCounts[cUid] = (visitCounts[cUid] ?? 0) + 1;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _rdvs = rows.map((r) {
            final cUid = r['client_uid'] as String?;
            final aId = r['animal_id']?.toString();
            return {
              ...r,
              '_client_name': cUid != null ? (clientNames[cUid] ?? 'Client') : 'Client',
              '_animal_nom': aId != null ? (animalNames[aId] ?? '') : '',
              '_visit_count': cUid != null ? (visitCounts[cUid] ?? 0) : 0,
            };
          }).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _demandes => _rdvs.where((r) => r['statut'] == 'demande').toList();
  List<Map<String, dynamic>> get _avenir {
    final now = DateTime.now();
    return _rdvs.where((r) {
      if (r['statut'] != 'confirme') return false;
      final dh = DateTime.tryParse(r['date_heure'] ?? '');
      return dh != null && dh.isAfter(now);
    }).toList();
  }
  List<Map<String, dynamic>> get _historique {
    final now = DateTime.now();
    return _rdvs.where((r) {
      if (r['statut'] == 'demande') return false;
      if (r['statut'] == 'confirme') {
        final dh = DateTime.tryParse(r['date_heure'] ?? '');
        return dh != null && dh.isBefore(now);
      }
      return true;
    }).toList();
  }

  Future<void> _showAcceptDialog(Map<String, dynamic> rdv) async {
    int duree = 60;

    final requestedDh = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
    int preciseHour   = requestedDh?.hour   ?? 10;
    int preciseMinute = requestedDh?.minute  ?? 0;

    // Counter-proposal state
    bool isCounter         = false;
    DateTime counterDate   = requestedDh ?? DateTime.now().add(const Duration(days: 1));
    int counterHour        = requestedDh?.hour ?? 10;
    int counterMinute      = 0;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Handle
              Center(child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),

              // ── Toggle Confirmer / Contre-proposition (pension only) ───────
              if (_isPension) ...[
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => setModal(() => isCounter = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !isCounter ? _teal : Colors.white,
                        border: Border.all(color: _teal),
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                      ),
                      child: Center(child: Text('Confirmer',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14,
                              color: !isCounter ? Colors.white : _teal))),
                    ),
                  )),
                  Expanded(child: GestureDetector(
                    onTap: () => setModal(() => isCounter = true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isCounter ? _teal : Colors.white,
                        border: Border.all(color: _teal),
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                      ),
                      child: Center(child: Text('Autre créneau',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14,
                              color: isCounter ? Colors.white : _teal))),
                    ),
                  )),
                ]),
                const SizedBox(height: 20),
              ],

              if (_isPension && isCounter) ...[
                // ── Contre-proposition : date + heure ─────────────────────────
                const Text('Proposer un autre créneau',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Le client recevra une notification avec votre proposition.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 14),
                // Date selector
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: counterDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      locale: const Locale('fr'),
                    );
                    if (picked != null) setModal(() => counterDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _teal),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined, color: _teal, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        '${counterDate.day.toString().padLeft(2, "0")}/${counterDate.month.toString().padLeft(2, "0")}/${counterDate.year}',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: _teal),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                // Counter hours
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(14, (i) => i + 7).map((h) {
                      final sel = counterHour == h;
                      return GestureDetector(
                        onTap: () => setModal(() => counterHour = h),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? _teal : Colors.white,
                            border: Border.all(color: sel ? _teal : const Color(0xFFE4E7E2)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$h h', style: TextStyle(
                              fontFamily: 'Galey', fontSize: 13,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                              color: sel ? Colors.white : const Color(0xFF1E2025))),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                // Counter minutes
                Row(children: [0, 15, 30, 45].map((m) {
                  final sel = counterMinute == m;
                  return GestureDetector(
                    onTap: () => setModal(() => counterMinute = m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? _teal : Colors.white,
                        border: Border.all(color: sel ? _teal : const Color(0xFFE4E7E2)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(m == 0 ? '00' : '$m',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                              color: sel ? Colors.white : const Color(0xFF1E2025))),
                    ),
                  );
                }).toList()),
                const SizedBox(height: 6),
                Text(
                  'Proposition : ${counterDate.day.toString().padLeft(2,"0")}/${counterDate.month.toString().padLeft(2,"0")} à ${counterHour.toString().padLeft(2,"0")}h${counterMinute.toString().padLeft(2,"0")}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, {
                      'confirmed':     false,
                      'isCounter':     true,
                      'counterYear':   counterDate.year,
                      'counterMonth':  counterDate.month,
                      'counterDay':    counterDate.day,
                      'counterHour':   counterHour,
                      'counterMinute': counterMinute,
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Envoyer la contre-proposition',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ] else ...[
                if (_isPension) ...[
                  // ── Confirmer : heure exacte dans le créneau demandé ────────
                  const Text('Heure exacte du rendez-vous',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    requestedDh != null
                        ? 'Créneau demandé : ${requestedDh.hour.toString().padLeft(2,"0")}h — ajustez si besoin'
                        : 'Proposez l\'heure exacte au client',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(14, (i) => i + 7).map((h) {
                        final sel = preciseHour == h;
                        return GestureDetector(
                          onTap: () => setModal(() => preciseHour = h),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: sel ? _teal : Colors.white,
                              border: Border.all(color: sel ? _teal : const Color(0xFFE4E7E2)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('$h h', style: TextStyle(
                                fontFamily: 'Galey', fontSize: 13,
                                fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                                color: sel ? Colors.white : const Color(0xFF1E2025))),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [0, 15, 30, 45].map((m) {
                    final sel = preciseMinute == m;
                    return GestureDetector(
                      onTap: () => setModal(() => preciseMinute = m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: sel ? _teal : Colors.white,
                          border: Border.all(color: sel ? _teal : const Color(0xFFE4E7E2)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(m == 0 ? '00' : '$m',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                                color: sel ? Colors.white : const Color(0xFF1E2025))),
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 6),
                  Text(
                    'Heure confirmée : ${preciseHour.toString().padLeft(2, "0")}h${preciseMinute.toString().padLeft(2, "0")}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Durée (commun) ──────────────────────────────────────────
                const Text('Durée du rendez-vous',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                const Text('Sert à bloquer votre agenda — le client ne la verra pas.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 10, children: [15, 30, 45, 60, 90, 120].map((d) {
                  final sel = duree == d;
                  return GestureDetector(
                    onTap: () => setModal(() => duree = d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? _teal : Colors.white,
                        border: Border.all(color: sel ? _teal : const Color(0xFFE4E7E2)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        d < 60 ? '$d min' : (d == 60 ? '1 h' : '${d ~/ 60} h${d % 60 > 0 ? " ${d % 60}" : ""}'),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : const Color(0xFF1E2025)),
                      ),
                    ),
                  );
                }).toList()),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, {
                      'confirmed': true,
                      'isCounter': false,
                      'preciseHour': preciseHour,
                      'preciseMinute': preciseMinute,
                      'duree': duree,
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Confirmer le RDV',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );

    if (result == null) return;

    // ── Contre-proposition ────────────────────────────────────────────────────
    if (result['isCounter'] == true) {
      final counterDh = DateTime(
        result['counterYear'] as int, result['counterMonth'] as int, result['counterDay'] as int,
        result['counterHour'] as int, result['counterMinute'] as int,
      ).toUtc();
      await _sendCounterProposal(rdv, counterDh);
      return;
    }

    if (result['confirmed'] != true) return;

    final dureeMinutes = result['duree'] as int;

    if (_isPension && requestedDh != null) {
      // Update date_heure with the precise time chosen by pension
      final preciseDh = DateTime(
        requestedDh.year, requestedDh.month, requestedDh.day,
        result['preciseHour'] as int, result['preciseMinute'] as int,
      ).toUtc();
      await _updateStatutWithPreciseTime(rdv['id'].toString(), preciseDh, dureeMinutes);
    } else {
      await _updateStatut(rdv['id'].toString(), 'confirme', dureeMinutes: dureeMinutes);
    }
  }

  Future<void> _sendCounterProposal(Map<String, dynamic> rdv, DateTime counterDh) async {
    try {
      final supa = Supabase.instance.client;
      await supa.from('rdv').update({
        'statut':     'contre_proposition',
        'date_heure': counterDh.toIso8601String(),
      }).eq('id', rdv['id']);

      final clientUid = rdv['client_uid'] as String?;
      if (clientUid != null) {
        final proName = User_Info.nameElevage.isNotEmpty ? User_Info.nameElevage : 'La pension';
        final local = counterDh.toLocal();
        final dateStr =
            '${local.day.toString().padLeft(2, "0")}/${local.month.toString().padLeft(2, "0")} '
            'à ${local.hour.toString().padLeft(2, "0")}h${local.minute.toString().padLeft(2, "0")}';
        await supa.from('notifications').insert({
          'uid':   clientUid,
          'type':  'rdv_contre_proposition',
          'title': '$proName vous propose un autre créneau',
          'body':  'Nouvelle proposition : le $dateStr — confirmez ou refusez dans vos RDV.',
          'data':  {'rdv_id': rdv['id']},
          'read':  false,
        });
      }
      await _loadRdvs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Contre-proposition envoyée au client.',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _updateStatutWithPreciseTime(String rdvId, DateTime preciseDh, int dureeMinutes) async {
    try {
      final supa = Supabase.instance.client;
      await supa.from('rdv').update({
        'statut':         'confirme',
        'duree_minutes':  dureeMinutes,
        'date_heure':     preciseDh.toIso8601String(),
      }).eq('id', rdvId);

      final rdv = _rdvs.firstWhere((r) => r['id'].toString() == rdvId, orElse: () => {});
      final clientUid = rdv['client_uid'] as String?;
      final proUid    = FirebaseAuth.instance.currentUser?.uid;
      final proName   = User_Info.nameElevage.isNotEmpty ? User_Info.nameElevage : 'La pension';
      final clientName = rdv['_client_name']?.toString() ?? 'Client';
      // Agenda client
      if (clientUid != null) {
        await supa.from('agenda_events').upsert({
          'uid':           clientUid,
          'titre':         'RDV avec $proName',
          'type':          'rdv',
          'date_debut':    preciseDh.toIso8601String(),
          'animal_id':     rdv['animal_id'],
          'notes':         rdv['motif'],
          'rdv_id':        rdv['id'],
          'duree_minutes': dureeMinutes,
        }, onConflict: 'rdv_id');
        // Notify client
        await supa.from('notifications').insert({
          'uid':   clientUid,
          'type':  'rdv_confirme',
          'title': 'RDV confirmé par $proName',
          'body':  'Votre rendez-vous est confirmé pour le ${preciseDh.toLocal().day.toString().padLeft(2,"0")}/${preciseDh.toLocal().month.toString().padLeft(2,"0")} à ${preciseDh.toLocal().hour.toString().padLeft(2,"0")}h${preciseDh.toLocal().minute.toString().padLeft(2,"0")}',
          'data':  {'rdv_id': rdv['id']},
          'read':  false,
        });
      }
      // Agenda pension — couleur trick (no unique constraint needed)
      if (proUid != null) {
        try {
          await supa.from('agenda_events').delete()
              .eq('uid', proUid).eq('couleur', 'rdv:${rdv['id']}');
          await supa.from('agenda_events').insert({
            'uid':           proUid,
            'titre':         'RDV avec $clientName',
            'type':          'rdv',
            'date_debut':    preciseDh.toIso8601String(),
            'animal_id':     rdv['animal_id'],
            'notes':         rdv['motif'],
            'duree_minutes': dureeMinutes,
            'couleur':       'rdv:${rdv['id']}',
          });
        } catch (_) {}
      }
      await _loadRdvs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _updateStatut(String rdvId, String statut,
      {int? dureeMinutes, String? motifAnnulation}) async {
    try {
      final supa = Supabase.instance.client;
      final update = <String, dynamic>{'statut': statut};
      if (dureeMinutes != null) update['duree_minutes'] = dureeMinutes;
      if (motifAnnulation != null) update['notes_annulation'] = motifAnnulation;
      await supa.from('rdv').update(update).eq('id', rdvId);

      final rdv = _rdvs.firstWhere(
        (r) => r['id'].toString() == rdvId,
        orElse: () => {},
      );
      final clientUid = rdv['client_uid'] as String?;

      if (statut == 'confirme' && clientUid != null) {
        final proUid2   = FirebaseAuth.instance.currentUser?.uid;
        final proName = User_Info.nameElevage.isNotEmpty
            ? User_Info.nameElevage
            : User_Info.professionPro.isNotEmpty
                ? User_Info.professionPro
                : 'Professionnel';
        final clientName2 = rdv['_client_name']?.toString() ?? 'Client';
        final dhUtc = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toUtc();
        // Agenda client
        await supa.from('agenda_events').upsert({
          'uid':           clientUid,
          'titre':         'RDV avec $proName',
          'type':          'rdv',
          'date_debut':    dhUtc?.toIso8601String() ?? rdv['date_heure'],
          'animal_id':     rdv['animal_id'],
          'notes':         rdv['motif'],
          'rdv_id':        rdv['id'],
          if (dureeMinutes != null) 'duree_minutes': dureeMinutes,
        }, onConflict: 'rdv_id');
        // Agenda pension — couleur trick (no unique constraint needed)
        if (proUid2 != null) {
          try {
            await supa.from('agenda_events').delete()
                .eq('uid', proUid2).eq('couleur', 'rdv:${rdv['id']}');
            await supa.from('agenda_events').insert({
              'uid':           proUid2,
              'titre':         'RDV avec $clientName2',
              'type':          'rdv',
              'date_debut':    dhUtc?.toIso8601String() ?? rdv['date_heure'],
              'animal_id':     rdv['animal_id'],
              'notes':         rdv['motif'],
              if (dureeMinutes != null) 'duree_minutes': dureeMinutes,
              'couleur':       'rdv:${rdv['id']}',
            });
          } catch (_) {}
        }
      } else if ((statut == 'annule' || statut == 'refuse') && rdv.isNotEmpty) {
        await supa.from('agenda_events').delete().eq('rdv_id', rdv['id']); // client
        final proUidDel = FirebaseAuth.instance.currentUser?.uid;
        if (proUidDel != null) {
          try {
            await supa.from('agenda_events').delete()
                .eq('uid', proUidDel).eq('couleur', 'rdv:${rdv['id']}');
          } catch (_) {}
        }

        // Notify client
        if (clientUid != null) {
          final proName = User_Info.nameElevage.isNotEmpty
              ? User_Info.nameElevage
              : User_Info.professionPro.isNotEmpty ? User_Info.professionPro : 'Le professionnel';
          final motifPart = (motifAnnulation?.isNotEmpty == true) ? ' — Motif : $motifAnnulation' : '';
          await supa.from('notifications').insert({
            'uid':   clientUid,
            'type':  statut == 'refuse' ? 'rdv_refuse' : 'rdv_annule',
            'title': statut == 'refuse' ? 'Demande de RDV refusée' : 'RDV annulé',
            'body':  statut == 'refuse'
                ? '$proName a refusé votre demande de RDV$motifPart'
                : 'Votre RDV avec $proName a été annulé$motifPart',
            'data':  {'rdv_id': rdv['id']},
            'read':  false,
          });
        }
      }

      await _loadRdvs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _showCancelDialog(Map<String, dynamic> rdv, {bool isRefus = false}) async {
    final ctrl = TextEditingController();
    final label = isRefus ? 'Refuser' : 'Annuler';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          Text('$label ce RDV',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Un motif (optionnel) sera envoyé au client.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Empêchement, motif… (optionnel)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('$label ce RDV',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
    ctrl.dispose();
    if (ok != true || !mounted) return;
    await _updateStatut(rdv['id'].toString(), 'annule',
        motifAnnulation: ctrl.text.trim().isEmpty ? null : ctrl.text.trim());
  }

  void _contactClient(Map<String, dynamic> rdv) {
    final name = rdv['_client_name']?.toString() ?? 'le client';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          Text('Contacter $name',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          const Text('Utilisez la messagerie intégrée pour contacter ce client directement.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => MessagePage()));
              },
              icon: const Icon(Icons.message_outlined),
              label: const Text('Ouvrir la messagerie', style: TextStyle(fontFamily: 'Galey')),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: _teal),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _showNotesDialog(Map<String, dynamic> rdv) async {
    String notes = (rdv['notes_pro'] as String?) ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Notes (visibles par vous seul)',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        content: TextFormField(
          initialValue: notes,
          maxLines: 4,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Ajouter des notes…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(12),
          ),
          onChanged: (v) => notes = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Enregistrer',
                style: TextStyle(color: _teal, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    try {
      await Supabase.instance.client
          .from('rdv')
          .update({'notes_pro': notes})
          .eq('id', rdv['id']);
      if (!mounted) return;
      setState(() {
        final idx = _rdvs.indexWhere((r) => r['id'] == rdv['id']);
        if (idx != -1) _rdvs[idx] = {..._rdvs[idx], 'notes_pro': notes};
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Note enregistrée', style: TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mon agenda',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: 'Demandes${_demandes.isNotEmpty ? " (${_demandes.length})" : ""}'),
            const Tab(text: 'À venir'),
            const Tab(text: 'Historique'),
            const Tab(text: 'Créneaux'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _loadRdvs,
              color: _teal,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildList(_demandes, showActions: true),
                  _buildList(_avenir, showCancel: true),
                  _buildList(_historique, showDelete: true),
                  _buildCreneauxTab(),
                ],
              ),
            ),
    );
  }

  // ── AG08 — Créneaux ──────────────────────────────────────────────────────────

  bool get _isPension => User_Info.catPro == 'pension';

  Future<void> _loadCreneaux() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final weekEnd = _weekStart.add(const Duration(days: 6));
    try {
      final query = Supabase.instance.client
          .from('creneaux_pro')
          .select()
          .eq('pro_uid', uid)
          .gte('date', _weekStart.toIso8601String().substring(0, 10))
          .lte('date', weekEnd.toIso8601String().substring(0, 10));

      // Pension: load 'disponible' slots; others: load 'bloque' slots
      final rows = await (_isPension
          ? query.eq('statut', 'disponible')
          : query.eq('statut', 'bloque'));

      if (!mounted) return;
      setState(() {
        _blockedSlots.clear();
        for (final row in rows) {
          final date = row['date'] as String;
          final heureDebut = (row['heure_debut'] as String).split(':')[0];
          _blockedSlots['${date}_$heureDebut'] = true;
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleSlot(String date, int hour) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final key = '${date}_$hour';
    final isActive = _blockedSlots[key] == true;
    setState(() {
      if (isActive) { _blockedSlots.remove(key); } else { _blockedSlots[key] = true; }
    });
    try {
      final heureDebut = '${hour.toString().padLeft(2, '0')}:00:00';
      if (isActive) {
        await Supabase.instance.client
            .from('creneaux_pro')
            .delete()
            .eq('pro_uid', uid)
            .eq('date', date)
            .eq('heure_debut', heureDebut);
      } else {
        final heureFin = '${(hour + 1).toString().padLeft(2, '0')}:00:00';
        // Pension: publishes disponible slots; others: blocks slots
        final statut = _isPension ? 'disponible' : 'bloque';
        await Supabase.instance.client.from('creneaux_pro').upsert({
          'pro_uid':     uid,
          'date':        date,
          'heure_debut': heureDebut,
          'heure_fin':   heureFin,
          'statut':      statut,
        }, onConflict: 'pro_uid,date,heure_debut');
      }
    } catch (e) {
      setState(() {
        if (isActive) { _blockedSlots[key] = true; } else { _blockedSlots.remove(key); }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _replicateWeek() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Collect all current week's disponible slots
    final weekSlots = _blockedSlots.entries.where((e) => e.value == true).toList();
    if (weekSlots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun créneau à répliquer cette semaine.',
              style: TextStyle(fontFamily: 'Galey')),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    // Confirm with user
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Répliquer les créneaux',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        content: Text(
          '${weekSlots.length} créneau(x) de cette semaine seront copiés sur les 4 semaines suivantes.',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Répliquer',
                style: TextStyle(color: _teal, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final supa = Supabase.instance.client;
      final rows = <Map<String, dynamic>>[];

      for (int week = 1; week <= 4; week++) {
        for (final entry in weekSlots) {
          // key format: 'YYYY-MM-DD_H'
          final parts = entry.key.split('_');
          if (parts.length < 2) continue;
          final originalDate = DateTime.tryParse(parts[0]);
          final hour = int.tryParse(parts[1]);
          if (originalDate == null || hour == null) continue;

          final targetDate = originalDate.add(Duration(days: 7 * week));
          final dateStr = targetDate.toIso8601String().substring(0, 10);
          final heureDebut = '${hour.toString().padLeft(2, '0')}:00:00';
          final heureFin = '${(hour + 1).toString().padLeft(2, '0')}:00:00';

          rows.add({
            'pro_uid':     uid,
            'date':        dateStr,
            'heure_debut': heureDebut,
            'heure_fin':   heureFin,
            'statut':      'disponible',
          });
        }
      }

      await supa.from('creneaux_pro').upsert(rows, onConflict: 'pro_uid,date,heure_debut');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${rows.length} créneau(x) ajoutés sur 4 semaines.',
            style: const TextStyle(fontFamily: 'Galey'),
          ),
          backgroundColor: const Color(0xFF6E9E57),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildCreneauxTab() {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final selectedDay = days[_selectedDayIdx];
    final dateStr = selectedDay.toIso8601String().substring(0, 10);

    return Column(children: [
      // Navigation semaine
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Row(children: [
          IconButton(
            onPressed: () {
              setState(() {
                _weekStart = _weekStart.subtract(const Duration(days: 7));
                _blockedSlots.clear();
              });
              _loadCreneaux();
            },
            icon: const Icon(Icons.chevron_left, color: _teal),
          ),
          Expanded(
            child: Text(
              'Semaine du ${_weekStart.day} ${_mois[_weekStart.month - 1]}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _weekStart = _weekStart.add(const Duration(days: 7));
                _blockedSlots.clear();
              });
              _loadCreneaux();
            },
            icon: const Icon(Icons.chevron_right, color: _teal),
          ),
        ]),
      ),
      // Sélecteur de jour
      SizedBox(
        height: 62,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: 7,
          itemBuilder: (_, i) {
            final day = days[i];
            final sel = i == _selectedDayIdx;
            final isToday = _sameDay(day, DateTime.now());
            return GestureDetector(
              onTap: () => setState(() => _selectedDayIdx = i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? _teal : (isToday ? const Color(0x1A0C5C6C) : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: sel ? _teal : (isToday ? _teal : const Color(0xFFE4E7E2)),
                  ),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_jours[day.weekday - 1],
                      style: TextStyle(
                          fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : Colors.grey)),
                  const SizedBox(height: 2),
                  Text('${day.day}',
                      style: TextStyle(
                          fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : (isToday ? _teal : Colors.black87))),
                ]),
              ),
            );
          },
        ),
      ),
      // Légende
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: _isPension
            ? Row(children: [
                _LegendDot(color: const Color(0xFF6E9E57).withValues(alpha: 0.15), border: const Color(0xFF6E9E57), label: 'Proposé'),
                const SizedBox(width: 16),
                _LegendDot(color: Colors.white, border: const Color(0xFFCCCCCC), label: 'Non proposé'),
                const SizedBox(width: 16),
                _LegendDot(color: const Color(0x1A0C5C6C), border: _teal, label: 'RDV'),
              ])
            : Row(children: [
                _LegendDot(color: Colors.white, border: const Color(0xFF6E9E57), label: 'Disponible'),
                const SizedBox(width: 16),
                _LegendDot(color: const Color(0xFFEEEEEE), border: Colors.grey, label: 'Bloqué'),
                const SizedBox(width: 16),
                _LegendDot(color: const Color(0x1A0C5C6C), border: _teal, label: 'RDV'),
              ]),
      ),
      if (_isPension) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _replicateWeek,
              icon: const Icon(Icons.repeat, size: 16),
              label: const Text('Répliquer aux 4 semaines suivantes',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: _teal),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ],
      const Divider(height: 1),
      // Grille horaire
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          itemCount: 12, // 8h → 19h
          itemBuilder: (_, i) {
            final hour = 8 + i;
            final key = '${dateStr}_$hour';
            final isBlocked = _blockedSlots[key] == true;
            final hasRdv = _rdvs.any((r) {
              final s = r['statut'] as String? ?? '';
              if (s != 'confirme' && s != 'demande') return false;
              final dh = DateTime.tryParse(r['date_heure'] ?? '')?.toLocal();
              if (dh == null || !_sameDay(dh, selectedDay)) return false;
              final dur = (r['duree_minutes'] as num?)?.toInt() ?? 60;
              final rdvStart = dh.hour;
              final rdvEnd = rdvStart + (dur / 60).ceil();
              return hour >= rdvStart && hour < rdvEnd;
            });

            Color bgColor;
            Color borderColor;
            Color textColor;
            IconData? trailingIcon;
            String? trailingLabel;

            if (hasRdv) {
              bgColor = const Color(0x1A0C5C6C);
              borderColor = _teal;
              textColor = _teal;
              trailingLabel = 'RDV';
            } else if (_isPension) {
              // Pension: isBlocked means "proposed/disponible"
              if (isBlocked) {
                bgColor = const Color(0xFF6E9E57).withValues(alpha: 0.12);
                borderColor = const Color(0xFF6E9E57);
                textColor = const Color(0xFF4A7A32);
                trailingIcon = Icons.check_circle_outline;
              } else {
                bgColor = Colors.white;
                borderColor = const Color(0xFFCCCCCC);
                textColor = Colors.grey.shade500;
                trailingIcon = Icons.add_circle_outline;
              }
            } else {
              // Non-pension: isBlocked means unavailable
              if (isBlocked) {
                bgColor = const Color(0xFFEEEEEE);
                borderColor = Colors.grey;
                textColor = Colors.grey.shade600;
                trailingIcon = Icons.block;
              } else {
                bgColor = Colors.white;
                borderColor = const Color(0xFF6E9E57);
                textColor = Colors.black87;
                trailingIcon = Icons.check_circle_outline;
              }
            }

            return GestureDetector(
              onTap: hasRdv ? null : () => _toggleSlot(dateStr, hour),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(children: [
                  Text(
                    '${hour.toString().padLeft(2, '0')}:00 — ${(hour + 1).toString().padLeft(2, '0')}:00',
                    style: TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w600,
                        fontSize: 14, color: textColor),
                  ),
                  const Spacer(),
                  if (trailingLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x260C5C6C),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(trailingLabel,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                              fontWeight: FontWeight.w600, color: _teal)),
                    )
                  else if (trailingIcon != null)
                    Icon(trailingIcon, size: 18,
                        color: _isPension && isBlocked
                            ? const Color(0xFF6E9E57)
                            : _isPension
                                ? Colors.grey.shade400
                                : isBlocked
                                    ? Colors.grey
                                    : Colors.green.shade400),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildList(List<Map<String, dynamic>> rdvs,
      {bool showActions = false, bool showCancel = false, bool showDelete = false}) {
    if (rdvs.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 80),
        const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_available_outlined, size: 60, color: Color(0xFFB0BEC5)),
            SizedBox(height: 12),
            Text('Aucun rendez-vous', style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Color(0xFFB0BEC5))),
          ]),
        ),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rdvs.length,
      itemBuilder: (_, i) {
        final rdv = rdvs[i];
        final animalId = rdv['animal_id']?.toString();
        final hasAnimal = animalId != null && animalId.isNotEmpty;
        final showProTools = !showActions; // confirme + historique uniquement
        return _RdvCard(
          rdv: rdv,
          showActions: showActions,
          showCancel: showCancel,
          onAccept:  () => _showAcceptDialog(rdv),
          onDecline: () => _showCancelDialog(rdv, isRefus: true),
          onCancel:  () => _showCancelDialog(rdv),
          onContact: showCancel ? () => _contactClient(rdv) : null,
          onDelete: showDelete ? () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Supprimer de l\'historique',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                content: const Text('Ce RDV sera supprimé définitivement.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
                  TextButton(onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Supprimer', style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w600))),
                ],
              ),
            );
            if (ok != true || !mounted) return;
            final supa = Supabase.instance.client;
            await supa.from('agenda_events').delete().eq('rdv_id', rdv['id']);
            final proUidDel = FirebaseAuth.instance.currentUser?.uid;
            if (proUidDel != null) {
              try {
                await supa.from('agenda_events').delete()
                    .eq('uid', proUidDel).eq('couleur', 'rdv:${rdv['id']}');
              } catch (_) {}
            }
            await supa.from('rdv').delete().eq('id', rdv['id']);
            await _loadRdvs();
          } : null,
          onDone:    () => _updateStatut(rdv['id'].toString(), 'termine'),
          onNotes:   () => _showNotesDialog(rdv),
          onCarnetSante: (showProTools && hasAnimal)
              ? () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnimalAccesPage(
                    animalId: animalId,
                    ownerUid: rdv['client_uid']?.toString() ?? '',
                    categoryColor: _teal,
                  )))
              : null,
          onCompteRendu: showProTools
              ? () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CompteRenduPage(
                    rdv: rdv,
                    clientName: rdv['_client_name']?.toString() ?? 'Client',
                    categoryColor: _teal,
                    isPension: _isPension,
                  )))
              : null,
        );
      },
    );
  }
}

// ── Légende créneaux ──────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final Color border;
  final String label;
  const _LegendDot({required this.color, required this.border, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
    ]);
  }
}

// ── Carte RDV ──────────────────────────────────────────────────────────────────

class _RdvCard extends StatelessWidget {
  final Map<String, dynamic> rdv;
  final bool showActions;
  final bool showCancel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onNotes;
  final VoidCallback? onCarnetSante;
  final VoidCallback? onCompteRendu;
  final VoidCallback? onContact;
  final VoidCallback? onDelete;

  const _RdvCard({
    required this.rdv,
    required this.showActions,
    required this.showCancel,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
    required this.onDone,
    required this.onNotes,
    this.onCarnetSante,
    this.onCompteRendu,
    this.onContact,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateHeure = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
    final clientName = rdv['_client_name']?.toString() ?? 'Client';
    final animalNom = rdv['_animal_nom']?.toString() ?? '';
    final motif = rdv['motif']?.toString() ?? '';
    final duree = (rdv['duree_minutes'] as num?)?.toInt();
    final notes = rdv['notes_pro']?.toString() ?? '';
    final statut = rdv['statut']?.toString() ?? '';
    final hasNotes = notes.isNotEmpty;
    final visitCount = (rdv['_visit_count'] as int?) ?? 0;
    final isFirstVisit = visitCount <= 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with date + status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _statutColor(statut).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_outlined, size: 15, color: _statutColor(statut)),
              const SizedBox(width: 8),
              Text(
                dateHeure != null ? _formatDateTime(dateHeure) : '—',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 14, color: _statutColor(statut)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statutColor(statut).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statutLabel(statut),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                        color: _statutColor(statut), fontWeight: FontWeight.w600)),
              ),
            ]),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Client + badge visite
              Row(children: [
                const CircleAvatar(radius: 14, backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.person_outline, size: 16, color: Color(0xFF0C5C6C))),
                const SizedBox(width: 10),
                Expanded(child: Text(clientName, style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w600, fontSize: 14))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isFirstVisit ? Colors.amber.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isFirstVisit ? Colors.amber.shade300 : Colors.blue.shade200),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(isFirstVisit ? Icons.star_outline : Icons.repeat,
                        size: 12, color: isFirstVisit ? Colors.amber.shade700 : Colors.blue.shade600),
                    const SizedBox(width: 4),
                    Text(
                      isFirstVisit ? 'Première visite' : '$visitCount visites',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                          color: isFirstVisit ? Colors.amber.shade700 : Colors.blue.shade600),
                    ),
                  ]),
                ),
              ]),
              if (animalNom.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.pets, size: 14, color: Color(0xFF6E9E57)),
                  const SizedBox(width: 10),
                  Text(animalNom, style: const TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6E9E57))),
                ]),
              ],
              const SizedBox(height: 8),

              // Motif + durée
              if (motif.isNotEmpty)
                Text(motif, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF555F6A))),
              const SizedBox(height: 4),
              Text(
                duree != null
                    ? (duree < 60 ? 'Durée : $duree min' : 'Durée : ${duree ~/ 60} h${duree % 60 > 0 ? " ${duree % 60}" : ""}')
                    : 'Durée : à définir par le professionnel',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: duree != null ? Colors.grey : Colors.orange.shade400),
              ),

              // Notes indicator
              if (hasNotes) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.sticky_note_2_outlined, size: 13, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(child: Text(notes, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange))),
                ]),
              ],
            ]),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(children: [
              // Notes button always visible
              IconButton(
                onPressed: onNotes,
                icon: Icon(Icons.edit_note_outlined,
                    size: 20, color: hasNotes ? Colors.orange : Colors.grey),
                tooltip: 'Notes',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  tooltip: 'Supprimer',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
              if (onCarnetSante != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: onCarnetSante,
                  icon: const Icon(Icons.medical_information_outlined, size: 20, color: Color(0xFF0C5C6C)),
                  tooltip: 'Carnet de santé',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
              if (onCompteRendu != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: onCompteRendu,
                  icon: const Icon(Icons.description_outlined, size: 20, color: Color(0xFF6E9E57)),
                  tooltip: 'CR / Ordonnance',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
              const SizedBox(width: 8),

              if (showActions) ...[
                const Spacer(),
                OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5C6C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    elevation: 0,
                  ),
                  child: const Text('Accepter', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ] else if (showCancel) ...[
                if (onContact != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: onContact,
                    icon: const Icon(Icons.message_outlined, size: 20, color: Color(0xFF0C5C6C)),
                    tooltip: 'Contacter le client',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: onDone,
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF6E9E57)),
                  child: const Text('Terminé', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ),
                OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Color _statutColor(String s) => switch (s) {
    'confirme' => const Color(0xFF0C5C6C),
    'termine'  => const Color(0xFF6E9E57),
    'annule'   => Colors.red,
    'no_show'  => Colors.orange,
    _          => const Color(0xFFF59E0B),
  };

  String _statutLabel(String s) => switch (s) {
    'confirme' => 'Confirmé',
    'termine'  => 'Terminé',
    'annule'   => 'Annulé',
    'no_show'  => 'Non présenté',
    _          => 'En attente',
  };

  String _formatDateTime(DateTime d) {
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const mois = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'août', 'sep', 'oct', 'nov', 'déc'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]} — $h:$m';
  }
}
