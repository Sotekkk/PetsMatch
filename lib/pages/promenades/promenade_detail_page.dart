import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:PetsMatch/main.dart' show getApiKey, User_Info;
import 'package:PetsMatch/pages/petfriends/public_profile_page.dart';
import 'package:PetsMatch/pages/particulier/social_feed_page.dart'
    show resolveActiveAuthorProfileId, socialProfileName, socialProfilePhoto, kSocialAuthorCols;
import 'package:PetsMatch/services/promenade_notification_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _darkC  = Color(0xFF071C22);
const _accent = Color(0xFF7ED69D);
const _green  = Color(0xFF2E7D5E); // kept for _EditSheet (white surface)
const _orange = Color(0xFFEF6C00);

class PromenadeDetailPage extends StatefulWidget {
  final String promenadeId;
  const PromenadeDetailPage({super.key, required this.promenadeId});

  @override
  State<PromenadeDetailPage> createState() => _PromenadeDetailPageState();
}

class _PromenadeDetailPageState extends State<PromenadeDetailPage> {
  final _supa = Supabase.instance.client;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Map<String, dynamic>? _promenade;
  Map<String, dynamic>? _organizer;
  List<Map<String, dynamic>> _participants = [];
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _saving = false;
  /// PetFriends acceptés (profile_id) du profil actif — badge « Ami » sur
  /// les participants et filtre de la liste d'invitation.
  Set<String> _friendProfileIds = {};

  final _msgCtrl = TextEditingController();
  bool _sendingMsg = false;
  bool _uploadingPhoto = false;

  bool get _isOrganizer =>
      _promenade?['organisateur_uid']?.toString() == _uid;

  String? get _myStatut {
    if (_uid.isEmpty) return null;
    try {
      return _participants
          .firstWhere((p) => p['user_uid'].toString() == _uid)['statut']
          ?.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await _supa
          .from('promenades')
          .select()
          .eq('id', widget.promenadeId)
          .single();

      final org = await _supa
          .from('user_profiles')
          .select('firstname, lastname, profile_picture_url:avatar_url')
          .eq('uid', p['organisateur_uid'].toString())
          .eq('is_main', true)
          .maybeSingle();

      final rawParts = await _supa
          .from('promenades_participants')
          .select('user_uid, user_profile_id, statut, rejoint_at')
          .eq('promenade_id', widget.promenadeId)
          .order('rejoint_at');

      final List<Map<String, dynamic>> parts = [];
      final uids = (rawParts as List).map((r) => r['user_uid'].toString()).toList();
      if (uids.isNotEmpty) {
        final usersData = await _supa
            .from('user_profiles')
            .select('uid, firstname, lastname, profile_picture_url:avatar_url')
            .inFilter('uid', uids).eq('is_main', true);
        final usersMap = {
          for (final u in (usersData as List)) u['uid'].toString(): u
        };
        for (final part in rawParts) {
          parts.add({
            ...Map<String, dynamic>.from(part),
            'user': usersMap[part['user_uid'].toString()],
          });
        }
      }

      final friendIds = await _loadFriendProfileIds();

      if (mounted) {
        setState(() {
          _promenade = Map<String, dynamic>.from(p);
          _organizer = org != null ? Map<String, dynamic>.from(org) : null;
          _participants = parts;
          _friendProfileIds = friendIds;
          _loading = false;
        });
      }
      // Messages en try séparé : la table peut ne pas encore exister
      _loadMessages();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Set<String>> _loadFriendProfileIds() async {
    if (_uid.isEmpty) return {};
    try {
      final myProfileId = await resolveActiveAuthorProfileId(_uid);
      if (myProfileId == null) return {};
      final sent = await _supa.from('petfriends').select('recepteur_profile_id')
          .eq('demandeur_profile_id', myProfileId).eq('statut', 'accepte');
      final received = await _supa.from('petfriends').select('demandeur_profile_id')
          .eq('recepteur_profile_id', myProfileId).eq('statut', 'accepte');
      return {
        for (final r in (sent as List)) if (r['recepteur_profile_id'] != null) r['recepteur_profile_id'].toString(),
        for (final r in (received as List)) if (r['demandeur_profile_id'] != null) r['demandeur_profile_id'].toString(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _loadMessages() async {
    try {
      final rawMsgs = await _supa
          .from('promenades_messages')
          .select('id, user_uid, message, image_url, created_at, user_profile_id')
          .eq('promenade_id', widget.promenadeId)
          .order('created_at');
      final List<Map<String, dynamic>> msgs = [];
      if ((rawMsgs as List).isNotEmpty) {
        final msgUids = rawMsgs.map((m) => m['user_uid'].toString()).toSet().toList();
        final msgUsers = await _supa.from('user_profiles')
            .select('uid, firstname, lastname, profile_picture_url:avatar_url')
            .inFilter('uid', msgUids).eq('is_main', true);
        final msgUsersMap = {for (final u in (msgUsers as List)) u['uid'].toString(): u};
        for (final m in rawMsgs) {
          msgs.add({...Map<String, dynamic>.from(m), 'user': msgUsersMap[m['user_uid'].toString()]});
        }
      }
      if (mounted) setState(() => _messages = msgs);
    } catch (_) {}
  }

  Future<void> _join() async {
    if (_uid.isEmpty) return;
    setState(() => _saving = true);
    try {
      final profileRow = await _supa.from('user_profiles').select('id').eq('uid', _uid).eq('is_main', true).maybeSingle();
      final pid = profileRow?['id'] as String?;
      await _supa.from('promenades_participants').insert({
        'promenade_id': widget.promenadeId,
        'user_uid': _uid,
        if (pid != null) 'user_profile_id': pid,
        'statut': 'en_attente',
        'rejoint_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _notifyOrganizer();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Bottom sheet listant mes PetFriends acceptés, avec un bouton pour
  /// chacun envoyant une notification l'invitant à rejoindre la balade
  /// (il reste libre de cliquer « Rejoindre » lui-même, même flow que les
  /// autres demandes de participation).
  Future<void> _openInviteFriends() async {
    if (_uid.isEmpty || _promenade == null) return;
    try {
      final myProfileId = await resolveActiveAuthorProfileId(_uid);
      if (myProfileId == null) return;
      final sent = await _supa.from('petfriends')
          .select('recepteur_profile_id, uid_recepteur')
          .eq('demandeur_profile_id', myProfileId).eq('statut', 'accepte');
      final received = await _supa.from('petfriends')
          .select('demandeur_profile_id, uid_demandeur')
          .eq('recepteur_profile_id', myProfileId).eq('statut', 'accepte');
      final Map<String, String> friendUidByProfileId = {
        for (final r in (sent as List))
          if (r['recepteur_profile_id'] != null) r['recepteur_profile_id'].toString(): r['uid_recepteur'].toString(),
        for (final r in (received as List))
          if (r['demandeur_profile_id'] != null) r['demandeur_profile_id'].toString(): r['uid_demandeur'].toString(),
      };
      if (friendUidByProfileId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Vous n\'avez pas encore de PetFriends', style: TextStyle(fontFamily: 'Galey'))));
        }
        return;
      }
      final profiles = await _supa.from('user_profiles').select(kSocialAuthorCols)
          .inFilter('id', friendUidByProfileId.keys.toList());
      final myProfile = await _supa.from('user_profiles').select(kSocialAuthorCols)
          .eq('id', myProfileId).maybeSingle();
      final myName = myProfile != null ? socialProfileName(myProfile) : 'Quelqu\'un';
      final alreadyUids = _participants.map((p) => p['user_uid']?.toString() ?? '').toSet();
      final titre = _promenade!['titre']?.toString() ?? 'une balade';

      if (!mounted) return;
      final invited = <String>{};
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) => DraggableScrollableSheet(
          initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4, expand: false,
          builder: (_, sc) => Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: const BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Inviter mes PetFriends',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: sc,
                  itemCount: (profiles as List).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final f = profiles[i];
                    final fUid = friendUidByProfileId[f['id'].toString()] ?? f['uid']?.toString() ?? '';
                    final already = alreadyUids.contains(fUid) || invited.contains(fUid);
                    return Row(children: [
                      CircleAvatar(
                        radius: 20, backgroundColor: const Color(0xFFE8F5E9),
                        backgroundImage: (socialProfilePhoto(f) ?? '').isNotEmpty
                            ? CachedNetworkImageProvider(socialProfilePhoto(f)!) : null,
                        child: (socialProfilePhoto(f) ?? '').isEmpty
                            ? const Icon(Icons.person_outline, color: _green) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(socialProfileName(f),
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14))),
                      already
                          ? const Text('✓ Invité(e)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey))
                          : GestureDetector(
                              onTap: () async {
                                setModal(() => invited.add(fUid));
                                try {
                                  await _supa.from('notifications').insert({
                                    'uid': fUid,
                                    'type': 'promenade_invite',
                                    'title': '🐾 Invitation à une balade',
                                    'body': '$myName t\'invite à "$titre"',
                                    'profile_id': f['id'],
                                    'data': {'promenadeId': widget.promenadeId, 'fromUid': _uid},
                                    'read': false,
                                    'created_at': DateTime.now().toUtc().toIso8601String(),
                                  });
                                } catch (_) {}
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(20)),
                                child: const Text('Inviter',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                              ),
                            ),
                    ]);
                  },
                ),
              ),
            ]),
          ),
        )),
      );
    } catch (_) {}
  }

  Future<void> _leave() async {
    if (_uid.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _supa
          .from('promenades_participants')
          .delete()
          .eq('promenade_id', widget.promenadeId)
          .eq('user_uid', _uid);
      // Supprimer l'événement agenda lié
      try {
        await _supa.from('agenda_events')
            .delete()
            .eq('promenade_id', widget.promenadeId)
            .eq('uid', _uid);
      } catch (_) {}
      // Annuler les notifications locales
      await cancelPromenadeReminders(widget.promenadeId);
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _notifyOrganizer() async {
    final p = _promenade!;
    final orgUid = p['organisateur_uid']?.toString() ?? '';
    if (orgUid.isEmpty || orgUid == _uid) return;
    try {
      final me = await _supa
          .from('user_profiles')
          .select('firstname, lastname')
          .eq('uid', _uid)
          .eq('is_main', true)
          .maybeSingle();
      final nom = me != null
          ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim()
          : 'Quelqu\'un';
      await _supa.from('notifications').insert({
        'uid': orgUid,
        'type': 'promenade_join',
        'title': 'Nouvelle demande de participation',
        'body': '$nom veut rejoindre "${p['titre']}"',
        if (_promenade!['organisateur_profile_id'] != null) 'profile_id': _promenade!['organisateur_profile_id'],
        'data': {'promenadeId': widget.promenadeId, 'fromUid': _uid},
        'read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _accept(String userUid) async {
    await _supa
        .from('promenades_participants')
        .update({'statut': 'accepte'})
        .eq('promenade_id', widget.promenadeId)
        .eq('user_uid', userUid);
    final titre = _promenade!['titre']?.toString() ?? 'Promenade';
    final dateHeure = _promenade!['date_heure']?.toString() ?? '';
    final lieu = _promenade!['lieu_rdv']?.toString() ?? '';
    // Récupérer le profile_id du participant accepté
    final partRow = await _supa.from('promenades_participants')
        .select('user_profile_id').eq('promenade_id', widget.promenadeId)
        .eq('user_uid', userUid).maybeSingle();
    final partProfileId = partRow?['user_profile_id'] as String?;
    // Ajouter l'événement dans l'agenda du participant
    try {
      await _supa.from('agenda_events').insert({
        'uid':          userUid,
        'titre':        titre,
        'type':         'promenade',
        'date_debut':   dateHeure,
        'notes':        lieu.isNotEmpty ? 'RDV : $lieu' : null,
        'pro_profile_id': partProfileId ?? '',
        'promenade_id': widget.promenadeId,
      });
    } catch (_) {}
    try {
      await _supa.from('notifications').insert({
        'uid': userUid,
        'type': 'promenade_accepte',
        'title': 'Participation confirmée',
        'body': 'Votre demande pour "$titre" a été acceptée !',
        if (partProfileId != null) 'profile_id': partProfileId,
        'data': {'promenadeId': widget.promenadeId},
        'read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
    _load();
  }

  Future<void> _refuse(String userUid) async {
    final partRow = await _supa.from('promenades_participants')
        .select('user_profile_id').eq('promenade_id', widget.promenadeId)
        .eq('user_uid', userUid).maybeSingle();
    final partProfileId = partRow?['user_profile_id'] as String?;
    await _supa
        .from('promenades_participants')
        .delete()
        .eq('promenade_id', widget.promenadeId)
        .eq('user_uid', userUid);
    try {
      await _supa.from('notifications').insert({
        'uid': userUid,
        'type': 'promenade_refuse',
        'title': 'Participation refusée',
        'body': 'Votre demande pour "${_promenade!['titre']}" n\'a pas été retenue.',
        if (partProfileId != null) 'profile_id': partProfileId,
        'data': {'promenadeId': widget.promenadeId},
        'read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
    _load();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la promenade',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text(
            'Tous les participants seront notifiés de l\'annulation. Cette action est irréversible.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok == true && mounted) _delete();
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    try {
      final titre = _promenade!['titre']?.toString() ?? 'la promenade';
      final dateStr = _promenade!['date_heure'] != null
          ? DateFormat('dd/MM/yyyy à HH:mm')
              .format(DateTime.parse(_promenade!['date_heure'].toString()).toLocal())
          : '';

      // Notifier tous les participants actifs
      final toNotify = _participants
          .where((p) => p['statut'] == 'accepte' || p['statut'] == 'en_attente')
          .toList();
      for (final part in toNotify) {
        final uid = part['user_uid'].toString();
        if (uid == _uid) continue;
        try {
          await _supa.from('notifications').insert({
            'uid': uid,
            'type': 'promenade_annulee',
            'title': 'Promenade annulée',
            'body': 'La promenade "$titre"${dateStr.isNotEmpty ? ' du $dateStr' : ''} a été annulée par l\'organisateur.',
            if (part['user_profile_id'] != null) 'profile_id': part['user_profile_id'],
            'data': {'promenadeId': widget.promenadeId},
            'read': false,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}
      }

      await _supa.from('promenades').delete().eq('id', widget.promenadeId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  Future<void> _sendMessage() async {
    final txt = _msgCtrl.text.trim();
    if (txt.isEmpty || _uid.isEmpty) return;
    setState(() => _sendingMsg = true);
    try {
      final pid = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;
      await _supa.from('promenades_messages').insert({
        'promenade_id':   widget.promenadeId,
        'user_uid':       _uid,
        if (pid != null) 'user_profile_id': pid,
        'message':        txt,
        // created_at omis → DEFAULT NOW() PostgreSQL (UTC garanti, évite le décalage +2h)
      });
      _msgCtrl.clear();
      await _notifyGroupMessage(txt, null);
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _sendingMsg = false);
    }
  }

  Future<void> _sendPhoto() async {
    if (_uid.isEmpty) return;
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (xfile == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final file = File(xfile.path);
      final ext  = xfile.path.split('.').last;
      final path = '${widget.promenadeId}/${DateTime.now().millisecondsSinceEpoch}_$_uid.$ext';
      await _supa.storage.from('promenades-photos').upload(path, file);
      final imageUrl = _supa.storage.from('promenades-photos').getPublicUrl(path);
      final pid = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;
      await _supa.from('promenades_messages').insert({
        'promenade_id': widget.promenadeId,
        'user_uid':     _uid,
        if (pid != null) 'user_profile_id': pid,
        'image_url':    imageUrl,
        // created_at omis → DEFAULT NOW() PostgreSQL (UTC garanti)
      });
      await _notifyGroupMessage(null, imageUrl);
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur upload : $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _notifyGroupMessage(String? text, String? imageUrl) async {
    if (_uid.isEmpty || _promenade == null) return;
    try {
      final me = await _supa.from('user_profiles')
          .select('firstname, lastname').eq('uid', _uid).eq('is_main', true).maybeSingle();
      final nom = me != null
          ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim()
          : 'Quelqu\'un';
      final body = text != null
          ? '$nom : ${text.length > 60 ? '${text.substring(0, 60)}…' : text}'
          : '$nom a partagé une photo';
      final toNotify = _participants
          .where((p) => p['statut'].toString() == 'accepte' && p['user_uid'].toString() != _uid)
          .toList();
      for (final part in toNotify) {
        await _supa.from('notifications').insert({
          'uid':        part['user_uid'].toString(),
          'type':       'promenade_message',
          'title':      '💬 ${_promenade!['titre']}',
          'body':       body,
          if (part['user_profile_id'] != null) 'profile_id': part['user_profile_id'],
          'data':       {'promenadeId': widget.promenadeId},
          'read':       false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (_) {}
  }

  Future<void> _openEdit() async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditSheet(
        promenade: _promenade!,
        onNotifyParticipants: (body) async {
          for (final part in _participants) {
            final uid = part['user_uid'].toString();
            if (uid == _uid) continue;
            try {
              await _supa.from('notifications').insert({
                'uid': uid,
                'type': 'promenade_modifiee',
                'title': 'Promenade modifiée',
                'body': body,
                if (part['user_profile_id'] != null) 'profile_id': part['user_profile_id'],
                'data': {'promenadeId': widget.promenadeId},
                'read': false,
                'created_at': DateTime.now().toUtc().toIso8601String(),
              });
            } catch (_) {}
          }
        },
      ),
    );
    if (updated == true) _load();
  }

  static Future<void> _openNavigation(double lat, double lng) async {
    final latStr = lat.toStringAsFixed(6);
    final lngStr = lng.toStringAsFixed(6);
    final wazeUrl = Uri.parse('waze://?ll=$latStr,$lngStr&navigate=yes');
    final mapsUrl = Uri.parse('https://maps.google.com/?daddr=$latStr,$lngStr');
    if (await canLaunchUrl(wazeUrl)) {
      await launchUrl(wazeUrl, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(mapsUrl, mode: LaunchMode.externalApplication);
    }
  }

  static String _fmtDate(String iso) {
    try {
      return DateFormat('EEEE d MMMM yyyy · HH:mm', 'fr_FR')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  static Color _niveauColor(String n) => switch (n) {
        'facile' => const Color(0xFF6E9E57),
        'moyen' => _orange,
        'difficile' => Colors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _darkC,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(children: [
              Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
              const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF7ED69D)))),
            ]),
          ),
        ),
      );
    }

    if (_promenade == null) {
      return Scaffold(
        backgroundColor: _darkC,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(children: [
              Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text('Promenade introuvable',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 16)),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    final p = _promenade!;
    final titre = p['titre']?.toString() ?? '';
    final lieu = p['lieu_rdv']?.toString() ?? '';
    final lat = (p['lat'] as num?)?.toDouble();
    final lng = (p['lng'] as num?)?.toDouble();
    final niveau = p['niveau']?.toString() ?? 'facile';
    final duree = (p['duree_minutes'] as num?)?.toInt();
    final distance = (p['distance_km'] as num?)?.toDouble();
    final desc = p['description']?.toString() ?? '';
    final dateHeure = p['date_heure']?.toString() ?? '';
    final participantsMax = (p['participants_max'] as num?)?.toInt();

    final accepted = _participants.where((p) => p['statut'] == 'accepte').toList();
    final pending = _participants.where((p) => p['statut'] == 'en_attente').toList();
    final nbAccepted = accepted.length;
    final isFull = participantsMax != null && nbAccepted >= participantsMax;
    final myStatut = _myStatut;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _darkC,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _load,
              color: _accent,
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 240,
                    pinned: true,
                    backgroundColor: _darkC,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    leading: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      if (_uid.isNotEmpty)
                        GestureDetector(
                          onTap: _openInviteFriends,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                ),
                                child: const Icon(Icons.person_add_alt_outlined, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ),
                      if (_isOrganizer) ...[
                        GestureDetector(
                          onTap: _saving ? null : _openEdit,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                ),
                                child: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _saving ? null : _confirmDelete,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                ),
                                child: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _niveauColor(niveau).withValues(alpha: 0.3),
                                  const Color(0xFF0C3535),
                                ],
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, _darkC.withValues(alpha: 0.7)],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16, right: 16, bottom: 16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _niveauColor(niveau).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: _niveauColor(niveau).withValues(alpha: 0.5)),
                                  ),
                                  child: Text(niveau.toUpperCase(),
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                                        fontWeight: FontWeight.w700, color: _niveauColor(niveau))),
                                ),
                                const SizedBox(height: 8),
                                Text(titre,
                                  style: const TextStyle(
                                    fontFamily: 'Galey',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      child: Column(
                        children: [
                          // ── Organisateur ──
                          GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PublicProfilePage(targetUid: _promenade!['organisateur_uid'].toString()))),
                            child: _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('ORGANISÉ PAR',
                                  style: TextStyle(
                                      fontFamily: 'Galey',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                      color: Colors.white.withValues(alpha: 0.5))),
                              const SizedBox(height: 8),
                              Row(children: [
                                _avatar(_organizer?['profile_picture_url']?.toString(), 22),
                                const SizedBox(width: 10),
                                Expanded(child: Text(
                                  '${_organizer?['firstname'] ?? ''} ${_organizer?['lastname'] ?? ''}'.trim().isEmpty
                                      ? 'Organisateur'
                                      : '${_organizer?['firstname'] ?? ''} ${_organizer?['lastname'] ?? ''}'.trim(),
                                  style: const TextStyle(
                                      fontFamily: 'Galey',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: Colors.white),
                                )),
                                Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.4), size: 18),
                              ]),
                            ])),
                          ),
                          const SizedBox(height: 10),

                          // ── Infos ──
                          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (dateHeure.isNotEmpty) ...[
                              Row(children: [
                                const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF7ED69D)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_fmtDate(dateHeure),
                                      style: const TextStyle(
                                          fontFamily: 'Galey',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white)),
                                ),
                              ]),
                              const SizedBox(height: 8),
                            ],
                            if (lieu.isNotEmpty) ...[
                              Row(children: [
                                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF7ED69D)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(lieu,
                                      style: TextStyle(
                                          fontFamily: 'Galey', fontSize: 13,
                                          color: Colors.white.withValues(alpha: 0.85))),
                                ),
                                if (lat != null && lng != null)
                                  GestureDetector(
                                    onTap: () => _openNavigation(lat, lng),
                                    child: Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7ED69D).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFF7ED69D).withValues(alpha: 0.3)),
                                      ),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.navigation_outlined, size: 13, color: Color(0xFF7ED69D)),
                                        SizedBox(width: 4),
                                        Text('Y aller',
                                            style: TextStyle(
                                                fontFamily: 'Galey',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF7ED69D))),
                                      ]),
                                    ),
                                  ),
                              ]),
                              const SizedBox(height: 8),
                            ],
                            Wrap(spacing: 12, runSpacing: 6, children: [
                              _badge(niveau, _niveauColor(niveau)),
                              if (duree != null) _badge('⏱ ${duree}min', Colors.grey),
                              if (distance != null)
                                _badge('📏 ${distance.toStringAsFixed(1)} km', Colors.grey),
                              _badge(
                                participantsMax != null
                                    ? '👥 $nbAccepted / $participantsMax participants'
                                    : '👥 $nbAccepted participant${nbAccepted > 1 ? 's' : ''}',
                                isFull ? Colors.red : Colors.grey,
                              ),
                            ]),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                              const SizedBox(height: 10),
                              Text(desc,
                                  style: TextStyle(
                                      fontFamily: 'Galey',
                                      fontSize: 13,
                                      color: Colors.white.withValues(alpha: 0.7))),
                            ],
                          ])),
                          const SizedBox(height: 10),

                          // ── Participants acceptés ──
                          if (accepted.isNotEmpty) ...[
                            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                '$nbAccepted participant${nbAccepted > 1 ? 's' : ''}',
                                style: const TextStyle(
                                    fontFamily: 'Galey',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Colors.white),
                              ),
                              const SizedBox(height: 10),
                              Wrap(spacing: 12, runSpacing: 10, children: accepted.map((part) {
                                final u = part['user'] as Map?;
                                final partUid = part['user_uid']?.toString() ?? '';
                                final partProfileId = part['user_profile_id']?.toString();
                                final isFriend = partProfileId != null && _friendProfileIds.contains(partProfileId);
                                return GestureDetector(
                                  onTap: partUid.isNotEmpty ? () => Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => PublicProfilePage(targetUid: partUid, targetProfileId: partProfileId))) : null,
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Stack(clipBehavior: Clip.none, children: [
                                      _avatar(u?['profile_picture_url']?.toString(), 20),
                                      if (isFriend)
                                        const Positioned(
                                          right: -2, bottom: -2,
                                          child: Text('❤', style: TextStyle(fontSize: 12)),
                                        ),
                                    ]),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      width: 52,
                                      child: Text(
                                        u?['firstname']?.toString() ?? '?',
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontFamily: 'Galey', fontSize: 10,
                                            color: Colors.white.withValues(alpha: 0.7)),
                                      ),
                                    ),
                                  ]),
                                );
                              }).toList()),
                            ])),
                            const SizedBox(height: 10),
                          ],

                          // ── Demandes en attente (organisateur seulement) ──
                          if (_isOrganizer && pending.isNotEmpty) ...[
                            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                const Text('Demandes en attente',
                                    style: TextStyle(
                                        fontFamily: 'Galey',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: Colors.white)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _orange,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text('${pending.length}',
                                      style: const TextStyle(
                                          fontFamily: 'Galey',
                                          fontSize: 11,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              ...pending.map((part) {
                                final u = part['user'] as Map?;
                                final nom =
                                    '${u?['firstname'] ?? ''} ${u?['lastname'] ?? ''}'.trim();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(children: [
                                    _avatar(u?['profile_picture_url']?.toString(), 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(nom.isEmpty ? 'Utilisateur' : nom,
                                          style: const TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white)),
                                    ),
                                    GestureDetector(
                                      onTap: () => _accept(part['user_uid'].toString()),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7ED69D),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Text('Accepter',
                                            style: TextStyle(
                                                fontFamily: 'Galey',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF071C22))),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () => _refuse(part['user_uid'].toString()),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                        ),
                                        child: const Text('Refuser',
                                            style: TextStyle(
                                                fontFamily: 'Galey',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.red)),
                                      ),
                                    ),
                                  ]),
                                );
                              }),
                            ])),
                            const SizedBox(height: 10),
                          ],

                          // ── Commentaires / discussion ─────────────────────────────────
                          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              const Text('Discussion',
                                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                      fontSize: 14, color: Colors.white)),
                              if (_uid.isNotEmpty && _messages.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF7ED69D),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text('${_messages.length}',
                                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                                          color: Color(0xFF071C22), fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 10),
                            if (_uid.isEmpty) ...[
                              // Non connecté → accès bloqué
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                                alignment: Alignment.center,
                                child: Column(children: [
                                  Icon(Icons.lock_outline, size: 32, color: Colors.white.withValues(alpha: 0.3)),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Connectez-vous pour voir la discussion',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                        color: Colors.white.withValues(alpha: 0.5)),
                                  ),
                                ]),
                              ),
                            ] else ...[
                            if (_messages.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text('Aucun message pour l\'instant.',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                        color: Colors.white.withValues(alpha: 0.5))),
                              ),
                            ..._messages.map((m) {
                              final u = m['user'] as Map?;
                              final nom = '${u?['firstname'] ?? ''} ${u?['lastname'] ?? ''}'.trim();
                              final isMe = m['user_uid'].toString() == _uid;
                              final ts = m['created_at'] != null
                                  ? DateFormat('dd/MM · HH:mm').format(
                                      DateTime.parse(m['created_at'].toString()).toLocal())
                                  : '';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                  children: [
                                    if (!isMe) ...[
                                      _avatar(u?['profile_picture_url']?.toString(), 16),
                                      const SizedBox(width: 8),
                                    ],
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                        children: [
                                          Row(mainAxisSize: MainAxisSize.min, children: [
                                            if (!isMe)
                                              Text(nom.isEmpty ? 'Utilisateur' : nom,
                                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                                                      fontWeight: FontWeight.w700, color: Color(0xFF7ED69D))),
                                            if (!isMe) const SizedBox(width: 6),
                                            Text(ts, style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                                                color: Colors.white.withValues(alpha: 0.3))),
                                          ]),
                                          const SizedBox(height: 3),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isMe
                                                  ? const Color(0xFF7ED69D).withValues(alpha: 0.15)
                                                  : Colors.white.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(isMe ? 12 : 0),
                                                topRight: Radius.circular(isMe ? 0 : 12),
                                                bottomLeft: const Radius.circular(12),
                                                bottomRight: const Radius.circular(12),
                                              ),
                                            ),
                                            child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (m['image_url'] != null)
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: CachedNetworkImage(
                                                    imageUrl: m['image_url'].toString(),
                                                    width: 180, fit: BoxFit.cover,
                                                  ),
                                                ),
                                              if (m['message'] != null)
                                                Text(m['message']?.toString() ?? '',
                                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                                                        color: Colors.white)),
                                            ],
                                          ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                            const SizedBox(height: 8),
                            if (_uid.isNotEmpty && (myStatut == 'accepte' || _isOrganizer))
                              Row(children: [
                                // Bouton photo
                                GestureDetector(
                                  onTap: _uploadingPhoto ? null : _sendPhoto,
                                  child: Container(
                                    width: 38, height: 38,
                                    decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
                                    child: _uploadingPhoto
                                        ? const Padding(padding: EdgeInsets.all(10),
                                            child: SizedBox(width: 16, height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7ED69D))))
                                        : const Icon(Icons.photo_camera_outlined, size: 20, color: Color(0xFF7ED69D)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _msgCtrl,
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white),
                                    maxLines: null,
                                    textCapitalization: TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      hintText: 'Écrire un message…',
                                      hintStyle: TextStyle(fontFamily: 'Galey',
                                          color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.08),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(20),
                                          borderSide: BorderSide.none),
                                      contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _sendingMsg ? null : _sendMessage,
                                  child: Container(
                                    width: 40, height: 40,
                                    decoration: const BoxDecoration(
                                        color: Color(0xFF7ED69D), shape: BoxShape.circle),
                                    child: _sendingMsg
                                        ? const Padding(padding: EdgeInsets.all(10),
                                            child: CircularProgressIndicator(color: Color(0xFF071C22), strokeWidth: 2))
                                        : const Icon(Icons.send_rounded, color: Color(0xFF071C22), size: 18),
                                  ),
                                ),
                              ])
                            else
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12)),
                                child: Row(children: [
                                  Icon(Icons.lock_outline, size: 14, color: Colors.white.withValues(alpha: 0.3)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(myStatut == 'en_attente'
                                        ? 'En attente d\'acceptation pour pouvoir écrire'
                                        : 'Rejoignez cette promenade pour participer à la discussion',
                                        style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                            color: Colors.white.withValues(alpha: 0.5))),
                                  ),
                                ]),
                              ),
                            ], // else (connecté)
                          ])),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_isOrganizer && _uid.isNotEmpty)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_darkC.withValues(alpha: 0), _darkC],
                    ),
                  ),
                  child: _buildJoinButton(myStatut, isFull),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinButton(String? myStatut, bool isFull) {
    if (myStatut == 'accepte') {
      return SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: _saving ? null : _leave,
          style: ElevatedButton.styleFrom(
            backgroundColor: _orange,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
          child: _saving
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Inscrit ✓ — Se désinscrire',
                  style: TextStyle(
                      fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15,
                      color: Colors.white)),
        ),
      );
    }
    if (myStatut == 'en_attente') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⏳ En attente de validation',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.amber)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: _saving ? null : _leave,
            child: Text('Annuler ma demande',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 12,
                    color: Colors.amber.withValues(alpha: 0.8),
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.amber.withValues(alpha: 0.8))),
          ),
        ]),
      );
    }
    if (isFull) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: const Text('Complet',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Colors.white)),
      );
    }
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _saving ? null : _join,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7ED69D),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
        child: _saving
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Color(0xFF071C22), strokeWidth: 2))
            : const Text('Rejoindre la promenade',
                style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15,
                    color: Color(0xFF071C22))),
      ),
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: child,
      );

  Widget _badge(String text, Color color) {
    final isGrey = color.toARGB32() == Colors.grey.toARGB32();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isGrey
            ? Colors.white.withValues(alpha: 0.08)
            : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isGrey
                ? Colors.white.withValues(alpha: 0.15)
                : color.withValues(alpha: 0.3)),
      ),
      child: Text(text,
          style: TextStyle(
              fontFamily: 'Galey',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isGrey ? Colors.white.withValues(alpha: 0.7) : color)),
    );
  }

  Widget _avatar(String? url, double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white.withValues(alpha: 0.12),
      backgroundImage:
          (url != null && url.isNotEmpty) ? CachedNetworkImageProvider(url) : null,
      child: (url == null || url.isEmpty)
          ? Icon(Icons.person_outline, size: radius, color: const Color(0xFF7ED69D))
          : null,
    );
  }
}

// ── Sheet modification ─────────────────────────────────────────────────────────

class _EditSheet extends StatefulWidget {
  final Map<String, dynamic> promenade;
  final Future<void> Function(String notifBody) onNotifyParticipants;
  const _EditSheet({required this.promenade, required this.onNotifyParticipants});

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  final _formKey = GlobalKey<FormState>();
  final _supa = Supabase.instance.client;

  late final TextEditingController _titreCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _lieuCtrl;
  String _niveau = 'facile';
  String _espece = 'Toutes espèces';
  bool _toutesRaces = true;
  late DateTime _dateHeure;
  late int _dureeMinutes;
  int? _participantsMax;
  double? _lat;
  double? _lng;
  bool _saving = false;

  late final TextEditingController _racesCtrl;

  // Google Places
  late final GoogleMapsPlaces _places;
  List<Prediction> _predictions = [];
  Timer? _debounce;
  bool _loadingPred = false;

  static const _kNiveaux = ['facile', 'moyen', 'difficile'];
  static const _kEspeces = ['Toutes', 'Chiens', 'Chevaux'];

  static String _especeEmoji(String e) => switch (e) {
    'Chiens'  => '🐕 Chiens',
    'Chevaux' => '🐴 Chevaux',
    _         => '🌍 Toutes',
  };

  @override
  void initState() {
    super.initState();
    final p = widget.promenade;
    _titreCtrl = TextEditingController(text: p['titre']?.toString() ?? '');
    _descCtrl = TextEditingController(text: p['description']?.toString() ?? '');
    _lieuCtrl = TextEditingController(text: p['lieu_rdv']?.toString() ?? '');
    _niveau = p['niveau']?.toString() ?? 'facile';
    _espece = p['espece']?.toString() ?? 'Toutes';
    _toutesRaces = p['toutes_races'] as bool? ?? true;
    _racesCtrl = TextEditingController(text: p['races']?.toString() ?? '');
    _dateHeure = p['date_heure'] != null
        ? DateTime.parse(p['date_heure'].toString()).toLocal()
        : DateTime.now().add(const Duration(days: 1));
    _dureeMinutes = (p['duree_minutes'] as num?)?.toInt() ?? 60;
    _participantsMax = (p['participants_max'] as num?)?.toInt();
    _lat = (p['lat'] as num?)?.toDouble();
    _lng = (p['lng'] as num?)?.toDouble();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
  }

  @override
  void dispose() {
    _titreCtrl.dispose();
    _descCtrl.dispose();
    _lieuCtrl.dispose();
    _racesCtrl.dispose();
    _places.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onLieuChanged(String val) {
    _debounce?.cancel();
    setState(() { _lat = null; _lng = null; });
    if (val.trim().length < 3) { setState(() { _predictions = []; _loadingPred = false; }); return; }
    setState(() => _loadingPred = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final res = await _places.autocomplete(val,
          components: [Component(Component.country, 'fr')], language: 'fr');
      if (!mounted) return;
      setState(() { _predictions = res.isOkay ? res.predictions : []; _loadingPred = false; });
    });
  }

  Future<void> _selectPrediction(Prediction p) async {
    _debounce?.cancel();
    setState(() { _predictions = []; _lieuCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;
    final det = await _places.getDetailsByPlaceId(p.placeId!);
    if (!mounted || !det.isOkay) return;
    final loc = det.result.geometry?.location;
    if (loc != null) setState(() { _lat = loc.lat; _lng = loc.lng; });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateHeure,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
          data: ThemeData.light()
              .copyWith(colorScheme: const ColorScheme.light(primary: _orange)),
          child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_dateHeure));
    if (time == null || !mounted) return;
    setState(() => _dateHeure =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      final updates = <String, dynamic>{
        'titre': _titreCtrl.text.trim(),
        'lieu_rdv': _lieuCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'niveau': _niveau,
        'date_heure': _dateHeure.toIso8601String(),
        'duree_minutes': _dureeMinutes,
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
        'participants_max': _participantsMax,
        'espece': _espece,
        'toutes_races': _toutesRaces,
        'races': (!_toutesRaces && _racesCtrl.text.trim().isNotEmpty) ? _racesCtrl.text.trim() : null,
      };
      await _supa.from('promenades')
          .update(updates)
          .eq('id', widget.promenade['id'].toString());

      // Notifier les participants
      final titre = _titreCtrl.text.trim();
      final dateStr = DateFormat('dd/MM à HH:mm').format(_dateHeure);
      await widget.onNotifyParticipants(
          'La promenade "$titre" a été modifiée. Nouvelles infos : ${_lieuCtrl.text.trim()}, $dateStr.');

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
          left: 20, right: 20, top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('Modifier la promenade',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18))),
              IconButton(icon: const Icon(Icons.close, size: 22, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ]),
            const SizedBox(height: 20),

            _lbl('Titre *'),
            TextFormField(
              controller: _titreCtrl,
              decoration: _dec('Titre de la promenade'),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
            ),
            const SizedBox(height: 12),

            _lbl('Lieu de rendez-vous *'),
            TextFormField(
              controller: _lieuCtrl,
              onChanged: _onLieuChanged,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
              decoration: _dec('Rechercher une adresse…').copyWith(
                prefixIcon: const Icon(Icons.search, size: 18, color: _green),
                suffixIcon: _loadingPred
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _green)))
                    : (_lat != null
                        ? const Icon(Icons.check_circle_outline, size: 18, color: _green)
                        : null),
              ),
            ),
            if (_predictions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8, offset: const Offset(0, 4))]),
                child: ListView.separated(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  itemCount: _predictions.length > 5 ? 5 : _predictions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 40),
                  itemBuilder: (_, i) {
                    final p = _predictions[i];
                    return ListTile(dense: true,
                        leading: const Icon(Icons.location_on_outlined, size: 18, color: _green),
                        title: Text(p.description ?? '',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                        onTap: () => _selectPrediction(p));
                  },
                ),
              ),
            const SizedBox(height: 12),

            _lbl('Date et heure *'),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300)),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: _orange),
                  const SizedBox(width: 10),
                  Text(DateFormat('dd/MM/yyyy · HH:mm').format(_dateHeure),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _lbl('Niveau'),
                InputDecorator(decoration: _dec(''),
                  child: DropdownButton<String>(value: _niveau, isExpanded: true, underline: const SizedBox(),
                    items: _kNiveaux.map((n) => DropdownMenuItem(value: n,
                        child: Text(n, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)))).toList(),
                    onChanged: (v) => setState(() => _niveau = v ?? 'facile')),
                ),
              ])),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _lbl('Durée (min)'),
                TextFormField(
                  initialValue: '$_dureeMinutes',
                  decoration: _dec('60'),
                  keyboardType: TextInputType.number,
                  onSaved: (v) => _dureeMinutes = int.tryParse(v?.trim() ?? '') ?? 60,
                ),
              ])),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _lbl('Max participants'),
                TextFormField(
                  initialValue: _participantsMax?.toString() ?? '',
                  decoration: _dec('Illimité'),
                  keyboardType: TextInputType.number,
                  onSaved: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    _participantsMax = (n != null && n >= 2) ? n : null;
                  },
                ),
              ])),
            ]),
            const SizedBox(height: 12),

            _lbl('Description'),
            TextFormField(
              controller: _descCtrl,
              decoration: _dec('Parcours, équipement recommandé…'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            _lbl('Espèce concernée'),
            Wrap(spacing: 6, runSpacing: 6, children: _kEspeces.map((e) {
              final sel = _espece == e;
              return GestureDetector(
                onTap: () => setState(() => _espece = e),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? _green : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_especeEmoji(e),
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : Colors.grey.shade700)),
                ),
              );
            }).toList()),
            const SizedBox(height: 12),

            Row(children: [
              const Expanded(child: Text('Toutes races acceptées',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600))),
              Switch(
                value: _toutesRaces,
                onChanged: (v) => setState(() => _toutesRaces = v),
                activeThumbColor: _green,
              ),
            ]),
            if (!_toutesRaces) ...[
              const SizedBox(height: 6),
              TextFormField(
                controller: _racesCtrl,
                decoration: _dec('Ex : Golden Retriever, Labrador…'),
              ),
            ],
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: _orange,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _saving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Enregistrer les modifications',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(t, style: const TextStyle(
          fontFamily: 'Galey', fontWeight: FontWeight.w600,
          fontSize: 13, color: Color(0xFF6F767B))));

  InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12));
}
