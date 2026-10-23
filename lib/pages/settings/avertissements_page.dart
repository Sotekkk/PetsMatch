import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

const _teal = Color(0xFF0C5C6C);

/// Décisions de modération visant le compte (table sanctions_moderation,
/// écrite par l'API admin). Paramètres → Connexion et sécurité →
/// Avertissements ; la notification « moderation » ouvre cette page.
/// Miroir site : /profil/avertissements.
class Avertissements {
  /// Sanctions pas encore vues (vue_le null) : bulle rouge dans les menus.
  static final ValueNotifier<int> nonVus = ValueNotifier<int>(0);

  static Future<void> rafraichir() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { nonVus.value = 0; return; }
    try {
      final rows = await Supabase.instance.client.from('sanctions_moderation')
          .select('id').eq('uid', uid).isFilter('vue_le', null);
      nonVus.value = (rows as List).length;
    } catch (_) {
      // Colonne vue_le absente (migration_sanctions_vues.sql pas encore passée).
      nonVus.value = 0;
    }
  }

  static Future<void> marquerVues() async {
    try {
      await Supabase.instance.client.rpc('marquer_sanctions_vues');
    } catch (_) {}
    nonVus.value = 0;
  }
}

/// Pastille rouge posée sur une icône de menu (ex. « Paramètres »).
class PastilleAvertissements extends StatefulWidget {
  final Widget child;
  const PastilleAvertissements({super.key, required this.child});

  @override
  State<PastilleAvertissements> createState() => _PastilleAvertissementsState();
}

class _PastilleAvertissementsState extends State<PastilleAvertissements> {
  @override
  void initState() {
    super.initState();
    Avertissements.rafraichir();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: Avertissements.nonVus,
        builder: (_, n, child) => Stack(clipBehavior: Clip.none, children: [
          child!,
          if (n > 0)
            Positioned(
              right: -3, top: -3,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5)),
              ),
            ),
        ]),
        child: widget.child,
      );
}

/// Bulle rouge avec le nombre, en fin de ligne de menu.
class BulleAvertissements extends StatelessWidget {
  const BulleAvertissements({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: Avertissements.nonVus,
        builder: (_, n, __) => n <= 0
            ? const SizedBox.shrink()
            : Container(
                margin: const EdgeInsets.only(right: 8),
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w700, fontFamily: 'Galey')),
              ),
      );
}

class AvertissementsPage extends StatefulWidget {
  const AvertissementsPage({super.key});

  @override
  State<AvertissementsPage> createState() => _AvertissementsPageState();
}

class _AvertissementsPageState extends State<AvertissementsPage> {
  List<Map<String, dynamic>> _sanctions = [];
  Set<String> _nouvelles = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    List<Map<String, dynamic>> rows = [];
    try {
      final r = await Supabase.instance.client.from('sanctions_moderation')
          .select('id, type, regle, precisions, fin_le, leve_le, contenu, created_at, vue_le')
          .eq('uid', uid).order('created_at', ascending: false);
      rows = List<Map<String, dynamic>>.from(r as List);
    } catch (_) {
      // Sans la colonne vue_le : même liste, sans repère « nouveau ».
      try {
        final r = await Supabase.instance.client.from('sanctions_moderation')
            .select('id, type, regle, precisions, fin_le, leve_le, contenu, created_at')
            .eq('uid', uid).order('created_at', ascending: false);
        rows = List<Map<String, dynamic>>.from(r as List);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _sanctions = rows;
      _nouvelles = rows.where((s) => s.containsKey('vue_le') && s['vue_le'] == null)
          .map((s) => s['id'].toString()).toSet();
      _loading = false;
    });
    // Ouvrir la page vaut lecture : la bulle rouge disparaît ; le repère
    // « Nouveau » reste affiché jusqu'à la prochaine visite.
    if (_nouvelles.isNotEmpty) await Avertissements.marquerVues();
  }

  static String _date(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    return d == null ? '' : DateFormat('d MMMM yyyy', 'fr_FR').format(d);
  }

  (String, IconData, Color) _libelle(Map<String, dynamic> s) {
    switch (s['type']) {
      case 'suspension':
        final fin = _date(s['fin_le'] as String?);
        final levee = s['leve_le'] != null
            || (DateTime.tryParse(s['fin_le'] as String? ?? '')?.isBefore(DateTime.now()) ?? false);
        return (levee ? 'Suspension terminée' : 'Compte suspendu jusqu\'au $fin',
            Icons.pause_circle_outline, const Color(0xFFD97706));
      case 'blocage':
        return ('Compte bloqué', Icons.block, Colors.red);
      case 'suppression':
        return ('Contenu retiré', Icons.delete_outline, const Color(0xFF6B7280));
      default:
        return ('Avertissement', Icons.warning_amber_rounded, const Color(0xFFD97706));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Avertissements',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              color: _teal,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: const Color(0xFFE6F4F7), borderRadius: BorderRadius.circular(14)),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline, color: _teal, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                        'Les décisions de l\'équipe de modération sur votre compte, avec la règle concernée. '
                        'Pour contester une décision, utilisez « Poser une question » dans Connexion et sécurité.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal, height: 1.35))),
                    ]),
                  ),
                  if (_sanctions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Column(children: [
                        Icon(Icons.verified_user_outlined, size: 48, color: Color(0xFF6E9E57)),
                        SizedBox(height: 12),
                        Text('Aucun avertissement', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 16, color: Color(0xFF1F2A2E))),
                        SizedBox(height: 4),
                        Text('Votre compte est en règle.', style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                            color: Color(0xFF9CA3AF))),
                      ]),
                    )
                  else
                    ..._sanctions.map(_carte),
                ],
              ),
            ),
    );
  }

  Widget _carte(Map<String, dynamic> s) {
    final (titre, icone, couleur) = _libelle(s);
    final contenu = s['contenu'] is Map ? Map<String, dynamic>.from(s['contenu'] as Map) : null;
    final extrait = contenu?['extrait']?.toString().trim() ?? '';
    final precisions = (s['precisions'] as String?)?.trim() ?? '';
    final nouveau = _nouvelles.contains(s['id'].toString());
    const corps = TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF5E6B70), height: 1.4);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: nouveau ? Border.all(color: Colors.red.shade200) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icone, color: couleur, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15,
                color: Color(0xFF1F2A2E))),
            Text(_date(s['created_at'] as String?), style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                color: Color(0xFF9CA3AF))),
          ])),
          if (nouveau)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
              child: const Text('Nouveau', style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                  fontWeight: FontWeight.w700, color: Colors.white)),
            ),
        ]),
        const SizedBox(height: 12),
        Text.rich(TextSpan(style: corps, children: [
          const TextSpan(text: 'Règle enfreinte : ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
          TextSpan(text: s['regle']?.toString() ?? ''),
        ])),
        if (precisions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(precisions, style: corps),
        ],
        if (extrait.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
            child: Text('« $extrait »', maxLines: 4, overflow: TextOverflow.ellipsis,
                style: corps.copyWith(fontStyle: FontStyle.italic)),
          ),
        ],
      ]),
    );
  }
}
