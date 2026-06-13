import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _orange = Color(0xFFEF6C00);

const _kNiveaux = ['facile', 'moyen', 'difficile'];

class PromenadePage extends StatefulWidget {
  const PromenadePage({super.key});

  @override
  State<PromenadePage> createState() => _PromenadesPageState();
}

class _PromenadesPageState extends State<PromenadePage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _promenades = [];
  Set<String> _mesParticipations = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final promData = await _supa
          .from('promenades')
          .select()
          .eq('statut', 'ouvert')
          .gte('date_heure', DateTime.now().toIso8601String())
          .order('date_heure');

      Set<String> participations = {};
      if (_uid.isNotEmpty) {
        final partData = await _supa
            .from('promenades_participants')
            .select('promenade_id')
            .eq('user_uid', _uid);
        participations = Set<String>.from(
            (partData as List).map((e) => e['promenade_id'].toString()));
      }

      if (mounted) {
        setState(() {
          _promenades = List<Map<String, dynamic>>.from(promData);
          _mesParticipations = participations;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleParticipation(String id) async {
    if (_uid.isEmpty) return;
    final dejaDedans = _mesParticipations.contains(id);
    setState(() {
      if (dejaDedans) {
        _mesParticipations.remove(id);
      } else {
        _mesParticipations.add(id);
      }
    });
    try {
      if (dejaDedans) {
        await _supa
            .from('promenades_participants')
            .delete()
            .eq('promenade_id', id)
            .eq('user_uid', _uid);
      } else {
        await _supa.from('promenades_participants').insert({
          'promenade_id': id,
          'user_uid': _uid,
          'rejoint_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {
      setState(() {
        if (dejaDedans) {
          _mesParticipations.add(id);
        } else {
          _mesParticipations.remove(id);
        }
      });
    }
  }

  Future<void> _openCreation() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreatePromenadesSheet(),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Promenades collectives',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: _uid.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: _orange,
              onPressed: _openCreation,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : _promenades.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _orange,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _promenades.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = _promenades[i];
                      final id = p['id'].toString();
                      return _PromenadesCard(
                        promenade: p,
                        estParticipant: _mesParticipations.contains(id),
                        onToggle: _uid.isNotEmpty ? () => _toggleParticipation(id) : null,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _empty() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.directions_walk_outlined, size: 72, color: Color(0xFFCCCCCC)),
          SizedBox(height: 16),
          Text('Aucune promenade à venir',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFFAAAAAA))),
          SizedBox(height: 8),
          Text('Organisez la première !',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ]),
      );
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _PromenadesCard extends StatelessWidget {
  final Map<String, dynamic> promenade;
  final bool estParticipant;
  final VoidCallback? onToggle;

  const _PromenadesCard(
      {required this.promenade, required this.estParticipant, this.onToggle});

  static Color _niveauColor(String n) => switch (n) {
        'facile' => const Color(0xFF6E9E57),
        'moyen' => const Color(0xFFEF6C00),
        'difficile' => Colors.red,
        _ => Colors.grey,
      };

  static String _fmtDate(String iso) {
    try {
      return DateFormat('dd/MM/yyyy · HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titre = promenade['titre']?.toString() ?? 'Promenade';
    final lieu = promenade['lieu_rdv']?.toString() ?? '';
    final dateHeure = promenade['date_heure']?.toString() ?? '';
    final niveau = promenade['niveau']?.toString() ?? 'facile';
    final duree = (promenade['duree_minutes'] as num?)?.toInt();
    final distance = (promenade['distance_km'] as num?)?.toDouble();
    final desc = promenade['description']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(titre,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF1E2025))),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _niveauColor(niveau).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(niveau,
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 11,
                      color: _niveauColor(niveau),
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          if (dateHeure.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.schedule_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Text(_fmtDate(dateHeure),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            ]),
          ],
          if (lieu.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Expanded(
                child: Text(lieu,
                    style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ],
          if (duree != null || distance != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              if (duree != null) ...[
                const Icon(Icons.timer_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${duree}min',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ],
              if (duree != null && distance != null) const SizedBox(width: 12),
              if (distance != null) ...[
                const Icon(Icons.straighten, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${distance.toStringAsFixed(1)} km',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ],
            ]),
          ],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc,
                style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (onToggle != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: estParticipant ? _orange : Colors.transparent,
                    border: Border.all(color: _orange),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    estParticipant ? 'Inscrit ✓' : 'Rejoindre',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: estParticipant ? Colors.white : _orange),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─── Sheet création ───────────────────────────────────────────────────────────

class _CreatePromenadesSheet extends StatefulWidget {
  const _CreatePromenadesSheet();

  @override
  State<_CreatePromenadesSheet> createState() => _CreatePromenadesSheetState();
}

class _CreatePromenadesSheetState extends State<_CreatePromenadesSheet> {
  final _formKey = GlobalKey<FormState>();
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _titre = '';
  String _lieuRdv = '';
  String _description = '';
  String _niveau = 'facile';
  DateTime _dateHeure = DateTime.now().add(const Duration(days: 3));
  int _dureeMinutes = 60;
  bool _saving = false;

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateHeure,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
          data: ThemeData.light()
              .copyWith(colorScheme: const ColorScheme.light(primary: _orange)),
          child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateHeure),
    );
    if (time == null || !mounted) return;
    setState(() => _dateHeure =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      await _supa.from('promenades').insert({
        'organisateur_uid': _uid,
        'titre': _titre,
        'lieu_rdv': _lieuRdv,
        'description': _description,
        'niveau': _niveau,
        'date_heure': _dateHeure.toIso8601String(),
        'duree_minutes': _dureeMinutes,
        'statut': 'ouvert',
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(
                      child: Text('Organiser une promenade',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 18))),
                  IconButton(
                      icon: const Icon(Icons.close, size: 22, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                ]),
                const SizedBox(height: 20),

                _lbl('Titre *'),
                TextFormField(
                  decoration: _dec('Ex : Balade au bord du lac'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _titre = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                _lbl('Lieu de rendez-vous *'),
                TextFormField(
                  decoration: _dec('Adresse, parking, point de repère…'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _lieuRdv = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                _lbl('Date et heure *'),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined, size: 16, color: _orange),
                      const SizedBox(width: 10),
                      Text(DateFormat('dd/MM/yyyy · HH:mm').format(_dateHeure),
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('Niveau'),
                    InputDecorator(
                      decoration: _dec(''),
                      child: DropdownButton<String>(
                        value: _niveau,
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: _kNiveaux
                            .map((n) => DropdownMenuItem(
                                value: n,
                                child: Text(n,
                                    style: const TextStyle(
                                        fontFamily: 'Galey', fontSize: 14))))
                            .toList(),
                        onChanged: (v) => setState(() => _niveau = v ?? 'facile'),
                      ),
                    ),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('Durée (min)'),
                    TextFormField(
                      initialValue: '60',
                      decoration: _dec('60'),
                      keyboardType: TextInputType.number,
                      onSaved: (v) => _dureeMinutes = int.tryParse(v?.trim() ?? '') ?? 60,
                    ),
                  ])),
                ]),
                const SizedBox(height: 12),

                _lbl('Description'),
                TextFormField(
                  decoration: _dec('Parcours, espèces bienvenues, équipement…'),
                  maxLines: 3,
                  onSaved: (v) => _description = v?.trim() ?? '',
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: _orange,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Publier la promenade',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF6F767B))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _orange, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      );
}
