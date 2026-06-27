import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/lieux/mon_etablissement_page.dart';
import 'package:PetsMatch/pages/notifications_page.dart';
import 'package:PetsMatch/pages/pro/restauration/inscription_restauration_detail_page.dart';

// ── Dashboard accueil pro hébergement/restauration ──────────────────────────

class RestaurationHomePage extends StatefulWidget {
  const RestaurationHomePage({super.key});

  @override
  State<RestaurationHomePage> createState() => _RestaurationHomePageState();
}

class _RestaurationHomePageState extends State<RestaurationHomePage> {
  static const _teal = Color(0xFF0C5C6C);

  bool _loading = true;
  String _verificationStatus = 'none';

  // Stats globales des établissements
  int    _nbEtablissements = 0;
  int    _vuesTotales      = 0;
  int    _nbAvis           = 0;
  double _noteMoyenne      = 0;

  // Profil
  String? _profilePhotoUrl;
  String? _bannerUrl;
  String  _nomEtabl = '';
  String  _villeEtabl = '';
  String  _typeEtabl = '';

  // Avis récents
  List<Map<String, dynamic>> _recentAvis = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }

    try {
      // Profil
      final profileRes = await Supabase.instance.client
          .from('user_profiles')
          .select('nom, ville_pro, type_restauration, avatar_url, banner_url, verification_status')
          .eq('uid', uid)
          .eq('cat_pro', 'restauration')
          .maybeSingle();

      if (profileRes != null) {
        _verificationStatus  = profileRes['verification_status']?.toString() ?? 'none';
        _nomEtabl            = profileRes['nom']?.toString() ?? '';
        _villeEtabl          = profileRes['ville_pro']?.toString() ?? '';
        _typeEtabl           = profileRes['type_restauration']?.toString() ?? '';
        _profilePhotoUrl     = profileRes['avatar_url']?.toString();
        _bannerUrl           = profileRes['banner_url']?.toString();
      }

      // Établissements
      final places = await Supabase.instance.client
          .from('petfriendly_places')
          .select('id, vue_count, nb_avis, note_moyenne')
          .eq('uid_pro', uid);

      final placesList = List<Map<String, dynamic>>.from(places as List);
      _nbEtablissements = placesList.length;
      _vuesTotales = placesList.fold(0, (s, e) => s + ((e['vue_count'] as int?) ?? 0));
      _nbAvis = placesList.fold(0, (s, e) => s + ((e['nb_avis'] as int?) ?? 0));

      if (_nbAvis > 0) {
        final totalNote = placesList.fold<double>(
          0, (s, e) => s + (((e['note_moyenne'] as num?) ?? 0) * ((e['nb_avis'] as int?) ?? 0)));
        _noteMoyenne = totalNote / _nbAvis;
      }

      // Avis récents (via les établissements de ce pro)
      if (placesList.isNotEmpty) {
        final placeIds = placesList.map((e) => e['id']).toList();
        final avisRes = await Supabase.instance.client
            .from('petfriendly_reviews')
            .select('id, note, commentaire, created_at, place_id')
            .inFilter('place_id', placeIds)
            .order('created_at', ascending: false)
            .limit(3);
        _recentAvis = List<Map<String, dynamic>>.from(avisRes as List);
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F8F6),
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: RefreshIndicator(
        onRefresh: () async { setState(() => _loading = true); await _load(); },
        child: CustomScrollView(
          slivers: [
            _buildHeader(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(children: [
                  _buildValidationBanner(),
                  const SizedBox(height: 16),
                  _buildStats(),
                  const SizedBox(height: 20),
                  _buildQuickLinks(),
                  if (_recentAvis.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildRecentAvis(),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final label = _typeEtabl.isEmpty ? 'Hébergement / Restauration' : _labelType(_typeEtabl);
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      backgroundColor: _teal,
      foregroundColor: Colors.white,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(fit: StackFit.expand, children: [
          if (_bannerUrl != null)
            CachedNetworkImage(imageUrl: _bannerUrl!, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: const Color(0xFF094F5D)))
          else
            Container(color: const Color(0xFF094F5D)),
          Container(color: Colors.black.withValues(alpha: 0.4)),
          Positioned(
            bottom: 16, left: 16,
            child: Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white24,
                backgroundImage: _profilePhotoUrl != null
                    ? CachedNetworkImageProvider(_profilePhotoUrl!) : null,
                child: _profilePhotoUrl == null
                    ? const Text('🏡', style: TextStyle(fontSize: 24)) : null,
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _nomEtabl.isNotEmpty ? _nomEtabl : User_Info.firstname,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 18, color: Colors.white),
                ),
                Text(label,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
                if (_villeEtabl.isNotEmpty)
                  Text('📍 $_villeEtabl',
                      style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildValidationBanner() {
    if (_verificationStatus == 'approved') return const SizedBox.shrink();

    Color bg; Color text; IconData ico; String titre; String sub;

    if (_verificationStatus == 'none') {
      bg = const Color(0xFFFFF8E1); text = const Color(0xFF795548);
      ico = Icons.edit_note_outlined;
      titre = 'Complétez votre profil';
      sub = 'Ajoutez vos informations pour soumettre votre dossier à validation.';
    } else if (_verificationStatus == 'pending') {
      bg = const Color(0xFFE3F2FD); text = const Color(0xFF1565C0);
      ico = Icons.hourglass_empty;
      titre = 'Dossier en cours d\'examen';
      sub = 'Notre équipe examine votre profil. Vous recevrez un email sous 48h.';
    } else {
      bg = const Color(0xFFFFEBEE); text = Colors.red.shade700;
      ico = Icons.error_outline;
      titre = 'Profil refusé';
      sub = 'Contactez-nous pour comprendre la raison du refus.';
    }

    return GestureDetector(
      onTap: _verificationStatus == 'none'
          ? () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const InscriptionRestaurationDetailPage()))
                .then((_) { setState(() => _loading = true); _load(); })
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: text.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(ico, color: text, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 14, color: text)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: text.withValues(alpha: 0.8), height: 1.3)),
            ]),
          ),
          if (_verificationStatus == 'none')
            Icon(Icons.arrow_forward_ios, color: text, size: 14),
        ]),
      ),
    );
  }

  Widget _buildStats() {
    return Row(children: [
      _stat(_nbEtablissements.toString(), 'Établissements', Icons.storefront_outlined,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MonEtablissementPage()))),
      const SizedBox(width: 12),
      _stat(_vuesTotales.toString(), 'Vues', Icons.visibility_outlined),
      const SizedBox(width: 12),
      _stat(_nbAvis > 0
          ? '${_noteMoyenne.toStringAsFixed(1)} ⭐'
          : '–',
          '$_nbAvis avis', Icons.star_outline),
    ]);
  }

  Widget _stat(String val, String label, IconData icon, {VoidCallback? onTap}) {
    final card = Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Icon(icon, color: _teal, size: 22),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
            fontSize: 16, color: Color(0xFF1F2A2E))),
        Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B)),
            textAlign: TextAlign.center),
      ]),
    );
    return Expanded(
      child: onTap != null ? GestureDetector(onTap: onTap, child: card) : card,
    );
  }

  Widget _buildQuickLinks() {
    final links = [
      _LinkItem('Mes établissements', Icons.storefront_outlined, const Color(0xFFE8F4F6),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonEtablissementPage()))),
      _LinkItem('Notifications', Icons.notifications_outlined, const Color(0xFFF3E5F5),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()))),
      _LinkItem('Abonnement', Icons.workspace_premium_outlined, const Color(0xFFFFF8E1),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AbonnementPage()))),
      _LinkItem('Mon profil', Icons.person_outline, const Color(0xFFEEF5EA),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const InscriptionRestaurationDetailPage()))),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Accès rapide',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.6,
        children: links.map((l) => GestureDetector(
          onTap: l.onTap,
          child: Container(
            decoration: BoxDecoration(
              color: l.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(l.icon, color: _teal, size: 20),
              const SizedBox(width: 8),
              Flexible(child: Text(l.label,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                      fontSize: 13, color: Color(0xFF1F2A2E)),
                  overflow: TextOverflow.ellipsis)),
            ]),
          ),
        )).toList(),
      ),
    ]);
  }

  Widget _buildRecentAvis() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Avis récents',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
      const SizedBox(height: 12),
      ...(_recentAvis.map((a) {
        final note = (a['note'] as num?)?.toDouble() ?? 0;
        final comment = a['commentaire']?.toString() ?? '';
        final date = a['created_at'] != null
            ? DateTime.tryParse(a['created_at'].toString())
            : null;
        final dateStr = date != null
            ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
            : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ...List.generate(5, (i) => Icon(
                i < note ? Icons.star : Icons.star_border,
                size: 14, color: Colors.amber,
              )),
              const Spacer(),
              Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(comment, style: const TextStyle(fontSize: 13, height: 1.4),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ]),
        );
      })),
    ]);
  }

  String _labelType(String t) {
    const m = {
      'restaurant': 'Restaurant',
      'hotel': 'Hôtel pet-friendly',
      'cafe': 'Café / Salon de thé',
      'bar': 'Bar / Brasserie',
      'fast_food': 'Restauration rapide',
      'boulangerie': 'Boulangerie',
      'gite': 'Gîte / Chambre d\'hôtes',
      'hebergement_insolite': 'Hébergement insolite',
      'camping': 'Camping',
      'villa_location': 'Location saisonnière',
    };
    return m[t] ?? 'Établissement';
  }
}

class _LinkItem {
  final String label;
  final IconData icon;
  final Color bg;
  final VoidCallback onTap;
  const _LinkItem(this.label, this.icon, this.bg, this.onTap);
}
