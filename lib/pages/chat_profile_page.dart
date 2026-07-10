import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatProfilePage extends StatefulWidget {
  final String uid;
  const ChatProfilePage({super.key, required this.uid});

  @override
  State<ChatProfilePage> createState() => _ChatProfilePageState();
}

class _ChatProfilePageState extends State<ChatProfilePage> {
  static const _teal = Color(0xFF0C5C6C);

  final _supa = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _animaux = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _supa
          .from('user_profiles')
          .select('firstname, lastname, ville, avatar_url')
          .eq('uid', widget.uid)
          .eq('is_main', true)
          .maybeSingle();

      List<Map<String, dynamic>> animaux = [];
      try {
        final res = await _supa
            .from('animaux')
            .select('id, nom, espece, race, date_naissance, photo_url, couleur')
            .eq('uid_proprietaire', widget.uid)
            .not('statut', 'in', '(sorti,decede)');
        animaux = List<Map<String, dynamic>>.from(res as List);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _profile = p != null ? Map<String, dynamic>.from(p) : null;
          _animaux = animaux;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendSignalementEmail({required String motif, String? details}) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    const username = 'petsmatch.contact@gmail.com';
    const password = 'dppu ctgp buve bxjd';
    final smtpServer = gmail(username, password);
    final message = Message()
      ..from = const Address(username, 'PetsMatch - Signalement')
      ..recipients.add(username)
      ..subject = '🔔 Signalement utilisateur : ${widget.uid}'
      ..text = '''
Un utilisateur a été signalé via l'application PetsMatch.

🔹 UID signalé : ${widget.uid}
🔹 UID signaleur : $myUid
🔹 Motif : $motif
🔹 Détails : ${details ?? "Non précisé"}

Veuillez traiter ce signalement sous 24h conformément aux CGU.

- PetsMatch App
''';
    await send(message, smtpServer);
  }

  Future<void> _blockUser() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bloquer cet utilisateur ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text(
            'Vous ne recevrez plus ses messages et son profil sera masqué.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bloquer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _supa.from('bloquages').insert({'uid': myUid, 'blocked_uid': widget.uid});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Utilisateur bloqué.')),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du blocage.')),
        );
      }
    }
  }

  void _showSignalementDialog() {
    String selectedMotif = 'Comportement abusif';
    final detailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Signaler un utilisateur',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(children: [
              RadioListTile(
                title: const Text('Comportement abusif', style: TextStyle(fontFamily: 'Galey')),
                value: 'Comportement abusif', groupValue: selectedMotif,
                onChanged: (v) => setS(() => selectedMotif = v!),
              ),
              RadioListTile(
                title: const Text('Contenu inapproprié', style: TextStyle(fontFamily: 'Galey')),
                value: 'Contenu inapproprié', groupValue: selectedMotif,
                onChanged: (v) => setS(() => selectedMotif = v!),
              ),
              RadioListTile(
                title: const Text('Spam ou arnaque', style: TextStyle(fontFamily: 'Galey')),
                value: 'Spam ou arnaque', groupValue: selectedMotif,
                onChanged: (v) => setS(() => selectedMotif = v!),
              ),
              RadioListTile(
                title: const Text('Autre', style: TextStyle(fontFamily: 'Galey')),
                value: 'Autre', groupValue: selectedMotif,
                onChanged: (v) => setS(() => selectedMotif = v!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: detailCtrl,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Détails (facultatif)',
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _sendSignalementEmail(
                      motif: selectedMotif, details: detailCtrl.text.trim());
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Signalement envoyé.')),
                    );
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Erreur lors de l'envoi.")),
                    );
                  }
                }
              },
              child: const Text('Envoyer', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isMe = widget.uid == myUid;

    final appBar = AppBar(
      backgroundColor: _teal,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        _profile != null
            ? '${_profile!['firstname'] ?? ''} ${_profile!['lastname'] ?? ''}'.trim()
            : '',
        style: const TextStyle(
            fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
      ),
      actions: [
        if (!isMe)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'signaler') _showSignalementDialog();
              if (v == 'bloquer') _blockUser();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'signaler',
                child: Row(children: [
                  Icon(Icons.flag_outlined, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Signaler', style: TextStyle(fontFamily: 'Galey')),
                ]),
              ),
              const PopupMenuItem(
                value: 'bloquer',
                child: Row(children: [
                  Icon(Icons.block_outlined, color: Colors.black87, size: 20),
                  SizedBox(width: 8),
                  Text('Bloquer', style: TextStyle(fontFamily: 'Galey')),
                ]),
              ),
            ],
          ),
      ],
    );

    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator(color: _teal)),
      );
    }

    if (_profile == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: appBar,
        body: const Center(
          child: Text('Profil introuvable',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey)),
        ),
      );
    }

    final p = _profile!;
    final nom = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
    final city = p['ville']?.toString() ?? '';
    final photo = p['avatar_url']?.toString() ?? '';
    const adopt = '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: appBar,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header card ──────────────────────────────────────────
          _card(
            Column(children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: const Color(0xFFE0EEF2),
                backgroundImage:
                    photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
                child: photo.isEmpty
                    ? const Icon(Icons.person_outline, size: 46, color: _teal)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                nom.isNotEmpty ? nom : '—',
                style: const TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: Color(0xFF1F2A2E)),
              ),
              if (city.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(city,
                      style: const TextStyle(
                          fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
                ]),
              ],
            ]),
          ),

          // ── Projet d'adoption ────────────────────────────────────
          if (adopt.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionTitle('Projet d\'adoption'),
            _card(
              Text(adopt,
                  style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 13, height: 1.5,
                      color: Color(0xFF1F2A2E))),
            ),
          ],

          // ── Animaux ──────────────────────────────────────────────
          const SizedBox(height: 12),
          _sectionTitle('Animaux (${_animaux.length})'),
          if (_animaux.isEmpty)
            _card(
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucun animal partagé',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
              ),
            )
          else
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                itemCount: _animaux.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _animalCard(_animaux[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: child,
      );

  Widget _sectionTitle(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF1F2A2E))),
      );

  Widget _animalCard(Map<String, dynamic> a) {
    final photo = a['photo_url']?.toString() ?? '';
    final nom = a['nom']?.toString() ?? '—';
    final espece = a['espece']?.toString() ?? '';
    final race = a['race']?.toString() ?? '';

    return Container(
      width: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
            child: photo.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photo,
                    width: 110,
                    height: 80,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _animalPlaceholder(),
                  )
                : _animalPlaceholder(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                if (race.isNotEmpty || espece.isNotEmpty)
                  Text(race.isNotEmpty ? race : espece,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 11,
                          color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _animalPlaceholder() => Container(
        width: 110,
        height: 80,
        color: const Color(0xFFE0EEF2),
        child: const Icon(Icons.pets, color: _teal, size: 28),
      );
}
