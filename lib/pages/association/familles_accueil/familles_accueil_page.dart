import 'dart:async';
import 'package:PetsMatch/main.dart' show getApiKey;
import 'package:flutter/material.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FamillesAccueilPage extends StatefulWidget {
  const FamillesAccueilPage({super.key});
  @override
  State<FamillesAccueilPage> createState() => _FamillesAccueilPageState();
}

class _FamillesAccueilPageState extends State<FamillesAccueilPage> {
  final _supa = Supabase.instance.client;

  static const _teal   = Color(0xFF0C5C6C);
  static const _green  = Color(0xFF6E9E57);

  List<Map<String, dynamic>> _fa = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final data = await _supa
          .from('familles_accueil')
          .select('*, animaux(id, nom, photo_url, statut)')
          .eq('association_uid', uid)
          .eq('actif', true)
          .order('nom');
      if (mounted) {
        setState(() {
          _fa = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la FA', style: TextStyle(fontFamily: 'Galey')),
        content: const Text('Cette action est irréversible.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _supa.from('familles_accueil').update({'actif': false}).eq('id', id);
      _load();
    }
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddFaSheet(
        onSaved: () { _load(); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        title: const Text('Familles d\'accueil',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        backgroundColor: _teal,
        icon: const Icon(Icons.house_outlined, color: Colors.white),
        label: const Text('Ajouter une FA', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _fa.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.house_outlined, size: 60, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    const Text('Aucune famille d\'accueil',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _showAddSheet,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter une FA', style: TextStyle(fontFamily: 'Galey')),
                      style: ElevatedButton.styleFrom(backgroundColor: _teal),
                    ),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: _fa.length,
                  itemBuilder: (_, i) {
                    final f = _fa[i];
                    final animaux = (f['animaux'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    final capacite = f['capacite_max'] ?? 1;
                    final dispo = capacite - animaux.length;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            CircleAvatar(
                              backgroundColor: _teal,
                              child: Text(
                                (f['prenom']?.toString() ?? '?')[0].toUpperCase(),
                                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${f['prenom'] ?? ''} ${f['nom'] ?? ''}',
                                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                                if (f['ville'] != null)
                                  Text(f['ville'], style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                              ]),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: dispo > 0 ? _green.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${animaux.length}/$capacite',
                                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12,
                                      color: dispo > 0 ? _green : Colors.orange)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () => _delete(f['id']),
                            ),
                          ]),
                          if (f['email'] != null || f['telephone'] != null) ...[
                            const SizedBox(height: 8),
                            Row(children: [
                              if (f['email'] != null) ...[
                                const Icon(Icons.email_outlined, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(f['email'], style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                                const SizedBox(width: 12),
                              ],
                              if (f['telephone'] != null) ...[
                                const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(f['telephone'], style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                              ],
                            ]),
                          ],
                          if (animaux.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text('Animaux en accueil :',
                                style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C))),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: animaux.map((a) => Chip(
                                label: Text(a['nom'] ?? '?',
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: const Color(0xFF0C5C6C).withValues(alpha: 0.08),
                              )).toList(),
                            ),
                          ],
                          if (f['notes'] != null) ...[
                            const SizedBox(height: 8),
                            Text(f['notes'],
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}

// ── Sheet d'ajout FA ─────────────────────────────────────────────────────────

class _AddFaSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _AddFaSheet({required this.onSaved});
  @override
  State<_AddFaSheet> createState() => _AddFaSheetState();
}

class _AddFaSheetState extends State<_AddFaSheet> {
  final _supa = Supabase.instance.client;
  late final GoogleMapsPlaces _places;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  // Recherche profil
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allUsers  = [];
  List<Map<String, dynamic>> _userResults = [];
  bool _loadingUsers = false;
  String? _linkedUid;

  // Champs FA
  final _prenomCtrl  = TextEditingController();
  final _nomCtrl     = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _telCtrl     = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _villeCtrl   = TextEditingController();
  final _cpCtrl      = TextEditingController();
  final _notesCtrl   = TextEditingController();
  int _capaciteMax = 1;

  // Places autocomplete
  List<Prediction> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
    _loadUsers();
  }

  @override
  void dispose() {
    _places.dispose();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    _adresseCtrl.dispose();
    _villeCtrl.dispose();
    _cpCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    setState(() => _loadingUsers = true);
    try {
      final rows = await _supa
          .from('users')
          .select('uid, firstname, lastname, email, phone, profile_picture_url')
          .neq('uid', myUid)
          .limit(500);
      if (mounted) setState(() {
        _allUsers = List<Map<String, dynamic>>.from(rows);
        _loadingUsers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  void _searchUsers(String q) {
    final query = q.toLowerCase().trim();
    if (query.length < 2) { setState(() => _userResults = []); return; }
    final res = _allUsers.where((u) {
      final full = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''} ${u['email'] ?? ''}'.toLowerCase();
      return full.contains(query);
    }).take(10).toList();
    setState(() => _userResults = res);
  }

  void _selectUser(Map<String, dynamic> u) {
    setState(() {
      _linkedUid = u['uid'] as String?;
      _prenomCtrl.text = u['firstname'] as String? ?? '';
      _nomCtrl.text    = u['lastname']  as String? ?? '';
      _emailCtrl.text  = u['email']     as String? ?? '';
      _telCtrl.text    = u['phone']     as String? ?? '';
      _searchCtrl.text = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
      _userResults = [];
    });
  }

  void _onAdresseChanged() {
    final text = _adresseCtrl.text;
    _debounce?.cancel();
    if (text.length < 3) { setState(() { _suggestions = []; _showSuggestions = false; }); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final response = await _places.autocomplete(text, language: 'fr');
      if (!mounted) return;
      setState(() {
        _suggestions = response.isOkay ? response.predictions : [];
        _showSuggestions = _suggestions.isNotEmpty;
      });
    });
  }

  Future<void> _selectPrediction(Prediction p) async {
    if (p.placeId == null) return;
    final det = await _places.getDetailsByPlaceId(p.placeId!);
    if (!mounted || !det.isOkay) return;
    String streetNum = '', route = '', cp = '', ville = '';
    for (final comp in det.result!.addressComponents) {
      if (comp.types.contains('street_number')) streetNum = comp.longName;
      if (comp.types.contains('route'))         route = comp.longName;
      if (comp.types.contains('postal_code'))   cp = comp.longName;
      if (comp.types.contains('locality'))      ville = comp.longName;
    }
    setState(() {
      _adresseCtrl.text = [streetNum, route].where((s) => s.isNotEmpty).join(' ');
      _cpCtrl.text    = cp;
      _villeCtrl.text = ville;
      _suggestions = [];
      _showSuggestions = false;
    });
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_prenomCtrl.text.trim().isEmpty || _nomCtrl.text.trim().isEmpty) return;
    try {
      await _supa.from('familles_accueil').insert({
        'association_uid': uid,
        'fa_uid':      _linkedUid,
        'prenom':      _prenomCtrl.text.trim(),
        'nom':         _nomCtrl.text.trim(),
        'email':       _emailCtrl.text.trim().isEmpty   ? null : _emailCtrl.text.trim(),
        'telephone':   _telCtrl.text.trim().isEmpty     ? null : _telCtrl.text.trim(),
        'adresse':     _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'ville':       _villeCtrl.text.trim().isEmpty   ? null : _villeCtrl.text.trim(),
        'code_postal': _cpCtrl.text.trim().isEmpty      ? null : _cpCtrl.text.trim(),
        'capacite_max': _capaciteMax,
        'notes':       _notesCtrl.text.trim().isEmpty   ? null : _notesCtrl.text.trim(),
        'actif': true,
      });
      if (mounted) Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text('Ajouter une famille d\'accueil',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 12),

          // ── Recherche profil existant ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _teal.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.person_search_outlined, color: _teal, size: 18),
                const SizedBox(width: 6),
                const Text('Chercher un utilisateur PetsMatch',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0C5C6C))),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Nom, prénom…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: _loadingUsers ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ) : null,
                ),
                onChanged: _searchUsers,
              ),
              if (_userResults.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _userResults.length,
                    itemBuilder: (_, i) {
                      final u = _userResults[i];
                      final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: _teal.withValues(alpha: 0.15),
                          backgroundImage: u['profile_picture_url'] != null
                              ? NetworkImage(u['profile_picture_url'] as String) : null,
                          child: u['profile_picture_url'] == null
                              ? Text(nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _teal))
                              : null,
                        ),
                        title: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                        subtitle: u['email'] != null
                            ? Text(u['email'] as String,
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey))
                            : null,
                        trailing: Icon(Icons.add_circle_outline, color: _green, size: 18),
                        onTap: () => _selectUser(u),
                      );
                    },
                  ),
                ),
              ],
              if (_linkedUid != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Icon(Icons.check_circle, color: _green, size: 14),
                    const SizedBox(width: 4),
                    Text('Profil lié — champs pré-remplis',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() {
                        _linkedUid = null;
                        _searchCtrl.clear();
                      }),
                      child: const Text('Délier', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Champs identité ───────────────────────────────────────────
          const Text('Informations', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _field(_prenomCtrl, 'Prénom *')),
            const SizedBox(width: 10),
            Expanded(child: _field(_nomCtrl, 'Nom *')),
          ]),
          const SizedBox(height: 10),
          _field(_emailCtrl, 'Email', keyboard: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _field(_telCtrl, 'Téléphone', keyboard: TextInputType.phone),
          const SizedBox(height: 14),

          // ── Adresse avec autocomplete ─────────────────────────────────
          const Text('Adresse', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: _adresseCtrl,
            style: const TextStyle(fontFamily: 'Galey'),
            onChanged: (_) => _onAdresseChanged(),
            decoration: InputDecoration(
              labelText: 'Adresse',
              labelStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
            ),
          ),
          if (_showSuggestions && _suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions.take(5).map((p) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, size: 16, color: Colors.grey),
                  title: Text(p.description ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  onTap: () => _selectPrediction(p),
                )).toList(),
              ),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(_villeCtrl, 'Ville')),
            const SizedBox(width: 10),
            Expanded(child: _field(_cpCtrl, 'Code postal', keyboard: TextInputType.number)),
          ]),
          const SizedBox(height: 10),

          // ── Capacité ──────────────────────────────────────────────────
          StatefulBuilder(
            builder: (_, setInner) => Row(children: [
              const Text('Capacité max :', style: TextStyle(fontFamily: 'Galey')),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setInner(() { if (_capaciteMax > 1) _capaciteMax--; }),
              ),
              Text('$_capaciteMax', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setInner(() => _capaciteMax++),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          _field(_notesCtrl, 'Notes (espèces, contraintes…)', maxLines: 2),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {TextInputType? keyboard, int maxLines = 1}) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Galey'),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      );
}
