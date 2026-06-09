import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/pro/compte_rendu_page.dart';
import 'package:PetsMatch/widgets/pro_day_timeline.dart';

/// Tableau de bord commun pour les pros non-vétérinaires :
/// - cat_pro = 'sante'     → ostéo, kiné, naturo, acupuncteur, homéopathe
/// - cat_pro = 'education' → comportementaliste, éducateur, dresseur
/// - cat_pro = 'garde'     → pet sitter, promeneur
///
/// Affiche les animaux ayant eu un accès accordé (animal_acces_pro) + agenda.
class ProClientsPage extends StatefulWidget {
  const ProClientsPage({super.key});

  @override
  State<ProClientsPage> createState() => _ProClientsPageState();
}

class _ProClientsPageState extends State<ProClientsPage>
    with SingleTickerProviderStateMixin {

  static const _especes = ['chien','chat','cheval','lapin','oiseau','nac','ovin','caprin','porcin','ane','autre'];
  static const _especeEmoji = {
    'chien':'🐕','chat':'🐈','cheval':'🐴','lapin':'🐰',
    'oiseau':'🦜','nac':'🦎','ovin':'🐑','caprin':'🐐','porcin':'🐷','ane':'🐴','autre':'🐾',
  };

  late TabController _tabCtrl;
  bool _loading = true;
  List<Map<String, dynamic>> _animals = [];
  String _search = '';
  String? _filterEspece;

  bool _loadingAgenda = false;
  DateTime _agendaDate = DateTime.now();
  List<Map<String, dynamic>> _rdvsJour = [];

  Color get _color {
    switch (User_Info.catPro) {
      case 'education': return const Color(0xFFEF6C00);
      case 'garde':     return const Color(0xFF26A69A);
      default:          return const Color(0xFFE91E63); // sante
    }
  }

  String get _pageTitle {
    switch (User_Info.catPro) {
      case 'education': return 'Mes animaux suivis';
      case 'garde':     return 'Mes animaux en garde';
      default:          return 'Mes patients';
    }
  }

  String get _emptyLabel {
    switch (User_Info.catPro) {
      case 'education': return 'Aucun animal suivi pour l\'instant';
      case 'garde':     return 'Aucun animal en garde pour l\'instant';
      default:          return 'Aucun patient pour l\'instant';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging && _tabCtrl.index == 1 && !_loadingAgenda) {
        setState(() => _rdvsJour = []);
        _loadAgenda();
      }
    });
    _loadAnimals();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Chargement ───────────────────────────────────────────────────────────────

  Future<void> _loadAnimals() async {
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    if (proUid == null) { setState(() => _loading = false); return; }

    try {
      final supa = Supabase.instance.client;

      // Accès accordés via animal_acces_pro
      final grants = await supa
          .from('animal_acces_pro')
          .select('animal_id, granted_at, owner_uid')
          .eq('pro_uid', proUid)
          .order('granted_at', ascending: false);

      // Compléter avec les animaux des RDVs qui n'ont pas encore d'accès accordé
      final rdvAnimals = await supa
          .from('rdv')
          .select('animal_id, client_uid, date_heure')
          .eq('pro_uid', proUid)
          .inFilter('statut', ['confirme', 'termine'])
          .not('animal_id', 'is', null);

      // Union des IDs animaux
      final Map<String, Map<String, dynamic>> seen = {};
      for (final g in grants as List) {
        final id = g['animal_id']?.toString();
        if (id != null) seen[id] = {'animal_id': id, 'owner_uid': g['owner_uid'], 'granted_at': g['granted_at']};
      }
      for (final r in rdvAnimals as List) {
        final id = r['animal_id']?.toString();
        if (id != null && !seen.containsKey(id)) {
          seen[id] = {'animal_id': id, 'owner_uid': r['client_uid']};
        }
      }

      if (seen.isEmpty) {
        if (mounted) setState(() { _animals = []; _loading = false; });
        return;
      }

      final animalIds = seen.keys.toList();
      final animals = await supa
          .from('animaux')
          .select('id, nom, espece, race, sexe, photo_url, date_naissance, uid_eleveur')
          .inFilter('id', animalIds);

      // Noms des propriétaires
      final ownerUids = seen.values
          .map((e) => e['owner_uid'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      Map<String, String> ownerNames = {};
      if (ownerUids.isNotEmpty) {
        final users = await supa
            .from('users')
            .select('uid, firstname, lastname, name_elevage')
            .inFilter('uid', ownerUids);
        for (final u in users) {
          final uid = u['uid'] as String;
          final name = (u['name_elevage'] as String?)?.isNotEmpty == true
              ? u['name_elevage'] as String
              : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
          ownerNames[uid] = name.isNotEmpty ? name : 'Propriétaire';
        }
      }

      if (mounted) {
        setState(() {
          _animals = (animals as List).map<Map<String, dynamic>>((a) {
            final anId = a['id']?.toString() ?? '';
            final extra = seen[anId] ?? {};
            return {
              ...a,
              '_owner_uid': extra['owner_uid'] ?? a['uid_eleveur'],
              '_owner_name': ownerNames[extra['owner_uid'] ?? a['uid_eleveur'] ?? ''] ?? 'Propriétaire',
              '_granted_at': extra['granted_at'],
            };
          }).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAgenda() async {
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    if (proUid == null) return;
    setState(() => _loadingAgenda = true);
    try {
      final supa = Supabase.instance.client;
      final dateStr = _agendaDate.toIso8601String().substring(0, 10);
      final start = DateTime.parse('${dateStr}T00:00:00Z').toIso8601String();
      final end   = DateTime.parse('${dateStr}T23:59:59Z').toIso8601String();

      final rdvs = await supa
          .from('rdv')
          .select()
          .eq('pro_uid', proUid)
          .inFilter('statut', ['confirme', 'termine'])
          .gte('date_heure', start)
          .lte('date_heure', end)
          .order('date_heure', ascending: true);

      if ((rdvs as List).isEmpty) {
        if (mounted) setState(() { _rdvsJour = []; _loadingAgenda = false; });
        return;
      }

      final clientUids = rdvs.map((r) => r['client_uid'] as String?).whereType<String>().toSet().toList();
      final animalIds  = rdvs.map((r) => r['animal_id']?.toString()).whereType<String>().toSet().toList();

      Map<String, String> clientNames = {};
      Map<String, Map<String, dynamic>> animalData = {};

      if (clientUids.isNotEmpty) {
        final users = await supa.from('users').select('uid, firstname, lastname, name_elevage')
            .inFilter('uid', clientUids);
        for (final u in users) {
          final uid = u['uid'] as String;
          final name = (u['name_elevage'] as String?)?.isNotEmpty == true
              ? u['name_elevage'] as String
              : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
          clientNames[uid] = name.isNotEmpty ? name : 'Client';
        }
      }
      if (animalIds.isNotEmpty) {
        final animaux = await supa.from('animaux').select('id, nom, espece, photo_url').inFilter('id', animalIds);
        for (final a in animaux) { animalData[a['id'].toString()] = Map<String, dynamic>.from(a); }
      }

      if (mounted) {
        setState(() {
          _rdvsJour = rdvs.map<Map<String, dynamic>>((r) {
            final cUid = r['client_uid'] as String?;
            final aId  = r['animal_id']?.toString();
            final a    = aId != null ? animalData[aId] : null;
            return {
              ...r,
              '_client_name': cUid != null ? (clientNames[cUid] ?? 'Client') : 'Client',
              '_animal_nom':  a?['nom']?.toString() ?? '',
              '_animal_photo': a?['photo_url']?.toString(),
              '_animal_espece': a?['espece']?.toString() ?? '',
            };
          }).toList();
          _loadingAgenda = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAgenda = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: c,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_pageTitle,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [Tab(text: 'Animaux'), Tab(text: 'Agenda')],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c))
          : TabBarView(
              controller: _tabCtrl,
              children: [_buildAnimalsTab(), _buildAgendaTab()],
            ),
    );
  }

  // ── Onglet animaux ───────────────────────────────────────────────────────────

  Widget _buildAnimalsTab() {
    final c = _color;
    final filtered = _animals.where((a) {
      final nom = (a['nom'] ?? '').toString().toLowerCase();
      if (_search.isNotEmpty && !nom.contains(_search.toLowerCase())) return false;
      if (_filterEspece != null && a['espece'] != _filterEspece) return false;
      return true;
    }).toList();

    return Column(children: [
      // Barre recherche + filtre espèce
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher un animal…',
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String?>(
            onSelected: (v) => setState(() => _filterEspece = v),
            icon: Icon(Icons.filter_list_outlined, color: _filterEspece != null ? c : Colors.grey),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Toutes les espèces',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
              ..._especes.map((e) => PopupMenuItem(value: e,
                  child: Text('${_especeEmoji[e] ?? '🐾'} ${e[0].toUpperCase()}${e.substring(1)}',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13)))),
            ],
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: filtered.isEmpty
            ? _emptyState()
            : RefreshIndicator(
                onRefresh: _loadAnimals,
                color: c,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _AnimalCard(
                    animal: filtered[i],
                    color: c,
                    catPro: User_Info.catPro,
                    onTap: () => _openAnimal(filtered[i]),
                    onCompteRendu: () => _openCompteRendu(filtered[i]),
                    onProgression: User_Info.catPro == 'education'
                        ? () => _addProgression(filtered[i])
                        : null,
                  ),
                ),
              ),
      ),
    ]);
  }

  Widget _emptyState() {
    return ListView(children: [
      const SizedBox(height: 80),
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.pets, size: 60, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(_emptyLabel,
            style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey.shade400)),
        const SizedBox(height: 8),
        Text('Les animaux apparaissent ici après un RDV confirmé.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
      ])),
    ]);
  }

  void _openAnimal(Map<String, dynamic> animal) {
    final animalId = animal['id']?.toString() ?? '';
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnimalFichePage(
        animalId: animalId,
        readOnly: true,
        vetMode: User_Info.catPro == 'sante' || User_Info.catPro == 'veterinaire',
      ),
    ));
  }

  void _openCompteRendu(Map<String, dynamic> animal) {
    final ownerUid = animal['_owner_uid']?.toString() ?? '';
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CompteRenduPage(
        rdv: null,
        animalId: animal['id']?.toString() ?? '',
        ownerUid: ownerUid,
        clientName: animal['_owner_name']?.toString() ?? 'Client',
        categoryColor: _color,
        isPension: User_Info.catPro == 'garde',
      ),
    ));
  }

  Future<void> _addProgression(Map<String, dynamic> animal) async {
    final animalNom = animal['nom']?.toString() ?? 'Animal';
    final contenuCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          Text('Rapport de séance — $animalNom',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          TextField(
            controller: contenuCtrl,
            maxLines: 5,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Compte rendu de la séance, exercices réalisés, progrès observés…',
              hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _color, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Enregistrer',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );

    if (ok != true || !mounted) return;

    final proUid = FirebaseAuth.instance.currentUser?.uid;
    if (proUid == null) return;

    try {
      await Supabase.instance.client.from('education_progression').insert({
        'pro_uid':    proUid,
        'animal_id':  animal['id']?.toString() ?? '',
        'owner_uid':  animal['_owner_uid']?.toString(),
        'date_seance': DateTime.now().toIso8601String().substring(0, 10),
        'contenu':    contenuCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rapport de séance enregistré.',
              style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Onglet agenda ────────────────────────────────────────────────────────────

  Widget _buildAgendaTab() {
    final c = _color;
    return Column(children: [
      // Sélecteur date
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: c),
            onPressed: () {
              setState(() => _agendaDate = _agendaDate.subtract(const Duration(days: 1)));
              _loadAgenda();
            },
          ),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _agendaDate,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  locale: const Locale('fr'),
                );
                if (picked != null) {
                  setState(() => _agendaDate = picked);
                  _loadAgenda();
                }
              },
              child: Center(
                child: Text(
                  _formatDate(_agendaDate),
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 15, color: c),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: c),
            onPressed: () {
              setState(() => _agendaDate = _agendaDate.add(const Duration(days: 1)));
              _loadAgenda();
            },
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _loadingAgenda
            ? Center(child: CircularProgressIndicator(color: c))
            : _rdvsJour.isEmpty
                ? _emptyAgenda()
                : ProDayTimeline(rdvs: _rdvsJour, date: _agendaDate),
      ),
    ]);
  }

  Widget _emptyAgenda() {
    return ListView(children: [
      const SizedBox(height: 80),
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.event_available_outlined, size: 60, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('Aucun RDV ce jour',
            style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey.shade400)),
      ])),
    ]);
  }

  String _formatDate(DateTime d) {
    const jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    const mois = ['jan.', 'fév.', 'mar.', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.'];
    final isToday = d.year == DateTime.now().year &&
        d.month == DateTime.now().month && d.day == DateTime.now().day;
    return isToday ? 'Aujourd\'hui ${d.day} ${mois[d.month - 1]}' : '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]}';
  }
}

// ── Carte animal ──────────────────────────────────────────────────────────────

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final Color color;
  final String catPro;
  final VoidCallback onTap;
  final VoidCallback onCompteRendu;
  final VoidCallback? onProgression;

  const _AnimalCard({
    required this.animal,
    required this.color,
    required this.catPro,
    required this.onTap,
    required this.onCompteRendu,
    this.onProgression,
  });

  @override
  Widget build(BuildContext context) {
    final nom = animal['nom']?.toString() ?? '—';
    final espece = animal['espece']?.toString() ?? '';
    final race = animal['race']?.toString() ?? '';
    final photoUrl = animal['photo_url']?.toString() ?? '';
    final ownerName = animal['_owner_name']?.toString() ?? 'Propriétaire';
    final emoji = const {
      'chien':'🐕','chat':'🐈','cheval':'🐴','lapin':'🐰',
      'oiseau':'🦜','nac':'🦎','ovin':'🐑','caprin':'🐐','porcin':'🐷','ane':'🐴','autre':'🐾',
    }[espece] ?? '🐾';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // Photo
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: ClipOval(
                child: photoUrl.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Center(child: Text(emoji,
                            style: const TextStyle(fontSize: 24))))
                    : Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
              ),
            ),
            const SizedBox(width: 12),
            // Infos
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom, style: const TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                [if (espece.isNotEmpty) '${espece[0].toUpperCase()}${espece.substring(1)}',
                 if (race.isNotEmpty) race].join(' · '),
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.person_outline, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(child: Text(ownerName,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ])),
            // Actions
            Column(mainAxisSize: MainAxisSize.min, children: [
              // Carnet santé (sante seulement)
              if (catPro == 'sante') ...[
                _ActionBtn(
                  icon: Icons.medical_information_outlined,
                  color: color,
                  tooltip: 'Carnet de santé',
                  onTap: onTap,
                ),
                const SizedBox(height: 6),
              ],
              // CR / Compte rendu (tous)
              _ActionBtn(
                icon: catPro == 'garde'
                    ? Icons.summarize_outlined
                    : catPro == 'education'
                        ? Icons.school_outlined
                        : Icons.description_outlined,
                color: color,
                tooltip: catPro == 'garde'
                    ? 'Rapport de garde'
                    : catPro == 'education'
                        ? 'Compte rendu séance'
                        : 'CR / Ordonnance',
                onTap: catPro == 'education' && onProgression != null
                    ? onProgression!
                    : onCompteRendu,
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.color,
      required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
