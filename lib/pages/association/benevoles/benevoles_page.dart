import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/main.dart' show User_Info;

class BenevolesPage extends StatefulWidget {
  const BenevolesPage({super.key});
  @override
  State<BenevolesPage> createState() => _BenevolesPageState();
}

class _BenevolesPageState extends State<BenevolesPage> {
  final _supa = Supabase.instance.client;

  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  List<Map<String, dynamic>> _benevoles = [];
  bool _loading = true;

  final _prenomCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<String?> _resolveProfileId(String uid) async {
    // Le profil ACTIF (association), pas le profil "is_main" du compte —
    // sinon on mélange les bénévoles avec un autre profil du même compte.
    if (User_Info.activeProfileId.isNotEmpty) return User_Info.activeProfileId;
    final mainProfile = await _supa.from('user_profiles')
        .select('id').eq('uid', uid).eq('is_main', true).maybeSingle();
    return mainProfile?['id'] as String?;
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profileId = await _resolveProfileId(uid);
      var q = _supa.from('employes').select().eq('type', 'benevole');
      q = profileId != null ? q.eq('eleveur_profile_id', profileId) : q.eq('uid_eleveur', uid);
      final data = await q.order('nom');
      if (mounted) {
        setState(() {
          _benevoles = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBenevole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_prenomCtrl.text.trim().isEmpty || _nomCtrl.text.trim().isEmpty) return;

    try {
      final profileId = await _resolveProfileId(uid);
      await _supa.from('employes').insert({
        'uid_eleveur': uid,
        if (profileId != null) 'eleveur_profile_id': profileId,
        'prenom': _prenomCtrl.text.trim(),
        'nom': _nomCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'telephone': _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'actif': true,
        'type': 'benevole',
        'profil_source': 'association',
      });
      _prenomCtrl.clear();
      _nomCtrl.clear();
      _emailCtrl.clear();
      _telCtrl.clear();
      _notesCtrl.clear();
      if (mounted) Navigator.pop(context);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggle(String id, bool actif, {String? uidEmploye, String? employeProfileId}) async {
    await _supa.from('employes').update({'actif': !actif}).eq('id', id);
    if (actif && uidEmploye != null) {
      await _supa.from('notifications').insert({
        'uid':   uidEmploye,
        'type':  'employee_revoked',
        'title': 'Statut bénévole modifié',
        'body':  'Votre statut de bénévole a été désactivé',
        if ((employeProfileId ?? '').isNotEmpty) 'profile_id': employeProfileId,
        'data':  <String, dynamic>{},
        'read':  false,
      });
    }
    _load();
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le bénévole', style: TextStyle(fontFamily: 'Galey')),
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
      await _supa.from('employes').delete().eq('id', id);
      _load();
    }
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ajouter un bénévole',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 20),
            // Recherche PetsMatch
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.search, color: _teal),
                label: const Text('Chercher sur PetsMatch',
                    style: TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _teal),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  Navigator.pop(context);
                  _showSearchSheet();
                },
              ),
            ),
            const SizedBox(height: 12),
            // Saisie manuelle
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                label: const Text('Saisir manuellement',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  Navigator.pop(context);
                  _showManualSheet();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Saisir un bénévole',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _field(_prenomCtrl, 'Prénom *')),
              const SizedBox(width: 10),
              Expanded(child: _field(_nomCtrl, 'Nom *')),
            ]),
            const SizedBox(height: 10),
            _field(_emailCtrl, 'Email', keyboard: TextInputType.emailAddress),
            const SizedBox(height: 10),
            _field(_telCtrl, 'Téléphone', keyboard: TextInputType.phone),
            const SizedBox(height: 10),
            _field(_notesCtrl, 'Notes', maxLines: 2),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _addBenevole,
                style: ElevatedButton.styleFrom(backgroundColor: _teal),
                child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchSheet() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchBenevoleSheet(uid: uid, onAdded: _load),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? keyboard, int maxLines = 1}) =>
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

  @override
  Widget build(BuildContext context) {
    final actifs = _benevoles.where((b) => b['actif'] == true).toList();
    final inactifs = _benevoles.where((b) => b['actif'] != true).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        title: const Text('Bénévoles',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddSheet),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        backgroundColor: _teal,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white),
        label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _benevoles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.volunteer_activism_outlined, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text('Aucun bénévole enregistré',
                          style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _showAddSheet,
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter un bénévole', style: TextStyle(fontFamily: 'Galey')),
                        style: ElevatedButton.styleFrom(backgroundColor: _teal),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (actifs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text('Actifs (${actifs.length})',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 14, color: _teal)),
                      ),
                      ...actifs.map((b) => _BenevoleTile(
                        benevole: b,
                        onToggle: () => _toggle(b['id'], b['actif'] == true, uidEmploye: b['uid_employe'] as String?, employeProfileId: b['employe_profile_id'] as String?),
                        onDelete: () => _delete(b['id']),
                      )),
                    ],
                    if (inactifs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        child: Text('Inactifs (${inactifs.length})',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 14, color: Colors.grey)),
                      ),
                      ...inactifs.map((b) => _BenevoleTile(
                        benevole: b,
                        onToggle: () => _toggle(b['id'], b['actif'] == true, uidEmploye: b['uid_employe'] as String?, employeProfileId: b['employe_profile_id'] as String?),
                        onDelete: () => _delete(b['id']),
                      )),
                    ],
                  ],
                ),
    );
  }
}

class _BenevoleTile extends StatelessWidget {
  final Map<String, dynamic> benevole;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _BenevoleTile({required this.benevole, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final actif = benevole['actif'] == true;
    final prenom = benevole['prenom']?.toString() ?? '';
    final nom = benevole['nom']?.toString() ?? '';
    final email = benevole['email']?.toString() ?? '';
    final tel = benevole['telephone']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: actif ? const Color(0xFF0C5C6C) : Colors.grey.shade300,
          child: Text(
            prenom.isNotEmpty ? prenom[0].toUpperCase() : '?',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        title: Text('$prenom $nom',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                color: actif ? const Color(0xFF1F2A2E) : Colors.grey)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (email.isNotEmpty)
              Text(email, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            if (tel.isNotEmpty)
              Text(tel, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(actif ? Icons.toggle_on : Icons.toggle_off,
                  color: actif ? const Color(0xFF6E9E57) : Colors.grey),
              onPressed: onToggle,
              tooltip: actif ? 'Désactiver' : 'Activer',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sheet recherche bénévole PetsMatch ─────────────────────────────────────

class _SearchBenevoleSheet extends StatefulWidget {
  final String uid;
  final VoidCallback onAdded;
  const _SearchBenevoleSheet({required this.uid, required this.onAdded});
  @override
  State<_SearchBenevoleSheet> createState() => _SearchBenevoleSheetState();
}

class _SearchBenevoleSheetState extends State<_SearchBenevoleSheet> {
  final _supa = Supabase.instance.client;
  final _ctrl = TextEditingController();
  static const _teal = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _results  = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _loadUsers() async {
    try {
      final rows = await _supa.from('user_profiles')
          .select('uid, firstname, lastname, nom, profile_type, avatar_url, profile_picture_url_pro')
          .neq('uid', widget.uid).eq('is_main', true).limit(500);
      if (mounted) setState(() {
        _allUsers = List<Map<String, dynamic>>.from(rows as List).map((cp) => {
          'uid': cp['uid'], 'firstname': cp['firstname'], 'lastname': cp['lastname'],
          'name_elevage': cp['nom'], 'is_elevage': cp['profile_type'] == 'eleveur',
          'profile_picture_url': cp['avatar_url'], 'profile_picture_url_elevage': cp['profile_picture_url_pro'],
        }).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _search(String q) {
    final query = q.toLowerCase().trim();
    if (query.length < 2) { setState(() => _results = []); return; }
    setState(() {
      _results = _allUsers.where((u) {
        final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''} ${u['name_elevage'] ?? ''}'.toLowerCase();
        return nom.contains(query);
      }).take(15).toList();
    });
  }

  String _nomUser(Map<String, dynamic> u) {
    if (u['is_elevage'] == true) return (u['name_elevage'] as String? ?? 'Élevage').trim();
    return '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
  }

  String? _photoUser(Map<String, dynamic> u) {
    if (u['is_elevage'] == true) return u['profile_picture_url_elevage'] as String?;
    return u['profile_picture_url'] as String?;
  }

  Future<void> _ajouter(Map<String, dynamic> user) async {
    final uid = user['uid'] as String;
    // Le profil ACTIF (association), pas le profil "is_main" du compte.
    String? profileId = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;
    if (profileId == null) {
      final mainProfile = await _supa.from('user_profiles')
          .select('id').eq('uid', widget.uid).eq('is_main', true).maybeSingle();
      profileId = mainProfile?['id'] as String?;
    }
    // Cherche uniquement dans les bénévoles de l'association active
    var existingQ = _supa.from('employes').select()
        .eq('uid_eleveur', widget.uid).eq('uid_employe', uid)
        .eq('profil_source', 'association').eq('type', 'benevole');
    if (profileId != null) existingQ = existingQ.eq('eleveur_profile_id', profileId);
    final existing = await existingQ.maybeSingle();

    if (existing != null) {
      if (existing['actif'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cette personne est déjà bénévole dans votre équipe.')));
        }
        return;
      }
      await _supa.from('employes').update({'actif': true}).eq('id', existing['id']);
    } else {
      await _supa.from('employes').insert({
        'uid_employe': uid,
        'uid_eleveur': widget.uid,
        if (profileId != null) 'eleveur_profile_id': profileId,
        'actif': true,
        'type': 'benevole',
        'profil_source': 'association',
      });
    }
    // Rejoindre une équipe est une notion particulier — résoudre ce profil
    // précis du destinataire (le picker ci-dessus liste tout profil is_main,
    // pas seulement particulier).
    final targetParticulier = await _supa.from('user_profiles')
        .select('id').eq('uid', uid).eq('profile_type', 'particulier').eq('is_main', true).maybeSingle();
    await _supa.from('notifications').insert({
      'uid':   uid,
      'type':  'employee_invite',
      'title': 'Invitation bénévole',
      'body':  'Vous avez été ajouté comme bénévole dans une association',
      if (targetParticulier?['id'] != null) 'profile_id': targetParticulier!['id'],
      'data':  {'assoUid': widget.uid},
      'read':  false,
    });
    widget.onAdded();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_nomUser(user)} ajouté comme bénévole ✓')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Ajouter un bénévole',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(fontFamily: 'Galey'),
              decoration: InputDecoration(
                hintText: 'Rechercher par prénom ou nom…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true, fillColor: const Color(0xFFF3F4F6),
              ),
              onChanged: _search,
            ),
          ),
          const SizedBox(height: 6),
          if (!_loading && _ctrl.text.length < 2)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('Tapez au moins 2 lettres pour rechercher.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            ),
          if (!_loading && _ctrl.text.length >= 2 && _results.isEmpty)
            const Padding(padding: EdgeInsets.all(20),
                child: Text('Aucun utilisateur trouvé',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
          Expanded(
            child: ListView.builder(
              controller: sc,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final u = _results[i];
                final nom   = _nomUser(u);
                final photo = _photoUser(u);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _teal.withValues(alpha: 0.12),
                    backgroundImage: photo != null
                        ? NetworkImage(photo) as ImageProvider : null,
                    child: photo == null ? Icon(Icons.person, color: _teal) : null,
                  ),
                  title: Text(nom.isEmpty ? 'Utilisateur' : nom,
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  subtitle: const Text('Bénévole',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _teal)),
                  trailing: Icon(Icons.add_circle_outline, color: _teal),
                  onTap: () => _ajouter(u),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
