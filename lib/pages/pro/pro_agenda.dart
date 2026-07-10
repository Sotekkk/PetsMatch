import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/pro/compte_rendu_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/utils/geocoding_helper.dart';

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
  List<Map<String, dynamic>> _aujourdhui = [];

  // AG08 — créneaux
  late DateTime _weekStart;
  int _selectedDayIdx = 0;
  final Map<String, String> _blockedSlots = {};
  // Type de prestation par créneau (éducateur uniquement) : 'individuel' /
  // 'collectif' / absent = les deux.
  final Map<String, String> _slotTypes = {};

  // VET07 — retard
  bool _retardDeclare = false;

  // Équipe d'intervenants — employés assignables à un RDV (instructeur_profile_id)
  List<({String profileId, String nom})> _employes = [];
  bool _employesLoaded = false;

  // Durées par motif (pour pré-remplir le dialog de confirmation)
  Map<String, int> _dureesMotifs = {};
  static const _motifToDuree = <String, String>{
    'Consultation': 'consultation', 'Vaccination': 'vaccination',
    'Bilan annuel': 'bilan', 'Urgence': 'urgence', 'Chirurgie': 'chirurgie',
    'Visite de la pension': 'visite', "Arrivée de l'animal": 'arrivee',
    "Départ de l'animal": 'depart',
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    final now = DateTime.now();
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _selectedDayIdx = now.weekday - 1;
    _loadRdvs();
    _loadCreneaux();
    _loadDureesMotifs();
    _loadAujourdhui();
    _loadEmployes();
    User_Info.profileNotifier.addListener(_onProfileChange);
  }

  // Équipe d'intervenants — employés assignables à un RDV/cours (ordre de
  // grandeur : quelques personnes, chargés une fois par ouverture de page).
  Future<void> _loadEmployes() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final pid = User_Info.activeProfileId;
      var q = Supabase.instance.client.from('employes')
          .select('uid_employe, employe_profile_id').eq('actif', true);
      q = pid.isNotEmpty ? q.eq('eleveur_profile_id', pid) : q.eq('uid_eleveur', uid);
      final emps = await q;
      if (emps.isEmpty) { if (mounted) setState(() => _employesLoaded = true); return; }

      final uidByProfileId = <String, String>{};
      final profileIds = emps.map((e) => e['employe_profile_id'] as String?).whereType<String>().toList();
      if (profileIds.isNotEmpty) {
        final profs = await Supabase.instance.client.from('user_profiles')
            .select('id, uid').inFilter('id', profileIds);
        for (final p in profs) {
          uidByProfileId[p['id'].toString()] = p['uid'].toString();
        }
      }

      final employeUids = <String>{};
      for (final e in emps) {
        final pfid = e['employe_profile_id'] as String?;
        final u = pfid != null ? uidByProfileId[pfid] : e['uid_employe'] as String?;
        if (u != null && u.isNotEmpty) employeUids.add(u);
      }
      if (employeUids.isEmpty) { if (mounted) setState(() => _employesLoaded = true); return; }

      final users = await Supabase.instance.client.from('users')
          .select('uid, firstname, lastname').inFilter('uid', employeUids.toList());
      final nameByUid = <String, String>{
        for (final u in users)
          u['uid'].toString(): '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim(),
      };

      final result = <({String profileId, String nom})>[];
      for (final e in emps) {
        final pfid = e['employe_profile_id'] as String?;
        if (pfid == null) continue;
        final u = uidByProfileId[pfid];
        final nom = (u != null ? nameByUid[u] : null) ?? 'Employé';
        result.add((profileId: pfid, nom: nom.isNotEmpty ? nom : 'Employé'));
      }
      if (mounted) setState(() { _employes = result; _employesLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _employesLoaded = true);
    }
  }

  void _onProfileChange() {
    _loadRdvs();
    _loadCreneaux();
    _loadAujourdhui();
  }

  // Séances du jour (RDV + cours collectifs confondus, via agenda_events).
  Future<void> _loadAujourdhui() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Même résolution de profil que _loadRdvs() — si le profil actif n'est
    // pas encore renseigné, ne pas afficher sans filtre (fuite cross-profil),
    // mais retomber sur le premier profil pro disponible.
    String pid = User_Info.activeProfileId;
    if (pid.isEmpty && User_Info.availableProfiles.isNotEmpty) {
      final proProfile = User_Info.availableProfiles.firstWhere(
        (p) => p['profile_type'] != 'particulier',
        orElse: () => User_Info.availableProfiles.first,
      );
      pid = proProfile['id']?.toString() ?? '';
    }
    if (pid.isEmpty) { if (mounted) setState(() => _aujourdhui = []); return; }
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    try {
      final rows = await Supabase.instance.client
          .from('agenda_events')
          .select()
          .eq('uid', uid)
          .eq('pro_profile_id', pid)
          .gte('date_debut', start.toIso8601String())
          .lt('date_debut', end.toIso8601String())
          .order('date_debut');
      if (mounted) setState(() => _aujourdhui = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  Future<void> _loadDureesMotifs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('users').select('durees_motifs').eq('uid', uid).maybeSingle();
      if (row?['durees_motifs'] is Map && mounted) {
        setState(() {
          _dureesMotifs = Map<String, int>.from(
            (row!['durees_motifs'] as Map).map((k, v) =>
                MapEntry(k.toString(), (v as num?)?.toInt() ?? 30)));
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    User_Info.profileNotifier.removeListener(_onProfileChange);
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRdvs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    // Si le profil actif est vide, utiliser le premier profil pro disponible
    String pid = User_Info.activeProfileId;
    if (pid.isEmpty && User_Info.availableProfiles.isNotEmpty) {
      final proProfile = User_Info.availableProfiles.firstWhere(
        (p) => p['profile_type'] != 'particulier',
        orElse: () => User_Info.availableProfiles.first,
      );
      pid = proProfile['id']?.toString() ?? '';
    }
    try {
      var q = Supabase.instance.client
          .from('rdv')
          .select()
          .eq('pro_uid', uid);
      if (pid.isNotEmpty) q = q.eq('pro_profile_id', pid);
      final rows = await q.order('date_heure', ascending: true);

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

  List<Map<String, dynamic>> get _demandes => _rdvs.where((r) =>
      r['statut'] == 'demande' || r['statut'] == 'contre_proposition').toList();
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
      if (r['statut'] == 'contre_proposition') return false;
      if (r['statut'] == 'confirme') {
        final dh = DateTime.tryParse(r['date_heure'] ?? '');
        return dh != null && dh.isBefore(now);
      }
      return true;
    }).toList();
  }

  Future<void> _showAcceptDialog(Map<String, dynamic> rdv) async {
    // Pré-remplir la durée depuis la config du pro selon le motif
    final motifLabel = rdv['motif']?.toString() ?? '';
    final motifKey = _motifToDuree[motifLabel];
    final rdvDuree = (rdv['duree_minutes'] as num?)?.toInt();
    int duree = rdvDuree ??
        (motifKey != null ? (_dureesMotifs[motifKey] ?? 30) : 30);

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

              // ── Toggle Confirmer / Contre-proposition ─────────────────────
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

              if (isCounter) ...[
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
                ...[
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

    if (requestedDh != null) {
      // Update date_heure with the precise time chosen by the pro
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
        'statut':               'confirme',
        'duree_minutes':        dureeMinutes,
        'date_heure':           preciseDh.toIso8601String(),
        'reminder_1h_sent':    false,  // reset si heure modifiée
        'reminder_15min_sent': false,
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
          'pro_profile_id': rdv['client_profile_id'],
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
            'uid':            proUid,
            'titre':          'RDV avec $clientName',
            'type':           'rdv',
            'date_debut':     preciseDh.toIso8601String(),
            'animal_id':      rdv['animal_id'],
            'notes':          rdv['motif'],
            'duree_minutes':  dureeMinutes,
            'couleur':        'rdv:${rdv['id']}',
            'pro_profile_id': rdv['pro_profile_id'],
          });
        } catch (_) {}
      }
      // A60 — accès carnet santé automatique
      await _autoGrantAccess(rdv);
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

  Future<void> _showModifierDialog(Map<String, dynamic> rdv) async {
    final currentDh = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    DateTime date = DateTime(currentDh.year, currentDh.month, currentDh.day);
    int hour = currentDh.hour;
    int minute = currentDh.minute;
    int duree = (rdv['duree_minutes'] as num?)?.toInt() ?? 60;
    final motifCtrl = TextEditingController(text: rdv['motif']?.toString() ?? '');
    final lieuCtrl = TextEditingController(text: rdv['lieu']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: rdv['notes_pro']?.toString() ?? '');
    String? instructeurProfileId = rdv['instructeur_profile_id']?.toString();
    if (instructeurProfileId != null && instructeurProfileId.isEmpty) instructeurProfileId = null;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const Text('Modifier le RDV', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: date,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)), locale: const Locale('fr'));
                  if (picked != null) setModal(() => date = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _teal), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, color: _teal, size: 18),
                    const SizedBox(width: 10),
                    Text('${date.day.toString().padLeft(2, "0")}/${date.month.toString().padLeft(2, "0")}/${date.year}',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: _teal)),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: DropdownButtonFormField<int>(
                  initialValue: hour,
                  decoration: const InputDecoration(labelText: 'Heure', border: OutlineInputBorder()),
                  items: List.generate(14, (i) => i + 7).map((h) => DropdownMenuItem(value: h, child: Text('${h}h'))).toList(),
                  onChanged: (v) => setModal(() => hour = v ?? hour),
                )),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<int>(
                  initialValue: minute,
                  decoration: const InputDecoration(labelText: 'Minutes', border: OutlineInputBorder()),
                  items: const [0, 15, 30, 45].map((m) => DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0')))).toList(),
                  onChanged: (v) => setModal(() => minute = v ?? minute),
                )),
              ]),
              const SizedBox(height: 14),
              const Text('Durée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [15, 30, 45, 60, 90, 120].map((d) {
                final sel = duree == d;
                return GestureDetector(
                  onTap: () => setModal(() => duree = d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? _teal : Colors.white,
                      border: Border.all(color: sel ? _teal : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(d < 60 ? '$d min' : d == 60 ? '1 h' : '${d ~/ 60} h',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: sel ? Colors.white : Colors.black87)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 14),
              TextField(controller: motifCtrl, decoration: const InputDecoration(labelText: 'Motif', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: lieuCtrl, decoration: const InputDecoration(
                  labelText: 'Lieu', hintText: 'Au cabinet, au domicile du client…', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              if (_employes.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  initialValue: instructeurProfileId,
                  decoration: const InputDecoration(labelText: 'Intervenant assigné', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Moi')),
                    for (final e in _employes)
                      DropdownMenuItem<String?>(value: e.profileId, child: Text(e.nom)),
                  ],
                  onChanged: (v) => setModal(() => instructeurProfileId = v),
                ),
                const SizedBox(height: 12),
              ],
              TextField(controller: notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optionnel)', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ),
      ),
    );

    if (result != true) return;
    final newDh = DateTime(date.year, date.month, date.day, hour, minute);
    await _modifierRdv(rdv, newDh, duree, motifCtrl.text.trim(), lieuCtrl.text.trim(),
        notesCtrl.text.trim(), instructeurProfileId);
  }

  Future<void> _modifierRdv(Map<String, dynamic> rdv, DateTime newDh, int duree, String motif,
      String lieu, String notes, String? instructeurProfileId) async {
    try {
      final supa = Supabase.instance.client;
      final rdvId = rdv['id'].toString();
      // Ne re-géocode que si le lieu a changé, pour éviter un appel réseau inutile
      // à chaque modification (durée, motif…) qui ne touche pas l'adresse.
      double? lieuLat;
      double? lieuLng;
      if (lieu.isNotEmpty && lieu != (rdv['lieu']?.toString() ?? '')) {
        final geo = await GeocodingHelper.geocode(lieu);
        lieuLat = geo?.lat;
        lieuLng = geo?.lng;
      } else if (lieu.isNotEmpty) {
        lieuLat = (rdv['lieu_lat'] as num?)?.toDouble();
        lieuLng = (rdv['lieu_lng'] as num?)?.toDouble();
      }
      await supa.from('rdv').update({
        'date_heure': newDh.toIso8601String(),
        'duree_minutes': duree,
        'motif': motif.isNotEmpty ? motif : null,
        'lieu': lieu.isNotEmpty ? lieu : null,
        'lieu_lat': lieuLat,
        'lieu_lng': lieuLng,
        'notes_pro': notes.isNotEmpty ? notes : null,
        'instructeur_profile_id': instructeurProfileId,
        'reminder_48h_sent': false, 'reminder_24h_sent': false,
        'reminder_1h_sent': false, 'reminder_15min_sent': false,
      }).eq('id', rdvId);

      final clientUid = rdv['client_uid'] as String?;
      final proUid = FirebaseAuth.instance.currentUser?.uid;
      final proName = User_Info.nameElevage.isNotEmpty ? User_Info.nameElevage : 'Le professionnel';
      final clientName = rdv['_client_name']?.toString() ?? 'Client';

      if (clientUid != null) {
        await supa.from('agenda_events').upsert({
          'uid': clientUid, 'titre': 'RDV avec $proName', 'type': 'rdv',
          'date_debut': newDh.toIso8601String(), 'animal_id': rdv['animal_id'],
          'notes': motif, 'rdv_id': rdvId, 'duree_minutes': duree,
          'pro_profile_id': rdv['client_profile_id'],
        }, onConflict: 'rdv_id');
        await supa.from('notifications').insert({
          'uid': clientUid, 'type': 'rdv_modifie',
          'title': 'RDV modifié par $proName',
          'body': 'Votre rendez-vous a été mis à jour : ${newDh.day.toString().padLeft(2, "0")}/${newDh.month.toString().padLeft(2, "0")} à ${newDh.hour.toString().padLeft(2, "0")}h${newDh.minute.toString().padLeft(2, "0")}${lieu.isNotEmpty ? " — $lieu" : ""}',
          'data': {'rdv_id': rdvId}, 'read': false,
        });
      }
      if (proUid != null) {
        await supa.from('agenda_events').delete().eq('uid', proUid).eq('couleur', 'rdv:$rdvId');
        await supa.from('agenda_events').insert({
          'uid': proUid, 'titre': 'RDV avec $clientName', 'type': 'rdv',
          'date_debut': newDh.toIso8601String(), 'animal_id': rdv['animal_id'],
          'notes': motif, 'duree_minutes': duree, 'couleur': 'rdv:$rdvId',
          'pro_profile_id': rdv['pro_profile_id'],
        });
      }
      await _loadRdvs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('RDV modifié.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57), behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
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
          'pro_profile_id': rdv['client_profile_id'],
          if (dureeMinutes != null) 'duree_minutes': dureeMinutes,
        }, onConflict: 'rdv_id');
        // Agenda pension — couleur trick (no unique constraint needed)
        if (proUid2 != null) {
          try {
            await supa.from('agenda_events').delete()
                .eq('uid', proUid2).eq('couleur', 'rdv:${rdv['id']}');
            await supa.from('agenda_events').insert({
              'uid':            proUid2,
              'titre':          'RDV avec $clientName2',
              'type':           'rdv',
              'date_debut':     dhUtc?.toIso8601String() ?? rdv['date_heure'],
              'animal_id':      rdv['animal_id'],
              'notes':          rdv['motif'],
              if (dureeMinutes != null) 'duree_minutes': dureeMinutes,
              'couleur':        'rdv:${rdv['id']}',
              'pro_profile_id': rdv['pro_profile_id'],
            });
          } catch (_) {}
        }
        // A60 — accès carnet santé automatique
        await _autoGrantAccess(rdv);
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

  // ── VET07 — Retard ───────────────────────────────────────────────────────────

  Future<void> _showRetardDialog() async {
    int delai = 15;
    final msgCtrl = TextEditingController();
    bool sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              const Text('Signaler un retard',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
            ]),
            const SizedBox(height: 4),
            const Text('Vos clients avec un RDV dans les 3 prochaines heures seront notifiés.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),
            const Text('Délai estimé',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [15, 30, 45, 60, 90].map((d) {
                final sel = delai == d;
                return GestureDetector(
                  onTap: () => setModal(() => delai = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? Colors.orange : Colors.white,
                      border: Border.all(color: sel ? Colors.orange : const Color(0xFFE4E7E2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      d < 60 ? '$d min' : '${d ~/ 60} h',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                          color: sel ? Colors.white : const Color(0xFF1E2025)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: msgCtrl,
              maxLength: 140,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Message optionnel pour vos clients…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: sending ? null : () async {
                  setModal(() => sending = true);
                  Navigator.pop(ctx);
                  await _sendRetard(delai, msgCtrl.text.trim());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: sending
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Envoyer la notification',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _sendRetard(int delaiMinutes, String message) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('sendRetardNotification');
      final result = await fn.call({'delaiMinutes': delaiMinutes, 'message': message});
      final notified = (result.data as Map?)?['notified'] as int? ?? 0;
      if (mounted) {
        setState(() => _retardDeclare = true);
        final delaiText = delaiMinutes < 60 ? '$delaiMinutes min' : '${delaiMinutes ~/ 60} h';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            notified > 0
                ? 'Retard de $delaiText signalé — $notified client(s) notifié(s).'
                : 'Retard signalé. Aucun client avec RDV dans les 3h.',
            style: const TextStyle(fontFamily: 'Galey'),
          ),
          backgroundColor: Colors.orange,
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

  // ── A60 — Auto-accès carnet santé à la confirmation du RDV ───────────────────

  Future<void> _autoGrantAccess(Map<String, dynamic> rdv) async {
    final animalId = rdv['animal_id']?.toString();
    final clientUid = rdv['client_uid']?.toString();
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    if (animalId == null || animalId.isEmpty || clientUid == null || proUid == null) return;
    try {
      final supa = Supabase.instance.client;

      // Profil pro actif
      final proProfile = await supa.from('user_profiles')
          .select('id').eq('uid', proUid).eq('is_main', true).maybeSingle();
      final proProfileId = proProfile?['id'] as String?;
      if (proProfileId == null) return;

      // Profil propriétaire depuis animaux_proprietes
      final ownerData = await supa.from('animaux_proprietes')
          .select('profile_id_proprio')
          .eq('animal_id', animalId)
          .maybeSingle();
      final ownerProfileId = ownerData?['profile_id_proprio'] as String?;
      if (ownerProfileId == null) return;

      final permissions = User_Info.catPro == 'veterinaire'
          ? ['read_basic', 'read_health', 'write_health']
          : User_Info.catPro == 'pension'
              ? ['read_basic', 'read_alimentation', 'write_notes']
              : ['read_basic', 'write_notes'];

      await supa.from('animal_access').upsert({
        'animal_id':             animalId,
        'pro_profile_id':        proProfileId,
        'granted_by_profile_id': ownerProfileId,
        'permissions':           permissions,
        'statut':                'active',
        'granted_at':            DateTime.now().toIso8601String(),
      }, onConflict: 'animal_id,pro_profile_id');
    } catch (_) {}
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
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.warning_amber_rounded),
                tooltip: 'Signaler un retard',
                onPressed: _showRetardDialog,
              ),
              if (_retardDeclare)
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ],
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
          : Column(children: [
              if (_aujourdhui.isNotEmpty) _buildAujourdhuiCard(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async { await Future.wait([_loadRdvs(), _loadAujourdhui()]); },
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
              ),
            ]),
    );
  }

  // Agenda dynamique — alerte retard : pour des séances à domicile
  // consécutives et géocodées le même jour, estime si le temps entre les
  // deux (fin de la 1re → début de la 2e) suffit à parcourir la distance à
  // vol d'oiseau (heuristique 30 km/h, pas d'API Directions payante).
  List<String> _travelWarningsToday() {
    final today = DateTime.now();
    final rdvsToday = _rdvs.where((r) {
      final s = r['statut'] as String? ?? '';
      if (s != 'confirme') return false;
      final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal();
      return dh != null && _sameDay(dh, today);
    }).toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['date_heure']?.toString() ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['date_heure']?.toString() ?? '') ?? DateTime(0);
        return da.compareTo(db);
      });

    final warnings = <String>[];
    for (var i = 0; i < rdvsToday.length - 1; i++) {
      final a = rdvsToday[i];
      final b = rdvsToday[i + 1];
      final aLat = (a['lieu_lat'] as num?)?.toDouble();
      final aLng = (a['lieu_lng'] as num?)?.toDouble();
      final bLat = (b['lieu_lat'] as num?)?.toDouble();
      final bLng = (b['lieu_lng'] as num?)?.toDouble();
      if (aLat == null || aLng == null || bLat == null || bLng == null) continue;
      final aDh = DateTime.tryParse(a['date_heure']?.toString() ?? '')?.toLocal();
      final bDh = DateTime.tryParse(b['date_heure']?.toString() ?? '')?.toLocal();
      if (aDh == null || bDh == null) continue;
      final aDuree = (a['duree_minutes'] as num?)?.toInt() ?? 60;
      final gapMin = bDh.difference(aDh.add(Duration(minutes: aDuree))).inMinutes;
      final distKm = GeocodingHelper.distanceKm(aLat, aLng, bLat, bLng);
      final travelMin = (distKm / 30 * 60).ceil(); // 30 km/h à vol d'oiseau
      if (gapMin < travelMin) {
        final bHeure = '${bDh.hour.toString().padLeft(2, "0")}h${bDh.minute.toString().padLeft(2, "0")}';
        warnings.add('Risque de retard pour le RDV de $bHeure : '
            '~${distKm.toStringAsFixed(1)} km à parcourir en $gapMin min seulement.');
      }
    }
    return warnings;
  }

  Widget _buildAujourdhuiCard() {
    final warnings = _travelWarningsToday();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _teal.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📅 Aujourd\'hui (${_aujourdhui.length})',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal)),
        const SizedBox(height: 8),
        ..._aujourdhui.map((e) {
          final dh = DateTime.tryParse(e['date_debut']?.toString() ?? '')?.toLocal();
          final heure = dh != null ? '${dh.hour.toString().padLeft(2, "0")}h${dh.minute.toString().padLeft(2, "0")}' : '';
          final estCollectif = e['type'] == 'cours_collectif';
          final rdvId = e['rdv_id']?.toString();
          final lieu = rdvId != null
              ? (_rdvs.firstWhere((r) => r['id']?.toString() == rdvId,
                  orElse: () => const {})['lieu']?.toString() ?? '')
              : '';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Row(children: [
                Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(color: estCollectif ? const Color(0xFF7B5EA7) : _teal, shape: BoxShape.circle)),
                Text(heure, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12)),
              ]),
              const SizedBox(width: 8),
              Expanded(child: Text(e['titre']?.toString() ?? '',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.black87),
                  overflow: TextOverflow.ellipsis)),
              if (lieu.isNotEmpty) ...[
                const SizedBox(width: 6),
                Icon(Icons.place_outlined, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 2),
                Text(lieu, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis),
              ],
            ]),
          );
        }),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final w in warnings)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(child: Text(w, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5,
                    color: Colors.orange.shade900))),
              ]),
            ),
        ],
      ]),
    );
  }

  // ── AG08 — Créneaux ──────────────────────────────────────────────────────────

  Future<void> _loadCreneaux() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    String pid = User_Info.activeProfileId;
    if (pid.isEmpty && User_Info.availableProfiles.isNotEmpty) {
      final proProfile = User_Info.availableProfiles.firstWhere(
        (p) => p['profile_type'] != 'particulier',
        orElse: () => User_Info.availableProfiles.first,
      );
      pid = proProfile['id']?.toString() ?? '';
    }
    final weekEnd = _weekStart.add(const Duration(days: 6));
    try {
      var creneauxQ = Supabase.instance.client
          .from('creneaux_pro')
          .select()
          .eq('pro_uid', uid)
          .inFilter('statut', ['disponible', 'bloque'])
          .gte('date', _weekStart.toIso8601String().substring(0, 10))
          .lte('date', weekEnd.toIso8601String().substring(0, 10));
      if (pid.isNotEmpty) creneauxQ = creneauxQ.eq('pro_profile_id', pid);
      final rows = await creneauxQ;

      if (!mounted) return;
      setState(() {
        _blockedSlots.clear();
        _slotTypes.clear();
        for (final row in rows) {
          final date = row['date'] as String;
          final heureDebut = row['heure_debut'] as String; // 'HH:MM:SS'
          final hh = heureDebut.substring(0, 2);
          final mm = heureDebut.substring(3, 5);
          final key = '${date}_$hh:$mm';
          _blockedSlots[key] = row['statut'] as String? ?? 'disponible';
          final type = row['type_prestation'] as String?;
          if (type != null) _slotTypes[key] = type;
        }
      });
    } catch (_) {}
  }

  // ── Helpers créneaux ─────────────────────────────────────────────────────────

  TimeOfDay _snapTo15(TimeOfDay t) {
    final mins = ((t.hour * 60 + t.minute) ~/ 15) * 15;
    return TimeOfDay(hour: mins ~/ 60, minute: mins % 60);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  List<({TimeOfDay start, TimeOfDay end, String statut, String? type})> _groupedRanges(String date) {
    final entries = _blockedSlots.entries
        .where((e) => e.key.startsWith('${date}_'))
        .map((e) {
          final tp = e.key.substring(date.length + 1).split(':');
          return (time: TimeOfDay(hour: int.parse(tp[0]), minute: int.parse(tp[1])),
              statut: e.value, type: _slotTypes[e.key]);
        })
        .toList()
      ..sort((a, b) => (a.time.hour * 60 + a.time.minute).compareTo(b.time.hour * 60 + b.time.minute));

    if (entries.isEmpty) return [];
    final ranges = <({TimeOfDay start, TimeOfDay end, String statut, String? type})>[];
    var rStart = entries.first.time;
    var prevMins = rStart.hour * 60 + rStart.minute;
    var curStatut = entries.first.statut;
    var curType = entries.first.type;

    for (var i = 1; i < entries.length; i++) {
      final curMins = entries[i].time.hour * 60 + entries[i].time.minute;
      if (entries[i].statut == curStatut && entries[i].type == curType && curMins == prevMins + 15) {
        prevMins = curMins;
      } else {
        final endM = prevMins + 15;
        ranges.add((start: rStart, end: TimeOfDay(hour: endM ~/ 60, minute: endM % 60), statut: curStatut, type: curType));
        rStart = entries[i].time; prevMins = curMins; curStatut = entries[i].statut; curType = entries[i].type;
      }
    }
    final endM = prevMins + 15;
    ranges.add((start: rStart, end: TimeOfDay(hour: endM ~/ 60, minute: endM % 60), statut: curStatut, type: curType));
    return ranges;
  }

  Future<void> _applyRange(String date, TimeOfDay start, TimeOfDay end, String statut, {String? type}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pid = User_Info.activeProfileId;
    int curMins = start.hour * 60 + start.minute;
    final endMins = end.hour * 60 + end.minute;
    if (curMins >= endMins) return;

    final slots = <Map<String, dynamic>>[];
    while (curMins < endMins) {
      final finMins = curMins + 15;
      final hd = '${(curMins ~/ 60).toString().padLeft(2, '0')}:${(curMins % 60).toString().padLeft(2, '0')}:00';
      final hf = '${(finMins ~/ 60).toString().padLeft(2, '0')}:${(finMins % 60).toString().padLeft(2, '0')}:00';
      final key = '${date}_${(curMins ~/ 60).toString().padLeft(2, '0')}:${(curMins % 60).toString().padLeft(2, '0')}';
      if (mounted) setState(() {
        _blockedSlots[key] = statut;
        if (type != null) { _slotTypes[key] = type; } else { _slotTypes.remove(key); }
      });
      slots.add({'pro_uid': uid, 'pro_profile_id': pid, 'date': date,
          'heure_debut': hd, 'heure_fin': hf, 'statut': statut, 'type_prestation': type});
      curMins = finMins;
    }
    try {
      await Supabase.instance.client.from('creneaux_pro')
          .upsert(slots, onConflict: 'pro_uid,pro_profile_id,date,heure_debut');
    } catch (e) {
      final keys = slots.map((s) {
        final hd = s['heure_debut'] as String;
        return '${date}_${hd.substring(0, 5)}';
      });
      if (mounted) setState(() { for (final k in keys) { _blockedSlots.remove(k); _slotTypes.remove(k); } });
      if (mounted) _showErr(e);
    }
  }

  Future<void> _deleteRange(String date, TimeOfDay start, TimeOfDay end) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pid = User_Info.activeProfileId;
    int curMins = start.hour * 60 + start.minute;
    final endMins = end.hour * 60 + end.minute;
    final hdList = <String>[];
    final keyList = <String>[];
    while (curMins < endMins) {
      hdList.add('${(curMins ~/ 60).toString().padLeft(2, '0')}:${(curMins % 60).toString().padLeft(2, '0')}:00');
      keyList.add('${date}_${(curMins ~/ 60).toString().padLeft(2, '0')}:${(curMins % 60).toString().padLeft(2, '0')}');
      curMins += 15;
    }
    if (mounted) setState(() { for (final k in keyList) { _blockedSlots.remove(k); _slotTypes.remove(k); } });
    try {
      await Supabase.instance.client.from('creneaux_pro').delete()
          .eq('pro_uid', uid).eq('pro_profile_id', pid).eq('date', date)
          .inFilter('heure_debut', hdList);
    } catch (e) { if (mounted) _showErr(e); }
  }

  void _showErr(dynamic e) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
    backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
  ));

  Future<void> _showRangeDialog(String dateStr) async {
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime   = const TimeOfDay(hour: 10, minute: 0);
    String statut = 'disponible';
    String? type; // 'individuel' / 'collectif' / null = les deux (éducateur uniquement)

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> pickTime(bool isStart) async {
            final picked = await showTimePicker(
              context: context, // use outer context for safe navigation
              initialTime: isStart ? startTime : endTime,
              builder: (c, child) => Theme(
                data: ThemeData.light().copyWith(
                    colorScheme: const ColorScheme.light(primary: _teal)),
                child: child!,
              ),
            );
            if (picked == null) return;
            final snapped = _snapTo15(picked);
            setS(() {
              if (isStart) {
                startTime = snapped;
                final sm = snapped.hour * 60 + snapped.minute;
                final em = endTime.hour * 60 + endTime.minute;
                if (em <= sm) {
                  final nm = sm + 60;
                  endTime = TimeOfDay(hour: (nm ~/ 60).clamp(0, 23), minute: nm % 60);
                }
              } else {
                endTime = snapped;
              }
            });
          }

          Widget timeCard(String label, TimeOfDay t, bool isStart) => GestureDetector(
            onTap: () => pickTime(isStart),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(children: [
                Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(_fmtTime(t),
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 24)),
              ]),
            ),
          );

          final isDisp = statut == 'disponible';
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Nouvelle plage', style: TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              // Mode
              Row(children: [
                for (final m in [('disponible', 'Disponible', const Color(0xFF6E9E57)),
                                 ('bloque', 'Bloqué', const Color(0xFFFF9800))])
                  Expanded(child: Padding(
                    padding: EdgeInsets.only(right: m.$1 == 'disponible' ? 6 : 0),
                    child: GestureDetector(
                      onTap: () => setS(() => statut = m.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: statut == m.$1 ? m.$3.withValues(alpha: 0.12) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: statut == m.$1 ? m.$3 : Colors.grey.shade300,
                              width: statut == m.$1 ? 2 : 1),
                        ),
                        child: Center(child: Text(m.$2, style: TextStyle(
                            fontFamily: 'Galey', fontWeight: FontWeight.w600,
                            color: statut == m.$1 ? m.$3 : Colors.grey.shade500))),
                      ),
                    ),
                  )),
              ]),
              const SizedBox(height: 16),
              // Time pickers
              Row(children: [
                Expanded(child: timeCard('De', startTime, true)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text('→', style: TextStyle(fontSize: 22, color: Colors.grey))),
                Expanded(child: timeCard('À', endTime, false)),
              ]),
              // Type de prestation (éducateur/comportementaliste uniquement)
              if (User_Info.catPro == 'education' && isDisp) ...[
                const SizedBox(height: 16),
                const Align(alignment: Alignment.centerLeft,
                    child: Text('Réservé à', style: TextStyle(
                        fontFamily: 'Galey', fontSize: 11, color: Colors.grey,
                        fontWeight: FontWeight.w600))),
                const SizedBox(height: 8),
                Row(children: [
                  for (final t in [('individuel', '🎓 Individuel'), ('collectif', '👥 Collectif'), (null, 'Les deux')])
                    Expanded(child: Padding(
                      padding: EdgeInsets.only(right: t.$1 == null ? 0 : 6),
                      child: GestureDetector(
                        onTap: () => setS(() => type = t.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: type == t.$1 ? const Color(0x187B5EA7) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: type == t.$1 ? const Color(0xFF7B5EA7) : Colors.grey.shade300,
                                width: type == t.$1 ? 2 : 1),
                          ),
                          child: Center(child: Text(t.$2, textAlign: TextAlign.center, style: TextStyle(
                              fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                              color: type == t.$1 ? const Color(0xFF7B5EA7) : Colors.grey.shade500))),
                        ),
                      ),
                    )),
                ]),
              ],
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDisp ? const Color(0xFF6E9E57) : const Color(0xFFFF9800),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Appliquer', style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w600,
                    fontSize: 15, color: Colors.white)),
              )),
            ]),
          );
        },
      ),
    );
    if (confirmed == true && mounted) {
      await _applyRange(dateStr, startTime, endTime, statut, type: statut == 'disponible' ? type : null);
    }
  }

  Future<void> _confirmDeleteRange(String date,
      ({TimeOfDay start, TimeOfDay end, String statut, String? type}) r) async {
    final label = '${_fmtTime(r.start)} — ${_fmtTime(r.end)}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer la plage ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        content: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.white, fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteRange(date, r.start, r.end);
  }

  Future<void> _replicateWeek() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final pid = User_Info.activeProfileId;
    final weekSlots = _blockedSlots.entries.where((e) => e.value == 'disponible').toList();
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

    // Dialog : choisir la durée de réplication
    String _choice = '4semaines';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Répliquer les créneaux',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${weekSlots.length} créneau(x) de cette semaine à répliquer.',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            for (final opt in [
              ('4semaines',  '4 semaines suivantes'),
              ('annee',      "Jusqu'à la fin de l'année"),
              ('perso',      'Date personnalisée…'),
            ])
              RadioListTile<String>(
                dense: true,
                activeColor: _teal,
                value: opt.$1,
                groupValue: _choice,
                title: Text(opt.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                onChanged: (v) => setS(() => _choice = v!),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text('Répliquer',
                    style: TextStyle(color: _teal, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    // Résoudre la date de fin
    DateTime endDate;
    if (_choice == 'annee') {
      endDate = DateTime(_weekStart.year, 12, 31);
    } else if (_choice == 'perso') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _weekStart.add(const Duration(days: 28)),
        firstDate: _weekStart.add(const Duration(days: 7)),
        lastDate: DateTime(_weekStart.year + 1, 12, 31),
        helpText: 'Répliquer jusqu\'au…',
        builder: (ctx, child) => Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: _teal)),
          child: child!,
        ),
      );
      if (picked == null || !mounted) return;
      endDate = picked;
    } else {
      endDate = _weekStart.add(const Duration(days: 28));
    }

    try {
      final supa = Supabase.instance.client;
      final rows = <Map<String, dynamic>>[];

      // Utilise la date UTC pure pour éviter les décalages timezone
      final weekStartUtc = DateTime.utc(_weekStart.year, _weekStart.month, _weekStart.day);
      final endDateUtc = DateTime.utc(endDate.year, endDate.month, endDate.day);

      for (DateTime target = weekStartUtc.add(const Duration(days: 7));
           !target.isAfter(endDateUtc);
           target = target.add(const Duration(days: 7))) {
        for (final entry in weekSlots) {
          final parts = entry.key.split('_');
          if (parts.length < 2) continue;
          final dateParts = parts[0].split('-');
          if (dateParts.length < 3) continue;
          final origUtc = DateTime.utc(
            int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]));
          final timeParts = parts[1].split(':');
          if (timeParts.length < 2) continue;
          final startMins = (int.tryParse(timeParts[0]) ?? 0) * 60 + (int.tryParse(timeParts[1]) ?? 0);
          final finMins = startMins + 15;

          final diff = origUtc.difference(weekStartUtc).inDays;
          final targetDate = target.add(Duration(days: diff));
          final dateStr = '${targetDate.year}-${targetDate.month.toString().padLeft(2,'0')}-${targetDate.day.toString().padLeft(2,'0')}';
          final heureDebut = '${(startMins ~/ 60).toString().padLeft(2, '0')}:${(startMins % 60).toString().padLeft(2, '0')}:00';
          final heureFin = '${(finMins ~/ 60).toString().padLeft(2, '0')}:${(finMins % 60).toString().padLeft(2, '0')}:00';

          rows.add({
            'pro_uid':        uid,
            'pro_profile_id': pid,
            'date':           dateStr,
            'heure_debut':    heureDebut,
            'heure_fin':      heureFin,
            'statut':         'disponible',
          });
        }
      }

      if (rows.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun créneau à ajouter.', style: TextStyle(fontFamily: 'Galey')),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }

      // Dédoublonnage par (date, heure_debut) avant upsert
      final seen = <String>{};
      final deduped = rows.where((r) =>
          seen.add('${r["date"]}_${r["heure_debut"]}')
      ).toList();

      await supa.from('creneaux_pro').upsert(deduped, onConflict: 'pro_uid,pro_profile_id,date,heure_debut');

      if (mounted) {
        final nbSemaines = deduped.length ~/ weekSlots.length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${deduped.length} créneau(x) ajoutés sur $nbSemaines semaine(s).',
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
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _replicateWeek,
            icon: const Icon(Icons.repeat, size: 16),
            label: const Text('Répliquer…', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _teal, side: const BorderSide(color: _teal),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(
            onPressed: () => _showRangeDialog(dateStr),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Ajouter une plage', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          )),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: Builder(builder: (ctx) {
        final rdvsJour = _rdvs.where((r) {
          final s = r['statut'] as String? ?? '';
          if (s != 'confirme' && s != 'demande') return false;
          final dh = DateTime.tryParse(r['date_heure'] ?? '')?.toLocal();
          return dh != null && _sameDay(dh, selectedDay);
        }).toList();
        final ranges = _groupedRanges(dateStr);

        if (rdvsJour.isEmpty && ranges.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.schedule_outlined, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text('Aucun créneau ce jour',
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade400)),
            const SizedBox(height: 6),
            Text('Appuyez sur « Ajouter une plage »',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
          ]));
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 16), children: [
          if (rdvsJour.isNotEmpty) ...[
            Text('Rendez-vous', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w600, fontSize: 12,
                color: Colors.grey.shade500, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            for (final rdv in rdvsJour) Builder(builder: (_) {
              final dh = DateTime.tryParse(rdv['date_heure'] ?? '')?.toLocal();
              final dur = (rdv['duree_minutes'] as num?)?.toInt() ?? 60;
              final endDh = dh?.add(Duration(minutes: dur));
              final label = dh != null
                  ? '${dh.hour.toString().padLeft(2,'0')}:${dh.minute.toString().padLeft(2,'0')}'
                    ' — ${endDh!.hour.toString().padLeft(2,'0')}:${endDh.minute.toString().padLeft(2,'0')}'
                  : '—';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: const Color(0x1A0C5C6C),
                    borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal)),
                child: Row(children: [
                  const Icon(Icons.event, size: 16, color: _teal),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w600, fontSize: 14, color: _teal)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(rdv['motif']?.toString() ?? '',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0x260C5C6C),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('RDV', style: TextStyle(fontFamily: 'Galey',
                        fontSize: 11, fontWeight: FontWeight.w600, color: _teal)),
                  ),
                ]),
              );
            }),
            const SizedBox(height: 12),
          ],
          if (ranges.isNotEmpty) ...[
            Text('Créneaux', style: TextStyle(fontFamily: 'Galey',
                fontWeight: FontWeight.w600, fontSize: 12,
                color: Colors.grey.shade500, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            for (final r in ranges)
              GestureDetector(
                onTap: () => _confirmDeleteRange(dateStr, r),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: r.statut == 'disponible'
                        ? const Color(0xFF6E9E57).withValues(alpha: 0.10)
                        : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: r.statut == 'disponible'
                        ? const Color(0xFF6E9E57) : const Color(0xFFFF9800)),
                  ),
                  child: Row(children: [
                    Icon(r.statut == 'disponible'
                        ? Icons.check_circle_outline : Icons.block_outlined,
                        size: 16,
                        color: r.statut == 'disponible'
                            ? const Color(0xFF4A7A32) : const Color(0xFFE65100)),
                    const SizedBox(width: 8),
                    Text('${_fmtTime(r.start)} — ${_fmtTime(r.end)}',
                        style: TextStyle(fontFamily: 'Galey',
                            fontWeight: FontWeight.w600, fontSize: 14,
                            color: r.statut == 'disponible'
                                ? const Color(0xFF4A7A32) : const Color(0xFFE65100))),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: r.statut == 'disponible'
                            ? const Color(0xFF6E9E57).withValues(alpha: 0.15)
                            : const Color(0x33FF9800),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(r.statut == 'disponible' ? 'Disponible' : 'Bloqué',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: r.statut == 'disponible'
                                  ? const Color(0xFF4A7A32) : const Color(0xFFE65100))),
                    ),
                    if (r.type != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x1A7B5EA7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(r.type == 'individuel' ? '🎓 Individuel' : '👥 Collectif',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                                fontWeight: FontWeight.w600, color: Color(0xFF7B5EA7))),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Icon(Icons.delete_outline, size: 16, color: Colors.grey.shade400),
                  ]),
                ),
              ),
          ],
        ]);
      })),
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
          onModifier: showCancel ? () => _showModifierDialog(rdv) : null,
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
                  builder: (_) => AnimalFichePage(
                    animalId: animalId,
                    readOnly: true,
                    vetMode: true,
                    rdvId: rdv['id']?.toString(),
                  )))
              : null,
          // CR / Ordonnance est un flux médical (vétérinaire, pension…) — sans
          // objet pour l'éducateur, qui a son propre rapport de séance
          // (lié à l'animal, voir animal_fiche.dart / education_devis_page.dart).
          onCompteRendu: (showProTools && User_Info.catPro != 'education')
              ? () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CompteRenduPage(
                    rdv: rdv,
                    clientName: rdv['_client_name']?.toString() ?? 'Client',
                    categoryColor: _teal,
                    isPension: User_Info.catPro == 'pension',
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
  final VoidCallback? onModifier;

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
    this.onModifier,
  });

  @override
  Widget build(BuildContext context) {
    final dateHeure = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
    final clientName = rdv['_client_name']?.toString() ?? 'Client';
    final animalNom = rdv['_animal_nom']?.toString() ?? '';
    final motif = rdv['motif']?.toString() ?? '';
    final lieu = rdv['lieu']?.toString() ?? '';
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

              // Motif + lieu + durée
              if (motif.isNotEmpty)
                Text(motif, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF555F6A))),
              if (lieu.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 14, color: Color(0xFF0C5C6C)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(lieu, style: const TextStyle(fontFamily: 'Galey',
                      fontSize: 13, color: Color(0xFF0C5C6C)))),
                ]),
              ],
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
                if (onModifier != null)
                  IconButton(
                    onPressed: onModifier,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 20, color: Color(0xFF0C5C6C)),
                    tooltip: 'Modifier le RDV',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                const SizedBox(width: 4),
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
    'confirme'            => const Color(0xFF0C5C6C),
    'termine'             => const Color(0xFF6E9E57),
    'annule'              => Colors.red,
    'no_show'             => Colors.orange,
    'contre_proposition'  => const Color(0xFF1565C0),
    _                     => const Color(0xFFF59E0B),
  };

  String _statutLabel(String s) => switch (s) {
    'confirme'            => 'Confirmé',
    'termine'             => 'Terminé',
    'annule'              => 'Annulé',
    'no_show'             => 'Non présenté',
    'contre_proposition'  => 'Modif. demandée',
    _                     => 'En attente',
  };

  String _formatDateTime(DateTime d) {
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const mois = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'août', 'sep', 'oct', 'nov', 'déc'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]} — $h:$m';
  }
}
