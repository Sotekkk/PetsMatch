import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'package:PetsMatch/pages/chatScreen.dart' show LocationCard;

class PetFriendChatPage extends StatefulWidget {
  final String conversationId;
  final String convNom; // nom affiché (prénom ami ou nom groupe)
  final bool isGroupe;

  const PetFriendChatPage({
    super.key,
    required this.conversationId,
    required this.convNom,
    this.isGroupe = false,
  });

  @override
  State<PetFriendChatPage> createState() => _PetFriendChatPageState();
}

class _PetFriendChatPageState extends State<PetFriendChatPage> {
  static final _supa = Supabase.instance.client;
  static String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF2E7D5E);
  static const _bgMsg = Color(0xFFE8F5E9);

  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic> _participantsInfo = {};
  bool _sending = false;
  RealtimeChannel? _channel;
  String? _myProfileId;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeRealtime();
    _markRead();
    _setActiveConversation(widget.conversationId);
  }

  @override
  void dispose() {
    _setActiveConversation(null);
    _channel?.unsubscribe();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Évite de notifier quelqu'un qui a déjà la conversation ouverte — même
  // mécanisme que chatScreen.dart (users.active_conversation_id).
  void _setActiveConversation(String? convId) {
    if (_myUid.isEmpty) return;
    _supa.from('users').update({'active_conversation_id': convId})
        .eq('uid', _myUid).then((_) {}).catchError((_) {});
  }

  Future<void> _loadMessages() async {
    try {
      // Charger la conversation pour récupérer participants_info
      final conv = await _supa
          .from('conversations')
          .select('participants_info')
          .eq('id', widget.conversationId)
          .maybeSingle();
      if (conv != null && conv['participants_info'] != null) {
        _participantsInfo = Map<String, dynamic>.from(conv['participants_info'] as Map);
      }

      final rows = await _supa
          .from('messages')
          .select()
          .eq('conversation_id', widget.conversationId)
          .order('created_at');
      if (mounted) {
        setState(() => _messages = List<Map<String, dynamic>>.from(rows));
        _scrollBottom();
      }
    } catch (_) {}
  }

  void _subscribeRealtime() {
    _channel = _supa
        .channel('pf_messages_${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (mounted) {
              setState(() => _messages.add(row));
              _scrollBottom();
              if (row['sender_id'] != _myUid) _markRead();
            }
          },
        )
        .subscribe();
  }

  Future<void> _markRead() async {
    try {
      final conv = await _supa
          .from('conversations')
          .select('unread_count')
          .eq('id', widget.conversationId)
          .maybeSingle();
      if (conv == null) return;
      final unread = Map<String, dynamic>.from(conv['unread_count'] as Map? ?? {});
      if ((unread[_myUid] ?? 0) > 0) {
        unread[_myUid] = 0;
        await _supa.from('conversations').update({'unread_count': unread})
            .eq('id', widget.conversationId);
      }
    } catch (_) {}
  }

  Future<void> _send({String? text, String? imageUrl, double? lat, double? lng, String? gardeId}) async {
    final t = text?.trim() ?? '';
    if (t.isEmpty && imageUrl == null && lat == null && gardeId == null) return;
    setState(() => _sending = true);
    try {
      final myInfo = _participantsInfo[_myUid] as Map? ?? {};
      final myName = myInfo['name']?.toString() ?? '';

      await _supa.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id':       _myUid,
        'text':            t.isNotEmpty ? t : null,
        'image_url':       imageUrl,
        'msg_type':        imageUrl != null ? 'image' : (lat != null ? 'location' : (gardeId != null ? 'garde_request' : 'text')),
        'lat':             lat,
        'lng':             lng,
        'garde_id':        gardeId,
        'is_read':         false,
      });

      // Mettre à jour last_message + unread des autres
      final conv = await _supa
          .from('conversations')
          .select('participants, unread_count')
          .eq('id', widget.conversationId)
          .maybeSingle();
      if (conv != null) {
        final members = List<String>.from((conv['participants'] as List?)?.map((e) => e.toString()) ?? []);
        final unread = Map<String, dynamic>.from(conv['unread_count'] as Map? ?? {});
        for (final uid in members) {
          if (uid != _myUid) unread[uid] = (unread[uid] as int? ?? 0) + 1;
        }
        // Stocker le nom de l'expéditeur dans participants_info
        final updatedInfo = Map<String, dynamic>.from(_participantsInfo);
        if (myName.isEmpty) {
          final me = await _supa.from('user_profiles')
              .select('firstname, lastname, avatar_url')
              .eq('uid', _myUid).eq('is_main', true).maybeSingle();
          if (me != null) {
            updatedInfo[_myUid] = {
              'name': '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim(),
              if ((me['avatar_url'] as String?)?.isNotEmpty == true)
                'photo': me['avatar_url'],
            };
            setState(() => _participantsInfo = updatedInfo);
          }
        }
        final previewText = imageUrl != null ? '📷 Photo' : (lat != null ? '📍 Position' : (gardeId != null ? '🐾 Demande de dépannage' : (t.length > 80 ? '${t.substring(0, 80)}…' : t)));
        await _supa.from('conversations').update({
          'last_message': previewText,
          'updated_at':   DateTime.now().toIso8601String(),
          'unread_count': unread,
          'participants_info': updatedInfo,
        }).eq('id', widget.conversationId);

        // Notif push fire-and-forget pour chaque destinataire pas déjà dans
        // la conv (1-1 ET groupe — ni l'un ni l'autre n'en envoyaient avant).
        final senderName = (updatedInfo[_myUid] as Map?)?['name']?.toString();
        final recipients = members.where((u) => u != _myUid).toSet().toList();
        if (recipients.isNotEmpty) {
          final userRows = await _supa.from('users')
              .select('uid, active_conversation_id')
              .inFilter('uid', recipients);
          for (final r in (userRows as List)) {
            final uid = r['uid'] as String;
            if (r['active_conversation_id'] == widget.conversationId) continue;
            _supa.from('notifications').insert({
              'uid':   uid,
              'type':  'message',
              'title': (senderName?.isNotEmpty == true ? senderName! : 'Nouveau message')
                  + (widget.isGroupe ? ' · ${widget.convNom}' : ''),
              'body':  previewText,
              'data':  {'conversation_id': widget.conversationId},
              'read':  false,
            }).then((_) {}).catchError((_) {});
          }
        }
      }

      _ctrl.clear();
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _shareLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activez la localisation', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    if (!mounted) return;
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Partager ma position', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: const Text('Envoyer vos coordonnées GPS actuelles à cet ami ? Pratique pour organiser une balade.',
          style: TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer', style: TextStyle(color: _green, fontWeight: FontWeight.w700))),
      ],
    ));
    if (confirm != true) return;
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      await _send(lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur GPS : $e', style: const TextStyle(fontFamily: 'Galey'))));
    }
  }

  Future<String?> _resolveMyProfileId() async {
    if (_myProfileId != null) return _myProfileId;
    final row = await _supa.from('user_profiles')
        .select('id')
        .eq('uid', _myUid).eq('profile_type', 'particulier').eq('is_main', true)
        .maybeSingle();
    _myProfileId = row?['id']?.toString();
    return _myProfileId;
  }

  Future<List<Map<String, dynamic>>> _loadMyAnimaux(String myProfileId) async {
    final ownRows = await _supa.from('animaux_proprietes')
        .select('animal_id')
        .eq('uid_proprio', _myUid)
        .eq('profile_id_proprio', myProfileId)
        .isFilter('date_fin', null);
    final ids = List<Map<String, dynamic>>.from(ownRows as List)
        .map((r) => r['animal_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return [];
    return List<Map<String, dynamic>>.from(
      await _supa.from('animaux').select('id, nom, espece, photo_url').inFilter('id', ids) as List,
    );
  }

  Future<void> _requestGardeEntraide() async {
    final myProfileId = await _resolveMyProfileId();
    if (myProfileId == null) return;

    final conv = await _supa.from('conversations')
        .select('participants').eq('id', widget.conversationId).maybeSingle();
    final members = List<String>.from((conv?['participants'] as List?)?.map((e) => e.toString()) ?? []);
    final otherUid = members.firstWhere((u) => u != _myUid, orElse: () => '');
    if (otherUid.isEmpty) return;
    final otherProfile = await _supa.from('user_profiles')
        .select('id').eq('uid', otherUid).eq('profile_type', 'particulier').eq('is_main', true).maybeSingle();

    final animaux = await _loadMyAnimaux(myProfileId);
    if (!mounted) return;

    Map<String, dynamic>? selectedAnimal = animaux.isNotEmpty ? animaux.first : null;
    DateTimeRange? range;
    final msgCtrl = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Demander un dépannage', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 4),
            const Text('Demandez à votre ami de s\'occuper d\'un de vos animaux sur une période.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            if (animaux.isEmpty)
              const Text('Vous n\'avez aucun animal enregistré.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey))
            else
              Wrap(spacing: 8, runSpacing: 8, children: animaux.map((a) {
                final sel = selectedAnimal?['id'] == a['id'];
                return ChoiceChip(
                  label: Text('${a['nom'] ?? ''}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  selected: sel,
                  selectedColor: _green.withValues(alpha: 0.15),
                  labelStyle: TextStyle(color: sel ? _green : Colors.black87, fontWeight: sel ? FontWeight.w700 : FontWeight.w400),
                  onSelected: (_) => setModal(() => selectedAnimal = a),
                );
              }).toList()),
            const SizedBox(height: 14),
            InkWell(
              onTap: () async {
                final r = await showDateRangePicker(
                  context: ctx,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDateRange: range,
                  locale: const Locale('fr'),
                );
                if (r != null) setModal(() => range = r);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.date_range, color: _green, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    range == null
                        ? 'Choisir les dates'
                        : '${DateFormat('dd/MM/yyyy').format(range!.start)} → ${DateFormat('dd/MM/yyyy').format(range!.end)}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: msgCtrl,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Précisions (facultatif)…',
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (selectedAnimal == null || range == null)
                    ? null
                    : () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Envoyer la demande', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      )),
    );

    if (result != true || selectedAnimal == null || range == null) return;

    setState(() => _sending = true);
    try {
      final row = await _supa.from('garde_entraide').insert({
        'uid_demandeur': _myUid,
        'uid_recepteur': otherUid,
        'demandeur_profile_id': myProfileId,
        'recepteur_profile_id': otherProfile?['id'],
        'conversation_id': widget.conversationId,
        'animal_id': selectedAnimal!['id'],
        'animal_nom': selectedAnimal!['nom'],
        'date_debut': DateFormat('yyyy-MM-dd').format(range!.start),
        'date_fin': DateFormat('yyyy-MM-dd').format(range!.end),
        'message': msgCtrl.text.trim().isNotEmpty ? msgCtrl.text.trim() : null,
      }).select('id').single();
      await _send(gardeId: row['id'].toString());
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file == null) return;
    setState(() => _sending = true);
    try {
      final path = 'chat_images/${_myUid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url = await storage.uploadPhoto(File(file.path), path, quality: 70);
      await _send(imageUrl: url);
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  String _fmtTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return DateFormat('HH:mm').format(dt);
    }
    return DateFormat('dd/MM HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white24,
            child: Icon(widget.isGroupe ? Icons.group : Icons.person,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.convNom,
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          if (!widget.isGroupe)
            IconButton(
              onPressed: _sending ? null : _requestGardeEntraide,
              icon: const Icon(Icons.pets, color: Colors.white),
              tooltip: 'Demander un dépannage',
            ),
        ],
      ),
      body: Column(children: [
        // ── Messages ──
        Expanded(
          child: _messages.isEmpty
              ? const Center(child: Text('Aucun message, dites bonjour 👋',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _buildMessage(_messages[i]),
                ),
        ),

        // ── Barre saisie ──
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).viewInsets.bottom + 8),
          child: Row(children: [
            IconButton(
              onPressed: _picking ? null : _pickImage,
              icon: const Icon(Icons.image_outlined, color: _green),
            ),
            if (!widget.isGroupe)
              IconButton(
                onPressed: _shareLocation,
                icon: const Icon(Icons.location_on_outlined, color: _green),
                tooltip: 'Partager ma position',
              ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                maxLines: 4, minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (v) => _send(text: v),
                decoration: InputDecoration(
                  hintText: 'Votre message…',
                  hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFFF5F7F5),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _green)))
                : IconButton(
                    onPressed: () => _send(text: _ctrl.text),
                    icon: const Icon(Icons.send_rounded),
                    color: _green,
                  ),
          ]),
        ),
      ]),
    );
  }

  bool get _picking => false; // pour désactiver le bouton pendant upload

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isMe = msg['sender_id']?.toString() == _myUid;
    final text = msg['text']?.toString() ?? '';
    final imageUrl = msg['image_url']?.toString() ?? '';
    final isLocation = msg['msg_type'] == 'location';
    final isGardeRequest = msg['msg_type'] == 'garde_request';
    final time = _fmtTime(msg['created_at']?.toString());
    final senderId = msg['sender_id']?.toString() ?? '';

    // Nom expéditeur pour groupes
    String? senderName;
    if (widget.isGroupe && !isMe) {
      final info = _participantsInfo[senderId] as Map?;
      senderName = info?['name']?.toString();
    }
    final senderPhoto = (_participantsInfo[senderId] as Map?)?['photo']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && widget.isGroupe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFFE8F5E9),
              backgroundImage: senderPhoto.isNotEmpty ? CachedNetworkImageProvider(senderPhoto) : null,
              child: senderPhoto.isEmpty ? const Icon(Icons.person, size: 14, color: _green) : null,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (senderName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, left: 2),
                    child: Text(senderName,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                            fontWeight: FontWeight.w600, color: _green)),
                  ),
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                  padding: imageUrl.isNotEmpty || isLocation || isGardeRequest
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? _teal : _bgMsg,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 200, height: 200, fit: BoxFit.cover,
                          ),
                        )
                      : isLocation
                          ? LocationCard(
                              lat: (msg['lat'] as num).toDouble(),
                              lng: (msg['lng'] as num).toDouble(),
                              isMe: isMe,
                            )
                          : isGardeRequest
                              ? _GardeRequestCard(
                                  gardeId: msg['garde_id'].toString(),
                                  isMe: isMe,
                                  myUid: _myUid,
                                )
                              : Text(text,
                                  style: TextStyle(
                                    fontFamily: 'Galey', fontSize: 14,
                                    color: isMe ? Colors.white : const Color(0xFF1F2A2E),
                                  )),
                ),
                const SizedBox(height: 2),
                Text(time, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte affichée dans le chat PetFriends pour une demande de garde/dépannage
/// entre particuliers (entraide informelle, ≠ module garde PRO).
class _GardeRequestCard extends StatefulWidget {
  final String gardeId;
  final bool isMe;
  final String myUid;

  const _GardeRequestCard({required this.gardeId, required this.isMe, required this.myUid});

  @override
  State<_GardeRequestCard> createState() => _GardeRequestCardState();
}

class _GardeRequestCardState extends State<_GardeRequestCard> {
  static final _supa = Supabase.instance.client;
  static const _green = Color(0xFF2E7D5E);

  Map<String, dynamic>? _row;
  bool _loading = true;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await _supa.from('garde_entraide').select().eq('id', widget.gardeId).maybeSingle();
      if (mounted) setState(() { _row = row; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatut(String statut) async {
    setState(() => _updating = true);
    try {
      await _supa.from('garde_entraide')
          .update({'statut': statut, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', widget.gardeId);
      if (mounted) setState(() { _row = {...?_row, 'statut': statut}; _updating = false; });
    } catch (_) {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _green)),
      );
    }
    if (_row == null) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('Demande introuvable', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
      );
    }

    final animalNom = _row!['animal_nom']?.toString() ?? 'un animal';
    final debut = DateTime.tryParse(_row!['date_debut']?.toString() ?? '');
    final fin = DateTime.tryParse(_row!['date_fin']?.toString() ?? '');
    final dateStr = (debut != null && fin != null)
        ? '${DateFormat('dd/MM/yyyy').format(debut)} → ${DateFormat('dd/MM/yyyy').format(fin)}'
        : '';
    final message = _row!['message']?.toString() ?? '';
    final statut = _row!['statut']?.toString() ?? 'en_attente';
    final iAmRecepteur = _row!['uid_recepteur']?.toString() == widget.myUid;

    Color badgeColor;
    String badgeLabel;
    switch (statut) {
      case 'accepte':
        badgeColor = _green; badgeLabel = 'Acceptée';
        break;
      case 'refuse':
        badgeColor = Colors.redAccent; badgeLabel = 'Refusée';
        break;
      case 'annule':
        badgeColor = Colors.grey; badgeLabel = 'Annulée';
        break;
      default:
        badgeColor = Colors.orange; badgeLabel = 'En attente';
    }

    return Container(
      width: 240,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.pets, color: _green, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Dépannage pour $animalNom',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13,
                  color: widget.isMe ? Colors.white : const Color(0xFF1F2A2E)))),
        ]),
        if (dateStr.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(dateStr, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
              color: widget.isMe ? Colors.white70 : Colors.black54)),
        ],
        if (message.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(message, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
              color: widget.isMe ? Colors.white70 : Colors.black54)),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
          child: Text(badgeLabel, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor)),
        ),
        if (statut == 'en_attente' && iAmRecepteur) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _updating ? null : () => _updateStatut('refuse'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _updating ? null : () => _updateStatut('accepte'),
                style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8)),
                child: const Text('Accepter', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
