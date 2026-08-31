import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/chat_profile_page.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/pages/main_feed.dart' show UserSelected;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:PetsMatch/utils/chat_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String eleveurId;
  final String? alerteId;
  final String? nomAnimal;
  final bool isNewConversation;
  final String? groupName;

  const ChatScreen({
    Key? key,
    required this.conversationId,
    required this.eleveurId,
    this.alerteId,
    this.nomAnimal,
    this.isNewConversation = false,
    this.groupName,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static final _supa = Supabase.instance.client;
  static const _teal = Color(0xFF0C5C6C);

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  final _controller      = TextEditingController();
  final _scrollController = ScrollController();
  File? _imageFile;

  List<Map<String, dynamic>> _messages = [];
  Map<String, List<Map<String, dynamic>>> _reactions = {};
  bool _sending = false;
  RealtimeChannel? _channel;
  String _themeId = 'default';
  OverlayEntry? _reactionOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMessages().then((_) => _loadReactions());
    _loadTheme();
    _subscribeRealtime();
    _markAsRead();
    if (widget.isNewConversation && widget.alerteId != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _sendAlertRefMessage());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMessages().then((_) => _loadReactions());
      _channel?.unsubscribe();
      _subscribeRealtime();
    }
  }

  void _dismissReactionOverlay() {
    _reactionOverlay?.remove();
    _reactionOverlay = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reactionOverlay?.remove();
    _channel?.unsubscribe();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Thème ─────────────────────────────────────────────────────────────────────

  Future<void> _loadTheme() async {
    try {
      final conv = await _supa.from('conversations')
          .select('theme_id').eq('id', widget.conversationId).maybeSingle();
      if (mounted && conv != null) {
        setState(() => _themeId = (conv['theme_id'] as String?) ?? 'default');
      }
    } catch (_) {}
  }

  Future<void> _saveTheme(String id) async {
    setState(() => _themeId = id);
    try {
      await _supa.from('conversations')
          .update({'theme_id': id}).eq('id', widget.conversationId);
    } catch (_) {}
  }

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const Text('Thème de la conversation',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E2025))),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85),
            itemCount: kChatThemes.length,
            itemBuilder: (_, i) {
              final t = kChatThemes[i];
              final selected = t.id == _themeId;
              return GestureDetector(
                onTap: () { Navigator.pop(context); _saveTheme(t.id); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: t.bgGradient,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? _teal : Colors.grey.shade200,
                      width: selected ? 3 : 1,
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(t.emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 6),
                    Text(t.name, textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                          color: t.id == 'night' ? Colors.white : const Color(0xFF1E2025),
                        )),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(Icons.check_circle, size: 14, color: _teal),
                      ),
                  ]),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  // ── Réactions ─────────────────────────────────────────────────────────────────

  static const _kEmojis = ['❤️', '😂', '😮', '😢', '👍', '🐾'];

  Future<void> _loadReactions() async {
    try {
      // Récupère toutes les réactions des messages de cette conv
      final msgIds = _messages.map((m) => m['id']?.toString()).whereType<String>().toList();
      if (msgIds.isEmpty) return;
      final rows = await _supa.from('message_reactions')
          .select().inFilter('message_id', msgIds);
      if (!mounted) return;
      final map = <String, List<Map<String, dynamic>>>{};
      for (final r in (rows as List)) {
        final mid = r['message_id'] as String;
        map.putIfAbsent(mid, () => []).add(Map<String, dynamic>.from(r as Map));
      }
      setState(() => _reactions = map);
    } catch (_) {}
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    final uid = _uid;
    final existing = (_reactions[messageId] ?? [])
        .where((r) => r['uid'] == uid).toList();
    if (existing.isNotEmpty && existing.first['emoji'] == emoji) {
      // Même emoji → supprime
      setState(() => _reactions[messageId]!.removeWhere((r) => r['uid'] == uid));
      await _supa.from('message_reactions')
          .delete().eq('message_id', messageId).eq('uid', uid);
    } else {
      // Nouveau ou changement d'emoji → upsert
      final newRow = {'message_id': messageId, 'uid': uid, 'emoji': emoji};
      setState(() {
        _reactions.putIfAbsent(messageId, () => []);
        _reactions[messageId]!.removeWhere((r) => r['uid'] == uid);
        _reactions[messageId]!.add(newRow);
      });
      await _supa.from('message_reactions').upsert(
        {'message_id': messageId, 'uid': uid, 'emoji': emoji},
        onConflict: 'message_id,uid',
      );
    }
  }

  void _showEmojiPicker(String messageId, bool isOwner, Offset tapPosition, Map<String, dynamic> msgData) {
    final theme = chatThemeById(_themeId);
    final uid = _uid;
    final myReaction = (_reactions[messageId] ?? [])
        .firstWhere((r) => r['uid'] == uid, orElse: () => {});
    final screen = MediaQuery.of(context).size;

    Widget pickerRow = ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ..._kEmojis.map((e) {
                  final isSelected = myReaction['emoji'] == e;
                  return GestureDetector(
                    onTap: () { _dismissReactionOverlay(); _toggleReaction(messageId, e); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: isSelected ? theme.sentColor.withValues(alpha: 0.35) : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(e, style: TextStyle(fontSize: isSelected ? 27 : 24))),
                    ),
                  );
                }),
                if (isOwner) ...[
                  Container(width: 1, height: 28,
                      color: Colors.white.withValues(alpha: 0.3),
                      margin: const EdgeInsets.symmetric(horizontal: 4)),
                  GestureDetector(
                    onTap: () {
                      _dismissReactionOverlay();
                      final msg = _messages.firstWhere(
                          (m) => m['id']?.toString() == messageId, orElse: () => {});
                      if (msg.isNotEmpty) _deleteMessage(msg);
                    },
                    child: const SizedBox(
                      width: 46, height: 46,
                      child: Center(child: Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 22)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        );

    _reactionOverlay = OverlayEntry(
      builder: (_) => Material(
        color: Colors.transparent,
        child: Stack(children: [
          // Fond flouté plein écran
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissReactionOverlay,
              behavior: HitTestBehavior.opaque,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(color: Colors.black.withValues(alpha: 0.52)),
              ),
            ),
          ),

          // Bulle + picker centrés verticalement
          Align(
            alignment: Alignment(isOwner ? 0.5 : -0.5, 0.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: isOwner ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: screen.width * 0.78),
                    child: Material(
                      color: Colors.transparent,
                      elevation: 14,
                      shadowColor: Colors.black54,
                      child: _MessageBubble(
                        data: msgData,
                        isMe: isOwner,
                        myUid: uid,
                        time: _formatTime(msgData['created_at']?.toString()),
                        isLastRead: false,
                        onLongPress: (_, __) {},
                        onDoubleTap: () {},
                        onImageTap: (_) {},
                        sentBubbleColor: theme.sentColor,
                        sentTextColor: theme.sentTextColor,
                        reactions: _reactions[messageId] ?? [],
                        onReact: (_) {},
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  pickerRow,
                ],
              ),
            ),
          ),
        ]),
      ),
    );
    Overlay.of(context).insert(_reactionOverlay!);
  }

  // ── Données ──────────────────────────────────────────────────────────────────

  Future<void> _loadMessages() async {
    try {
      final rows = await _supa
          .from('messages')
          .select()
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _messages = List<Map<String, dynamic>>.from(rows as List));
      }
    } catch (_) {}
  }

  void _subscribeRealtime() {
    _channel = _supa
        .channel('chat_${widget.conversationId}')
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
              // Éviter les doublons (Realtime peut notifier notre propre INSERT)
              if (!_messages.any((m) => m['id'] == row['id'])) {
                setState(() => _messages.insert(0, row));
                _scrollToBottom();
              }
              if (row['sender_id'] != _uid) _markAsRead();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            final old = payload.oldRecord;
            if (mounted && old['id'] != null) {
              setState(() => _messages.removeWhere((m) => m['id'] == old['id']));
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            final mid = row['message_id'] as String?;
            if (mounted && mid != null) {
              setState(() {
                _reactions.putIfAbsent(mid, () => []);
                _reactions[mid]!.removeWhere((r) => r['uid'] == row['uid']);
                _reactions[mid]!.add(row);
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) {
            final old = payload.oldRecord;
            final mid = old['message_id'] as String?;
            final uid = old['uid'] as String?;
            if (mounted && mid != null && uid != null) {
              setState(() => _reactions[mid]?.removeWhere((r) => r['uid'] == uid));
            }
          },
        )
        .subscribe();
  }

  Future<void> _markAsRead() async {
    try {
      final conv = await _supa.from('conversations')
          .select('unread_count').eq('id', widget.conversationId).maybeSingle();
      if (conv == null) return;
      final unread = Map<String, dynamic>.from(conv['unread_count'] as Map? ?? {});
      if ((unread[_uid] as int? ?? 0) > 0) {
        unread[_uid] = 0;
        await _supa.from('conversations').update({'unread_count': unread})
            .eq('id', widget.conversationId);
      }
    } catch (_) {}
  }

  Future<void> _sendAlertRefMessage() async {
    final nom = widget.nomAnimal ?? 'l\'animal';
    await _sendMessage('Bonjour, j\'ai peut-être aperçu votre animal $nom (réf : ${widget.alerteId!})',
        alerteId: widget.alerteId);
  }

  Future<void> _sendMessage(String text, {String? imageUrl, double? lat, double? lng, String? alerteId, Map<String, dynamic>? animalData}) async {
    if (text.trim().isEmpty && imageUrl == null && lat == null && animalData == null) return;
    final uid = _uid;
    setState(() => _sending = true);

    try {
      final senderProfileId = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;

      final inserted = await _supa.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id':       uid,
        'text':            animalData != null
                               ? jsonEncode({'id': animalData['id'], 'nom': animalData['nom'], 'espece': animalData['espece'], 'race': animalData['race'], 'photo_url': animalData['photo_url']})
                               : (text.isNotEmpty ? text : null),
        'image_url':       imageUrl,
        'msg_type':        imageUrl != null ? 'image' : (lat != null ? 'location' : (animalData != null ? 'animal_card' : 'text')),
        'lat':             lat,
        'lng':             lng,
        'alerte_id':       alerteId,
        'is_read':         false,
        if (senderProfileId != null) 'sender_profile_id': senderProfileId,
      }).select().single();
      // Ajout optimiste — le callback realtime vérifiera le doublon si il arrive
      if (mounted && !_messages.any((m) => m['id'] == inserted['id'])) {
        setState(() => _messages.insert(0, inserted));
        _scrollToBottom();
      }

      // Mettre à jour la conversation
      final conv = await _supa.from('conversations')
          .select('participants, unread_count, participants_info')
          .eq('id', widget.conversationId).maybeSingle();
      if (conv != null) {
        final members = List<String>.from((conv['participants'] as List?)?.map((e) => e.toString()) ?? []);
        final unread  = Map<String, dynamic>.from(conv['unread_count'] as Map? ?? {});
        for (final p in members) if (p != uid) unread[p] = (unread[p] as int? ?? 0) + 1;

        final myName  = User_Info.isElevage
            ? (User_Info.nameElevage.isNotEmpty ? User_Info.nameElevage : '${User_Info.firstname} ${User_Info.lastname}'.trim())
            : '${User_Info.firstname} ${User_Info.lastname}'.trim();
        final myPhoto = User_Info.isElevage ? User_Info.profilePictureUrlElevage : User_Info.profilePictureUrl;
        final info    = Map<String, dynamic>.from(conv['participants_info'] as Map? ?? {});
        info[uid] = {
          'name': myName.isEmpty ? 'Utilisateur' : myName,
          if (myPhoto.isNotEmpty) 'photo': myPhoto,
        };

        await _supa.from('conversations').update({
          'last_message':      imageUrl != null ? '📷 Photo' : (lat != null ? '📍 Position' : (animalData != null ? '🐾 ${animalData['nom'] ?? 'Animal'}' : text)),
          'updated_at':        DateTime.now().toIso8601String(),
          'unread_count':      unread,
          'participants_info': info,
          'deleted_for':       {},
        }).eq('id', widget.conversationId);
      }

      _controller.clear();
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    try {
      await _supa.from('messages').delete().eq('id', msg['id'].toString());
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.position.minScrollExtent == 0) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  // ── User info (AppBar) ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _getUserInfo(String userId) async {
    try {
      final d = await MessagingHelper.getDisplayInfo(userId);
      return {
        'name': d['name'],
        'profilePictureUrl': d['photo'] as String? ?? '',
        'uid': userId,
        'isElevage': d['isElevage'],
        'isPro': d['isPro'],
      };
    } catch (_) {
      return {'name': 'Utilisateur', 'profilePictureUrl': '', 'uid': userId, 'isElevage': false, 'isPro': false};
    }
  }

  Future<void> _navigateToUser(Map<String, dynamic> userInfo) async {
    final uid = userInfo['uid'] as String;
    final isElevage = userInfo['isElevage'] as bool? ?? false;
    final isPro = userInfo['isPro'] as bool? ?? false;

    if (isElevage || isPro) {
      // Fetch full data for éleveur/pro profile page
      try {
        final d = await _supa.from('users').select(
          'name_elevage, profile_picture_url_elevage, desc_entreprise, is_partenaire, '
          'cat_pro, profession_pro, code_iso_elevage, numero_elevage, adress_elevage, '
          'is_validate, is_elevage, is_pro, is_dog, is_cat, dog_breeds, cat_breeds, '
          'ville_elevage, code_postal_elevage, pays_elevage, siret',
        ).eq('uid', uid).maybeSingle();
        final data = <String, dynamic>{
          'nameElevage':             d?['name_elevage'] ?? '',
          'profilePictureUrlElevage': d?['profile_picture_url_elevage'] ?? '',
          'descEntreprise':          d?['desc_entreprise'] ?? '',
          'isPartenaire':            d?['is_partenaire'] ?? false,
          'catPro':                  d?['cat_pro'] ?? '',
          'professionPro':           d?['profession_pro'] ?? '',
          'codeISOElevage':          d?['code_iso_elevage'] ?? '',
          'numeroElevage':           d?['numero_elevage'] ?? '',
          'adressElevage':           d?['adress_elevage'] ?? '',
          'isValidate':              d?['is_validate'] ?? false,
          'isElevage':               d?['is_elevage'] ?? false,
          'isPro':                   d?['is_pro'] ?? false,
          'isDog':                   d?['is_dog'] ?? false,
          'isCat':                   d?['is_cat'] ?? false,
          'dogBreeds':               d?['dog_breeds'] ?? [],
          'catBreeds':               d?['cat_breeds'] ?? [],
          'villeElevage':            d?['ville_elevage'] ?? '',
          'codePostalElevage':       d?['code_postal_elevage'] ?? '',
          'paysElevage':             d?['pays_elevage'] ?? '',
          'siret':                   d?['siret'] ?? '',
        };
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => UserDetailPageFeed(user: UserSelected.fromMap(data, uid)),
        ));
      } catch (_) {
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatProfilePage(uid: uid),
        ));
      }
    } else {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatProfilePage(uid: uid),
      ));
    }
  }

  // ── Images / localisation ─────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _sending = true);
    try {
      final path = 'chat_images/${_uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final url  = await storage.uploadPhoto(File(file.path), path, quality: 70);
      await _sendMessage('', imageUrl: url);
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _takePhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return;
    setState(() => _imageFile = File(file.path));
    _showImagePreview();
  }

  void _showImagePreview() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black87,
        contentPadding: const EdgeInsets.all(12),
        content: _imageFile == null ? const SizedBox() : ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(_imageFile!),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_imageFile == null) return;
              setState(() => _sending = true);
              try {
                final path = 'chat_images/${_uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                final url  = await storage.uploadPhoto(_imageFile!, path, quality: 70);
                await _sendMessage('', imageUrl: url);
              } catch (_) {
                if (mounted) setState(() => _sending = false);
              }
            },
            child: const Text('Envoyer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activez la localisation')));
      return;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Partager ma position', style: TextStyle(fontFamily: 'Galey')),
      content: const Text('Envoyer vos coordonnées GPS actuelles ?', style: TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer', style: TextStyle(color: _teal))),
      ],
    ));
    if (confirm != true) return;
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      _sendMessage('', lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur GPS : $e')));
    }
  }

  Future<void> _proposeVisite() async {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    await showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true,
      isDismissible: true, enableDrag: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('📅  Proposer une visite',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1E2025))),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: selectedDate,
                    firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
                    locale: const Locale('fr'));
                if (d != null) setModal(() => selectedDate = d);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, color: Color(0xFF0C5C6C), size: 20),
                  const SizedBox(width: 10),
                  Text(DateFormat('EEEE d MMMM yyyy', 'fr').format(selectedDate),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1E2025))),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                final t = await showTimePicker(context: ctx, initialTime: selectedTime);
                if (t != null) setModal(() => selectedTime = t);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.access_time_rounded, color: Color(0xFF0C5C6C), size: 20),
                  const SizedBox(width: 10),
                  Text(selectedTime.format(ctx),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1E2025))),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final dateVisite = DateTime(selectedDate.year, selectedDate.month, selectedDate.day,
                      selectedTime.hour, selectedTime.minute);
                  await _saveVisite(dateVisite);
                },
                child: const Text('Confirmer la visite',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _saveVisite(DateTime dateVisite) async {
    final nomAnimal = widget.nomAnimal ?? 'animal';
    final dateStr   = DateFormat('EEEE d MMMM yyyy à HH:mm', 'fr').format(dateVisite);
    try {
      await _supa.from('agenda_events').insert([
        {'uid': _uid,            'titre': 'Visite — $nomAnimal', 'type': 'visite', 'date_debut': dateVisite.toUtc().toIso8601String(), 'notes': 'Visite organisée via messagerie'},
        {'uid': widget.eleveurId,'titre': 'Visite — $nomAnimal', 'type': 'visite', 'date_debut': dateVisite.toUtc().toIso8601String(), 'notes': 'Visite organisée via messagerie'},
      ]);
    } catch (_) {}
    await _sendMessage('📅  Visite proposée : $dateStr');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Visite ajoutée à vos agendas !', style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Color(0xFF0C5C6C),
      ));
    }
  }

  void _showFullImage(String url) {
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.black, insetPadding: EdgeInsets.zero,
      child: Stack(fit: StackFit.loose, children: [
        Positioned.fill(child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain))),
        Positioned(top: 12, right: 12, child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        )),
      ]),
    ));
  }

  void _showMessageOptions(Map<String, dynamic> msg) {
    if (msg['sender_id'] != _uid) return;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Supprimer le message', style: TextStyle(fontFamily: 'Galey', color: Colors.redAccent)),
            onTap: () { Navigator.pop(context); _deleteMessage(msg); },
          ),
        ]),
      ),
    );
  }

  // ── Formatage temps ───────────────────────────────────────────────────────────

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    if (DateUtils.isSameDay(dt, now)) return 'Aujourd\'hui';
    if (DateUtils.isSameDay(dt, now.subtract(const Duration(days: 1)))) return 'Hier';
    return DateFormat('dd MMMM yyyy', 'fr').format(dt);
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    return dt == null ? '' : DateFormat('HH:mm').format(dt);
  }

  // ── Options conversation (menu 3 points) ─────────────────────────────────────

  void _showConvOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          _OptionsItem(
            icon: Icons.palette_outlined,
            label: 'Thème de la conversation',
            onTap: () { Navigator.pop(context); _showThemeSelector(); },
          ),
          _OptionsItem(
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer la conversation',
            color: Colors.redAccent,
            onTap: () { Navigator.pop(context); _confirmDeleteConv(); },
          ),
          _OptionsItem(
            icon: Icons.flag_outlined,
            label: 'Signaler la conversation',
            color: Colors.orange,
            onTap: () { Navigator.pop(context); _reportConv(); },
          ),
        ]),
      ),
    );
  }

  Future<void> _confirmDeleteConv() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la conversation ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _supa.from('messages').delete().eq('conversation_id', widget.conversationId);
      await _supa.from('conversations').delete().eq('id', widget.conversationId);
      if (mounted) Navigator.maybePop(context);
    } catch (_) {}
  }

  void _reportConv() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ReportSheet(
        conversationId: widget.conversationId,
        reporterUid: _uid,
      ),
    );
  }

  // ── Menu "+" glassmorphe ──────────────────────────────────────────────────────

  void _showPlusMenu(ChatTheme theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: theme.bgGradient[0].withValues(alpha: 0.55),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
              _PlusItem(icon: Icons.photo_outlined,           label: 'Galerie',             isDark: theme.isDark, onTap: () { Navigator.pop(ctx); _pickImage(); }),
              _PlusItem(icon: Icons.camera_alt_outlined,      label: 'Appareil photo',       isDark: theme.isDark, onTap: () { Navigator.pop(ctx); _takePhoto(); }),
              _PlusItem(icon: Icons.location_on_outlined,     label: 'Ma position',           isDark: theme.isDark, onTap: () { Navigator.pop(ctx); _shareLocation(); }),
              _PlusItem(icon: Icons.calendar_today_outlined,  label: 'Proposer une visite',   isDark: theme.isDark, onTap: () { Navigator.pop(ctx); _proposeVisite(); }),
              _PlusItem(icon: Icons.pets_rounded,             label: 'Partager un animal',    isDark: theme.isDark, onTap: () { Navigator.pop(ctx); _showAnimalPicker(); }),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showAnimalPicker() async {
    final uid = _uid;
    List<Map<String, dynamic>> animaux = [];
    try {
      final rows = await _supa.from('animaux')
          .select('id, nom, espece, race, photo_url')
          .or('uid_eleveur.eq.$uid,uid_proprietaire.eq.$uid')
          .not('statut', 'in', '(decede)')
          .order('created_at', ascending: false);
      animaux = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AnimalPickerSheet(
        animaux: animaux,
        onSelected: (animal) => _sendMessage('', animalData: animal),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    // Retrouver le dernier message lu par l'autre
    String? lastReadId;
    for (int i = _messages.length - 1; i >= 0; i--) {
      final d = _messages[i];
      if (d['sender_id'] == uid && d['is_read'] == true) {
        lastReadId = d['id']?.toString();
        break;
      }
    }

    final theme = chatThemeById(_themeId);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0, titleSpacing: 0,
        flexibleSpace: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.transparent],
            stops: [0.55, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Stack(children: [
                Container(color: theme.bgGradient[0].withValues(alpha: 0.90)),
                Container(color: Colors.black.withValues(alpha: 0.20)),
              ]),
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 24),
            onPressed: _showConvOptions,
          ),
        ],
        title: widget.groupName != null
            ? Row(children: [
                CircleAvatar(radius: 18, backgroundColor: const Color(0xFF5B9EAA),
                    child: const Icon(Icons.group, color: Colors.white, size: 18)),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.groupName!,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ])
            : FutureBuilder<Map<String, dynamic>>(
                future: _getUserInfo(widget.eleveurId),
                builder: (_, snap) {
                  final info    = snap.data ?? {'name': '...', 'profilePictureUrl': null};
                  final name    = info['name'] as String? ?? '...';
                  final photoUrl = info['profilePictureUrl'] as String?;
                  return GestureDetector(
                    onTap: snap.hasData ? () => _navigateToUser(snap.data!) : null,
                    child: Row(children: [
                      CircleAvatar(
                        radius: 18, backgroundColor: const Color(0xFF5B9EAA),
                        backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
                        child: photoUrl == null ? const Icon(Icons.person, color: Colors.white, size: 18) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(name,
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  );
                },
              ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: theme.bgGradient,
          ),
        ),
        child: Column(children: [
        // Messages
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Text('Aucun message',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)))
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + kToolbarHeight + 8, 12, 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final msg  = _messages[i];
                    final ts   = msg['created_at']?.toString();
                    final olderTs = i < _messages.length - 1 ? _messages[i+1]['created_at']?.toString() : null;
                    final showDate = i == _messages.length - 1 || _formatDate(ts) != _formatDate(olderTs);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDate)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12)),
                              child: Text(_formatDate(ts),
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white)),
                            )),
                          ),
                        _MessageBubble(
                          data: msg,
                          isMe: msg['sender_id'] == uid,
                          myUid: uid,
                          time: _formatTime(ts),
                          isLastRead: msg['sender_id'] == uid && msg['id']?.toString() == lastReadId,
                          onLongPress: (pos, isOwner) => _showEmojiPicker(msg['id']?.toString() ?? '', isOwner, pos, msg),
                          onDoubleTap: () => _toggleReaction(msg['id']?.toString() ?? '', '❤️'),
                          onImageTap: (url) => _showFullImage(url),
                          onAnimalTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatProfilePage(uid: msg['sender_id']?.toString() ?? widget.eleveurId),
                          )),
                          sentBubbleColor: theme.sentColor,
                          sentTextColor: theme.sentTextColor,
                          reactions: _reactions[msg['id']?.toString()] ?? [],
                          onReact: (emoji) => _toggleReaction(msg['id']?.toString() ?? '', emoji),
                        ),
                      ],
                    );
                  },
                ),
        ),
        // Barre saisie avec dégradé en bas (miroir de l'AppBar)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.22)],
              stops: const [0.0, 1.0],
            ),
          ),
          padding: EdgeInsets.fromLTRB(8, 12, 8, MediaQuery.of(context).padding.bottom + 8),
          child: Row(children: [
            GestureDetector(
              onTap: () => _showPlusMenu(theme),
              child: ClipOval(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.38), width: 1),
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: theme.isDark ? 0.12 : 0.28),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: theme.isDark ? 0.18 : 0.50),
                    width: 1.0,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                      color: theme.isDark ? Colors.white : const Color(0xFF1E2025)),
                  maxLines: 3, minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) { if (v.trim().isNotEmpty) { _sendMessage(v); } },
                  decoration: InputDecoration(
                    hintText: 'Votre message...',
                    hintStyle: TextStyle(
                        fontFamily: 'Galey',
                        color: theme.isDark ? Colors.white38 : Colors.black.withValues(alpha: 0.35),
                        fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _teal)))
                : GestureDetector(
                    onTap: () {
                      final text = _controller.text.trim();
                      if (text.isEmpty) return;
                      _sendMessage(text);
                    },
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(color: theme.sentColor, shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
          ]),
        ),
      ]),
      ), // Container gradient
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final String myUid;
  final String time;
  final bool isLastRead;
  final void Function(Offset position, bool isOwner) onLongPress;
  final VoidCallback onDoubleTap;
  final void Function(String url) onImageTap;
  final VoidCallback? onAnimalTap;
  final Color sentBubbleColor;
  final Color sentTextColor;
  final List<Map<String, dynamic>> reactions;
  final void Function(String emoji) onReact;

  const _MessageBubble({
    required this.data, required this.isMe, required this.myUid, required this.time,
    required this.isLastRead, required this.onLongPress, required this.onDoubleTap, required this.onImageTap,
    required this.reactions, required this.onReact,
    this.onAnimalTap,
    this.sentBubbleColor = const Color(0xFF0C5C6C),
    this.sentTextColor = Colors.white,
  });

  static const _teal = Color(0xFF0C5C6C);

  @override
  Widget build(BuildContext context) {
    final text       = (data['text'] as String?) ?? '';
    final imageUrl   = data['image_url'] as String?;
    final isLocation   = data['msg_type'] == 'location';
    final isAnimalCard = data['msg_type'] == 'animal_card';

    return GestureDetector(
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox?;
        final pos = box != null
            ? box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))
            : Offset.zero;
        onLongPress(pos, isMe);
      },
      onDoubleTap: onDoubleTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                    margin: EdgeInsets.only(left: isMe ? 48 : 4, right: isMe ? 4 : 48),
                    padding: imageUrl != null || isLocation || isAnimalCard
                        ? const EdgeInsets.all(4)
                        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? sentBubbleColor : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(22), topRight: const Radius.circular(22),
                        bottomLeft: Radius.circular(isMe ? 22 : 5),
                        bottomRight: Radius.circular(isMe ? 5 : 22),
                      ),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (imageUrl != null)
                          GestureDetector(
                            onTap: () => onImageTap(imageUrl),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: CachedNetworkImage(imageUrl: imageUrl, width: 200, height: 200, fit: BoxFit.cover,
                                placeholder: (_, __) => Container(width: 200, height: 200,
                                    color: Colors.grey.shade200, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                              ),
                            ),
                          ),
                        if (isLocation)
                          _LocationCard(
                            lat: (data['lat'] as num).toDouble(),
                            lng: (data['lng'] as num).toDouble(),
                            isMe: isMe,
                          ),
                        if (isAnimalCard)
                          _AnimalCardContent(
                            jsonText: text,
                            isMe: isMe,
                            sentColor: sentBubbleColor,
                            sentTextColor: sentTextColor,
                            onTap: onAnimalTap,
                          ),
                        if (text.isNotEmpty)
                          Padding(
                            padding: imageUrl != null ? const EdgeInsets.fromLTRB(8, 6, 8, 2) : EdgeInsets.zero,
                            child: Text(text, style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                                color: isMe ? sentTextColor : const Color(0xFF1F2A2E))),
                          ),
                        const SizedBox(height: 2),
                        Text(time, style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                            color: isMe ? sentTextColor.withValues(alpha: 0.6) : Colors.grey.shade400)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (reactions.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  left: isMe ? 0 : 12, right: isMe ? 12 : 0, top: 4),
                child: _ReactionBar(reactions: reactions, myUid: myUid, selectedColor: sentBubbleColor, onReact: onReact),
              ),
            if (isLastRead)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Text('Vu', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade400)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Location card ──────────────────────────────────────────────────────────────

class _LocationCard extends StatelessWidget {
  final double lat, lng;
  final bool isMe;
  const _LocationCard({required this.lat, required this.lng, required this.isMe});

  Future<void> _openMaps() async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openMaps,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(0.15) : const Color(0xFFEEF5EA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_on, color: isMe ? Colors.white : const Color(0xFF6E9E57), size: 20),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Position GPS partagée',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13,
                  color: isMe ? Colors.white : const Color(0xFF1F2A2E))),
            Text('Appuyer pour ouvrir Maps',
              style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                  color: isMe ? Colors.white70 : Colors.grey.shade600)),
          ]),
        ]),
      ),
    );
  }
}

// ── Reaction bar ───────────────────────────────────────────────────────────────

class _ReactionBar extends StatelessWidget {
  final List<Map<String, dynamic>> reactions;
  final String myUid;
  final Color selectedColor;
  final void Function(String emoji) onReact;

  const _ReactionBar({required this.reactions, required this.myUid, required this.selectedColor, required this.onReact});

  @override
  Widget build(BuildContext context) {
    // Grouper par emoji
    final counts = <String, int>{};
    String? myEmoji;
    for (final r in reactions) {
      final e = r['emoji'] as String? ?? '';
      counts[e] = (counts[e] ?? 0) + 1;
      if (r['uid'] == myUid) myEmoji = e;
    }
    return Wrap(spacing: 4, children: counts.entries.map((entry) {
      final isMyReaction = myEmoji == entry.key;
      return GestureDetector(
        onTap: () => onReact(entry.key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isMyReaction ? selectedColor.withValues(alpha: 0.18) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isMyReaction ? selectedColor.withValues(alpha: 0.6) : Colors.grey.shade300,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(entry.key, style: const TextStyle(fontSize: 13)),
            if (entry.value > 1) ...[
              const SizedBox(width: 3),
              Text('${entry.value}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                      color: isMyReaction ? selectedColor : Colors.grey.shade600,
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      );
    }).toList());
  }
}

// ── Helpers UI ─────────────────────────────────────────────────────────────────

class _OptionsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _OptionsItem({required this.icon, required this.label, required this.onTap, this.color = const Color(0xFF1E2025)});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color, size: 22),
    title: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: color)),
    onTap: onTap,
  );
}

class _PlusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _PlusItem({required this.icon, required this.label, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: isDark ? Colors.white : Colors.white, size: 22),
    title: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.white)),
    onTap: onTap,
  );
}

class _ReportSheet extends StatefulWidget {
  final String conversationId;
  final String reporterUid;
  const _ReportSheet({required this.conversationId, required this.reporterUid});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

// ── Animal card content (inside bubble) ───────────────────────────────────────

class _AnimalCardContent extends StatelessWidget {
  final String jsonText;
  final bool isMe;
  final Color sentColor;
  final Color sentTextColor;
  final VoidCallback? onTap;

  const _AnimalCardContent({
    required this.jsonText,
    required this.isMe,
    required this.sentColor,
    required this.sentTextColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> animal = {};
    try { animal = Map<String, dynamic>.from(jsonDecode(jsonText) as Map); } catch (_) {}

    final nom      = animal['nom'] as String? ?? 'Animal';
    final espece   = animal['espece'] as String? ?? '';
    final race     = animal['race'] as String? ?? '';
    final photoUrl = animal['photo_url'] as String?;
    final subtitle = [espece, race].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      width: 210,
      decoration: BoxDecoration(
        color: isMe ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        // Photo
        SizedBox(
          height: 130,
          child: photoUrl != null && photoUrl.isNotEmpty
              ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.grey.shade200,
                      child: const Center(child: Icon(Icons.pets, color: Colors.grey, size: 36))),
                  errorWidget: (_, __, ___) => Container(color: Colors.grey.shade200,
                      child: const Center(child: Icon(Icons.pets, color: Colors.grey, size: 36))),
                )
              : Container(color: isMe ? Colors.white.withValues(alpha: 0.18) : Colors.grey.shade200,
                  child: Center(child: Icon(Icons.pets, color: isMe ? Colors.white54 : Colors.grey, size: 40))),
        ),
        // Infos
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nom,
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14,
                  color: isMe ? Colors.white : const Color(0xFF1E2025)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                    color: isMe ? Colors.white70 : Colors.grey.shade600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        // Bouton Voir profil
        GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withValues(alpha: 0.22) : sentColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isMe ? Colors.white.withValues(alpha: 0.35) : sentColor.withValues(alpha: 0.30),
              ),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.open_in_new_rounded, size: 13,
                  color: isMe ? Colors.white : sentColor),
              const SizedBox(width: 5),
              Text('Voir le profil',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                    color: isMe ? Colors.white : sentColor)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Animal picker sheet ────────────────────────────────────────────────────────

class _AnimalPickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> animaux;
  final void Function(Map<String, dynamic> animal) onSelected;

  const _AnimalPickerSheet({required this.animaux, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const Text('Choisir un animal',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1E2025))),
        const SizedBox(height: 16),
        if (animaux.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Aucun animal dans votre profil.',
                style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500))),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: animaux.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final a = animaux[i];
                final photoUrl = a['photo_url'] as String?;
                final espece = a['espece'] as String? ?? '';
                final race   = a['race'] as String? ?? '';
                final subtitle = [espece, race].where((s) => s.isNotEmpty).join(' · ');
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  leading: CircleAvatar(
                    radius: 26, backgroundColor: const Color(0xFFEEF5EA),
                    backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(photoUrl) : null,
                    child: photoUrl == null || photoUrl.isEmpty
                        ? const Icon(Icons.pets, color: Color(0xFF6E9E57), size: 22) : null,
                  ),
                  title: Text(a['nom'] as String? ?? '',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: subtitle.isNotEmpty
                      ? Text(subtitle, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500))
                      : null,
                  trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF0C5C6C)),
                  onTap: () { Navigator.pop(context); onSelected(a); },
                );
              },
            ),
          ),
      ]),
    );
  }
}

class _ReportSheetState extends State<_ReportSheet> {
  static final _supa = Supabase.instance.client;
  String? _selected;
  final _detailsCtrl = TextEditingController();
  bool _sending = false;

  static const _reasons = [
    'Contenu inapproprié',
    'Harcèlement',
    'Spam / arnaque',
    'Autre',
  ];

  @override
  void dispose() { _detailsCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_selected == null) return;
    setState(() => _sending = true);
    try {
      await _supa.from('conversation_reports').insert({
        'conversation_id': widget.conversationId,
        'reported_by_uid': widget.reporterUid,
        'reason': _selected,
        'details': _detailsCtrl.text.trim().isNotEmpty ? _detailsCtrl.text.trim() : null,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Conversation signalée. Merci, nous allons examiner.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF0C5C6C),
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
      const Text('Signaler la conversation',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1E2025))),
      const SizedBox(height: 16),
      ..._reasons.map((r) => RadioListTile<String>(
        value: r, groupValue: _selected,
        onChanged: (v) => setState(() => _selected = v),
        title: Text(r, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
        activeColor: const Color(0xFF0C5C6C),
        contentPadding: EdgeInsets.zero,
      )),
      if (_selected == 'Autre') ...[
        const SizedBox(height: 8),
        TextField(
          controller: _detailsCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Précisez...',
            hintStyle: const TextStyle(fontFamily: 'Galey'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ],
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _selected == null || _sending ? null : _submit,
          child: _sending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Envoyer le signalement', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}
