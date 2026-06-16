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
//   CREATE TABLE IF NOT EXISTS tache_commentaires (
//     id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
//     tache_id    BIGINT NOT NULL,
//     uid_auteur  TEXT NOT NULL,
//     contenu     TEXT NOT NULL,
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

// SQL à exécuter une fois pour les permissions :
//   ALTER TABLE employes ADD COLUMN IF NOT EXISTS permissions JSONB DEFAULT '{}';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart'
    show speciesColor, speciesIcon, speciesLabel, kSpeciesData;
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/services/planning_service.dart';

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
  String _nomElevage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final profile = await _supa
          .from('users')
          .select('name_elevage, firstname, lastname')
          .eq('uid', _uid)
          .maybeSingle();
      _nomElevage = (profile?['name_elevage'] as String?)?.trim().isNotEmpty == true
          ? profile!['name_elevage'] as String
          : '${profile?['firstname'] ?? ''} ${profile?['lastname'] ?? ''}'.trim();

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
            builder: (_) => _AddEmployeSheet(uid: _uid, nomElevage: _nomElevage, teal: widget.teal, dark: widget.dark),
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
                      employeId: e['id'].toString(),
                      permissions: (e['permissions'] as Map<String, dynamic>?) ?? {},
                      onRevoquer: () => _revoquer(e['id'].toString(), nom),
                      onPermissionsChanged: _load,
                    );
                  },
                ),
    );
  }
}

class _EmployeCard extends StatelessWidget {
  const _EmployeCard({required this.nom, required this.photoUrl,
      required this.teal, required this.dark, required this.onRevoquer,
      required this.employeId, required this.permissions, required this.onPermissionsChanged});
  final String nom, employeId;
  final String? photoUrl;
  final Color teal, dark;
  final VoidCallback onRevoquer;
  final Map<String, dynamic> permissions;
  final VoidCallback onPermissionsChanged;

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
        IconButton(
          icon: Icon(Icons.tune_rounded, color: teal, size: 20),
          tooltip: 'Gérer les accès',
          onPressed: () async {
            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _PermissionsSheet(
                employeId: employeId,
                nom: nom,
                permissions: permissions,
                teal: teal,
              ),
            );
            onPermissionsChanged();
          },
        ),
        TextButton(
          onPressed: onRevoquer,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
          child: const Text('Révoquer', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
              color: Colors.red, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─── Feuille de permissions (côté employeur) ─────────────────────────────────

class _PermissionsSheet extends StatefulWidget {
  final String employeId, nom;
  final Map<String, dynamic> permissions;
  final Color teal;
  const _PermissionsSheet({required this.employeId, required this.nom,
      required this.permissions, required this.teal});
  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  final _supa = Supabase.instance.client;
  late bool _modifierAnimaux;
  late bool _gererTaches;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _modifierAnimaux = widget.permissions['modifier_animaux'] == true;
    _gererTaches     = widget.permissions['gerer_taches']     == true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _supa.from('employes').update({
        'permissions': {
          'modifier_animaux': _modifierAnimaux,
          'gerer_taches':     _gererTaches,
        },
      }).eq('id', widget.employeId);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('Accès de ${widget.nom}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Définissez ce que cet employé peut faire.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
        const SizedBox(height: 16),
        _PermSwitch(
          icon: Icons.pets_outlined,
          title: 'Modifier les fiches animaux',
          subtitle: 'Peut éditer les informations, poids, santé',
          value: _modifierAnimaux,
          teal: widget.teal,
          onChanged: (v) => setState(() => _modifierAnimaux = v),
        ),
        const Divider(height: 1, indent: 56),
        _PermSwitch(
          icon: Icons.task_alt,
          title: 'Gérer les tâches',
          subtitle: 'Peut créer et modifier ses propres tâches',
          value: _gererTaches,
          teal: widget.teal,
          onChanged: (v) => setState(() => _gererTaches = v),
        ),
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
    );
  }
}

class _PermSwitch extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final Color teal;
  final ValueChanged<bool> onChanged;
  const _PermSwitch({required this.icon, required this.title, required this.subtitle,
      required this.value, required this.teal, required this.onChanged});

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: Icon(icon, color: value ? teal : Colors.grey.shade400),
    title: Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
    subtitle: Text(subtitle, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
    value: value,
    activeColor: teal,
    onChanged: onChanged,
    contentPadding: EdgeInsets.zero,
  );
}

// ─── Bottom sheet : Ajouter un employé ───────────────────────────────────────

class _AddEmployeSheet extends StatefulWidget {
  final String uid;
  final String nomElevage;
  final Color teal, dark;
  const _AddEmployeSheet({required this.uid, required this.nomElevage, required this.teal, required this.dark});
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

    // Notification in-app (cloche)
    final nomElevage = widget.nomElevage;
    await _supa.from('notifications').insert({
      'uid':   uid,
      'type':  'employee_invite',
      'title': 'Invitation à rejoindre un élevage',
      'body':  'Vous avez été ajouté à l\'équipe de $nomElevage',
      'data':  {'eleveurUid': widget.uid, 'eleveurNom': nomElevage},
      'read':  false,
    });
    // Push FCM (best-effort)
    try {
      await FirebaseFunctions.instance
          .httpsCallable('notifyEmployeeAdded')
          .call({'employeUid': uid, 'nomElevage': nomElevage});
    } catch (_) {}

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
  List<Map<String, dynamic>> _taches      = [];
  List<Map<String, dynamic>> _planTaches  = [];
  List<Map<String, dynamic>> _employes    = [];
  List<Map<String, dynamic>> _animaux     = [];
  bool _showDone = false;

  // Liste unifiée triée par date
  List<Map<String, dynamic>> get _toutesLesTaches {
    final manuel = _taches.map((t) => {
      ...t,
      '_source': 'manuel',
      '_sort_date': (t['date'] as String?) ?? '',
    }).toList();
    final proto = _planTaches.map((t) => {
      ...t,
      '_source': 'protocole',
      '_sort_date': (t['date_prevue'] as String?) ?? '',
    }).toList();
    final all = [...manuel, ...proto];
    all.sort((a, b) {
      final da = DateTime.tryParse(a['_sort_date'] as String? ?? '') ?? DateTime(2099);
      final db = DateTime.tryParse(b['_sort_date'] as String? ?? '') ?? DateTime(2099);
      return da.compareTo(db);
    });
    return all;
  }

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
        final animauxIds = (t['animaux_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        final resolvedAnimalNoms = animauxIds.map((id) => animalNoms[id] ?? id).toList();
        return {...t, 'assigne_nom': assigneNom, 'animal_nom': animalNom, 'animal_noms': resolvedAnimalNoms};
      }).toList();

      // Charger les plan_taches assignées aux employés
      List<Map<String, dynamic>> planTaches = [];
      try {
        final ptRaw = await _supa
            .from('plan_taches')
            .select('*, plans_actifs(reference_label)')
            .eq('uid_eleveur', _uid)
            .not('assigned_to', 'is', null)
            .not('statut', 'eq', 'fait')
            .order('date_prevue');
        planTaches = List<Map<String, dynamic>>.from(ptRaw);
        // Enrichir avec le nom de l'assigné
        for (final pt in planTaches) {
          final assignedTo = pt['assigned_to'] as String?;
          if (assignedTo != null && uidToNom.containsKey(assignedTo)) {
            pt['assigne_nom'] = uidToNom[assignedTo];
          } else if (assignedTo != null) {
            final u = await _supa.from('users')
                .select('firstname, lastname, name_elevage, is_elevage')
                .eq('uid', assignedTo).maybeSingle();
            if (u != null) {
              pt['assigne_nom'] = u['is_elevage'] == true
                  ? (u['name_elevage'] ?? 'Employé')
                  : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
            }
          }
        }
      } catch (_) {}

      if (mounted) setState(() {
        _taches     = taches;
        _planTaches = planTaches;
        _employes   = employes;
        _animaux    = List<Map<String, dynamic>>.from(animauxRaw);
        _loading    = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStatut(Map<String, dynamic> tache) async {
    final id = tache['id'];
    final newStatut = tache['statut'] == 'fait' ? 'a_faire' : 'fait';
    setState(() {
      final idx = _taches.indexWhere((t) => t['id'] == id);
      if (idx != -1) _taches[idx] = {..._taches[idx], 'statut': newStatut};
    });
    await _supa.from('taches_elevage').update({'statut': newStatut}).eq('id', id);
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

  Future<void> _togglePlanTache(Map<String, dynamic> t) async {
    await _supa.from('plan_taches').update({'statut': 'fait'}).eq('id', t['id']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final toutes = _toutesLesTaches;
    final affichees = _showDone
        ? toutes.where((t) => t['statut'] == 'fait').toList()
        : toutes.where((t) => t['statut'] != 'fait').toList();

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
                        itemBuilder: (ctx, i) {
                          final t = affichees[i];
                          if (t['_source'] == 'protocole') {
                            return _buildProtoCardEleveur(t);
                          }
                          return _TacheCard(
                            tache: t,
                            teal: widget.teal, dark: widget.dark,
                            onToggle: () => _toggleStatut(t),
                            onDelete: () => _delete(t),
                            onEdit: () => _edit(t),
                            onTap: () => Navigator.push(ctx, MaterialPageRoute(
                              builder: (_) => TacheDetailPage(tache: t),
                            )).then((_) => _load()),
                          );
                        },
                      ),
              ),
            ]),
    );
  }

  Widget _buildProtoCardEleveur(Map<String, dynamic> t) {
    final date     = DateTime.tryParse(t['date_prevue'] as String? ?? '');
    final dateStr  = date != null ? DateFormat('dd MMM', 'fr_FR').format(date) : '';
    final ref      = (t['plans_actifs'] as Map<String, dynamic>?)?['reference_label'] as String?;
    final assigneNom = t['assigne_nom'] as String?;
    final typeActe = t['type_acte']?.toString() ?? '';
    final emoji = switch (typeActe) {
      'vermifuge'       => '💊',
      'vaccination'     => '💉',
      'antiparasitaire' => '🛡️',
      'traitement'      => '🩺',
      'visite'          => '🏥',
      'nettoyage'       => '🧹',
      'promenade'       => '🦮',
      'socialisation'   => '🐾',
      _                 => '📋',
    };
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
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(6)),
              child: const Text('Protocole', style: TextStyle(
                  fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8))),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t['label'] as String? ?? '',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                      fontSize: 13, color: widget.dark),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            if (dateStr.isNotEmpty) _Badge(text: '📅 $dateStr', bg: const Color(0xFFEEF5EA), fg: widget.teal),
            if (animalNom != null) _Badge(text: '🐾 $animalNom', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1D4ED8)),
            if (assigneNom != null) _Badge(text: '👤 $assigneNom', bg: const Color(0xFFF5F5F5), fg: Colors.grey.shade600),
            if (ref != null) _Badge(text: ref, bg: const Color(0xFFF0F4FF), fg: const Color(0xFF1D4ED8)),
          ]),
        ])),
        TextButton(
          onPressed: () => _togglePlanTache(t),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: Text('Fait ✓', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
              color: widget.teal, fontWeight: FontWeight.w600)),
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
      required this.onToggle, required this.onDelete, required this.onEdit, this.onTap});
  final Map<String, dynamic> tache;
  final Color teal, dark;
  final VoidCallback onToggle, onDelete, onEdit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fait = tache['statut'] == 'fait';
    final date = DateTime.tryParse(tache['date'] ?? '');
    final dateStr = date != null ? DateFormat('dd MMM', 'fr_FR').format(date) : '';
    final heureRaw = tache['heure'] as String?;
    final heureStr = heureRaw != null ? heureRaw.substring(0, 5) : null;
    final animalNoms = (tache['animal_noms'] as List<dynamic>?)?.cast<String>() ?? [];
    final animalNomLegacy = tache['animal_nom'] as String?;
    final assigneNom = tache['assigne_nom'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (dateStr.isNotEmpty) _Badge(text: '📅 $dateStr', bg: const Color(0xFFEEF5EA), fg: teal),
              if (heureStr != null) _Badge(text: '🕐 $heureStr', bg: const Color(0xFFFFF8E1), fg: const Color(0xFFE65100)),
              for (final nom in animalNoms) _Badge(text: '🐾 $nom', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1D4ED8)),
              if (animalNoms.isEmpty && animalNomLegacy != null)
                _Badge(text: '🐾 $animalNomLegacy', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1D4ED8)),
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
    ));
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
  final _supa      = Supabase.instance.client;
  final _titreCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date    = DateTime.now();
  TimeOfDay? _heure;
  final Set<String> _selectedAnimalIds = {};
  String? _selectedEmployeUid;
  bool _saving = false;

  // ── Récurrence ─────────────────────────────────────────────────────────────
  bool _recurrent          = false;
  String _recurrence       = 'quotidien'; // 'quotidien' | 'jours_semaine'
  DateTime? _dateFin;
  final Set<int> _joursSemaine = {}; // 1=Lun … 7=Dim

  static const _joursLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  List<DateTime> get _datesGenerees {
    if (!_recurrent || _dateFin == null) return [_date];
    final result = <DateTime>[];
    var cur = _date;
    while (!cur.isAfter(_dateFin!)) {
      if (_recurrence == 'quotidien' ||
          (_recurrence == 'jours_semaine' && _joursSemaine.contains(cur.weekday))) {
        result.add(cur);
      }
      cur = cur.add(const Duration(days: 1));
    }
    return result;
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Galey'))));

  Future<void> _save() async {
    if (_titreCtrl.text.trim().isEmpty) return;
    final dates = _datesGenerees;
    if (dates.isEmpty) { _snack('Aucun jour dans la période.'); return; }
    setState(() => _saving = true);
    try {
      final heureStr = _heure != null
          ? '${_heure!.hour.toString().padLeft(2, '0')}:${_heure!.minute.toString().padLeft(2, '0')}:00'
          : null;
      final titre = _titreCtrl.text.trim();
      final basePayload = <String, dynamic>{
        'titre':       titre,
        'uid_eleveur': widget.uid,
        if (heureStr != null) 'heure': heureStr,
        if (_selectedAnimalIds.isNotEmpty) 'animaux_ids': _selectedAnimalIds.toList(),
        if (_selectedEmployeUid != null) 'assigne_a': _selectedEmployeUid,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        'statut': 'a_faire',
      };

      for (int i = 0; i < dates.length; i++) {
        final result = await _supa.from('taches_elevage').insert({
          ...basePayload,
          'date': dates[i].toIso8601String().split('T').first,
        }).select().single();

        // Notifier l'employé seulement pour la 1ère occurrence
        if (i == 0 && _selectedEmployeUid != null) {
          final tacheId = result['id'];
          await _supa.from('notifications').insert({
            'uid':   _selectedEmployeUid,
            'type':  'tache',
            'title': 'Nouvelle tâche assignée',
            'body':  dates.length > 1 ? '$titre (${dates.length} occurrences)' : titre,
            'data':  {'eleveurUid': widget.uid, 'tacheId': tacheId.toString()},
            'read':  false,
          });
          try {
            await FirebaseFunctions.instance
                .httpsCallable('notifyTacheAssignee')
                .call({'assigneUid': _selectedEmployeUid, 'titre': titre});
          } catch (_) {}
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack('Erreur : $e');
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
            // Heure
            GestureDetector(
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _heure ?? TimeOfDay.now(),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.light(primary: widget.teal)),
                    child: child!,
                  ),
                );
                if (t != null) setState(() => _heure = t);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE4E7E2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.access_time_outlined, size: 16, color: widget.teal),
                  const SizedBox(width: 8),
                  Text(
                    _heure != null ? _heure!.format(context) : 'Heure (optionnel)',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        color: _heure != null ? const Color(0xFF1F2A2E) : const Color(0xFF6F767B)),
                  ),
                  const Spacer(),
                  if (_heure != null) GestureDetector(
                    onTap: () => setState(() => _heure = null),
                    child: const Icon(Icons.close, size: 16, color: Color(0xFF6F767B)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            // Animaux (multi-select)
            if (widget.animaux.isNotEmpty) ...[
              GestureDetector(
                onTap: () async {
                  final sel = Set<String>.from(_selectedAnimalIds);
                  await showDialog(
                    context: context,
                    builder: (ctx) => StatefulBuilder(
                      builder: (ctx, setS) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('Animaux concernés',
                            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView(shrinkWrap: true, children: widget.animaux.map((a) {
                            final id = a['id'].toString();
                            return CheckboxListTile(
                              value: sel.contains(id),
                              activeColor: widget.teal,
                              dense: true,
                              title: Text(a['nom'] ?? '—',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                              onChanged: (v) => setS(() => v == true ? sel.add(id) : sel.remove(id)),
                            );
                          }).toList()),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: widget.teal),
                            onPressed: () { setState(() => _selectedAnimalIds..clear()..addAll(sel)); Navigator.pop(ctx); },
                            child: const Text('Valider', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE4E7E2)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.pets_outlined, size: 16, color: widget.teal),
                      const SizedBox(width: 8),
                      Text(_selectedAnimalIds.isEmpty ? 'Animaux concernés (optionnel)' : '${_selectedAnimalIds.length} animal(aux) sélectionné(s)',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                              color: _selectedAnimalIds.isEmpty ? const Color(0xFF6F767B) : const Color(0xFF1F2A2E))),
                    ]),
                    if (_selectedAnimalIds.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, runSpacing: 4, children: _selectedAnimalIds.map((id) {
                        final a = widget.animaux.firstWhere((a) => a['id'].toString() == id, orElse: () => {});
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: widget.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(a['nom'] ?? id, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: widget.teal, fontWeight: FontWeight.w600)),
                        );
                      }).toList()),
                    ],
                  ]),
                ),
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
            const SizedBox(height: 16),

            // ── Récurrence ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E7E2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.repeat, size: 16, color: widget.teal),
                  const SizedBox(width: 8),
                  const Text('Répétition',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                  const Spacer(),
                  Switch(
                    value: _recurrent,
                    activeColor: widget.teal,
                    onChanged: (v) => setState(() => _recurrent = v),
                  ),
                ]),
                if (_recurrent) ...[
                  const SizedBox(height: 12),
                  // Type de récurrence
                  Row(children: [
                    _recChip('Quotidien', 'quotidien'),
                    const SizedBox(width: 8),
                    _recChip('Jours sélectifs', 'jours_semaine'),
                  ]),
                  const SizedBox(height: 12),
                  // Jours de la semaine (si jours_semaine)
                  if (_recurrence == 'jours_semaine') ...[
                    Wrap(spacing: 6, children: List.generate(7, (i) {
                      final day = i + 1;
                      final sel = _joursSemaine.contains(day);
                      return GestureDetector(
                        onTap: () => setState(() => sel ? _joursSemaine.remove(day) : _joursSemaine.add(day)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: sel ? widget.teal : Colors.white,
                            border: Border.all(color: sel ? widget.teal : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: Text(_joursLabels[i],
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white : Colors.grey.shade500))),
                        ),
                      );
                    })),
                    const SizedBox(height: 12),
                  ],
                  // Date de fin
                  GestureDetector(
                    onTap: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: _dateFin ?? _date.add(const Duration(days: 7)),
                        firstDate: _date,
                        lastDate: _date.add(const Duration(days: 365)),
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.light(primary: widget.teal)),
                          child: child!,
                        ),
                      );
                      if (p != null) setState(() => _dateFin = p);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _dateFin != null ? widget.teal : const Color(0xFFE4E7E2)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.event_repeat_outlined, size: 16, color: widget.teal),
                        const SizedBox(width: 8),
                        Text(
                          _dateFin != null
                              ? 'Jusqu\'au ${DateFormat('dd MMMM yyyy', 'fr_FR').format(_dateFin!)}'
                              : 'Date de fin *',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                              color: _dateFin != null ? const Color(0xFF1F2A2E) : const Color(0xFF6F767B)),
                        ),
                      ]),
                    ),
                  ),
                  // Résumé
                  if (_dateFin != null) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (_) {
                      final n = _datesGenerees.length;
                      return Text('→ $n occurrence${n > 1 ? 's' : ''} créée${n > 1 ? 's' : ''}',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                              color: widget.teal, fontWeight: FontWeight.w600));
                    }),
                  ],
                ],
              ]),
            ),
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
                    : Text(
                        _recurrent && _dateFin != null && _datesGenerees.length > 1
                            ? 'Créer ${_datesGenerees.length} tâches'
                            : 'Créer la tâche',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _recChip(String label, String value) {
    final sel = _recurrence == value;
    return GestureDetector(
      onTap: () => setState(() => _recurrence = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? widget.teal : Colors.white,
          border: Border.all(color: sel ? widget.teal : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
            fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
            color: sel ? Colors.white : Colors.grey.shade600)),
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
  TimeOfDay? _heure;
  late Set<String> _selectedAnimalIds;
  String? _selectedEmployeUid;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titreCtrl = TextEditingController(text: widget.tache['titre'] as String? ?? '');
    _notesCtrl = TextEditingController(text: widget.tache['notes'] as String? ?? '');
    _date = DateTime.tryParse(widget.tache['date'] ?? '') ?? DateTime.now();
    final heureRaw = widget.tache['heure'] as String?;
    if (heureRaw != null) {
      final parts = heureRaw.split(':');
      _heure = TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
    }
    final ids = (widget.tache['animaux_ids'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? {};
    _selectedAnimalIds = ids.where((id) => widget.animaux.any((a) => a['id'].toString() == id)).toSet();
    _selectedEmployeUid = widget.tache['assigne_a'] as String?;
    if (_selectedEmployeUid != null &&
        !widget.employes.any((e) => e['uid_employe'] == _selectedEmployeUid)) {
      _selectedEmployeUid = null;
    }
  }

  Future<void> _save() async {
    if (_titreCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final heureStr = _heure != null
        ? '${_heure!.hour.toString().padLeft(2, '0')}:${_heure!.minute.toString().padLeft(2, '0')}:00'
        : null;
    try {
      await _supa.from('taches_elevage').update({
        'titre': _titreCtrl.text.trim(),
        'date':  _date.toIso8601String().split('T').first,
        'heure': heureStr,
        'animaux_ids': _selectedAnimalIds.toList(),
        'animal_id':  null,
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
            // Heure
            GestureDetector(
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _heure ?? TimeOfDay.now(),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.light(primary: widget.teal)),
                    child: child!,
                  ),
                );
                if (t != null) setState(() => _heure = t);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE4E7E2)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.access_time_outlined, size: 16, color: widget.teal),
                  const SizedBox(width: 8),
                  Text(
                    _heure != null ? _heure!.format(context) : 'Heure (optionnel)',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        color: _heure != null ? const Color(0xFF1F2A2E) : const Color(0xFF6F767B)),
                  ),
                  const Spacer(),
                  if (_heure != null) GestureDetector(
                    onTap: () => setState(() => _heure = null),
                    child: const Icon(Icons.close, size: 16, color: Color(0xFF6F767B)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.animaux.isNotEmpty) ...[
              GestureDetector(
                onTap: () async {
                  final sel = Set<String>.from(_selectedAnimalIds);
                  await showDialog(
                    context: context,
                    builder: (ctx) => StatefulBuilder(
                      builder: (ctx, setS) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('Animaux concernés',
                            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView(shrinkWrap: true, children: widget.animaux.map((a) {
                            final id = a['id'].toString();
                            return CheckboxListTile(
                              value: sel.contains(id),
                              activeColor: widget.teal,
                              dense: true,
                              title: Text(a['nom'] ?? '—',
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                              onChanged: (v) => setS(() => v == true ? sel.add(id) : sel.remove(id)),
                            );
                          }).toList()),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: widget.teal),
                            onPressed: () { setState(() => _selectedAnimalIds..clear()..addAll(sel)); Navigator.pop(ctx); },
                            child: const Text('Valider', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE4E7E2)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.pets_outlined, size: 16, color: widget.teal),
                      const SizedBox(width: 8),
                      Text(_selectedAnimalIds.isEmpty ? 'Animaux concernés (optionnel)' : '${_selectedAnimalIds.length} animal(aux) sélectionné(s)',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                              color: _selectedAnimalIds.isEmpty ? const Color(0xFF6F767B) : const Color(0xFF1F2A2E))),
                    ]),
                    if (_selectedAnimalIds.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, runSpacing: 4, children: _selectedAnimalIds.map((id) {
                        final a = widget.animaux.firstWhere((a) => a['id'].toString() == id, orElse: () => {});
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: widget.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(a['nom'] ?? id, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: widget.teal, fontWeight: FontWeight.w600)),
                        );
                      }).toList()),
                    ],
                  ]),
                ),
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
                        final perms = (e['permissions'] as Map<String, dynamic>?) ?? {};
                        return _EmployeurCard(
                          nom: nom, photo: photo,
                          teal: _teal, dark: _dark,
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => EmployeurDetailPage(
                              eleveurUid: u['uid'] as String,
                              eleveurNom: nom,
                              permissions: perms,
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
  final Map<String, dynamic> permissions;
  const EmployeurDetailPage({
    super.key,
    required this.eleveurUid,
    required this.eleveurNom,
    this.permissions = const {},
  });
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

  bool _loadingTaches     = true;
  bool _loadingPlanTaches = true;
  List<Map<String, dynamic>> _taches     = [];
  List<Map<String, dynamic>> _planTaches = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadTaches();
    _loadPlanTaches();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadPlanTaches() async {
    if (!mounted) return;
    setState(() => _loadingPlanTaches = true);
    try {
      final rows = await _supa
          .from('plan_taches')
          .select('*, plans_actifs(reference_label)')
          .eq('uid_eleveur', widget.eleveurUid)
          .eq('assigned_to', _uid)
          .neq('statut', 'fait')
          .order('date_prevue');
      if (mounted) setState(() {
        _planTaches = List<Map<String, dynamic>>.from(rows);
        _loadingPlanTaches = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPlanTaches = false);
    }
  }

  Future<void> _marquerPlanTacheFait(Map<String, dynamic> t) async {
    try {
      await PlanningService.validerTache(
        t['id'] as String,
        validateurUid: _uid,
        tacheData: t,
        insertRegistre: false,
      );
      _loadPlanTaches();
      final moi = await _supa.from('users')
          .select('firstname, lastname, name_elevage, is_elevage')
          .eq('uid', _uid).maybeSingle();
      final nomEmploye = moi == null ? 'Votre employé'
          : moi['is_elevage'] == true
              ? (moi['name_elevage'] ?? 'Votre employé')
              : '${moi['firstname'] ?? ''} ${moi['lastname'] ?? ''}'.trim();
      await _supa.from('notifications').insert({
        'uid':   widget.eleveurUid,
        'type':  'tache_validee',
        'title': 'Tâche de protocole validée ✓',
        'body':  '$nomEmploye a terminé : ${t['label']}',
        'data':  {'tacheId': t['id'].toString(), 'eleveurUid': widget.eleveurUid},
        'read':  false,
      });
    } catch (_) {}
  }

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

  Future<void> _marquerFait(Map<String, dynamic> t) async {
    await _supa.from('taches_elevage').update({'statut': 'fait'}).eq('id', t['id']);

    // Notifier l'employeur
    try {
      final moi = await _supa.from('users')
          .select('firstname, lastname, name_elevage, is_elevage')
          .eq('uid', _uid).maybeSingle();
      final nomEmploye = moi != null
          ? (moi['is_elevage'] == true
              ? (moi['name_elevage'] ?? 'Votre employé')
              : '${moi['firstname'] ?? ''} ${moi['lastname'] ?? ''}'.trim())
          : 'Votre employé';
      await _supa.from('notifications').insert({
        'uid':   widget.eleveurUid,
        'type':  'tache_validee',
        'title': 'Tâche validée ✓',
        'body':  '$nomEmploye a terminé : ${t['titre']}',
        'data':  {'tacheId': t['id'].toString(), 'eleveurUid': widget.eleveurUid},
        'read':  false,
      });
    } catch (_) {}

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
        children: [
          _buildTachesTab(),
          _AnimauxEmployeTab(
            eleveurUid: widget.eleveurUid,
            canEditAnimaux: widget.permissions['modifier_animaux'] == true,
          ),
        ],
      ),
    );
  }

  // ── Vue unifiée manuelles + protocoles ──────────────────────────────────────

  List<Map<String, dynamic>> get _toutesLesTaches {
    final manuel = _taches.map((t) => {
      ...t,
      '_source': 'manuel',
      '_sort_date': t['date'] as String? ?? '',
    }).toList();
    final proto = _planTaches.map((t) => {
      ...t,
      '_source': 'protocole',
      '_sort_date': t['date_prevue'] as String? ?? '',
    }).toList();
    final all = [...manuel, ...proto];
    all.sort((a, b) {
      final da = DateTime.tryParse(a['_sort_date'] as String? ?? '') ?? DateTime(2099);
      final db = DateTime.tryParse(b['_sort_date'] as String? ?? '') ?? DateTime(2099);
      return da.compareTo(db);
    });
    return all;
  }

  Widget _buildTachesTab() {
    final canGererTaches = widget.permissions['gerer_taches'] == true;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final loading = _loadingTaches || _loadingPlanTaches;
    if (loading) return const Center(child: CircularProgressIndicator(color: _teal));

    final all = _toutesLesTaches;

    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: canGererTaches ? FloatingActionButton.extended(
        backgroundColor: _teal,
        icon: const Icon(Icons.add_task, color: Colors.white),
        label: const Text('Nouvelle tâche', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
        onPressed: () async {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _CreateTacheSheet(
              uid: widget.eleveurUid,
              employes: [{'uid_employe': uid, 'nom': 'Moi'}],
              animaux: const [],
              teal: _teal, dark: _dark,
            ),
          );
          _loadTaches();
        },
      ) : null,
      body: RefreshIndicator(
        onRefresh: () async { await _loadTaches(); await _loadPlanTaches(); },
        color: _teal,
        child: all.isEmpty
            ? _empty('Aucune tâche', 'Votre responsable n\'a pas encore créé de tâche pour vous.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: all.length,
                itemBuilder: (ctx, i) {
                  final t      = all[i];
                  final source = t['_source'] as String;
                  if (source == 'protocole') {
                    return _buildProtoCard(t);
                  } else {
                    return _buildManuelCard(ctx, t);
                  }
                },
              ),
      ),
    );
  }

  Widget _buildManuelCard(BuildContext ctx, Map<String, dynamic> t) {
    final fait      = t['statut'] == 'fait';
    final date      = DateTime.tryParse(t['date'] as String? ?? '');
    final dateStr   = date != null ? DateFormat('dd MMM', 'fr_FR').format(date) : '';
    final animalNom = t['animal_nom'] as String?;
    return GestureDetector(
      onTap: () => Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => TacheDetailPage(tache: t),
      )).then((_) => _loadTaches()),
      child: Container(
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
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Tâche', style: TextStyle(
                    fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w600,
                    color: Color(0xFF0C5C6C))),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(t['titre'] as String? ?? '',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                        fontSize: 14, color: _dark,
                        decoration: fait ? TextDecoration.lineThrough : null),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              if (dateStr.isNotEmpty) _Badge(text: '📅 $dateStr', bg: const Color(0xFFEEF5EA), fg: _teal),
              if (animalNom != null) _Badge(text: '🐾 $animalNom', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1D4ED8)),
            ]),
            if ((t['notes'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(t['notes'] as String, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
            ],
          ])),
          if (!fait) TextButton(
            onPressed: () => _marquerFait(t),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Fait ✓', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
          ),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFFCBD5E0)),
        ]),
      ),
    );
  }

  Widget _buildProtoCard(Map<String, dynamic> t) {
    final date    = DateTime.tryParse(t['date_prevue'] as String? ?? '');
    final dateStr = date != null ? DateFormat('dd MMM', 'fr_FR').format(date) : '';
    final ref     = (t['plans_actifs'] as Map<String, dynamic>?)?['reference_label'] as String?;
    final typeActe = t['type_acte']?.toString() ?? '';
    final emoji = switch (typeActe) {
      'vermifuge'       => '💊',
      'vaccination'     => '💉',
      'antiparasitaire' => '🛡️',
      'traitement'      => '🩺',
      'visite'          => '🏥',
      'toilettage'      => '🛁',
      'peignage'        => '🪮',
      'nettoyage'       => '🧹',
      'promenade'       => '🦮',
      'socialisation'   => '🐾',
      _                 => '📋',
    };
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
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: _teal.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Protocole', style: TextStyle(
                  fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w600,
                  color: Color(0xFF1D4ED8))),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t['label'] as String? ?? '',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: _dark),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            if (dateStr.isNotEmpty) _Badge(text: '📅 $dateStr', bg: const Color(0xFFEEF5EA), fg: _teal),
            if (animalNom != null) _Badge(text: '🐾 $animalNom', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1D4ED8)),
            if (ref != null) _Badge(text: ref, bg: const Color(0xFFF0F4FF), fg: const Color(0xFF1D4ED8)),
          ]),
        ])),
        TextButton(
          onPressed: () => _marquerPlanTacheFait(t),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: const Text('Fait ✓', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

}

// ─── Tab animaux employé (Reproducteurs / Bébés / Tous + filtres) ─────────────

class _AnimauxEmployeTab extends StatefulWidget {
  final String eleveurUid;
  final bool canEditAnimaux;
  const _AnimauxEmployeTab({required this.eleveurUid, this.canEditAnimaux = false});
  @override
  State<_AnimauxEmployeTab> createState() => _AnimauxEmployeTabState();
}

class _AnimauxEmployeTabState extends State<_AnimauxEmployeTab> {
  static const _teal = Color(0xFF0C5C6C);

  final _supa       = Supabase.instance.client;
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<Map<String, dynamic>> _all = [];

  int _subTab = 0; // 0=Tous, 1=Reproducteurs, 2=Bébés

  String? _filterEspece;
  String? _filterSexe;
  String? _filterRace;
  String _search = '';

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await _supa
          .from('animaux')
          .select('id, nom, espece, race, sexe, photo_url, identification, reproducteur, portee_id, date_naissance')
          .eq('uid_eleveur', widget.eleveurUid)
          .not('statut', 'in', '(sorti,decede)')
          .order('nom');
      if (mounted) setState(() { _all = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _all;
    if (_subTab == 1) {
      list = list.where((a) => a['reproducteur'] == true).toList();
    } else if (_subTab == 2) {
      list = list.where((a) {
        final p = a['portee_id'] as String? ?? '';
        return p.isNotEmpty && a['reproducteur'] != true;
      }).toList();
    }
    if (_filterEspece != null) {
      list = list.where((a) => (a['espece'] as String? ?? '') == _filterEspece).toList();
    }
    if (_filterSexe != null) {
      list = list.where((a) => (a['sexe'] as String? ?? '') == _filterSexe).toList();
    }
    if (_filterRace != null) {
      list = list.where((a) => (a['race'] as String? ?? '') == _filterRace).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((a) {
        final nom  = (a['nom'] as String? ?? '').toLowerCase();
        final puce = (a['identification'] as String? ?? '').toLowerCase();
        return nom.contains(q) || puce.contains(q);
      }).toList();
    }
    return list;
  }

  int get _activeFilterCount {
    int n = 0;
    if (_filterEspece != null) n++;
    if (_filterSexe   != null) n++;
    if (_filterRace   != null) n++;
    return n;
  }

  List<String> get _availableRaces => _all
      .where((a) => _filterEspece == null || (a['espece'] as String? ?? '') == _filterEspece)
      .map((a) => a['race'] as String? ?? '')
      .where((r) => r.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  Widget _buildPorteeGroupedView(List<Map<String, dynamic>> docs) {
    final fmt = DateFormat('dd/MM/yyyy', 'fr_FR');
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final d in docs) {
      final pid = (d['portee_id'] as String?) ?? '';
      if (pid.isEmpty) continue;
      groups.putIfAbsent(pid, () => []).add(d);
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(groups[a]!.first['date_naissance'] as String? ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(groups[b]!.first['date_naissance'] as String? ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: sortedKeys.length,
      itemBuilder: (_, gi) {
        final pid     = sortedKeys[gi];
        final members = groups[pid]!;
        final first   = members.first;
        final dn      = DateTime.tryParse(first['date_naissance'] as String? ?? '');
        final race    = (first['race']   as String?) ?? '';
        final espece  = (first['espece'] as String?) ?? '';

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (gi > 0) const SizedBox(height: 20),
          // Header portée
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _teal.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.diversity_3, size: 18, color: _teal),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    ['Portée', if (race.isNotEmpty) race, if (espece.isNotEmpty) '· ${speciesLabel(espece)}'].join(' '),
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal),
                  ),
                  if (dn != null)
                    Text('Nés le ${fmt.format(dn)}',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF5F9EAA))),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${members.length}',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal)),
              ),
            ]),
          ),
          // Grille bébés
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.68,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: members.length,
            itemBuilder: (_, i) => _EmployeAnimalCard(
              data: members[i],
              eleveurUid: widget.eleveurUid,
              canEdit: widget.canEditAnimaux,
            ),
          ),
        ]);
      },
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheetE(
        filterEspece: _filterEspece,
        filterSexe:   _filterSexe,
        filterRace:   _filterRace,
        availableRaces: _availableRaces,
        onApply: (espece, sexe, race) => setState(() {
          _filterEspece = espece;
          _filterSexe   = sexe;
          _filterRace   = race;
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));
    final filtered       = _filtered;
    final hasFilter      = _activeFilterCount > 0;

    return RefreshIndicator(
      onRefresh: _load,
      color: _teal,
      child: Column(children: [
        // ── Recherche + filtre ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v.trim()),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Nom ou numéro de puce…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); },
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: Icon(Icons.tune_rounded, color: hasFilter ? _teal : Colors.grey.shade600),
                  onPressed: _openFilterSheet,
                ),
                if (hasFilter)
                  Positioned(
                    top: 6, right: 6,
                    child: Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ]),
        ),
        // ── Sub-tabs ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _SubTabChip(label: 'Tous', active: _subTab == 0,
                  onTap: () => setState(() => _subTab = 0)),
              const SizedBox(width: 8),
              _SubTabChip(label: '⭐ Reproducteurs', active: _subTab == 1,
                  onTap: () => setState(() => _subTab = 1)),
              const SizedBox(width: 8),
              _SubTabChip(label: '🐣 Bébés', active: _subTab == 2,
                  onTap: () => setState(() => _subTab = 2)),
            ]),
          ),
        ),
        // ── Chips filtres actifs ──
        if (hasFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              if (_filterEspece != null)
                _ActiveFilterChipE(
                  label: speciesLabel(_filterEspece!),
                  onRemove: () => setState(() { _filterEspece = null; _filterRace = null; }),
                ),
              if (_filterSexe != null)
                _ActiveFilterChipE(
                  label: _filterSexe == 'male' ? '♂ Mâle' : '♀ Femelle',
                  onRemove: () => setState(() => _filterSexe = null),
                ),
              if (_filterRace != null)
                _ActiveFilterChipE(
                  label: _filterRace!,
                  onRemove: () => setState(() => _filterRace = null),
                ),
            ]),
          ),
        // ── Grille / portées ──
        Expanded(
          child: filtered.isEmpty
              ? _empty(_subTab == 2 ? 'Aucun bébé dans une portée' : 'Aucun animal', '')
              : _subTab == 2
                  ? _buildPorteeGroupedView(filtered)
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.68,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _EmployeAnimalCard(
                        data: filtered[i],
                        eleveurUid: widget.eleveurUid,
                        canEdit: widget.canEditAnimaux,
                      ),
                    ),
        ),
      ]),
    );
  }
}

// ─── Filter sheet (animaux employé) ──────────────────────────────────────────

class _FilterSheetE extends StatefulWidget {
  final String? filterEspece, filterSexe, filterRace;
  final List<String> availableRaces;
  final void Function(String? espece, String? sexe, String? race) onApply;
  const _FilterSheetE({
    required this.filterEspece, required this.filterSexe, required this.filterRace,
    required this.availableRaces, required this.onApply,
  });
  @override
  State<_FilterSheetE> createState() => _FilterSheetEState();
}

class _FilterSheetEState extends State<_FilterSheetE> {
  static const _teal = Color(0xFF0C5C6C);
  String? _espece, _sexe, _race;

  @override
  void initState() {
    super.initState();
    _espece = widget.filterEspece;
    _sexe   = widget.filterSexe;
    _race   = widget.filterRace;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.3,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: SingleChildScrollView(
          controller: sc,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('Filtres',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),
              TextButton(
                onPressed: () => setState(() { _espece = null; _sexe = null; _race = null; }),
                child: const Text('Tout effacer', style: TextStyle(fontFamily: 'Galey', color: _teal)),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: kSpeciesData
                .where((s) => s.value != 'tous')
                .map((s) {
              final selected = _espece == s.value;
              return GestureDetector(
                onTap: () => setState(() { _espece = selected ? null : s.value; _race = null; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? _teal : Colors.white,
                    border: Border.all(color: selected ? _teal : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(s.label,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : Colors.grey.shade700)),
                ),
              );
            }).toList()),
            const SizedBox(height: 16),
            const Text('Sexe', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              _SexeChipE(label: '♂ Mâle',    value: 'male',    selected: _sexe == 'male',
                  onTap: () => setState(() => _sexe = _sexe == 'male'    ? null : 'male')),
              const SizedBox(width: 8),
              _SexeChipE(label: '♀ Femelle', value: 'femelle', selected: _sexe == 'femelle',
                  onTap: () => setState(() => _sexe = _sexe == 'femelle' ? null : 'femelle')),
            ]),
            if (widget.availableRaces.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Race', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: widget.availableRaces.map((r) {
                final selected = _race == r;
                return GestureDetector(
                  onTap: () => setState(() => _race = selected ? null : r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? _teal : Colors.white,
                      border: Border.all(color: selected ? _teal : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(r,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : Colors.grey.shade700)),
                  ),
                );
              }).toList()),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () { widget.onApply(_espece, _sexe, _race); Navigator.pop(context); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Appliquer',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SubTabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SubTabChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF0C5C6C) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? const Color(0xFF0C5C6C) : Colors.grey.shade300),
      ),
      child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
          color: active ? Colors.white : Colors.grey)),
    ),
  );
}

class _ActiveFilterChipE extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _ActiveFilterChipE({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFF0C5C6C).withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
          color: Color(0xFF0C5C6C), fontWeight: FontWeight.w600)),
      const SizedBox(width: 4),
      GestureDetector(
        onTap: onRemove,
        child: const Icon(Icons.close, size: 14, color: Color(0xFF0C5C6C)),
      ),
    ]),
  );
}

class _SexeChipE extends StatelessWidget {
  final String label, value;
  final bool selected;
  final VoidCallback onTap;
  const _SexeChipE({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF0C5C6C) : Colors.white,
        border: Border.all(color: selected ? const Color(0xFF0C5C6C) : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : Colors.grey.shade700)),
    ),
  );
}

// ─── Page : Détail tâche + commentaires ──────────────────────────────────────

class TacheDetailPage extends StatefulWidget {
  final Map<String, dynamic> tache;
  const TacheDetailPage({super.key, required this.tache});
  @override
  State<TacheDetailPage> createState() => _TacheDetailPageState();
}

class _TacheDetailPageState extends State<TacheDetailPage> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;
  final _commentCtrl = TextEditingController();

  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);

  bool _loading = true;
  bool _sending = false;
  List<Map<String, dynamic>> _comments = [];
  final Map<String, String> _authorNames = {};

  @override
  void initState() { super.initState(); _loadComments(); }

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  Future<void> _loadComments() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await _supa
          .from('tache_commentaires')
          .select()
          .eq('tache_id', widget.tache['id'])
          .order('created_at');

      for (final c in rows) {
        final uid = c['uid_auteur'] as String;
        if (!_authorNames.containsKey(uid)) {
          final u = await _supa.from('users')
              .select('uid, firstname, lastname, name_elevage, is_elevage')
              .eq('uid', uid).maybeSingle();
          if (u != null) {
            _authorNames[uid] = u['is_elevage'] == true
                ? (u['name_elevage'] as String? ?? 'Élevage')
                : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
          }
        }
        c['auteur_nom'] = _authorNames[uid] ?? 'Utilisateur';
      }
      if (mounted) setState(() {
        _comments = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _supa.from('tache_commentaires').insert({
        'tache_id':   widget.tache['id'],
        'uid_auteur': _uid,
        'contenu':    text,
      });
      _commentCtrl.clear();
      await _loadComments();
    } catch (_) {} finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tache;
    final date = DateTime.tryParse(t['date'] ?? '');
    final dateStr = date != null ? DateFormat('dd MMMM yyyy', 'fr_FR').format(date) : '';
    final animalNom  = t['animal_nom']  as String?;
    final assigneNom = t['assigne_nom'] as String?;
    final notes = t['notes'] as String?;
    final fait = t['statut'] == 'fait';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _dark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Détail de la tâche',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Fiche tâche ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 28, height: 28, margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: fait ? _teal : Colors.transparent,
                        border: Border.all(color: fait ? _teal : Colors.grey.shade400, width: 1.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: fait ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(t['titre'] ?? '',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 16, color: _dark,
                              decoration: fait ? TextDecoration.lineThrough : null)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  _InfoRow(icon: Icons.calendar_today_outlined, label: 'Date', value: dateStr),
                  if (animalNom != null) ...[
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.pets_outlined, label: 'Animal', value: animalNom),
                  ],
                  if (assigneNom != null) ...[
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.person_outline, label: 'Assigné à', value: assigneNom),
                  ],
                  if (notes != null && notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.notes_outlined, label: 'Notes', value: notes),
                  ],
                ]),
              ),
              const SizedBox(height: 20),
              // ── Commentaires ──
              const Text('Commentaires',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 15, color: _dark)),
              const SizedBox(height: 12),
              if (_loading)
                const Center(child: CircularProgressIndicator(color: _teal)),
              if (!_loading && _comments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aucun commentaire pour l\'instant.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
                ),
              ..._comments.map((c) => _CommentBubble(comment: c, currentUid: _uid)),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // ── Saisie commentaire ──
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(12, 8, 12,
              MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                maxLines: null,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Écrire un commentaire…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)),
                  filled: true, fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _addComment,
              child: Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
                child: _sending
                    ? const Padding(padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 16, color: const Color(0xFF6F767B)),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E), fontWeight: FontWeight.w500)),
    ])),
  ]);
}

class _CommentBubble extends StatelessWidget {
  final Map<String, dynamic> comment;
  final String currentUid;
  const _CommentBubble({required this.comment, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    final isMe = comment['uid_auteur'] == currentUid;
    final nom     = comment['auteur_nom'] as String? ?? 'Utilisateur';
    final contenu  = comment['contenu'] as String? ?? '';
    final rawDate  = comment['created_at'] as String?;
    final dt = rawDate != null ? DateTime.tryParse(rawDate)?.toLocal() : null;
    final timeStr = dt != null ? DateFormat('dd/MM · HH:mm').format(dt) : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Text(isMe ? 'Moi' : nom,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF0C5C6C) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
            ),
            child: Text(contenu,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    color: isMe ? Colors.white : const Color(0xFF1F2A2E))),
          ),
          const SizedBox(height: 3),
          Text(timeStr,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF9CA3AF))),
        ]),
      ),
    );
  }
}

// ─── Card animal employé (grille, lecture seule) ──────────────────────────────

class _EmployeAnimalCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String eleveurUid;
  final bool canEdit;
  const _EmployeAnimalCard({required this.data, required this.eleveurUid, this.canEdit = false});

  @override
  Widget build(BuildContext context) {
    final photoUrl  = data['photo_url']  as String?;
    final nom       = data['nom']        as String? ?? 'Sans nom';
    final espece    = data['espece']     as String? ?? '';
    final race      = data['race']       as String? ?? '';
    final sexe      = data['sexe']       as String? ?? '';
    final color     = speciesColor(espece);
    final isRepro   = data['reproducteur'] == true;
    final hasPortee = (data['portee_id']  as String? ?? '').isNotEmpty;
    final animalId  = data['id']?.toString();

    return GestureDetector(
      onTap: animalId == null ? null : () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnimalFichePage(
          animalId: animalId,
          readOnly: !canEdit,
          eleveurUidOverride: canEdit ? eleveurUid : null,
        ),
      )),
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Stack(children: [
              Positioned.fill(
                child: photoUrl != null
                    ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
                    : Container(
                        color: color.withOpacity(0.12),
                        child: Center(child: speciesIcon(espece, 44, color)),
                      ),
              ),
              if (isRepro)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Color(0xFFFFA000), shape: BoxShape.circle),
                    child: const Icon(Icons.star, color: Colors.white, size: 11),
                  ),
                ),
              if (hasPortee)
                Positioned(
                  top: 6, left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C5C6C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Portée',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 8,
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 13, color: Color(0xFF1F2A2E)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (race.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(race,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              const Spacer(),
              Wrap(spacing: 4, runSpacing: 4, children: [
                _AnimalBadge(text: speciesLabel(espece), color: color),
                if (sexe == 'male')    _AnimalBadge(text: '♂', color: const Color(0xFF1D4ED8)),
                if (sexe == 'femelle') _AnimalBadge(text: '♀', color: Colors.pinkAccent),
              ]),
            ]),
          ),
        ),
      ]),
      ),
    );
  }
}

class _AnimalBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _AnimalBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(fontFamily: 'Galey', fontSize: 9,
        color: color, fontWeight: FontWeight.w700)),
  );
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
