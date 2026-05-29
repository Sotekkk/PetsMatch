import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _green = Color(0xFF6E9E57);

const _kTypes = [
  'Tous',
  'Exposition / Concours',
  'Salon / Foire',
  'Formation / Atelier',
  'Balade collective',
  'Rassemblement de race',
  'Vente de portée',
  'Autre',
];

class EvenementsPage extends StatefulWidget {
  const EvenementsPage({super.key});

  @override
  State<EvenementsPage> createState() => _EvenementsPageState();
}

class _EvenementsPageState extends State<EvenementsPage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _evenements = [];
  Set<String> _mesInscriptions = {};
  bool _loading = true;
  String _filterType = 'Tous';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final evData = await _supa
          .from('evenements')
          .select()
          .eq('statut', 'publie')
          .gte('date_debut', DateTime.now().toIso8601String())
          .order('date_debut');

      Set<String> inscriptions = {};
      if (_uid.isNotEmpty) {
        final insData = await _supa
            .from('evenements_inscrits')
            .select('evenement_id')
            .eq('user_uid', _uid);
        inscriptions = Set<String>.from(
            (insData as List).map((e) => e['evenement_id'].toString()));
      }

      if (mounted) {
        setState(() {
          _evenements = List<Map<String, dynamic>>.from(evData);
          _mesInscriptions = inscriptions;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleInscription(String evId) async {
    if (_uid.isEmpty) return;
    final estInscrit = _mesInscriptions.contains(evId);
    setState(() {
      if (estInscrit) {
        _mesInscriptions.remove(evId);
      } else {
        _mesInscriptions.add(evId);
      }
    });
    try {
      if (estInscrit) {
        await _supa
            .from('evenements_inscrits')
            .delete()
            .eq('evenement_id', evId)
            .eq('user_uid', _uid);
      } else {
        await _supa.from('evenements_inscrits').insert({
          'evenement_id': evId,
          'user_uid': _uid,
          'inscrit_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {
      // Revert on error
      setState(() {
        if (estInscrit) {
          _mesInscriptions.add(evId);
        } else {
          _mesInscriptions.remove(evId);
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
      builder: (_) => const _CreateEvenementSheet(),
    );
    if (created == true) _load();
  }

  List<Map<String, dynamic>> get _filtered => _filterType == 'Tous'
      ? _evenements
      : _evenements.where((e) => e['type'] == _filterType).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _green,
        title: const Text('Événements',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: _uid.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: _green,
              onPressed: _openCreation,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            itemCount: _kTypes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final t = _kTypes[i];
              final sel = _filterType == t;
              return GestureDetector(
                onTap: () => setState(() => _filterType = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? _green : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? _green : Colors.grey.shade300),
                  ),
                  child: Text(t,
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : Colors.grey.shade700)),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _green))
              : _filtered.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: _green,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final ev = _filtered[i];
                          final id = ev['id'].toString();
                          return _EvenementCard(
                            evenement: ev,
                            estInscrit: _mesInscriptions.contains(id),
                            onToggle: _uid.isNotEmpty ? () => _toggleInscription(id) : null,
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.event_outlined, size: 72, color: Color(0xFFCCCCCC)),
          const SizedBox(height: 16),
          Text(
            _filterType != 'Tous'
                ? 'Aucun événement "$_filterType"'
                : 'Aucun événement à venir',
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFFAAAAAA)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text('Soyez le premier à en créer un !',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ]),
      );
}

// ─── Card événement ───────────────────────────────────────────────────────────

class _EvenementCard extends StatelessWidget {
  final Map<String, dynamic> evenement;
  final bool estInscrit;
  final VoidCallback? onToggle;

  const _EvenementCard(
      {required this.evenement, required this.estInscrit, this.onToggle});

  static String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return DateFormat('dd/MM/yyyy · HH:mm').format(d);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titre = evenement['titre']?.toString() ?? '';
    final type = evenement['type']?.toString() ?? '';
    final dateDebut = evenement['date_debut']?.toString() ?? '';
    final lieu = evenement['lieu']?.toString() ?? '';
    final ville = evenement['ville']?.toString() ?? '';
    final prix = (evenement['prix'] as num?) ?? 0;
    final desc = evenement['description']?.toString() ?? '';
    final localisation = [lieu, ville].where((s) => s.isNotEmpty).join(', ');

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
            if (type.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(type,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 11,
                        color: _green,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
          if (dateDebut.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Text(_fmtDate(dateDebut),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            ]),
          ],
          if (localisation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Expanded(
                child: Text(localisation,
                    style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis),
              ),
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
          const SizedBox(height: 10),
          Row(children: [
            Text(
              prix == 0 ? 'Gratuit' : '${prix.toStringAsFixed(0)} €',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: prix == 0 ? _green : const Color(0xFF1E2025)),
            ),
            const Spacer(),
            if (onToggle != null)
              GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: estInscrit ? _green : Colors.transparent,
                    border: Border.all(color: _green),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    estInscrit ? 'Inscrit ✓' : 'Je participe',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: estInscrit ? Colors.white : _green),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

// ─── Sheet création ───────────────────────────────────────────────────────────

class _CreateEvenementSheet extends StatefulWidget {
  const _CreateEvenementSheet();

  @override
  State<_CreateEvenementSheet> createState() => _CreateEvenementSheetState();
}

class _CreateEvenementSheetState extends State<_CreateEvenementSheet> {
  final _formKey = GlobalKey<FormState>();
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _titre = '';
  String _type = 'Autre';
  String _description = '';
  String _lieu = '';
  String _ville = '';
  DateTime _dateDebut = DateTime.now().add(const Duration(days: 7));
  double _prix = 0;
  bool _saving = false;

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateDebut,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
          data: ThemeData.light()
              .copyWith(colorScheme: const ColorScheme.light(primary: _green)),
          child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateDebut),
    );
    if (time == null || !mounted) return;
    setState(() => _dateDebut =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      await _supa.from('evenements').insert({
        'createur_uid': _uid,
        'titre': _titre,
        'type': _type,
        'description': _description,
        'lieu': _lieu,
        'ville': _ville,
        'date_debut': _dateDebut.toIso8601String(),
        'prix': _prix,
        'statut': 'publie',
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
                      child: Text('Créer un événement',
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
                  decoration: _dec('Ex : Concours d\'agility Lyon'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _titre = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                _lbl('Type *'),
                InputDecorator(
                  decoration: _dec(''),
                  child: DropdownButton<String>(
                    value: _type,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _kTypes
                        .skip(1)
                        .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t,
                                style: const TextStyle(
                                    fontFamily: 'Galey', fontSize: 14))))
                        .toList(),
                    onChanged: (v) => setState(() => _type = v ?? 'Autre'),
                  ),
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
                      const Icon(Icons.calendar_today_outlined, size: 16, color: _green),
                      const SizedBox(width: 10),
                      Text(DateFormat('dd/MM/yyyy · HH:mm').format(_dateDebut),
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
                    _lbl('Lieu'),
                    TextFormField(decoration: _dec('Salle, parc…'), onSaved: (v) => _lieu = v?.trim() ?? ''),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('Ville'),
                    TextFormField(decoration: _dec('Ex : Lyon'), onSaved: (v) => _ville = v?.trim() ?? ''),
                  ])),
                ]),
                const SizedBox(height: 12),

                _lbl('Prix (0 = Gratuit)'),
                TextFormField(
                  decoration: _dec('0'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSaved: (v) => _prix = double.tryParse(v?.trim() ?? '') ?? 0,
                ),
                const SizedBox(height: 12),

                _lbl('Description'),
                TextFormField(
                  decoration: _dec('Programme, infos pratiques…'),
                  maxLines: 3,
                  onSaved: (v) => _description = v?.trim() ?? '',
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Publier l\'événement',
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
            borderSide: const BorderSide(color: _green, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      );
}
