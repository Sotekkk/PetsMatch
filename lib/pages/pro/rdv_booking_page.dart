import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RdvBookingPage extends StatefulWidget {
  final String proUid;
  final String proName;
  final Color categoryColor;

  const RdvBookingPage({
    super.key,
    required this.proUid,
    required this.proName,
    required this.categoryColor,
  });

  @override
  State<RdvBookingPage> createState() => _RdvBookingPageState();
}

class _RdvBookingPageState extends State<RdvBookingPage> {
  static const _bg = Color(0xFFF8F8F8);

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  int _selectedHour = 10;
  int _selectedMinute = 0;
  String? _selectedAnimalId;
  final _motifCtrl = TextEditingController();

  bool _loadingAnimaux = true;
  bool _saving = false;
  List<Map<String, dynamic>> _animaux = [];
  List<Map<String, dynamic>> _proRdvs = [];

  @override
  void initState() {
    super.initState();
    _loadAnimaux();
    _loadProRdvs();
  }

  @override
  void dispose() {
    _motifCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAnimaux() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loadingAnimaux = false); return; }
    try {
      final rows = await Supabase.instance.client
          .from('animaux')
          .select('id, nom, espece')
          .eq('uid_eleveur', uid)
          .order('nom');
      if (mounted) {
        setState(() {
          _animaux = List<Map<String, dynamic>>.from(rows);
          _loadingAnimaux = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAnimaux = false);
    }
  }

  Future<void> _loadProRdvs() async {
    try {
      final rows = await Supabase.instance.client
          .from('rdv')
          .select('date_heure, duree_minutes')
          .eq('pro_uid', widget.proUid)
          .eq('statut', 'confirme')
          .gte('date_heure', DateTime.now().toIso8601String());
      if (mounted) setState(() => _proRdvs = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  bool _isBusy(int h, int m) {
    final selDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    for (final r in _proRdvs) {
      final dh = DateTime.tryParse(r['date_heure'] ?? '')?.toLocal();
      if (dh == null) continue;
      if (dh.year != selDay.year || dh.month != selDay.month || dh.day != selDay.day) continue;
      final dur = (r['duree_minutes'] as num?)?.toInt() ?? 30;
      final rdvStart = dh.hour * 60 + dh.minute;
      final rdvEnd = rdvStart + dur;
      final proposed = h * 60 + m;
      if (proposed >= rdvStart && proposed < rdvEnd) return true;
    }
    return false;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: widget.categoryColor),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_isBusy(_selectedHour, _selectedMinute)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ce créneau est déjà réservé. Choisissez un autre horaire.', style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (_motifCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Veuillez indiquer le motif du rendez-vous', style: TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final dateHeure = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day,
        _selectedHour, _selectedMinute,
      ).toUtc();

      await Supabase.instance.client.from('rdv').insert({
        'pro_uid':        widget.proUid,
        'client_uid':     uid,
        if (_selectedAnimalId != null) 'animal_id': int.tryParse(_selectedAnimalId!) ?? _selectedAnimalId,
        'date_heure':     dateHeure.toIso8601String(),
        'motif':          _motifCtrl.text.trim(),
        'statut':         'demande',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Demande de RDV envoyée !', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: widget.categoryColor,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: widget.categoryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Prendre un RDV',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
        ),
      ),
      body: _loadingAnimaux
          ? Center(child: CircularProgressIndicator(color: widget.categoryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pro name banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: widget.categoryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.categoryColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(Icons.person_outlined, color: widget.categoryColor, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        widget.proName,
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 15, color: widget.categoryColor),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Date
                  _sectionTitle('Date du rendez-vous'),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4E7E2)),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined, color: widget.categoryColor, size: 18),
                        const SizedBox(width: 12),
                        Text(
                          _formatDate(_selectedDate),
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Heure
                  _sectionTitle('Heure'),
                  const SizedBox(height: 8),
                  _buildTimeSelector(),
                  const SizedBox(height: 20),

                  // Animal
                  _sectionTitle('Pour quel animal ?'),
                  const SizedBox(height: 8),
                  if (_loadingAnimaux)
                    const Center(child: SizedBox(height: 24, width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                  else if (_animaux.isEmpty)
                    Text('Aucun animal enregistré dans votre élevage.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _AnimalChip(
                          label: 'Aucun',
                          icon: Icons.block_outlined,
                          selected: _selectedAnimalId == null,
                          color: widget.categoryColor,
                          onTap: () => setState(() => _selectedAnimalId = null),
                        ),
                        ..._animaux.map((a) => _AnimalChip(
                          label: a['nom']?.toString() ?? 'Sans nom',
                          subtitle: a['espece']?.toString() ?? '',
                          icon: Icons.pets,
                          selected: _selectedAnimalId == a['id'].toString(),
                          color: widget.categoryColor,
                          onTap: () => setState(() => _selectedAnimalId = a['id'].toString()),
                        )),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // Motif
                  _sectionTitle('Motif du rendez-vous *'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _motifCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ex : Vaccination annuelle, bilan de santé, consultation…',
                      hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: widget.categoryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Submit
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.categoryColor,
                        foregroundColor: Colors.white,
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
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Le professionnel confirmera votre rendez-vous.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
        fontSize: 13, color: Color(0xFF1E2025)),
  );

  Widget _buildTimeSelector() {
    final busyWarning = _isBusy(_selectedHour, _selectedMinute);
    return Column(children: [
      // Heures
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
                  color: busy
                      ? const Color(0xFFF0F0F0)
                      : sel ? widget.categoryColor : Colors.white,
                  border: Border.all(
                    color: busy
                        ? const Color(0xFFCCCCCC)
                        : sel ? widget.categoryColor : const Color(0xFFE4E7E2),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  busy ? '$h h ✕' : '$h h',
                  style: TextStyle(
                    fontFamily: 'Galey', fontSize: 13,
                    color: busy ? Colors.grey : sel ? Colors.white : const Color(0xFF1E2025),
                    fontWeight: sel && !busy ? FontWeight.w700 : FontWeight.normal,
                    decoration: busy ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 8),
      // Minutes
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
              color: busy
                  ? const Color(0xFFF0F0F0)
                  : sel ? widget.categoryColor : Colors.white,
              border: Border.all(
                color: busy
                    ? const Color(0xFFCCCCCC)
                    : sel ? widget.categoryColor : const Color(0xFFE4E7E2),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              m == 0 ? '00 min' : '$m min',
              style: TextStyle(
                fontFamily: 'Galey', fontSize: 13,
                color: busy ? Colors.grey : sel ? Colors.white : const Color(0xFF1E2025),
                fontWeight: sel && !busy ? FontWeight.w700 : FontWeight.normal,
                decoration: busy ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        );
      }).toList()),
      if (busyWarning) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: const Row(children: [
            Icon(Icons.warning_amber_outlined, size: 15, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Ce créneau est déjà réservé. Sélectionnez un autre horaire.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange),
            )),
          ]),
        ),
      ],
    ]);
  }


  String _formatDate(DateTime d) {
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const mois = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'août', 'sep', 'oct', 'nov', 'déc'];
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]} ${d.year}';
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
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
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
          Text(label, style: TextStyle(
            fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF1E2025),
          )),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text('($subtitle)', style: TextStyle(
              fontFamily: 'Galey', fontSize: 11,
              color: selected ? Colors.white.withValues(alpha: 0.75) : Colors.grey.shade500,
            )),
          ],
        ]),
      ),
    );
  }
}
