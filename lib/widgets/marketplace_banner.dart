import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart';

const _kPlaceholders = {
  'assurance':   'https://images.unsplash.com/photo-1450778869180-41d0601e046e?w=600&q=70&fit=crop',
  'sante':       'https://images.unsplash.com/photo-1628009368231-7bb7cfcb0def?w=600&q=70&fit=crop',
  'veterinaire': 'https://images.unsplash.com/photo-1628009368231-7bb7cfcb0def?w=600&q=70&fit=crop',
  'alimentation':'https://images.unsplash.com/photo-1601758124277-a7a9e4cc79e2?w=600&q=70&fit=crop',
  'accessoire':  'https://images.unsplash.com/photo-1587300003388-59208cc962cb?w=600&q=70&fit=crop',
  '_default':    'https://images.unsplash.com/photo-1516734212186-a967f81ad0d7?w=600&q=70&fit=crop',
};

/// Bannière rotative — affiche les partenaires marketplace actifs.
/// Swipe manuel + rotation automatique toutes les 8s.
/// Recharge un nouveau lot toutes les 40s.
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
  late final PageController _pageController;

  List<Map<String, dynamic>> _partners = [];
  int _currentIndex = 0;

  Timer? _slideTimer;
  Timer? _reloadTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
    _loadPartners();
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _reloadTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadPartners() async {
    try {
      final data = await _supabase
          .from('marketplace_partners')
          .select()
          .eq('statut', 'actif')
          .limit(20);

      if (!mounted) return;

      final raw = List<Map<String, dynamic>>.from(data as List);
      raw.shuffle();
      final partners = raw.take(5).toList();
      if (partners.isEmpty) return;

      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }

      setState(() {
        _partners = partners;
        _currentIndex = 0;
      });

      _logImpression(0);
      _startTimers();
    } catch (_) {}
  }

  void _startTimers() {
    _slideTimer?.cancel();
    _reloadTimer?.cancel();

    if (_partners.length > 1) {
      _slideTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!mounted || !_pageController.hasClients) return;
        final next = (_currentIndex + 1) % _partners.length;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      });
    }

    _reloadTimer = Timer.periodic(const Duration(seconds: 40), (_) {
      _slideTimer?.cancel();
      _loadPartners();
    });
  }

  void _resetSlideTimer() {
    if (_partners.length <= 1) return;
    _slideTimer?.cancel();
    _slideTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_currentIndex + 1) % _partners.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _logImpression(int i) async {
    if (i >= _partners.length) return;
    try {
      await _supabase.from('marketplace_events').insert({
        'partner_id': _partners[i]['id'],
        'user_id': User_Info.uid,
        'event_type': 'impression',
        'espece': widget.espece,
        'region': User_Info.ville.isNotEmpty ? User_Info.ville : null,
      });
    } catch (_) {}
  }

  Future<void> _onTap(int i) async {
    if (i >= _partners.length) return;
    try {
      await _supabase.from('marketplace_events').insert({
        'partner_id': _partners[i]['id'],
        'user_id': User_Info.uid,
        'event_type': 'clic',
        'espece': widget.espece,
        'region': User_Info.ville.isNotEmpty ? User_Info.ville : null,
      });
    } catch (_) {}
    final url = _partners[i]['site_url'] as String?;
    if (url != null && url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Color _accentColor(Map<String, dynamic> partner) {
    final cat = partner['categorie'] as String? ?? '';
    if (cat == 'assurance') return const Color(0xFF0C5C6C);
    if (cat == 'sante' || cat == 'veterinaire') return const Color(0xFF2E86AB);
    return const Color(0xFF6E9E57);
  }

  String _heroImage(Map<String, dynamic> partner) {
    final logo = partner['logo_url'] as String?;
    if (logo != null && logo.isNotEmpty) return logo;
    final cat = partner['categorie'] as String? ?? '';
    return _kPlaceholders[cat] ?? _kPlaceholders['_default']!;
  }

  @override
  Widget build(BuildContext context) {
    if (_partners.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          // ── Carrousel ───────────────────────────────────────────────────
          SizedBox(
            height: 150,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _partners.length,
              physics: const ClampingScrollPhysics(),
              onPageChanged: (i) {
                setState(() => _currentIndex = i);
                _logImpression(i);
                _resetSlideTimer();
              },
              itemBuilder: (_, i) {
                final p = _partners[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _BannerCard(
                    heroImage: _heroImage(p),
                    nom: p['nom'] as String? ?? '',
                    desc: p['description'] as String?,
                    accentColor: _accentColor(p),
                    isAssurance: (p['categorie'] as String?) == 'assurance',
                    onTap: () => _onTap(i),
                  ),
                );
              },
            ),
          ),

          // ── Dots ────────────────────────────────────────────────────────
          if (_partners.length > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_partners.length, (i) {
                final color = _accentColor(_partners[i]);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _currentIndex ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _currentIndex ? color : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Carte ───────────────────────────────────────────────────────────────────

class _BannerCard extends StatelessWidget {
  final String heroImage;
  final String nom;
  final String? desc;
  final Color accentColor;
  final bool isAssurance;
  final VoidCallback onTap;

  const _BannerCard({
    required this.heroImage,
    required this.nom,
    required this.desc,
    required this.accentColor,
    required this.isAssurance,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 5))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero ──────────────────────────────────────────────────
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image ou gradient
                Image.network(heroImage, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _gradient()),

                // Vignette bas
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xBB000000)],
                        stops: [0.35, 1.0],
                      ),
                    ),
                  ),
                ),

                // Badge pub
                Positioned(
                  top: 10,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(5)),
                    child: const Text('Publicité',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 10,
                            color: Colors.white)),
                  ),
                ),

                // Nom du partenaire
                Positioned(
                  bottom: 10,
                  left: 14,
                  right: 14,
                  child: Text(nom,
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                                color: Colors.black54,
                                blurRadius: 6,
                                offset: Offset(0, 1))
                          ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),

          // ── Description ───────────────────────────────────────────
          if (desc != null && desc!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Text(desc!,
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 12.5,
                      height: 1.4,
                      color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    ));
  }

  Widget _gradient() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accentColor, accentColor.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
}
