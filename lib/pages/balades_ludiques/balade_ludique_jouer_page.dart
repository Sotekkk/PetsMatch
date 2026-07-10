import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'balades_ludiques_shared.dart';
import 'widgets/defi_photo_widget.dart';
import 'widgets/defi_question_widget.dart';
import 'widgets/defi_qr_widget.dart';
import 'widgets/defi_gps_widget.dart';

class BaladeLudiqueJouerPage extends StatefulWidget {
  final String baladeId;
  const BaladeLudiqueJouerPage({super.key, required this.baladeId});

  @override
  State<BaladeLudiqueJouerPage> createState() => _BaladeLudiqueJouerPageState();
}

class _BaladeLudiqueJouerPageState extends State<BaladeLudiqueJouerPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _balade;
  List<Map<String, dynamic>> _points = [];
  Map<String, dynamic>? _progression;
  List<String> _badgesDebloquees = [];
  int? _xpGagne;
  bool _showIndice = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final balade = await _supa.from('balades_ludiques').select().eq('id', widget.baladeId).single();
    final points = await _supa.from('balades_ludiques_points').select().eq('balade_id', widget.baladeId).order('ordre');
    var progression = await _supa.from('balades_ludiques_progressions').select()
        .eq('balade_id', widget.baladeId).eq('joueur_uid', _uid).maybeSingle();
    progression ??= await _supa.from('balades_ludiques_progressions').insert({
      'balade_id': widget.baladeId, 'joueur_uid': _uid,
    }).select().single();

    if (mounted) {
      setState(() {
        _balade = balade;
        _points = List<Map<String, dynamic>>.from(points as List);
        _progression = progression;
        _showIndice = false;
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _currentPoint {
    final idx = (_progression?['nb_points_valides'] as int?) ?? 0;
    if (idx >= _points.length) return null;
    return _points[idx];
  }

  Future<void> _onValidated(Map<String, dynamic> point, {
    String? photoUrl, String? texte, double? lat, double? lng, double? distance,
  }) async {
    final progressionId = _progression!['id'] as String;
    final typeDefi = point['type_defi'] as String;
    final typePreuve = switch (typeDefi) {
      'photo' || 'objet_nature' || 'action_animal' => 'photo',
      'question' => 'texte',
      'qr_code' => 'qr_code',
      _ => 'gps',
    };

    try {
      await _supa.from('balades_ludiques_validations').insert({
        'progression_id': progressionId,
        'point_id': point['id'],
        'joueur_uid': _uid,
        'type_preuve': typePreuve,
        'preuve_photo_url': photoUrl,
        'preuve_texte': texte,
        'preuve_lat': lat,
        'preuve_lng': lng,
        'distance_calculee_m': distance,
      });
    } catch (_) {
      // Déjà validée (contrainte UNIQUE) — on continue simplement.
    }

    final nouveauNb = ((_progression!['nb_points_valides'] as int?) ?? 0) + 1;
    final estTermine = nouveauNb >= _points.length;

    final update = <String, dynamic>{'nb_points_valides': nouveauNb};
    if (estTermine) {
      update['statut'] = 'termine';
      update['completed_at'] = DateTime.now().toIso8601String();
    }
    final updated = await _supa.from('balades_ludiques_progressions')
        .update(update).eq('id', progressionId).select().single();

    if (mounted) setState(() { _progression = updated; _showIndice = false; });

    if (estTermine) await _onCompletion();
  }

  Future<void> _onCompletion() async {
    final b = _balade!;
    final xpGagne = (b['xp_recompense'] as int?) ?? 0;

    // Compteur de complétions du parcours
    try {
      final rows = await _supa.from('balades_ludiques_progressions').select()
          .eq('balade_id', widget.baladeId).eq('statut', 'termine').count(CountOption.exact);
      await _supa.from('balades_ludiques').update({'nb_completions': rows.count}).eq('id', widget.baladeId);
    } catch (_) {}

    // XP + compteur joueur
    Map<String, dynamic> xpRow;
    try {
      final existing = await _supa.from('joueurs_xp').select().eq('user_uid', _uid).maybeSingle();
      final nouveauXp = ((existing?['xp_total'] as int?) ?? 0) + xpGagne;
      final nouveauNbCompletes = ((existing?['nb_parcours_completes'] as int?) ?? 0) + 1;
      xpRow = await _supa.from('joueurs_xp').upsert({
        'user_uid': _uid,
        'xp_total': nouveauXp,
        'nb_parcours_completes': nouveauNbCompletes,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_uid').select().single();
    } catch (_) {
      xpRow = {'xp_total': xpGagne, 'nb_parcours_completes': 1};
    }

    // Badges débloqués par seuils
    final debloquees = <String>[];
    try {
      final catalogue = await _supa.from('badges').select().eq('actif', true);
      final deja = await _supa.from('badges_obtenus').select('badge_id').eq('user_uid', _uid);
      final dejaIds = List<Map<String, dynamic>>.from(deja as List).map((r) => r['badge_id']).toSet();

      for (final badgeRaw in List<Map<String, dynamic>>.from(catalogue as List)) {
        if (dejaIds.contains(badgeRaw['id'])) continue;
        final conditionType = badgeRaw['condition_type'] as String;
        final valeur = (badgeRaw['condition_valeur'] as Map<String, dynamic>?) ?? {};
        bool obtenu = false;
        if (conditionType == 'nb_parcours_completes') {
          obtenu = (xpRow['nb_parcours_completes'] as int) >= ((valeur['seuil'] as num?)?.toInt() ?? 999999);
        } else if (conditionType == 'nb_xp') {
          obtenu = (xpRow['xp_total'] as int) >= ((valeur['seuil'] as num?)?.toInt() ?? 999999);
        }
        if (obtenu) {
          await _supa.from('badges_obtenus').insert({
            'user_uid': _uid, 'badge_id': badgeRaw['id'], 'balade_id': widget.baladeId,
          });
          debloquees.add('${badgeRaw['icone_url'] ?? '🏅'} ${badgeRaw['nom']}');
        }
      }
    } catch (_) {}

    // Notification
    try {
      await _supa.from('notifications').insert({
        'uid': _uid,
        'type': 'balade_ludique_xp',
        'data': {'balade_id': widget.baladeId, 'xp': xpGagne, 'titre': b['titre']},
        'read': false,
      });
    } catch (_) {}

    if (mounted) setState(() { _xpGagne = xpGagne; _badgesDebloquees = debloquees; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kBlTeal)));
    final point = _currentPoint;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: kBlTeal, foregroundColor: Colors.white, elevation: 0,
        title: Text(_balade?['titre']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: point == null ? _buildTermine() : _buildEtape(point),
    );
  }

  Widget _buildTermine() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎉', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text('Parcours terminé !', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 22)),
          const SizedBox(height: 8),
          if (_xpGagne != null)
            Text('+$_xpGagne XP', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: kBlOrange)),
          if (_badgesDebloquees.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Badges débloqués :', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._badgesDebloquees.map((b) => Text(b, style: const TextStyle(fontFamily: 'Galey', fontSize: 15))),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: kBlTeal, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('Retour au parcours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ]),
      ),
    );
  }

  Widget _buildEtape(Map<String, dynamic> point) {
    final idx = (_progression?['nb_points_valides'] as int?) ?? 0;
    final lat = (point['lat'] as num).toDouble();
    final lng = (point['lng'] as num).toDouble();

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 200,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 15),
            markers: {Marker(markerId: const MarkerId('point'), position: LatLng(lat, lng))},
            zoomControlsEnabled: false,
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 14, backgroundColor: kBlTeal,
                  child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Galey'))),
              const SizedBox(width: 8),
              Expanded(child: Text('Étape ${idx + 1} / ${_points.length}',
                  style: const TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 12))),
            ]),
            const SizedBox(height: 8),
            Text(point['titre']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 19)),
            if ((point['description'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(point['description'], style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)]),
              child: _buildDefi(point),
            ),
            if ((point['indice'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              _showIndice
                  ? Text('💡 ${point['indice']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontStyle: FontStyle.italic))
                  : TextButton(onPressed: () => setState(() => _showIndice = true),
                      child: const Text('Afficher un indice', style: TextStyle(fontFamily: 'Galey', color: kBlTeal))),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _buildDefi(Map<String, dynamic> point) {
    final type = point['type_defi'] as String;
    switch (type) {
      case 'photo':
        return DefiPhotoWidget(
          consigne: (point['question_texte'] as String?) ?? 'Prenez une photo pour valider cette étape.',
          storagePath: 'balades_ludiques/preuves/${_progression!['id']}/${point['id']}.jpg',
          onValidated: (url) => _onValidated(point, photoUrl: url),
        );
      case 'objet_nature':
      case 'action_animal':
        return DefiPhotoWidget(
          consigne: (point['consigne_texte'] as String?) ?? 'Prenez une photo pour prouver que vous avez réussi le défi.',
          storagePath: 'balades_ludiques/preuves/${_progression!['id']}/${point['id']}.jpg',
          onValidated: (url) => _onValidated(point, photoUrl: url),
        );
      case 'question':
        return DefiQuestionWidget(
          question: (point['question_texte'] as String?) ?? '',
          reponseAttendue: (point['question_reponse'] as String?) ?? '',
          onValidated: (rep) => _onValidated(point, texte: rep),
        );
      case 'qr_code':
        return DefiQrWidget(
          qrCodeValeurAttendue: (point['qr_code_value'] as String?) ?? '',
          onValidated: (v) => _onValidated(point, texte: v),
        );
      case 'gps_seul':
      default:
        return DefiGpsWidget(
          pointLat: (point['lat'] as num).toDouble(),
          pointLng: (point['lng'] as num).toDouble(),
          rayonValidationM: (point['rayon_validation_m'] as int?) ?? 30,
          onValidated: (lat, lng, dist) => _onValidated(point, lat: lat, lng: lng, distance: dist),
        );
    }
  }
}
