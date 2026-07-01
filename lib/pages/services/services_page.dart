import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/services/service_list_page.dart';
import 'package:PetsMatch/pages/services/service_detail_page.dart';
import 'package:PetsMatch/pages/services/annuaire_subcategory_page.dart';

const _teal = Color(0xFF0C5C6C);
const _bg = Color(0xFFF8F8F8);

// ── Sous-catégories par domaine ───────────────────────────────────────────────

final _santeItems = [
  const AnnuaireSubItem(
    label: 'Vétérinaires',
    subtitle: 'Consultations, urgences, chirurgie',
    icon: Icons.local_hospital_outlined,
    color: Color(0xFF2E7D5E),
    catProValues: ['sante', 'veterinaire'],
  ),
  const AnnuaireSubItem(
    label: 'Ostéopathes',
    subtitle: 'Manipulations ostéopathiques pour animaux',
    icon: Icons.self_improvement_outlined,
    color: Color(0xFF2E7D5E),
    catProValues: ['sante', 'osteo'],
  ),
  const AnnuaireSubItem(
    label: 'Kinésithérapeutes',
    subtitle: 'Rééducation fonctionnelle animale',
    icon: Icons.fitness_center_outlined,
    color: Color(0xFF2E7D5E),
    catProValues: ['sante', 'kine'],
  ),
  const AnnuaireSubItem(
    label: 'Maréchal-ferrant',
    subtitle: 'Soins des sabots et ferrure',
    icon: Icons.hardware_outlined,
    color: Color(0xFF558B2F),
    catProValues: ['marechal_ferrant'],
  ),
  const AnnuaireSubItem(
    label: 'Dentiste équin',
    subtitle: 'Soins dentaires pour chevaux',
    icon: Icons.medical_information_outlined,
    color: Color(0xFF558B2F),
    catProValues: ['sante', 'dentiste_equin'],
  ),
];

final _educationItems = [
  const AnnuaireSubItem(
    label: 'Éducateurs canins & félins',
    subtitle: 'Apprentissage, obéissance et socialisation',
    icon: Icons.school_outlined,
    color: Color(0xFFE65100),
    catProValues: ['education', 'educateur'],
  ),
  const AnnuaireSubItem(
    label: 'Comportementalistes',
    subtitle: 'Troubles du comportement, anxiété, agressivité',
    icon: Icons.psychology_outlined,
    color: Color(0xFFBF360C),
    catProValues: ['comportementaliste'],
  ),
];

final _gardeItems = [
  const AnnuaireSubItem(
    label: 'Pet-sitters',
    subtitle: 'Garde à domicile chez vous ou chez eux',
    icon: Icons.home_outlined,
    color: Color(0xFFF57C00),
    catProValues: ['pet_sitter', 'garde'],
  ),
  const AnnuaireSubItem(
    label: 'Promeneurs',
    subtitle: 'Sorties quotidiennes et balades',
    icon: Icons.directions_walk_outlined,
    color: Color(0xFFE65100),
    catProValues: ['promeneur'],
  ),
  const AnnuaireSubItem(
    label: 'Pensions',
    subtitle: 'Hébergement gardé en établissement',
    icon: Icons.business_outlined,
    color: Color(0xFFF57C00),
    catProValues: ['pension'],
  ),
];

final _alimentationItems = [
  const AnnuaireSubItem(
    label: 'Animaleries',
    subtitle: 'Magasins spécialisés alimentation & accessoires',
    icon: Icons.store_outlined,
    color: Color(0xFF1565C0),
    catProValues: ['animalerie', 'alimentation'],
  ),
  const AnnuaireSubItem(
    label: 'Nutritionnistes animaliers',
    subtitle: 'Conseils en alimentation adaptée & régimes',
    icon: Icons.restaurant_outlined,
    color: Color(0xFF1976D2),
    catProValues: ['nutrition', 'nutritionniste'],
  ),
];

final _transportItems = [
  const AnnuaireSubItem(
    label: 'Taxi animalier',
    subtitle: 'Transport spécialisé pour vos animaux',
    icon: Icons.local_taxi_outlined,
    color: Color(0xFF00838F),
    catProValues: ['taxi_animalier', 'transport'],
  ),
  const AnnuaireSubItem(
    label: 'VTC & Taxi acceptant les animaux',
    subtitle: 'Chauffeurs qui acceptent vos compagnons',
    icon: Icons.directions_car_outlined,
    color: Color(0xFF00695C),
    catProValues: ['transport', 'vtc'],
  ),
  const AnnuaireSubItem(
    label: 'Ambulance vétérinaire',
    subtitle: 'Transport médicalisé pour urgences',
    icon: Icons.emergency_outlined,
    color: Color(0xFFC62828),
    catProValues: ['ambulance_vet', 'transport'],
  ),
];

final _boutiqueItems = [
  const AnnuaireSubItem(
    label: 'Boutiques spécialisées',
    subtitle: 'Petites boutiques professionnelles vérifiées',
    icon: Icons.shopping_bag_outlined,
    color: Color(0xFF00695C),
    catProValues: ['boutique'],
  ),
  const AnnuaireSubItem(
    label: 'Créateurs & artisans',
    subtitle: 'Accessoires faits main, personnalisation',
    icon: Icons.palette_outlined,
    color: Color(0xFF6A1B9A),
    catProValues: ['artisan', 'createur'],
  ),
];

// ── Categories grid ───────────────────────────────────────────────────────────

class _AnnuaireCategory {
  final IconData icon;
  final String label;
  final Color color;
  final List<String> catProValues;
  final List<AnnuaireSubItem>? subItems;

  const _AnnuaireCategory({
    required this.icon,
    required this.label,
    required this.color,
    required this.catProValues,
    this.subItems,
  });
}

// ── Main page ─────────────────────────────────────────────────────────────────

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  final _supa = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _verifiedPros = [];
  bool _loadingPros = false;

  static final _categories = <_AnnuaireCategory>[
    _AnnuaireCategory(
      icon: Icons.medical_services_outlined,
      label: 'Santé\n& bien-être',
      color: const Color(0xFF2E7D5E),
      catProValues: const ['sante', 'veterinaire', 'osteo', 'kine', 'marechal_ferrant'],
      subItems: _santeItems,
    ),
    _AnnuaireCategory(
      icon: Icons.school_outlined,
      label: 'Éducation\n& comportement',
      color: const Color(0xFFE65100),
      catProValues: const ['education', 'educateur', 'comportementaliste'],
      subItems: _educationItems,
    ),
    _AnnuaireCategory(
      icon: Icons.home_outlined,
      label: 'Garde\n& hébergement',
      color: const Color(0xFFF57C00),
      catProValues: const ['pension', 'garde', 'pet_sitter', 'promeneur'],
      subItems: _gardeItems,
    ),
    _AnnuaireCategory(
      icon: Icons.content_cut,
      label: 'Toilettage\n& soins',
      color: const Color(0xFFC62828),
      catProValues: const ['toilettage', 'toiletteur'],
    ),
    _AnnuaireCategory(
      icon: Icons.set_meal_outlined,
      label: 'Alimentation',
      color: const Color(0xFF1565C0),
      catProValues: const ['alimentation', 'animalerie', 'nutrition'],
      subItems: _alimentationItems,
    ),
    _AnnuaireCategory(
      icon: Icons.directions_car_outlined,
      label: 'Transport',
      color: const Color(0xFF00838F),
      catProValues: const ['transport', 'taxi_animalier', 'ambulance_vet', 'vtc'],
      subItems: _transportItems,
    ),
    _AnnuaireCategory(
      icon: Icons.photo_camera_outlined,
      label: 'Photographes',
      color: const Color(0xFFAD1457),
      catProValues: const ['photographe'],
    ),
    _AnnuaireCategory(
      icon: Icons.shopping_bag_outlined,
      label: 'Boutiques\n& Créateurs',
      color: const Color(0xFF6A1B9A),
      catProValues: const ['boutique', 'artisan', 'createur'],
      subItems: _boutiqueItems,
    ),
    _AnnuaireCategory(
      icon: Icons.shield_outlined,
      label: 'Assurances\n& juridique',
      color: const Color(0xFF1E3A5F),
      catProValues: const ['assurance', 'juridique'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadVerifiedPros();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVerifiedPros() async {
    if (_loadingPros) return;
    setState(() => _loadingPros = true);
    try {
      final rows = await _supa
          .from('user_profiles')
          .select(
              'id, uid, nom, profile_type, profession_pro, avatar_url, ville_pro, accept_new_clients')
          .inFilter('statut_pro', ['actif', 'validated'])
          .not('profile_type', 'in', '(eleveur,association)')
          .order('updated_at', ascending: false)
          .limit(12);
      if (mounted) {
        setState(() {
          _verifiedPros = (rows as List).cast<Map<String, dynamic>>();
          _loadingPros = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPros = false);
    }
  }

  void _openCategory(_AnnuaireCategory cat) {
    if (cat.subItems != null && cat.subItems!.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnnuaireSubCategoryPage(
            title: cat.label.replaceAll('\n', ' '),
            color: cat.color,
            icon: cat.icon,
            items: cat.subItems!,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceListPage(
            categoryLabel: cat.label.replaceAll('\n', ' '),
            categoryColor: cat.color,
            categoryIcon: cat.icon,
            catProValues: cat.catProValues,
          ),
        ),
      );
    }
  }

  void _openSearch() {
    final query = _searchCtrl.text.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceListPage(
          categoryLabel: query.isEmpty
              ? 'Tous les professionnels'
              : 'Résultats : "$query"',
          categoryColor: _teal,
          categoryIcon: Icons.search,
          catProValues: const [],
          searchQuery: query.isEmpty ? null : query,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: canPop
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
            title: const Text(
              'Annuaire des professionnels',
              style: TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ),
          SliverToBoxAdapter(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Barre de recherche (sans bouton Filtres) ──────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: GestureDetector(
            onTap: _openSearch,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(Icons.search, color: Colors.grey.shade400, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Rechercher un professionnel…',
                        hintStyle: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 13,
                            color: Colors.grey.shade400),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onSubmitted: (_) => _openSearch(),
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
        ),

        // ── Catégories ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              const Text('Catégories',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: Color(0xFF1E2025))),
              const Spacer(),
              GestureDetector(
                onTap: _openSearch,
                child: Row(children: [
                  Text('Voir tout',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: Colors.grey.shade500),
                ]),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (context, index) => _CategoryTile(
                cat: _categories[index], onTap: _openCategory),
          ),
        ),

        // ── Professionnels vérifiés (sans "Voir tout") ────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 28, 16, 12),
          child: Text('Professionnels vérifiés',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: Color(0xFF1E2025))),
        ),

        if (_loadingPros)
          const SizedBox(
            height: 220,
            child: Center(
                child:
                    CircularProgressIndicator(color: _teal, strokeWidth: 2)),
          )
        else if (_verifiedPros.isEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Text(
              'Aucun professionnel disponible pour le moment.',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 13,
                  color: Colors.grey.shade500),
            ),
          )
        else
          SizedBox(
            height: 230,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _verifiedPros.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _ProCard(
                pro: _verifiedPros[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServiceDetailPage(
                      proUid: _verifiedPros[i]['uid']?.toString() ?? '',
                      categoryLabel: labelForType(
                          _verifiedPros[i]['profile_type']?.toString() ?? ''),
                      categoryColor: colorForType(
                          _verifiedPros[i]['profile_type']?.toString() ?? ''),
                      profileTableId: _verifiedPros[i]['id']?.toString(),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ── Bannière vérification ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _teal.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_outlined,
                      color: _teal, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Des professionnels vérifiés',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: _teal)),
                      SizedBox(height: 3),
                      Text(
                        'Tous les professionnels de notre annuaire sont vérifiés par notre équipe.',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 12,
                            color: Color(0xFF444444)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String labelForType(String type) => switch (type) {
        'sante' || 'veterinaire' => 'Santé & bien-être',
        'osteo' => 'Ostéopathe',
        'kine' => 'Kinésithérapeute',
        'marechal_ferrant' => 'Maréchal-ferrant',
        'dentiste_equin' => 'Dentiste équin',
        'education' || 'educateur' => 'Éducateur',
        'comportementaliste' => 'Comportementaliste',
        'pension' => 'Pension',
        'pet_sitter' || 'garde' => 'Pet-sitter',
        'promeneur' => 'Promeneur',
        'toilettage' || 'toiletteur' => 'Toilettage & soins',
        'alimentation' || 'animalerie' => 'Animalerie',
        'nutrition' || 'nutritionniste' => 'Nutritionniste',
        'transport' || 'taxi_animalier' || 'vtc' => 'Transport',
        'ambulance_vet' => 'Ambulance vétérinaire',
        'photographe' => 'Photographe',
        'boutique' => 'Boutique',
        'artisan' || 'createur' => 'Créateur & artisan',
        'assurance' => 'Assurance',
        'juridique' => 'Juridique',
        _ => 'Professionnel',
      };

  static Color colorForType(String type) => switch (type) {
        'sante' || 'veterinaire' || 'osteo' || 'kine' => const Color(0xFF2E7D5E),
        'marechal_ferrant' || 'dentiste_equin' => const Color(0xFF558B2F),
        'education' || 'educateur' => const Color(0xFFE65100),
        'comportementaliste' => const Color(0xFFBF360C),
        'pension' || 'pet_sitter' || 'garde' || 'promeneur' => const Color(0xFFF57C00),
        'toilettage' || 'toiletteur' => const Color(0xFFC62828),
        'alimentation' || 'animalerie' || 'nutrition' => const Color(0xFF1565C0),
        'transport' || 'taxi_animalier' || 'vtc' => const Color(0xFF00838F),
        'ambulance_vet' => const Color(0xFFC62828),
        'photographe' => const Color(0xFFAD1457),
        'boutique' || 'artisan' || 'createur' => const Color(0xFF6A1B9A),
        'assurance' || 'juridique' => const Color(0xFF1E3A5F),
        _ => _teal,
      };
}

// ── Category tile (3-col grid) ────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final _AnnuaireCategory cat;
  final void Function(_AnnuaireCategory) onTap;

  const _CategoryTile({required this.cat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasSubcategories = cat.subItems != null && cat.subItems!.isNotEmpty;
    return GestureDetector(
      onTap: () => onTap(cat),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Center(
                        child: Icon(cat.icon, color: cat.color, size: 24)),
                    if (hasSubcategories)
                      Positioned(
                        right: 3,
                        top: 3,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: cat.color,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chevron_right,
                              size: 8, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cat.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E2025)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pro card (horizontal scroll) ─────────────────────────────────────────────

class _ProCard extends StatelessWidget {
  final Map<String, dynamic> pro;
  final VoidCallback onTap;

  const _ProCard({required this.pro, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nom = pro['nom']?.toString() ?? '';
    final type = pro['profile_type']?.toString() ?? '';
    final profLabel = _ServicesPageState.labelForType(type);
    final color = _ServicesPageState.colorForType(type);
    final photoUrl = pro['avatar_url']?.toString() ?? '';
    final ville = pro['ville_pro']?.toString() ?? '';
    final acceptNew = pro['accept_new_clients'] as bool? ?? true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Stack(
                children: [
                  if (photoUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: photoUrl,
                      width: 160,
                      height: 120,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _placeholder(color),
                    )
                  else
                    _placeholder(color),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.88),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.favorite_border,
                          size: 16, color: Colors.grey),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: Icon(_iconForType(type), size: 14, color: color),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nom.isEmpty ? profLabel : nom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF1E2025)),
                  ),
                  const SizedBox(height: 2),
                  Text(profLabel,
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 11,
                          color: Colors.grey.shade500)),
                  if (ville.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.location_on_outlined,
                          size: 11, color: Colors.grey.shade400),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(ville,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 10,
                                color: Colors.grey.shade400)),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: acceptNew
                          ? const Color(0xFF2E7D5E).withValues(alpha: 0.10)
                          : Colors.orange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      acceptNew ? 'Ouvert' : 'Sur rendez-vous',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: acceptNew
                              ? const Color(0xFF2E7D5E)
                              : Colors.orange.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _placeholder(Color color) => Container(
        width: 160,
        height: 120,
        color: color.withValues(alpha: 0.10),
        child: Icon(Icons.storefront_outlined,
            size: 40, color: color.withValues(alpha: 0.35)),
      );

  static IconData _iconForType(String type) => switch (type) {
        'sante' || 'veterinaire' => Icons.medical_services_outlined,
        'osteo' => Icons.self_improvement_outlined,
        'kine' => Icons.fitness_center_outlined,
        'marechal_ferrant' => Icons.hardware_outlined,
        'education' || 'educateur' => Icons.school_outlined,
        'comportementaliste' => Icons.psychology_outlined,
        'pension' || 'garde' || 'pet_sitter' => Icons.home_outlined,
        'promeneur' => Icons.directions_walk_outlined,
        'toilettage' || 'toiletteur' => Icons.content_cut,
        'alimentation' || 'animalerie' => Icons.store_outlined,
        'transport' || 'taxi_animalier' || 'vtc' => Icons.directions_car_outlined,
        'photographe' => Icons.photo_camera_outlined,
        'boutique' => Icons.shopping_bag_outlined,
        'artisan' || 'createur' => Icons.palette_outlined,
        'assurance' || 'juridique' => Icons.shield_outlined,
        _ => Icons.storefront_outlined,
      };
}
