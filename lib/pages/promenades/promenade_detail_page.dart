import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _green = Color(0xFF2E7D5E);
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
  bool _loading = true;
  bool _saving = false;

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await _supa
          .from('promenades')
          .select()
          .eq('id', widget.promenadeId)
          .single();

      final org = await _supa
          .from('users')
          .select('firstname, lastname, profile_picture_url')
          .eq('uid', p['organisateur_uid'].toString())
          .maybeSingle();

      final rawParts = await _supa
          .from('promenades_participants')
          .select('user_uid, statut, rejoint_at')
          .eq('promenade_id', widget.promenadeId)
          .order('rejoint_at');

      final List<Map<String, dynamic>> parts = [];
      final uids = (rawParts as List).map((r) => r['user_uid'].toString()).toList();
      if (uids.isNotEmpty) {
        final usersData = await _supa
            .from('users')
            .select('uid, firstname, lastname, profile_picture_url')
            .inFilter('uid', uids);
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

      if (mounted) {
        setState(() {
          _promenade = Map<String, dynamic>.from(p);
          _organizer = org != null ? Map<String, dynamic>.from(org) : null;
          _participants = parts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    if (_uid.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _supa.from('promenades_participants').insert({
        'promenade_id': widget.promenadeId,
        'user_uid': _uid,
        'statut': 'en_attente',
        'rejoint_at': DateTime.now().toIso8601String(),
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

  Future<void> _leave() async {
    if (_uid.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _supa
          .from('promenades_participants')
          .delete()
          .eq('promenade_id', widget.promenadeId)
          .eq('user_uid', _uid);
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
          .from('users')
          .select('firstname, lastname')
          .eq('uid', _uid)
          .maybeSingle();
      final nom = me != null
          ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim()
          : 'Quelqu\'un';
      await _supa.from('notifications').insert({
        'user_uid': orgUid,
        'type': 'promenade_join',
        'title': 'Nouvelle demande de participation',
        'body': '$nom veut rejoindre "${p['titre']}"',
        'data': {'promenadeId': widget.promenadeId, 'fromUid': _uid},
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _accept(String userUid) async {
    await _supa
        .from('promenades_participants')
        .update({'statut': 'accepte'})
        .eq('promenade_id', widget.promenadeId)
        .eq('user_uid', userUid);
    try {
      await _supa.from('notifications').insert({
        'user_uid': userUid,
        'type': 'promenade_accepte',
        'title': 'Participation confirmée',
        'body': 'Votre demande pour "${_promenade!['titre']}" a été acceptée !',
        'data': {'promenadeId': widget.promenadeId},
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
    _load();
  }

  Future<void> _refuse(String userUid) async {
    await _supa
        .from('promenades_participants')
        .delete()
        .eq('promenade_id', widget.promenadeId)
        .eq('user_uid', userUid);
    try {
      await _supa.from('notifications').insert({
        'user_uid': userUid,
        'type': 'promenade_refuse',
        'title': 'Participation refusée',
        'body': 'Votre demande pour "${_promenade!['titre']}" n\'a pas été retenue.',
        'data': {'promenadeId': widget.promenadeId},
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
    _load();
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
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator(color: _orange)),
      );
    }

    if (_promenade == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: _green, foregroundColor: Colors.white),
        body: const Center(child: Text('Promenade introuvable')),
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
        title: Text(titre,
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
            overflow: TextOverflow.ellipsis),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _orange,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Organisateur ──
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Organisé par',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              Row(children: [
                _avatar(_organizer?['profile_picture_url']?.toString(), 22),
                const SizedBox(width: 10),
                Text(
                  '${_organizer?['firstname'] ?? ''} ${_organizer?['lastname'] ?? ''}'.trim().isEmpty
                      ? 'Organisateur'
                      : '${_organizer?['firstname'] ?? ''} ${_organizer?['lastname'] ?? ''}'.trim(),
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                ),
              ]),
            ])),
            const SizedBox(height: 10),

            // ── Infos ──
            _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (dateHeure.isNotEmpty) ...[
                Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 14, color: _green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_fmtDate(dateHeure),
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 8),
              ],
              if (lieu.isNotEmpty) ...[
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: _green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(lieu,
                        style: const TextStyle(
                            fontFamily: 'Galey', fontSize: 13, color: Color(0xFF444))),
                  ),
                  if (lat != null && lng != null)
                    GestureDetector(
                      onTap: () => _openNavigation(lat, lng),
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.navigation_outlined, size: 13, color: _green),
                          SizedBox(width: 4),
                          Text('Y aller',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _green)),
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
                const Divider(height: 1),
                const SizedBox(height: 10),
                Text(desc,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 13,
                        color: Color(0xFF555))),
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
                      fontSize: 14),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 12, runSpacing: 10, children: accepted.map((part) {
                  final u = part['user'] as Map?;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    _avatar(u?['profile_picture_url']?.toString(), 20),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 52,
                      child: Text(
                        u?['firstname']?.toString() ?? '?',
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Galey', fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  ]);
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
                          fontSize: 14)),
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
                                fontWeight: FontWeight.w600)),
                      ),
                      GestureDetector(
                        onTap: () => _accept(part['user_uid'].toString()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _green,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Accepter',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _refuse(part['user_uid'].toString()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Refuser',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade400)),
                        ),
                      ),
                    ]),
                  );
                }),
              ])),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),

      // ── Bouton rejoindre / en attente / inscrit ──
      bottomNavigationBar: !_isOrganizer && _uid.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _buildJoinButton(myStatut, isFull),
              ),
            )
          : null,
    );
  }

  Widget _buildJoinButton(String? myStatut, bool isFull) {
    if (myStatut == 'accepte') {
      return FilledButton(
        onPressed: _saving ? null : _leave,
        style: FilledButton.styleFrom(
            backgroundColor: _orange,
            padding: const EdgeInsets.symmetric(vertical: 14)),
        child: _saving
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Inscrit ✓ — Se désinscrire',
                style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
      );
    }
    if (myStatut == 'en_attente') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('⏳ En attente de validation',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.amber.shade800)),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: _saving ? null : _leave,
            child: Text('Annuler ma demande',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 12,
                    color: Colors.amber.shade700,
                    decoration: TextDecoration.underline)),
          ),
        ]),
      );
    }
    if (isFull) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text('Complet',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Colors.grey)),
      );
    }
    return FilledButton(
      onPressed: _saving ? null : _join,
      style: FilledButton.styleFrom(
          backgroundColor: _green,
          padding: const EdgeInsets.symmetric(vertical: 14)),
      child: _saving
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text('Rejoindre la promenade',
              style: TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: child,
      );

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontFamily: 'Galey',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
      );

  Widget _avatar(String? url, double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE8F5E9),
      backgroundImage:
          (url != null && url.isNotEmpty) ? CachedNetworkImageProvider(url) : null,
      child: (url == null || url.isEmpty)
          ? Icon(Icons.person_outline, size: radius, color: _green)
          : null,
    );
  }
}
