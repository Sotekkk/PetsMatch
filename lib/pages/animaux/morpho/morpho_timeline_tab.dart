import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/services/acces_animal_service.dart';
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
  // Pro (proProfileId renseigné) : accès réel à l'animal — sans accès
  // accordé par le propriétaire, la base refuse l'enregistrement.
  String? _acces;
  bool _demandeEnCours = false;
  bool _accesCharge = false;

  bool get _modePro => widget.canWrite && widget.proProfileId != null;
  bool get _peutEcrire => widget.canWrite &&
      (!_modePro || const ['proprietaire', 'active', 'active_write'].contains(_acces));

  Future<void> _chargerAcces() async {
    if (!_modePro) return;
    try {
      final a = await AccesAnimalService.statut(widget.animalId);
      if (mounted) setState(() => _acces = a);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _accesCharge = true);
    }
  }

  Future<void> _demanderAcces() async {
    setState(() => _demandeEnCours = true);
    try {
      final statut = await AccesAnimalService.demander(widget.animalId);
      if (mounted) {
        setState(() => _acces = statut == 'envoyee' ? 'pending' : statut);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Demande envoyée au propriétaire', style: TextStyle(fontFamily: 'Galey'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Demande impossible : ${e is PostgrestException ? e.message : e}', style: const TextStyle(fontFamily: 'Galey')),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _demandeEnCours = false);
    }
  }

  Widget _bandeauAcces() {
    final enAttente = _acces == 'pending';
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: enAttente ? const Color(0xFFFFF7E6) : const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enAttente ? const Color(0xFFF5C26B) : const Color(0xFFF2A7A7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(enAttente ? Icons.hourglass_top_rounded : Icons.lock_outline,
              size: 18, color: enAttente ? const Color(0xFFB7791F) : const Color(0xFFC53030)),
          const SizedBox(width: 8),
          Expanded(child: Text(enAttente ? "Demande d'accès envoyée" : 'Accès non autorisé',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14))),
        ]),
        const SizedBox(height: 6),
        Text(enAttente
              ? "En attente de la réponse du propriétaire. Vous pourrez créer des suivis dès qu'il aura accepté."
              : "Le propriétaire ne vous a pas encore donné accès au dossier de cet animal. Demandez-lui l'accès pour enregistrer des suivis.",
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
        if (!enAttente) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _demandeEnCours ? null : _demanderAcces,
              icon: const Icon(Icons.vpn_key_outlined, size: 18),
              label: Text(_demandeEnCours ? 'Envoi…' : "Demander l'accès",
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kMorphoTeal, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _chargerAcces();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supa.from('suivis_morpho').select()
          .eq('animal_id', widget.animalId).order('date', ascending: false);
      // Bilan d'un pro NON ENVOYÉ : visible seulement de son profil auteur.
      // La RLS le cache aux autres comptes ; ce filtre couvre le même compte
      // (ex. profil ostéo + profil élevage propriétaire de l'animal).
      final pid = widget.proProfileId;
      final visibles = List<Map<String, dynamic>>.from(rows as List).where((s) =>
          s['source'] != 'professionnel' ||
          s['notifie_a'] != null ||
          (pid != null && s['pro_profile_id']?.toString() == pid)).toList();
      if (mounted) setState(() { _suivis = visibles; _loading = false; });
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
          child: Text('Le suivi morphologique est disponible pour le chien, le chat et le cheval pour le moment.',
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
      if (_modePro && !_accesCharge)
        const SizedBox(height: 12)
      else if (_modePro && !_peutEcrire)
        _bandeauAcces()
      else if (_peutEcrire)
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
