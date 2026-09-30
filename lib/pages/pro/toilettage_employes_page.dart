import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_prestations_page.dart' show kTypesPrestationToilettage;
import 'package:PetsMatch/pages/pro/toilettage_abonnement_page.dart';
import 'package:PetsMatch/widgets/employe_conges_section.dart';

const kJoursSemaine = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const kCouleursPlanning = ['#FFB74D', '#4DB6AC', '#7986CB', '#F06292', '#81C784', '#BA68C8'];

/// Employés enrichis (toiletteur, Premium) — couleur planning, compétences
/// (prestations autorisées), horaires, congés. Vient en complément de
/// EmployesPage (invitation/permissions générique, déjà fonctionnelle et
/// corrigée cross-profil cette session) plutôt que la remplacer.
class ToilettageEmployesPage extends StatefulWidget {
  const ToilettageEmployesPage({super.key});

  @override
  State<ToilettageEmployesPage> createState() => _ToilettageEmployesPageState();
}

class _ToilettageEmployesPageState extends State<ToilettageEmployesPage> {
  static const _orange = Color(0xFFFFB74D);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _hasPlanningEmployes = false;
  List<Map<String, dynamic>> _employes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final results = await Future.wait([
        PlanService.getToilettagePlanCode(uid),
        pid.isNotEmpty
            // .neq('type', 'benevole') excluait TOUT le monde : ce champ
            // n'est jamais renseigné pour un employé normal (seuls les
            // bénévoles association l'ont), et NULL != 'benevole' n'est
            // jamais vrai en SQL — donc les lignes NULL étaient exclues.
            ? _supa.from('employes').select().eq('eleveur_profile_id', pid).eq('actif', true).or('type.is.null,type.neq.benevole')
            : Future.value(<Map<String, dynamic>>[]),
      ]);
      final planCode = results[0] as String;
      final rows = List<Map<String, dynamic>>.from(results[1] as List);

      // `employes.prenom`/`nom` ne sont renseignés QUE pour un contact ajouté
      // manuellement (sans compte PetsMatch) — un employé invité via son
      // compte (le cas normal) n'a que `employe_profile_id`, d'où le nom/la
      // photo manquants ici. On résout ces cas via user_profiles, comme le
      // fait déjà _EmployesTab (employes_page.dart).
      final profileIds = rows
          .map((e) => e['employe_profile_id'] as String?)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (profileIds.isNotEmpty) {
        final profiles = await _supa.from('user_profiles')
            .select('id, firstname, lastname, avatar_url')
            .inFilter('id', profileIds);
        final byId = { for (final p in (profiles as List)) p['id'] as String: p };
        for (final e in rows) {
          final p = byId[e['employe_profile_id']];
          if (p == null) continue;
          final nom = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          if (nom.isNotEmpty) { e['prenom'] = p['firstname']; e['nom'] = p['lastname']; }
          e['_avatar_url'] = p['avatar_url'];
        }
      }

      if (mounted) setState(() {
        _hasPlanningEmployes = PlanService.getToilettageConfig(planCode).hasPlanningEmployes;
        _employes = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEdit(Map<String, dynamic> employe) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EmployeToilettageForm(employe: employe),
    );
    if (result == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        title: const Text('Mes employés', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Inviter un employé',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployesPage(profileType: 'toilettage'))),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : !_hasPlanningEmployes
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock_outline, size: 40, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('Fonctionnalité réservée à la formule Premium',
                          textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text('Couleur planning, compétences, horaires et congés par employé.',
                          textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToilettageAbonnementPage())),
                        style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white),
                        child: const Text('Voir les formules', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                )
              : _employes.isEmpty
                  ? const Center(child: Text('Aucun employé actif.\nInvitez-en un avec le bouton en haut à droite.',
                      textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _employes.length,
                      itemBuilder: (_, i) {
                        final e = _employes[i];
                        final couleur = Color(int.parse((e['couleur_planning'] as String? ?? '#FFB74D').replaceFirst('#', '0xFF')));
                        final competences = (e['competences'] as List?) ?? [];
                        final nom = '${e['prenom'] ?? ''} ${e['nom'] ?? ''}'.trim();
                        final photo = e['_avatar_url'] as String?;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            onTap: () => _openEdit(e),
                            leading: Stack(clipBehavior: Clip.none, children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: couleur.withValues(alpha: 0.2),
                                backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                                child: (photo == null || photo.isEmpty)
                                    ? Icon(Icons.person, color: couleur, size: 18) : null,
                              ),
                              Positioned(
                                right: -1, bottom: -1,
                                child: Container(
                                  width: 10, height: 10,
                                  decoration: BoxDecoration(
                                    color: couleur, shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                ),
                              ),
                            ]),
                            title: Text(nom.isEmpty ? 'Employé' : nom,
                                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: Text(competences.isEmpty
                                ? 'Toutes prestations'
                                : competences.map((c) => kTypesPrestationToilettage[c] ?? c).join(', '),
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _EmployeToilettageForm extends StatefulWidget {
  final Map<String, dynamic> employe;
  const _EmployeToilettageForm({required this.employe});

  @override
  State<_EmployeToilettageForm> createState() => _EmployeToilettageFormState();
}

class _EmployeToilettageFormState extends State<_EmployeToilettageForm> {
  static const _orange = Color(0xFFFFB74D);
  final _supa = Supabase.instance.client;

  late String _couleur;
  late Set<String> _competences;
  late Map<String, dynamic> _horaires;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _couleur = widget.employe['couleur_planning'] as String? ?? kCouleursPlanning.first;
    _competences = ((widget.employe['competences'] as List?)?.cast<String>().toSet()) ?? {};
    _horaires = Map<String, dynamic>.from((widget.employe['horaires'] as Map?) ?? {});
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await _supa.from('employes').update({
        'couleur_planning': _couleur,
        'competences': _competences.toList(),
        'horaires': _horaires,
      }).eq('id', widget.employe['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom = '${widget.employe['prenom'] ?? ''} ${widget.employe['nom'] ?? ''}'.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nom.isEmpty ? 'Employé' : nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 16),
          Text('Couleur planning', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: kCouleursPlanning.map((c) {
            final color = Color(int.parse(c.replaceFirst('#', '0xFF')));
            final selected = _couleur == c;
            return GestureDetector(
              onTap: () => setState(() => _couleur = c),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                    border: selected ? Border.all(color: Colors.black87, width: 2) : null),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),
          Text('Prestations autorisées (vide = toutes)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: kTypesPrestationToilettage.entries.map((entry) {
            final selected = _competences.contains(entry.key);
            return FilterChip(
              label: Text(entry.value, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              selected: selected,
              selectedColor: _orange.withValues(alpha: 0.2),
              onSelected: (v) => setState(() => v ? _competences.add(entry.key) : _competences.remove(entry.key)),
            );
          }).toList()),
          const SizedBox(height: 16),
          Text('Jours travaillés', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: kJoursSemaine.map((j) {
            final selected = _horaires.containsKey(j);
            return FilterChip(
              label: Text(j, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              selected: selected,
              selectedColor: _orange.withValues(alpha: 0.2),
              onSelected: (v) => setState(() {
                if (v) { _horaires[j] = {'debut': '09:00', 'fin': '18:00'}; } else { _horaires.remove(j); }
              }),
            );
          }).toList()),
          const SizedBox(height: 16),
          EmployeCongesSection(
            employeId: widget.employe['id'],
            employeUidEmploye: widget.employe['uid_employe'] as String?,
            employeProfileId: widget.employe['employe_profile_id'] as String?,
            color: _orange,
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: _orange, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          )),
        ]),
      ),
    );
  }
}
