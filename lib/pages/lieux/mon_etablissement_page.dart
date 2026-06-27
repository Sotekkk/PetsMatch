import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/lieux/inscription_lieu_page.dart';
import 'package:PetsMatch/pages/lieux/lieu_detail_page.dart';

// ─── Page principale ─────────────────────────────────────────────────────────

class MonEtablissementPage extends StatefulWidget {
  const MonEtablissementPage({super.key});

  @override
  State<MonEtablissementPage> createState() => _MonEtablissementPageState();
}

class _MonEtablissementPageState extends State<MonEtablissementPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supabase = Supabase.instance.client;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  List<Map<String, dynamic>> _places = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final data = await _supabase
          .from('petfriendly_places')
          .select()
          .eq('uid_pro', _uid)
          .order('created_at', ascending: false);
      setState(() {
        _places = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> place) async {
    final nom = place['nom'] as String? ?? 'cet établissement';
    bool confirmed = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_forever_outlined, color: Colors.red.shade400, size: 28),
              ),
              const SizedBox(height: 14),
              const Text('Supprimer l\'établissement ?',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Tu es sur le point de supprimer "$nom".\nToutes les données, photos, avis et disponibilités seront définitivement supprimés. Cette action est irréversible.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => setSheet(() => confirmed = !confirmed),
                child: Row(children: [
                  Checkbox(
                    value: confirmed,
                    onChanged: (v) => setSheet(() => confirmed = v ?? false),
                    activeColor: Colors.red.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  const Expanded(
                    child: Text('Je confirme vouloir supprimer définitivement cet établissement',
                        style: TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Annuler'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: confirmed ? () { Navigator.pop(ctx); _deleteLieu(place); } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.red.shade100,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteLieu(Map<String, dynamic> place) async {
    final id = place['id'].toString();
    setState(() => _loading = true);
    try {
      // Suppression Firebase Storage
      try {
        final ref = FirebaseStorage.instance.ref('lieux/$id');
        final listing = await ref.listAll();
        for (final item in listing.items) {
          await item.delete().catchError((_) {});
        }
      } catch (_) {}

      // Suppression Supabase (enfants d'abord)
      await _supabase.from('place_disponibilites').delete().eq('place_id', id);
      await _supabase.from('petfriendly_reviews').delete().eq('place_id', id);
      await _supabase.from('place_likes').delete().eq('place_id', id);
      await _supabase.from('place_favoris').delete().eq('place_id', id);
      await _supabase.from('petfriendly_places').delete().eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Établissement supprimé'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mon établissement',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _places.isEmpty
              ? _EmptyState(onAdd: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const InscriptionLieuPage(),
                  )).then((_) => _load());
                })
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _places.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final place = _places[i];
                      return _PlaceCard(
                        place: place,
                        onEdit: () async {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => _EditLieuPage(place: place),
                          ));
                          _load();
                        },
                        onView: place['statut'] == 'actif'
                            ? () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => LieuDetailPage(id: place['id'].toString()),
                                ))
                            : null,
                        onDelete: () => _confirmDelete(place),
                      );
                    },
                  ),
                ),
      floatingActionButton: _places.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const InscriptionLieuPage(),
                )).then((_) => _load());
              },
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un lieu'),
            )
          : null,
    );
  }
}

// ─── Card lieu ───────────────────────────────────────────────────────────────

class _PlaceCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final VoidCallback onEdit;
  final VoidCallback? onView;
  final VoidCallback onDelete;
  const _PlaceCard({required this.place, required this.onEdit, required this.onDelete, this.onView});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0C5C6C);
    final nom = place['nom'] as String? ?? '';
    final ville = place['ville'] as String? ?? '';
    final statut = place['statut'] as String? ?? '';
    final banniere = place['banniere_url'] as String?;
    final logo = place['photo_profil_url'] as String?;
    final nbLikes = place['nb_likes'] as int? ?? 0;
    final nbAvis = place['nb_avis'] as int? ?? 0;
    final note = (place['note_moyenne'] as num?)?.toDouble() ?? 0.0;
    final categorie = place['categorie'] as String? ?? '';

    final (statusLabel, statusColor) = switch (statut) {
      'actif'                   => ('✅ Actif', const Color(0xFF4CAF50)),
      'en_attente_validation'   => ('⏳ En attente de validation', const Color(0xFFFF9800)),
      'suspendu'                => ('⛔ Suspendu', Colors.red),
      _                         => ('❓ $statut', Colors.grey),
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bannière
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Stack(
              children: [
                SizedBox(
                  height: 120, width: double.infinity,
                  child: banniere != null
                      ? CachedNetworkImage(imageUrl: banniere, fit: BoxFit.cover)
                      : Container(
                          color: categorie == 'hebergement'
                              ? const Color(0xFF1E88E5)
                              : const Color(0xFFEF6C00),
                          child: Icon(
                            categorie == 'hebergement' ? Icons.hotel_outlined : Icons.restaurant_outlined,
                            color: Colors.white30, size: 60,
                          ),
                        ),
                ),
                Positioned(
                  top: 8, right: 8,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (logo != null)
                    Container(
                      width: 36, height: 36,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(logo), fit: BoxFit.cover),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                      ),
                    ),
                  Expanded(child: Text(nom,
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16))),
                ]),
                const SizedBox(height: 2),
                Text(ville, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
                ),
                if (statut == 'actif') ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.favorite, size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 4),
                    Text('$nbLikes', style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 12),
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFA000)),
                    const SizedBox(width: 4),
                    Text('${note.toStringAsFixed(1)} ($nbAvis avis)',
                        style: const TextStyle(fontSize: 12)),
                  ]),
                ],
                if (statut == 'en_attente_validation') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Votre établissement est en cours de vérification par notre équipe (48h max).',
                      style: TextStyle(fontSize: 12, color: Color(0xFFE65100)),
                    ),
                  ),
                ],
                if (statut == 'suspendu') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Votre établissement a été suspendu. Contactez le support.',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Modifier'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: teal,
                      side: const BorderSide(color: teal),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  )),
                  if (onView != null) ...[
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: onView,
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Voir la fiche'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: teal, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    )),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.store_outlined, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Aucun établissement référencé',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              'Référencez votre hôtel, hébergement ou restaurant pour toucher des propriétaires d\'animaux.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Référencer mon établissement'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5C6C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page d'édition ──────────────────────────────────────────────────────────

class _EditLieuPage extends StatefulWidget {
  final Map<String, dynamic> place;
  const _EditLieuPage({required this.place});

  @override
  State<_EditLieuPage> createState() => _EditLieuPageState();
}

class _EditLieuPageState extends State<_EditLieuPage>
    with SingleTickerProviderStateMixin {
  static const _teal = Color(0xFF0C5C6C);
  late TabController _tabCtrl;
  bool _saving = false;

  // Infos générales (lecture seule sauf description + contact)
  late final TextEditingController _descCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _siteCtrl;

  // Photos
  File? _newLogo;
  File? _newBanniere;
  late List<String> _existingPhotos;
  final Set<int> _removedPhotos = {};
  final List<File> _newPhotos = [];

  // Horaires
  late final Map<String, bool> _horairesFerme;
  late final Map<String, String> _horairesDebut;
  late final Map<String, String> _horairesFin;

  // Espèces
  late final List<String> _especes;

  // Hébergement
  late bool _animauxChambre;
  late int _fraisNuit;
  late int _nbAnimauxMax;
  late bool _espaceDetente;

  // Restauration
  late bool _terrasse;
  late bool _animauxSalle;
  late bool _eauFournie;
  late bool _friandises;
  late bool _petMenu;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    final p = widget.place;

    _descCtrl = TextEditingController(text: p['description'] as String? ?? '');
    _telCtrl = TextEditingController(text: p['telephone'] as String? ?? '');
    _emailCtrl = TextEditingController(text: p['email_contact'] as String? ?? '');
    _siteCtrl = TextEditingController(text: p['site_web'] as String? ?? '');

    _existingPhotos = List<String>.from(p['photos'] as List? ?? []);
    _especes = List<String>.from(p['especes_acceptees'] as List? ?? []);

    // Horaires
    const days = ['lundi','mardi','mercredi','jeudi','vendredi','samedi','dimanche'];
    _horairesFerme = {};
    _horairesDebut = {};
    _horairesFin = {};
    final raw = p['horaires'] as Map<String, dynamic>? ?? {};
    for (final d in days) {
      final val = raw[d] as String?;
      if (val == null || val.toLowerCase().startsWith('ferm')) {
        _horairesFerme[d] = true;
        _horairesDebut[d] = '08:00';
        _horairesFin[d] = '20:00';
      } else {
        _horairesFerme[d] = false;
        final parts = val.split('-');
        _horairesDebut[d] = parts.isNotEmpty ? parts[0].trim() : '08:00';
        _horairesFin[d] = parts.length > 1 ? parts[1].trim() : '20:00';
      }
    }

    // Hébergement
    _animauxChambre = p['animaux_dans_chambre'] as bool? ?? true;
    _fraisNuit = p['frais_animal_nuit'] as int? ?? 0;
    _nbAnimauxMax = p['nb_animaux_max'] as int? ?? 2;
    _espaceDetente = p['espace_detente'] as bool? ?? false;

    // Restauration
    _terrasse = p['terrasse'] as bool? ?? true;
    _animauxSalle = p['animaux_en_salle'] as bool? ?? false;
    _eauFournie = p['eau_fournie'] as bool? ?? false;
    _friandises = p['friandises'] as bool? ?? false;
    _petMenu = p['pet_menu'] as bool? ?? false;
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in [_descCtrl, _telCtrl, _emailCtrl, _siteCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(String day, bool isStart) async {
    final str = isStart ? _horairesDebut[day]! : _horairesFin[day]!;
    final parts = str.split(':');
    final h = int.tryParse(parts[0]) ?? 8;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      final s = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) _horairesDebut[day] = s;
        else _horairesFin[day] = s;
      });
    }
  }

  Future<String> _upload(File file, String path) async {
    final ref = FirebaseStorage.instance.ref('lieux/$path');
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (_descCtrl.text.trim().length < 50) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Description : min 50 caractères'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = widget.place['id'].toString();

      // Logo
      String? logoUrl = widget.place['photo_profil_url'] as String?;
      if (_newLogo != null) logoUrl = await _upload(_newLogo!, '$id/logo.jpg');

      // Bannière
      String? banniereUrl = widget.place['banniere_url'] as String?;
      if (_newBanniere != null) banniereUrl = await _upload(_newBanniere!, '$id/banniere.jpg');

      // Photos finales = existantes (sans supprimées) + nouvelles
      final finalPhotos = _existingPhotos.asMap().entries
          .where((e) => !_removedPhotos.contains(e.key))
          .map((e) => e.value)
          .toList();
      for (int i = 0; i < _newPhotos.length; i++) {
        final url = await _upload(_newPhotos[i], '$id/photo_${finalPhotos.length + i}.jpg');
        finalPhotos.add(url);
      }

      // Horaires
      final horairesClean = <String, String>{
        for (final j in _horairesFerme.keys)
          j: _horairesFerme[j]! ? 'fermé' : '${_horairesDebut[j]}-${_horairesFin[j]}',
      };

      final payload = <String, dynamic>{
        'description':     _descCtrl.text.trim(),
        'telephone':       _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'email_contact':   _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'site_web':        _siteCtrl.text.trim().isEmpty ? null : _siteCtrl.text.trim(),
        'especes_acceptees': _especes,
        'horaires':        horairesClean,
        'photo_profil_url': logoUrl,
        'banniere_url':    banniereUrl,
        'photos':          finalPhotos,
      };

      if (widget.place['categorie'] == 'hebergement') {
        payload.addAll({
          'animaux_dans_chambre': _animauxChambre,
          'frais_animal_nuit':    _fraisNuit > 0 ? _fraisNuit : null,
          'nb_animaux_max':       _nbAnimauxMax,
          'espace_detente':       _espaceDetente,
        });
      } else {
        payload.addAll({
          'terrasse':         _terrasse,
          'animaux_en_salle': _animauxSalle,
          'eau_fournie':      _eauFournie,
          'friandises':       _friandises,
          'pet_menu':         _petMenu,
        });
      }

      await Supabase.instance.client
          .from('petfriendly_places')
          .update(payload)
          .eq('id', id);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Modifications enregistrées ✅'),
          backgroundColor: _teal,
        ));
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHebergement = widget.place['categorie'] == 'hebergement';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Modifier mon établissement',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: 'Informations'),
            if (isHebergement) const Tab(text: 'Disponibilités'),
            if (!isHebergement) const Tab(text: 'Conditions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildInfoTab(),
          isHebergement
              ? _DisponibilitesSection(
                  placeId: widget.place['id'].toString(),
                  prixDefaut: widget.place['prix_nuit_defaut'] as int? ?? 0,
                )
              : _buildConditionsTab(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _saving
                ? const SizedBox(height: 18, width: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Enregistrer les modifications',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    final p = widget.place;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Infos non modifiables
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Informations non modifiables',
                  style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(p['nom'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text('${p['adresse'] ?? ''}, ${p['code_postal'] ?? ''} ${p['ville'] ?? ''}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 2),
              Text('SIRET : ${p['siret'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Description
        _SectionTitle2('Description'),
        TextFormField(
          controller: _descCtrl,
          maxLines: 5,
          maxLength: 1000,
          decoration: _deco('Décrivez votre établissement (min 50 caractères)…'),
        ),
        const SizedBox(height: 20),

        // Logo
        _SectionTitle2('Logo'),
        _NetworkOrFilePicker(
          label: 'Logo (400×400 min)',
          existingUrl: _newLogo == null ? (p['photo_profil_url'] as String?) : null,
          newFile: _newLogo,
          onPick: () async {
            final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
            if (f != null && mounted) setState(() => _newLogo = File(f.path));
          },
        ),
        const SizedBox(height: 12),

        // Bannière
        _SectionTitle2('Bannière'),
        _NetworkOrFilePicker(
          label: 'Bannière (1200×400 min)',
          existingUrl: _newBanniere == null ? (p['banniere_url'] as String?) : null,
          newFile: _newBanniere,
          wide: true,
          onPick: () async {
            final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
            if (f != null && mounted) setState(() => _newBanniere = File(f.path));
          },
        ),
        const SizedBox(height: 12),

        // Photos
        Row(children: [
          _SectionTitle2('Photos du lieu'),
          const Spacer(),
          Text('${_existingPhotos.length - _removedPhotos.length + _newPhotos.length}/5',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Photos existantes
              ..._existingPhotos.asMap().entries.map((e) {
                final removed = _removedPhotos.contains(e.key);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ColorFiltered(
                        colorFilter: removed
                            ? const ColorFilter.mode(Colors.black38, BlendMode.darken)
                            : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                        child: CachedNetworkImage(
                          imageUrl: e.value, width: 90, height: 100, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(top: 4, right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          if (removed) _removedPhotos.remove(e.key);
                          else _removedPhotos.add(e.key);
                        }),
                        child: Container(
                          decoration: BoxDecoration(
                            color: removed ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            removed ? Icons.add : Icons.close,
                            color: Colors.white, size: 16,
                          ),
                        ),
                      ),
                    ),
                  ]),
                );
              }),
              // Nouvelles photos
              ..._newPhotos.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(e.value, width: 90, height: 100, fit: BoxFit.cover),
                  ),
                  Positioned(top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _newPhotos.removeAt(e.key)),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ]),
              )),
              // Bouton ajouter
              if ((_existingPhotos.length - _removedPhotos.length + _newPhotos.length) < 5)
                GestureDetector(
                  onTap: () async {
                    final picks = await ImagePicker().pickMultiImage(imageQuality: 80);
                    if (picks.isNotEmpty && mounted) {
                      setState(() {
                        for (final f in picks) {
                          final total = _existingPhotos.length - _removedPhotos.length + _newPhotos.length;
                          if (total < 5) _newPhotos.add(File(f.path));
                        }
                      });
                    }
                  },
                  child: Container(
                    width: 90, height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_photo_alternate_outlined,
                        color: Colors.grey, size: 30),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Horaires
        _SectionTitle2('Horaires d\'ouverture'),
        ..._horairesFerme.keys.map((j) {
          final ferme = _horairesFerme[j]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(
                width: 82,
                child: Text(_cap(j), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              Transform.scale(
                scale: 0.75,
                alignment: Alignment.centerLeft,
                child: Switch(
                  value: !ferme,
                  onChanged: (v) => setState(() => _horairesFerme[j] = !v),
                  activeColor: _teal,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (!ferme) ...[
                const SizedBox(width: 2),
                _TimeBtn(_horairesDebut[j]!, () => _pickTime(j, true)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('–', style: TextStyle(fontSize: 14)),
                ),
                _TimeBtn(_horairesFin[j]!, () => _pickTime(j, false)),
              ] else ...[
                const SizedBox(width: 4),
                Text('Fermé', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ],
            ]),
          );
        }),
        const SizedBox(height: 20),

        // Espèces
        _SectionTitle2('Espèces acceptées'),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            ('chien', '🐶 Chien'), ('chat', '🐱 Chat'), ('cheval', '🐴 Cheval'),
            ('lapin', '🐰 Lapin'), ('oiseau', '🦜 Oiseau'), ('nac', '🐾 NAC'),
          ].map((e) {
            final sel = _especes.contains(e.$1);
            return FilterChip(
              label: Text(e.$2, style: TextStyle(fontSize: 12,
                  color: sel ? Colors.white : Colors.grey.shade700)),
              selected: sel,
              selectedColor: _teal,
              backgroundColor: Colors.white,
              checkmarkColor: Colors.white,
              side: BorderSide(color: sel ? _teal : Colors.grey.shade300),
              onSelected: (v) => setState(() {
                if (v) _especes.add(e.$1); else _especes.remove(e.$1);
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Contact
        _SectionTitle2('Contact'),
        TextFormField(controller: _telCtrl, keyboardType: TextInputType.phone,
            decoration: _deco('Téléphone professionnel')),
        const SizedBox(height: 10),
        TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
            decoration: _deco('Email de contact')),
        const SizedBox(height: 10),
        TextFormField(controller: _siteCtrl, keyboardType: TextInputType.url,
            decoration: _deco('Site web (optionnel)')),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildConditionsTab() {
    final isHebergement = widget.place['categorie'] == 'hebergement';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isHebergement) ...[
          _BoolRow2('Animaux dans la chambre', _animauxChambre, (v) => setState(() => _animauxChambre = v)),
          _BoolRow2('Espace détente / jardin clôturé', _espaceDetente, (v) => setState(() => _espaceDetente = v)),
          const SizedBox(height: 12),
          _IntField('Supplément/nuit (€)', _fraisNuit, (v) => setState(() => _fraisNuit = v)),
          const SizedBox(height: 8),
          _IntField('Nb animaux max / séjour', _nbAnimauxMax, (v) => setState(() => _nbAnimauxMax = v)),
        ] else ...[
          _BoolRow2('Terrasse disponible', _terrasse, (v) => setState(() => _terrasse = v)),
          _BoolRow2('Animaux acceptés en salle', _animauxSalle, (v) => setState(() => _animauxSalle = v)),
          _BoolRow2('Gamelle d\'eau fournie', _eauFournie, (v) => setState(() => _eauFournie = v)),
          _BoolRow2('Friandises proposées', _friandises, (v) => setState(() => _friandises = v)),
          _BoolRow2('Menu dédié aux animaux', _petMenu, (v) => setState(() => _petMenu = v)),
        ],
      ],
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
    filled: true, fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _teal)),
  );
}

// ─── Section disponibilités (hôtels) ─────────────────────────────────────────

class _DisponibilitesSection extends StatefulWidget {
  final String placeId;
  final int prixDefaut;
  const _DisponibilitesSection({required this.placeId, required this.prixDefaut});

  @override
  State<_DisponibilitesSection> createState() => _DisponibilitesSectionState();
}

class _DisponibilitesSectionState extends State<_DisponibilitesSection> {
  static const _teal = Color(0xFF0C5C6C);
  final _supabase = Supabase.instance.client;
  Map<String, Map<String, dynamic>> _exceptions = {};
  late int _prixDefaut;
  late DateTime _month;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prixDefaut = widget.prixDefaut;
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('place_disponibilites')
          .select()
          .eq('place_id', widget.placeId);
      setState(() {
        _exceptions = {
          for (final d in (data as List))
            d['date'] as String: Map<String, dynamic>.from(d as Map),
        };
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  static String _ds(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _upsert(String dateStr, int prix, bool disponible) async {
    setState(() => _saving = true);
    try {
      if (disponible && prix == _prixDefaut) {
        await _supabase.from('place_disponibilites').delete()
            .eq('place_id', widget.placeId).eq('date', dateStr);
      } else {
        await _supabase.from('place_disponibilites').upsert({
          'place_id': widget.placeId,
          'date': dateStr,
          'prix_override': prix,
          'disponible': disponible,
        }, onConflict: 'place_id,date');
      }
      await _load();
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _applyRange(DateTime start, DateTime end, int prix, bool disponible) async {
    setState(() => _saving = true);
    try {
      final rows = <Map<String, dynamic>>[];
      final delDates = <String>[];
      var d = start;
      while (!d.isAfter(end)) {
        final ds = _ds(d);
        if (disponible && prix == _prixDefaut) {
          delDates.add(ds);
        } else {
          rows.add({'place_id': widget.placeId, 'date': ds, 'prix_override': prix, 'disponible': disponible});
        }
        d = d.add(const Duration(days: 1));
      }
      if (rows.isNotEmpty) {
        await _supabase.from('place_disponibilites').upsert(rows, onConflict: 'place_id,date');
      }
      for (final ds in delDates) {
        await _supabase.from('place_disponibilites').delete()
            .eq('place_id', widget.placeId).eq('date', ds);
      }
      await _load();
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _editPrixDefaut() async {
    final ctrl = TextEditingController(text: _prixDefaut > 0 ? '$_prixDefaut' : '');
    await showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Prix par défaut', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(suffixText: '€/nuit', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              final v = int.tryParse(ctrl.text) ?? 0;
              Navigator.pop(dlg);
              await _supabase.from('petfriendly_places')
                  .update({'prix_nuit_defaut': v}).eq('id', widget.placeId);
              if (mounted) setState(() => _prixDefaut = v);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  void _onDayTap(DateTime day) {
    final dateStr = _ds(day);
    final exc = _exceptions[dateStr];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DaySheet(
        day: day,
        prixDefaut: _prixDefaut,
        currentPrix: exc?['prix_override'] as int? ?? _prixDefaut,
        currentDispo: exc?['disponible'] as bool? ?? true,
        hasException: exc != null,
        onSave: (prix, dispo) => _upsert(dateStr, prix, dispo),
      ),
    );
  }

  void _showPeriodeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PeriodeSheet(
        prixDefaut: _prixDefaut,
        onApply: _applyRange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));

    const monthNames = ['Janvier','Février','Mars','Avril','Mai','Juin',
                        'Juillet','Août','Septembre','Octobre','Novembre','Décembre'];
    final prevMonth = DateTime(_month.year, _month.month - 1, 1);
    final nextMonth = DateTime(_month.year, _month.month + 1, 1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: Column(
        children: [
          // Barre prix défaut + bouton période
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              GestureDetector(
                onTap: _editPrixDefaut,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF0C5C6C).withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Défaut : ${_prixDefaut}€/nuit',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: _teal)),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined, size: 13, color: _teal),
                  ]),
                ),
              ),
              const Spacer(),
              if (_saving)
                const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: _teal, strokeWidth: 2)),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _saving ? null : _showPeriodeSheet,
                icon: const Icon(Icons.date_range_outlined, size: 15),
                label: const Text('Période'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          // Navigation mois
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(
                onPressed: () => setState(() => _month = prevMonth),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(child: Center(child: Text(
                '${monthNames[_month.month - 1]} ${_month.year}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16),
              ))),
              IconButton(
                onPressed: () => setState(() => _month = nextMonth),
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
          ),
          // Légende
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
            child: Row(children: [
              _LegendChip(color: Colors.white, border: Colors.grey.shade300, label: 'Prix défaut'),
              const SizedBox(width: 8),
              _LegendChip(color: const Color(0xFFE8F5E9), border: const Color(0xFF0C5C6C), label: 'Prix modifié'),
              const SizedBox(width: 8),
              _LegendChip(color: Colors.red.shade50, border: Colors.red.shade200, label: 'Indisponible'),
            ]),
          ),
          // Grille calendrier
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
              child: _CalendrierGrid(
                month: _month,
                exceptions: _exceptions,
                prixDefaut: _prixDefaut,
                onDayTap: _onDayTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grille calendrier ────────────────────────────────────────────────────────

class _CalendrierGrid extends StatelessWidget {
  final DateTime month;
  final Map<String, Map<String, dynamic>> exceptions;
  final int prixDefaut;
  final ValueChanged<DateTime>? onDayTap;
  const _CalendrierGrid({
    required this.month, required this.exceptions,
    required this.prixDefaut, this.onDayTap,
  });

  static String _ds(DateTime d) =>
      '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final startOffset = firstDay.weekday - 1;
    final today = DateTime.now();

    return Column(
      children: [
        Row(
          children: ['L','M','M','J','V','S','D'].map((d) => Expanded(
            child: Center(child: Text(d,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500))),
          )).toList(),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, childAspectRatio: 0.82,
          ),
          itemCount: startOffset + lastDay.day,
          itemBuilder: (_, i) {
            if (i < startOffset) return const SizedBox();
            final day = DateTime(month.year, month.month, i - startOffset + 1);
            final dateStr = _ds(day);
            final exc = exceptions[dateStr];
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
              bg = const Color(0xFFE8F5E9); borderColor = const Color(0xFF0C5C6C); textColor = const Color(0xFF0C5C6C);
            } else {
              bg = Colors.white; borderColor = Colors.grey.shade200; textColor = Colors.black87;
            }

            return GestureDetector(
              onTap: (isPast || onDayTap == null) ? null : () => onDayTap!(day),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isToday ? const Color(0xFF0C5C6C) : borderColor,
                    width: isToday ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${day.day}', style: TextStyle(
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13, color: textColor,
                    )),
                    if (!isPast)
                      Text(
                        isUnavail ? '✖' : (prix > 0 ? '$prix€' : ''),
                        style: TextStyle(fontSize: 9, color: textColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─── Légende ──────────────────────────────────────────────────────────────────

class _LegendChip extends StatelessWidget {
  final Color color, border;
  final String label;
  const _LegendChip({required this.color, required this.border, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 12, height: 12,
      decoration: BoxDecoration(color: color, border: Border.all(color: border), borderRadius: BorderRadius.circular(3)),
    ),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);
}

// ─── Sheet : modifier un jour ─────────────────────────────────────────────────

class _DaySheet extends StatefulWidget {
  final DateTime day;
  final int prixDefaut;
  final int currentPrix;
  final bool currentDispo;
  final bool hasException;
  final Future<void> Function(int prix, bool dispo) onSave;
  const _DaySheet({
    required this.day, required this.prixDefaut, required this.currentPrix,
    required this.currentDispo, required this.hasException, required this.onSave,
  });

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  static const _teal = Color(0xFF0C5C6C);
  late bool _dispo;
  late final TextEditingController _prixCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dispo = widget.currentDispo;
    _prixCtrl = TextEditingController(
        text: widget.currentPrix > 0 ? '${widget.currentPrix}' : '');
  }

  @override
  void dispose() {
    _prixCtrl.dispose();
    super.dispose();
  }

  String _fmtDay(DateTime dt) {
    const months = ['janvier','février','mars','avril','mai','juin',
                    'juillet','août','septembre','octobre','novembre','décembre'];
    const dayNames = ['lundi','mardi','mercredi','jeudi','vendredi','samedi','dimanche'];
    return '${dayNames[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Text(_fmtDay(widget.day),
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Text('Disponible', style: TextStyle(fontSize: 14))),
            Switch(value: _dispo, onChanged: (v) => setState(() => _dispo = v), activeThumbColor: _teal),
          ]),
          if (_dispo) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _prixCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Prix par nuit (€)',
                hintText: 'Défaut : ${widget.prixDefaut}€',
                suffixText: '€',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _teal),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : () async {
                setState(() => _saving = true);
                final prix = int.tryParse(_prixCtrl.text) ?? widget.prixDefaut;
                await widget.onSave(prix, _dispo);
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          if (widget.hasException) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _saving ? null : () async {
                  setState(() => _saving = true);
                  await widget.onSave(widget.prixDefaut, true);
                  if (mounted) Navigator.pop(context);
                },
                child: Text('Restaurer au tarif par défaut (${widget.prixDefaut}€)',
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Sheet : appliquer à une période ─────────────────────────────────────────

class _PeriodeSheet extends StatefulWidget {
  final int prixDefaut;
  final Future<void> Function(DateTime start, DateTime end, int prix, bool dispo) onApply;
  const _PeriodeSheet({required this.prixDefaut, required this.onApply});

  @override
  State<_PeriodeSheet> createState() => _PeriodeSheetState();
}

class _PeriodeSheetState extends State<_PeriodeSheet> {
  static const _teal = Color(0xFF0C5C6C);
  DateTime? _start;
  DateTime? _end;
  bool _dispo = true;
  late final TextEditingController _prixCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prixCtrl = TextEditingController(
        text: widget.prixDefaut > 0 ? '${widget.prixDefaut}' : '');
  }

  @override
  void dispose() {
    _prixCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime dt) {
    const months = ['jan.','fév.','mar.','avr.','mai','juin','juil.','août','sep.','oct.','nov.','déc.'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final canApply = _start != null && _end != null && !_end!.isBefore(_start!);
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          const Text('Appliquer à une période',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (p != null && mounted) setState(() => _start = p);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal, side: const BorderSide(color: _teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_start == null ? 'Date début' : _fmtDate(_start!),
                  overflow: TextOverflow.ellipsis),
            )),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('→')),
            Expanded(child: OutlinedButton(
              onPressed: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: _start ?? DateTime.now(),
                  firstDate: _start ?? DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (p != null && mounted) setState(() => _end = p);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal, side: const BorderSide(color: _teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_end == null ? 'Date fin' : _fmtDate(_end!),
                  overflow: TextOverflow.ellipsis),
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Text('Disponible', style: TextStyle(fontSize: 14))),
            Switch(value: _dispo, onChanged: (v) => setState(() => _dispo = v), activeThumbColor: _teal),
          ]),
          if (_dispo) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _prixCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Prix par nuit (€)',
                suffixText: '€',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _teal),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (canApply && !_saving) ? () async {
                setState(() => _saving = true);
                final prix = int.tryParse(_prixCtrl.text) ?? widget.prixDefaut;
                await widget.onApply(_start!, _end!, prix, _dispo);
                if (mounted) Navigator.pop(context);
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Appliquer', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets helpers locaux ───────────────────────────────────────────────────

class _SectionTitle2 extends StatelessWidget {
  final String title;
  const _SectionTitle2(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title,
        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
  );
}

class _NetworkOrFilePicker extends StatelessWidget {
  final String label;
  final String? existingUrl;
  final File? newFile;
  final bool wide;
  final VoidCallback onPick;
  const _NetworkOrFilePicker({
    required this.label,
    required this.existingUrl,
    required this.newFile,
    required this.onPick,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = newFile != null || (existingUrl != null && existingUrl!.isNotEmpty);
    return GestureDetector(
      onTap: onPick,
      child: Container(
        width: double.infinity, height: wide ? 100 : 80,
        decoration: BoxDecoration(
          color: hasImage ? null : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasImage ? Colors.transparent : Colors.grey.shade300),
          image: hasImage
              ? DecorationImage(
                  image: newFile != null
                      ? FileImage(newFile!) as ImageProvider
                      : CachedNetworkImageProvider(existingUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: hasImage
            ? const Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined, color: Colors.grey),
                  const SizedBox(height: 4),
                  Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
      ),
    );
  }
}

Widget _TimeBtn(String time, VoidCallback onTap) => GestureDetector(
  onTap: onTap,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
    ),
    child: Text(time, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
  ),
);

Widget _BoolRow2(String label, bool value, ValueChanged<bool> onChanged) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(children: [
    Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
    Switch(value: value, onChanged: onChanged, activeThumbColor: const Color(0xFF0C5C6C)),
  ]),
);

Widget _IntField(String label, int value, ValueChanged<int> onChanged) {
  final ctrl = TextEditingController(text: value == 0 ? '' : '$value');
  return TextFormField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(fontSize: 12),
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF0C5C6C))),
    ),
    onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
  );
}
