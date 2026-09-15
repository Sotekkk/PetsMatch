import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'morpho_constants.dart';
import 'morpho_form_page.dart';
import 'morpho_detail_page.dart';

/// Onglet "Suivi morphologique & bien-être" — timeline des suivis d'un
/// animal, embarquable dans n'importe quelle fiche (particulier, éleveur,
/// pro santé/véto). [canWrite] est calculé par la fiche hôte (mêmes règles
/// que le reste du carnet de santé : propriétaire/éleveur toujours, pro
/// externe seulement si accès accordé) — ce widget ne re-dérive pas les
/// permissions lui-même.
class MorphoTimelineTab extends StatefulWidget {
  final String animalId;
  final String espece;
  final bool canWrite;
  /// Renseigné quand l'auteur est un professionnel (source = 'professionnel').
  final String? proProfileId;
  final String? proNom;

  const MorphoTimelineTab({
    super.key,
    required this.animalId,
    required this.espece,
    this.canWrite = true,
    this.proProfileId,
    this.proNom,
  });

  @override
  State<MorphoTimelineTab> createState() => _MorphoTimelineTabState();
}

class _MorphoTimelineTabState extends State<MorphoTimelineTab> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _suivis = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supa.from('suivis_morpho').select()
          .eq('animal_id', widget.animalId).order('date', ascending: false);
      if (mounted) setState(() { _suivis = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _nouveauSuivi() async {
    final created = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => MorphoFormPage(
        animalId: widget.animalId,
        espece: widget.espece,
        proProfileId: widget.proProfileId,
        proNom: widget.proNom,
      ),
    ));
    if (created == true) _load();
  }

  Future<void> _ouvrir(Map<String, dynamic> s) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => MorphoDetailPage(suivi: s, espece: widget.espece, readOnly: !widget.canWrite),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!morphoSpeciesSupported(widget.espece)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Le suivi morphologique est disponible pour chien et chat pour le moment.',
              textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator(color: kMorphoTeal));

    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF1F5F4), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(kMorphoAvertissement,
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600))),
        ]),
      ),
      if (widget.canWrite)
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _nouveauSuivi,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nouveau suivi', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kMorphoTeal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        )
      else
        const SizedBox(height: 12),
      Expanded(
        child: _suivis.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.accessibility_new, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Aucun suivi pour l\'instant', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                ]),
              )
            : RefreshIndicator(
                onRefresh: _load,
                color: kMorphoTeal,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _suivis.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _SuiviCard(suivi: _suivis[i], onTap: () => _ouvrir(_suivis[i])),
                ),
              ),
      ),
    ]);
  }
}

class _SuiviCard extends StatelessWidget {
  final Map<String, dynamic> suivi;
  final VoidCallback onTap;
  const _SuiviCard({required this.suivi, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(suivi['date']?.toString() ?? '');
    final source = suivi['source']?.toString() ?? 'proprietaire';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.accessibility_new, color: kMorphoTeal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(labelTypeSuivi(suivi['type_suivi']?.toString()),
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: kMorphoDark)),
              const SizedBox(height: 2),
              Text([
                if (date != null) DateFormat('d MMM yyyy', 'fr_FR').format(date),
                if (suivi['checkpoint_age'] != null && (suivi['checkpoint_age'] as String).isNotEmpty) suivi['checkpoint_age'],
                kSourceLabels[source] ?? '',
              ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }
}
