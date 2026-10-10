import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart' show speciesIcon, speciesColor, speciesLabel;
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/services/chip_scanner_service.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:flutter/material.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MesAnimauxAssoPage extends StatefulWidget {
  final String initialFilterStatut;
  const MesAnimauxAssoPage({super.key, this.initialFilterStatut = 'tous'});
  @override
  State<MesAnimauxAssoPage> createState() => _MesAnimauxAssoPageState();
}

class _MesAnimauxAssoPageState extends State<MesAnimauxAssoPage> with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;

  static const _teal = Color(0xFF0C5C6C);

  late final TabController _tabController;
  List<Map<String, dynamic>> _animaux = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  late String _filterStatut = widget.initialFilterStatut;
  String _search = '';
  String? _myUid;

  // "Ancien" = l'animal a un nouveau propriétaire (adopté/transféré) ou est décédé.
  // "Détenus" = tout le reste (en_soin, disponible — et en_fa n'est plus un statut,
  // c'est un état indépendant porté par fa_id, un animal en FA reste "détenu").
  // 'sorti' = cédé via la fiche de cession (contrat / certificat).
  static const _anciensValues = {'adopte', 'transfere', 'sorti', 'decede'};

  static const _detenusStatuts = [
    ('tous', 'Tous', Colors.grey),
    ('en_soin', 'En soin', Colors.orange),
    ('disponible', 'Disponible', Color(0xFF6E9E57)),
    ('en_fa', 'En FA', Colors.purple),
  ];

  static const _anciensStatuts = [
    ('tous', 'Tous', Colors.grey),
    ('adopte', 'Adopté', Color(0xFF0C5C6C)),
    ('transfere', 'Transféré', Colors.blue),
    ('sorti', 'Cédé', Colors.amber),
    ('decede', 'Décédé', Colors.red),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (_anciensValues.contains(widget.initialFilterStatut)) _tabController.index = 1;
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      setState(() { _filterStatut = 'tous'; _applyFilters(); });
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _myUid = uid;
    try {
      const cols = 'id,nom,espece,race,sexe,statut,fa_id,date_naissance,age_estime,photo_url,date_entree,date_sortie,uid_eleveur,identification';
      final owned = List<Map<String, dynamic>>.from(
        await _supa.from('animaux').select(cols)
            .eq('uid_eleveur', uid).eq('is_association', true).order('nom') as List,
      );

      // Cessions reçues : un même uid Firebase peut porter plusieurs profils
      // (élevage + association). On ne garde que les animaux réellement reçus
      // par CE profil (animaux_proprietes.profile_id_proprio), sinon un animal
      // cédé au profil élevage apparaît aussi dans l'association.
      final activeProfileId = User_Info.activeProfileId;
      List<Map<String, dynamic>> received = [];
      final fermes = <String>{};
      if (activeProfileId.isNotEmpty) {
        final migrated = await _supa.from('animaux_proprietes')
            .select('animal_id')
            .eq('uid_proprio', uid)
            .not('profile_id_proprio', 'is', null)
            .limit(1);
        if ((migrated as List).isNotEmpty) {
          final ownRows = List<Map<String, dynamic>>.from(await _supa.from('animaux_proprietes')
              .select('animal_id, date_fin')
              .eq('uid_proprio', uid)
              .eq('profile_id_proprio', activeProfileId) as List);
          final ids = ownRows
              .map((r) => r['animal_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
          final ouverts = ownRows.where((r) => r['date_fin'] == null)
              .map((r) => r['animal_id']?.toString() ?? '').toSet();
          fermes.addAll(ids.where((id) => !ouverts.contains(id)));
          if (ids.isNotEmpty) {
            received = List<Map<String, dynamic>>.from(
              await _supa.from('animaux').select(cols)
                  .inFilter('id', ids).order('date_sortie', ascending: false) as List,
            );
          }
        } else {
          // Migration profile_id_proprio pas encore jouée → rétrocompat sur l'uid seul
          received = List<Map<String, dynamic>>.from(
            await _supa.from('animaux').select(cols)
                .eq('uid_acquereur', uid).order('date_sortie', ascending: false) as List,
          );
        }
      } else {
        received = List<Map<String, dynamic>>.from(
          await _supa.from('animaux').select(cols)
              .eq('uid_acquereur', uid).order('date_sortie', ascending: false) as List,
        );
      }

      final ownedIds = owned.map((a) => a['id']).toSet();
      received = received.where((a) => !ownedIds.contains(a['id'])).toList();
      // Cédé puis repris par une autre structure : la fiche porte le statut
      // du nouveau détenteur (« disponible »…) → affiché « Transféré » ici,
      // en lecture seule.
      for (final a in received) {
        if (!fermes.contains(a['id']?.toString())) continue;
        a['_ancien'] = true;
        if (!_anciensValues.contains(a['statut'])) a['statut'] = 'transfere';
      }

      if (mounted) {
        setState(() {
          _animaux = [...owned, ...received];
          _applyFilters();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Statut rapide : En soin / Disponible directement ; sortie (adopté,
  /// transféré, décédé) → fiche, qui inscrit la sortie au registre.
  Future<void> _changerStatut(Map<String, dynamic> a, bool isCession) async {
    final actuel = a['statut']?.toString() ?? 'en_soin';
    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Statut de ${a['nom'] ?? "l'animal"}",
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          for (final e in const [
            ('en_soin', 'En soin', Colors.orange, Icons.healing_outlined),
            ('disponible', "Disponible à l'adoption", Color(0xFF6E9E57), Icons.favorite_outline),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.$4, color: e.$3),
              title: Text(e.$2, style: TextStyle(fontFamily: 'Galey', fontWeight: e.$1 == actuel ? FontWeight.w700 : FontWeight.w500)),
              trailing: e.$1 == actuel ? Icon(Icons.check, color: e.$3) : null,
              onTap: () => Navigator.pop(ctx, e.$1),
            ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: Color(0xFF0C5C6C)),
            title: const Text('Adopté, transféré ou décédé…', style: TextStyle(fontFamily: 'Galey')),
            subtitle: const Text('Ouvre la fiche pour inscrire la sortie au registre',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
            onTap: () => Navigator.pop(ctx, '_fiche'),
          ),
        ]),
      )),
    );
    if (choix == null || choix == actuel || !mounted) return;
    if (choix == '_fiche') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalFichePage(
        animalId: a['id'], initialData: a, isAssociation: true)));
    } else {
      try {
        await Supabase.instance.client.from('animaux').update({'statut': choix}).eq('id', a['id']);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
    _load();
  }

  Future<void> _deleteAnimal(String id) async {
    try {
      await _supa.from('animaux').delete().eq('id', id);
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression : $e')),
        );
      }
    }
  }

  void _applyFilters() {
    final isDetenus = _tabController.index == 0;
    _filtered = _animaux.where((a) {
      final statut = a['statut']?.toString() ?? 'en_soin';
      final matchTab = isDetenus ? !_anciensValues.contains(statut) : _anciensValues.contains(statut);
      if (!matchTab) return false;
      final matchStatut = _filterStatut == 'tous'
          || (_filterStatut == 'en_fa' ? a['fa_id'] != null : statut == _filterStatut);
      final matchSearch = _search.isEmpty ||
          (a['nom']?.toString().toLowerCase().contains(_search.toLowerCase()) ?? false) ||
          (a['espece']?.toString().toLowerCase().contains(_search.toLowerCase()) ?? false) ||
          (a['race']?.toString().toLowerCase().contains(_search.toLowerCase()) ?? false) ||
          // Numéro de puce saisi à la main (espaces ignorés)
          (a['identification']?.toString().replaceAll(' ', '').contains(_search.replaceAll(' ', '')) ?? false);
      return matchStatut && matchSearch;
    }).toList();
  }

  String _age(dynamic dateNaissance, [dynamic ageEstime]) {
    if (dateNaissance == null) return '';
    try {
      final dn = DateTime.parse(dateNaissance.toString());
      final diff = DateTime.now().difference(dn);
      final mois = (diff.inDays / 30).floor();
      final suffixe = ageEstime == true ? ' (est.)' : '';
      if (mois < 12) return '${mois}m$suffixe';
      return '${(mois / 12).floor()}a$suffixe';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuts = _tabController.index == 0 ? _detenusStatuts : _anciensStatuts;
    return Scaffold(
      backgroundColor: kDashFond,
      appBar: AppBar(
        backgroundColor: _teal,
        surfaceTintColor: _teal,
        title: const Text('Mes animaux',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
          tabs: const [Tab(text: 'Nos protégés'), Tab(text: 'Anciens')],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sensors_rounded),
            tooltip: 'Scanner une puce',
            onPressed: () {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) ChipScannerService.scanFromAssociation(context, uid);
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => const AnimalFichePage(isAssociation: true),
              ));
              _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Recherche + statut (liste déroulante, comme l'éleveur)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(children: [
              TextField(
                onChanged: (v) => setState(() { _search = v; _applyFilters(); }),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Rechercher par nom, race ou n° de puce',
                  hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500, fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kDashBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kDashBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _teal)),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('statut_${_tabController.index}'),
                initialValue: statuts.any((s) => s.$1 == _filterStatut) ? _filterStatut : statuts.first.$1,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14.5, color: kDashInk),
                decoration: InputDecoration(
                  labelText: 'Statut',
                  labelStyle: const TextStyle(fontFamily: 'Galey', color: kDashMuted),
                  isDense: true, filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kDashBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kDashBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _teal)),
                ),
                items: [
                  for (final st in statuts)
                    DropdownMenuItem(value: st.$1, child: Row(children: [
                      if (st.$1 != 'tous') ...[
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: st.$3, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                      ],
                      Text(st.$1 == 'tous' ? 'Tous les statuts' : st.$2),
                    ])),
                ],
                onChanged: (v) => setState(() { _filterStatut = v ?? 'tous'; _applyFilters(); }),
              ),
            ]),
          ),
          // Liste
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _teal))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('Aucun animal trouvé.',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 14.5, color: kDashMuted)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.68,
                        ),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final a = _filtered[i];
                          final isCession = _myUid != null && a['uid_eleveur'] != _myUid;
                          return _AnimalCard(
                            animal: a,
                            age: _age(a['date_naissance'], a['age_estime']),
                            isCession: isCession,
                            onDelete: isCession ? null : () => _deleteAnimal(a['id'].toString()),
                            onStatut: isCession ? null : () => _changerStatut(a, isCession),
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => AnimalFichePage(
                                  animalId: a['id'],
                                  initialData: a,
                                  isAssociation: true,
                                  readOnly: a['_ancien'] == true,
                                  eleveurUidOverride: isCession ? a['uid_eleveur'] as String? : null,
                                ),
                              ));
                              _load();
                            },
                            onAddAnnonce: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => CreateAnnonceAssoPage(
                                animalId: a['id']?.toString(),
                                initialAnimal: a,
                              ),
                            )),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final String age;
  final bool isCession;
  final VoidCallback onTap;
  final VoidCallback onAddAnnonce;
  final VoidCallback? onDelete;
  final VoidCallback? onStatut;

  const _AnimalCard({
    required this.animal,
    required this.age,
    required this.onTap,
    this.onStatut,
    required this.onAddAnnonce,
    this.isCession = false,
    this.onDelete,
  });

  static const _statutColors = <String, Color>{
    'en_soin':   Colors.orange,
    'disponible': Color(0xFF6E9E57),
    'en_fa':     Colors.purple,
    'adopte':    Color(0xFF0C5C6C),
    'transfere': Colors.blue,
    'sorti':     Colors.amber,
    'decede':    Colors.red,
    'present':   Color(0xFF6E9E57),
  };

  static const _statutLabels = <String, String>{
    'en_soin':   'En soin',
    'disponible': 'Disponible',
    'en_fa':     'En FA',
    'adopte':    'Adopté',
    'transfere': 'Transféré',
    'sorti':     'Cédé',
    'decede':    'Décédé',
    'present':   'Présent',
  };

  @override
  Widget build(BuildContext context) {
    final photo  = animal['photo_url']?.toString() ?? '';
    final nom    = animal['nom']?.toString()    ?? 'Sans nom';
    final espece = animal['espece']?.toString() ?? '';
    final race   = animal['race']?.toString()   ?? '';
    final sexe   = animal['sexe']?.toString()   ?? '';
    final statut = animal['statut']?.toString() ?? 'en_soin';
    final enFa   = animal['fa_id'] != null;
    final statutColor = _statutColors[statut] ?? Colors.grey;
    final statutLabel = _statutLabels[statut] ?? statut;
    final specColor   = speciesColor(espece);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete == null ? null : () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Text(nom, style: const TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 6),
              const Divider(),
              if (onStatut != null)
                ListTile(
                  leading: const Icon(Icons.swap_vert_circle_outlined, color: Color(0xFF0C5C6C)),
                  title: const Text('Changer le statut',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Color(0xFF0C5C6C))),
                  onTap: () {
                    Navigator.pop(context);
                    onStatut!();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Supprimer',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 15,
                        color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Text('Supprimer cet animal ?',
                          style: TextStyle(fontFamily: 'Galey',
                              fontWeight: FontWeight.w700)),
                      content: Text(
                          'La fiche de $nom sera définitivement supprimée.',
                          style: const TextStyle(fontFamily: 'Galey')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler',
                              style: TextStyle(fontFamily: 'Galey')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Supprimer',
                              style: TextStyle(fontFamily: 'Galey',
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) onDelete!();
                },
              ),
            ]),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kDashBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo carrée
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    photo.isNotEmpty
                        ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: specColor.withValues(alpha: 0.12),
                              child: Center(child: speciesIcon(espece, 44, specColor))))
                        : Container(
                            color: specColor.withValues(alpha: 0.12),
                            child: Center(child: speciesIcon(espece, 44, specColor))),
                    // Statut badge
                    Positioned(
                      top: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statutColor.withValues(alpha: 0.35)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: statutColor, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text(statutLabel, style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                              fontWeight: FontWeight.w600, color: statutColor)),
                        ]),
                      ),
                    ),
                    // Badge En FA — indépendant du statut, un animal peut être
                    // à la fois "Disponible" et "En FA" en même temps.
                    if (enFa)
                      Positioned(
                        top: 6, left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                          ),
                          child: const Text('En FA',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                                  fontWeight: FontWeight.w600, color: Color(0xFF7E22CE))),
                        ),
                      ),
                    if (isCession)
                      Positioned(
                        bottom: 6, left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: kDashBorder),
                          ),
                          child: const Text('Cession',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                                  fontWeight: FontWeight.w600, color: kDashInk)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Infos
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 14, color: Color(0xFF1F2A2E)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (race.isNotEmpty)
                  Text(race,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Row(children: [
                  _Chip(speciesLabel(espece), specColor),
                  if (sexe.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _Chip(sexe == 'male' ? 'Mâle' : 'Femelle', const Color(0xFF5F9EAA)),
                  ],
                  if (statut == 'disponible') ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onAddAnnonce,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6E9E57).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF6E9E57), width: 0.7),
                        ),
                        child: const Text('+ Adopter',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 9,
                                fontWeight: FontWeight.w700, color: Color(0xFF6E9E57))),
                      ),
                    ),
                  ],
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label,
        style: TextStyle(fontFamily: 'Galey', fontSize: 10,
            fontWeight: FontWeight.w600, color: color)),
  );
}
