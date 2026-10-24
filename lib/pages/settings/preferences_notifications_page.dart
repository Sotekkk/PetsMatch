import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Paramètres → Notifications : choisir les notifications du forum (réponses,
/// citations). Table preferences_notifications, lue par les triggers du forum
/// (migration_forum_notifs_preferences.sql) : une notification refusée n'est
/// ni créée ni envoyée en push. Miroir site : /profil/notifications.
class PreferencesNotificationsPage extends StatefulWidget {
  const PreferencesNotificationsPage({super.key});

  @override
  State<PreferencesNotificationsPage> createState() => _PreferencesNotificationsPageState();
}

class _PreferencesNotificationsPageState extends State<PreferencesNotificationsPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _chargement = true;
  bool _forumReponses = true;
  bool _forumMentions = true;
  int _sujetsMuets = 0;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    if (_uid.isEmpty) return;
    try {
      final p = await _supa.from('preferences_notifications').select().eq('uid', _uid).maybeSingle();
      final m = await _supa.from('forum_sujets_muets').select('sujet_id').eq('uid', _uid);
      if (!mounted) return;
      setState(() {
        _forumReponses = p?['forum_reponses'] != false;
        _forumMentions = p?['forum_mentions'] != false;
        _sujetsMuets = (m as List).length;
        _chargement = false;
      });
    } catch (_) {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _enregistrer({bool? reponses, bool? mentions}) async {
    final avant = (_forumReponses, _forumMentions);
    setState(() {
      if (reponses != null) _forumReponses = reponses;
      if (mentions != null) _forumMentions = mentions;
    });
    try {
      await _supa.from('preferences_notifications').upsert({
        'uid': _uid,
        'forum_reponses': _forumReponses,
        'forum_mentions': _forumMentions,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _forumReponses = avant.$1; _forumMentions = avant.$2; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _reactiverSujets() async {
    try {
      await _supa.from('forum_sujets_muets').delete().eq('uid', _uid);
      if (mounted) setState(() => _sujetsMuets = 0);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white,
          title: const Text('Notifications', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800))),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(padding: const EdgeInsets.all(16), children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text('Forum', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)]),
                child: Column(children: [
                  SwitchListTile(
                    activeThumbColor: _teal,
                    title: const Text('Réponses', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                    subtitle: const Text('Quand quelqu\'un répond à un sujet que vous avez créé ou auquel vous avez participé'),
                    value: _forumReponses,
                    onChanged: (v) => _enregistrer(reponses: v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    activeThumbColor: _teal,
                    title: const Text('Citations', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                    subtitle: const Text('Quand quelqu\'un vous cite (@votre nom) dans un sujet ou une réponse'),
                    value: _forumMentions,
                    onChanged: (v) => _enregistrer(mentions: v),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Text(
                  'Vous pouvez aussi couper les notifications d\'un seul sujet depuis la discussion (icône cloche).',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
              if (_sujetsMuets > 0) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Text(
                    '$_sujetsMuets sujet${_sujetsMuets > 1 ? 's' : ''} sans notification',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
                  TextButton(onPressed: _reactiverSujets, child: const Text('Tout réactiver')),
                ]),
              ],
            ]),
    );
  }
}
