import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/pro/animal_fiche_pension_page.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart' show PensionEntreeSheet;
import 'package:PetsMatch/services/chip_scanner_service.dart';
import 'package:PetsMatch/utils/pensionnaires_partis.dart';

class FichesPensionPage extends StatefulWidget {
  const FichesPensionPage({super.key});

  @override
  State<FichesPensionPage> createState() => _FichesPensionPageState();
}

class _FichesPensionPageState extends State<FichesPensionPage> {
  static const _teal   = Color(0xFF0C5C6C);
  static const _purple = Color(0xFF7B5EA7);

  final _supa          = Supabase.instance.client;
  final _searchCtrl    = TextEditingController();
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<_FicheItem> _items     = [];
  // Avec les animaux partis : scan de la puce (retour d'un ancien pensionnaire).
  List<_FicheItem> _tous      = [];
  // Demandes d'accès sans réponse du propriétaire (miroir site : /pension/demandes).
  List<_DemandeAttente> _attente = [];
  String? _suppressionId;
  bool _loading               = true;
  String? _filterEspece;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_FicheItem> get _filtered {
    final q = _searchCtrl.text.toLowerCase().trim();
    final qPuce = q.replaceAll(RegExp(r'[\s\-]'), '');
    return _items.where((item) {
      if (_filterEspece != null && item.espece != _filterEspece) return false;
      if (q.isNotEmpty) {
        final matchNom  = item.animalNom.toLowerCase().contains(q);
        final matchPuce = qPuce.isNotEmpty && (item.puce ?? '').toLowerCase().replaceAll(RegExp(r'[\s\-]'), '').contains(qPuce);
        if (!matchNom && !matchPuce) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _scanPuce() async {
    final chip = await ChipScannerService.showScanner(context);
    if (chip == null || chip.isEmpty || !mounted) return;
    _matchAndOpen(chip);
  }

  Future<void> _enterPuceManually() async {
    final ctrl = TextEditingController();
    final chip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Saisir le numéro de puce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontFamily: 'Galey'),
          decoration: const InputDecoration(
            hintText: 'Ex : 250269812345678',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (chip == null || chip.trim().isEmpty || !mounted) return;
    _matchAndOpen(chip);
  }

  void _matchAndOpen(String chip) {
    final normalized = chip.replaceAll(RegExp(r'[\s\-]'), '');
    final match = _tous.where((item) {
      final p = (item.puce ?? '').replaceAll(RegExp(r'[\s\-]'), '');
      return p == normalized;
    }).toList();
    if (match.isNotEmpty && mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnimalFichePensionPage(
          animalId: match.first.animalId,
          animalNom: match.first.animalNom,
        ),
      ));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune fiche accessible avec cette puce.')),
      );
    }
  }

  Future<List<_DemandeAttente>> _chargerAttente(String proProfileId) async {
    try {
      final rows = List<Map<String, dynamic>>.from(await _supa.from('animal_access')
          .select('id, animal_id, created_at').eq('pro_profile_id', proProfileId).eq('statut', 'pending')
          .order('created_at', ascending: false));
      if (rows.isEmpty) return [];
      final ids = rows.map((r) => r['animal_id'].toString()).toList();
      final animaux = {
        for (final a in List<Map<String, dynamic>>.from(await _supa.from('animaux')
            .select('id, nom, photo_url, identification').inFilter('id', ids))) a['id'].toString(): a,
      };
      // Fiche pas (encore) lisible : nom et puce du registre de la pension.
      final entrees = {
        for (final e in List<Map<String, dynamic>>.from(await _supa.from('pension_entrees')
            .select('animal_id, animal_nom, puce').eq('pro_profile_id', proProfileId).inFilter('animal_id', ids)))
          e['animal_id'].toString(): e,
      };
      return [
        for (final r in rows)
          (() {
            final id = r['animal_id'].toString();
            final a = animaux[id], e = entrees[id];
            return _DemandeAttente(
              id: r['id'].toString(),
              nom: a != null ? (a['nom'] ?? 'Animal').toString() : e?['animal_nom']?.toString(),
              photoUrl: a?['photo_url']?.toString(),
              puce: (a != null ? a['identification'] : e?['puce'])?.toString(),
              date: r['created_at']?.toString(),
            );
          })(),
      ];
    } catch (_) {
      return [];
    }
  }

  List<_DemandeAttente> get _attenteFiltrees {
    final q = _searchCtrl.text.toLowerCase().trim();
    final qPuce = q.replaceAll(RegExp(r'[\s\-]'), '');
    if (q.isEmpty) return _attente;
    return _attente.where((d) => (d.nom ?? '').toLowerCase().contains(q)
        || (qPuce.isNotEmpty && (d.puce ?? '').toLowerCase().replaceAll(RegExp(r'[\s\-]'), '').contains(qPuce))).toList();
  }

  Future<void> _supprimerDemande(_DemandeAttente d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer la demande', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text("Supprimer la demande d'accès à la fiche de ${d.nom ?? 'cet animal'} ? Vous pourrez en refaire une plus tard.",
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Conserver')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _suppressionId = d.id);
    String? message;
    try {
      final r = await _supa.from('animal_access').delete().eq('id', d.id).eq('statut', 'pending').select('id');
      // Aucune ligne : le propriétaire a répondu entre-temps.
      if ((r as List).isEmpty) message = 'Cette demande a changé entre-temps : la liste est mise à jour.';
    } catch (_) {
      message = "La demande n'a pas pu être supprimée. Réessayez.";
    }
    if (!mounted) return;
    setState(() => _suppressionId = null);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Galey'))));
    }
    await _load();
  }

  Widget _carteAttente(_DemandeAttente d) {
    final initiale = Container(
      width: 52, height: 52, alignment: Alignment.center,
      decoration: BoxDecoration(color: _purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Text((d.nom ?? 'A').isEmpty ? 'A' : (d.nom ?? 'A')[0].toUpperCase(),
          style: const TextStyle(fontFamily: 'Galey', fontSize: 22, fontWeight: FontWeight.w700, color: _purple)),
    );
    final date = DateTime.tryParse(d.date ?? '')?.toLocal();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        (d.photoUrl ?? '').isEmpty ? initiale : ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(imageUrl: d.photoUrl!, width: 52, height: 52, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => initiale),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.nom ?? 'Animal (fiche non visible)',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E2025))),
          if (date != null)
            Text('Demande envoyée le ${DateFormat('dd/MM/yyyy').format(date)}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
          if ((d.puce ?? '').isNotEmpty)
            Text('Puce : ${d.puce}', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF9CA3AF))),
          const Text('En attente de réponse du propriétaire.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFE08000))),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _suppressionId != null ? null : () => _supprimerDemande(d),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_suppressionId == d.id ? 'Suppression…' : 'Supprimer la demande',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          ),
        ])),
      ]),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Accès approuvés — scopés par profil ACTIF, pas "is_main" du compte
      // (pension est souvent un profil secondaire, is_main pointe ailleurs).
      // Repli (profil actif inconnu) : le profil pension / pet-sitter du
      // compte — jamais is_main (souvent l'élevage : ses accès s'affichaient ici).
      var proProfileId = User_Info.activeProfileId;
      if (proProfileId.isEmpty) {
        final proProfile = await _supa.from('user_profiles_complet')
            .select('id').eq('uid', _uid).inFilter('profile_type', ['pension', 'garde']).limit(1).maybeSingle();
        proProfileId = proProfile?['id'] as String? ?? '';
      }
      if (proProfileId.isEmpty) {
        if (mounted) setState(() { _items = []; _tous = []; _attente = []; _loading = false; });
        return;
      }
      final attente = await _chargerAttente(proProfileId);
      if (mounted) setState(() => _attente = attente);
      final acces = await _supa
          .from('animal_access')
          .select('animal_id, granted_by_profile_id, created_at, granted_at')
          .eq('pro_profile_id', proProfileId)
          .eq('statut', 'active')
          .order('created_at', ascending: false);

      final ids = (acces as List).map((a) => a['animal_id'] as String).toList();
      if (ids.isEmpty) {
        if (mounted) setState(() { _items = []; _tous = []; _loading = false; });
        return;
      }

      // Détails animaux
      final animaux = await _supa
          .from('animaux')
          .select('id, nom, espece, race, photo_url, identification, date_naissance')
          .inFilter('id', ids);

      final animalMap = <String, Map<String, dynamic>>{};
      for (final a in animaux as List) {
        animalMap[a['id'] as String] = Map<String, dynamic>.from(a);
      }

      // Animaux déjà en pension (statut actuel) — pour ne pas ré-proposer
      // "Admettre" sur un animal déjà présent.
      final entrees = await _supa.from('pension_entrees')
          .select('animal_id').eq('pro_uid', _uid).eq('pro_profile_id', proProfileId)
          .eq('statut', 'en_pension').inFilter('animal_id', ids);
      final animauxEnPension = (entrees as List).map((e) => e['animal_id'].toString()).toSet();

      // Profils proprio via granted_by_profile_id → user_profiles (pas de
      // colonne owner_uid sur animal_access, et Firestore users est
      // obsolète depuis la migration — documents vides/périmés).
      final grantedProfileIds = (acces as List)
          .map((a) => a['granted_by_profile_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final ownerProfiles = <String, Map<String, String>>{}; // granted_by_profile_id → infos
      if (grantedProfileIds.isNotEmpty) {
        try {
          final profils = await _supa.from('user_profiles_complet')
              .select('id, uid, profile_type, nom, profile_label, firstname, lastname, phone_number, phone, telephone, email_contact')
              .inFilter('id', grantedProfileIds.toList());

          // Repli users.phone_number : user_profiles.phone_number contient
          // parfois le placeholder "0000000000" jamais mis à jour depuis la
          // vraie donnée saisie à l'inscription (table users).
          final uidsToCheck = (profils as List).map((p) => p['uid'] as String? ?? '').where((u) => u.isNotEmpty).toSet();
          final usersFallback = <String, String>{};
          if (uidsToCheck.isNotEmpty) {
            try {
              final users = await _supa.from('users_complet').select('uid, phone_number').inFilter('uid', uidsToCheck.toList());
              for (final u in users as List) {
                usersFallback[u['uid'] as String] = (u['phone_number'] as String?) ?? '';
              }
            } catch (_) {}
          }

          for (final p in profils) {
            final pid = p['id'] as String;
            final uid = (p['uid'] as String?) ?? '';
            final nomVal = (p['nom'] as String?)?.trim();
            final labelVal = (p['profile_label'] as String?)?.trim();
            final fullVal = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
            final nom = (nomVal?.isNotEmpty == true) ? nomVal!
                : (labelVal?.isNotEmpty == true) ? labelVal!
                : (fullVal.isNotEmpty ? fullVal : '');
            var contact = (p['phone_number'] as String?)?.trim().isNotEmpty == true ? p['phone_number'] as String
                : (p['phone'] as String?)?.trim().isNotEmpty == true ? p['phone'] as String
                : (p['telephone'] as String?) ?? '';
            if (contact.isEmpty || contact == '0000000000') {
              final fb = usersFallback[uid] ?? '';
              if (fb.isNotEmpty) contact = fb;
            }
            ownerProfiles[pid] = {
              'uid':     uid,
              'nom':     nom,
              'contact': contact,
              'email':   (p['email_contact'] as String?) ?? '',
            };
          }
        } catch (_) {}
      }

      final items = (acces as List).map((a) {
        final animalId = a['animal_id'] as String;
        final animal  = animalMap[animalId] ?? {};
        final grantedProfileId = a['granted_by_profile_id'] as String? ?? '';
        final owner   = ownerProfiles[grantedProfileId] ?? {};
        final ownerUid = owner['uid'] ?? '';
        return _FicheItem(
          animalId:    animalId,
          animalNom:   animal['nom'] as String? ?? a['animal_nom'] as String? ?? 'Animal',
          espece:      animal['espece'] as String? ?? '',
          race:        animal['race'] as String? ?? '',
          photoUrl:    animal['photo_url'] as String?,
          puce:        animal['identification'] as String?,
          dateNaissance: animal['date_naissance'] as String?,
          accessDate:  a['created_at'] as String?,
          ownerUid:    ownerUid.isNotEmpty ? ownerUid : null,
          proprietaireNom:     owner['nom'],
          proprietaireContact: owner['contact'],
          proprietaireEmail:   owner['email'],
          dejaEnPension: animauxEnPension.contains(animalId),
        );
      }).toList();

      // Séjour terminé et rien à venir : retiré de la liste.
      final partis = await animauxPartis(proProfileId, {
        for (final a in acces as List) a['animal_id'].toString(): (a['granted_at'] ?? a['created_at'] ?? '').toString(),
      });
      if (mounted) {
        setState(() {
          _tous = items;
          _items = items.where((i) => !partis.contains(i.animalId)).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final attente = _attenteFiltrees;
    final especes  = _items.map((e) => e.espece).where((s) => s.isNotEmpty).toSet().toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        title: const Text('Fiches accessibles',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sensors_rounded),
            tooltip: 'Scanner une puce',
            onPressed: _scanPuce,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_outlined),
            tooltip: 'Saisir la puce manuellement',
            onPressed: _enterPuceManually,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : _items.isEmpty && _attente.isEmpty
              ? _buildEmpty()
              : Column(children: [
                  // Barre de recherche
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Nom ou numéro de puce…',
                          hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => _searchCtrl.clear())
                              : null,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _purple, width: 1.5)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ),
                  // Filtre espèce
                  if (especes.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Row(children: [
                        _especeChip(null, 'Toutes', especes),
                        for (final e in especes) _especeChip(e, _espLabel(e), especes),
                      ]),
                    ),
                  // Liste
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      color: _purple,
                      child: filtered.isEmpty && attente.isEmpty
                          ? const Center(child: Text('Aucun résultat',
                              style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                              itemCount: attente.length + filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                if (i < attente.length) return _carteAttente(attente[i]);
                                final item = filtered[i - attente.length];
                                return _FicheCard(
                                  item: item,
                                  onViewFiche: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => AnimalFichePensionPage(
                                      animalId: item.animalId,
                                      animalNom: item.animalNom,
                                    ),
                                  )),
                                  onAdmettre: () async {
                                    final added = await showModalBottomSheet<bool>(
                                      context: context,
                                      isScrollControlled: true,
                                      useSafeArea: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => PensionEntreeSheet(
                                        initialNom:                item.animalNom,
                                        initialEspece:             item.espece,
                                        initialRace:               item.race,
                                        initialPuce:               item.puce,
                                        initialProprietaireNom:    item.proprietaireNom,
                                        initialProprietaireContact: item.proprietaireContact,
                                        initialProprietaireEmail:  item.proprietaireEmail,
                                        initialPhotoUrl:           item.photoUrl,
                                        initialAnimalId:           item.animalId,
                                        initialOwnerUid:           item.ownerUid,
                                      ),
                                    );
                                    if (added == true && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Animal admis en pension ✓'),
                                          backgroundColor: Color(0xFF6E9E57),
                                        ),
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ]),
    );
  }

  Widget _especeChip(String? value, String label, List<String> especes) {
    final selected = _filterEspece == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label,
            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF1F2A2E))),
        selected: selected,
        onSelected: (_) => setState(() => _filterEspece = value),
        backgroundColor: Colors.white,
        selectedColor: _purple,
        checkmarkColor: Colors.white,
        side: BorderSide(color: selected ? _purple : Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        showCheckmark: false,
      ),
    );
  }

  static String _espLabel(String e) {
    const m = {'chien':'Chiens','chat':'Chats','cheval':'Chevaux','lapin':'Lapins',
               'ovin':'Ovins','caprin':'Caprins','porcin':'Porcins','nac':'NAC','oiseau':'Oiseaux'};
    return m[e] ?? e[0].toUpperCase() + e.substring(1);
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.folder_open_outlined, size: 56, color: Colors.grey.shade300),
      const SizedBox(height: 14),
      const Text('Aucune fiche accessible',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
              fontSize: 15, color: Color(0xFF1F2A2E))),
      const SizedBox(height: 6),
      Text(
        'Scannez la puce d\'un animal pour demander\nl\'accès à sa fiche au propriétaire.',
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500),
      ),
    ]),
  );
}

class _DemandeAttente {
  final String id;
  final String? nom, photoUrl, puce, date;
  const _DemandeAttente({required this.id, this.nom, this.photoUrl, this.puce, this.date});
}

// ── Modèle ─────────────────────────────────────────────────────────────────────

class _FicheItem {
  final String animalId;
  final String animalNom;
  final String espece;
  final String race;
  final String? photoUrl;
  final String? puce;
  final String? dateNaissance;
  final String? accessDate;
  final String? ownerUid;
  final String? proprietaireNom;
  final String? proprietaireContact;
  final String? proprietaireEmail;
  final bool dejaEnPension;

  const _FicheItem({
    required this.animalId,
    required this.animalNom,
    required this.espece,
    required this.race,
    this.photoUrl,
    this.puce,
    this.dateNaissance,
    this.accessDate,
    this.ownerUid,
    this.proprietaireNom,
    this.proprietaireContact,
    this.proprietaireEmail,
    this.dejaEnPension = false,
  });
}

// ── Carte fiche ─────────────────────────────────────────────────────────────────

class _FicheCard extends StatelessWidget {
  final _FicheItem item;
  final VoidCallback onViewFiche;
  final VoidCallback onAdmettre;

  static const _teal   = Color(0xFF0C5C6C);
  static const _purple = Color(0xFF7B5EA7);

  static const _espEmoji = {
    'chien': '🐕', 'chat': '🐈', 'lapin': '🐇', 'oiseau': '🦜',
    'cheval': '🐴', 'nac': '🐹', 'ovin': '🐑', 'caprin': '🐐', 'porcin': '🐷',
  };

  const _FicheCard({
    required this.item,
    required this.onViewFiche,
    required this.onAdmettre,
  });

  static String _age(String? iso) {
    if (iso == null) return '';
    try {
      final dob = DateTime.parse(iso);
      final now = DateTime.now();
      final m = (now.year - dob.year) * 12 + now.month - dob.month;
      if (m < 12) return '$m mois';
      final y = m ~/ 12;
      final r = m % 12;
      return r == 0 ? '$y an${y > 1 ? 's' : ''}' : '$y an${y > 1 ? 's' : ''} $r mois';
    } catch (_) { return ''; }
  }

  static String _fmtDate(String? iso) {
    if (iso == null) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso)); } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final emoji = _espEmoji[item.espece] ?? '🐾';
    final age   = _age(item.dateNaissance);
    final especeRace = [
      if (item.espece.isNotEmpty) item.espece[0].toUpperCase() + item.espece.substring(1),
      if (item.race.isNotEmpty) item.race,
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Photo ou emoji
            item.photoUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: item.photoUrl!,
                      width: 52, height: 52, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _speciesBox(emoji),
                    ),
                  )
                : _speciesBox(emoji),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.animalNom,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 16, color: Color(0xFF1E2025))),
              if (especeRace.isNotEmpty)
                Text(especeRace,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
              if (age.isNotEmpty)
                Text(age,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF9CA3AF))),
            ])),
            // Badge accès
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: _purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_open_rounded, size: 11, color: _purple),
                SizedBox(width: 4),
                Text('Accès accordé',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                        fontWeight: FontWeight.w700, color: _purple)),
              ]),
            ),
          ]),
          if (item.puce != null && item.puce!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Puce : ${item.puce}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
          if (item.accessDate != null) ...[
            const SizedBox(height: 3),
            Text('Accès accordé le ${_fmtDate(item.accessDate)}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: item.dejaEnPension
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Déjà en pension',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: onAdmettre,
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: const Text('Admettre',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _teal,
                        side: const BorderSide(color: _teal),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onViewFiche,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Voir la fiche',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _speciesBox(String emoji) => Container(
    width: 52, height: 52,
    decoration: BoxDecoration(
      color: _purple.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
  );
}
