import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrePensionPage extends StatefulWidget {
  const RegistrePensionPage({super.key});

  @override
  State<RegistrePensionPage> createState() => _RegistrePensionPageState();
}

class _RegistrePensionPageState extends State<RegistrePensionPage>
    with SingleTickerProviderStateMixin {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _entrees = [];
  bool _loading = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadEntrees();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntrees() async {
    setState(() => _loading = true);
    try {
      final data = await _supa
          .from('pension_entrees')
          .select()
          .eq('pro_uid', _uid)
          .order('date_entree', ascending: false);
      if (mounted) {
        setState(() {
          _entrees = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _marquerSorti(Map<String, dynamic> entree) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    await _supa.from('pension_entrees').update({
      'statut': 'sorti',
      'date_sortie_effective': dateStr,
    }).eq('id', entree['id']);
    final idx = _entrees.indexWhere((e) => e['id'] == entree['id']);
    if (idx != -1 && mounted) {
      setState(() {
        _entrees[idx] = {
          ..._entrees[idx],
          'statut': 'sorti',
          'date_sortie_effective': dateStr,
        };
      });
    }
  }

  Future<void> _openAjout() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PensionEntreeSheet(),
    );
    if (added == true) _loadEntrees();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        title: const Text('Registre pension',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'En pension'), Tab(text: 'Sortis'), Tab(text: 'Tous')],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _teal,
        onPressed: _openAjout,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildList(_entrees.where((e) => e['statut'] == 'en_pension').toList()),
                _buildList(_entrees.where((e) => e['statut'] == 'sorti').toList()),
                _buildList(_entrees),
              ],
            ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.pets, size: 64, color: Color(0xFFCCCCCC)),
          SizedBox(height: 16),
          Text('Aucune entrée',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFFAAAAAA))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadEntrees,
      color: _teal,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _PensionCard(
          entree: items[i],
          onSorti: items[i]['statut'] == 'en_pension' ? () => _marquerSorti(items[i]) : null,
        ),
      ),
    );
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _PensionCard extends StatelessWidget {
  final Map<String, dynamic> entree;
  final VoidCallback? onSorti;

  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  const _PensionCard({required this.entree, this.onSorti});

  static String _fmt(String iso) {
    if (iso.isEmpty) return '';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inPension = entree['statut'] == 'en_pension';
    final nom = entree['animal_nom']?.toString() ?? '';
    final espece = entree['espece']?.toString() ?? '';
    final race = entree['race']?.toString() ?? '';
    final puce = entree['puce']?.toString() ?? '';
    final proprietaire = entree['proprietaire_nom']?.toString() ?? '';
    final contact = entree['proprietaire_contact']?.toString() ?? '';
    final dateEntree = entree['date_entree']?.toString() ?? '';
    final dateSortiePrevue = entree['date_sortie_prevue']?.toString() ?? '';
    final dateSortieEff = entree['date_sortie_effective']?.toString() ?? '';
    final notes = entree['notes']?.toString() ?? '';

    final especeRace = [espece, race].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: inPension ? _teal.withValues(alpha: 0.25) : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(nom,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF1E2025))),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: inPension ? const Color(0xFFE0F2F1) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                inPension ? 'En pension' : 'Sorti',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: inPension ? _teal : Colors.grey.shade600),
              ),
            ),
          ]),
          if (especeRace.isNotEmpty || puce.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [if (especeRace.isNotEmpty) especeRace, if (puce.isNotEmpty) 'Puce : $puce']
                  .join(' — '),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
            ),
          ],
          const Divider(height: 16),
          Row(children: [
            const Icon(Icons.person_outline, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                [
                  if (proprietaire.isNotEmpty) proprietaire,
                  if (contact.isNotEmpty) contact,
                ].join(' · '),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.login_rounded, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text('Entrée : ${_fmt(dateEntree)}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            if (dateSortiePrevue.isNotEmpty) ...[
              const SizedBox(width: 12),
              const Icon(Icons.event_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text('Prévue : ${_fmt(dateSortiePrevue)}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            ],
          ]),
          if (dateSortieEff.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.check_circle_outline, size: 14, color: _green),
              const SizedBox(width: 4),
              Text('Sorti le : ${_fmt(dateSortieEff)}',
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 13,
                      color: _green,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(notes,
                style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (onSorti != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onSorti,
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Marquer sorti',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─── Sheet ajout ─────────────────────────────────────────────────────────────

class _PensionEntreeSheet extends StatefulWidget {
  const _PensionEntreeSheet();

  @override
  State<_PensionEntreeSheet> createState() => _PensionEntreeSheetState();
}

class _PensionEntreeSheetState extends State<_PensionEntreeSheet> {
  static const _teal = Color(0xFF0C5C6C);
  final _formKey = GlobalKey<FormState>();
  final _supa = Supabase.instance.client;

  String _animalNom = '';
  String _espece = '';
  String _race = '';
  String _puce = '';
  String _proprietaireNom = '';
  String _proprietaireContact = '';
  DateTime _dateEntree = DateTime.now();
  DateTime? _dateSortiePrevue;
  String _notes = '';
  bool _saving = false;

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _pickDate(bool isEntree) async {
    final initial = isEntree
        ? _dateEntree
        : (_dateSortiePrevue ?? DateTime.now().add(const Duration(days: 3)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData.light()
            .copyWith(colorScheme: const ColorScheme.light(primary: _teal)),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isEntree) {
        _dateEntree = picked;
      } else {
        _dateSortiePrevue = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      await _supa.from('pension_entrees').insert({
        'pro_uid': _uid,
        'animal_nom': _animalNom,
        'espece': _espece,
        'race': _race,
        'puce': _puce,
        'proprietaire_nom': _proprietaireNom,
        'proprietaire_contact': _proprietaireContact,
        'date_entree': DateFormat('yyyy-MM-dd').format(_dateEntree),
        if (_dateSortiePrevue != null)
          'date_sortie_prevue': DateFormat('yyyy-MM-dd').format(_dateSortiePrevue!),
        'notes': _notes,
        'statut': 'en_pension',
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child:
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(
                child: Text('Nouvelle entrée pension',
                    style: TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 22, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 20),

            _sectionTitle('ANIMAL'),
            const SizedBox(height: 10),

            _lbl('Nom de l\'animal *'),
            TextFormField(
              decoration: _dec('Ex : Médor'),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
              onSaved: (v) => _animalNom = v?.trim() ?? '',
            ),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _lbl('Espèce'),
                TextFormField(
                    decoration: _dec('Ex : Chien'), onSaved: (v) => _espece = v?.trim() ?? ''),
              ])),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _lbl('Race'),
                TextFormField(
                    decoration: _dec('Ex : Labrador'),
                    onSaved: (v) => _race = v?.trim() ?? ''),
              ])),
            ]),
            const SizedBox(height: 10),
            _lbl('Numéro de puce'),
            TextFormField(
                decoration: _dec('250 269 810 000 000'),
                onSaved: (v) => _puce = v?.trim() ?? ''),
            const SizedBox(height: 20),

            _sectionTitle('PROPRIÉTAIRE'),
            const SizedBox(height: 10),

            _lbl('Nom'),
            TextFormField(
                decoration: _dec('Nom du propriétaire'),
                onSaved: (v) => _proprietaireNom = v?.trim() ?? ''),
            const SizedBox(height: 10),
            _lbl('Contact (tél / email)'),
            TextFormField(
                decoration: _dec('06 XX XX XX XX'),
                onSaved: (v) => _proprietaireContact = v?.trim() ?? ''),
            const SizedBox(height: 20),

            _sectionTitle('SÉJOUR'),
            const SizedBox(height: 10),

            Row(children: [
              Expanded(
                  child: _DateTile(
                      label: 'Entrée *',
                      date: _dateEntree,
                      onTap: () => _pickDate(true))),
              const SizedBox(width: 10),
              Expanded(
                  child: _DateTile(
                      label: 'Sortie prévue',
                      date: _dateSortiePrevue,
                      onTap: () => _pickDate(false))),
            ]),
            const SizedBox(height: 14),

            _lbl('Notes'),
            TextFormField(
              decoration: _dec('Alimentation, médicaments, comportement…'),
              maxLines: 3,
              onSaved: (v) => _notes = v?.trim() ?? '',
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Enregistrer l\'entrée',
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

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: Color(0xFF0C5C6C),
          letterSpacing: 0.8));

  Widget _lbl(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
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
            borderSide: const BorderSide(color: _teal, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      );
}

// ─── Date tile ────────────────────────────────────────────────────────────────

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  static const _teal = Color(0xFF0C5C6C);

  const _DateTile({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = date != null ? DateFormat('dd/MM/yyyy').format(date!) : 'Choisir';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 11,
                  color: Color(0xFF6F767B),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 14, color: _teal),
            const SizedBox(width: 6),
            Text(fmt,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: date != null ? const Color(0xFF1E2025) : Colors.grey)),
          ]),
        ]),
      ),
    );
  }
}
