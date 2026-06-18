import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/main_feed.dart';
import 'package:PetsMatch/pages/user_details_particulier.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String eleveurId;
  final String? alerteId;
  final String? nomAnimal;
  final bool isNewConversation;

  const ChatScreen({
    Key? key,
    required this.conversationId,
    required this.eleveurId,
    this.alerteId,
    this.nomAnimal,
    this.isNewConversation = false,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _defaultPp = 'https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60';

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _conversations = FirebaseFirestore.instance.collection('conversations');
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _markAsRead();
    if (widget.isNewConversation && widget.alerteId != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _sendAlertRefMessage());
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendAlertRefMessage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final nom = widget.nomAnimal ?? 'l\'animal';
    await _sendMessage('Bonjour, j\'ai peut-être aperçu votre animal $nom (réf : ${widget.alerteId!})', uid, alerteId: widget.alerteId);
  }

  void _markAsRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _conversations.doc(widget.conversationId).update({'unreadCount.$uid': 0});
  }

  Future<void> _sendMessage(String text, String senderId, {String? imageUrl, double? lat, double? lng, String? alerteId}) async {
    if (text.trim().isEmpty && imageUrl == null && lat == null) return;
    final convRef = _conversations.doc(widget.conversationId);
    await convRef.collection('messages').add({
      'text': text,
      'senderId': senderId,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (lat != null && lng != null) ...{'type': 'location', 'lat': lat, 'lng': lng},
      if (alerteId != null) 'alerteId': alerteId,
    });
    final snap = await convRef.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final unread = Map<String, dynamic>.from(data['unreadCount'] ?? {});
    for (final p in (data['participants'] as List<dynamic>? ?? [])) {
      if (p != senderId) unread[p] = (unread[p] ?? 0) + 1;
    }
    // Stocke le nom/avatar de l'expéditeur dans la conversation pour éviter
    // de relire Firestore à chaque affichage dans la liste des messages.
    final myName = User_Info.isElevage
        ? (User_Info.nameElevage.isNotEmpty ? User_Info.nameElevage : '${User_Info.firstname} ${User_Info.lastname}'.trim())
        : '${User_Info.firstname} ${User_Info.lastname}'.trim();
    final myPhoto = User_Info.isElevage
        ? User_Info.profilePictureUrlElevage
        : User_Info.profilePictureUrl;
    final myInfo = <String, dynamic>{
      'name': myName.isEmpty ? 'Utilisateur' : myName,
      if (myPhoto.isNotEmpty && myPhoto != _defaultPp) 'photo': myPhoto,
    };

    await convRef.update({
      'unreadCount': unread,
      'lastMessage': imageUrl != null ? '📷 Photo' : (lat != null ? '📍 Position' : text),
      'timestamp': FieldValue.serverTimestamp(),
      'deletedFor': FieldValue.delete(),
      'participants_info.$senderId': myInfo,
    });
    _scrollToBottom();
  }

  Future<void> _deleteMessage(DocumentSnapshot msg) async {
    await _conversations.doc(widget.conversationId).collection('messages').doc(msg.id).delete();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<Map<String, dynamic>> _getUserInfo(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (!doc.exists) return {'name': 'Utilisateur', 'profilePictureUrl': null, 'isElevage': false, 'isPro': false};
      final d = doc.data() as Map<String, dynamic>;
      final isElevage = d['isElevage'] == true;
      final isPro = d['isPro'] == true;
      final name = isElevage ? (d['nameElevage'] ?? 'Élevage') : '${d['firstname'] ?? ''} ${d['lastname'] ?? ''}'.trim();
      final rawUrl = isElevage ? d['profilePictureUrlElevage'] : d['profilePictureUrl'];
      final photoUrl = (rawUrl != null && rawUrl != _defaultPp && (rawUrl as String).startsWith('http')) ? rawUrl as String : null;
      UserSelected? user;
      if (isElevage || isPro) {
        user = UserSelected.fromMap(d, userId);
      }
      return {'name': name, 'profilePictureUrl': photoUrl, 'isElevage': isElevage, 'isPro': isPro, 'user': user, 'description': d['desc'] ?? '', 'adoptionProject': d['adoptProject'] ?? ''};
    } catch (_) {
      return {'name': 'Utilisateur', 'profilePictureUrl': null, 'isElevage': false, 'isPro': false};
    }
  }

  void _navigateToUser(Map<String, dynamic> userInfo) {
    if (userInfo['user'] != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => UserDetailPageFeed(user: userInfo['user'] as UserSelected)));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => UserParticulierFeedDetails(
        profilePictureUrl: userInfo['profilePictureUrl'],
        description: userInfo['description'],
        adoptionProject: userInfo['adoptionProject'],
        name: userInfo['name'],
      )));
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseStorage.instance.ref().child('chat_images/${DateTime.now().millisecondsSinceEpoch}');
    final snap = await ref.putFile(File(file.path));
    final url = await snap.ref.getDownloadURL();
    _sendMessage('', uid, imageUrl: url);
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_imageFile == null) return;
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;
              final ref = FirebaseStorage.instance.ref().child('chat_images/${DateTime.now().millisecondsSinceEpoch}');
              final snap = await ref.putFile(_imageFile!);
              final url = await snap.ref.getDownloadURL();
              _sendMessage('', uid, imageUrl: url);
            },
            child: const Text('Envoyer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareLocation() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
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
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Envoyer', style: TextStyle(color: _teal))),
      ],
    ));
    if (confirm != true) return;
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      _sendMessage('', uid, lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur GPS : $e')));
    }
  }

  Future<void> _proposeVisite() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.white,
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

            // Date
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  locale: const Locale('fr'),
                );
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

            // Heure
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
                  final dateVisite = DateTime(
                    selectedDate.year, selectedDate.month, selectedDate.day,
                    selectedTime.hour, selectedTime.minute,
                  );
                  await _saveVisite(uid, dateVisite);
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

  Future<void> _saveVisite(String uid, DateTime dateVisite) async {
    final supa = Supabase.instance.client;
    final nomAnimal = widget.nomAnimal ?? 'animal';
    final dateStr = DateFormat('EEEE d MMMM yyyy à HH:mm', 'fr').format(dateVisite);

    // Créer l'événement dans l'agenda des deux parties
    final rows = [
      {
        'uid':        uid,
        'titre':      'Visite — $nomAnimal',
        'type':       'visite',
        'date_debut': dateVisite.toUtc().toIso8601String(),
        'notes':      'Visite organisée via messagerie',
      },
      {
        'uid':        widget.eleveurId,
        'titre':      'Visite — $nomAnimal',
        'type':       'visite',
        'date_debut': dateVisite.toUtc().toIso8601String(),
        'notes':      'Visite organisée via messagerie',
      },
    ];
    try {
      await supa.from('agenda_events').insert(rows);
    } catch (_) {}

    // Envoyer un message dans la conversation
    await _sendMessage('📅  Visite proposée : $dateStr', uid);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Visite ajoutée à vos agendas !',
            style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Color(0xFF0C5C6C),
      ));
    }
  }

  void _showFullImage(String url) {
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(fit: StackFit.loose, children: [
        Positioned.fill(child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain))),
        Positioned(top: 12, right: 12, child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        )),
      ]),
    ));
  }

  void _showMessageOptions(DocumentSnapshot msg) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (msg['senderId'] != uid) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Supprimer le message', style: TextStyle(fontFamily: 'Galey', color: Colors.redAccent)),
            onTap: () {
              Navigator.pop(context);
              _deleteMessage(msg);
            },
          ),
        ]),
      ),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    if (DateUtils.isSameDay(dt, now)) return 'Aujourd\'hui';
    if (DateUtils.isSameDay(dt, now.subtract(const Duration(days: 1)))) return 'Hier';
    return DateFormat('dd MMMM yyyy', 'fr').format(dt);
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    return DateFormat('HH:mm').format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: FutureBuilder<Map<String, dynamic>>(
          future: _getUserInfo(widget.eleveurId),
          builder: (_, snap) {
            final info = snap.data ?? {'name': '...', 'profilePictureUrl': null};
            final name = info['name'] as String? ?? '...';
            final photoUrl = info['profilePictureUrl'] as String?;
            return GestureDetector(
              onTap: snap.hasData ? () => _navigateToUser(snap.data!) : null,
              child: Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF5B9EAA),
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
        // ── Messages list ──────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _conversations.doc(widget.conversationId).collection('messages').orderBy('timestamp').snapshots(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _teal));
              }
              final msgs = snap.data?.docs ?? [];
              if (msgs.isEmpty) {
                return Center(child: Text('Aucun message',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)));
              }

              // Mark as read
              for (final m in msgs) {
                final data = m.data() as Map<String, dynamic>;
                if (data['senderId'] != uid && data['isRead'] == false) {
                  m.reference.update({'isRead': true}).catchError((_) {});
                }
              }

              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

              String? lastReadId;
              for (int i = msgs.length - 1; i >= 0; i--) {
                final d = msgs[i].data() as Map<String, dynamic>;
                if (d['senderId'] == uid && d['isRead'] == true) {
                  lastReadId = msgs[i].id;
                  break;
                }
              }

              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final msg = msgs[i];
                  final data = msg.data() as Map<String, dynamic>;
                  final isMe = data['senderId'] == uid;
                  final ts = data['timestamp'] as Timestamp?;
                  final prevTs = i > 0 ? (msgs[i-1].data() as Map<String, dynamic>)['timestamp'] as Timestamp? : null;
                  final showDate = i == 0 || _formatDate(ts) != _formatDate(prevTs);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showDate)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(_formatDate(ts),
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                            ),
                          ),
                        ),
                      _MessageBubble(
                        data: data,
                        isMe: isMe,
                        time: _formatTime(ts),
                        isLastRead: isMe && msg.id == lastReadId,
                        onLongPress: () => _showMessageOptions(msg),
                        onImageTap: (url) => _showFullImage(url),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        // ── Input bar ──────────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
          child: Row(children: [
            // Attachments
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_circle_outline, color: _teal, size: 26),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                if (v == 'photo') _pickImage();
                else if (v == 'camera') _takePhoto();
                else if (v == 'location') _shareLocation();
                else if (v == 'visite') _proposeVisite();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'photo', child: Row(children: [Icon(Icons.photo_outlined, size: 18), SizedBox(width: 10), Text('Galerie', style: TextStyle(fontFamily: 'Galey'))])),
                PopupMenuItem(value: 'camera', child: Row(children: [Icon(Icons.camera_alt_outlined, size: 18), SizedBox(width: 10), Text('Appareil photo', style: TextStyle(fontFamily: 'Galey'))])),
                PopupMenuItem(value: 'location', child: Row(children: [Icon(Icons.location_on_outlined, size: 18), SizedBox(width: 10), Text('Ma position', style: TextStyle(fontFamily: 'Galey'))])),
                PopupMenuItem(value: 'visite', child: Row(children: [Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF0C5C6C)), SizedBox(width: 10), Text('Proposer une visite', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF0C5C6C)))])),
              ],
            ),
            // Text field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  maxLines: 4,
                  minLines: 1,
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
            // Send button
            GestureDetector(
              onTap: () {
                final text = _controller.text.trim();
                if (text.isEmpty) return;
                final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                _sendMessage(text, uid);
                _controller.clear();
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
    required this.data,
    required this.isMe,
    required this.time,
    required this.isLastRead,
    required this.onLongPress,
    required this.onImageTap,
  });

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  @override
  Widget build(BuildContext context) {
    final text       = (data['text'] as String?) ?? '';
    final imageUrl   = (data['imageUrl'] as String?);
    final isLocation = data['type'] == 'location';

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
                    margin: EdgeInsets.only(
                      left: isMe ? 48 : 4,
                      right: isMe ? 4 : 48,
                    ),
                    padding: imageUrl != null || isLocation
                        ? const EdgeInsets.all(4)
                        : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? _teal : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
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
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                width: 200, height: 200,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                    width: 200, height: 200,
                                    color: Colors.grey.shade200,
                                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
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
                            child: Text(text,
                                style: TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 14,
                                    color: isMe ? Colors.white : const Color(0xFF1F2A2E))),
                          ),
                        const SizedBox(height: 2),
                        Text(time,
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 10,
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
                child: Text('Vu',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade400)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Location card ──────────────────────────────────────────────────────────────

class _LocationCard extends StatelessWidget {
  final double lat;
  final double lng;
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
