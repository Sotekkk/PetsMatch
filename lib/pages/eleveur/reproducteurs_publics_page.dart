import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart'
    show speciesLabel, speciesColor, speciesIcon;

const _teal = Color(0xFF0C5C6C);
const _dark = Color(0xFF1F2A2E);

/// Vitrine publique des reproducteurs qu'un éleveur a choisi d'exposer
/// (`animaux.reproducteur_public = true` + `user_profiles.montre_reproducteurs`).
/// Lecture seule, groupée par espèce puis race.
class ReproducteursPublicsPage extends StatefulWidget {
  final String uid;
  final String nomElevage;
  const ReproducteursPublicsPage({super.key, required this.uid, required this.nomElevage});

  @override
  State<ReproducteursPublicsPage> createState() => _ReproducteursPublicsPageState();
}

class _ReproducteursPublicsPageState extends State<ReproducteursPublicsPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _repros = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Profil ÉLEVEUR de ce compte uniquement — jamais un autre profil du
      // même uid (association, pension…), pour éviter toute fuite cross-profil.
      final prof = await _supa
          .from('user_profiles')
          .select('id, montre_reproducteurs')
          .eq('uid', widget.uid)
          .eq('profile_type', 'eleveur')
          .maybeSingle();
      final profileId = prof?['id'] as String?;
      if (profileId == null || prof?['montre_reproducteurs'] != true) {
        if (mounted) setState(() { _repros = []; _loading = false; });
        return;
      }
      final rows = await _supa
          .from('animaux')
          .select('id, nom, nom_pedigree, espece, espece_autre, race, sexe, '
              'photo_url, date_naissance, couleur, pedigree_lof, pedigree_numero, '
              'club_registre, description, is_retraite')
          .eq('profile_id', profileId)
          .eq('uid_eleveur', widget.uid)
          .eq('reproducteur_public', true)
          .order('espece')
          .order('race')
          .order('nom');
      if (mounted) {
        setState(() {
          _repros = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// { espèce : { race : [animaux] } }
  Map<String, Map<String, List<Map<String, dynamic>>>> get _grouped {
    final out = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final a in _repros) {
      final esp = (a['espece'] as String?)?.isNotEmpty == true
          ? a['espece'] as String
          : 'autre';
      final race = (a['race'] as String?)?.trim().isNotEmpty == true
          ? (a['race'] as String).trim()
          : 'Sans race renseignée';
      out.putIfAbsent(esp, () => {}).putIfAbsent(race, () => []).add(a);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Reproducteurs',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
          if (widget.nomElevage.isNotEmpty)
            Text(widget.nomElevage,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w400, fontSize: 12)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _repros.isEmpty
              ? _empty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                  children: [
                    for (final esp in _grouped.keys) ...[
                      _especeHeader(esp),
                      for (final race in _grouped[esp]!.keys) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                          child: Text(race,
                              style: TextStyle(
                                  fontFamily: 'Galey', fontWeight: FontWeight.w600,
                                  fontSize: 13, color: Colors.grey.shade600)),
                        ),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.74,
                          children: _grouped[esp]![race]!
                              .map((a) => _ReproCard(
                                    data: a,
                                    onTap: () => _openFiche(a),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
    );
  }

  Widget _especeHeader(String esp) {
    final color = speciesColor(esp);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
      child: Row(children: [
        speciesIcon(esp, 16, color),
        const SizedBox(width: 8),
        Text(speciesLabel(esp),
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
      ]),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.pets_outlined, size: 48, color: Color(0xFFB0B8C1)),
            const SizedBox(height: 12),
            const Text('Aucun reproducteur affiché',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _dark)),
          ]),
        ),
      );

  void _openFiche(Map<String, dynamic> a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReproFichePublique(data: a),
    );
  }
}

// ── Utilitaires ──────────────────────────────────────────────────────────────

String _ageLabel(dynamic raw) {
  final d = raw == null ? null : DateTime.tryParse(raw.toString());
  if (d == null) return '';
  final now = DateTime.now();
  var mois = (now.year - d.year) * 12 + (now.month - d.month);
  if (now.day < d.day) mois -= 1;
  if (mois < 0) mois = 0;
  if (mois < 12) return '$mois mois';
  final ans = mois ~/ 12;
  return '$ans an${ans > 1 ? 's' : ''}';
}

IconData _sexeIcon(String? sexe) {
  final s = (sexe ?? '').toLowerCase();
  if (s.startsWith('m') || s.startsWith('mâle') || s == 'male') return Icons.male;
  if (s.startsWith('f')) return Icons.female;
  return Icons.pets;
}

Color _sexeColor(String? sexe) {
  final s = (sexe ?? '').toLowerCase();
  if (s.startsWith('m')) return const Color(0xFF3B82F6);
  if (s.startsWith('f')) return const Color(0xFFEC4899);
  return Colors.grey;
}

// ── Carte ────────────────────────────────────────────────────────────────────

class _ReproCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _ReproCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final photoUrl = data['photo_url'] as String?;
    final nom = (data['nom'] as String?)?.trim().isNotEmpty == true
        ? (data['nom'] as String).trim()
        : 'Sans nom';
    final pedigree = (data['nom_pedigree'] as String?)?.trim() ?? '';
    final race = (data['race'] as String?)?.trim() ?? '';
    final espece = (data['espece'] as String?) ?? '';
    final age = _ageLabel(data['date_naissance']);
    final retraite = data['is_retraite'] == true;
    final color = speciesColor(espece);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(fit: StackFit.expand, children: [
              (photoUrl != null && photoUrl.isNotEmpty)
                  ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
                  : Container(
                      color: color.withValues(alpha: 0.12),
                      child: Center(child: speciesIcon(espece, 40, color)),
                    ),
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: _sexeColor(data['sexe']), shape: BoxShape.circle),
                  child: Icon(_sexeIcon(data['sexe']), size: 12, color: Colors.white),
                ),
              ),
              if (retraite)
                Positioned(
                  top: 6, left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFFB45309), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Retraité',
                        style: TextStyle(color: Colors.white, fontSize: 8, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _dark)),
              if (pedigree.isNotEmpty)
                Text(pedigree,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text([if (race.isNotEmpty) race, if (age.isNotEmpty) age].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Fiche publique détaillée (lecture seule) ─────────────────────────────────

class _ReproFichePublique extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReproFichePublique({required this.data});

  @override
  Widget build(BuildContext context) {
    final photoUrl = data['photo_url'] as String?;
    final nom = (data['nom'] as String?)?.trim() ?? 'Reproducteur';
    final pedigree = (data['nom_pedigree'] as String?)?.trim() ?? '';
    final espece = (data['espece'] as String?) ?? '';
    final race = (data['race'] as String?)?.trim() ?? '';
    final couleur = (data['couleur'] as String?)?.trim() ?? '';
    final desc = (data['description'] as String?)?.trim() ?? '';
    final dn = data['date_naissance'] == null
        ? null
        : DateTime.tryParse(data['date_naissance'].toString());
    final age = _ageLabel(data['date_naissance']);
    final lof = (data['pedigree_lof'] as String?)?.trim() ?? '';
    final pedNum = (data['pedigree_numero'] as String?)?.trim() ?? '';
    final club = (data['club_registre'] as String?)?.trim() ?? '';
    final color = speciesColor(espece);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1.1,
              child: (photoUrl != null && photoUrl.isNotEmpty)
                  ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
                  : Container(
                      color: color.withValues(alpha: 0.12),
                      child: Center(child: speciesIcon(espece, 56, color)),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(nom,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: _dark)),
            ),
            Icon(_sexeIcon(data['sexe']), color: _sexeColor(data['sexe'])),
          ]),
          if (pedigree.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(pedigree,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
            ),
          const SizedBox(height: 12),
          _line('Espèce', speciesLabel(espece)),
          _line('Race', race),
          if (dn != null) _line('Naissance', '${DateFormat('dd/MM/yyyy').format(dn)}${age.isNotEmpty ? '  ·  $age' : ''}'),
          _line('Couleur / robe', couleur),
          _line('N° LOF / pedigree', [lof, pedNum].where((e) => e.isNotEmpty).join(' · ')),
          _line('Club / registre', club),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Présentation',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.black87)),
          ],
          const SizedBox(height: 14),
          _TestsBadges(animalId: data['id'] as String),
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: _dark)),
        ),
      ]),
    );
  }
}

/// Badges des tests de santé renseignés (ADN, hanches, santé reproducteur,
/// filiation) — d'après `documents_animaux`, sans exposer les fichiers.
class _TestsBadges extends StatefulWidget {
  final String animalId;
  const _TestsBadges({required this.animalId});
  @override
  State<_TestsBadges> createState() => _TestsBadgesState();
}

class _TestsBadgesState extends State<_TestsBadges> {
  static const _labels = {
    'adn': 'Test ADN',
    'hanches': 'Test hanches',
    'sante_repro': 'Santé reproducteur',
    'filiation': 'Filiation',
  };
  Set<String> _types = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('documents_animaux')
          .select('type')
          .eq('animal_id', widget.animalId)
          .inFilter('type', _labels.keys.toList());
      if (mounted) {
        setState(() => _types =
            {for (final r in (rows as List)) r['type'] as String});
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_types.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Tests renseignés',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in _types)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF5EA),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 13, color: Color(0xFF6E9E57)),
              const SizedBox(width: 5),
              Text(_labels[t] ?? t,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4d7a3c))),
            ]),
          ),
      ]),
    ]);
  }
}
