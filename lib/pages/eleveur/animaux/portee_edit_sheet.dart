import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

class PorteeEditSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animals;

  const PorteeEditSheet({super.key, required this.animals});

  /// Ouvre le bottom sheet et retourne true si la portée a été mise à jour.
  static Future<bool> show(BuildContext context, List<Map<String, dynamic>> animals) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PorteeEditSheet(animals: animals),
    );
    return result ?? false;
  }

  @override
  State<PorteeEditSheet> createState() => _PorteeEditSheetState();
}

class _PorteeEditSheetState extends State<PorteeEditSheet> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  late final TextEditingController _raceCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _clubRegistreCtrl;
  late final TextEditingController _pedigreeLofCtrl;
  late final TextEditingController _nomPereCtrl;
  late final TextEditingController _pucePereCtrl;
  late final TextEditingController _nomMereCtrl;
  late final TextEditingController _puceMereCtrl;
  late final TextEditingController _raceMereCtrl;

  late DateTime _dateNaissance;
  DateTime? _dateNaissanceMere;
  bool _pedigree = false;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _animauxExistants = [];
  bool _loadingExistants = false;

  Map<String, dynamic> get _first => widget.animals.first;

  List<Map<String, dynamic>> get _peres => _animauxExistants
      .where((a) => a['espece'] == _first['espece'] && (a['sexe'] as String? ?? '').startsWith('m'))
      .toList();

  List<Map<String, dynamic>> get _meres => _animauxExistants
      .where((a) => a['espece'] == _first['espece'] && (a['sexe'] as String? ?? '').startsWith('f'))
      .toList();

  @override
  void initState() {
    super.initState();
    _raceCtrl         = TextEditingController(text: (_first['race'] as String?) ?? '');
    _descriptionCtrl  = TextEditingController(text: (_first['description'] as String?) ?? '');
    _clubRegistreCtrl = TextEditingController(text: (_first['club_registre'] as String?) ?? '');
    _pedigreeLofCtrl  = TextEditingController(text: (_first['pedigree_lof'] as String?) ?? '');
    _nomPereCtrl      = TextEditingController(text: (_first['nom_pere'] as String?) ?? '');
    _pucePereCtrl     = TextEditingController(text: (_first['puce_pere'] as String?) ?? '');
    _nomMereCtrl      = TextEditingController(text: (_first['nom_mere'] as String?) ?? '');
    _puceMereCtrl     = TextEditingController(text: (_first['puce_mere'] as String?) ?? '');
    _raceMereCtrl     = TextEditingController(text: (_first['race_mere'] as String?) ?? '');
    _pedigree         = _first['pedigree'] == true;
    _dateNaissance    = DateTime.tryParse(_first['date_naissance'] as String? ?? '') ?? DateTime.now();
    _dateNaissanceMere = DateTime.tryParse(_first['date_naissance_mere'] as String? ?? '');
    _loadExistants();
  }

  Future<void> _loadExistants() async {
    setState(() => _loadingExistants = true);
    try {
      final supa = Supabase.instance.client;
      final pid = User_Info.activeProfileId;
      var q = supa.from('animaux')
          .select('id, nom, sexe, espece, race, identification, date_naissance, photo_url')
          .eq('uid_eleveur', User_Info.uid)
          .or('statut.is.null,statut.eq.present');
      if (pid.isNotEmpty) q = q.eq('profile_id', pid);
      final rows = await q;
      if (mounted) setState(() {
        _animauxExistants = List<Map<String, dynamic>>.from(rows as List);
        _loadingExistants = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingExistants = false);
    }
  }

  void _openParentPicker({required bool isMere}) {
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ParentPickerSheet(
        animals: isMere ? _meres : _peres,
        title: isMere ? 'Sélectionner la mère' : 'Sélectionner le père',
      ),
    ).then((sel) {
      if (sel == null) return;
      setState(() {
        if (isMere) {
          _nomMereCtrl.text  = sel['nom']            as String? ?? '';
          _puceMereCtrl.text = sel['identification'] as String? ?? '';
          _raceMereCtrl.text = sel['race']           as String? ?? '';
          final dn = sel['date_naissance'] as String?;
          _dateNaissanceMere = dn != null ? DateTime.tryParse(dn) : null;
        } else {
          _nomPereCtrl.text  = sel['nom']            as String? ?? '';
          _pucePereCtrl.text = sel['identification'] as String? ?? '';
        }
      });
    });
  }

  @override
  void dispose() {
    _raceCtrl.dispose();
    _descriptionCtrl.dispose();
    _clubRegistreCtrl.dispose();
    _pedigreeLofCtrl.dispose();
    _nomPereCtrl.dispose();
    _pucePereCtrl.dispose();
    _nomMereCtrl.dispose();
    _puceMereCtrl.dispose();
    _raceMereCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool mere}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: mere ? (_dateNaissanceMere ?? DateTime.now()) : _dateNaissance,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('fr'),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: _teal)),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() { if (mere) _dateNaissanceMere = picked; else _dateNaissance = picked; });
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    final supa = Supabase.instance.client;
    final porteeId = _first['portee_id'] as String? ?? '';
    final dateIso = _dateNaissance.toIso8601String().split('T')[0];
    try {
      await supa.from('animaux').update({
        'race':                _raceCtrl.text.trim().isEmpty ? null : _raceCtrl.text.trim(),
        'date_naissance':      dateIso,
        'date_entree':         dateIso,
        'description':         _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
        'pedigree':            _pedigree,
        'club_registre':       _clubRegistreCtrl.text.trim().isEmpty ? null : _clubRegistreCtrl.text.trim(),
        'pedigree_lof':        _pedigreeLofCtrl.text.trim().isEmpty ? null : _pedigreeLofCtrl.text.trim(),
        'nom_pere':            _nomPereCtrl.text.trim().isEmpty ? null : _nomPereCtrl.text.trim(),
        'puce_pere':           _pucePereCtrl.text.trim().isEmpty ? null : _pucePereCtrl.text.trim(),
        'nom_mere':            _nomMereCtrl.text.trim().isEmpty ? null : _nomMereCtrl.text.trim(),
        'puce_mere':           _puceMereCtrl.text.trim().isEmpty ? null : _puceMereCtrl.text.trim(),
        'race_mere':           _raceMereCtrl.text.trim().isEmpty ? null : _raceMereCtrl.text.trim(),
        'date_naissance_mere': _dateNaissanceMere?.toIso8601String().split('T')[0],
      }).eq('portee_id', porteeId);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'Erreur lors de la sauvegarde.'; });
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
    filled: true, fillColor: const Color(0xFFF8F8F6),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _teal.withOpacity(0.2))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _teal.withOpacity(0.2))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _teal, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontFamily: 'Galey',
        fontWeight: FontWeight.w700, fontSize: 13, color: _teal)),
  );

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Titre
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.edit_outlined, color: _teal, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Modifier la portée', style: TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
                Text('${widget.animals.length} animal${widget.animals.length > 1 ? 'aux' : ''} concerné${widget.animals.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context, false),
              padding: EdgeInsets.zero,
            ),
          ]),

          const SizedBox(height: 18),

          // Race
          _label('Race'),
          TextField(controller: _raceCtrl, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: _dec('Race commune à tous')),

          const SizedBox(height: 14),

          // Date de naissance
          _label('Date de naissance *'),
          GestureDetector(
            onTap: () => _pickDate(mere: false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _teal.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: _teal),
                const SizedBox(width: 8),
                Text(fmt.format(_dateNaissance), style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9E9E9E)),
              ]),
            ),
          ),

          const SizedBox(height: 14),

          // Description
          _label('Description (optionnel)'),
          TextField(controller: _descriptionCtrl, maxLines: 2,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: _dec('Caractère, particularités de la portée…')),

          const SizedBox(height: 20),

          // Pedigree & Registre
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🏅 Pedigree & Registre', style: TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: Text('Inscrit au registre (LOF / LOOF…)',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
                Switch(
                  value: _pedigree,
                  activeThumbColor: _green,
                  onChanged: (v) => setState(() => _pedigree = v),
                ),
              ]),
              const SizedBox(height: 8),
              _label('Club de race / Association pedigree'),
              TextField(controller: _clubRegistreCtrl, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: _dec('Ex: SCC, Club du Berger Australien…')),
              const SizedBox(height: 12),
              _label('N° d\'inscription au registre'),
              TextField(controller: _pedigreeLofCtrl, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: _dec('Ex: LOF 12345/00, LOOF 67890…')),
            ]),
          ),

          const SizedBox(height: 14),

          // Père
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('♂ Père (optionnel)', style: TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loadingExistants ? null : () => _openParentPicker(isMere: false),
                icon: const Icon(Icons.search, size: 16, color: _teal),
                label: const Text('Chercher parmi mes animaux',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: _teal)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _teal),
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Nom du père'),
                  TextField(controller: _nomPereCtrl, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      decoration: _dec('Nom')),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('N° identification'),
                  TextField(controller: _pucePereCtrl, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      decoration: _dec('Puce / tatouage')),
                ])),
              ]),
            ]),
          ),

          const SizedBox(height: 14),

          // Mère
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('♀ Mère (optionnel)', style: TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _loadingExistants ? null : () => _openParentPicker(isMere: true),
                icon: const Icon(Icons.search, size: 16, color: _teal),
                label: const Text('Chercher parmi mes animaux',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: _teal)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _teal),
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Nom de la mère'),
                  TextField(controller: _nomMereCtrl, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      decoration: _dec('Nom')),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('N° identification'),
                  TextField(controller: _puceMereCtrl, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      decoration: _dec('Puce / tatouage')),
                ])),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Race de la mère'),
                  TextField(controller: _raceMereCtrl, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      decoration: _dec('Race')),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Date de naissance'),
                  GestureDetector(
                    onTap: () => _pickDate(mere: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _teal.withOpacity(0.2)),
                      ),
                      child: Text(
                        _dateNaissanceMere != null ? fmt.format(_dateNaissanceMere!) : '—',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E)),
                      ),
                    ),
                  ),
                ])),
              ]),
            ]),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFB71C1C))),
            ),
          ],

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(_saving ? 'Enregistrement…' : 'Enregistrer',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Sheet sélection animal existant (avec recherche) ────────────────────────

class _ParentPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final String title;
  const _ParentPickerSheet({required this.animals, required this.title});
  @override State<_ParentPickerSheet> createState() => _ParentPickerSheetState();
}

class _ParentPickerSheetState extends State<_ParentPickerSheet> {
  late List<Map<String, dynamic>> _filtered;
  final _searchCtrl = TextEditingController();
  static const _teal = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _filtered = widget.animals;
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? widget.animals
          : widget.animals.where((a) {
              final nom  = (a['nom'] as String? ?? '').toLowerCase();
              final race = (a['race'] as String? ?? '').toLowerCase();
              return nom.contains(q.toLowerCase()) || race.contains(q.toLowerCase());
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scroll) => Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(child: Text(widget.title,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 17))),
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Annuler',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _filter,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Rechercher…',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true, fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _filtered.isEmpty
              ? const Center(child: Text('Aucun animal trouvé', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : ListView.builder(
            controller: scroll,
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final a        = _filtered[i];
              final nom      = a['nom']  as String? ?? 'Sans nom';
              final race     = a['race'] as String? ?? '';
              final photoUrl = a['photo_url'] as String? ?? '';
              return ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF5EA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: photoUrl.isEmpty
                      ? const Icon(Icons.pets, color: _teal, size: 20)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(photoUrl, width: 44, height: 44, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.pets, color: _teal, size: 20)),
                        ),
                ),
                title: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: race.isNotEmpty
                    ? Text(race, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)))
                    : null,
                onTap: () => Navigator.pop(context, a),
              );
            },
          ),
        ),
      ]),
    );
  }
}
