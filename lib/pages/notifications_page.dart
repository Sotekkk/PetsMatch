import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _orange = Color(0xFFE65100);

  final _supa = Supabase.instance.client;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (_uid.isEmpty) return;
    try {
      final data = await _supa
          .from('notifications')
          .select()
          .eq('uid', _uid)
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) setState(() {
        _notifs = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteNotif(Map<String, dynamic> notif) async {
    try {
      await _supa.from('notifications').delete().eq('id', notif['id']);
      if (mounted) setState(() => _notifs.removeWhere((n) => n['id'] == notif['id']));
    } catch (_) {}
  }

  Future<void> _deleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer toutes les notifications ?', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _supa.from('notifications').delete().eq('uid', _uid);
      if (mounted) setState(() => _notifs.clear());
    } catch (_) {}
  }

  Future<void> _handleTap(Map<String, dynamic> notif) async {
    final type = notif['type'] as String?;
    final data = notif['data'];
    String? alerteId;
    if (data is Map) alerteId = data['alerteId'] as String?;

    _deleteNotif(notif);

    if (!mounted) return;
    if (type == 'alerte_perdu') {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnimauxPerdusPage(initialAlertId: alerteId),
      ));
    }
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return DateFormat('dd/MM/yyyy', 'fr').format(dt);
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'alerte_perdu': return Icons.location_searching;
      case 'message': return Icons.chat_bubble_outline;
      default: return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String? type) {
    switch (type) {
      case 'alerte_perdu': return _orange;
      case 'message': return _teal;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Notifications',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          if (_notifs.isNotEmpty)
            TextButton(
              onPressed: _deleteAll,
              child: const Text('Tout supprimer',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.white70, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _fetch,
              color: _teal,
              child: _notifs.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.notifications_none, size: 72, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text('Aucune notification',
                                  style: TextStyle(
                                      fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _notifs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (context, i) {
                        final n = _notifs[i];
                        final isRead = n['read'] == true;
                        final type = n['type'] as String?;

                        return Dismissible(
                          key: ValueKey(n['id']),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red.shade400,
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          onDismissed: (_) => _deleteNotif(n),
                          child: InkWell(
                          onTap: () => _handleTap(n),
                          child: Container(
                            color: isRead ? Colors.transparent : _teal.withAlpha(12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _colorFor(type).withAlpha(20),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(_iconFor(type), color: _colorFor(type), size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(n['title'] as String? ?? '',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                              fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text(n['body'] as String? ?? '',
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 13,
                                              color: Colors.grey.shade600),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(_timeAgo(n['created_at'] as String?),
                                          style: TextStyle(
                                              fontFamily: 'Galey',
                                              fontSize: 11,
                                              color: Colors.grey.shade400)),
                                    ],
                                  ),
                                ),
                                if (!isRead)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 6, left: 6),
                                    decoration: const BoxDecoration(
                                      color: _teal,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ));
                      },
                    ),
            ),
    );
  }
}

/// Streams the unread notification count from Supabase for the badge.
class NotifBadge extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final VoidCallback onTap;

  const NotifBadge({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.onTap,
  });

  @override
  State<NotifBadge> createState() => _NotifBadgeState();
}

class _NotifBadgeState extends State<NotifBadge> {
  static const _green = Color(0xFF6E9E57);
  final _supa = Supabase.instance.client;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  int _unread = 0;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _fetchUnread();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchUnread() async {
    if (_uid.isEmpty) return;
    try {
      final data = await _supa
          .from('notifications')
          .select('id')
          .eq('uid', _uid)
          .eq('read', false);
      if (mounted) setState(() => _unread = (data as List).length);
    } catch (_) {}
  }

  void _subscribe() {
    if (_uid.isEmpty) return;
    _channel = _supa
        .channel('notif_badge_$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'uid', value: _uid),
          callback: (_) => _fetchUnread(),
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  widget.active ? widget.activeIcon : widget.icon,
                  color: widget.active ? _green : Colors.grey,
                  size: 24,
                ),
                if (_unread > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text(
                        _unread > 99 ? '99+' : '$_unread',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'Alertes',
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Galey',
                  color: widget.active ? _green : Colors.grey,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}
