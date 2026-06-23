import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PublicProfilePage extends StatefulWidget {
  final String targetUid;
  const PublicProfilePage({super.key, required this.targetUid});

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  final _supa = Supabase.instance.client;
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  static const _green = Color(0xFF2E7D5E);

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _animaux = [];
  // statut de la relation : null | 'en_attente' | 'accepte'
  // + direction : 'sent' | 'received'
  String? _relStatut;
  String? _relDirection;
  String? _relId;
  bool _loading = true;
  bool _saving = false;

  bool get _isMe => widget.targetUid == _myUid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Profil
      final p = await _supa
          .from('users')
          .select('uid, firstname, lastname, profile_picture_url, city, profile_type')
          .eq('uid', widget.targetUid)
          .maybeSingle();

      // Relation PetFriend
      String? relStatut, relDir, relId;
      if (!_isMe) {
        final sent = await _supa
            .from('petfriends')
            .select('id, statut')
            .eq('uid_demandeur', _myUid)
            .eq('uid_recepteur', widget.targetUid)
            .maybeSingle();
        if (sent != null) {
          relId = sent['id'].toString();
          relStatut = sent['statut'].toString();
          relDir = 'sent';
        } else {
          final received = await _supa
              .from('petfriends')
              .select('id, statut')
              .eq('uid_demandeur', widget.targetUid)
              .eq('uid_recepteur', _myUid)
              .maybeSingle();
          if (received != null) {
            relId = received['id'].toString();
            relStatut = received['statut'].toString();
            relDir = 'received';
          }
        }
      }

      // Animaux : visibles si ami accepté, sinon uniquement publics
      final bool isFriend = relStatut == 'accepte';
      List<Map<String, dynamic>> animaux = [];
      if (isFriend) {
        final res = await _supa
            .from('animaux')
            .select('id, nom, espece, race, age, photo')
            .eq('uid_proprietaire', widget.targetUid)
            .eq('est_actif', true);
        animaux = List<Map<String, dynamic>>.from(res as List);
      } else {
        // Uniquement les animaux non-marqués petfriends-only (visible_petfriends = false)
        final res = await _supa
            .from('animaux')
            .select('id, nom, espece, race, age, photo')
            .eq('uid_proprietaire', widget.targetUid)
            .eq('est_actif', true)
            .eq('visible_petfriends', false);
        animaux = List<Map<String, dynamic>>.from(res as List);
      }

      if (mounted) {
        setState(() {
          _profile = p != null ? Map<String, dynamic>.from(p) : null;
          _animaux = animaux;
          _relStatut = relStatut;
          _relDirection = relDir;
          _relId = relId;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendRequest() async {
    setState(() => _saving = true);
    try {
      final res = await _supa.from('petfriends').insert({
        'uid_demandeur': _myUid,
        'uid_recepteur': widget.targetUid,
        'statut': 'en_attente',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).select('id').single();

      // Notifier la cible
      final me = await _supa
          .from('users')
          .select('firstname, lastname')
          .eq('uid', _myUid)
          .maybeSingle();
      final nom = me != null
          ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim()
          : 'Quelqu\'un';
      await _supa.from('notifications').insert({
        'uid': widget.targetUid,
        'type': 'petfriend_request',
        'title': '🐾 Nouvelle demande PetFriend',
        'body': '$nom veut être ton PetFriend !',
        'data': {'fromUid': _myUid},
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        setState(() {
          _relId = res['id'].toString();
          _relStatut = 'en_attente';
          _relDirection = 'sent';
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelRequest() async {
    if (_relId == null) return;
    setState(() => _saving = true);
    await _supa.from('petfriends').delete().eq('id', _relId!);
    if (mounted) setState(() { _relStatut = null; _relDirection = null; _relId = null; _saving = false; });
  }

  Future<void> _accept() async {
    if (_relId == null) return;
    setState(() => _saving = true);
    await _supa.from('petfriends').update({
      'statut': 'accepte',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', _relId!);

    // Notifier le demandeur
    final me = await _supa.from('users').select('firstname, lastname').eq('uid', _myUid).maybeSingle();
    final nom = me != null ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim() : 'Quelqu\'un';
    await _supa.from('notifications').insert({
      'uid': widget.targetUid,
      'type': 'petfriend_accepted',
      'title': '🐾 PetFriend accepté !',
      'body': '$nom a accepté ta demande PetFriend.',
      'data': {'fromUid': _myUid},
      'read': false,
      'created_at': DateTime.now().toIso8601String(),
    });

    if (mounted) {
      setState(() { _relStatut = 'accepte'; _saving = false; });
      _load();
    }
  }

  Future<void> _removeFriend() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce PetFriend ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Vous ne serez plus PetFriends.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || _relId == null) return;
    setState(() => _saving = true);
    await _supa.from('petfriends').delete().eq('id', _relId!);
    if (mounted) setState(() { _relStatut = null; _relDirection = null; _relId = null; _saving = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: AppBar(backgroundColor: _green, foregroundColor: Colors.white,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context))),
        body: const Center(child: CircularProgressIndicator(color: _green)),
      );
    }

    if (_profile == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: AppBar(backgroundColor: _green, foregroundColor: Colors.white,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context))),
        body: const Center(child: Text('Profil introuvable',
            style: TextStyle(fontFamily: 'Galey', fontSize: 16))),
      );
    }

    final p = _profile!;
    final nom = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
    final city = p['city']?.toString() ?? '';
    final photoUrl = p['profile_picture_url']?.toString() ?? '';
    final isFriend = _relStatut == 'accepte';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(nom.isNotEmpty ? nom : 'Profil',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Card profil ──
          _card(Column(children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: const Color(0xFFE8F5E9),
              backgroundImage: photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl) : null,
              child: photoUrl.isEmpty
                  ? Icon(Icons.person_outline, size: 44, color: _green)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(nom.isNotEmpty ? nom : '—',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20)),
            if (city.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(city, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
              ]),
            ],
            const SizedBox(height: 4),
            if (isFriend)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: _green.withAlpha(20), borderRadius: BorderRadius.circular(20)),
                child: const Text('🐾 PetFriend',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        fontWeight: FontWeight.w600, color: _green)),
              ),
            if (!_isMe) ...[
              const SizedBox(height: 16),
              _petFriendButton(),
            ],
          ])),
          const SizedBox(height: 16),

          // ── Animaux ──
          _sectionTitle('Animaux', _animaux.length),
          if (_animaux.isEmpty)
            _card(Center(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                isFriend
                    ? 'Aucun animal partagé'
                    : 'Devenez PetFriends pour voir ses animaux',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            )))
          else
            _card(Wrap(
              spacing: 12, runSpacing: 12,
              children: _animaux.map((a) => _animalChip(a)).toList(),
            )),
        ],
      ),
    );
  }

  Widget _petFriendButton() {
    if (_saving) {
      return const SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: _green));
    }

    if (_relStatut == null) {
      return FilledButton.icon(
        onPressed: _sendRequest,
        style: FilledButton.styleFrom(backgroundColor: _green,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
        icon: const Icon(Icons.person_add_outlined, size: 18),
        label: const Text('Ajouter en PetFriend',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      );
    }

    if (_relStatut == 'en_attente' && _relDirection == 'sent') {
      return OutlinedButton.icon(
        onPressed: _cancelRequest,
        style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey,
            side: const BorderSide(color: Colors.grey),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
        icon: const Icon(Icons.hourglass_empty, size: 16),
        label: const Text('En attente… (annuler)',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
      );
    }

    if (_relStatut == 'en_attente' && _relDirection == 'received') {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        FilledButton(
          onPressed: _accept,
          style: FilledButton.styleFrom(backgroundColor: _green,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          child: const Text('Accepter',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: _cancelRequest,
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          child: const Text('Refuser',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ]);
    }

    if (_relStatut == 'accepte') {
      return OutlinedButton.icon(
        onPressed: _removeFriend,
        style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
        icon: const Icon(Icons.person_remove_outlined, size: 18),
        label: const Text('Supprimer PetFriend',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _animalChip(Map<String, dynamic> a) {
    final photo = a['photo']?.toString() ?? '';
    final nom = a['nom']?.toString() ?? '—';
    final espece = a['espece']?.toString() ?? '';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(
        radius: 30,
        backgroundColor: const Color(0xFFE8F5E9),
        backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
        child: photo.isEmpty ? const Icon(Icons.pets, size: 22, color: _green) : null,
      ),
      const SizedBox(height: 4),
      Text(nom, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
      Text(espece, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey)),
    ]);
  }

  Widget _sectionTitle(String title, int count) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Text(title,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: _green.withAlpha(20), borderRadius: BorderRadius.circular(12)),
          child: Text('$count',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                  fontWeight: FontWeight.w600, color: _green)),
        ),
      ]));

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: child,
      );
}
