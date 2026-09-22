import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

const _teal = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _bg = Color(0xFFF8F8F6);

/// Co-gérance d'un élevage : un second compte PetsMatch obtient un accès
/// complet lecture/écriture sur TOUT l'élevage (animaux, chaleurs, employés,
/// agenda, tâches, annonces, signatures) en "empruntant" le profil élevage du
/// gérant principal depuis son propre compte — pas de duplication de
/// données, le profile_id du principal reste utilisé partout. Voir
/// elevage_cogerants (migration_elevage_cogerance.sql) et
/// ProfileService.loadProfiles (fusion dans le sélecteur de profil).
///
/// Cette page sert deux usages à la fois : gérer les cogérants de SON PROPRE
/// élevage (si on en a un), et voir/répondre aux invitations reçues en tant
/// que cogérant potentiel d'un élevage d'autrui — un même compte peut être
/// les deux à la fois.
class CogerancePage extends StatefulWidget {
  const CogerancePage({super.key});
  @override
  State<CogerancePage> createState() => _CogerancePageState();
}

class _CogerancePageState extends State<CogerancePage> {
  final _supa = Supabase.instance.client;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  bool _busy = false;
  String? _elevageProfileId; // mon propre profil éleveur, si j'en ai un
  String _myName = 'Un utilisateur';

  List<Map<String, dynamic>> _cogerants = []; // cogérants (actifs + invités) de MON élevage
  List<Map<String, dynamic>> _invitationsRecues = []; // invitations reçues, tous élevages confondus

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Résolution déterministe depuis le contexte (uid), jamais depuis
  // User_Info.activeProfileId qui peut être périmé après un switch récent —
  // même pattern que employes_page.dart._resolveOwnerProfileId.
  Future<String?> _resolveElevageProfileId() async {
    final row = await _supa.from('user_profiles').select('id')
        .eq('uid', _uid).eq('profile_type', 'eleveur').maybeSingle();
    return row?['id'] as String?;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await _supa.from('user_profiles').select('id, firstname, lastname, nom')
          .eq('uid', _uid).eq('profile_type', 'particulier').maybeSingle();
      final myParticulierName = _nomFromProfile(me);
      if (myParticulierName != null) _myName = myParticulierName;

      _elevageProfileId = await _resolveElevageProfileId();

      final futures = await Future.wait([
        _elevageProfileId != null
            ? _supa.from('elevage_cogerants').select()
                .eq('elevage_profile_id', _elevageProfileId!)
                .isFilter('date_fin', null)
                .inFilter('statut', ['actif', 'invite'])
            : Future.value(<Map<String, dynamic>>[]),
        _supa.from('elevage_cogerants').select()
            .eq('uid_cogerant', _uid).eq('statut', 'invite').isFilter('date_fin', null),
      ]);

      final cogerants = List<Map<String, dynamic>>.from(futures[0] as List);
      final recues = List<Map<String, dynamic>>.from(futures[1] as List);

      // Enrichir avec le nom/photo (cogérants : profil cogérant ; invitations
      // reçues : profil élevage + nom de l'inviteur).
      final profileIds = <String>{
        ...cogerants.map((r) => r['profile_id_cogerant']?.toString()).whereType<String>(),
        ...recues.map((r) => r['elevage_profile_id']?.toString()).whereType<String>(),
        ...recues.map((r) => r['invite_par_profile_id']?.toString()).whereType<String>(),
      };
      final Map<String, Map<String, dynamic>> byId = {};
      if (profileIds.isNotEmpty) {
        final profs = await _supa.from('user_profiles')
            .select('id, firstname, lastname, nom, avatar_url')
            .inFilter('id', profileIds.toList());
        for (final p in (profs as List)) {
          byId[p['id'] as String] = Map<String, dynamic>.from(p);
        }
      }
      for (final r in cogerants) {
        final p = byId[r['profile_id_cogerant']];
        r['_name'] = _nomFromProfile(p) ?? 'Utilisateur PetsMatch';
        r['_photo'] = p?['avatar_url'] as String?;
      }
      for (final r in recues) {
        final elevage = byId[r['elevage_profile_id']];
        final inviteur = byId[r['invite_par_profile_id']];
        r['_elevageName'] = _nomFromProfile(elevage) ?? 'Un élevage';
        r['_inviteurName'] = _nomFromProfile(inviteur) ?? 'Le gérant';
      }

      if (mounted) setState(() {
        _cogerants = cogerants;
        _invitationsRecues = recues;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _nomFromProfile(Map<String, dynamic>? p) {
    if (p == null) return null;
    final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
    if (n.isNotEmpty) return n;
    final nom = (p['nom'] as String?)?.trim();
    return (nom != null && nom.isNotEmpty) ? nom : null;
  }

  Future<void> _notify(String uid, String? profileId, String type, String title, String body) async {
    try {
      await _supa.from('notifications').insert({
        'uid': uid,
        'type': type,
        'title': title,
        'body': body,
        if (profileId != null) 'profile_id': profileId,
        if (profileId != null) 'recipient_profile_id': profileId,
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviter() async {
    final elevageId = _elevageProfileId;
    if (elevageId == null) return;
    final picked = await showModalBottomSheet<_UserPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RechercheCogerantSheet(excludeUid: _uid),
    );
    if (picked == null) return;
    if (_cogerants.any((c) => c['uid_cogerant'] == picked.uid)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cette personne est déjà cogérante ou invitée.')));
      }
      return;
    }
    await _run(() async {
      // Pas d'upsert(onConflict) ici : l'index unique sur (elevage_profile_id,
      // uid_cogerant) est PARTIEL (WHERE date_fin IS NULL, pour garder
      // l'historique des résiliations) — les clients Supabase ne savent pas
      // cibler un index partiel via onConflict (erreur Postgres 42P10). On
      // vérifie donc nous-mêmes s'il existe déjà un lien courant.
      final existing = await _supa.from('elevage_cogerants')
          .select('id')
          .eq('elevage_profile_id', elevageId)
          .eq('uid_cogerant', picked.uid)
          .isFilter('date_fin', null)
          .maybeSingle();
      final data = {
        'elevage_profile_id': elevageId,
        'uid_gerant': _uid,
        'uid_cogerant': picked.uid,
        'profile_id_cogerant': picked.profileId,
        'statut': 'invite',
        'invite_par_profile_id': elevageId,
        'invite_le': DateTime.now().toUtc().toIso8601String(),
      };
      if (existing != null) {
        await _supa.from('elevage_cogerants').update(data).eq('id', existing['id'] as String);
      } else {
        await _supa.from('elevage_cogerants').insert(data);
      }
      await _notify(picked.uid, picked.profileId, 'cogerance_invitation',
          'Invitation de co-gérance',
          '$_myName vous invite à cogérer son élevage.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation envoyée.')));
      }
    });
  }

  Future<void> _annulerInvitation(Map<String, dynamic> row) => _run(() async {
        await _supa.from('elevage_cogerants').delete().eq('id', row['id']);
      });

  Future<void> _resilier(Map<String, dynamic> row) => _run(() async {
        await _supa.from('elevage_cogerants')
            .update({'date_fin': DateTime.now().toIso8601String().substring(0, 10)})
            .eq('id', row['id']);
        await _notify(row['uid_cogerant'] as String, row['profile_id_cogerant'] as String?,
            'cogerance_resiliee', 'Co-gérance résiliée',
            '$_myName a mis fin à votre accès de co-gérance sur son élevage.');
      });

  Future<void> _accepter(Map<String, dynamic> row) => _run(() async {
        final me = await _supa.from('user_profiles').select('id')
            .eq('uid', _uid).eq('profile_type', 'particulier').maybeSingle();
        await _supa.from('elevage_cogerants').update({
          'statut': 'actif',
          'profile_id_cogerant': me?['id'],
          'date_debut': DateTime.now().toIso8601String().substring(0, 10),
          'accepte_le': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', row['id']);
        await _notify(row['uid_gerant'] as String, row['elevage_profile_id'] as String?,
            'cogerance_acceptee', 'Invitation de co-gérance acceptée',
            '$_myName a accepté de cogérer votre élevage.');
      });

  Future<void> _refuser(Map<String, dynamic> row) => _run(() async {
        await _supa.from('elevage_cogerants').update({
          'statut': 'refuse',
          'date_fin': DateTime.now().toIso8601String().substring(0, 10),
        }).eq('id', row['id']);
        await _notify(row['uid_gerant'] as String, row['elevage_profile_id'] as String?,
            'cogerance_refusee', 'Invitation de co-gérance refusée',
            '$_myName a refusé votre invitation de co-gérance.');
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Co-gérance', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_invitationsRecues.isNotEmpty) ...[
                    _sectionTitle('Invitations reçues'),
                    const SizedBox(height: 8),
                    ..._invitationsRecues.map((r) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['_inviteurName']} vous invite à cogérer ${r['_elevageName']}',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('Accès complet lecture/écriture sur cet élevage (animaux, chaleurs, employés, agenda, tâches, annonces, signatures).',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: OutlinedButton(
                              onPressed: _busy ? null : () => _refuser(r),
                              child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey')),
                            )),
                            const SizedBox(width: 10),
                            Expanded(child: ElevatedButton(
                              onPressed: _busy ? null : () => _accepter(r),
                              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
                              child: const Text('Accepter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                            )),
                          ]),
                        ]),
                      ),
                    )),
                    const SizedBox(height: 16),
                  ],
                  if (_elevageProfileId != null) ...[
                    Row(children: [
                      Expanded(child: _sectionTitle('Cogérants de mon élevage')),
                      TextButton.icon(
                        onPressed: _busy ? null : _inviter,
                        icon: const Icon(Icons.person_add_outlined, size: 18),
                        label: const Text('Inviter', style: TextStyle(fontFamily: 'Galey')),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'Un cogérant a un accès complet lecture/écriture sur tout l\'élevage — animaux, chaleurs, employés, agenda, tâches, annonces, signatures.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    if (_cogerants.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text('Aucun cogérant pour le moment.',
                            style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                      )
                    else
                      ..._cogerants.map((r) {
                        final statut = r['statut'] as String? ?? '';
                        final enAttente = statut == 'invite';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFDCEDD5),
                              backgroundImage: (r['_photo'] as String?)?.isNotEmpty == true
                                  ? NetworkImage(r['_photo'] as String) : null,
                              child: (r['_photo'] as String?)?.isNotEmpty != true
                                  ? const Icon(Icons.person, color: _green) : null,
                            ),
                            title: Text(r['_name'] as String? ?? 'Utilisateur PetsMatch',
                                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              enAttente ? 'Invitation en attente'
                                  : 'Cogérant depuis le ${_fmtDate(r['date_debut'] as String?)}',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                  color: enAttente ? Colors.orange.shade700 : Colors.grey.shade600),
                            ),
                            trailing: IconButton(
                              icon: Icon(enAttente ? Icons.close : Icons.link_off, color: Colors.grey, size: 20),
                              tooltip: enAttente ? 'Annuler l\'invitation' : 'Résilier la co-gérance',
                              onPressed: _busy ? null : () => enAttente ? _annulerInvitation(r) : _resilier(r),
                            ),
                          ),
                        );
                      }),
                  ] else if (_invitationsRecues.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text('Vous n\'avez pas de profil élevage à cogérer.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _teal));

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    return d == null ? '' : DateFormat('dd/MM/yyyy').format(d);
  }
}

class _UserPick {
  final String uid;
  final String? profileId;
  final String name;
  _UserPick(this.uid, this.profileId, this.name);
}

class _RechercheCogerantSheet extends StatefulWidget {
  final String? excludeUid;
  const _RechercheCogerantSheet({this.excludeUid});
  @override
  State<_RechercheCogerantSheet> createState() => _RechercheCogerantSheetState();
}

class _RechercheCogerantSheetState extends State<_RechercheCogerantSheet> {
  final _supa = Supabase.instance.client;
  final _ctrl = TextEditingController();
  bool _searching = false;
  bool _searched = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.length < 3) return;
    setState(() { _searching = true; _searched = true; });
    try {
      List<Map<String, dynamic>> users;
      if (q.contains('@')) {
        final rows = await _supa.from('users').select('uid, firstname, lastname, email')
            .eq('email', q.toLowerCase()).limit(5);
        users = List<Map<String, dynamic>>.from(rows as List);
      } else {
        final rows = await _supa.from('users').select('uid, firstname, lastname, email')
            .or('firstname.ilike.%$q%,lastname.ilike.%$q%').limit(15);
        users = List<Map<String, dynamic>>.from(rows as List);
      }
      users = users.where((u) => u['uid'] != widget.excludeUid).toList();

      final uids = users.map((u) => u['uid'] as String).toList();
      final Map<String, String> profileByUid = {};
      if (uids.isNotEmpty) {
        final profs = await _supa.from('user_profiles').select('uid, id')
            .inFilter('uid', uids).eq('profile_type', 'particulier');
        for (final p in (profs as List)) {
          profileByUid[p['uid'] as String] = p['id'] as String;
        }
      }
      for (final u in users) {
        u['_profileId'] = profileByUid[u['uid']];
      }
      if (mounted) setState(() { _results = users; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
              child: Text('Inviter un cogérant', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 4),
          const Text('Saisissez l\'adresse e-mail exacte de la personne (ou son nom).',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'E-mail ou nom',
              prefixIcon: const Icon(Icons.search),
              filled: true, fillColor: const Color(0xFFF6F7F7),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              suffixIcon: TextButton(onPressed: _searching ? null : _search,
                  child: const Text('OK', style: TextStyle(fontFamily: 'Galey'))),
            ),
          ),
          const SizedBox(height: 12),
          if (_searching)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(color: _green)))
          else if (_searched && _results.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Aucun compte PetsMatch trouvé.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
          else
            ..._results.map((u) {
              final name = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(radius: 18, backgroundColor: Color(0xFFE4E7E2),
                    child: Icon(Icons.person, size: 18, color: Colors.grey)),
                title: Text(name.isEmpty ? 'Utilisateur PetsMatch' : name,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(u['email'] as String? ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                trailing: const Icon(Icons.add_circle_outline, color: _green),
                onTap: () => Navigator.pop(context,
                    _UserPick(u['uid'] as String, u['_profileId'] as String?, name.isEmpty ? 'Utilisateur PetsMatch' : name)),
              );
            }),
        ],
      ),
    );
  }
}
