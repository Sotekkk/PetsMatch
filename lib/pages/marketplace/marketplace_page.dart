import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/marketplace/partner_signup_page.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _partners = [];
  String _filterEspece = 'tous';
  bool _loading = true;

  static const _especes = ['tous', 'chien', 'chat', 'equide', 'autre'];
  static const _especeLabels = {
    'tous': 'Tous',
    'chien': 'Chien',
    'chat': 'Chat',
    'equide': 'Équidé',
    'autre': 'Autre'
  };

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  Future<void> _loadPartners() async {
    setState(() => _loading = true);
    try {
      var query = _supabase
          .from('marketplace_partners')
          .select()
          .eq('statut', 'actif');

      if (_filterEspece != 'tous') {
        query = query.contains('especes_cibles', [_filterEspece]);
      }

      final data = await query.order('plan', ascending: false);
      if (mounted) {
        setState(() {
          _partners = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPartner(
      Map<String, dynamic> partner, String eventType) async {
    try {
      await _supabase.from('marketplace_events').insert({
        'partner_id': partner['id'],
        'user_id': User_Info.uid,
        'event_type': eventType,
        'espece': _filterEspece == 'tous' ? null : _filterEspece,
        'region': User_Info.ville.isNotEmpty ? User_Info.ville : null,
      });
    } catch (_) {}

    final url = partner['site_url'] as String?;
    if (url != null && url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insurers =
        _partners.where((p) => p['categorie'] == 'assurance').toList();
    final others =
        _partners.where((p) => p['categorie'] != 'assurance').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFA7C79A),
        elevation: 0,
        title: const Text('Marketplace',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF6E9E57),
        onRefresh: _loadPartners,
        child: CustomScrollView(
          slivers: [
            // Header + filtres espèce
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nos partenaires sélectionnés',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 18)),
                    const SizedBox(height: 4),
                    Text('Des marques vérifiées pour vos animaux',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 13,
                            color: Colors.grey.shade600)),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _especes.map((e) {
                          final selected = _filterEspece == e;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(
                                _especeLabels[e]!,
                                style: TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 13,
                                    color: selected
                                        ? Colors.white
                                        : Colors.black87),
                              ),
                              selected: selected,
                              onSelected: (_) {
                                setState(() => _filterEspece = e);
                                _loadPartners();
                              },
                              selectedColor: const Color(0xFF6E9E57),
                              backgroundColor: Colors.white,
                              checkmarkColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                    color: selected
                                        ? const Color(0xFF6E9E57)
                                        : Colors.grey.shade300),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_loading)
              const SliverFillRemaining(
                child: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF6E9E57))),
              )
            else if (_partners.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.storefront_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun partenaire disponible',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 16,
                            color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Section Assurances
              if (insurers.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 10),
                    child: Row(
                      children: [
                        Text('🛡️', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 8),
                        Text('Assurances animaux',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _InsuranceCard(
                        partner: insurers[i],
                        onTap: (p) => _openPartner(p, 'lead')),
                    childCount: insurers.length,
                  ),
                ),
              ],

              // Section partenaires
              if (others.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 10),
                    child: Row(
                      children: [
                        Text('🤝', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 8),
                        Text('Nos partenaires',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _PartnerCard(
                          partner: others[i],
                          onTap: (p) => _openPartner(p, 'clic')),
                      childCount: others.length,
                    ),
                  ),
                ),
              ],

              // Devenir partenaire CTA
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6E9E57), Color(0xFF4A7A3D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Vous êtes une marque ?',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.white)),
                        const SizedBox(height: 6),
                        Text(
                          'Rejoignez nos partenaires et touchez une audience qualifiée d\'amoureux des animaux.',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.9)),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const PartnerSignupPage())),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF4A7A3D),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                          child: const Text('Devenir partenaire'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Partner card (grille) ─────────────────────────────────────────────────────

class _PartnerCard extends StatelessWidget {
  final Map<String, dynamic> partner;
  final void Function(Map<String, dynamic>) onTap;
  const _PartnerCard({required this.partner, required this.onTap});

  static const _catLabels = {
    'artisan': 'Artisan',
    'alimentation': 'Alimentation',
    'boutique': 'Boutique',
    'assurance': 'Assurance'
  };
  static const _catIcons = {
    'artisan': Icons.brush_outlined,
    'alimentation': Icons.restaurant_outlined,
    'boutique': Icons.store_outlined,
    'assurance': Icons.shield_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final plan = partner['plan'] as String? ?? 'starter';
    final isPremium = plan == 'premium';
    final logoUrl = partner['logo_url'] as String?;
    final categorie = partner['categorie'] as String? ?? 'boutique';

    return GestureDetector(
      onTap: () => onTap(partner),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isPremium
              ? Border.all(
                  color: const Color(0xFF8E24AA).withValues(alpha: 0.4),
                  width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: logoUrl != null && logoUrl.isNotEmpty
                    ? Image.network(logoUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            _placeholder(categorie))
                    : _placeholder(categorie),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(partner['nom'] ?? '',
                            style: const TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFF6E9E57)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('✓',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 9,
                                color: Color(0xFF6E9E57),
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_catLabels[categorie] ?? categorie,
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 11,
                          color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(String categorie) {
    return Container(
      color: const Color(0xFFF0F7EC),
      child: Icon(_catIcons[categorie] ?? Icons.storefront_outlined,
          size: 40, color: const Color(0xFF6E9E57)),
    );
  }
}

// ── Insurance card (ligne) ────────────────────────────────────────────────────

class _InsuranceCard extends StatelessWidget {
  final Map<String, dynamic> partner;
  final void Function(Map<String, dynamic>) onTap;
  const _InsuranceCard({required this.partner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final logoUrl = partner['logo_url'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: const Color(0xFFF0F7EC),
                    borderRadius: BorderRadius.circular(12)),
                child: logoUrl != null && logoUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(logoUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.shield_outlined,
                                color: Color(0xFF6E9E57),
                                size: 26)))
                    : const Icon(Icons.shield_outlined,
                        color: Color(0xFF6E9E57), size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(partner['nom'] ?? '',
                              style: const TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: const Color(0xFF6E9E57)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: const Text('✓ Vérifié',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 9,
                                  color: Color(0xFF6E9E57),
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    if ((partner['description'] as String?)?.isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 3),
                      Text(partner['description']!,
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 12,
                              color: Colors.grey.shade600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => onTap(partner),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                child: const Text('Devis'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
