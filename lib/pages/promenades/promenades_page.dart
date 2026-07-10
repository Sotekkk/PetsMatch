import 'dart:async';

import 'package:PetsMatch/main.dart' show getApiKey, User_Info;
import 'package:PetsMatch/pages/promenades/promenade_detail_page.dart';
import 'package:PetsMatch/services/promenade_notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _orange = Color(0xFFEF6C00);

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
  String _filterEspece = 'Toutes';
  final _filterLieuCtrl = TextEditingController();

  List<Map<String, dynamic>> get _filtered {
    final lieu = _filterLieuCtrl.text.toLowerCase().trim();
    return _promenades.where((p) {
      final espece = p['espece']?.toString() ?? 'Toutes';
      if (_filterEspece != 'Toutes' && espece != 'Toutes' && espece != 'Toutes espèces' && espece != _filterEspece) return false;
      if (lieu.isNotEmpty) {
        final adresse = (p['lieu_rdv'] ?? '').toString().toLowerCase();
        if (!adresse.contains(lieu)) return false;
      }
      return true;
    }).toList();
  }

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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D5E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Promenades & Randonnées',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: _uid.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: _orange,
              onPressed: _openCreation,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : Column(children: [
              // ── Filtres ──
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Filtre lieu
                  TextField(
                    controller: _filterLieuCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Filtrer par ville, département, région…',
                      hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 13),
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF2E7D5E)),
                      suffixIcon: _filterLieuCtrl.text.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() => _filterLieuCtrl.clear()))
                          : null,
                      filled: true, fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Filtre espèce
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _kEspeces.map((e) {
                      final sel = _filterEspece == e;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _filterEspece = e),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: sel ? const Color(0xFF2E7D5E) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(_especeEmoji(e),
                                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : Colors.grey.shade700)),
                          ),
                        ),
                      );
                    }).toList()),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: _filtered.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _orange,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
              ),
            ]),
    );
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

// ─── Card ─────────────────────────────────────────────────────────────────────

class _PromenadesCard extends StatelessWidget {
  final Map<String, dynamic> promenade;
  final bool estParticipant;
  final String? myStatut;
  final VoidCallback? onToggle;

  const _PromenadesCard(
      {required this.promenade, required this.estParticipant, this.myStatut, this.onToggle});

  static Color _niveauColor(String n) => switch (n) {
        'facile' => const Color(0xFF6E9E57),
        'moyen' => const Color(0xFFEF6C00),
        'difficile' => Colors.red,
        _ => Colors.grey,
      };

  static String _fmtDate(String iso) {
    try {
      return DateFormat('dd/MM/yyyy · HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final titre = promenade['titre']?.toString() ?? 'Promenade';
    final lieu = promenade['lieu_rdv']?.toString() ?? '';
    final dateHeure = promenade['date_heure']?.toString() ?? '';
    final niveau = promenade['niveau']?.toString() ?? 'facile';
    final duree = (promenade['duree_minutes'] as num?)?.toInt();
    final distance = (promenade['distance_km'] as num?)?.toDouble();
    final desc = promenade['description']?.toString() ?? '';
    final lat = (promenade['lat'] as num?)?.toDouble();
    final lng = (promenade['lng'] as num?)?.toDouble();
    final participantsMax = (promenade['participants_max'] as num?)?.toInt();
    final espece = promenade['espece']?.toString() ?? '';
    final toutesRaces = promenade['toutes_races'] as bool? ?? true;
    final races = promenade['races']?.toString() ?? '';

    final partsData = promenade['promenades_participants'];
    final nbParticipants = (partsData is List && partsData.isNotEmpty)
        ? (partsData.first['count'] as num?)?.toInt() ?? 0
        : 0;

    final isFull = !estParticipant &&
        participantsMax != null &&
        nbParticipants >= participantsMax;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(titre,
                  style: const TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF1E2025))),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _niveauColor(niveau).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(niveau,
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 11,
                      color: _niveauColor(niveau),
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          if (espece.isNotEmpty && espece != 'Toutes' && espece != 'Toutes espèces') ...[
            const SizedBox(height: 6),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFF2E7D5E).withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(_especeEmoji(espece),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                        color: Color(0xFF2E7D5E), fontWeight: FontWeight.w600)),
              ),
              if (!toutesRaces && races.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(child: Text('• $races',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis)),
              ],
            ]),
          ],
          if (dateHeure.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.schedule_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Text(_fmtDate(dateHeure),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            ]),
          ],
          if (lieu.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Expanded(
                child: Text(lieu,
                    style: const TextStyle(
                        fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis),
              ),
              if (lat != null && lng != null)
                GestureDetector(
                  onTap: () => _openNavigation(lat, lng),
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D5E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.navigation_outlined, size: 11, color: Color(0xFF2E7D5E)),
                      SizedBox(width: 3),
                      Text('Y aller',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D5E))),
                    ]),
                  ),
                ),
            ]),
          ],
          if (duree != null || distance != null || nbParticipants > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              if (duree != null) ...[
                const Icon(Icons.timer_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${duree}min',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ],
              if (duree != null && distance != null) const SizedBox(width: 12),
              if (distance != null) ...[
                const Icon(Icons.straighten, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${distance.toStringAsFixed(1)} km',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ],
              if ((duree != null || distance != null) && nbParticipants > 0)
                const SizedBox(width: 12),
              if (nbParticipants > 0 || participantsMax != null) ...[
                Icon(Icons.group_outlined,
                    size: 13, color: isFull ? Colors.red.shade400 : Colors.grey),
                const SizedBox(width: 4),
                Text(
                  participantsMax != null
                      ? '$nbParticipants / $participantsMax'
                      : '$nbParticipants',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 12,
                      color: isFull ? Colors.red.shade400 : Colors.grey,
                      fontWeight: isFull ? FontWeight.w700 : FontWeight.normal),
                ),
                if (isFull) ...[
                  const SizedBox(width: 4),
                  Text('· Complet',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 12,
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.w700)),
                ],
              ],
            ]),
          ],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc,
                style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (estParticipant || onToggle != null || isFull) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: myStatut == 'en_attente'
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade300),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('⏳ En attente',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.amber.shade800)),
                    )
                  : isFull
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Complet',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey)),
                        )
                      : GestureDetector(
                          onTap: onToggle,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: myStatut == 'accepte' ? _orange : Colors.transparent,
                              border: Border.all(color: _orange),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              myStatut == 'accepte' ? 'Inscrit ✓' : 'Rejoindre',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: myStatut == 'accepte' ? Colors.white : _orange),
                            ),
                          ),
                        ),
            ),
          ],
        ]),
      ),
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
