import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart';

/// Bannière contextuelle Marketplace (MKT03).
/// Afficher dans les fiches animaux, feed, dashboard éleveur, etc.
/// [espece] : 'chien', 'chat', 'equide', 'autre' — null = tous
/// [placement] : 'fiche_animal', 'feed', 'carnet_sante', 'dashboard', 'onboarding'
class MarketplaceBanner extends StatefulWidget {
  final String? espece;
  final String placement;

  const MarketplaceBanner({
    super.key,
    this.espece,
    this.placement = 'fiche_animal',
  });

  @override
  State<MarketplaceBanner> createState() => _MarketplaceBannerState();
}

class _MarketplaceBannerState extends State<MarketplaceBanner> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _ad;
  Map<String, dynamic>? _partner;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    try {
      var query = _supabase
          .from('marketplace_ads')
          .select('*, marketplace_partners(*)')
          .eq('type', 'banniere')
          .eq('statut', 'actif');

      if (widget.espece != null) {
        query = query.contains('especes_cibles', [widget.espece!]);
      }

      final data = await query.limit(10);
      if (data.isEmpty || !mounted) return;

      final list = List<Map<String, dynamic>>.from(data);
      list.shuffle();
      final ad = list.first;
      final partner = ad['marketplace_partners'] as Map<String, dynamic>?;

      if (partner == null || !mounted) return;
      setState(() {
        _ad = ad;
        _partner = partner;
      });

      // Log impression
      await _supabase.from('marketplace_events').insert({
        'ad_id': ad['id'],
        'partner_id': partner['id'],
        'user_id': User_Info.uid,
        'event_type': 'impression',
        'espece': widget.espece,
        'region': User_Info.ville.isNotEmpty ? User_Info.ville : null,
      });
    } catch (_) {}
  }

  Future<void> _onTap() async {
    if (_ad == null || _partner == null) return;
    try {
      await _supabase.from('marketplace_events').insert({
        'ad_id': _ad!['id'],
        'partner_id': _partner!['id'],
        'user_id': User_Info.uid,
        'event_type': 'clic',
        'espece': widget.espece,
        'region': User_Info.ville.isNotEmpty ? User_Info.ville : null,
      });
    } catch (_) {}

    final url = _partner!['site_url'] as String?;
    if (url != null && url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _ad == null || _partner == null) return const SizedBox.shrink();

    final logoUrl = _partner!['logo_url'] as String?;
    final nom = _partner!['nom'] as String? ?? '';
    final desc = _partner!['description'] as String?;
    final categorie = _partner!['categorie'] as String? ?? 'boutique';
    final isAssurance = categorie == 'assurance';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: GestureDetector(
        onTap: _onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête : logo + nom + badge "Publicité"
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                          color: const Color(0xFFF0F7EC),
                          borderRadius: BorderRadius.circular(14)),
                      child: logoUrl != null && logoUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(logoUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Icon(
                                      isAssurance
                                          ? Icons.shield_outlined
                                          : Icons.storefront_outlined,
                                      color: const Color(0xFF6E9E57),
                                      size: 30)))
                          : Icon(
                              isAssurance
                                  ? Icons.shield_outlined
                                  : Icons.storefront_outlined,
                              color: const Color(0xFF6E9E57),
                              size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nom,
                              style: const TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text('Publicité',
                                style: TextStyle(
                                    fontFamily: 'Galey',
                                    fontSize: 10,
                                    color: Colors.grey.shade500)),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _dismissed = true),
                      child: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
                    ),
                  ],
                ),
                // Description
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(desc,
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 13,
                          color: Colors.grey.shade700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 14),
                // CTA pleine largeur
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAssurance
                          ? const Color(0xFF0C5C6C)
                          : const Color(0xFF6E9E57),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                    child: Text(isAssurance ? 'Obtenir un devis' : 'Découvrir'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
