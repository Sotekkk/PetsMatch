import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/chat_profile_page.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:PetsMatch/pages/main_feed.dart' show UserSelected;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'package:PetsMatch/utils/messaging_helper.dart';
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

class _ChatScreenState extends State<ChatScreen> {
  static final _supa = Supabase.instance.client;
  static const _teal = Color(0xFF0C5C6C);

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  final _controller      = TextEditingController();
  final _scrollController = ScrollController();
  File? _imageFile;

  List<Map<String, dynamic>> _messages = [];
  bool _sending = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeRealtime();
    _markAsRead();
    if (widget.isNewConversation && widget.alerteId != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _sendAlertRefMessage());
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _sendMessage(String text, {String? imageUrl, double? lat, double? lng, String? alerteId}) async {
    if (text.trim().isEmpty && imageUrl == null && lat == null) return;
    final uid = _uid;
    setState(() => _sending = true);

    try {
      final senderProfileId = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;

      await _supa.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id':       uid,
        'text':            text.isNotEmpty ? text : null,
        'image_url':       imageUrl,
        'msg_type':        imageUrl != null ? 'image' : (lat != null ? 'location' : 'text'),
        'lat':             lat,
        'lng':             lng,
        'alerte_id':       alerteId,
        'is_read':         false,
        if (senderProfileId != null) 'sender_profile_id': senderProfileId,
      });

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
          'last_message':      imageUrl != null ? '📷 Photo' : (lat != null ? '📍 Position' : text),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0, titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
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
      body: Column(children: [
        // Messages
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Text('Aucun message',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)))
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final msg  = _messages[i];
                    final ts   = msg['created_at']?.toString();
                    // Avec reverse:true + ordre DESC, _messages[i+1] est plus ancien (visuellement au-dessus)
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
                              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                              child: Text(_formatDate(ts),
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                            )),
                          ),
                        _MessageBubble(
                          data: msg,
                          isMe: msg['sender_id'] == uid,
                          time: _formatTime(ts),
                          isLastRead: msg['sender_id'] == uid && msg['id']?.toString() == lastReadId,
                          onLongPress: () => _showMessageOptions(msg),
                          onImageTap: (url) => _showFullImage(url),
                        ),
                      ],
                    );
                  },
                ),
        ),
        // Barre saisie
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
          child: Row(children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_circle_outline, color: _teal, size: 26),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                if (v == 'photo')    _pickImage();
                else if (v == 'camera')   _takePhoto();
                else if (v == 'location') _shareLocation();
                else if (v == 'visite')   _proposeVisite();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'photo',    child: Row(children: [Icon(Icons.photo_outlined, size: 18), SizedBox(width: 10), Text('Galerie', style: TextStyle(fontFamily: 'Galey'))])),
                PopupMenuItem(value: 'camera',   child: Row(children: [Icon(Icons.camera_alt_outlined, size: 18), SizedBox(width: 10), Text('Appareil photo', style: TextStyle(fontFamily: 'Galey'))])),
                PopupMenuItem(value: 'location', child: Row(children: [Icon(Icons.location_on_outlined, size: 18), SizedBox(width: 10), Text('Ma position', style: TextStyle(fontFamily: 'Galey'))])),
                PopupMenuItem(value: 'visite',   child: Row(children: [Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF0C5C6C)), SizedBox(width: 10), Text('Proposer une visite', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF0C5C6C)))])),
              ],
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(24)),
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  maxLines: 4, minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) { if (v.trim().isNotEmpty) { _sendMessage(v); } },
                  decoration: const InputDecoration(
                    hintText: 'Votre message...',
                    hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 14),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
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
                      decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
          ]),
        ),
      ]),
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final String time;
  final bool isLastRead;
  final VoidCallback onLongPress;
  final void Function(String url) onImageTap;

  const _MessageBubble({
    required this.data, required this.isMe, required this.time,
    required this.isLastRead, required this.onLongPress, required this.onImageTap,
  });

  static const _teal = Color(0xFF0C5C6C);

  @override
  Widget build(BuildContext context) {
    final text       = (data['text'] as String?) ?? '';
    final imageUrl   = data['image_url'] as String?;
    final isLocation = data['msg_type'] == 'location';

    return GestureDetector(
      onLongPress: isMe ? onLongPress : null,
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
                    padding: imageUrl != null || isLocation
                        ? const EdgeInsets.all(4)
                        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? _teal : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (imageUrl != null)
                          GestureDetector(
                            onTap: () => onImageTap(imageUrl),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
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
                        if (text.isNotEmpty)
                          Padding(
                            padding: imageUrl != null ? const EdgeInsets.fromLTRB(8, 6, 8, 2) : EdgeInsets.zero,
                            child: Text(text, style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                                color: isMe ? Colors.white : const Color(0xFF1F2A2E))),
                          ),
                        const SizedBox(height: 2),
                        Text(time, style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                            color: isMe ? Colors.white60 : Colors.grey.shade400)),
                      ],
                    ),
                  ),
                ),
              ],
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
