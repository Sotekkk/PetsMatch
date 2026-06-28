import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// ─── Constantes ───────────────────────────────────────────────────────────────

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);

const _catEmoji = {
  'foret':   '🌲',
  'plage':   '🏖️',
  'parc':    '🌿',
  'lac':     '💧',
  'riviere': '🏞️',
};

const _catLabel = {
  'foret':   'Forêt',
  'plage':   'Plage',
  'parc':    'Parc',
  'lac':     'Lac',
  'riviere': 'Rivière',
};

const _catColor = {
  'foret':   Color(0xFF2E7D32),
  'plage':   Color(0xFF1565C0),
  'parc':    Color(0xFF558B2F),
  'lac':     Color(0xFF00838F),
  'riviere': Color(0xFF0277BD),
};

const _catPhoto = {
  'foret':   'https://images.unsplash.com/photo-1448375240586-882707db888b?w=800&q=80&fit=crop',
  'plage':   'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&q=80&fit=crop',
  'parc':    'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?w=800&q=80&fit=crop',
  'lac':     'https://images.unsplash.com/photo-1501854140801-50d01698950b?w=800&q=80&fit=crop',
  'riviere': 'https://images.unsplash.com/photo-1544198365-f5d60b6d8190?w=800&q=80&fit=crop',
};

// ─── Page ─────────────────────────────────────────────────────────────────────

class NaturalPlaceDetailPage extends StatefulWidget {
  final Map<String, dynamic> place;
  const NaturalPlaceDetailPage({super.key, required this.place});

  @override
  State<NaturalPlaceDetailPage> createState() => _NaturalPlaceDetailPageState();
}

class _NaturalPlaceDetailPageState extends State<NaturalPlaceDetailPage> {
  final _supa = Supabase.instance.client;
  String get _uid => User_Info.activeProfileId;

  late Map<String, dynamic> _place;
  List<Map<String, dynamic>> _reviews = [];
  bool _loadingReviews = true;
  bool _savingReview   = false;

  // Pour le formulaire d'avis
  int    _myNote    = 0;
  String _myComment = '';
  final  _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _place = Map<String, dynamic>.from(widget.place);
    _loadReviews();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    setState(() => _loadingReviews = true);
    try {
      final id = _place['id']?.toString();
      if (id == null) return;

      final data = await _supa
          .from('natural_place_reviews')
          .select()
          .eq('place_id', id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _reviews = List<Map<String, dynamic>>.from(data as List);
          _loadingReviews = false;
        });

        // Pré-remplir si l'user a déjà un avis
        final myReview = _reviews.firstWhere(
          (r) => r['profile_id']?.toString() == _uid,
          orElse: () => {},
        );
        if (myReview.isNotEmpty) {
          setState(() {
            _myNote    = (myReview['note'] as int?) ?? 0;
            _myComment = myReview['commentaire'] as String? ?? '';
            _commentCtrl.text = _myComment;
          });
        }
      }
    } catch (e) {
      debugPrint('[NaturalDetail] reviews error: $e');
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  Future<void> _refreshPlace() async {
    try {
      final id = _place['id']?.toString();
      if (id == null) return;
      final data = await _supa.from('natural_places').select().eq('id', id).single();
      if (mounted) setState(() => _place = Map<String, dynamic>.from(data as Map));
    } catch (_) {}
  }

  Future<void> _submitReview() async {
    if (_myNote == 0 || _uid.isEmpty) return;
    setState(() => _savingReview = true);
    try {
      final id = _place['id']?.toString();
      if (id == null) return;

      await _supa.from('natural_place_reviews').upsert({
        'place_id':    id,
        'profile_id':    _uid,
        'note':        _myNote,
        'commentaire': _commentCtrl.text.trim(),
      }, onConflict: 'place_id,profile_id');

      // Recalcul note moyenne + nb_avis côté client approximatif
      await _recalcStats(id);
      await _loadReviews();
      await _refreshPlace();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Avis publié !',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _green,
        ));
      }
    } catch (e) {
      debugPrint('[NaturalDetail] review error: $e');
    } finally {
      if (mounted) setState(() => _savingReview = false);
    }
  }

  Future<void> _recalcStats(String placeId) async {
    try {
      final rows = await _supa
          .from('natural_place_reviews')
          .select('note')
          .eq('place_id', placeId);
      final notes = (rows as List).map((r) => (r['note'] as int?) ?? 0).toList();
      if (notes.isEmpty) return;
      final avg = notes.reduce((a, b) => a + b) / notes.length;
      await _supa.from('natural_places').update({
        'nb_avis':       notes.length,
        'note_moyenne':  avg,
      }).eq('id', placeId);
    } catch (_) {}
  }

  Future<void> _reportCyano() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Signaler cyanobactéries ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text(
            'Confirmer la présence de cyanobactéries sur ce site ? '
            'Cette alerte sera visible par tous les utilisateurs.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Signaler', style: TextStyle(color: Colors.white, fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final id = _place['id']?.toString();
      if (id == null) return;
      await _supa.from('natural_places').update({
        'alerte_cyano':      true,
        'alerte_cyano_date': DateTime.now().toIso8601String(),
        'alerte_cyano_profile_id':  _uid,
      }).eq('id', id);
      await _refreshPlace();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Alerte signalée. Merci !',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    } catch (_) {}
  }

  Future<void> _removeCyano() async {
    try {
      final id = _place['id']?.toString();
      if (id == null) return;
      await _supa.from('natural_places').update({
        'alerte_cyano':      false,
        'alerte_cyano_date': null,
        'alerte_cyano_profile_id':  null,
      }).eq('id', id);
      await _refreshPlace();
    } catch (_) {}
  }

  Future<void> _updateAmenity(String field, bool value) async {
    try {
      final id = _place['id']?.toString();
      if (id == null) return;
      await _supa.from('natural_places').update({field: value}).eq('id', id);
      setState(() => _place[field] = value);
    } catch (_) {}
  }

  Future<void> _openNavigation() async {
    final lat = (_place['lat'] as num?)?.toDouble();
    final lng = (_place['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom   = _place['nom']      as String? ?? '';
    final cat   = _place['categorie'] as String? ?? '';
    final desc  = _place['description'] as String? ?? '';
    final cyano = _place['alerte_cyano'] == true;
    final color = _catColor[cat] ?? _teal;
    final photoUrl = (_place['photo_url'] as String?)?.isNotEmpty == true
        ? _place['photo_url'] as String
        : _catPhoto[cat];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar avec photo ───────────────────────────────────
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: color,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(nom,
                  style: const TextStyle(
                      fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 16, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
              background: Stack(children: [
                photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        width: double.infinity, height: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: color),
                      )
                    : Container(color: color),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                      stops: [0.4, 1.0],
                    ),
                  ),
                ),
              ]),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(children: [
              // ── Alerte cyano ──────────────────────────────────────────
              if (cyano)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '⚠️ Alerte cyanobactéries active — Baignade et contact avec l\'eau déconseillés.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_uid.isNotEmpty)
                      TextButton(
                        onPressed: _removeCyano,
                        child: const Text('Lever', style: TextStyle(color: Colors.white,
                            fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // ── Header info ────────────────────────────────────────
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '${_catEmoji[cat] ?? ''} ${_catLabel[cat] ?? cat}',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                            fontWeight: FontWeight.w600, color: color),
                      ),
                    ),
                    const Spacer(),
                    // Note globale
                    if ((_place['nb_avis'] as int? ?? 0) > 0)
                      Row(children: [
                        const Icon(Icons.star, size: 16, color: Color(0xFFFDD835)),
                        const SizedBox(width: 3),
                        Text(
                          '${(_place['note_moyenne'] as num? ?? 0).toStringAsFixed(1)} '
                          '(${_place['nb_avis']} avis)',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                              color: Colors.black87),
                        ),
                      ]),
                  ]),

                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(desc, style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                        color: Colors.black87, height: 1.5)),
                  ],

                  const SizedBox(height: 16),

                  // ── Boutons actions ────────────────────────────────────
                  Row(children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.directions_outlined,
                        label: 'Itinéraire',
                        color: _teal,
                        onTap: _openNavigation,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (!cyano)
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.warning_amber_outlined,
                          label: 'Signaler cyano',
                          color: Colors.red.shade600,
                          onTap: _uid.isEmpty ? null : _reportCyano,
                        ),
                      ),
                  ]),

                  const SizedBox(height: 20),

                  // ── Équipements ────────────────────────────────────────
                  _SectionTitle(title: 'Équipements & caractéristiques'),
                  const SizedBox(height: 10),
                  _AmenitiesGrid(
                    place: _place,
                    onChanged: _uid.isNotEmpty ? _updateAmenity : null,
                  ),

                  const SizedBox(height: 20),

                  // ── Niveau difficulté ──────────────────────────────────
                  _SectionTitle(title: 'Difficulté'),
                  const SizedBox(height: 8),
                  _DifficultyPicker(
                    current: _place['niveau_difficulte'] as String? ?? '',
                    onChanged: _uid.isEmpty ? null : (val) async {
                      try {
                        final id = _place['id']?.toString();
                        if (id == null) return;
                        await _supa.from('natural_places')
                            .update({'niveau_difficulte': val}).eq('id', id);
                        setState(() => _place['niveau_difficulte'] = val);
                      } catch (_) {}
                    },
                  ),

                  const SizedBox(height: 20),

                  // ── Avis ──────────────────────────────────────────────
                  _SectionTitle(title: 'Avis'),
                  const SizedBox(height: 12),

                  if (_uid.isNotEmpty) ...[
                    _ReviewForm(
                      myNote:      _myNote,
                      controller:  _commentCtrl,
                      saving:      _savingReview,
                      onNoteChange: (n) => setState(() => _myNote = n),
                      onSubmit:    _submitReview,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                  ],

                  if (_loadingReviews)
                    const Center(child: CircularProgressIndicator(color: _teal))
                  else if (_reviews.isEmpty)
                    const Text('Aucun avis pour le moment. Soyez le premier !',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey))
                  else
                    ..._reviews.map((r) => _ReviewTile(review: r)),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── Grille équipements ───────────────────────────────────────────────────────

class _AmenitiesGrid extends StatelessWidget {
  final Map<String, dynamic> place;
  final void Function(String field, bool value)? onChanged;

  const _AmenitiesGrid({required this.place, this.onChanged});

  static const _items = [
    ('has_eau',          Icons.water_drop_outlined,    'Eau potable'),
    ('has_parking',      Icons.local_parking_outlined, 'Parking'),
    ('has_fontaine',     Icons.local_drink_outlined,   'Fontaine'),
    ('has_poubelle',     Icons.delete_outline,         'Poubelles'),
    ('parcours_ombre',   Icons.wb_shade,               'Parcours ombragé'),
    ('baignade_possible',Icons.pool_outlined,           'Baignade'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3.5,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: _items.map((item) {
        final (field, icon, label) = item;
        final active = place[field] == true;
        return GestureDetector(
          onTap: onChanged != null
              ? () => onChanged!(field, !active)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: active ? _green.withValues(alpha: 0.12) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _green.withValues(alpha: 0.5) : Colors.grey.shade200,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Icon(icon, size: 16,
                  color: active ? _green : Colors.grey.shade400),
              const SizedBox(width: 6),
              Expanded(child: Text(label,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: active ? Colors.black87 : Colors.grey.shade500,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal),
                  overflow: TextOverflow.ellipsis)),
              if (onChanged != null)
                Icon(
                  active ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 14,
                  color: active ? _green : Colors.grey.shade300,
                ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Difficulté ───────────────────────────────────────────────────────────────

class _DifficultyPicker extends StatelessWidget {
  final String current;
  final void Function(String)? onChanged;
  const _DifficultyPicker({required this.current, this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [
      ('facile',    '🟢 Facile',    Colors.green),
      ('moyen',     '🟡 Moyen',     Colors.orange),
      ('difficile', '🔴 Difficile', Colors.red),
    ];
    return Row(children: options.map((o) {
      final (val, label, color) = o;
      final active = current == val;
      return Expanded(
        child: GestureDetector(
          onTap: onChanged != null ? () => onChanged!(val) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: active ? (color as Color).withValues(alpha: 0.15) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? (color as Color) : Colors.grey.shade200,
              ),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                    color: active ? (color as Color) : Colors.grey.shade500)),
          ),
        ),
      );
    }).toList());
  }
}

// ─── Formulaire avis ─────────────────────────────────────────────────────────

class _ReviewForm extends StatelessWidget {
  final int myNote;
  final TextEditingController controller;
  final bool saving;
  final void Function(int) onNoteChange;
  final VoidCallback onSubmit;

  const _ReviewForm({
    required this.myNote,
    required this.controller,
    required this.saving,
    required this.onNoteChange,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Votre avis', style: TextStyle(
            fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),

        // Étoiles
        Row(children: List.generate(5, (i) => GestureDetector(
          onTap: () => onNoteChange(i + 1),
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              i < myNote ? Icons.star : Icons.star_border,
              color: const Color(0xFFFDD835),
              size: 28,
            ),
          ),
        ))),
        const SizedBox(height: 10),

        // Commentaire
        TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Partagez votre expérience...',
            hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                color: Colors.grey),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _teal)),
            filled: true, fillColor: const Color(0xFFF8F9FA),
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (saving || myNote == 0) ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Publier mon avis',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

// ─── Tile avis ────────────────────────────────────────────────────────────────

class _ReviewTile extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final note      = (review['note'] as int?) ?? 0;
    final comment   = review['commentaire'] as String? ?? '';
    final createdAt = review['created_at'] as String? ?? '';
    DateTime? dt;
    try { dt = DateTime.parse(createdAt).toLocal(); } catch (_) {}
    final dateStr = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Row(children: List.generate(5, (i) => Icon(
            i < note ? Icons.star : Icons.star_border,
            size: 14,
            color: const Color(0xFFFDD835),
          ))),
          const Spacer(),
          Text(dateStr, style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
              color: Colors.grey)),
        ]),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(comment, style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
              color: Colors.black87)),
        ],
      ]),
    );
  }
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
          fontSize: 16, color: Color(0xFF1F2A2E)));
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ActionButton({
    required this.icon, required this.label,
    required this.color, this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
            fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}
