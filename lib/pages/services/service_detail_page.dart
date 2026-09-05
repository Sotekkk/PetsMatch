import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/pages/pro/rdv_booking_page.dart';
import 'package:PetsMatch/pages/pro/education_reservation_page.dart';
import 'package:PetsMatch/widgets/animal_picker_sheet.dart';
import 'package:PetsMatch/widgets/avis_pro_widget.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart' show kPensionEspeces;
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
  Map<String, Map<String, dynamic>> _monInscription = {}; // cours_id -> {id, statut}
  bool _inscrivant = false;
  List<Map<String, dynamic>> _prestations = [];
  List<Map<String, dynamic>> _forfaitsPublics = []; // éducateur : forfaits affiche_public

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
        final raw = await _supa
            .from('user_profiles')
            .select()
            .eq('uid', widget.proUid)
            .eq('is_main', true)
            .maybeSingle();
        if (raw != null) {
          row = {
            ...raw,
            'uid':                       raw['uid'],
            'name_elevage':              raw['nom'] ?? raw['firstname'] ?? '',
            'profile_picture_url_elevage': raw['profile_picture_url_pro'] ?? '',
            'profile_picture_url':       raw['avatar_url'] ?? '',
            'banner_url':                raw['banner_url'] ?? '',
            'ville_elevage':             raw['ville_pro'] ?? raw['ville'] ?? '',
            'ville':                     raw['ville'] ?? '',
            'desc_entreprise':           raw['desc_entreprise'] ?? '',
            'especes_acceptees':         raw['especes_acceptees'] ?? [],
            'accept_new_clients':        raw['accept_new_clients'] ?? true,
            'horaires':                  raw['horaires'] ?? {},
            'certifications':            raw['certifications'] ?? [],
            'tarifs':                    raw['tarifs'] ?? '',
            'site_web':                  raw['site_web'] ?? '',
            'instagram':                 raw['instagram'] ?? '',
            'facebook':                  raw['facebook'] ?? '',
            'rayon_intervention':        raw['rayon_intervention'] ?? 0,
            'cat_pro':                   raw['cat_pro'] ?? '',
            'profession_pro':            raw['profession_pro'] ?? '',
            'lat':                       raw['latitude'] ?? raw['lat'],
            'lng':                       raw['longitude'] ?? raw['lng'],
          };
        }
      }
      if (mounted) setState(() { _proData = row; _loading = false; });
      if (row?['cat_pro'] == 'education') {
        await _loadCoursCollectifs();
        if (row?['tarifs_education_visibles'] == true) await _loadForfaitsPublics();
      }
      if (row?['cat_pro'] == 'photographe' || row?['cat_pro'] == 'toilettage') await _loadPrestations();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadForfaitsPublics() async {
    final proUid = _proData?['uid']?.toString();
    if (proUid == null) return;
    try {
      final rows = await _supa.from('forfaits_education').select()
          .eq('pro_uid', proUid).eq('actif', true).eq('affiche_public', true)
          .order('created_at');
      if (mounted) setState(() => _forfaitsPublics = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {}
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
      final mine = <String, Map<String, dynamic>>{};
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (coursIds.isNotEmpty) {
        final participants = await _supa.from('cours_collectifs_participants')
            .select('cours_id, id, statut, client_uid').inFilter('cours_id', coursIds).neq('statut', 'annule');
        for (final p in participants as List) {
          final cid = p['cours_id'] as String;
          counts[cid] = (counts[cid] ?? 0) + 1;
          if (uid != null && p['client_uid'] == uid) mine[cid] = p;
        }
      }
      if (mounted) setState(() { _coursCollectifs = cours; _participantsCount = counts; _monInscription = mine; });
    } catch (_) {}
  }

  /// Promeut le plus ancien inscrit en liste d'attente d'un cours quand une
  /// place se libère (annulation/désinscription) — reconduit le principe déjà
  /// utilisé pour la génération de série côté Cloud Function.
  Future<void> _promouvoirListeAttente(String coursId) async {
    try {
      final attente = await _supa.from('cours_collectifs_participants')
          .select().eq('cours_id', coursId).eq('statut', 'en_attente')
          .order('created_at').limit(1);
      final row = attente.isNotEmpty ? attente.first : null;
      if (row == null) return;
      await _supa.from('cours_collectifs_participants').update({'statut': 'inscrit'}).eq('id', row['id']);
      final cours = await _supa.from('cours_collectifs').select('titre, date_heure, pro_profile_id')
          .eq('id', coursId).maybeSingle();
      if (cours != null) {
        final dateStr = DateFormat('dd/MM à HH:mm').format(DateTime.tryParse(cours['date_heure']?.toString() ?? '') ?? DateTime.now());
        await _supa.from('notifications').insert({
          'uid': row['client_uid'],
          'type': 'cours_collectif_place_liberee',
          'title': 'Une place s\'est libérée !',
          'body': 'Vous êtes maintenant inscrit au cours "${cours['titre']}" du $dateStr.',
          if (row['client_profile_id'] != null) 'profile_id': row['client_profile_id'],
          'data': <String, dynamic>{'coursId': coursId},
          'read': false,
        });
      }
    } catch (_) {}
  }

  Future<void> _seDesinscrire(Map<String, dynamic> cours) async {
    final coursId = cours['id'] as String;
    final participation = _monInscription[coursId];
    if (participation == null || _inscrivant) return;
    setState(() => _inscrivant = true);
    try {
      // Libère une place (à promouvoir depuis la liste d'attente) si on
      // occupait réellement une place — 'inscrit' (confirmé) ou 'demande'
      // (en attente de confirmation, compte quand même dans la capacité).
      final occupaitUnePlace = participation['statut'] == 'inscrit' || participation['statut'] == 'demande';
      await _supa.from('cours_collectifs_participants').update({'statut': 'annule'}).eq('id', participation['id']);
      if (occupaitUnePlace) await _promouvoirListeAttente(coursId);
      await _loadCoursCollectifs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Désinscription confirmée.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.black87, behavior: SnackBarBehavior.floating,
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

  Future<void> _loadPrestations() async {
    final table = _proData?['cat_pro'] == 'toilettage' ? 'prestations_toilettage' : 'prestations_photographe';
    final proUid = _proData?['uid']?.toString();
    if (proUid == null) return;
    try {
      var query = _supa.from(table).select().eq('pro_uid', proUid).eq('actif', true);
      if (widget.profileTableId != null) query = query.eq('pro_profile_id', widget.profileTableId!);
      final rows = await query.order('created_at');
      if (mounted) setState(() => _prestations = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {}
  }

  String _prestationPrixLabel(Map<String, dynamic> p) {
    if (_proData?['cat_pro'] != 'toilettage') {
      return '${((p['prix'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} €';
    }
    final grille = (p['grille_prix'] as List?) ?? [];
    if (grille.isEmpty) {
      return 'à partir de ${((p['prix_base'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} €';
    }
    final prix = grille.map((t) => ((t as Map)['prix'] as num?)?.toDouble() ?? 0).toList();
    final min = prix.reduce((a, b) => a < b ? a : b);
    final max = prix.reduce((a, b) => a > b ? a : b);
    return min == max ? '${min.toStringAsFixed(0)} €' : '${min.toStringAsFixed(0)}-${max.toStringAsFixed(0)} €';
  }

  Future<void> _inscrireAuCours(Map<String, dynamic> cours) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _inscrivant) return;

    // Cours récurrent : proposer de s'inscrire à cette séance seule ou à
    // toutes les séances à venir de la série.
    var touteLaSerie = false;
    final serieId = cours['serie_id']?.toString();
    if (serieId != null && mounted) {
      final choix = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ce cours est récurrent', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text('Vous pouvez vous inscrire à cette séance seule, ou à toutes les prochaines séances de la série.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cette séance seulement', style: TextStyle(fontFamily: 'Galey')),
              )),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B5EA7)),
                child: const Text('Toute la série', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
              )),
            ]),
          ),
        ),
      );
      if (choix == null || !mounted) return;
      touteLaSerie = choix;
    }

    final animal = await AnimalPickerSheet.pickOne(
      context,
      uid: uid,
      profileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
      accentColor: widget.categoryColor,
    );
    if (animal == null || !mounted) return;
    setState(() => _inscrivant = true);
    try {
      final tarifs = _proData?['tarifs_education'];
      final prix = tarifs is Map ? (tarifs['cours_collectif'] as num?) : null;
      final clientProfileId = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;
      final animalId = animal['id']?.toString();

      // Cible : cette occurrence seule, ou toutes les occurrences à venir déjà
      // générées de la série (les vagues futures sont prises en charge par
      // generateCoursCollectifsOccurrences côté Cloud Function).
      List<Map<String, dynamic>> occurrences;
      if (touteLaSerie && serieId != null) {
        final rows = await _supa.from('cours_collectifs').select('id, capacite_max, titre, date_heure, pro_profile_id')
            .eq('serie_id', serieId).eq('statut', 'planifie')
            .gte('date_heure', DateTime.now().toIso8601String()).order('date_heure');
        occurrences = List<Map<String, dynamic>>.from(rows as List);
      } else {
        occurrences = [cours];
      }

      var uneEnAttente = false;
      for (final occ in occurrences) {
        final occId = occ['id'] as String;
        final current = await _supa.from('cours_collectifs_participants')
            .select('id').eq('cours_id', occId).neq('statut', 'annule');
        final capacite = occ['capacite_max'] as int? ?? cours['capacite_max'] as int? ?? 0;
        final complet = (current as List).length >= capacite;
        if (complet) uneEnAttente = true;
        await _supa.from('cours_collectifs_participants').insert({
          'cours_id': occId,
          'client_uid': uid,
          if (clientProfileId != null) 'client_profile_id': clientProfileId,
          'animal_id': animalId,
          if (touteLaSerie && serieId != null) 'serie_id': serieId,
          if (prix != null) 'prix': prix,
          'statut': complet ? 'en_attente' : 'demande',
        });
      }

      final clientName = FirebaseAuth.instance.currentUser?.displayName?.isNotEmpty == true
          ? FirebaseAuth.instance.currentUser!.displayName!
          : 'Un client';
      final proUid = _proData?['uid']?.toString();
      if (proUid != null) {
        final dateStr = DateFormat('dd/MM à HH:mm').format(DateTime.tryParse(cours['date_heure']?.toString() ?? '') ?? DateTime.now());
        await _supa.from('notifications').insert({
          'uid': proUid,
          'type': 'cours_collectif_inscription',
          'title': 'Demande d\'inscription — ${cours['titre']}',
          'body': touteLaSerie
              ? '$clientName souhaite inscrire ${animal['nom'] ?? 'son animal'} à toute la série "${cours['titre']}" — en attente de votre confirmation.'
              : '$clientName souhaite inscrire ${animal['nom'] ?? 'son animal'} au cours du $dateStr — en attente de votre confirmation.',
          if (cours['pro_profile_id'] != null) 'profile_id': cours['pro_profile_id'],
          'data': <String, dynamic>{'coursId': cours['id']},
          'read': false,
        });
      }
      await _loadCoursCollectifs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(uneEnAttente ? 'Demande envoyée — en liste d\'attente pour une ou plusieurs séances complètes.' : 'Demande envoyée — en attente de confirmation du professionnel.',
              style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: uneEnAttente ? Colors.orange : const Color(0xFF6E9E57), behavior: SnackBarBehavior.floating,
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

  /// photos_galerie : liste de String (URL) OU {url, legende}.
  List<({String url, String legende})> get _photosGalerie {
    final raw = _proData?['photos_galerie'];
    if (raw is! List) return [];
    return raw.map<({String url, String legende})?>((e) {
      if (e is String) return (url: e, legende: '');
      if (e is Map) {
        final u = e['url']?.toString() ?? '';
        return u.isEmpty ? null : (url: u, legende: e['legende']?.toString() ?? '');
      }
      return null;
    }).whereType<({String url, String legende})>().toList();
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

  /// Tarifs pension par espèce, uniquement si la pension a activé l'affichage
  /// public. Retourne (label, prix formaté).
  List<(String, String)> get _pensionTarifsPublics {
    if (_proData?['cat_pro'] != 'pension') return [];
    final tp = _proData?['tarifs_pension'];
    if (tp is! Map || tp['afficher_public'] != true) return [];
    final especes = tp['especes'];
    if (especes is! List) return [];
    final out = <(String, String)>[];
    for (final sp in kPensionEspeces) {
      Map? match;
      for (final e in especes) {
        if (e is Map && e['espece'] == sp['key']) { match = e; break; }
      }
      if (match == null) continue;
      final seul = (match['prix_seul'] as num?)?.toDouble() ?? 0;
      if (seul <= 0) continue;
      final partage = (match['prix_partage'] as num?)?.toDouble();
      final prix = (partage != null && partage > 0 && partage != seul)
          ? '${seul.toStringAsFixed(0)} € · ${partage.toStringAsFixed(0)} € partagé'
          : '${seul.toStringAsFixed(0)} €';
      out.add((sp['label']!, prix));
    }
    return out;
  }
  /// Éducateur : tarifs à afficher publiquement (label, prix formaté), si le pro
  /// a activé `tarifs_education_visibles`. Prestations fixes non nulles +
  /// prestations libres.
  List<(String, String)> get _tarifsEducationPublics {
    if (_proData?['cat_pro'] != 'education' || _proData?['tarifs_education_visibles'] != true) {
      return [];
    }
    const labels = {
      'cours_individuel': 'Cours individuel',
      'cours_collectif': 'Cours collectif (par participant)',
      'evaluation': 'Évaluation comportementale',
      'domicile_supplement': 'Supplément à domicile',
    };
    final out = <(String, String)>[];
    final fixes = _proData?['tarifs_education'];
    if (fixes is Map) {
      for (final entry in labels.entries) {
        final v = (fixes[entry.key] as num?)?.toDouble() ?? 0;
        if (v > 0) out.add((entry.value, '${v.toStringAsFixed(0)} €'));
      }
    }
    final extra = _proData?['tarifs_education_extra'];
    if (extra is List) {
      for (final e in extra) {
        if (e is! Map) continue;
        final label = e['label']?.toString().trim() ?? '';
        if (label.isEmpty) continue;
        final v = (e['prix'] as num?)?.toDouble() ?? 0;
        final desc = e['description']?.toString().trim() ?? '';
        out.add((desc.isEmpty ? label : '$label — $desc', v > 0 ? '${v.toStringAsFixed(0)} €' : '—'));
      }
    }
    return out;
  }

  String get _educationBilanDescription =>
      (_proData?['education_bilan_description'] ?? '').toString().trim();

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

  String get _telephone =>
      (_proData?['phone_number'] ?? _proData?['numero_elevage'] ?? _proData?['phone'] ?? '')
          .toString()
          .trim();

  /// Téléphone au format international sans « + » pour wa.me (France par défaut).
  String _waPhone(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('0')) d = '33${d.substring(1)}';
    return d;
  }

  Future<void> _openExt(Uri uri) async {
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
        if (_telephone.isNotEmpty || _siteWeb.isNotEmpty || _instagram.isNotEmpty || _facebook.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_telephone.isNotEmpty)
              _socialBtn(Icons.call_outlined, 'Appeler',
                  () => _openExt(Uri(scheme: 'tel', path: _telephone.replaceAll(RegExp(r'[^0-9+]'), ''))),
                  color: const Color(0xFF6E9E57)),
            if (_telephone.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _openExt(Uri.parse('https://wa.me/${_waPhone(_telephone)}')),
                icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 13),
                label: const Text('WhatsApp', style: TextStyle(fontFamily: 'Galey', fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  side: const BorderSide(color: Color(0xFF25D366)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
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

  Widget _socialBtn(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color ?? const Color(0xFF1E2025),
        side: BorderSide(color: color ?? const Color(0xFFDDDDDD)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

          // Galerie / portfolio (photographe et tout autre pro l'ayant renseignée)
          if (_photosGalerie.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Galerie'),
                const SizedBox(height: 10),
                _GalerieCarrousel(photos: _photosGalerie),
              ],
            )),
          ],

          // Prestations (photographe / toilettage)
          if (_prestations.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Prestations'),
                const SizedBox(height: 10),
                ..._prestations.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                      if ((p['description'] as String?)?.isNotEmpty == true)
                        Text(p['description'].toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                      Text('${p['duree_minutes'] ?? 0} min', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
                    ])),
                    const SizedBox(width: 8),
                    Text(_prestationPrixLabel(p), style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: widget.categoryColor)),
                  ]),
                )),
              ],
            )),
          ],

          // Tarifs de course (taxi animalier)
          if (_proData?['cat_pro'] == 'taxi_animalier' && _proData?['tarifs_taxi'] is Map && (_proData!['tarifs_taxi'] as Map).isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(child: Builder(builder: (_) {
              final t = _proData!['tarifs_taxi'] as Map;
              final priseEnCharge = (t['prise_en_charge'] as num?)?.toDouble() ?? 0;
              final prixKm = (t['prix_km'] as num?)?.toDouble() ?? 0;
              final minimum = (t['minimum'] as num?)?.toDouble() ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Tarifs de course'),
                  const SizedBox(height: 8),
                  Text('${priseEnCharge.toStringAsFixed(2)} € de prise en charge + ${prixKm.toStringAsFixed(2)} €/km'
                      '${minimum > 0 ? ' (minimum ${minimum.toStringAsFixed(2)} €)' : ''}',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5, color: Color(0xFF444444))),
                ],
              );
            })),
          ],

          // Tarifs pension par espèce (si la pension a choisi de les afficher)
          if (_pensionTarifsPublics.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Tarifs — prix par nuit'),
                const SizedBox(height: 8),
                ..._pensionTarifsPublics.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(child: Text(t.$1,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                            fontWeight: FontWeight.w600, color: Color(0xFF1E2025)))),
                    Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                        fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
                  ]),
                )),
              ],
            )),
          ],

          // Tarifs éducateur (grille + forfaits publics), si le pro les expose
          if (_tarifsEducationPublics.isNotEmpty || _forfaitsPublics.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Tarifs'),
                const SizedBox(height: 8),
                ..._tarifsEducationPublics.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(t.$1,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                            fontWeight: FontWeight.w600, color: Color(0xFF1E2025)))),
                    const SizedBox(width: 8),
                    Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                        fontWeight: FontWeight.w700, color: Color(0xFF7B5EA7))),
                  ]),
                )),
                if (_forfaitsPublics.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Forfaits', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  ..._forfaitsPublics.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(child: Text(
                          '${f['nom']} · ${f['nb_seances']} séances',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                              fontWeight: FontWeight.w600, color: Color(0xFF1E2025)))),
                      Text('${(f['prix'] as num?)?.toStringAsFixed(0) ?? 0} €',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                              fontWeight: FontWeight.w700, color: Color(0xFF7B5EA7))),
                    ]),
                  )),
                ],
              ],
            )),
          ],

          // Bilan préalable (éducateur)
          if (_proData?['cat_pro'] == 'education' && _educationBilanDescription.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Le bilan préalable'),
                const SizedBox(height: 8),
                Text(_educationBilanDescription,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5, color: Color(0xFF444444))),
              ],
            )),
          ],

          // Tarifs (texte libre — sauf éducateur, qui a une grille structurée)
          if (_tarifs.isNotEmpty && _proData?['cat_pro'] != 'education') ...[
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

          // Avis — système générique avis_pro (tous les pros de service).
          if (const {
            'taxi_animalier', 'education', 'sante', 'garde',
            'toilettage', 'photographe', 'marechal_ferrant', 'veterinaire',
          }.contains(_proData?['cat_pro'])) ...[
            const SizedBox(height: 12),
            _card(child: AvisProSection(proUid: widget.proUid, proProfileId: widget.profileTableId)),
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
                  final recurrent = c['serie_id'] != null;
                  final moi = _monInscription[c['id']];
                  final statutMoi = moi?['statut'] as String?;
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
                        Row(children: [
                          if (recurrent) const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.repeat, size: 13, color: Color(0xFF7B5EA7)),
                          ),
                          Flexible(child: Text(c['titre']?.toString() ?? 'Cours collectif', overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13))),
                        ]),
                        if (d != null)
                          Text(DateFormat('EEEE d MMMM à HH:mm', 'fr_FR').format(d),
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                        Text(
                          statutMoi == 'inscrit' ? 'Vous êtes inscrit·e ✓'
                              : statutMoi == 'demande' ? 'En attente de confirmation du pro'
                              : statutMoi == 'en_attente' ? 'Vous êtes en liste d\'attente'
                              : complet ? 'Complet — $inscrits / $capacite places'
                              : '$inscrits / $capacite places',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: statutMoi != null ? FontWeight.w700 : FontWeight.normal,
                              color: statutMoi == 'inscrit' ? const Color(0xFF6E9E57)
                                  : (complet || statutMoi == 'en_attente' || statutMoi == 'demande') ? Colors.orange.shade700 : Colors.grey.shade500),
                        ),
                        if (prixCours != null && prixCours > 0)
                          Text('${prixCours.toStringAsFixed(0)} €',
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7B5EA7))),
                      ])),
                      const SizedBox(width: 8),
                      if (statutMoi != null)
                        OutlinedButton(
                          onPressed: _inscrivant ? null : () => _seDesinscrire(c),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade400,
                            side: BorderSide(color: Colors.red.shade200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text('Se désinscrire', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12)),
                        )
                      else
                        ElevatedButton(
                          onPressed: _inscrivant ? null : () => _inscrireAuCours(c),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: complet ? Colors.orange.shade700 : const Color(0xFF7B5EA7),
                            disabledBackgroundColor: Colors.grey.shade300,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: Text(complet ? 'File d\'attente' : 'S\'inscrire',
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
                    builder: (_) => _proData?['cat_pro'] == 'education'
                        ? EducationReservationPage(
                            proUid: widget.proUid,
                            proName: _nomStructure,
                            categoryColor: widget.categoryColor,
                            proProfileId: widget.profileTableId,
                          )
                        : RdvBookingPage(
                      proUid: widget.proUid,
                      proName: _nomStructure,
                      categoryColor: widget.categoryColor,
                      isPension: _proData?['cat_pro'] == 'pension',
                      isVet: _proData?['cat_pro'] == 'sante' || _proData?['cat_pro'] == 'veterinaire',
                      isGarde: _proData?['cat_pro'] == 'garde',
                      isTaxi: _proData?['cat_pro'] == 'taxi_animalier',
                      isPhotographe: _proData?['cat_pro'] == 'photographe',
                      isToilettage: _proData?['cat_pro'] == 'toilettage',
                      proProfileId: widget.profileTableId,
                    )))
                : null,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(
              _acceptNewClients ? (_proData?['cat_pro'] == 'education' ? 'Réserver un cours' : 'Prendre RDV') : 'Complet',
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

// ── Galerie défilable + visionneuse plein écran ───────────────────────────────

class _GalerieCarrousel extends StatefulWidget {
  final List<({String url, String legende})> photos;
  const _GalerieCarrousel({required this.photos});

  @override
  State<_GalerieCarrousel> createState() => _GalerieCarrouselState();
}

class _GalerieCarrouselState extends State<_GalerieCarrousel> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _openViewer(int initial) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _GalerieViewer(photos: widget.photos, initial: initial),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Column(children: [
      SizedBox(
        height: 210,
        child: PageView.builder(
          controller: _ctrl,
          itemCount: photos.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _openViewer(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  CachedNetworkImage(imageUrl: photos[i].url, fit: BoxFit.cover),
                  if (photos[i].legende.isNotEmpty)
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black54],
                          ),
                        ),
                        child: Text(photos[i].legende,
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                                fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
      if (photos.length > 1) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (int i = 0; i < photos.length; i++)
            Container(
              width: i == _page ? 18 : 6, height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == _page ? const Color(0xFF0C5C6C) : const Color(0xFFCBD5D8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ]),
      ],
    ]);
  }
}

class _GalerieViewer extends StatefulWidget {
  final List<({String url, String legende})> photos;
  final int initial;
  const _GalerieViewer({required this.photos, required this.initial});

  @override
  State<_GalerieViewer> createState() => _GalerieViewerState();
}

class _GalerieViewerState extends State<_GalerieViewer> {
  late final PageController _ctrl = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: photos.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1, maxScale: 4,
              child: Center(child: CachedNetworkImage(imageUrl: photos[i].url, fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: 8, right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (photos[_page].legende.isNotEmpty)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                color: Colors.black54,
                child: Text(photos[_page].legende,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.white)),
              ),
            ),
        ]),
      ),
    );
  }
}
