import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

const _teal  = Color(0xFF0C5C6C);
const _amber = Color(0xFFD97706);
const _dark  = Color(0xFF1F2A2E);

// ── Feuille de réservation (avant cession) ─────────────────────────────────────

class ReservationSheet extends StatefulWidget {
  final Map<String, dynamic> animal;
  final String uid;
  final VoidCallback onReserved;

  const ReservationSheet({
    super.key,
    required this.animal,
    required this.uid,
    required this.onReserved,
  });

  @override
  State<ReservationSheet> createState() => _ReservationSheetState();
}

class _ReservationSheetState extends State<ReservationSheet> {
  final _supa = Supabase.instance.client;

  int _step = 0; // 0 = futur propriétaire, 1 = détails

  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _foundUser;
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  bool _searchDone = false;

  String _qualite = 'particulier';
  final _nomCtrl     = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _telCtrl     = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _notesCtrl   = TextEditingController();
  late DateTime _dateReservation;

  bool _saving = false;
  String? _error;

  static const _cpFields = 'uid, firstname, lastname, nom, profile_type, avatar_url, phone_number, adresse, rue, ville, code_postal, numero_elevage';

  @override
  void initState() {
    super.initState();
    _dateReservation = DateTime.now();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    _adresseCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _mapProfile(Map<String, dynamic> cp, {String? email}) => {
    'uid': cp['uid'],
    'firstname': cp['firstname'], 'lastname': cp['lastname'],
    'name_elevage': cp['nom'], 'is_elevage': cp['profile_type'] == 'eleveur',
    'profile_picture_url': cp['avatar_url'], 'phone_number': cp['phone_number'],
    'code_iso': '+33', 'code_iso_elevage': '+33',
    'adress': cp['adresse'], 'adress_elevage': cp['adresse'],
    'rue': cp['rue'], 'ville': cp['ville'], 'code_postal': cp['code_postal'],
    'numero_elevage': cp['numero_elevage'],
    'email': email,
  };

  Future<void> _searchUser() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _searching = true; _searchDone = false; _foundUser = null; _searchResults = []; });
    try {
      final isEmail = q.contains('@');
      List<Map<String, dynamic>> rows;
      if (isEmail) {
        final userRow = await _supa.from('users').select('uid, email')
            .eq('email', q.toLowerCase()).maybeSingle();
        if (userRow == null) {
          rows = [];
        } else {
          final cp = await _supa.from('user_profiles').select(_cpFields)
              .eq('uid', userRow['uid'] as String).eq('is_main', true).maybeSingle();
          rows = cp != null ? [_mapProfile(cp, email: userRow['email'] as String?)] : [];
        }
      } else {
        final cps = await _supa
            .from('user_profiles')
            .select(_cpFields)
            .or('firstname.ilike.%$q%,lastname.ilike.%$q%,nom.ilike.%$q%')
            .eq('is_main', true)
            .limit(8);
        rows = (cps as List).map((cp) => _mapProfile(Map<String, dynamic>.from(cp))).toList();
      }
      final mapped = rows.map((r) {
        final isElv = r['is_elevage'] == true;
        final nom = isElv
            ? (r['name_elevage'] as String? ?? '${r['firstname'] ?? ''} ${r['lastname'] ?? ''}'.trim())
            : '${r['firstname'] ?? ''} ${r['lastname'] ?? ''}'.trim();
        return {...r, 'nom': nom.isEmpty ? 'Utilisateur PetsMatch' : nom};
      }).toList();
      if (mapped.length == 1) {
        _selectUser(mapped.first);
      } else {
        setState(() { _searchResults = mapped; });
      }
    } finally {
      setState(() { _searching = false; _searchDone = true; });
    }
  }

  void _selectUser(Map<String, dynamic> r) {
    final isElv = r['is_elevage'] == true;
    final adresse = isElv
        ? (r['adress_elevage'] as String? ?? [r['rue'], r['ville'], r['code_postal']].where((e) => e != null).join(', '))
        : (r['adress'] as String? ?? [r['rue'], r['ville'], r['code_postal']].where((e) => e != null).join(', '));
    final tel = isElv
        ? '${r['code_iso_elevage'] ?? '+33'} ${r['numero_elevage'] ?? ''}'.trim()
        : '${r['code_iso'] ?? '+33'} ${r['phone_number'] ?? ''}'.trim();
    setState(() {
      _foundUser = r;
      _nomCtrl.text    = r['nom'] as String;
      _emailCtrl.text  = (r['email'] as String? ?? '');
      _telCtrl.text    = tel;
      _adresseCtrl.text = adresse;
      _searchResults   = [];
      if (isElv) _qualite = 'eleveur';
    });
  }

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Le nom du futur propriétaire est requis.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final profileId = User_Info.activeProfileId;
      await _supa.from('reservations_animaux').insert({
        'animal_id':   widget.animal['id'],
        'uid_eleveur': widget.uid,
        if (profileId.isNotEmpty) 'eleveur_profile_id': profileId,
        'statut':      'active',
        'qualite':     _qualite,
        'nom':         _nomCtrl.text.trim(),
        'email':       _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'tel':         _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'adresse':     _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'uid_acquereur': _foundUser?['uid'],
        'date_reservation': _dateReservation.toIso8601String().split('T').first,
        'notes':       _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      });
      await _supa.from('animaux').update({'statut': 'reserve'}).eq('id', widget.animal['id']);
      if (mounted) {
        Navigator.pop(context);
        widget.onReserved();
      }
    } catch (e) {
      setState(() { _saving = false; _error = 'Erreur : $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🔖 Réserver ${widget.animal['nom'] ?? 'cet animal'}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _dark)),
              Text('Étape ${_step + 1}/2', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
            if (_step > 0)
              GestureDetector(
                onTap: () => setState(() => _step--),
                child: const Icon(Icons.chevron_left, color: _teal),
              ),
          ]),
          const SizedBox(height: 16),

          if (_error != null)
            Container(margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                child: Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700))),

          // ── Étape 0 : Futur propriétaire ─────────────────────
          if (_step == 0) ...[
            const Text('Rechercher sur PetsMatch',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: TextField(
                controller: _searchCtrl,
                onSubmitted: (_) => _searchUser(),
                decoration: InputDecoration(
                  hintText: 'Nom, prénom ou email…',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _teal, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _searching ? null : _searchUser,
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _searching ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Chercher'),
              ),
            ]),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...(_searchResults.map((r) => GestureDetector(
                onTap: () => _selectUser(r),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    const Icon(Icons.person_outline, color: _teal, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['nom'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Galey')),
                      if (r['email'] != null) Text(r['email'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ])),
                    const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                  ]),
                ),
              ))),
            ],
            if (_searchDone && _searchResults.isEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _foundUser != null ? _teal.withValues(alpha: 0.06) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _foundUser != null ? _teal.withValues(alpha: 0.2) : Colors.grey.shade200),
                ),
                child: _foundUser != null
                    ? Row(children: [
                        const Icon(Icons.verified_user_outlined, color: _teal, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_foundUser!['nom'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: _teal, fontFamily: 'Galey'))),
                      ])
                    : const Text('Aucun utilisateur trouvé.', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Divider()),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('ou', style: TextStyle(color: Colors.grey, fontSize: 12))),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() { _step = 1; }),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Saisie manuelle', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _dark,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
            if (_foundUser != null) ...[
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => setState(() => _step = 1),
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Continuer →', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ],
          ],

          // ── Étape 1 : Détails ────────────────────────────────
          if (_step == 1) ...[
            if (_foundUser != null) Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _teal.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.verified_user_outlined, color: _teal, size: 16),
                const SizedBox(width: 6),
                Text(_foundUser!['nom'] as String,
                    style: const TextStyle(color: _teal, fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
            _FieldBlock('Date de réservation', child: GestureDetector(
              onTap: () async {
                final d = await showDatePicker(context: context,
                    initialDate: _dateReservation, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _dateReservation = d);
              },
              child: Container(
                height: 48,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${_dateReservation.day.toString().padLeft(2, '0')}/${_dateReservation.month.toString().padLeft(2, '0')}/${_dateReservation.year}',
                    style: const TextStyle(fontSize: 13)),
              ),
            )),
            const SizedBox(height: 10),
            _FieldBlock('Qualité', child: DropdownButtonFormField<String>(
              value: _qualite,
              items: const [
                DropdownMenuItem(value: 'particulier', child: Text('Particulier')),
                DropdownMenuItem(value: 'eleveur',     child: Text('Éleveur')),
                DropdownMenuItem(value: 'refuge',      child: Text('Refuge / Association')),
                DropdownMenuItem(value: 'autre',       child: Text('Autre')),
              ],
              onChanged: (v) => setState(() => _qualite = v!),
              decoration: _inputDec('Qualité'),
            )),
            const SizedBox(height: 10),
            _FieldBlock('Nom du futur propriétaire *', child: TextField(
              controller: _nomCtrl,
              decoration: _inputDec('Nom complet'),
            )),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _FieldBlock('Email', child: TextField(
                controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                decoration: _inputDec('email@exemple.fr'),
              ))),
              const SizedBox(width: 8),
              Expanded(child: _FieldBlock('Téléphone', child: TextField(
                controller: _telCtrl, keyboardType: TextInputType.phone,
                decoration: _inputDec('06 XX XX XX XX'),
              ))),
            ]),
            const SizedBox(height: 10),
            _FieldBlock('Adresse', child: TextField(
              controller: _adresseCtrl,
              decoration: _inputDec('Adresse du futur propriétaire'),
            )),
            const SizedBox(height: 10),
            _FieldBlock('Notes', child: TextField(
              controller: _notesCtrl, maxLines: 2,
              decoration: _inputDec('Acompte versé, conditions…'),
            )),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _saving || _nomCtrl.text.trim().isEmpty ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: _amber, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('🔖 Réserver', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      ),
    );
  }
}

InputDecoration _inputDec(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 2)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
);

class _FieldBlock extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldBlock(this.label, {required this.child});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
    const SizedBox(height: 4),
    child,
  ]);
}
