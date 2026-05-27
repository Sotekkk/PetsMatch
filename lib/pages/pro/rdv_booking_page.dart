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
  int _dureeMinutes = 30;
  String? _selectedAnimalId;
  final _motifCtrl = TextEditingController();

  bool _loadingAnimaux = true;
  bool _saving = false;
  List<Map<String, dynamic>> _animaux = [];

  @override
  void initState() {
    super.initState();
    _loadAnimaux();
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
        if (_selectedAnimalId != null) 'animal_id': _selectedAnimalId,
        'date_heure':     dateHeure.toIso8601String(),
        'duree_minutes':  _dureeMinutes,
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

                  // Durée
                  _sectionTitle('Durée estimée'),
                  const SizedBox(height: 8),
                  _buildDureeSelector(),
                  const SizedBox(height: 20),

                  // Animal (optionnel)
                  if (_animaux.isNotEmpty) ...[
                    _sectionTitle('Animal concerné (optionnel)'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4E7E2)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedAnimalId,
                          isExpanded: true,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1E2025)),
                          hint: const Text('Aucun animal sélectionné',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey)),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Aucun', style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
                            ),
                            ..._animaux.map((a) => DropdownMenuItem<String?>(
                              value: a['id'].toString(),
                              child: Text(
                                '${a['nom'] ?? 'Sans nom'} (${a['espece'] ?? ''})',
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                              ),
                            )),
                          ],
                          onChanged: (v) => setState(() => _selectedAnimalId = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

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
    return Column(children: [
      // Heures
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(13, (i) => i + 8).map((h) {
            final sel = _selectedHour == h;
            return GestureDetector(
              onTap: () => setState(() => _selectedHour = h),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? widget.categoryColor : Colors.white,
                  border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$h h',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                      color: sel ? Colors.white : const Color(0xFF1E2025),
                      fontWeight: sel ? FontWeight.w700 : FontWeight.normal),
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
        return GestureDetector(
          onTap: () => setState(() => _selectedMinute = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? widget.categoryColor : Colors.white,
              border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              m == 0 ? '00 min' : '$m min',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: sel ? Colors.white : const Color(0xFF1E2025),
                  fontWeight: sel ? FontWeight.w700 : FontWeight.normal),
            ),
          ),
        );
      }).toList()),
    ]);
  }

  Widget _buildDureeSelector() {
    return Row(children: [30, 60, 90].map((d) {
      final sel = _dureeMinutes == d;
      return GestureDetector(
        onTap: () => setState(() => _dureeMinutes = d),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: sel ? widget.categoryColor : Colors.white,
            border: Border.all(color: sel ? widget.categoryColor : const Color(0xFFE4E7E2)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            d < 60 ? '$d min' : '${d ~/ 60} h',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: sel ? Colors.white : const Color(0xFF1E2025),
                fontWeight: sel ? FontWeight.w700 : FontWeight.normal),
          ),
        ),
      );
    }).toList());
  }

  String _formatDate(DateTime d) {
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const mois = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'août', 'sep', 'oct', 'nov', 'déc'];
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]} ${d.year}';
  }
}
