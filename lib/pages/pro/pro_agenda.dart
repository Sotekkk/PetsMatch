import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/pro/animal_acces_page.dart';
import 'package:PetsMatch/pages/pro/compte_rendu_page.dart';

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

      if (mounted) {
        setState(() {
          _rdvs = rows.map((r) {
            final cUid = r['client_uid'] as String?;
            final aId = r['animal_id']?.toString();
            return {
              ...r,
              '_client_name': cUid != null ? (clientNames[cUid] ?? 'Client') : 'Client',
              '_animal_nom': aId != null ? (animalNames[aId] ?? '') : '',
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
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Durée du rendez-vous',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Le client ne verra pas cette durée — elle sert à bloquer votre agenda.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 18),
            Wrap(spacing: 10, runSpacing: 10, children: [30, 45, 60, 90, 120].map((d) {
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
                    style: TextStyle(
                        fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : const Color(0xFF1E2025)),
                  ),
                ),
              );
            }).toList()),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
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
          ]),
        ),
      ),
    );
    if (confirmed == true) {
      await _updateStatut(rdv['id'].toString(), 'confirme', dureeMinutes: duree);
    }
  }

  Future<void> _updateStatut(String rdvId, String statut, {int? dureeMinutes}) async {
    try {
      final supa = Supabase.instance.client;
      final update = <String, dynamic>{'statut': statut};
      if (dureeMinutes != null) update['duree_minutes'] = dureeMinutes;
      await supa.from('rdv').update(update).eq('id', rdvId);

      // Sync agenda du client
      final rdv = _rdvs.firstWhere(
        (r) => r['id'].toString() == rdvId,
        orElse: () => {},
      );
      final clientUid = rdv['client_uid'] as String?;

      if (statut == 'confirme' && clientUid != null) {
        final proName = User_Info.nameElevage.isNotEmpty
            ? User_Info.nameElevage
            : User_Info.professionPro.isNotEmpty
                ? User_Info.professionPro
                : 'Professionnel';
        final dhUtc = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toUtc();
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
      } else if ((statut == 'annule' || statut == 'refuse') && rdv.isNotEmpty) {
        await supa.from('agenda_events').delete().eq('rdv_id', rdv['id']);
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
                  _buildList(_historique),
                  _buildCreneauxTab(),
                ],
              ),
            ),
    );
  }

  // ── AG08 — Créneaux ──────────────────────────────────────────────────────────

  Future<void> _loadCreneaux() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final weekEnd = _weekStart.add(const Duration(days: 6));
    try {
      final rows = await Supabase.instance.client
          .from('creneaux_pro')
          .select()
          .eq('pro_uid', uid)
          .gte('date', _weekStart.toIso8601String().substring(0, 10))
          .lte('date', weekEnd.toIso8601String().substring(0, 10));
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
    final isBlocked = _blockedSlots[key] == true;
    setState(() {
      if (isBlocked) _blockedSlots.remove(key);
      else _blockedSlots[key] = true;
    });
    try {
      if (isBlocked) {
        await Supabase.instance.client
            .from('creneaux_pro')
            .delete()
            .eq('pro_uid', uid)
            .eq('date', date)
            .like('heure_debut', '$hour:%');
      } else {
        final heureDebut = '${hour.toString().padLeft(2, '0')}:00:00';
        final heureFin   = '${(hour + 1).toString().padLeft(2, '0')}:00:00';
        await Supabase.instance.client.from('creneaux_pro').upsert({
          'pro_uid':     uid,
          'date':        date,
          'heure_debut': heureDebut,
          'heure_fin':   heureFin,
          'statut':      'bloque',
        }, onConflict: 'pro_uid,date,heure_debut');
      }
    } catch (e) {
      // Rollback optimiste
      setState(() {
        if (isBlocked) _blockedSlots[key] = true;
        else _blockedSlots.remove(key);
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
        child: Row(children: [
          _LegendDot(color: Colors.white, border: const Color(0xFF6E9E57), label: 'Disponible'),
          const SizedBox(width: 16),
          _LegendDot(color: const Color(0xFFEEEEEE), border: Colors.grey, label: 'Bloqué'),
          const SizedBox(width: 16),
          _LegendDot(color: const Color(0x1A0C5C6C), border: _teal, label: 'RDV'),
        ]),
      ),
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
            if (hasRdv) {
              bgColor = const Color(0x1A0C5C6C);
              borderColor = _teal;
              textColor = _teal;
            } else if (isBlocked) {
              bgColor = const Color(0xFFEEEEEE);
              borderColor = Colors.grey;
              textColor = Colors.grey.shade600;
            } else {
              bgColor = Colors.white;
              borderColor = const Color(0xFF6E9E57);
              textColor = Colors.black87;
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
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: textColor),
                  ),
                  const Spacer(),
                  if (hasRdv)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x260C5C6C),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('RDV',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                              fontWeight: FontWeight.w600, color: _teal)),
                    )
                  else if (isBlocked)
                    const Icon(Icons.block, size: 18, color: Colors.grey)
                  else
                    Icon(Icons.check_circle_outline, size: 18, color: Colors.green.shade400),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildList(List<Map<String, dynamic>> rdvs,
      {bool showActions = false, bool showCancel = false}) {
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
          onDecline: () => _updateStatut(rdv['id'].toString(), 'annule'),
          onCancel:  () => _updateStatut(rdv['id'].toString(), 'annule'),
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
              // Client
              Row(children: [
                const CircleAvatar(radius: 14, backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.person_outline, size: 16, color: Color(0xFF0C5C6C))),
                const SizedBox(width: 10),
                Text(clientName, style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w600, fontSize: 14)),
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
