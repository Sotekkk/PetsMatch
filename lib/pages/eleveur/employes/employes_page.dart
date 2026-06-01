// ─── A46 — Profils employés d'élevage ─────────────────────────────────────────
//
// Migration SQL requise (à exécuter une fois dans Supabase) :
//
//   CREATE TABLE IF NOT EXISTS employes (
//     id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
//     uid_employe TEXT NOT NULL,
//     uid_eleveur TEXT NOT NULL,
//     actif       BOOLEAN DEFAULT TRUE NOT NULL,
//     created_at  TIMESTAMPTZ DEFAULT NOW()
//   );
//
//   CREATE TABLE IF NOT EXISTS taches_elevage (
//     id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
//     titre       TEXT NOT NULL,
//     animal_id   TEXT,
//     uid_eleveur TEXT NOT NULL,
//     date        DATE NOT NULL,
//     statut      TEXT DEFAULT 'a_faire' NOT NULL,
//     assigne_a   TEXT,
//     notes       TEXT,
//     created_at  TIMESTAMPTZ DEFAULT NOW()
//   );

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

// ─── Page principale ──────────────────────────────────────────────────────────

class EmployesPage extends StatefulWidget {
  const EmployesPage({super.key});
  @override
  State<EmployesPage> createState() => _EmployesPageState();
}

class _EmployesPageState extends State<EmployesPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  static const _green = Color(0xFF6E9E57);
  static const _teal  = Color(0xFF0C5C6C);
  static const _dark  = Color(0xFF1F2A2E);
  static const _bg    = Color(0xFFF8F8F6);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _dark, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Employés',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 18, color: _dark)),
        bottom: TabBar(
          controller: _tab,
          labelColor: _teal,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _teal,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Employés'),
            Tab(text: 'Tâches'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _EmployesTab(green: _green, teal: _teal, dark: _dark, bg: _bg),
          _TachesTab(green: _green, teal: _teal, dark: _dark, bg: _bg),
        ],
      ),
    );
  }
}

// ─── Tab Employés ─────────────────────────────────────────────────────────────

class _EmployesTab extends StatefulWidget {
  final Color green, teal, dark, bg;
  const _EmployesTab({required this.green, required this.teal, required this.dark, required this.bg});
  @override
  State<_EmployesTab> createState() => _EmployesTabState();
}

class _EmployesTabState extends State<_EmployesTab> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;
  bool _loading = true;
  List<Map<String, dynamic>> _employes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await _supa
          .from('employes')
          .select()
          .eq('uid_eleveur', _uid)
          .eq('actif', true)
          .order('created_at');

      final List<Map<String, dynamic>> result = [];
      for (final e in rows) {
        final u = await _supa
            .from('users')
            .select('uid, firstname, lastname, name_elevage, is_elevage, profile_picture_url, profile_picture_url_elevage')
            .eq('uid', e['uid_employe'] as String)
            .maybeSingle();
        result.add({...e, 'user': u});
      }
      if (mounted) setState(() { _employes = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoquer(String employeId, String nom) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Révoquer l\'accès', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text('Retirer $nom de votre élevage ?',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Révoquer', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('employes').update({'actif': false}).eq('id', employeId);
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nom a été retiré de votre élevage')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: widget.teal,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white),
        label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
        onPressed: () async {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _AddEmployeSheet(uid: _uid, teal: widget.teal, dark: widget.dark),
          );
          _load();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _employes.isEmpty
              ? _empty('Aucun employé', 'Ajoutez des membres de votre équipe.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _employes.length,
                  itemBuilder: (_, i) {
                    final e = _employes[i];
                    final u = e['user'] as Map<String, dynamic>?;
                    final nom = u == null ? 'Utilisateur inconnu'
                        : (u['is_elevage'] == true ? (u['name_elevage'] ?? '') : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}').trim();
                    final photoUrl = u == null ? null
                        : (u['is_elevage'] == true ? u['profile_picture_url_elevage'] : u['profile_picture_url']) as String?;
                    return _EmployeCard(
                      nom: nom, photoUrl: photoUrl,
                      teal: widget.teal, dark: widget.dark,
                      onRevoquer: () => _revoquer(e['id'].toString(), nom),
                    );
                  },
                ),
    );
  }
}

class _EmployeCard extends StatelessWidget {
  const _EmployeCard({required this.nom, required this.photoUrl,
      required this.teal, required this.dark, required this.onRevoquer});
  final String nom;
  final String? photoUrl;
  final Color teal, dark;
  final VoidCallback onRevoquer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: teal.withOpacity(0.12),
          backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl!) : null,
          child: photoUrl == null ? Icon(Icons.person, color: teal, size: 22) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(nom, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
              fontSize: 14, color: dark)),
        ),
        TextButton(
          onPressed: onRevoquer,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
          child: const Text('Révoquer', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
              color: Colors.red, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─── Bottom sheet : Ajouter un employé ───────────────────────────────────────

class _AddEmployeSheet extends StatefulWidget {
  final String uid;
  final Color teal, dark;
  const _AddEmployeSheet({required this.uid, required this.teal, required this.dark});
  @override
  State<_AddEmployeSheet> createState() => _AddEmployeSheetState();
}

class _AddEmployeSheetState extends State<_AddEmployeSheet> {
  final _supa = Supabase.instance.client;
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _results  = [];
  bool _loading  = true;
  bool _searching = false;

  // Catégories pôle santé à exclure
  static const _catSante = {'sante', 'veterinaire', 'vétérinaire', 'vet'};

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  Future<void> _loadAllUsers() async {
    try {
      final rows = await _supa
          .from('users')
          .select('uid, firstname, lastname, name_elevage, is_elevage, is_pro, cat_pro, profile_picture_url, profile_picture_url_elevage')
          .neq('uid', widget.uid)
          .limit(500);
      if (mounted) setState(() {
        _allUsers = List<Map<String, dynamic>>.from(rows)
            .where((u) {
              // Exclure pôle santé
              if (u['is_pro'] == true) {
                final cat = (u['cat_pro'] as String? ?? '').toLowerCase().trim();
                if (_catSante.contains(cat)) return false;
              }
              return true;
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
    setState(() => _searching = true);
    final filtered = _allUsers.where((u) {
      final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''} ${u['name_elevage'] ?? ''}'
          .toLowerCase();
      return nom.contains(query);
    }).take(15).toList();
    setState(() { _results = filtered; _searching = false; });
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
    final existing = await _supa
        .from('employes')
        .select()
        .eq('uid_eleveur', widget.uid)
        .eq('uid_employe', uid)
        .maybeSingle();

    if (existing != null) {
      if (existing['actif'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cette personne est déjà dans votre équipe.')));
        return;
      }
      await _supa.from('employes').update({'actif': true}).eq('id', existing['id']);
    } else {
      await _supa.from('employes').insert({'uid_employe': uid, 'uid_eleveur': widget.uid, 'actif': true});
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_nomUser(user)} ajouté à votre élevage ✓')));
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
          const Text('Ajouter un employé',
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
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
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
                final isPro = u['is_pro'] == true;
                final isElv = u['is_elevage'] == true;
                final badge = isPro ? 'Pro' : isElv ? 'Éleveur' : 'Particulier';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: widget.teal.withOpacity(0.12),
                    backgroundImage: photo != null ? CachedNetworkImageProvider(photo) : null,
                    child: photo == null ? Icon(Icons.person, color: widget.teal) : null,
                  ),
                  title: Text(nom.isEmpty ? 'Utilisateur' : nom,
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  subtitle: Text(badge,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: widget.teal)),
                  trailing: Icon(Icons.add_circle_outline, color: widget.teal),
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

// ─── Tab Tâches ───────────────────────────────────────────────────────────────

class _TachesTab extends StatefulWidget {
  final Color green, teal, dark, bg;
  const _TachesTab({required this.green, required this.teal, required this.dark, required this.bg});
  @override
  State<_TachesTab> createState() => _TachesTabState();
}

class _TachesTabState extends State<_TachesTab> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;
  bool _loading = true;
  List<Map<String, dynamic>> _taches  = [];
  List<Map<String, dynamic>> _employes = [];
  List<Map<String, dynamic>> _animaux  = [];
  bool _showDone = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final tachesRaw = await _supa
          .from('taches_elevage')
          .select()
          .eq('uid_eleveur', _uid)
          .order('date');

      final empsRaw = await _supa
          .from('employes')
          .select()
          .eq('uid_eleveur', _uid)
          .eq('actif', true);

      final animauxRaw = await _supa
          .from('animaux')
          .select('id, nom')
          .eq('uid_eleveur', _uid)
          .not('statut', 'in', '(sorti,decede)')
          .order('nom');

      // Resolve assignee names
      final Map<String, String> uidToNom = {};
      for (final e in empsRaw) {
        final uid = e['uid_employe'] as String;
        if (!uidToNom.containsKey(uid)) {
          final u = await _supa.from('users')
              .select('uid, firstname, lastname, name_elevage, is_elevage')
              .eq('uid', uid).maybeSingle();
          if (u != null) {
            uidToNom[uid] = u['is_elevage'] == true
                ? (u['name_elevage'] ?? 'Élevage')
                : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
          }
        }
      }

      final employes = empsRaw.map<Map<String, dynamic>>((e) => {
        ...e, 'nom': uidToNom[e['uid_employe']] ?? 'Employé',
      }).toList();

      // Résoudre les noms d'animaux
      final Map<String, String> animalNoms = {};
      for (final a in animauxRaw) {
        animalNoms[a['id'].toString()] = a['nom'] as String? ?? '—';
      }

      final taches = tachesRaw.map<Map<String, dynamic>>((t) {
        final assigneNom = t['assigne_a'] != null ? (uidToNom[t['assigne_a']] ?? 'Employé') : null;
        final animalNom = t['animal_id'] != null ? animalNoms[t['animal_id'].toString()] : null;
        return {...t, 'assigne_nom': assigneNom, 'animal_nom': animalNom};
      }).toList();

      if (mounted) setState(() {
        _taches   = taches;
        _employes = employes;
        _animaux  = List<Map<String, dynamic>>.from(animauxRaw);
        _loading  = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStatut(Map<String, dynamic> tache) async {
    final newStatut = tache['statut'] == 'fait' ? 'a_faire' : 'fait';
    await _supa.from('taches_elevage').update({'statut': newStatut}).eq('id', tache['id']);
    _load();
  }

  Future<void> _delete(Map<String, dynamic> tache) async {
    await _supa.from('taches_elevage').delete().eq('id', tache['id']);
    _load();
  }

  Future<void> _edit(Map<String, dynamic> tache) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditTacheSheet(
        tache: tache,
        employes: _employes,
        animaux: _animaux,
        teal: widget.teal, dark: widget.dark,
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final affichees = _taches.where((t) => _showDone ? t['statut'] == 'fait' : t['statut'] != 'fait').toList();

    return Scaffold(
      backgroundColor: widget.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: widget.teal,
        icon: const Icon(Icons.add_task, color: Colors.white),
        label: const Text('Nouvelle tâche', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
        onPressed: () async {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _CreateTacheSheet(
              uid: _uid, employes: _employes, animaux: _animaux,
              teal: widget.teal, dark: widget.dark,
            ),
          );
          _load();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  _FilterChip(label: 'À faire', active: !_showDone, color: widget.teal,
                      onTap: () => setState(() => _showDone = false)),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Terminées', active: _showDone, color: widget.green,
                      onTap: () => setState(() => _showDone = true)),
                ]),
              ),
              Expanded(
                child: affichees.isEmpty
                    ? _empty(_showDone ? 'Aucune tâche terminée' : 'Aucune tâche à faire',
                        _showDone ? '' : 'Appuyez sur + pour créer une tâche.')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: affichees.length,
                        itemBuilder: (_, i) => _TacheCard(
                          tache: affichees[i],
                          teal: widget.teal, dark: widget.dark,
                          onToggle: () => _toggleStatut(affichees[i]),
                          onDelete: () => _delete(affichees[i]),
                          onEdit: () => _edit(affichees[i]),
                        ),
                      ),
              ),
            ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.color, required this.onTap});
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: active ? color : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? color : Colors.grey.shade300),
      ),
      child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
          fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.grey)),
    ),
  );
}

class _TacheCard extends StatelessWidget {
  const _TacheCard({required this.tache, required this.teal, required this.dark,
      required this.onToggle, required this.onDelete, required this.onEdit});
  final Map<String, dynamic> tache;
  final Color teal, dark;
  final VoidCallback onToggle, onDelete, onEdit;

  @override
  Widget build(BuildContext context) {
    final fait = tache['statut'] == 'fait';
    final date = DateTime.tryParse(tache['date'] ?? '');
    final dateStr = date != null ? DateFormat('dd MMM', 'fr_FR').format(date) : '';
    final animalNom = tache['animal_nom'] as String?;
    final assigneNom = tache['assigne_nom'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        GestureDetector(
          onTap: onToggle,
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: fait ? teal : Colors.transparent,
              border: Border.all(color: fait ? teal : Colors.grey.shade400, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: fait ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tache['titre'] ?? '',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                    fontSize: 14, color: dark,
                    decoration: fait ? TextDecoration.lineThrough : null)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              if (dateStr.isNotEmpty) _Badge(text: '📅 $dateStr', bg: const Color(0xFFEEF5EA), fg: teal),
              if (animalNom != null) _Badge(text: '🐾 $animalNom', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1D4ED8)),
              if (assigneNom != null) _Badge(text: '👤 $assigneNom', bg: const Color(0xFFF3F4F6), fg: Colors.grey.shade700),
            ]),
            if ((tache['notes'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(tache['notes'], style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
            ],
          ]),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF6F767B)),
            onPressed: onEdit,
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: onDelete,
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
        ]),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
  );
}

// ─── Bottom sheet : Créer une tâche ──────────────────────────────────────────

class _CreateTacheSheet extends StatefulWidget {
  final String uid;
  final List<Map<String, dynamic>> employes, animaux;
  final Color teal, dark;
  const _CreateTacheSheet({required this.uid, required this.employes, required this.animaux,
      required this.teal, required this.dark});
  @override
  State<_CreateTacheSheet> createState() => _CreateTacheSheetState();
}

class _CreateTacheSheetState extends State<_CreateTacheSheet> {
  final _supa   = Supabase.instance.client;
  final _titreCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  String? _selectedAnimalId;
  String? _selectedEmployeUid;
  bool _saving = false;

  Future<void> _save() async {
    if (_titreCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final result = await _supa.from('taches_elevage').insert({
        'titre':       _titreCtrl.text.trim(),
        'uid_eleveur': widget.uid,
        'date':        _date.toIso8601String().split('T').first,
        if (_selectedAnimalId != null) 'animal_id': _selectedAnimalId,
        if (_selectedEmployeUid != null) 'assigne_a': _selectedEmployeUid,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        'statut': 'a_faire',
      }).select().single();

      if (_selectedEmployeUid != null) {
        final tacheId = result['id'];
        // Notification in-app (cloche)
        await _supa.from('notifications').insert({
          'uid':   _selectedEmployeUid,
          'type':  'tache',
          'title': 'Nouvelle tâche assignée',
          'body':  _titreCtrl.text.trim(),
          'data':  {'eleveurUid': widget.uid, 'tacheId': tacheId.toString()},
          'read':  false,
        });
        // Push FCM (best-effort)
        try {
          await FirebaseFunctions.instance
              .httpsCallable('notifyTacheAssignee')
              .call({'assigneUid': _selectedEmployeUid, 'titre': _titreCtrl.text.trim()});
        } catch (_) {}
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Nouvelle tâche',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            // Titre
            _sheetField('Titre de la tâche *', _titreCtrl, teal: widget.teal),
            const SizedBox(height: 12),
            // Date
            GestureDetector(
              onTap: () async {
                final p = await showDatePicker(
                  context: context, initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.light(primary: widget.teal)),
                    child: child!,
                  ),
                );
                if (p != null) setState(() => _date = p);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE4E7E2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 16, color: widget.teal),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd MMMM yyyy', 'fr_FR').format(_date),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            // Animal
            if (widget.animaux.isNotEmpty) ...[
              _sheetDropdown(
                hint: '🐾 Animal (optionnel)',
                value: _selectedAnimalId,
                items: widget.animaux.map((a) => DropdownMenuItem(
                  value: a['id'].toString(),
                  child: Text(a['nom'] ?? '—', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                )).toList(),
                onChanged: (v) => setState(() => _selectedAnimalId = v),
                teal: widget.teal,
              ),
              const SizedBox(height: 12),
            ],
            // Assigné à
            if (widget.employes.isNotEmpty) ...[
              _sheetDropdown(
                hint: '👤 Assigné à (optionnel)',
                value: _selectedEmployeUid,
                items: widget.employes.map((e) => DropdownMenuItem(
                  value: e['uid_employe'] as String,
                  child: Text(e['nom'] ?? '—', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                )).toList(),
                onChanged: (v) => setState(() => _selectedEmployeUid = v),
                teal: widget.teal,
              ),
              const SizedBox(height: 12),
            ],
            // Notes
            _sheetField('Notes (optionnel)', _notesCtrl, maxLines: 2, teal: widget.teal),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Créer la tâche', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sheetField(String label, TextEditingController ctrl, {int maxLines = 1, required Color teal}) =>
      TextFormField(
        controller: ctrl, maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: teal, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );

  Widget _sheetDropdown({required String hint, required String? value,
      required List<DropdownMenuItem<String>> items, required ValueChanged<String?> onChanged, required Color teal}) =>
      DropdownButtonFormField<String>(
        value: value,
        hint: Text(hint, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
        items: items,
        onChanged: onChanged,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: teal, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );
}

// ─── Bottom sheet : Modifier une tâche ───────────────────────────────────────

class _EditTacheSheet extends StatefulWidget {
  final Map<String, dynamic> tache;
  final List<Map<String, dynamic>> employes, animaux;
  final Color teal, dark;
  const _EditTacheSheet({required this.tache, required this.employes, required this.animaux,
      required this.teal, required this.dark});
  @override
  State<_EditTacheSheet> createState() => _EditTacheSheetState();
}

class _EditTacheSheetState extends State<_EditTacheSheet> {
  final _supa   = Supabase.instance.client;
  late final TextEditingController _titreCtrl;
  late final TextEditingController _notesCtrl;
  late DateTime _date;
  String? _selectedAnimalId;
  String? _selectedEmployeUid;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titreCtrl = TextEditingController(text: widget.tache['titre'] as String? ?? '');
    _notesCtrl = TextEditingController(text: widget.tache['notes'] as String? ?? '');
    _date = DateTime.tryParse(widget.tache['date'] ?? '') ?? DateTime.now();
    _selectedAnimalId = widget.tache['animal_id'] as String?;
    _selectedEmployeUid = widget.tache['assigne_a'] as String?;
    // Validate selections exist in current lists
    if (_selectedAnimalId != null &&
        !widget.animaux.any((a) => a['id'].toString() == _selectedAnimalId)) {
      _selectedAnimalId = null;
    }
    if (_selectedEmployeUid != null &&
        !widget.employes.any((e) => e['uid_employe'] == _selectedEmployeUid)) {
      _selectedEmployeUid = null;
    }
  }

  Future<void> _save() async {
    if (_titreCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await _supa.from('taches_elevage').update({
        'titre': _titreCtrl.text.trim(),
        'date':  _date.toIso8601String().split('T').first,
        'animal_id':  _selectedAnimalId,
        'assigne_a':  _selectedEmployeUid,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      }).eq('id', widget.tache['id']);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Modifier la tâche',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            _sheetField('Titre de la tâche *', _titreCtrl, teal: widget.teal),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final p = await showDatePicker(
                  context: context, initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.light(primary: widget.teal)),
                    child: child!,
                  ),
                );
                if (p != null) setState(() => _date = p);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE4E7E2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 16, color: widget.teal),
                  const SizedBox(width: 8),
                  Text(DateFormat('dd MMMM yyyy', 'fr_FR').format(_date),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.animaux.isNotEmpty) ...[
              _sheetDropdown(
                hint: '🐾 Animal (optionnel)',
                value: _selectedAnimalId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Aucun —', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                  ...widget.animaux.map((a) => DropdownMenuItem(
                    value: a['id'].toString(),
                    child: Text(a['nom'] ?? '—', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  )),
                ],
                onChanged: (v) => setState(() => _selectedAnimalId = v),
                teal: widget.teal,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.employes.isNotEmpty) ...[
              _sheetDropdown(
                hint: '👤 Assigné à (optionnel)',
                value: _selectedEmployeUid,
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Aucun —', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                  ...widget.employes.map((e) => DropdownMenuItem(
                    value: e['uid_employe'] as String,
                    child: Text(e['nom'] ?? '—', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  )),
                ],
                onChanged: (v) => setState(() => _selectedEmployeUid = v),
                teal: widget.teal,
              ),
              const SizedBox(height: 12),
            ],
            _sheetField('Notes (optionnel)', _notesCtrl, maxLines: 2, teal: widget.teal),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sheetField(String label, TextEditingController ctrl, {int maxLines = 1, required Color teal}) =>
      TextFormField(
        controller: ctrl, maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: teal, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );

  Widget _sheetDropdown({required String hint, required String? value,
      required List<DropdownMenuItem<String?>> items, required ValueChanged<String?> onChanged, required Color teal}) =>
      DropdownButtonFormField<String?>(
        value: value,
        hint: Text(hint, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
        items: items,
        onChanged: onChanged,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: teal, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );
}

// ─── Page : Mes Employeurs (vue employé) ─────────────────────────────────────

class MesEmployeursPage extends StatefulWidget {
  const MesEmployeursPage({super.key});
  @override
  State<MesEmployeursPage> createState() => _MesEmployeursPageState();
}

class _MesEmployeursPageState extends State<MesEmployeursPage> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;
  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);
  static const _bg   = Color(0xFFF8F8F6);

  bool _loading = true;
  List<Map<String, dynamic>> _employeurs = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await _supa
          .from('employes')
          .select()
          .eq('uid_employe', _uid)
          .eq('actif', true)
          .order('created_at');

      final List<Map<String, dynamic>> result = [];
      for (final e in rows) {
        final u = await _supa
            .from('users')
            .select('uid, firstname, lastname, name_elevage, is_elevage, profile_picture_url, profile_picture_url_elevage')
            .eq('uid', e['uid_eleveur'] as String)
            .maybeSingle();
        if (u != null) result.add({...e, 'user': u});
      }
      if (mounted) setState(() { _employeurs = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _nomEmployeur(Map<String, dynamic> u) {
    if (u['is_elevage'] == true) return (u['name_elevage'] as String? ?? 'Élevage').trim();
    return '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
  }

  String? _photoEmployeur(Map<String, dynamic> u) {
    if (u['is_elevage'] == true) return u['profile_picture_url_elevage'] as String?;
    return u['profile_picture_url'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _dark, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mes Employeurs',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: _employeurs.isEmpty
                  ? _empty('Aucun employeur', 'Vous n\'êtes employé dans aucun élevage.')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _employeurs.length,
                      itemBuilder: (_, i) {
                        final e = _employeurs[i];
                        final u = e['user'] as Map<String, dynamic>;
                        final nom = _nomEmployeur(u);
                        final photo = _photoEmployeur(u);
                        return _EmployeurCard(
                          nom: nom, photo: photo,
                          teal: _teal, dark: _dark,
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => EmployeurDetailPage(
                              eleveurUid: u['uid'] as String,
                              eleveurNom: nom,
                            ),
                          )),
                        );
                      },
                    ),
            ),
    );
  }
}

class _EmployeurCard extends StatelessWidget {
  final String nom;
  final String? photo;
  final Color teal, dark;
  final VoidCallback onTap;
  const _EmployeurCard({required this.nom, required this.photo,
      required this.teal, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: teal.withOpacity(0.12),
          backgroundImage: photo != null ? CachedNetworkImageProvider(photo!) : null,
          child: photo == null ? Icon(Icons.business, color: teal, size: 22) : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(nom.isEmpty ? 'Élevage' : nom,
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15, color: dark)),
        ),
        Icon(Icons.chevron_right, color: Colors.grey.shade400),
      ]),
    ),
  );
}

// ─── Page détail employeur (public — deep link depuis notifications) ───────────

class EmployeurDetailPage extends StatefulWidget {
  final String eleveurUid, eleveurNom;
  const EmployeurDetailPage({super.key, required this.eleveurUid, required this.eleveurNom});
  @override
  State<EmployeurDetailPage> createState() => _EmployeurDetailPageState();
}

class _EmployeurDetailPageState extends State<EmployeurDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;

  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);
  static const _bg   = Color(0xFFF8F8F6);

  bool _loadingTaches  = true;
  bool _loadingAnimaux = true;
  List<Map<String, dynamic>> _taches  = [];
  List<Map<String, dynamic>> _animaux = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadTaches();
    _loadAnimaux();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadTaches() async {
    if (!mounted) return;
    setState(() => _loadingTaches = true);
    try {
      final rows = await _supa
          .from('taches_elevage')
          .select()
          .eq('uid_eleveur', widget.eleveurUid)
          .eq('assigne_a', _uid)
          .order('date');

      for (final t in rows) {
        if (t['animal_id'] != null) {
          final a = await _supa.from('animaux').select('nom').eq('id', t['animal_id']).maybeSingle();
          t['animal_nom'] = a?['nom'];
        }
      }
      if (mounted) setState(() { _taches = List<Map<String, dynamic>>.from(rows); _loadingTaches = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingTaches = false);
    }
  }

  Future<void> _loadAnimaux() async {
    if (!mounted) return;
    setState(() => _loadingAnimaux = true);
    try {
      final rows = await _supa
          .from('animaux')
          .select('id, nom, espece, race, photo_url')
          .eq('uid_eleveur', widget.eleveurUid)
          .not('statut', 'in', '(sorti,decede)')
          .order('nom');
      if (mounted) setState(() { _animaux = List<Map<String, dynamic>>.from(rows); _loadingAnimaux = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingAnimaux = false);
    }
  }

  Future<void> _marquerFait(Map<String, dynamic> t) async {
    await _supa.from('taches_elevage').update({'statut': 'fait'}).eq('id', t['id']);
    _loadTaches();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _dark, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.eleveurNom,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
        bottom: TabBar(
          controller: _tab,
          labelColor: _teal,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _teal,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [Tab(text: 'Mes Tâches'), Tab(text: 'Animaux')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_buildTachesTab(), _buildAnimauxTab()],
      ),
    );
  }

  Widget _buildTachesTab() {
    if (_loadingTaches) return const Center(child: CircularProgressIndicator(color: _teal));
    return RefreshIndicator(
      onRefresh: _loadTaches,
      color: _teal,
      child: _taches.isEmpty
          ? _empty('Aucune tâche', 'Votre responsable n\'a pas encore créé de tâche pour vous.')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _taches.length,
              itemBuilder: (_, i) {
                final t = _taches[i];
                final fait = t['statut'] == 'fait';
                final date = DateTime.tryParse(t['date'] ?? '');
                final dateStr = date != null ? DateFormat('dd MMM', 'fr_FR').format(date) : '';
                final animalNom = t['animal_nom'] as String?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Row(children: [
                    GestureDetector(
                      onTap: fait ? null : () => _marquerFait(t),
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: fait ? _teal : Colors.transparent,
                          border: Border.all(color: fait ? _teal : Colors.grey.shade400, width: 1.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: fait ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t['titre'] ?? '',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                              fontSize: 14, color: _dark,
                              decoration: fait ? TextDecoration.lineThrough : null)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, children: [
                        if (dateStr.isNotEmpty) _Badge(text: '📅 $dateStr', bg: const Color(0xFFEEF5EA), fg: _teal),
                        if (animalNom != null) _Badge(text: '🐾 $animalNom', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1D4ED8)),
                      ]),
                      if ((t['notes'] as String?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(t['notes'], style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
                      ],
                    ])),
                    if (!fait) TextButton(
                      onPressed: () => _marquerFait(t),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('Fait ✓',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                );
              },
            ),
    );
  }

  Widget _buildAnimauxTab() {
    if (_loadingAnimaux) return const Center(child: CircularProgressIndicator(color: _teal));
    return RefreshIndicator(
      onRefresh: _loadAnimaux,
      color: _teal,
      child: _animaux.isEmpty
          ? _empty('Aucun animal', '')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _animaux.length,
              itemBuilder: (_, i) {
                final a = _animaux[i];
                final photo = a['photo_url'] as String?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)],
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _teal.withOpacity(0.1),
                      backgroundImage: photo != null ? CachedNetworkImageProvider(photo) : null,
                      child: photo == null ? const Icon(Icons.pets, size: 18, color: _teal) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a['nom'] ?? '—',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: _dark)),
                      Text('${a['espece'] ?? ''} · ${a['race'] ?? ''}',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
                    ])),
                  ]),
                );
              },
            ),
    );
  }
}

// ─── Helper ───────────────────────────────────────────────────────────────────

Widget _empty(String title, String subtitle) => Center(
  child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.people_outline, size: 48, color: Color(0xFFCBD5E0)),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
          fontSize: 16, color: Color(0xFF1F2A2E))),
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
      ],
    ]),
  ),
);
