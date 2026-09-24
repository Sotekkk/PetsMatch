import 'dart:async';
import 'dart:ui';

import 'package:PetsMatch/main.dart' show getApiKey, User_Info;
import 'package:PetsMatch/pages/promenades/promenade_detail_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:PetsMatch/services/promenade_notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _orange = Color(0xFFEF6C00);
const _darkC = Color(0xFF071C22);
const _bgGrad = LinearGradient(
  begin: Alignment.topCenter, end: Alignment.bottomCenter,
  colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
  stops: [0.0, 0.5, 1.0],
);

const _kNiveaux = ['facile', 'moyen', 'difficile'];
const _kEspeces = ['Toutes', 'Chiens', 'Chevaux'];

String _especeEmoji(String e) => switch (e) {
  'Chiens'  => '🐕 Chiens',
  'Chevaux' => '🐴 Chevaux',
  _         => '🌍 Toutes',
};

class PromenadePage extends StatefulWidget {
  const PromenadePage({super.key});

  @override
  State<PromenadePage> createState() => _PromenadesPageState();
}

class _PromenadesPageState extends State<PromenadePage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _promenades = [];
  Map<String, String> _mesParticipations = {}; // id → statut
  bool _loading = true;

  // Filtres
  String _activeTab = 'upcoming';
  final _searchCtrl = TextEditingController();
  String? _filterEspece;
  String? _filterNiveau;

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.toLowerCase().trim();
    return _promenades.where((p) {
      if (q.isNotEmpty) {
        final adresse = (p['lieu_rdv'] ?? '').toString().toLowerCase();
        final titre = (p['titre'] ?? '').toString().toLowerCase();
        if (!adresse.contains(q) && !titre.contains(q)) return false;
      }
      if (_activeTab == 'mes') return _mesParticipations.containsKey(p['id'].toString());
      if (_filterEspece != null) {
        final espece = (p['espece'] ?? '').toString();
        if (espece != _filterEspece && espece != 'Toutes' && espece != 'Toutes espèces') return false;
      }
      if (_filterNiveau != null && p['niveau']?.toString() != _filterNiveau) return false;
      return true;
    }).toList();
  }

  bool get _hasActiveFilters => _filterEspece != null || _filterNiveau != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String();
      final promData = await _supa
          .from('promenades')
          .select('*, promenades_participants(count)')
          .eq('statut', 'ouvert')
          .gte('date_heure', cutoff)
          .order('date_heure');

      Map<String, String> participations = {};
      if (_uid.isNotEmpty) {
        final partData = await _supa
            .from('promenades_participants')
            .select('promenade_id, statut')
            .eq('user_uid', _uid);
        participations = {
          for (final e in (partData as List))
            e['promenade_id'].toString(): (e['statut'] ?? 'accepte').toString()
        };
      }

      if (mounted) {
        setState(() {
          _promenades = List<Map<String, dynamic>>.from(promData);
          _mesParticipations = participations;
          _loading = false;
        });
      }
      // Programmer les rappels locaux pour les promenades acceptées à venir
      _scheduleAcceptedReminders(List<Map<String, dynamic>>.from(promData), participations);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleAcceptedReminders(
      List<Map<String, dynamic>> promenades,
      Map<String, String> participations,
  ) {
    for (final p in promenades) {
      final id = p['id'].toString();
      if (participations[id] != 'accepte') continue;
      final dateStr = p['date_heure']?.toString();
      if (dateStr == null) continue;
      try {
        final date = DateTime.parse(dateStr).toLocal();
        if (date.isBefore(DateTime.now())) continue;
        schedulePromenadeReminders(
          promenadeId: id,
          titre: p['titre']?.toString() ?? 'Promenade',
          dateHeure: date,
        );
      } catch (_) {}
    }
  }

  Future<void> _toggleParticipation(String id) async {
    if (_uid.isEmpty) return;
    final dejaDedans = _mesParticipations.containsKey(id);
    setState(() {
      if (dejaDedans) {
        _mesParticipations.remove(id);
      } else {
        _mesParticipations[id] = 'en_attente';
      }
    });
    try {
      if (dejaDedans) {
        await _supa
            .from('promenades_participants')
            .delete()
            .eq('promenade_id', id)
            .eq('user_uid', _uid);
      } else {
        final pid = User_Info.activeProfileId;
        await _supa.from('promenades_participants').insert({
          'promenade_id': id,
          'user_uid': _uid,
          if (pid != null) 'user_profile_id': pid,
          'statut': 'en_attente',
          'rejoint_at': DateTime.now().toIso8601String(),
        });
        // Notifier l'organisateur
        final promenade = _promenades.firstWhere(
            (p) => p['id'].toString() == id, orElse: () => {});
        final orgUid = promenade['organisateur_uid']?.toString() ?? '';
        final titre = promenade['titre']?.toString() ?? 'une promenade';
        if (orgUid.isNotEmpty && orgUid != _uid) {
          try {
            final me = await _supa
                .from('user_profiles')
                .select('firstname, lastname')
                .eq('uid', _uid)
                .eq('is_main', true)
                .maybeSingle();
            final nom = me != null
                ? '${me['firstname'] ?? ''} ${me['lastname'] ?? ''}'.trim()
                : 'Quelqu\'un';
            await _supa.from('notifications').insert({
              'uid': orgUid,
              'type': 'promenade_join',
              'title': 'Nouvelle demande de participation',
              'body': '$nom veut rejoindre "$titre"',
              if (promenade['organisateur_profile_id'] != null) 'profile_id': promenade['organisateur_profile_id'],
              'data': {'promenadeId': id, 'fromUid': _uid},
              'read': false,
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        }
      }
      _load();
    } catch (_) {
      setState(() {
        if (dejaDedans) {
          _mesParticipations[id] = 'accepte';
        } else {
          _mesParticipations.remove(id);
        }
      });
    }
  }

  Future<void> _openCreation() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreatePromenadesSheet(),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _darkC,
      body: Container(
        decoration: const BoxDecoration(gradient: _bgGrad),
        child: Stack(children: [
          // ── Contenu scrollable ──
          CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _heroSection()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _searchBar(),
                  const SizedBox(height: 12),
                  _filterTabs(),
                  const SizedBox(height: 20),
                  Row(children: [
                    const Expanded(
                      child: Text('Balades à proximité',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 16, color: Colors.white)),
                    ),
                    GestureDetector(
                      onTap: _openMapView,
                      child: const Row(children: [
                        Text('Voir la carte',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                color: Color(0xFF7ED69D), fontWeight: FontWeight.w600)),
                        SizedBox(width: 4),
                        Icon(Icons.location_on_rounded, color: Color(0xFF7ED69D), size: 16),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF7ED69D))))
            else if (_filtered.isEmpty)
              SliverFillRemaining(child: _empty())
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 90),
                sliver: SliverList.separated(
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = _filtered[i];
                    final id = p['id'].toString();
                    final myStatut = _mesParticipations[id];
                    return GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => PromenadeDetailPage(promenadeId: id))),
                      child: _PromenadesCard(
                        promenade: p,
                        estParticipant: myStatut != null,
                        myStatut: myStatut,
                        onToggle: _uid.isNotEmpty && myStatut == null
                            ? () => _toggleParticipation(id)
                            : null,
                      ),
                    );
                  },
                ),
              ),
          ]),
          // ── Bouton bas fixe ──
          if (_uid.isNotEmpty)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [_darkC.withValues(alpha: 0), _darkC],
                  ),
                ),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _openCreation,
                    icon: const Icon(Icons.add, size: 18, color: Color(0xFF071C22)),
                    label: const Text('Créer une balade',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 15, color: Color(0xFF071C22))),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7ED69D),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  void _openMapView() {
    final withCoords = _promenades
        .where((p) => p['lat'] != null && p['lng'] != null)
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PromenadMapPage(promenades: withCoords)),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        String? tmpEspece = _filterEspece;
        String? tmpNiveau = _filterNiveau;
        return StatefulBuilder(builder: (ctx, setLocal) {
          const especes = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Rongeur'];
          const niveaux = ['facile', 'moyen', 'difficile'];
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            decoration: const BoxDecoration(
              color: Color(0xFF0E2A30),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Filtres', style: TextStyle(fontFamily: 'Galey', fontSize: 18,
                    fontWeight: FontWeight.w800, color: Colors.white)),
                const Spacer(),
                if (tmpEspece != null || tmpNiveau != null)
                  GestureDetector(
                    onTap: () { setLocal(() { tmpEspece = null; tmpNiveau = null; }); },
                    child: const Text('Réinitialiser',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF7ED69D))),
                  ),
              ]),
              const SizedBox(height: 20),
              const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  fontWeight: FontWeight.w700, color: Colors.white70)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: especes.map((e) {
                final active = tmpEspece == e;
                return GestureDetector(
                  onTap: () => setLocal(() => tmpEspece = active ? null : e),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF7ED69D).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? const Color(0xFF7ED69D) : Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Text(e, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        color: active ? const Color(0xFF7ED69D) : Colors.white70,
                        fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 20),
              const Text('Niveau', style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  fontWeight: FontWeight.w700, color: Colors.white70)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: niveaux.map((n) {
                final active = tmpNiveau == n;
                final label = n[0].toUpperCase() + n.substring(1);
                return GestureDetector(
                  onTap: () => setLocal(() => tmpNiveau = active ? null : n),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF7ED69D).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? const Color(0xFF7ED69D) : Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        color: active ? const Color(0xFF7ED69D) : Colors.white70,
                        fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() { _filterEspece = tmpEspece; _filterNiveau = tmpNiveau; });
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7ED69D), elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Appliquer', style: TextStyle(fontFamily: 'Galey',
                      fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF071C22))),
                ),
              ),
            ]),
          );
        });
      },
    );
  }

  Widget _heroSection() {
    return Stack(children: [
      SizedBox(
        height: 210,
        width: double.infinity,
        child: Image.asset('assets/deco/communautybackground.jpg', fit: BoxFit.cover),
      ),
      Positioned(
        bottom: 0, left: 0, right: 0, height: 90,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, _darkC],
            ),
          ),
        ),
      ),
      Positioned(
        top: 0, left: 0, right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Balades & Rencontres',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800,
                          fontSize: 22, color: Colors.white)),
                  Text('Sortez, rencontrez et partagez des moments uniques !',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white70)),
                ]),
              ),
              GestureDetector(
                onTap: _showFilterSheet,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _hasActiveFilters
                            ? const Color(0xFF7ED69D).withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _hasActiveFilters
                              ? const Color(0xFF7ED69D).withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(Icons.tune_rounded,
                          color: _hasActiveFilters ? const Color(0xFF7ED69D) : Colors.white,
                          size: 18),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _searchBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Rechercher une balade, une ville…',
              hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
              prefixIcon: Icon(Icons.search, size: 18, color: Colors.white.withValues(alpha: 0.6)),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                      onPressed: () => setState(() => _searchCtrl.clear()))
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterTabs() {
    const tabs = [('upcoming', 'Autour de moi'), ('avenir', 'À venir'), ('mes', 'Mes balades')];
    return Row(children: tabs.map((tab) {
      final active = _activeTab == tab.$1;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _activeTab = tab.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF7ED69D) : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: active ? null : Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: Text(tab.$2,
                style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                    color: active ? const Color(0xFF071C22) : Colors.white)),
          ),
        ),
      );
    }).toList());
  }

  Widget _empty() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.directions_walk_outlined, size: 72, color: Color(0xFFCCCCCC)),
          SizedBox(height: 16),
          Text('Aucune promenade à venir',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFFAAAAAA))),
          SizedBox(height: 8),
          Text('Organisez la première !',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ]),
      );
}

// ─── Map View ─────────────────────────────────────────────────────────────────

class _PromenadMapPage extends StatelessWidget {
  final List<Map<String, dynamic>> promenades;
  const _PromenadMapPage({required this.promenades});

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{};
    for (final p in promenades) {
      final lat = (p['lat'] as num?)?.toDouble();
      final lng = (p['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      markers.add(Marker(
        markerId: MarkerId(p['id'].toString()),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: p['titre']?.toString() ?? 'Promenade',
          snippet: p['lieu_rdv']?.toString(),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => PromenadeDetailPage(promenadeId: p['id'].toString())));
          },
        ),
      ));
    }

    LatLng center = const LatLng(46.603354, 1.888334);
    double zoom = 5.5;
    if (promenades.isNotEmpty) {
      final first = promenades.first;
      final lat = (first['lat'] as num?)?.toDouble();
      final lng = (first['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        center = LatLng(lat, lng);
        zoom = 10;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF071C22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF071C22),
        foregroundColor: Colors.white,
        title: const Text('Balades sur la carte',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: promenades.isEmpty
          ? const Center(
              child: Text('Aucune balade avec position GPS',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.white70)))
          : GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: zoom),
              markers: markers,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
            ),
    );
  }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

class _PromenadesCard extends StatelessWidget {
  final Map<String, dynamic> promenade;
  final bool estParticipant;
  final String? myStatut;
  final VoidCallback? onToggle;

  const _PromenadesCard(
      {required this.promenade, required this.estParticipant, this.myStatut, this.onToggle});

  static Future<void> _openNavigation(double lat, double lng) async {
    final latStr = lat.toStringAsFixed(6);
    final lngStr = lng.toStringAsFixed(6);
    final wazeUrl = Uri.parse('waze://?ll=$latStr,$lngStr&navigate=yes');
    final mapsUrl = Uri.parse('https://maps.google.com/?daddr=$latStr,$lngStr');
    if (await canLaunchUrl(wazeUrl)) {
      await launchUrl(wazeUrl, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(mapsUrl, mode: LaunchMode.externalApplication);
    }
  }

  static String _fmtDateRelative(String iso) {
    try {
      final date = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dateDay = DateTime(date.year, date.month, date.day);
      final diff = dateDay.difference(today).inDays;
      final prefix = diff == 0 ? "Aujourd'hui" : diff == 1 ? 'Demain'
          : DateFormat('EEE d MMM', 'fr_FR').format(date);
      return '$prefix • ${DateFormat('HH:mm').format(date)}';
    } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    final titre = promenade['titre']?.toString() ?? 'Promenade';
    final lieu = promenade['lieu_rdv']?.toString() ?? '';
    final dateHeure = promenade['date_heure']?.toString() ?? '';
    final espece = promenade['espece']?.toString() ?? '';
    final participantsMax = (promenade['participants_max'] as num?)?.toInt();
    final lat = (promenade['lat'] as num?)?.toDouble();
    final lng = (promenade['lng'] as num?)?.toDouble();
    final photoUrl = promenade['photo_url']?.toString();

    final partsData = promenade['promenades_participants'];
    final nbParticipants = (partsData is List && partsData.isNotEmpty)
        ? (partsData.first['count'] as num?)?.toInt() ?? 0 : 0;
    final isFull = !estParticipant && participantsMax != null && nbParticipants >= participantsMax;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Thumbnail ──
        ClipRRect(
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
          child: SizedBox(
            width: 88,
            child: photoUrl != null
                ? Image.network(photoUrl, fit: BoxFit.cover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF2E7D5E), Color(0xFF7ED69D)],
                      ),
                    ),
                    child: const Center(child: Icon(Icons.directions_walk_rounded, color: Colors.white, size: 34)),
                  ),
          ),
        ),
        // ── Contenu ──
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (dateHeure.isNotEmpty)
                Text(_fmtDateRelative(dateHeure),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 3),
              Text(titre,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 14, color: Color(0xFF1E2025)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              if (lieu.isNotEmpty)
                Row(children: [
                  Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Expanded(child: Text(lieu,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (lat != null && lng != null)
                    GestureDetector(
                      onTap: () => _openNavigation(lat, lng),
                      child: const Icon(Icons.navigation_outlined, size: 14, color: Color(0xFF2E7D5E)),
                    ),
                ]),
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.group_outlined, size: 12, color: isFull ? Colors.red.shade300 : Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  participantsMax != null ? '$nbParticipants/$participantsMax participants' : '$nbParticipants participants',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                      color: isFull ? Colors.red.shade300 : Colors.grey.shade500,
                      fontWeight: isFull ? FontWeight.w700 : FontWeight.normal),
                ),
              ]),
              if (espece.isNotEmpty && espece != 'Toutes' && espece != 'Toutes espèces') ...[
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.pets, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('$espece bienvenus',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                ]),
              ],
              if (myStatut != null || isFull) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFull ? Colors.grey.shade100
                          : myStatut == 'accepte' ? const Color(0xFF7ED69D).withValues(alpha: 0.15)
                          : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isFull ? 'Complet'
                          : myStatut == 'accepte' ? '✓ Inscrit'
                          : '⏳ En attente',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700,
                          color: isFull ? Colors.grey
                              : myStatut == 'accepte' ? const Color(0xFF2E7D5E)
                              : Colors.amber.shade800),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
        // ── Chevron ──
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Center(child: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300, size: 22)),
        ),
      ]),
    );
  }
}

// ─── Sheet création ───────────────────────────────────────────────────────────

class _CreatePromenadesSheet extends StatefulWidget {
  const _CreatePromenadesSheet();

  @override
  State<_CreatePromenadesSheet> createState() => _CreatePromenadesSheetState();
}

class _CreatePromenadesSheetState extends State<_CreatePromenadesSheet> {
  final _formKey = GlobalKey<FormState>();
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _titre = '';
  String _description = '';
  String _niveau = 'facile';
  String _espece = 'Toutes';
  bool _toutesRaces = true;
  DateTime _dateHeure = DateTime.now().add(const Duration(days: 3));
  int _dureeMinutes = 60;
  int? _participantsMax;
  double? _lat;
  double? _lng;
  bool _saving = false;

  final _racesCtrl = TextEditingController();

  late final GoogleMapsPlaces _places;
  final _lieuCtrl = TextEditingController();
  List<Prediction> _predictions = [];
  Timer? _debounce;
  bool _loadingPredictions = false;

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(apiKey: getApiKey());
  }

  @override
  void dispose() {
    _places.dispose();
    _debounce?.cancel();
    _lieuCtrl.dispose();
    _racesCtrl.dispose();
    super.dispose();
  }

  void _onLieuChanged(String val) {
    _debounce?.cancel();
    if (val.length < 3) {
      setState(() { _predictions = []; _loadingPredictions = false; _lat = null; _lng = null; });
      return;
    }
    setState(() => _loadingPredictions = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetchPredictions(val));
  }

  Future<void> _fetchPredictions(String input) async {
    final res = await _places.autocomplete(
      input,
      components: [Component(Component.country, 'fr')],
      language: 'fr',
    );
    if (!mounted) return;
    setState(() {
      _predictions = res.isOkay ? res.predictions : [];
      _loadingPredictions = false;
    });
  }

  Future<void> _selectPrediction(Prediction p) async {
    _debounce?.cancel();
    setState(() { _predictions = []; _lieuCtrl.text = p.description ?? ''; });
    if (p.placeId == null) return;
    final det = await _places.getDetailsByPlaceId(p.placeId!);
    if (!mounted || !det.isOkay) return;
    final loc = det.result.geometry?.location;
    if (loc != null) setState(() { _lat = loc.lat; _lng = loc.lng; });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateHeure,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
          data: ThemeData.light()
              .copyWith(colorScheme: const ColorScheme.light(primary: _orange)),
          child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateHeure),
    );
    if (time == null || !mounted) return;
    setState(() => _dateHeure =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      final pid = User_Info.activeProfileId;
      final result = await _supa.from('promenades').insert({
        'organisateur_uid': _uid,
        if (pid != null) 'organisateur_profile_id': pid,
        'titre': _titre,
        'lieu_rdv': _lieuCtrl.text.trim(),
        'description': _description,
        'niveau': _niveau,
        'date_heure': _dateHeure.toIso8601String(),
        'duree_minutes': _dureeMinutes,
        'statut': 'ouvert',
        'created_at': DateTime.now().toIso8601String(),
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
        if (_participantsMax != null) 'participants_max': _participantsMax,
        'espece': _espece,
        'toutes_races': _toutesRaces,
        if (!_toutesRaces && _racesCtrl.text.trim().isNotEmpty) 'races': _racesCtrl.text.trim(),
      }).select('id').single();
      // Ajouter l'événement dans l'agenda de l'organisateur
      try {
        final promenadeId = result['id']?.toString();
        if (promenadeId != null) {
          await _supa.from('agenda_events').insert({
            'uid':            _uid,
            'titre':          _titre,
            'type':           'promenade',
            'date_debut':     _dateHeure.toUtc().toIso8601String(),
            'notes':          _lieuCtrl.text.trim().isNotEmpty
                ? 'RDV : ${_lieuCtrl.text.trim()}'
                : null,
            'pro_profile_id': pid ?? '',
            'promenade_id':   promenadeId,
          });
        }
      } catch (_) {}
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(
                      child: Text('Organiser une promenade',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 18))),
                  IconButton(
                      icon: const Icon(Icons.close, size: 22, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                ]),
                const SizedBox(height: 20),

                _lbl('Titre *'),
                TextFormField(
                  decoration: _dec('Ex : Balade au bord du lac'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _titre = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                _lbl('Lieu de rendez-vous *'),
                TextFormField(
                  controller: _lieuCtrl,
                  onChanged: _onLieuChanged,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  decoration: InputDecoration(
                    hintText: 'Rechercher une adresse…',
                    hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF2E7D5E)),
                    suffixIcon: _loadingPredictions
                        ? const Padding(padding: EdgeInsets.all(12),
                            child: SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D5E))))
                        : (_lat != null
                            ? const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF2E7D5E))
                            : (_predictions.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () => setState(() {
                                      _predictions = []; _lieuCtrl.clear(); _lat = null; _lng = null;
                                    }))
                                : null)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2E7D5E), width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  ),
                ),
                if (_predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _predictions.length > 5 ? 5 : _predictions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 40),
                      itemBuilder: (_, i) {
                        final p = _predictions[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on_outlined,
                              size: 18, color: Color(0xFF2E7D5E)),
                          title: Text(p.description ?? '',
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                          onTap: () => _selectPrediction(p),
                        );
                      },
                    ),
                  ),
                if (_lat != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.navigation_outlined, size: 12, color: Color(0xFF2E7D5E)),
                    const SizedBox(width: 4),
                    const Text('Position géolocalisée — bouton Y aller disponible',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF2E7D5E))),
                  ]),
                ],
                const SizedBox(height: 12),

                _lbl('Date et heure *'),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined, size: 16, color: _orange),
                      const SizedBox(width: 10),
                      Text(DateFormat('dd/MM/yyyy · HH:mm').format(_dateHeure),
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('Niveau'),
                    InputDecorator(
                      decoration: _dec(''),
                      child: DropdownButton<String>(
                        value: _niveau,
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: _kNiveaux
                            .map((n) => DropdownMenuItem(
                                value: n,
                                child: Text(n,
                                    style: const TextStyle(
                                        fontFamily: 'Galey', fontSize: 14))))
                            .toList(),
                        onChanged: (v) => setState(() => _niveau = v ?? 'facile'),
                      ),
                    ),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('Durée (min)'),
                    TextFormField(
                      initialValue: '60',
                      decoration: _dec('60'),
                      keyboardType: TextInputType.number,
                      onSaved: (v) => _dureeMinutes = int.tryParse(v?.trim() ?? '') ?? 60,
                    ),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('Max participants'),
                    TextFormField(
                      decoration: _dec('Illimité'),
                      keyboardType: TextInputType.number,
                      onSaved: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        _participantsMax = (n != null && n >= 2) ? n : null;
                      },
                    ),
                  ])),
                ]),
                const SizedBox(height: 12),

                _lbl('Description'),
                TextFormField(
                  decoration: _dec('Parcours, équipement recommandé…'),
                  maxLines: 3,
                  onSaved: (v) => _description = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                _lbl('Espèce concernée'),
                Wrap(spacing: 6, runSpacing: 6, children: _kEspeces.map((e) {
                  final sel = _espece == e;
                  return GestureDetector(
                    onTap: () => setState(() => _espece = e),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF2E7D5E) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_especeEmoji(e),
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.grey.shade700)),
                    ),
                  );
                }).toList()),
                const SizedBox(height: 12),

                Row(children: [
                  const Expanded(child: Text('Toutes races acceptées',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600))),
                  Switch(
                    value: _toutesRaces,
                    onChanged: (v) => setState(() => _toutesRaces = v),
                    activeColor: const Color(0xFF2E7D5E),
                  ),
                ]),
                if (!_toutesRaces) ...[
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _racesCtrl,
                    decoration: _dec('Ex : Golden Retriever, Labrador…'),
                  ),
                ],
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: _orange,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Publier la promenade',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF6F767B))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _orange, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      );
}
