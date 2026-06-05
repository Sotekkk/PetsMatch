import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RdvBookingPage extends StatefulWidget {
  final String proUid;
  final String proName;
  final Color categoryColor;
  final bool isPension;

  const RdvBookingPage({
    super.key,
    required this.proUid,
    required this.proName,
    required this.categoryColor,
    this.isPension = false,
  });

  @override
  State<RdvBookingPage> createState() => _RdvBookingPageState();
}

class _RdvBookingPageState extends State<RdvBookingPage> {
  static const _bg = Color(0xFFF8F8F8);

  // Common
  bool _loadingData = true;
  bool _saving = false;
  List<Map<String, dynamic>> _animaux = [];
  Map<String, dynamic>? _selectedAnimal;
  final _notesCtrl = TextEditingController();

  // Non-pension
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  int _selectedHour = 10;
  int _selectedMinute = 0;
  final _motifCtrl = TextEditingController();
  List<Map<String, dynamic>> _proRdvs = [];
  List<Map<String, dynamic>> _proCreneauxBloques = [];

  // Pension-specific
  List<Map<String, dynamic>> _availableSlots = [];
  List<Map<String, dynamic>> _existingRdvs = [];
  String? _selectedDateKey;    // 'YYYY-MM-DD'
  Map<String, dynamic>? _selectedSlot;
  String? _selectedMotif;
  bool? _premiereVisite;

  static const _pensionMotifs = [
    ('visite',  'Visite de la pension',  Icons.tour_outlined),
    ('arrivee', 'Arrivée de l\'animal',  Icons.login_outlined),
    ('depart',  'Départ de l\'animal',   Icons.logout_outlined),
    ('autre',   'Autre',                 Icons.more_horiz_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _motifCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadAnimaux(),
      if (widget.isPension) _loadPensionData() else _loadProRdvs(),
    ]);
    if (mounted) setState(() => _loadingData = false);
  }

  // ── Animal loading ────────────────────────────────────────────────────────────

  Future<void> _loadAnimaux() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('animaux')
          .select('id, nom, espece')
          .or('uid_eleveur.eq.$uid,uid_proprietaire.eq.$uid')
          .order('nom');
      if (mounted) {
        _animaux = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
  }

  // ── Pension data ──────────────────────────────────────────────────────────────

  Future<void> _loadPensionData() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final results = await Future.wait([
        Supabase.instance.client
            .from('creneaux_pro')
            .select('date, heure_debut, heure_fin')
            .eq('pro_uid', widget.proUid)
            .eq('statut', 'disponible')
            .gte('date', today)
            .order('date')
            .order('heure_debut'),
        Supabase.instance.client
            .from('rdv')
            .select('date_heure, duree_minutes, statut')
            .eq('pro_uid', widget.proUid)
            .inFilter('statut', ['confirme', 'demande'])
            .gte('date_heure', DateTime.now().toIso8601String()),
      ]);

      if (mounted) {
        _availableSlots = (results[0] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _existingRdvs = (results[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
  }

  bool _isSlotTaken(String date, String heureDebut) {
    for (final r in _existingRdvs) {
      final dh = DateTime.tryParse(r['date_heure'] as String? ?? '')?.toLocal();
      if (dh == null) continue;
      final rdvDate = '${dh.year}-${dh.month.toString().padLeft(2, '0')}-${dh.day.toString().padLeft(2, '0')}';
      final rdvHeure = '${dh.hour.toString().padLeft(2, '0')}:${dh.minute.toString().padLeft(2, '0')}';
      if (rdvDate == date && rdvHeure == heureDebut.substring(0, 5)) return true;
    }
    return false;
  }

  Map<String, List<Map<String, dynamic>>> get _slotsByDate {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final s in _availableSlots) {
      final date = s['date'] as String;
      if (!_isSlotTaken(date, s['heure_debut'] as String)) {
        map.putIfAbsent(date, () => []).add(s);
      }
    }
    return map;
  }

  List<String> get _availableDates => _slotsByDate.keys.toList()..sort();

  // ── Non-pension: busy check ───────────────────────────────────────────────────

  Future<void> _loadProRdvs() async {
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('rdv')
            .select('date_heure, duree_minutes, statut')
            .eq('pro_uid', widget.proUid)
            .inFilter('statut', ['confirme', 'demande'])
            .gte('date_heure', DateTime.now().toIso8601String()),
        Supabase.instance.client
            .from('creneaux_pro')
            .select('date, heure_debut, heure_fin')
            .eq('pro_uid', widget.proUid)
            .eq('statut', 'bloque')
            .gte('date', DateTime.now().toIso8601String().substring(0, 10)),
      ]);
      if (mounted) {
        _proRdvs = (results[0] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _proCreneauxBloques = (results[1] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
  }

  bool _isBusy(int h, int m) {
    final selDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final dateStr = _selectedDate.toIso8601String().substring(0, 10);
    for (final c in _proCreneauxBloques) {
      if (c['date'] != dateStr) continue;
      final startH = int.parse((c['heure_debut'] as String).split(':')[0]);
      final endH   = int.parse((c['heure_fin']   as String).split(':')[0]);
      if (h >= startH && h < endH) return true;
    }
    for (final r in _proRdvs) {
      final dh = DateTime.tryParse(r['date_heure'] as String? ?? '')?.toLocal();
      if (dh == null) continue;
      if (dh.year != selDay.year || dh.month != selDay.month || dh.day != selDay.day) continue;
      final dur = (r['duree_minutes'] as num?)?.toInt() ?? 30;
      final rdvStart = dh.hour * 60 + dh.minute;
      final proposed = h * 60 + m;
      if (proposed >= rdvStart && proposed < rdvStart + dur) return true;
    }
    return false;
  }

  // ── Submit ────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (widget.isPension) {
      if (_selectedSlot == null) {
        _snack('Veuillez sélectionner un créneau disponible', color: Colors.orange); return;
      }
      if (_selectedMotif == null) {
        _snack('Veuillez choisir le motif du rendez-vous', color: Colors.orange); return;
      }
      if (_selectedMotif == 'autre' && _notesCtrl.text.trim().isEmpty) {
        _snack('Précisez le motif dans le champ "Autre"', color: Colors.orange); return;
      }
    } else {
      if (_isBusy(_selectedHour, _selectedMinute)) {
        _snack('Ce créneau est déjà réservé.', color: Colors.orange); return;
      }
      if (_motifCtrl.text.trim().isEmpty) {
        _snack('Veuillez indiquer le motif du rendez-vous', color: Colors.orange); return;
      }
    }

    setState(() => _saving = true);
    try {
      final DateTime dateHeure;
      final String motif;

      if (widget.isPension) {
        final slotDate = DateTime.parse(_selectedSlot!['date'] as String);
        final heureDebut = (_selectedSlot!['heure_debut'] as String).split(':');
        dateHeure = DateTime(slotDate.year, slotDate.month, slotDate.day,
            int.parse(heureDebut[0]), int.parse(heureDebut[1])).toUtc();
        motif = _selectedMotif == 'autre'
            ? _notesCtrl.text.trim()
            : _pensionMotifs.firstWhere((m) => m.$1 == _selectedMotif).$2;
      } else {
        dateHeure = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
            _selectedHour, _selectedMinute).toUtc();
        motif = _motifCtrl.text.trim();
      }

      // Explicit int cast for animal_id (bigint column)
      final animalId = _selectedAnimal != null
          ? ((_selectedAnimal!['id'] is int)
              ? _selectedAnimal!['id'] as int
              : int.tryParse(_selectedAnimal!['id'].toString()))
          : null;

      await Supabase.instance.client.from('rdv').insert({
        'pro_uid':    widget.proUid,
        'client_uid': uid,
        if (animalId != null) 'animal_id': animalId,
        'date_heure': dateHeure.toIso8601String(),
        'motif':      motif,
        if (widget.isPension && _premiereVisite != null) 'premiere_visite': _premiereVisite,
        if (widget.isPension && _notesCtrl.text.trim().isNotEmpty && _selectedMotif != 'autre')
          'notes_client': _notesCtrl.text.trim(),
        'statut': 'demande',
      });

      // Notification in-app (cloche) pour la pension
      try {
        final clientName = FirebaseAuth.instance.currentUser?.displayName?.isNotEmpty == true
            ? FirebaseAuth.instance.currentUser!.displayName!
            : 'Un client';
        final dateStr = _formatDate(dateHeure.toLocal());
        await Supabase.instance.client.from('notifications').insert({
          'uid':   widget.proUid,
          'type':  'rdv_demande',
          'title': 'Nouvelle demande de RDV',
          'body':  '$clientName souhaite un RDV le $dateStr — motif : $motif',
          'data':  <String, dynamic>{
            'client_uid': uid,
            if (_selectedAnimal != null) 'animal_nom': _selectedAnimal!['nom']?.toString() ?? '',
          },
          'read':  false,
        });

        // Push FCM via Cloud Function
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('notifyProNewRdv')
            .call({
              'proUid':     widget.proUid,
              'clientName': clientName,
              'dateStr':    dateStr,
              'motif':      motif,
            });
      } catch (_) {}

      if (mounted) {
        _snack('Demande de RDV envoyée !', color: widget.categoryColor);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _snack('Erreur : $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {Color color = Colors.black87}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Galey')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: widget.categoryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Prendre un RDV',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loadingData
          ? Center(child: CircularProgressIndicator(color: widget.categoryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProBanner(),
                  const SizedBox(height: 20),
                  if (widget.isPension) ..._buildPensionFields() else ..._buildStandardFields(),
                  const SizedBox(height: 20),
                  _buildAnimalSection(),
                  const SizedBox(height: 20),
                  _buildNotesSection(),
                  const SizedBox(height: 32),
                  _buildSubmitButton(),
                  const SizedBox(height: 8),
                  Center(child: Text(
                    widget.isPension
                        ? 'La pension vous confirmera l\'heure exacte de votre RDV.'
                        : 'Le professionnel confirmera votre rendez-vous.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildProBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: widget.categoryColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: widget.categoryColor.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      Icon(widget.isPension ? Icons.home_work_outlined : Icons.person_outlined,
          color: widget.categoryColor, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(widget.proName,
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
              fontSize: 15, color: widget.categoryColor))),
    ]),
  );

  // ── Pension fields ────────────────────────────────────────────────────────────

  List<Widget> _buildPensionFields() => [
    // Motif chips
    _sectionTitle('Motif du rendez-vous *'),
    const SizedBox(height: 10),
    Wrap(
      spacing: 8, runSpacing: 8,
      children: _pensionMotifs.map((m) {
        final sel = _selectedMotif == m.$1;
        return GestureDetector(
          onTap: () => setState(() {
            _selectedMotif = m.$1;
            if (m.$1 != 'autre') _notesCtrl.clear();
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? widget.categoryColor : Colors.white,
              border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
              borderRadius: BorderRadius.circular(22),
              boxShadow: sel ? [BoxShadow(color: widget.categoryColor.withValues(alpha: 0.2),
                  blurRadius: 6, offset: const Offset(0, 2))] : [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(m.$3, size: 16, color: sel ? Colors.white : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(m.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : const Color(0xFF1E2025))),
            ]),
          ),
        );
      }).toList(),
    ),
    if (_selectedMotif == 'autre') ...[
      const SizedBox(height: 10),
      TextField(
        controller: _notesCtrl,
        maxLines: 2,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: _inputDecoration('Précisez le motif…'),
      ),
    ],
    const SizedBox(height: 20),

    // Première visite
    _sectionTitle('Avez-vous déjà visité cette pension ?'),
    const SizedBox(height: 10),
    Row(children: [
      for (final v in [(true, 'Première visite'), (false, 'Déjà venu·e')]) ...[
        GestureDetector(
          onTap: () => setState(() => _premiereVisite = v.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _premiereVisite == v.$1 ? widget.categoryColor : Colors.white,
              border: Border.all(color: _premiereVisite == v.$1
                  ? widget.categoryColor : const Color(0xFFE4E7E2)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(v.$2, style: TextStyle(
                fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                color: _premiereVisite == v.$1 ? Colors.white : const Color(0xFF1E2025))),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ]),
    const SizedBox(height: 20),

    // Créneau selector
    _sectionTitle('Choisir un créneau *'),
    const SizedBox(height: 10),
    _buildSlotSelector(),
  ];

  Widget _buildSlotSelector() {
    final dates = _availableDates;
    if (dates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E7E2)),
        ),
        child: Center(child: Column(children: [
          Icon(Icons.event_busy_outlined, size: 36, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text('Aucun créneau disponible pour le moment',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text('Contactez la pension pour plus d\'informations',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
        ])),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Horizontal date chips
        SizedBox(
          height: 68,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: dates.length,
            itemBuilder: (_, i) {
              final dateStr = dates[i];
              final date = DateTime.tryParse(dateStr);
              if (date == null) return const SizedBox.shrink();
              final sel = _selectedDateKey == dateStr;
              final slotsCount = _slotsByDate[dateStr]?.length ?? 0;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedDateKey = dateStr;
                  _selectedSlot = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? widget.categoryColor : Colors.white,
                    border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: sel ? [BoxShadow(color: widget.categoryColor.withValues(alpha: 0.2),
                        blurRadius: 6, offset: const Offset(0, 2))] : [],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_weekdayShort(date),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                            color: sel ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade500)),
                    Text('${date.day}/${date.month}',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : const Color(0xFF1E2025))),
                    Text('$slotsCount crén.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                            color: sel ? Colors.white.withValues(alpha: 0.7) : Colors.grey.shade400)),
                  ]),
                ),
              );
            },
          ),
        ),

        // Slots for selected date
        if (_selectedDateKey != null) ...[
          const SizedBox(height: 14),
          Text(_formatDateLong(DateTime.parse(_selectedDateKey!)),
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 13, color: Color(0xFF1E2025))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: (_slotsByDate[_selectedDateKey!] ?? []).map((slot) {
              final sel = _selectedSlot != null &&
                  _selectedSlot!['date'] == slot['date'] &&
                  _selectedSlot!['heure_debut'] == slot['heure_debut'];
              final debut = (slot['heure_debut'] as String).substring(0, 5);
              final fin   = (slot['heure_fin']   as String).substring(0, 5);
              return GestureDetector(
                onTap: () => setState(() => _selectedSlot = slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: sel ? widget.categoryColor : Colors.white,
                    border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: sel ? [BoxShadow(color: widget.categoryColor.withValues(alpha: 0.2),
                        blurRadius: 6, offset: const Offset(0, 2))] : [],
                  ),
                  child: Text('$debut — $fin',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : const Color(0xFF1E2025))),
                ),
              );
            }).toList(),
          ),
        ] else ...[
          const SizedBox(height: 10),
          Text('Sélectionnez une date pour voir les créneaux disponibles',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
        ],
      ],
    );
  }

  // ── Standard (non-pension) fields ────────────────────────────────────────────

  List<Widget> _buildStandardFields() => [
    _sectionTitle('Date du rendez-vous'),
    const SizedBox(height: 8),
    GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E7E2)),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, color: widget.categoryColor, size: 18),
          const SizedBox(width: 12),
          Text(_formatDate(_selectedDate),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        ]),
      ),
    ),
    const SizedBox(height: 20),
    _sectionTitle('Heure'),
    const SizedBox(height: 8),
    _buildTimeSelector(),
    const SizedBox(height: 20),
    _sectionTitle('Motif du rendez-vous *'),
    const SizedBox(height: 8),
    TextField(
      controller: _motifCtrl,
      maxLines: 3,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
      decoration: _inputDecoration('Décrivez la raison de votre demande de RDV…'),
    ),
  ];

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.light(primary: widget.categoryColor)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Widget _buildTimeSelector() {
    final busyWarning = _isBusy(_selectedHour, _selectedMinute);
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(13, (i) => i + 8).map((h) {
            final sel = _selectedHour == h;
            final busy = _isBusy(h, _selectedMinute);
            return GestureDetector(
              onTap: busy ? null : () => setState(() => _selectedHour = h),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: busy ? const Color(0xFFF0F0F0) : sel ? widget.categoryColor : Colors.white,
                  border: Border.all(color: busy ? const Color(0xFFCCCCCC)
                      : sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(busy ? '$h h ✕' : '$h h',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        color: busy ? Colors.grey : sel ? Colors.white : const Color(0xFF1E2025),
                        fontWeight: sel && !busy ? FontWeight.w700 : FontWeight.normal,
                        decoration: busy ? TextDecoration.lineThrough : null)),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [0, 15, 30, 45].map((m) {
        final sel = _selectedMinute == m;
        final busy = _isBusy(_selectedHour, m);
        return GestureDetector(
          onTap: busy ? null : () => setState(() => _selectedMinute = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: busy ? const Color(0xFFF0F0F0) : sel ? widget.categoryColor : Colors.white,
              border: Border.all(color: busy ? const Color(0xFFCCCCCC)
                  : sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(m == 0 ? '00 min' : '$m min',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    color: busy ? Colors.grey : sel ? Colors.white : const Color(0xFF1E2025),
                    fontWeight: sel && !busy ? FontWeight.w700 : FontWeight.normal,
                    decoration: busy ? TextDecoration.lineThrough : null)),
          ),
        );
      }).toList()),
      if (busyWarning) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: const Row(children: [
            Icon(Icons.warning_amber_outlined, size: 15, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('Ce créneau est déjà réservé.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange))),
          ]),
        ),
      ],
    ]);
  }

  // ── Animal & notes sections ───────────────────────────────────────────────────

  Widget _buildAnimalSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Pour quel animal ?'),
      const SizedBox(height: 8),
      if (_animaux.isEmpty)
        Text('Aucun animal enregistré dans votre profil.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500))
      else
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            _AnimalChip(
              label: 'Aucun', icon: Icons.block_outlined,
              selected: _selectedAnimal == null, color: widget.categoryColor,
              onTap: () => setState(() => _selectedAnimal = null),
            ),
            ..._animaux.map((a) => _AnimalChip(
              label: a['nom']?.toString() ?? 'Sans nom',
              subtitle: a['espece']?.toString() ?? '',
              icon: Icons.pets,
              selected: _selectedAnimal?['id'] == a['id'],
              color: widget.categoryColor,
              onTap: () => setState(() => _selectedAnimal = a),
            )),
          ],
        ),
    ],
  );

  Widget _buildNotesSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(widget.isPension && _selectedMotif != 'autre'
          ? 'Notes (optionnel)' : 'Notes'),
      const SizedBox(height: 8),
      if (widget.isPension && _selectedMotif == 'autre') const SizedBox.shrink()
      else TextField(
        controller: _notesCtrl,
        maxLines: 2,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: _inputDecoration(widget.isPension
            ? 'Informations complémentaires pour la pension…'
            : 'Informations complémentaires…'),
      ),
    ],
  );

  Widget _buildSubmitButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _saving ? null : _submit,
      style: ElevatedButton.styleFrom(
        backgroundColor: widget.categoryColor, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: _saving
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text('Envoyer la demande',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
          fontSize: 13, color: Color(0xFF1E2025)));

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.categoryColor, width: 1.5)),
    contentPadding: const EdgeInsets.all(14),
  );

  String _weekdayShort(DateTime d) {
    const j = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return j[d.weekday - 1];
  }

  String _formatDate(DateTime d) {
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const mois  = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'août', 'sep', 'oct', 'nov', 'déc'];
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]} ${d.year}';
  }

  String _formatDateLong(DateTime d) {
    const jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    const mois  = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
                   'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]}';
  }
}

// ── Animal chip ───────────────────────────────────────────────────────────────

class _AnimalChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _AnimalChip({
    required this.label, required this.icon,
    required this.selected, required this.color, required this.onTap,
    this.subtitle = '',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? color : const Color(0xFFDDDDDD)),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: selected ? Colors.white : Colors.grey.shade500),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF1E2025))),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text('($subtitle)', style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                color: selected ? Colors.white.withValues(alpha: 0.75) : Colors.grey.shade500)),
          ],
        ]),
      ),
    );
  }
}
