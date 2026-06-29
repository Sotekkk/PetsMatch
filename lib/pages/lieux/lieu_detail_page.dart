import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';

class LieuDetailPage extends StatefulWidget {
  final String id;
  const LieuDetailPage({super.key, required this.id});

  @override
  State<LieuDetailPage> createState() => _LieuDetailPageState();
}

class _LieuDetailPageState extends State<LieuDetailPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supabase = Supabase.instance.client;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  Map<String, dynamic>? _lieu;
  List<Map<String, dynamic>> _avis = [];
  List<Map<String, dynamic>> _dispos = [];
  DateTime _dispoMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _loading = true;
  bool _isFavori = false;
  bool _loadingChat = false;
  String? _profileId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lieu = await _supabase
          .from('petfriendly_places')
          .select()
          .eq('id', widget.id)
          .single();

      final avis = await _supabase
          .from('petfriendly_reviews')
          .select()
          .eq('place_id', widget.id)
          .eq('statut', 'actif')
          .order('created_at', ascending: false)
          .limit(20);

      bool favori = false;
      if (_uid != null) {
        if (_profileId == null) {
          final row = await _supabase.from('user_profiles').select('id').eq('uid', _uid!).eq('is_main', true).maybeSingle();
          _profileId = row?['id'] as String?;
        }
        final filterCol = _profileId != null ? 'user_profile_id' : 'user_uid';
        final filterVal = _profileId ?? _uid!;
        final f = await _supabase.from('place_favoris').select('id').eq('place_id', widget.id).eq(filterCol, filterVal).maybeSingle();
        favori = f != null;
      }

      // Noms des auteurs d'avis
      final avisList = List<Map<String, dynamic>>.from(avis as List);
      final uids = avisList.map((a) => a['user_uid'] as String?).whereType<String>().toSet();
      if (uids.isNotEmpty) {
        try {
          final usersData = await _supabase.from('users')
              .select('uid, firstname, lastname, is_elevage, name_elevage')
              .inFilter('uid', uids.toList());
          for (final u in (usersData as List)) {
            final isElevage = u['is_elevage'] == true;
            final name = isElevage && (u['name_elevage'] as String?)?.isNotEmpty == true
                ? u['name_elevage'] as String
                : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
            for (final a in avisList) {
              if (a['user_uid'] == u['uid']) a['_user_nom'] = name.isEmpty ? 'Utilisateur' : name;
            }
          }
        } catch (_) {}
      }

      List<Map<String, dynamic>> dispos = [];
      if ((lieu['categorie'] as String?) == 'hebergement') {
        try {
          final today = DateTime.now().toIso8601String().substring(0, 10);
          final d = await _supabase
              .from('place_disponibilites')
              .select()
              .eq('place_id', widget.id)
              .gte('date', today)
              .order('date');
          dispos = List<Map<String, dynamic>>.from(d as List);
        } catch (_) {}
      }

      setState(() {
        _lieu = Map<String, dynamic>.from(lieu as Map);
        _avis = avisList;
        _dispos = dispos;
        _isFavori = favori;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavori() async {
    if (_uid == null) return;
    setState(() => _isFavori = !_isFavori);
    if (_isFavori) {
      await _supabase.from('place_favoris').insert({
        'place_id': widget.id,
        'user_uid': _uid,
        if (_profileId != null) 'user_profile_id': _profileId,
      });
      // Notifier le propriétaire (sauf si c'est lui-même)
      final ownerUid = _lieu?['uid_pro'] as String?;
      if (ownerUid != null && ownerUid != _uid) {
        try {
          final me = await _supabase.from('users').select('firstname, lastname').eq('uid', _uid).maybeSingle();
          final nom = me != null ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim() : 'Quelqu\'un';
          final nomLieu = (_lieu?['name'] ?? _lieu?['nom'] ?? 'votre établissement').toString();
          await _supabase.from('notifications').insert({
            'uid': ownerUid,
            'type': 'place_favori',
            'title': '⭐ Nouvel ajout en favori',
            'body': '$nom a ajouté $nomLieu à ses favoris !',
            'data': {'fromUid': _uid, 'placeId': widget.id},
            'read': false,
            'created_at': DateTime.now().toIso8601String(),
          });
          unawaited(FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('notifyPlaceFavori')
              .call({
                'receiverUid': ownerUid,
                'senderName': nom,
                'nomLieu': nomLieu,
                'placeId': widget.id,
              }));
        } catch (_) {}
      }
    } else {
      await _supabase.from('place_favoris').delete().eq('place_id', widget.id).eq('user_uid', _uid);
    }
  }

  Future<void> _openChat() async {
    final uidPro = _lieu?['uid_pro'] as String?;
    if (uidPro == null || _uid == null) return;
    setState(() => _loadingChat = true);
    try {
      final convId = await MessagingHelper.openOrCreateConversation(
        otherUid: uidPro,
        categorie: 'communaute',
      );
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => ChatScreen(conversationId: convId, eleveurId: uidPro)));
      }
    } finally {
      if (mounted) setState(() => _loadingChat = false);
    }
  }

  Future<void> _callPhone(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openNavigation() async {
    final lieu = _lieu!;
    final lat = lieu['lat'];
    final lng = lieu['lng'];
    final wazeUri = Uri.parse('waze://ul?ll=$lat,$lng&navigate=yes');
    final gmapsUri = Uri.parse('https://maps.google.com/?daddr=$lat,$lng');
    if (await canLaunchUrl(wazeUri)) {
      await launchUrl(wazeUri);
    } else {
      await launchUrl(gmapsUri, mode: LaunchMode.externalApplication);
    }
  }

  // Statut ouverture enrichi — comme Google Maps
  String _ouvertLabel() {
    final lieu = _lieu;
    if (lieu == null) return '';
    final horaires = lieu['horaires'] as Map<String, dynamic>?;
    if (horaires == null || horaires.isEmpty) return '';
    const days = ['lundi','mardi','mercredi','jeudi','vendredi','samedi','dimanche'];
    final now = DateTime.now();
    final dayKey = days[now.weekday - 1];
    final val = horaires[dayKey] as String?;

    int parseMins(String s) {
      final p = s.trim().split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    if (val == null || val.toLowerCase().startsWith('ferm')) {
      for (int i = 1; i <= 7; i++) {
        final nextDay = days[(now.weekday - 1 + i) % 7];
        final nv = horaires[nextDay] as String?;
        if (nv != null && !nv.toLowerCase().startsWith('ferm')) {
          final parts = nv.split('-');
          if (parts.isNotEmpty) {
            final label = i == 1 ? 'demain' : nextDay;
            return '🔴 Fermé · Ouvre $label à ${parts[0].trim()}';
          }
        }
      }
      return '🔴 Fermé';
    }

    final parts = val.split('-');
    if (parts.length < 2) return '';
    try {
      final t = now.hour * 60 + now.minute;
      final open = parseMins(parts[0]);
      final close = parseMins(parts[1]);
      if (t < open) return '🔴 Fermé · Ouvre à ${parts[0].trim()}';
      if (t >= open && t < close) {
        if (close - t <= 30) return '🟡 Ferme bientôt · ${parts[1].trim()}';
        return '🟢 Ouvert · Ferme à ${parts[1].trim()}';
      }
      return '🔴 Fermé';
    } catch (_) {
      return '';
    }
  }

  void _openPhoto(List<String> photos, int index) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _PhotoViewer(photos: photos, initialIndex: index),
    ));
  }

  void _showAvisDetail(Map<String, dynamic> avis) {
    final isOwner = avis['user_uid'] == _uid;
    final isPlaceOwner = (_lieu?['uid_pro'] as String?) == _uid;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AvisDetailSheet(
        avis: avis,
        isOwner: isOwner,
        isPlaceOwner: isPlaceOwner,
        uid: _uid,
        onDelete: () async {
          await _supabase.from('petfriendly_reviews').delete().eq('id', avis['id']);
          _load();
        },
        onReload: _load,
      ),
    );
  }

  // ─── Section horaires ──────────────────────────────────────────────────────

  Widget _buildHorairesSection(Map<String, dynamic>? horaires) {
    if (horaires == null || horaires.isEmpty) return const SizedBox.shrink();
    const days = ['lundi','mardi','mercredi','jeudi','vendredi','samedi','dimanche'];
    final todayKey = days[DateTime.now().weekday - 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Horaires', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(
            children: days.map((d) {
              final val = horaires[d] as String?;
              final ferme = val == null || val.toLowerCase().startsWith('ferm');
              final isToday = d == todayKey;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      d[0].toUpperCase() + d.substring(1),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                        color: isToday ? _teal : null,
                      ),
                    ),
                  ),
                  Text(
                    ferme ? 'Fermé' : (val ?? ''),
                    style: TextStyle(
                      fontSize: 13,
                      color: ferme ? Colors.red.shade400 : Colors.grey.shade700,
                      fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ]),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Section disponibilités (hébergement) ──────────────────────────────────

  Widget _buildDisposSection() {
    final prixDefaut = _lieu?['prix_nuit_defaut'] as int? ?? 0;
    if (_dispos.isEmpty && prixDefaut == 0) return const SizedBox.shrink();

    final exceptionsMap = <String, Map<String, dynamic>>{
      for (final d in _dispos) d['date'] as String: d,
    };

    const monthNames = ['Janvier','Février','Mars','Avril','Mai','Juin',
                        'Juillet','Août','Septembre','Octobre','Novembre','Décembre'];
    final now = DateTime.now();
    final minMonth = DateTime(now.year, now.month, 1);
    final prevMonth = DateTime(_dispoMonth.year, _dispoMonth.month - 1, 1);
    final nextMonth = DateTime(_dispoMonth.year, _dispoMonth.month + 1, 1);
    final canGoPrev = prevMonth.isAfter(minMonth) || prevMonth == minMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Disponibilités',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
          if (prixDefaut > 0) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
              child: Text('$prixDefaut€/nuit',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _teal)),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _DispoLegend(color: Colors.white, border: Colors.grey.shade300, label: 'Disponible'),
          const SizedBox(width: 8),
          _DispoLegend(color: const Color(0xFFE8F5E9), border: _teal, label: 'Prix spécial'),
          const SizedBox(width: 8),
          _DispoLegend(color: Colors.red.shade50, border: Colors.red.shade200, label: 'Indisponible'),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
          ),
          child: Column(
            children: [
              Row(children: [
                IconButton(
                  onPressed: canGoPrev
                      ? () => setState(() => _dispoMonth = prevMonth)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: _teal,
                  disabledColor: Colors.grey.shade300,
                ),
                Expanded(child: Center(child: Text(
                  '${monthNames[_dispoMonth.month - 1]} ${_dispoMonth.year}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14),
                ))),
                IconButton(
                  onPressed: () => setState(() => _dispoMonth = nextMonth),
                  icon: const Icon(Icons.chevron_right),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: _teal,
                ),
              ]),
              const SizedBox(height: 8),
              _buildDispoGrid(_dispoMonth, exceptionsMap, prixDefaut),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Contactez l\'établissement pour réserver.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDispoGrid(DateTime month, Map<String, Map<String, dynamic>> exceptions, int prixDefaut) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final startOffset = firstDay.weekday - 1;
    final today = DateTime.now();

    return Column(
      children: [
        Row(children: ['L','M','M','J','V','S','D'].map((d) => Expanded(
          child: Center(child: Text(d,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
        )).toList()),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, childAspectRatio: 0.85,
          ),
          itemCount: startOffset + lastDay.day,
          itemBuilder: (_, i) {
            if (i < startOffset) return const SizedBox();
            final day = DateTime(month.year, month.month, i - startOffset + 1);
            final ds = '${day.year.toString().padLeft(4,'0')}-${day.month.toString().padLeft(2,'0')}-${day.day.toString().padLeft(2,'0')}';
            final exc = exceptions[ds];
            final isPast = day.isBefore(DateTime(today.year, today.month, today.day));
            final isUnavail = exc != null && !(exc['disponible'] as bool? ?? true);
            final hasCustom = exc != null && !isUnavail;
            final prix = exc?['prix_override'] as int? ?? prixDefaut;
            final isToday = day.year == today.year && day.month == today.month && day.day == today.day;

            Color bg, borderColor, textColor;
            if (isPast) {
              bg = Colors.grey.shade50; borderColor = Colors.grey.shade100; textColor = Colors.grey.shade300;
            } else if (isUnavail) {
              bg = Colors.red.shade50; borderColor = Colors.red.shade200; textColor = Colors.red.shade400;
            } else if (hasCustom) {
              bg = const Color(0xFFE8F5E9); borderColor = _teal; textColor = _teal;
            } else {
              bg = Colors.white; borderColor = Colors.grey.shade200; textColor = Colors.black87;
            }

            return Container(
              margin: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isToday ? _teal : borderColor, width: isToday ? 2 : 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${day.day}', style: TextStyle(
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 11, color: textColor,
                  )),
                  if (!isPast)
                    Text(
                      isUnavail ? '✖' : (prix > 0 ? '${prix}€' : ''),
                      style: TextStyle(fontSize: 8, color: textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }
    if (_lieu == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white),
        body: const Center(child: Text('Lieu introuvable')),
      );
    }

    final lieu = _lieu!;
    final nom = lieu['nom'] as String? ?? '';
    final ville = lieu['ville'] as String? ?? '';
    final adresse = lieu['adresse'] as String? ?? '';
    final description = lieu['description'] as String? ?? '';
    final banniere = lieu['banniere_url'] as String?;
    final photos = List<String>.from(lieu['photos'] as List? ?? []);
    final especes = List<String>.from(lieu['especes_acceptees'] as List? ?? []);
    final note = (lieu['note_moyenne'] as num?)?.toDouble() ?? 0.0;
    final nbAvis = lieu['nb_avis'] as int? ?? 0;
    final tel = lieu['telephone'] as String?;
    final site = lieu['site_web'] as String?;
    final categorie = lieu['categorie'] as String? ?? '';
    final horaires = lieu['horaires'] as Map<String, dynamic>?;
    final ouvert = _ouvertLabel();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _teal,
        child: CustomScrollView(
        slivers: [
          // Bannière
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(_isFavori ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                onPressed: _toggleFavori,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: banniere != null && banniere.isNotEmpty
                  ? CachedNetworkImage(imageUrl: banniere, fit: BoxFit.cover)
                  : Container(
                      color: categorie == 'hebergement'
                          ? const Color(0xFF1E88E5)
                          : const Color(0xFFEF6C00),
                      child: Icon(
                        categorie == 'hebergement' ? Icons.hotel_outlined : Icons.restaurant_outlined,
                        size: 80, color: Colors.white30,
                      ),
                    ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nom
                  Text(nom,
                      style: const TextStyle(
                        fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 22, color: Color(0xFF1E2025),
                      )),
                  const SizedBox(height: 8),
                  if (ouvert.isNotEmpty) ...[
                    Text(ouvert, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                  ],
                  if (note > 0)
                    Row(children: [
                      const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFA000)),
                      const SizedBox(width: 2),
                      Text('${note.toStringAsFixed(1)} ($nbAvis avis)',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  const SizedBox(height: 12),

                  // Adresse + nav
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                    ),
                    child: Column(
                      children: [
                        Row(children: [
                          const Icon(Icons.location_on_rounded, color: _teal, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text('$adresse, $ville',
                              style: const TextStyle(fontSize: 13))),
                        ]),
                        if (tel != null) ...[
                          const Divider(height: 16),
                          GestureDetector(
                            onTap: () => _callPhone(tel),
                            child: Row(children: [
                              const Icon(Icons.phone_outlined, color: _teal, size: 18),
                              const SizedBox(width: 8),
                              Text(tel, style: const TextStyle(fontSize: 13, color: _teal)),
                            ]),
                          ),
                        ],
                        if (site != null) ...[
                          const Divider(height: 16),
                          GestureDetector(
                            onTap: () {
                              final url = (site.startsWith('http://') || site.startsWith('https://'))
                                  ? site
                                  : 'https://$site';
                              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                            },
                            child: Row(children: [
                              const Icon(Icons.language_outlined, color: _teal, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(site,
                                  style: const TextStyle(fontSize: 13, color: _teal,
                                      decoration: TextDecoration.underline),
                                  overflow: TextOverflow.ellipsis)),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (tel != null) ...[
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _callPhone(tel),
                                  icon: const Icon(Icons.call_rounded, size: 18),
                                  label: const Text('Appeler'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade600,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (_uid != null && _uid != lieu['uid_pro']) ...[
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _loadingChat ? null : _openChat,
                                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                  label: const Text('Message'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _teal,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _openNavigation,
                                icon: const Icon(Icons.navigation_rounded, size: 18),
                                label: const Text('Itinéraire'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF334155),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Espèces acceptées
                  if (especes.isNotEmpty) ...[
                    const Text('Animaux acceptés',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 6,
                      children: especes.map((e) {
                        const labels = {
                          'chien': 'Chien', 'chat': 'Chat', 'cheval': 'Cheval',
                          'lapin': 'Lapin', 'oiseau': 'Oiseau', 'nac': 'NAC',
                        };
                        return Chip(
                          label: Text(labels[e.toLowerCase()] ?? e,
                              style: const TextStyle(fontSize: 12)),
                          backgroundColor: const Color(0xFFE8F5E9),
                          side: BorderSide.none,
                          padding: EdgeInsets.zero,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Champs spécifiques hébergement
                  if (categorie == 'hebergement') ...[
                    const Text('Conditions animaux',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 8),
                    _PetInfoCard(lieu: lieu),
                    const SizedBox(height: 16),
                  ],

                  // Description
                  if (description.isNotEmpty) ...[
                    const Text('Description',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 8),
                    Text(description, style: const TextStyle(fontSize: 13, height: 1.5)),
                    const SizedBox(height: 16),
                  ],

                  // Horaires
                  _buildHorairesSection(horaires),

                  // Disponibilités (hébergement)
                  if (categorie == 'hebergement') _buildDisposSection(),

                  // Photos
                  if (photos.isNotEmpty) ...[
                    const Text('Photos',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => _openPhoto(photos, i),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: photos[i],
                              width: 90, height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Avis
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Avis ($nbAvis)',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                      if (_uid != null)
                        TextButton.icon(
                          onPressed: () => _showAvisForm(context),
                          icon: const Icon(Icons.rate_review_outlined, size: 16),
                          label: const Text('Laisser un avis'),
                          style: TextButton.styleFrom(foregroundColor: _teal),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_avis.isEmpty)
                    const Text('Aucun avis pour le moment.',
                        style: TextStyle(color: Colors.grey, fontSize: 13))
                  else
                    ..._avis.map((a) => _AvisCard(
                      avis: a,
                      onTap: () => _showAvisDetail(a),
                    )),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  void _showAvisForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AvisForm(placeId: widget.id, uid: _uid!, onSubmit: () {
        Navigator.pop(context);
        _load();
      }),
    );
  }
}

// ─── Viewer photos plein écran ───────────────────────────────────────────────

class _PhotoViewer extends StatelessWidget {
  final List<String> photos;
  final int initialIndex;
  const _PhotoViewer({required this.photos, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${initialIndex + 1} / ${photos.length}',
            style: const TextStyle(fontSize: 14)),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: photos.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: photos[i],
              fit: BoxFit.contain,
              placeholder: (_, __) => const CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Infos pet hébergement ───────────────────────────────────────────────────

class _PetInfoCard extends StatelessWidget {
  final Map<String, dynamic> lieu;
  const _PetInfoCard({required this.lieu});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    void add(String label, dynamic val) {
      if (val == null) return;
      String text;
      if (val is bool) {
        text = val ? '✅ $label' : '❌ $label';
      } else {
        text = '$label : $val';
      }
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      ));
    }

    add('Animaux dans la chambre', lieu['animaux_dans_chambre']);
    final frais = lieu['frais_animal_nuit'];
    if (frais != null) add('Supplément / nuit', '${frais}€');
    final nbMax = lieu['nb_animaux_max'];
    if (nbMax != null) add('Animaux max / séjour', nbMax == 0 ? 'Pas de limite' : '$nbMax');
    add('Espace détente animaux', lieu['espace_detente']);

    final equip = List<String>.from(lieu['equipements_fournis'] as List? ?? []);
    if (equip.isNotEmpty) {
      items.add(Text('Équipements fournis : ${equip.join(', ')}',
          style: const TextStyle(fontSize: 13)));
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: items),
    );
  }
}

// ─── Card avis (simple, tap → détail) ───────────────────────────────────────

class _AvisCard extends StatelessWidget {
  final Map<String, dynamic> avis;
  final VoidCallback onTap;
  const _AvisCard({required this.avis, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final note = avis['note'] as int? ?? 0;
    final noteAccueil = avis['note_accueil'] as int? ?? 0;
    final commentaire = avis['commentaire'] as String? ?? '';
    final reponse = avis['reponse_pro'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              ...List.generate(5, (i) => Icon(
                i < note ? Icons.star_rounded : Icons.star_border_rounded,
                size: 15, color: const Color(0xFFFFA000),
              )),
              if (noteAccueil > 0) ...[
                const SizedBox(width: 6),
                Icon(Icons.pets, size: 12, color: Colors.grey.shade400),
                ...List.generate(5, (i) => Icon(
                  i < noteAccueil ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 12, color: Colors.grey.shade400,
                )),
              ],
              const Spacer(),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
            ]),
            const SizedBox(height: 4),
            Text(avis['_user_nom'] as String? ?? 'Anonyme',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Text(commentaire,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.4)),
            if (reponse != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.store_outlined, size: 13, color: Color(0xFF0C5C6C)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(reponse,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11))),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Détail avis (bottom sheet) ──────────────────────────────────────────────

class _AvisDetailSheet extends StatefulWidget {
  final Map<String, dynamic> avis;
  final bool isOwner;
  final bool isPlaceOwner;
  final String? uid;
  final VoidCallback onDelete;
  final VoidCallback onReload;
  const _AvisDetailSheet({
    required this.avis,
    required this.isOwner,
    required this.isPlaceOwner,
    required this.uid,
    required this.onDelete,
    required this.onReload,
  });

  @override
  State<_AvisDetailSheet> createState() => _AvisDetailSheetState();
}

class _AvisDetailSheetState extends State<_AvisDetailSheet> {
  static const _teal = Color(0xFF0C5C6C);

  bool _editing = false;
  bool _reporting = false;
  bool _saving = false;

  late int _editNote;
  late int _editNoteAccueil;
  late final TextEditingController _editCtrl;
  late final TextEditingController _reportCtrl;

  @override
  void initState() {
    super.initState();
    _editNote = widget.avis['note'] as int? ?? 0;
    _editNoteAccueil = widget.avis['note_accueil'] as int? ?? 0;
    _editCtrl = TextEditingController(text: widget.avis['commentaire'] as String? ?? '');
    _reportCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    _reportCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveEdit() async {
    if (_editNote == 0 || _editNoteAccueil == 0 || _editCtrl.text.trim().length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note + accueil obligatoires, commentaire min 20 chars')));
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('petfriendly_reviews')
          .update({
            'note': _editNote,
            'note_accueil': _editNoteAccueil,
            'commentaire': _editCtrl.text.trim(),
          })
          .eq('id', widget.avis['id']);
      if (mounted) {
        Navigator.pop(context);
        widget.onReload();
      }
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _saveReport(String type) async {
    if (_reportCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merci d\'indiquer le motif')));
      return;
    }
    setState(() => _saving = true);
    try {
      final profileRow = await Supabase.instance.client
          .from('user_profiles').select('id').eq('uid', widget.uid).eq('is_main', true).maybeSingle();
      final userProfileId = profileRow?['id'] as String?;
      await Supabase.instance.client.from('petfriendly_review_contests').insert({
        'review_id': widget.avis['id'],
        'place_id': widget.avis['place_id'],
        'user_uid': widget.uid,
        if (userProfileId != null) 'user_profile_id': userProfileId,
        'motif': _reportCtrl.text.trim(),
        'type': type,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Signalement envoyé — notre équipe va l\'examiner'),
          backgroundColor: _teal,
        ));
      }
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Widget _stars(int count, ValueChanged<int> onTap) => Row(
    children: List.generate(5, (i) => GestureDetector(
      onTap: () => onTap(i + 1),
      child: Icon(
        i < count ? Icons.star_rounded : Icons.star_border_rounded,
        size: 28, color: const Color(0xFFFFA000),
      ),
    )),
  );

  @override
  Widget build(BuildContext context) {
    if (_editing) return _buildEditForm();
    if (_reporting) return _buildReportForm();
    return _buildView();
  }

  Widget _buildView() {
    final avis = widget.avis;
    final note = avis['note'] as int? ?? 0;
    final noteAccueil = avis['note_accueil'] as int? ?? 0;
    final commentaire = avis['commentaire'] as String? ?? '';
    final animalNom = avis['animal_nom'] as String?;
    final dateVisite = avis['date_visite'] as String?;
    final reponse = avis['reponse_pro'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Avis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 16),
          const Text('Note globale', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          Row(children: List.generate(5, (i) => Icon(
            i < note ? Icons.star_rounded : Icons.star_border_rounded,
            size: 22, color: const Color(0xFFFFA000),
          ))),
          if (noteAccueil > 0) ...[
            const SizedBox(height: 10),
            const Text('Accueil des animaux', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Row(children: List.generate(5, (i) => Icon(
              i < noteAccueil ? Icons.star_rounded : Icons.star_border_rounded,
              size: 22, color: const Color(0xFFFFA000),
            ))),
          ],
          const SizedBox(height: 6),
          Text(avis['_user_nom'] as String? ?? 'Anonyme',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
          Text(commentaire, style: const TextStyle(fontSize: 14, height: 1.6)),
          if (animalNom != null) ...[
            const SizedBox(height: 10),
            Text('Avec $animalNom',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
          if (dateVisite != null) ...[
            const SizedBox(height: 4),
            Text('Visité le $dateVisite',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ],
          if (reponse != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Réponse de l\'établissement',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: _teal)),
                  const SizedBox(height: 6),
                  Text(reponse, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (widget.isOwner) ...[
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Modifier'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                label: const Text('Supprimer', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),
            ]),
          ] else if (widget.uid != null) ...[
            SizedBox(width: double.infinity, child: TextButton.icon(
              onPressed: () => setState(() => _reporting = true),
              icon: const Icon(Icons.flag_outlined, size: 16, color: Colors.orange),
              label: Text(
                widget.isPlaceOwner ? 'Contester cet avis' : 'Signaler cet avis',
                style: const TextStyle(color: Colors.orange),
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconButton(
                onPressed: () => setState(() => _editing = false),
                icon: const Icon(Icons.arrow_back),
              ),
              const Text('Modifier mon avis',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            ]),
            const SizedBox(height: 12),
            const Text('Note globale', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _stars(_editNote, (v) => setState(() => _editNote = v)),
            const SizedBox(height: 12),
            const Text('Accueil des animaux', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _stars(_editNoteAccueil, (v) => setState(() => _editNoteAccueil = v)),
            const SizedBox(height: 12),
            TextField(
              controller: _editCtrl,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: 'Commentaire (min 20 caractères)…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _teal),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveEdit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportForm() {
    final isContest = widget.isPlaceOwner;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconButton(
                onPressed: () => setState(() => _reporting = false),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(child: Text(
                isContest ? 'Contester cet avis' : 'Signaler cet avis',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
              )),
            ]),
            const SizedBox(height: 8),
            Text(
              isContest
                  ? 'Expliquez pourquoi vous contestez cet avis. Notre équipe l\'examinera sous 48h.'
                  : 'Expliquez pourquoi vous signalez cet avis. Notre équipe l\'examinera sous 48h.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reportCtrl,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Motif du signalement…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _teal),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : () => _saveReport(isContest ? 'contest' : 'report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Envoyer le signalement',
                        style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Supprimer cet avis ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(d);
              Navigator.pop(context);
              widget.onDelete();
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ─── Formulaire avis ─────────────────────────────────────────────────────────

class _AvisForm extends StatefulWidget {
  final String placeId;
  final String uid;
  final VoidCallback onSubmit;
  const _AvisForm({required this.placeId, required this.uid, required this.onSubmit});

  @override
  State<_AvisForm> createState() => _AvisFormState();
}

class _AvisFormState extends State<_AvisForm> {
  static const _teal = Color(0xFF0C5C6C);
  int _note = 0;
  int _noteAccueil = 0;
  final _commentCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (_note == 0 || _noteAccueil == 0 || _commentCtrl.text.trim().length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note + accueil obligatoires, commentaire min 20 chars')));
      return;
    }
    setState(() => _saving = true);
    try {
      final profileRow = await Supabase.instance.client
          .from('user_profiles').select('id').eq('uid', widget.uid).eq('is_main', true).maybeSingle();
      final userProfileId = profileRow?['id'] as String?;
      await Supabase.instance.client.from('petfriendly_reviews').insert({
        'place_id': widget.placeId,
        'user_uid': widget.uid,
        if (userProfileId != null) 'user_profile_id': userProfileId,
        'note': _note,
        'note_accueil': _noteAccueil,
        'commentaire': _commentCtrl.text.trim(),
      });
      widget.onSubmit();
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().contains('unique')
                ? 'Vous avez déjà laissé un avis'
                : 'Erreur : $e')));
      }
    }
  }

  Widget _stars(int selected, ValueChanged<int> onTap) {
    return Row(
      children: List.generate(5, (i) => GestureDetector(
        onTap: () => onTap(i + 1),
        child: Icon(
          i < selected ? Icons.star_rounded : Icons.star_border_rounded,
          size: 32, color: const Color(0xFFFFA000),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Laisser un avis',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 16),
          const Text('Note globale', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _stars(_note, (v) => setState(() => _note = v)),
          const SizedBox(height: 12),
          const Text('Accueil des animaux', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _stars(_noteAccueil, (v) => setState(() => _noteAccueil = v)),
          const SizedBox(height: 12),
          TextField(
            controller: _commentCtrl,
            maxLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(
              hintText: 'Votre commentaire (min 20 caractères)…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _teal),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Publier l\'avis', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DispoLegend extends StatelessWidget {
  final Color color, border;
  final String label;
  const _DispoLegend({required this.color, required this.border, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 11, height: 11,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);
}
