import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/pro/rdv_booking_page.dart';
import 'package:PetsMatch/widgets/animal_picker_sheet.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:intl/intl.dart';

class ServiceDetailPage extends StatefulWidget {
  final String proUid;
  final String categoryLabel;
  final Color categoryColor;
  /// UUID from user_profiles.id — set for secondary profiles, null for primary
  final String? profileTableId;

  const ServiceDetailPage({
    super.key,
    required this.proUid,
    required this.categoryLabel,
    required this.categoryColor,
    this.profileTableId,
  });

  @override
  State<ServiceDetailPage> createState() => _ServiceDetailPageState();
}

class _ServiceDetailPageState extends State<ServiceDetailPage>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  Map<String, dynamic>? _proData;
  bool _loading = true;
  bool _loadingChat = false;
  late TabController _tabController;
  List<Map<String, dynamic>> _coursCollectifs = [];
  Map<String, int> _participantsCount = {};
  bool _inscrivant = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPro();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPro() async {
    try {
      Map<String, dynamic>? row;
      if (widget.profileTableId != null) {
        final raw = await _supa
            .from('user_profiles')
            .select()
            .eq('id', widget.profileTableId!)
            .maybeSingle();
        if (raw != null) {
          row = {
            ...raw,
            'uid':                       raw['uid'],
            'name_elevage':              raw['nom'] ?? raw['name_elevage'] ?? '',
            'profile_picture_url_elevage': raw['avatar_url'] ?? '',
            'profile_picture_url':       raw['avatar_url'] ?? '',
            'banner_url':                raw['banner_url'] ?? '',
            'ville_elevage':             raw['ville'] ?? '',
            'ville':                     raw['ville'] ?? '',
            'desc_entreprise':           raw['desc_entreprise'] ?? raw['description'] ?? '',
            'especes_acceptees':         raw['especes_acceptees'] ?? [],
            'accept_new_clients':        raw['accept_new_clients'] ?? true,
            'horaires':                  raw['horaires'] ?? {},
            'certifications':            raw['certifications'] ?? [],
            'tarifs':                    raw['tarifs'] ?? '',
            'site_web':                  raw['site_web'] ?? '',
            'instagram':                 raw['instagram'] ?? '',
            'facebook':                  raw['facebook'] ?? '',
            'rayon_intervention':        raw['rayon_intervention'] ?? 0,
            'cat_pro':                   raw['profile_type'] ?? raw['cat_pro'] ?? '',
            'profession_pro':            raw['profession_pro'] ?? '',
            'lat':                       raw['latitude'] ?? raw['lat'],
            'lng':                       raw['longitude'] ?? raw['lng'],
          };
        }
      } else {
        row = await _supa
            .from('users')
            .select()
            .eq('uid', widget.proUid)
            .maybeSingle();
      }
      if (mounted) setState(() { _proData = row; _loading = false; });
      if (row?['cat_pro'] == 'education') await _loadCoursCollectifs();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCoursCollectifs() async {
    final proUid = _proData?['uid']?.toString();
    if (proUid == null) return;
    try {
      final rows = await _supa.from('cours_collectifs').select()
          .eq('pro_uid', proUid)
          .eq('statut', 'planifie')
          .gte('date_heure', DateTime.now().toIso8601String())
          .order('date_heure');
      final cours = List<Map<String, dynamic>>.from(rows as List);
      final coursIds = cours.map((c) => c['id'] as String).toList();
      final counts = <String, int>{};
      if (coursIds.isNotEmpty) {
        final participants = await _supa.from('cours_collectifs_participants')
            .select('cours_id').inFilter('cours_id', coursIds).neq('statut', 'annule');
        for (final p in participants as List) {
          final cid = p['cours_id'] as String;
          counts[cid] = (counts[cid] ?? 0) + 1;
        }
      }
      if (mounted) setState(() { _coursCollectifs = cours; _participantsCount = counts; });
    } catch (_) {}
  }

  Future<void> _inscrireAuCours(Map<String, dynamic> cours) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _inscrivant) return;
    final animal = await AnimalPickerSheet.pickOne(
      context,
      uid: uid,
      profileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
      accentColor: widget.categoryColor,
    );
    if (animal == null || !mounted) return;
    setState(() => _inscrivant = true);
    try {
      final coursId = cours['id'] as String;
      final current = await _supa.from('cours_collectifs_participants')
          .select('id').eq('cours_id', coursId).neq('statut', 'annule');
      final capacite = cours['capacite_max'] as int? ?? 0;
      if ((current as List).length >= capacite) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ce cours est complet.', style: TextStyle(fontFamily: 'Galey')),
            backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
      final tarifs = _proData?['tarifs_education'];
      final prix = tarifs is Map ? (tarifs['cours_collectif'] as num?) : null;
      await _supa.from('cours_collectifs_participants').insert({
        'cours_id': coursId,
        'client_uid': uid,
        if (User_Info.activeProfileId.isNotEmpty) 'client_profile_id': User_Info.activeProfileId,
        'animal_id': animal['id']?.toString(),
        if (prix != null) 'prix': prix,
      });
      final clientName = FirebaseAuth.instance.currentUser?.displayName?.isNotEmpty == true
          ? FirebaseAuth.instance.currentUser!.displayName!
          : 'Un client';
      final proUid = _proData?['uid']?.toString();
      if (proUid != null) {
        final dateStr = DateFormat('dd/MM à HH:mm').format(DateTime.tryParse(cours['date_heure']?.toString() ?? '') ?? DateTime.now());
        await _supa.from('notifications').insert({
          'uid': proUid,
          'type': 'cours_collectif_inscription',
          'title': 'Nouvelle inscription — ${cours['titre']}',
          'body': '$clientName a inscrit ${animal['nom'] ?? 'son animal'} au cours du $dateStr.',
          'data': <String, dynamic>{'coursId': coursId},
          'read': false,
        });
      }
      await _loadCoursCollectifs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Inscription confirmée !', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57), behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _inscrivant = false);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String get _nomStructure =>
      _proData?['name_elevage'] ?? _proData?['firstname'] ?? 'Professionnel';

  String get _profession =>
      _proData?['profession_pro'] ?? widget.categoryLabel;

  String get _description =>
      _proData?['desc_entreprise'] ?? 'Aucune description disponible.';

  String get _ville => _proData?['ville_elevage'] ?? _proData?['ville'] ?? '';

  bool get _acceptNewClients {
    final raw = _proData?['accept_new_clients'];
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() != 'false' && raw != '0';
    return true;
  }

  List<String> get _especes {
    final raw = _proData?['especes_acceptees'];
    if (raw is List) return List<String>.from(raw);
    return [];
  }

  Map<String, String> get _horaires {
    final raw = _proData?['horaires'];
    if (raw is Map) {
      return Map<String, String>.from(
        raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
      );
    }
    return {};
  }

  List<Map<String, dynamic>> get _certifications {
    final raw = _proData?['certifications'];
    if (raw is List) {
      return List<Map<String, dynamic>>.from(
        raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
    }
    return [];
  }

  String get _tarifs => _proData?['tarifs'] ?? '';
  String get _siteWeb => _proData?['site_web'] ?? '';
  String get _instagram => _proData?['instagram'] ?? '';
  String get _facebook => _proData?['facebook'] ?? '';
  String get _photoUrl  => _proData?['profile_picture_url_elevage'] ?? _proData?['profile_picture_url'] ?? '';
  String get _bannerUrl => _proData?['banner_url'] ?? '';
  int get _rayon {
    final raw = _proData?['rayon_intervention'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<void> _openChat() async {
    setState(() => _loadingChat = true);
    try {
      final convId = await MessagingHelper.openOrCreateConversation(
        otherUid: widget.proUid,
        categorie: 'service-professionnel',
        myProfileId: widget.profileTableId,
      );
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatScreen(conversationId: convId, eleveurId: widget.proUid),
        ));
      }
    } finally {
      if (mounted) setState(() => _loadingChat = false);
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)))
          : _proData == null
              ? _emptyState()
              : NestedScrollView(
                  headerSliverBuilder: (ctx, _) => [
                    // Simple barre de navigation (pas d'expanded)
                    SliverAppBar(
                      pinned: true,
                      backgroundColor: const Color(0xFF0C5C6C),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      title: Text(widget.categoryLabel,
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    // Bannière + bulle photo (même pattern que l'éleveur)
                    SliverToBoxAdapter(child: _buildBannerSection()),
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildTabBar()),
                  ],
                  body: TabBarView(
                    controller: _tabController,
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 100),
                        child: _buildPresentation(),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 100),
                        child: _buildHoraires(),
                      ),
                    ],
                  ),
                ),
      bottomNavigationBar: _proData == null ? null : _buildBottomBar(),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.person_search_outlined, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('Profil introuvable', style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
      ]),
    );
  }

  // Bannière 200px + bulle photo 88px chevauchante — identique au profil éleveur
  Widget _buildBannerSection() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(children: [
          // Bannière
          SizedBox(
            height: 200,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              _bannerUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: _bannerUrl, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _gradientBg())
                  : (_photoUrl.isNotEmpty
                      ? CachedNetworkImage(imageUrl: _photoUrl, fit: BoxFit.cover,
                          color: Colors.black26, colorBlendMode: BlendMode.darken,
                          errorWidget: (_, __, ___) => _gradientBg())
                      : _gradientBg()),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black45],
                  ),
                ),
              ),
            ]),
          ),
          // Espace blanc pour accueillir la moitié basse de la bulle
          Container(color: Colors.white, height: 52),
        ]),
        // Bulle photo chevauchant bannière / section blanche
        Positioned(
          top: 156, // 200 - 88/2
          left: 16,
          child: Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)],
            ),
            child: ClipOval(
              child: _photoUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: _photoUrl, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _photoBubblePlaceholder())
                  : _photoBubblePlaceholder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _gradientBg() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [widget.categoryColor.withValues(alpha: 0.8), const Color(0xFF1E2025)],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Nom + badge alignés à droite de la bulle (88px + 8px gap)
        Row(children: [
          const SizedBox(width: 96),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nomStructure,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1E2025))),
              const SizedBox(height: 2),
              Text(_profession,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: widget.categoryColor, fontWeight: FontWeight.w600)),
            ]),
          ),
          _statusBadge(),
        ]),
        if (_ville.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 15, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(_ville, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
            if (_rayon > 0) ...[
              Text(' · ', style: TextStyle(color: Colors.grey.shade400)),
              Text('$_rayon km', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
            ],
          ]),
        ],
        if (_especes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: _especes.map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.categoryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(e, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: widget.categoryColor, fontWeight: FontWeight.w600)),
            )).toList(),
          ),
        ],
        if (_siteWeb.isNotEmpty || _instagram.isNotEmpty || _facebook.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            if (_siteWeb.isNotEmpty)
              _socialBtn(Icons.language_outlined, 'Site web', () => _launch(_siteWeb)),
            if (_instagram.isNotEmpty)
              _socialBtn(Icons.camera_alt_outlined, 'Instagram', () => _launch('https://instagram.com/${_instagram.replaceAll('@', '')}')),
            if (_facebook.isNotEmpty)
              _socialBtn(Icons.facebook_outlined, 'Facebook', () => _launch(_facebook)),
          ]),
        ],
      ]),
    );
  }

  Widget _photoBubblePlaceholder() {
    return Container(
      color: widget.categoryColor.withValues(alpha: 0.15),
      child: Icon(Icons.store_outlined, size: 36, color: widget.categoryColor),
    );
  }

  Widget _statusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _acceptNewClients ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _acceptNewClients ? '✓ Disponible' : 'Complet',
        style: TextStyle(
          fontFamily: 'Galey',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _acceptNewClients ? const Color(0xFF388E3C) : const Color(0xFFF57C00),
        ),
      ),
    );
  }

  Widget _socialBtn(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1E2025),
          side: const BorderSide(color: Color(0xFFDDDDDD)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: widget.categoryColor,
        unselectedLabelColor: Colors.grey,
        indicatorColor: widget.categoryColor,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
        tabs: const [
          Tab(text: 'Présentation'),
          Tab(text: 'Horaires'),
        ],
      ),
    );
  }

  Widget _buildPresentation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          _card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('À propos'),
              const SizedBox(height: 8),
              Text(_description, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5, color: Color(0xFF444444))),
            ],
          )),

          // Tarifs
          if (_tarifs.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Tarifs'),
                const SizedBox(height: 8),
                Text(_tarifs, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5, color: Color(0xFF444444))),
              ],
            )),
          ],

          // Cours collectifs disponibles (éducateur/comportementaliste)
          if (_proData?['cat_pro'] == 'education' && _coursCollectifs.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Cours collectifs disponibles'),
                const SizedBox(height: 10),
                ..._coursCollectifs.map((c) {
                  final d = DateTime.tryParse(c['date_heure']?.toString() ?? '');
                  final inscrits = _participantsCount[c['id']] ?? 0;
                  final capacite = c['capacite_max'] as int? ?? 0;
                  final complet = inscrits >= capacite;
                  final tarifs = _proData?['tarifs_education'];
                  final prixCours = tarifs is Map ? (tarifs['cours_collectif'] as num?) : null;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF7B5EA7).withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['titre']?.toString() ?? 'Cours collectif',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                        if (d != null)
                          Text(DateFormat('EEEE d MMMM à HH:mm', 'fr_FR').format(d),
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                        Text(complet ? 'Complet' : '$inscrits / $capacite places',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                color: complet ? Colors.orange.shade700 : Colors.grey.shade500)),
                        if (prixCours != null && prixCours > 0)
                          Text('${prixCours.toStringAsFixed(0)} €',
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7B5EA7))),
                      ])),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: (complet || _inscrivant) ? null : () => _inscrireAuCours(c),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B5EA7),
                          disabledBackgroundColor: Colors.grey.shade300,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Text(complet ? 'Complet' : 'S\'inscrire',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
                      ),
                    ]),
                  );
                }),
              ],
            )),
          ],

          // Certifications
          if (_certifications.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Certifications'),
                const SizedBox(height: 8),
                ..._certifications.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Icon(Icons.verified_outlined, size: 18, color: widget.categoryColor),
                    const SizedBox(width: 8),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                        if ((c['numero']?.toString() ?? '').isNotEmpty)
                          Text('N° ${c['numero']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                      ],
                    )),
                  ]),
                )),
              ],
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildHoraires() {
    const jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Horaires d\'ouverture'),
          const SizedBox(height: 12),
          if (_horaires.isEmpty)
            Text('Non renseignés', style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500))
          else
            ...jours.map((j) {
              final h = _horaires[j] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(width: 90, child: Text(j, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13))),
                  Text(h.isNotEmpty ? h : 'Fermé',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        color: h.isNotEmpty ? const Color(0xFF444444) : Colors.grey.shade400)),
                ]),
              );
            }),
        ],
      )),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -3))],
      ),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _loadingChat ? null : _openChat,
            icon: _loadingChat
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.message_outlined, size: 18),
            label: const Text('Contacter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1E2025),
              side: const BorderSide(color: Color(0xFFDDDDDD)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _acceptNewClients
                ? () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => RdvBookingPage(
                      proUid: widget.proUid,
                      proName: _nomStructure,
                      categoryColor: widget.categoryColor,
                      isPension: _proData?['cat_pro'] == 'pension',
                      isVet: _proData?['cat_pro'] == 'sante' || _proData?['cat_pro'] == 'veterinaire',
                      proProfileId: widget.profileTableId,
                    )))
                : null,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(
              _acceptNewClients ? 'Prendre RDV' : 'Complet',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.categoryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String t) {
    return Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E2025)));
  }
}
