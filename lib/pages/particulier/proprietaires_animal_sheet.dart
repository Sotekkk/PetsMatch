import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _teal = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);

/// Gestion des **co-propriétaires** d'un animal (profils particuliers) :
/// 1 propriétaire principal (référent I-CAD) + N secondaires en accès complet
/// lecture/écriture. Distinct du partage lien (`partage_animal_sheet.dart`) et
/// du partage à un pro (`animal_access`).
Future<void> showProprietairesAnimalSheet(
    BuildContext context, String animalId, String animalNom) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _ProprietairesAnimalSheet(animalId: animalId, animalNom: animalNom),
  );
}

class _ProprietairesAnimalSheet extends StatefulWidget {
  final String animalId;
  final String animalNom;
  const _ProprietairesAnimalSheet({required this.animalId, required this.animalNom});

  @override
  State<_ProprietairesAnimalSheet> createState() => _ProprietairesAnimalSheetState();
}

class _ProprietairesAnimalSheetState extends State<_ProprietairesAnimalSheet> {
  final _supa = Supabase.instance.client;
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _owners = []; // enrichi avec name/photo
  String? _myProfileId;
  String _myName = 'Un propriétaire';

  Map<String, dynamic>? get _myRow {
    for (final o in _owners) {
      if (o['profile_id_proprio'] == _myProfileId) return o;
    }
    return null;
  }

  bool get _amPrincipal =>
      _myRow != null && _myRow!['role_proprio'] == 'principal' && _myRow!['statut'] == 'actif';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _uid;
      if (_myProfileId == null && uid != null) {
        final me = await _supa
            .from('user_profiles')
            .select('id, firstname, lastname, nom')
            .eq('uid', uid)
            .eq('profile_type', 'particulier')
            .maybeSingle();
        _myProfileId = me?['id'] as String?;
        _myName = _nomFromProfile(me) ?? _myName;
      }

      final rows = await _supa
          .from('animaux_proprietes')
          .select('id, uid_proprio, profile_id_proprio, role_proprio, statut, '
              'transfert_principal_propose, invite_par_profile_id')
          .eq('animal_id', widget.animalId)
          .isFilter('date_fin', null)
          .inFilter('statut', ['actif', 'invite']);

      final list = List<Map<String, dynamic>>.from(rows as List);
      final ids = list
          .map((r) => r['profile_id_proprio'])
          .where((e) => e != null)
          .cast<String>()
          .toSet()
          .toList();

      final Map<String, Map<String, dynamic>> byId = {};
      if (ids.isNotEmpty) {
        final profs = await _supa
            .from('user_profiles')
            .select('id, firstname, lastname, nom, avatar_url')
            .inFilter('id', ids);
        for (final p in (profs as List)) {
          byId[p['id'] as String] = Map<String, dynamic>.from(p);
        }
      }

      for (final r in list) {
        final p = byId[r['profile_id_proprio']];
        r['_name'] = _nomFromProfile(p) ?? 'Utilisateur PetsMatch';
        r['_photo'] = p?['avatar_url'] as String?;
      }
      // principal d'abord, puis secondaires actifs, puis invitations
      list.sort((a, b) {
        int rank(Map<String, dynamic> r) {
          if (r['role_proprio'] == 'principal') return 0;
          if (r['statut'] == 'actif') return 1;
          return 2;
        }
        return rank(a).compareTo(rank(b));
      });

      if (mounted) setState(() { _owners = list; _loading = false; });
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
        'data': {'animal_id': widget.animalId, 'animal_nom': widget.animalNom},
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
    final picked = await showModalBottomSheet<_UserPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RechercheProprietaireSheet(excludeUid: _uid),
    );
    if (picked == null) return;
    if (_owners.any((o) => o['uid_proprio'] == picked.uid)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cette personne est déjà propriétaire ou invitée.')));
      }
      return;
    }
    await _run(() async {
      await _supa.from('animaux_proprietes').upsert({
        'animal_id': widget.animalId,
        'uid_proprio': picked.uid,
        'profile_id_proprio': picked.profileId,
        'role_proprio': 'secondaire',
        'statut': 'invite',
        'transfert_principal_propose': false,
        'date_debut': DateTime.now().toIso8601String().substring(0, 10),
        'date_fin': null,
        'invite_par_profile_id': _myProfileId,
        'invite_le': DateTime.now().toUtc().toIso8601String(),
        'accepte_le': null,
      }, onConflict: 'animal_id,uid_proprio');
      await _notify(picked.uid, picked.profileId, 'coproprio_invitation',
          'Invitation de co-propriété',
          '$_myName vous invite à co-gérer la fiche de ${widget.animalNom}.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invitation envoyée.')));
      }
    });
  }

  Future<void> _annuler(Map<String, dynamic> row) => _run(() async {
        await _supa.from('animaux_proprietes').delete().eq('id', row['id']);
      });

  Future<void> _retirer(Map<String, dynamic> row) => _run(() async {
        await _supa.from('animaux_proprietes').delete().eq('id', row['id']);
        await _notify(row['uid_proprio'] as String, row['profile_id_proprio'] as String?,
            'coproprio_retire', 'Co-propriété retirée',
            'Vous n\'êtes plus co-propriétaire de ${widget.animalNom}.');
      });

  Future<void> _proposerPrincipal(Map<String, dynamic> row) => _run(() async {
        await _supa
            .from('animaux_proprietes')
            .update({'transfert_principal_propose': true}).eq('id', row['id']);
        await _notify(row['uid_proprio'] as String, row['profile_id_proprio'] as String?,
            'coproprio_transfert_propose', 'Proposition : devenir propriétaire principal',
            '$_myName vous propose de devenir le propriétaire principal de ${widget.animalNom}.');
      });

  Future<void> _quitter() => _run(() async {
        final myRow = _myRow;
        if (myRow == null) return;
        await _supa.from('animaux_proprietes').delete().eq('id', myRow['id']);
        final principal = _owners.firstWhere(
            (o) => o['role_proprio'] == 'principal',
            orElse: () => {});
        if (principal.isNotEmpty) {
          await _notify(principal['uid_proprio'] as String,
              principal['profile_id_proprio'] as String?,
              'coproprio_quitte', 'Un co-propriétaire a quitté',
              '$_myName ne co-gère plus la fiche de ${widget.animalNom}.');
        }
        if (mounted) Navigator.pop(context);
      });

  Future<void> _accepterPrincipal() => _run(() async {
        await _supa.rpc('transferer_proprietaire_principal', params: {
          'p_animal_id': widget.animalId,
          'p_nouveau_profile_id': _myProfileId,
        });
        final ancien = _owners.firstWhere(
            (o) => o['role_proprio'] == 'principal',
            orElse: () => {});
        if (ancien.isNotEmpty) {
          await _notify(ancien['uid_proprio'] as String,
              ancien['profile_id_proprio'] as String?,
              'coproprio_transfert_accepte', 'Transfert de propriété accepté',
              '$_myName est maintenant le propriétaire principal de ${widget.animalNom}.');
        }
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Vous êtes propriétaire principal',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              content: const Text(
                  'Pensez à mettre à jour la déclaration I-CAD : PetsMatch ne modifie '
                  'pas automatiquement le fichier national d\'identification.',
                  style: TextStyle(fontFamily: 'Galey')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Compris', style: TextStyle(fontFamily: 'Galey'))),
              ],
            ),
          );
        }
      });

  Future<void> _refuserPrincipal() => _run(() async {
        final myRow = _myRow;
        if (myRow == null) return;
        await _supa
            .from('animaux_proprietes')
            .update({'transfert_principal_propose': false}).eq('id', myRow['id']);
        final principal = _owners.firstWhere(
            (o) => o['role_proprio'] == 'principal',
            orElse: () => {});
        if (principal.isNotEmpty) {
          await _notify(principal['uid_proprio'] as String,
              principal['profile_id_proprio'] as String?,
              'coproprio_transfert_accepte', 'Transfert de propriété refusé',
              '$_myName préfère rester co-propriétaire de ${widget.animalNom}.');
        }
      });

  @override
  Widget build(BuildContext context) {
    final myRow = _myRow;
    final transfertPourMoi = myRow != null && myRow['transfert_principal_propose'] == true;

    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.people_alt_outlined, color: _green, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Propriétaires',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
                      Text(widget.animalNom,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _green)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
                'Les co-propriétaires ont accès à toute la fiche, en lecture et en écriture. '
                'Le propriétaire principal est le référent I-CAD.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 18),

            if (transfertPourMoi) _transfertBanner(),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: _green)),
              )
            else ...[
              ..._owners.map(_ownerTile),
              const SizedBox(height: 14),
              if (_amPrincipal)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _inviter,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Inviter un co-propriétaire',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                )
              else if (myRow != null && myRow['statut'] == 'actif')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _quitter,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Quitter la copropriété',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _transfertBanner() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2F4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _teal.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('On vous propose de devenir propriétaire principal',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 4),
            const Text('Vous deviendrez le référent I-CAD de cet animal.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : _accepterPrincipal,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _teal, foregroundColor: Colors.white),
                  child: const Text('Accepter', style: TextStyle(fontFamily: 'Galey')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _refuserPrincipal,
                  child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey')),
                ),
              ),
            ]),
          ],
        ),
      );

  Widget _ownerTile(Map<String, dynamic> o) {
    final isPrincipal = o['role_proprio'] == 'principal';
    final isInvite = o['statut'] == 'invite';
    final isMe = o['profile_id_proprio'] == _myProfileId;
    final photo = o['_photo'] as String?;

    Widget badge;
    if (isInvite) {
      badge = _pill('Invitation envoyée', Colors.orange.shade700, Colors.orange.shade50);
    } else if (isPrincipal) {
      badge = _pill('Principal · I-CAD', _teal, const Color(0xFFEAF2F4));
    } else {
      badge = _pill('Co-propriétaire', _green, const Color(0xFFEFF4EA));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE4E7E2),
            backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
            child: (photo == null || photo.isEmpty)
                ? const Icon(Icons.person, size: 18, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${o['_name']}${isMe ? ' (vous)' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                badge,
              ],
            ),
          ),
          if (_amPrincipal && !isPrincipal) _ownerActions(o, isInvite),
        ],
      ),
    );
  }

  Widget _ownerActions(Map<String, dynamic> o, bool isInvite) {
    return PopupMenuButton<String>(
      enabled: !_busy,
      icon: const Icon(Icons.more_vert, size: 20, color: Colors.black45),
      onSelected: (v) {
        if (v == 'annuler') _annuler(o);
        if (v == 'retirer') _retirer(o);
        if (v == 'principal') _proposerPrincipal(o);
      },
      itemBuilder: (_) => [
        if (isInvite)
          const PopupMenuItem(value: 'annuler', child: Text('Annuler l\'invitation'))
        else ...[
          if (o['transfert_principal_propose'] != true)
            const PopupMenuItem(value: 'principal', child: Text('Proposer comme principal')),
          const PopupMenuItem(value: 'retirer', child: Text('Retirer de la copropriété')),
        ],
      ],
    );
  }

  Widget _pill(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(fontFamily: 'Galey', fontSize: 10.5, color: fg, fontWeight: FontWeight.w600)),
      );
}

// ── Recherche d'un utilisateur : email exact d'abord, nom/prénom en secours ──

class _UserPick {
  final String uid;
  final String profileId;
  final String name;
  _UserPick(this.uid, this.profileId, this.name);
}

class _RechercheProprietaireSheet extends StatefulWidget {
  final String? excludeUid;
  const _RechercheProprietaireSheet({this.excludeUid});

  @override
  State<_RechercheProprietaireSheet> createState() => _RechercheProprietaireSheetState();
}

class _RechercheProprietaireSheetState extends State<_RechercheProprietaireSheet> {
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
        final rows = await _supa
            .from('users')
            .select('uid, firstname, lastname, email')
            .eq('email', q.toLowerCase())
            .limit(5);
        users = List<Map<String, dynamic>>.from(rows as List);
      } else {
        final rows = await _supa
            .from('users')
            .select('uid, firstname, lastname, email')
            .or('firstname.ilike.%$q%,lastname.ilike.%$q%')
            .limit(15);
        users = List<Map<String, dynamic>>.from(rows as List);
      }
      users = users.where((u) => u['uid'] != widget.excludeUid).toList();

      // Résout le profil particulier de chaque utilisateur
      final uids = users.map((u) => u['uid'] as String).toList();
      final Map<String, String> profileByUid = {};
      if (uids.isNotEmpty) {
        final profs = await _supa
            .from('user_profiles')
            .select('uid, id')
            .inFilter('uid', uids)
            .eq('profile_type', 'particulier');
        for (final p in (profs as List)) {
          profileByUid[p['uid'] as String] = p['id'] as String;
        }
      }
      for (final u in users) {
        u['_profileId'] = profileByUid[u['uid']];
      }
      if (mounted) {
        setState(() {
          _results = users.where((u) => u['_profileId'] != null).toList();
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Inviter un co-propriétaire',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
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
              filled: true,
              fillColor: const Color(0xFFF6F7F7),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              suffixIcon: TextButton(
                onPressed: _searching ? null : _search,
                child: const Text('OK', style: TextStyle(fontFamily: 'Galey')),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: _green)),
            )
          else if (_searched && _results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Aucun compte PetsMatch trouvé.',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
            )
          else
            ..._results.map((u) {
              final name = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFFE4E7E2),
                    child: Icon(Icons.person, size: 18, color: Colors.grey)),
                title: Text(name.isEmpty ? 'Utilisateur PetsMatch' : name,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(u['email'] as String? ?? '',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                trailing: const Icon(Icons.add_circle_outline, color: _green),
                onTap: () => Navigator.pop(
                    context,
                    _UserPick(u['uid'] as String, u['_profileId'] as String,
                        name.isEmpty ? 'Utilisateur PetsMatch' : name)),
              );
            }),
        ],
      ),
    );
  }
}
