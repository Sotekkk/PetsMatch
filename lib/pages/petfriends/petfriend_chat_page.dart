import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/storage_helper.dart' as storage;

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

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeRealtime();
    _markRead();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
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

  Future<void> _send({String? text, String? imageUrl}) async {
    final t = text?.trim() ?? '';
    if (t.isEmpty && imageUrl == null) return;
    setState(() => _sending = true);
    try {
      final myInfo = _participantsInfo[_myUid] as Map? ?? {};
      final myName = myInfo['name']?.toString() ?? '';

      await _supa.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id':       _myUid,
        'text':            t.isNotEmpty ? t : null,
        'image_url':       imageUrl,
        'msg_type':        imageUrl != null ? 'image' : 'text',
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
        await _supa.from('conversations').update({
          'last_message': imageUrl != null ? '📷 Photo' : t,
          'updated_at':   DateTime.now().toIso8601String(),
          'unread_count': unread,
          'participants_info': updatedInfo,
        }).eq('id', widget.conversationId);
      }

      _ctrl.clear();
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
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
                  padding: imageUrl.isNotEmpty
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
