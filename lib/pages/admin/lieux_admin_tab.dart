import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LieuxAdminTab extends StatefulWidget {
  const LieuxAdminTab({super.key});

  @override
  State<LieuxAdminTab> createState() => _LieuxAdminTabState();
}

class _LieuxAdminTabState extends State<LieuxAdminTab>
    with SingleTickerProviderStateMixin {
  static const _teal  = Color(0xFF0C5C6C);

  late final TabController _tabs;
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _actifs  = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pending = await _supabase
          .from('petfriendly_places')
          .select()
          .eq('statut', 'en_attente_validation')
          .order('created_at', ascending: true);

      final actifs = await _supabase
          .from('petfriendly_places')
          .select()
          .inFilter('statut', ['actif', 'suspendu'])
          .order('created_at', ascending: false)
          .limit(50);

      setState(() {
        _pending = List<Map<String, dynamic>>.from(pending as List);
        _actifs  = List<Map<String, dynamic>>.from(actifs  as List);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _valider(String id) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    await _supabase.from('petfriendly_places').update({
      'statut': 'actif',
      'valide_par': adminUid,
      'valide_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Établissement validé et publié'),
              backgroundColor: Color(0xFF4CAF50)));
    }
  }

  Future<void> _rejeter(String id) async {
    String? motif;
    await showDialog(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Motif de rejet'),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Expliquez pourquoi le profil est rejeté…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () { motif = ctrl.text.trim(); Navigator.pop(ctx); },
              child: const Text('Rejeter', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (motif == null) return;
    await _supabase.from('petfriendly_places').update({
      'statut': 'suspendu',
    }).eq('id', id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Rejeté : $motif'), backgroundColor: Colors.red));
    }
  }

  Future<void> _suspendre(String id) async {
    await _supabase.from('petfriendly_places')
        .update({'statut': 'suspendu'}).eq('id', id);
    await _load();
  }

  Future<void> _reactiver(String id) async {
    await _supabase.from('petfriendly_places')
        .update({'statut': 'actif'}).eq('id', id);
    await _load();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: _teal,
          indicatorColor: _teal,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(text: 'En attente (${_pending.length})'),
            Tab(text: 'Publiés (${_actifs.length})'),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _PendingList(
                      lieux: _pending,
                      onValider: _valider,
                      onRejeter: _rejeter,
                    ),
                    _ActifsList(
                      lieux: _actifs,
                      onSuspendre: _suspendre,
                      onReactiver: _reactiver,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─── Liste en attente ─────────────────────────────────────────────────────────

class _PendingList extends StatelessWidget {
  final List<Map<String, dynamic>> lieux;
  final Future<void> Function(String) onValider;
  final Future<void> Function(String) onRejeter;

  const _PendingList({required this.lieux, required this.onValider, required this.onRejeter});

  @override
  Widget build(BuildContext context) {
    if (lieux.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: Color(0xFF6E9E57)),
            SizedBox(height: 12),
            Text('Aucun établissement en attente', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: lieux.length,
        itemBuilder: (_, i) => _PendingCard(
          lieu: lieux[i],
          onValider: () => onValider(lieux[i]['id'] as String),
          onRejeter: () => onRejeter(lieux[i]['id'] as String),
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final Map<String, dynamic> lieu;
  final VoidCallback onValider;
  final VoidCallback onRejeter;

  const _PendingCard({required this.lieu, required this.onValider, required this.onRejeter});

  @override
  Widget build(BuildContext context) {
    final s = _autoScore(lieu);
    final pct = s.score / s.max;
    final autoOk = pct >= 0.75;   // ≥ 6/8 critères → éligible auto-validation
    final nom    = lieu['nom'] as String? ?? '';
    final ville  = lieu['ville'] as String? ?? '';
    final cat    = lieu['categorie'] as String? ?? '';
    final logo   = lieu['photo_profil_url'] as String?;
    final createdRaw = lieu['created_at'] as String?;
    final created = createdRaw != null
        ? DateTime.tryParse(createdRaw)
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              if (logo != null && logo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: logo, width: 52, height: 52, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _PlaceholderIcon(cat),
                  ),
                )
              else
                _PlaceholderIcon(cat),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom, style: const TextStyle(fontFamily: 'Galey',
                        fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('$ville · ${cat == 'hebergement' ? '🏨 Hébergement' : '🍽️ Restauration'}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    if (created != null)
                      Text('Soumis le ${_date(created)}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 12),

            // Score auto
            Row(children: [
              Text('Score auto : ${s.score}/${s.max}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13,
                    color: autoOk ? const Color(0xFF4CAF50) : Colors.orange,
                  )),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(autoOk ? const Color(0xFF4CAF50) : Colors.orange),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              if (autoOk)
                const Text('✅ Éligible auto', style: TextStyle(fontSize: 11, color: Color(0xFF4CAF50)))
              else
                const Text('⚠️ Vérif. requise', style: TextStyle(fontSize: 11, color: Colors.orange)),
            ]),

            const SizedBox(height: 10),

            // Critères détaillés
            Wrap(
              spacing: 6, runSpacing: 4,
              children: s.criteres.map((c) => _CritereChip(c)).toList(),
            ),

            const Divider(height: 20),

            // Infos détail
            _InfoRow(Icons.location_on_outlined, '${lieu['adresse'] ?? ''}, ${lieu['code_postal'] ?? ''} $ville'),
            _InfoRow(Icons.badge_outlined, 'SIRET : ${lieu['siret'] ?? 'Non renseigné'}'),
            if ((lieu['telephone'] as String?) != null)
              _InfoRow(Icons.phone_outlined, lieu['telephone']!),
            if ((lieu['email_contact'] as String?) != null)
              _InfoRow(Icons.email_outlined, lieu['email_contact']!),

            const SizedBox(height: 12),

            // Bouton "Voir fiche complète"
            GestureDetector(
              onTap: () => _showDetail(context, lieu),
              child: const Text('Voir la fiche complète →',
                  style: TextStyle(color: Color(0xFF0C5C6C), fontSize: 12,
                      decoration: TextDecoration.underline)),
            ),

            const SizedBox(height: 14),

            // Actions
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRejeter,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Rejeter'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onValider,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Valider'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6E9E57),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> lieu) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, ctrl) => _LieuDetailSheet(lieu: lieu, scrollController: ctrl),
      ),
    );
  }

  String _date(DateTime d) => '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
}

// ─── Liste publiés / suspendus ───────────────────────────────────────────────

class _ActifsList extends StatelessWidget {
  final List<Map<String, dynamic>> lieux;
  final Future<void> Function(String) onSuspendre;
  final Future<void> Function(String) onReactiver;

  const _ActifsList({required this.lieux, required this.onSuspendre, required this.onReactiver});

  @override
  Widget build(BuildContext context) {
    if (lieux.isEmpty) {
      return const Center(child: Text('Aucun établissement publié', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: lieux.length,
      itemBuilder: (_, i) {
        final lieu = lieux[i];
        final statut = lieu['statut'] as String? ?? '';
        final isSuspendu = statut == 'suspendu';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: lieu['photo_profil_url'] != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: lieu['photo_profil_url']!, width: 48, height: 48, fit: BoxFit.cover))
              : _PlaceholderIcon(lieu['categorie'] as String? ?? ''),
          title: Text(lieu['nom'] as String? ?? '',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: Text(
            '${lieu['ville'] ?? ''} · ${lieu['plan'] ?? 'decouverte'}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: isSuspendu
              ? TextButton(
                  onPressed: () => onReactiver(lieu['id'] as String),
                  child: const Text('Réactiver', style: TextStyle(color: Color(0xFF6E9E57))))
              : TextButton(
                  onPressed: () => onSuspendre(lieu['id'] as String),
                  child: const Text('Suspendre', style: TextStyle(color: Colors.orange))),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
      },
    );
  }
}

// ─── Fiche détail (bottom sheet) ─────────────────────────────────────────────

class _LieuDetailSheet extends StatelessWidget {
  final Map<String, dynamic> lieu;
  final ScrollController scrollController;

  const _LieuDetailSheet({required this.lieu, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final photos = List<String>.from(lieu['photos'] as List? ?? []);
    final horaires = lieu['horaires'] as Map<String, dynamic>? ?? {};
    final especes = List<String>.from(lieu['especes_acceptees'] as List? ?? []);
    final cat = lieu['categorie'] as String? ?? '';

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Center(
          child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 12),
        Text(lieu['nom'] as String? ?? '',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 4),
        Text('${lieu['sous_categorie'] ?? ''} · ${lieu['ville'] ?? ''}',
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const Divider(height: 24),

        _Row('SIRET', lieu['siret'] ?? '-'),
        _Row('Adresse', '${lieu['adresse'] ?? ''}, ${lieu['code_postal'] ?? ''} ${lieu['ville'] ?? ''}'),
        _Row('GPS', 'lat: ${lieu['lat'] ?? '-'}, lng: ${lieu['lng'] ?? '-'}'),
        _Row('Téléphone', lieu['telephone'] ?? '-'),
        _Row('Email', lieu['email_contact'] ?? '-'),
        _Row('Site web', lieu['site_web'] ?? '-'),
        _Row('Espèces', especes.join(', ')),

        if (horaires.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Horaires', style: TextStyle(fontWeight: FontWeight.w700)),
          ...horaires.entries.map((e) => _Row(e.key, e.value.toString())),
        ],

        if (cat == 'hebergement') ...[
          const SizedBox(height: 12),
          const Text('Conditions animaux', style: TextStyle(fontWeight: FontWeight.w700)),
          _Row('Animaux en chambre', '${lieu['animaux_dans_chambre'] ?? '-'}'),
          _Row('Frais/nuit', '${lieu['frais_animal_nuit'] ?? 0}€'),
          _Row('Poids max', '${lieu['poids_max_kg'] ?? 0} kg'),
          _Row('Nb max', '${lieu['nb_animaux_max'] ?? '-'}'),
          _Row('Espace détente', '${lieu['espace_detente'] ?? '-'}'),
        ] else if (cat == 'restauration') ...[
          const SizedBox(height: 12),
          const Text('Conditions animaux', style: TextStyle(fontWeight: FontWeight.w700)),
          _Row('Terrasse', '${lieu['terrasse'] ?? '-'}'),
          _Row('Animaux en salle', '${lieu['animaux_en_salle'] ?? '-'}'),
          _Row('Eau fournie', '${lieu['eau_fournie'] ?? '-'}'),
          _Row('Friandises', '${lieu['friandises'] ?? '-'}'),
        ],

        if ((lieu['description'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Description', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(lieu['description'] as String? ?? '',
              style: const TextStyle(fontSize: 13, height: 1.4)),
        ],

        if (photos.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Photos', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                    imageUrl: photos[i], width: 90, height: 100, fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _Row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 110, child: Text(label,
          style: const TextStyle(fontSize: 12, color: Colors.grey))),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
    ]),
  );
}

// ─── Score de confiance automatique (top-level) ──────────────────────────────

({int score, int max, List<_Critere> criteres}) _autoScore(Map<String, dynamic> lieu) {
  final criteres = <_Critere>[];
  int score = 0;

  void add(String label, bool ok) {
    criteres.add(_Critere(label, ok));
    if (ok) score++;
  }

  final siret = lieu['siret'] as String? ?? '';
  add('SIRET 14 chiffres', siret.length == 14 && RegExp(r'^\d+$').hasMatch(siret));
  final lat = (lieu['lat'] as num?)?.toDouble();
  final lng = (lieu['lng'] as num?)?.toDouble();
  add('Coordonnées GPS valides', lat != null && lng != null && lat != 0 && lng != 0);
  final desc = lieu['description'] as String? ?? '';
  add('Description ≥ 100 caractères', desc.length >= 100);
  final logo = lieu['photo_profil_url'] as String?;
  add('Logo uploadé', logo != null && logo.isNotEmpty);
  final photos = lieu['photos'] as List?;
  add('≥ 1 photo du lieu', photos != null && photos.isNotEmpty);
  final tel = lieu['telephone'] as String?;
  final email = lieu['email_contact'] as String?;
  add('Contact (tél ou email)',
      (tel != null && tel.isNotEmpty) || (email != null && email.isNotEmpty));
  final especes = lieu['especes_acceptees'] as List?;
  add('≥ 1 espèce acceptée', especes != null && especes.isNotEmpty);
  final horaires = lieu['horaires'] as Map<String, dynamic>?;
  add('Horaires renseignés', horaires != null && horaires.isNotEmpty);

  return (score: score, max: criteres.length, criteres: criteres);
}

// ─── Widgets utilitaires ─────────────────────────────────────────────────────

class _PlaceholderIcon extends StatelessWidget {
  final String categorie;
  const _PlaceholderIcon(this.categorie);

  @override
  Widget build(BuildContext context) => Container(
    width: 52, height: 52,
    decoration: BoxDecoration(
      color: categorie == 'hebergement'
          ? const Color(0xFFE3F2FD)
          : const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(
      categorie == 'hebergement' ? Icons.hotel_outlined : Icons.restaurant_outlined,
      color: categorie == 'hebergement' ? const Color(0xFF1E88E5) : const Color(0xFFEF6C00),
    ),
  );
}

class _CritereChip extends StatelessWidget {
  final _Critere critere;
  const _CritereChip(this.critere);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: critere.ok ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: critere.ok
          ? const Color(0xFF4CAF50)
          : const Color(0xFFFFB74D)),
    ),
    child: Text(
      '${critere.ok ? "✓" : "✗"} ${critere.label}',
      style: TextStyle(
        fontSize: 10,
        color: critere.ok ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey),
          overflow: TextOverflow.ellipsis)),
    ]),
  );
}

class _Critere {
  final String label;
  final bool ok;
  const _Critere(this.label, this.ok);
}
