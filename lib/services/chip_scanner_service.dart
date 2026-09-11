import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:PetsMatch/widgets/vet_share_dialog.dart';

// ─── Service ──────────────────────────────────────────────────────────────────

class ChipScannerService {
  static final _supa = Supabase.instance.client;

  // Affiche l'overlay de scan et retourne le numéro de puce ou null.
  static Future<String?> showScanner(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ScannerDialog(),
    );
  }

  // Contexte élevage : scan → cherche dans animaux de l'éleveur → ouvre fiche.
  // Si pas trouvé dans animaux → cherche dans perdu/trouvé → propose actions.
  static Future<void> scanFromElevage(BuildContext context, String uid) async {
    final chip = await showScanner(context);
    if (chip == null || chip.isEmpty || !context.mounted) return;
    await _searchAndNavigate(context, chip, eleveurUid: uid, isAssociation: false);
  }

  // Contexte association : scan → cherche uniquement dans animaux is_association=true.
  static Future<void> scanFromAssociation(BuildContext context, String uid) async {
    final chip = await showScanner(context);
    if (chip == null || chip.isEmpty || !context.mounted) return;
    await _searchAndNavigate(context, chip, eleveurUid: uid, isAssociation: true);
  }

  // Contexte formulaire : scan → retourne le numéro pour pré-remplir un champ.
  static Future<String?> scanForField(BuildContext context) => showScanner(context);

  // Contexte vétérinaire : scan puce → cherche dans tous les animaux → fiche.
  static Future<void> scanFromVet(BuildContext context) async {
    final chip = await showScanner(context);
    if (chip == null || chip.isEmpty || !context.mounted) return;
    await _searchForVet(context, chip);
  }

  // Saisie manuelle pour le vétérinaire.
  static Future<void> enterPuceForVet(BuildContext context) async {
    final ctrl = TextEditingController();
    final chip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Saisir le numéro de puce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontFamily: 'Galey'),
          decoration: const InputDecoration(
            hintText: 'Ex: 250269802005832',
            hintStyle: TextStyle(fontFamily: 'Galey'),
          ),
          onSubmitted: (v) { if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim()); },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF26A69A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () { if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, ctrl.text.trim()); },
            child: const Text('Rechercher', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (chip == null || chip.isEmpty || !context.mounted) return;
    await _searchForVet(context, chip);
  }

  // ── Recherche vétérinaire (tous animaux) ─────────────────────────────────────

  static Future<void> _searchForVet(BuildContext context, String chip) async {
    final normalized = chip.replaceAll(RegExp(r'[\s\-]'), '');
    if (!context.mounted) return;
    _showLoading(context);

    Map<String, dynamic>? animal;
    try {
      // 1. Match exact sur le champ normalisé
      final exact = await _supa
          .from('animaux')
          .select('id, nom, espece, race, sexe, date_naissance, photo_url, identification, uid_eleveur, uid_proprietaire, couleur')
          .eq('identification', normalized)
          .limit(1)
          .maybeSingle();
      if (exact != null) {
        animal = Map<String, dynamic>.from(exact);
      } else {
        // 2. Fallback : ilike avec wildcards + normalisation client
        final rows = await _supa
            .from('animaux')
            .select('id, nom, espece, race, sexe, date_naissance, photo_url, identification, uid_eleveur, uid_proprietaire, couleur')
            .ilike('identification', '%$normalized%')
            .limit(20);
        for (final row in rows as List) {
          final id = ((row as Map)['identification'] ?? '').toString()
              .replaceAll(RegExp(r'[\s\-]'), '');
          if (id == normalized) {
            animal = Map<String, dynamic>.from(row);
            break;
          }
        }
      }
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.pop(context); // ferme loading

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _VetResultSheet(chip: normalized, animal: animal),
    );
  }

  // ── Recherche multi-tables ─────────────────────────────────────────────────

  static Future<void> _searchAndNavigate(
    BuildContext context,
    String chip, {
    String? eleveurUid,
    bool isAssociation = false,
  }) async {
    // Normalise (supprime espaces/tirets)
    final normalized = chip.replaceAll(RegExp(r'[\s\-]'), '');

    if (!context.mounted) return;
    _showLoading(context);

    Map<String, dynamic>? animal;
    Map<String, dynamic>? alerte;
    Map<String, dynamic>? trouve;
    Map<String, dynamic>? autreAnimal;
    Map<String, dynamic>? autreOwnerProfile;
    String? autreOwnerUid;

    try {
      // 1. Animaux de l'éleveur/association (Supabase)
      if (eleveurUid != null) {
        final List rows = isAssociation
            ? await _supa.from('animaux').select().eq('uid_eleveur', eleveurUid).eq('is_association', true).limit(50)
            : await _supa.from('animaux').select().eq('uid_eleveur', eleveurUid).limit(50);
        for (final row in rows) {
          final id = ((row as Map)['identification'] ?? '').toString()
              .replaceAll(RegExp(r'[\s\-]'), '');
          if (id.isNotEmpty && id == normalized) {
            animal = Map<String, dynamic>.from(row);
            break;
          }
        }
      }

      // 2. Alertes perdus
      if (animal == null) {
        final rows = await _supa
            .from('alertes_perdus')
            .select('id,nom_animal,espece,race,sexe,couleur,identification,uid_proprietaire,date_perte,ville')
            .limit(200);
        for (final row in rows as List) {
          final id = ((row as Map)['identification'] ?? '').toString()
              .replaceAll(RegExp(r'[\s\-]'), '');
          if (id.isNotEmpty && id == normalized) {
            alerte = Map<String, dynamic>.from(row);
            break;
          }
        }
      }

      // 3. Animaux trouvés
      if (animal == null) {
        final rows = await _supa
            .from('animaux_trouves')
            .select('id,espece,race,sexe,couleur,numero_puce,date_decouverte,ville,statut')
            .limit(200);
        for (final row in rows as List) {
          final puce = ((row as Map)['numero_puce'] ?? '').toString()
              .replaceAll(RegExp(r'[\s\-]'), '');
          if (puce.isNotEmpty && puce == normalized) {
            trouve = Map<String, dynamic>.from(row);
            break;
          }
        }
      }

      // 4. Puce déjà enregistrée sur un animal d'un AUTRE propriétaire (pas le
      // mien, pas une alerte perdu/trouvé) — identité en lecture seule +
      // fiche du propriétaire actuel, jamais la fiche complète (données
      // santé/repro privées d'un tiers).
      if (animal == null && alerte == null && trouve == null) {
        const cols = 'id,nom,espece,race,sexe,couleur,date_naissance,photo_url,'
            'identification,uid_eleveur,uid_proprietaire';
        final exact = await _supa
            .from('animaux')
            .select(cols)
            .eq('identification', normalized)
            .limit(1)
            .maybeSingle();
        if (exact != null) {
          autreAnimal = Map<String, dynamic>.from(exact);
        } else {
          final rows = await _supa.from('animaux').select(cols)
              .ilike('identification', '%$normalized%').limit(20);
          for (final row in rows as List) {
            final id = ((row as Map)['identification'] ?? '').toString()
                .replaceAll(RegExp(r'[\s\-]'), '');
            if (id == normalized) {
              autreAnimal = Map<String, dynamic>.from(row);
              break;
            }
          }
        }

        if (autreAnimal != null) {
          // Propriétaire courant résolu via animaux_proprietes (ligne active)
          // — animaux.uid_eleveur/uid_proprietaire peut être périmé après une
          // cession, voir migration_fix_animaux_proprietes_unique_constraint.sql.
          String? ownerProfileId;
          try {
            final propRows = await _supa
                .from('animaux_proprietes')
                .select('uid_proprio, profile_id_proprio')
                .eq('animal_id', autreAnimal['id'].toString())
                .isFilter('date_fin', null)
                .limit(1);
            if ((propRows as List).isNotEmpty) {
              autreOwnerUid = propRows.first['uid_proprio'] as String?;
              ownerProfileId = propRows.first['profile_id_proprio'] as String?;
            }
          } catch (_) {}
          autreOwnerUid ??= (autreAnimal['uid_eleveur'] ?? autreAnimal['uid_proprietaire'])?.toString();

          const pcols = 'id,uid,profile_type,nom,firstname,lastname,photo_url';
          if (ownerProfileId != null) {
            autreOwnerProfile = await _supa.from('user_profiles')
                .select(pcols).eq('id', ownerProfileId).maybeSingle();
          }
          if (autreOwnerProfile == null && autreOwnerUid != null) {
            autreOwnerProfile = await _supa.from('user_profiles')
                .select(pcols).eq('uid', autreOwnerUid).eq('is_main', true).maybeSingle();
          }
        }
      }
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.pop(context); // ferme loading

    if (animal != null) {
      // Fiche animal directe
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnimalFichePage(
          animalId: animal!['id']?.toString(),
          initialData: animal,
        ),
      ));
      return;
    }

    if (autreAnimal != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _OwnerAnimalResultSheet(
          animal: autreAnimal!,
          ownerProfile: autreOwnerProfile,
          ownerUid: autreOwnerUid,
        ),
      );
      return;
    }

    _showResultSheet(context, normalized, alerte: alerte, trouve: trouve);
  }

  static void _showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF0C5C6C)),
      ),
    );
  }

  static void _showResultSheet(
    BuildContext context,
    String chip, {
    Map<String, dynamic>? alerte,
    Map<String, dynamic>? trouve,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ResultSheet(
        chip: chip,
        alerte: alerte,
        trouve: trouve,
        onDeclarePerdu: () {
          Navigator.pop(ctx);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => AlertePerduFormPage(identification: chip),
          ));
        },
        onDeclareTrouve: () {
          Navigator.pop(ctx);
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => AnimalTrouveFormPage(initialPuce: chip),
          ));
        },
      ),
    );
  }
}

// ─── Overlay de scan ──────────────────────────────────────────────────────────

class _ScannerDialog extends StatefulWidget {
  const _ScannerDialog();
  @override
  State<_ScannerDialog> createState() => _ScannerDialogState();
}

class _ScannerDialogState extends State<_ScannerDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double>   _pulse;
  String _buffer    = '';
  bool   _completed = false;

  // Capture directe des keystrokes HID — pas de TextField, pas de focus Android
  bool _handleKey(KeyEvent event) {
    if (_completed || !mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final char = event.character;
    if (char != null && char != '\r' && char != '\n' && char.isNotEmpty) {
      if (mounted) setState(() => _buffer += char);
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
               event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_buffer.length >= 10) {
        _completed = true;
        final chip = _buffer.trim();
        _buffer = '';
        Navigator.pop(context, chip);
      } else {
        if (mounted) setState(() => _buffer = '');
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animation pulsée
            ScaleTransition(
              scale: _pulse,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C5C6C).withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sensors_rounded,
                  size: 44,
                  color: Color(0xFF0C5C6C),
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'Prêt à scanner',
              style: TextStyle(
                fontFamily: 'Galey',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2A2E),
              ),
            ),
            const SizedBox(height: 10),

            // Indicateur de progression si le lecteur envoie des données
            if (_buffer.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${_buffer.length} chiffre${_buffer.length > 1 ? "s" : ""} reçu${_buffer.length > 1 ? "s" : ""}…',
                  style: const TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 13,
                    color: Color(0xFF0C5C6C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            Text(
              _buffer.isEmpty
                  ? 'Approchez le lecteur de la puce\nde votre animal'
                  : _buffer.replaceAll(RegExp(r'.{4}'), r'$0 ').trim(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Galey',
                fontSize: _buffer.isEmpty ? 14 : 16,
                color: _buffer.isEmpty
                    ? const Color(0xFF6F767B)
                    : const Color(0xFF1F2A2E),
                height: 1.5,
                letterSpacing: _buffer.isEmpty ? 0 : 1.5,
                fontWeight: _buffer.isEmpty
                    ? FontWeight.normal
                    : FontWeight.w600,
              ),
            ),

            const SizedBox(height: 28),
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text(
                'Annuler',
                style: TextStyle(
                  fontFamily: 'Galey',
                  color: Color(0xFF6F767B),
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Feuille de résultats ─────────────────────────────────────────────────────

class _ResultSheet extends StatelessWidget {
  final String chip;
  final Map<String, dynamic>? alerte;
  final Map<String, dynamic>? trouve;
  final VoidCallback? onDeclarePerdu;
  final VoidCallback? onDeclareTrouve;

  const _ResultSheet({
    required this.chip,
    this.alerte,
    this.trouve,
    this.onDeclarePerdu,
    this.onDeclareTrouve,
  });

  @override
  Widget build(BuildContext context) {
    final bool found = alerte != null || trouve != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDE1E7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(children: [
            Icon(
              found ? Icons.check_circle_rounded : Icons.help_outline_rounded,
              color: found ? const Color(0xFF6E9E57) : const Color(0xFFE08080),
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Puce $chip',
                style: const TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2A2E),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          if (alerte != null) ...[
            _ResultCard(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFE08080),
              label: 'Alerte animal perdu',
              lines: [
                alerte!['nom_animal']?.toString() ?? 'Animal sans nom',
                '${alerte!['espece'] ?? ''} · ${alerte!['race'] ?? ''}',
                alerte!['ville']?.toString() ?? '',
              ],
            ),
            const SizedBox(height: 12),
          ],

          if (trouve != null) ...[
            _ResultCard(
              icon: Icons.location_on_rounded,
              color: const Color(0xFF0C5C6C),
              label: 'Animal trouvé déclaré',
              lines: [
                '${trouve!['espece'] ?? ''} · ${trouve!['race'] ?? ''}',
                'Trouvé le ${trouve!['date_decouverte'] ?? ''}',
                trouve!['ville']?.toString() ?? '',
              ],
            ),
            const SizedBox(height: 12),
          ],

          if (!found) ...[
            const Text(
              'Aucun animal enregistré avec ce numéro de puce.',
              style: TextStyle(
                fontFamily: 'Galey',
                fontSize: 14,
                color: Color(0xFF6F767B),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDeclarePerdu,
                  icon: const Icon(Icons.search_off_rounded, size: 18),
                  label: const Text('Déclarer perdu'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE08080),
                    side: const BorderSide(color: Color(0xFFE08080)),
                    textStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDeclareTrouve,
                  icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                  label: const Text('Déclarer trouvé'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0C5C6C),
                    side: const BorderSide(color: Color(0xFF0C5C6C)),
                    textStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontFamily: 'Galey', fontSize: 15),
                ),
                child: const Text('OK'),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Feuille de résultat vétérinaire ─────────────────────────────────────────

class _VetResultSheet extends StatefulWidget {
  final String chip;
  final Map<String, dynamic>? animal;
  const _VetResultSheet({required this.chip, this.animal});
  @override
  State<_VetResultSheet> createState() => _VetResultSheetState();
}

class _VetResultSheetState extends State<_VetResultSheet> {
  static const _teal = Color(0xFF26A69A);
  bool _saving = false;
  bool _loadingStatus = true;
  String? _existingStatus; // null = pas de grant, 'demande', 'active'

  @override
  void initState() {
    super.initState();
    if (widget.animal != null) _loadGrant();
  }

  Future<void> _loadGrant() async {
    final vetUid = FirebaseAuth.instance.currentUser?.uid;
    final animalId = widget.animal?['id']?.toString();
    if (vetUid == null || animalId == null) {
      if (mounted) setState(() => _loadingStatus = false);
      return;
    }
    try {
      final vetProfile = await Supabase.instance.client.from('user_profiles')
          .select('id').eq('uid', vetUid).eq('is_main', true).maybeSingle();
      final vetProfileId = vetProfile?['id'] as String?;
      String? status;
      if (vetProfileId != null) {
        final row = await Supabase.instance.client
            .from('animal_access')
            .select('statut')
            .eq('pro_profile_id', vetProfileId)
            .eq('animal_id', animalId)
            .neq('statut', 'revoked')
            .limit(1)
            .maybeSingle();
        status = row?['statut'] as String?;
      }
      if (mounted) setState(() {
        _existingStatus = status;
        _loadingStatus = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _demanderAcces() async {
    final vetUid = FirebaseAuth.instance.currentUser?.uid;
    final animal = widget.animal;
    if (vetUid == null || animal == null) return;
    final ownerId = (animal['uid_eleveur'] ?? animal['uid_proprietaire'])?.toString();
    if (ownerId == null) return;

    setState(() => _saving = true);
    try {
      final vetProfile = await Supabase.instance.client.from('user_profiles')
          .select('id').eq('uid', vetUid).eq('is_main', true).maybeSingle();
      final vetProfileId = vetProfile?['id'] as String?;
      final ownerProfile = await Supabase.instance.client.from('user_profiles')
          .select('id').eq('uid', ownerId).eq('is_main', true).maybeSingle();
      final ownerProfileId = ownerProfile?['id'] as String?;
      if (vetProfileId == null || ownerProfileId == null) throw Exception('Profils introuvables');
      await Supabase.instance.client.from('animal_access').upsert({
        'pro_profile_id':        vetProfileId,
        'granted_by_profile_id': ownerProfileId,
        'animal_id':             animal['id']?.toString(),
        'permissions':           ['read_basic', 'read_health', 'write_health'],
        'statut':                'pending',
      }, onConflict: 'animal_id,pro_profile_id');
      // Récupérer le nom de la structure ou du vétérinaire
      String vetNom = '';
      bool isClinic = false;
      try {
        final vetUser = await Supabase.instance.client
            .from('user_profiles')
            .select('firstname, lastname, nom')
            .eq('uid', vetUid)
            .eq('is_main', true)
            .maybeSingle();
        if (vetUser != null) {
          final clinic = (vetUser['nom'] ?? '').toString().trim();
          final fname  = (vetUser['firstname']   ?? '').toString().trim();
          final lname  = (vetUser['lastname']    ?? '').toString().trim();
          if (clinic.isNotEmpty) {
            vetNom  = clinic;
            isClinic = true;
          } else {
            vetNom = '$fname $lname'.trim();
          }
        }
      } catch (_) {}

      final animalNom = animal['nom']?.toString() ?? 'votre animal';
      final vetDisplay = isClinic ? vetNom : (vetNom.isNotEmpty ? 'Dr. $vetNom' : 'Un vétérinaire');
      await Supabase.instance.client.from('notifications').insert({
        'uid':   ownerId,
        'type':  'vet_access_demande',
        'title': 'Demande d\'accès — $vetDisplay',
        'body':  '$vetDisplay demande l\'accès au carnet de santé de $animalNom.',
        'profile_id': ownerProfileId,
        'data':  <String, dynamic>{
          'animal_id':  animal['id']?.toString(),
          'vet_id':     vetUid,
          'vet_nom':    vetNom,
          'is_clinic':  isClinic,
          'animal_nom': animalNom,
        },
        'read':  false,
      });
      if (mounted) {
        setState(() { _existingStatus = 'demande'; _saving = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Demande envoyée au propriétaire',
              style: TextStyle(fontFamily: 'Galey')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _ouvrirFiche() {
    final animal = widget.animal;
    if (animal == null) return;
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnimalFichePage(
        animalId: animal['id']?.toString(),
        initialData: animal,
        readOnly: true,
        vetMode: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final found  = animal != null;
    final photo  = animal?['photo_url']?.toString() ?? '';
    final nom    = animal?['nom']?.toString() ?? 'Animal';
    final espece = animal?['espece']?.toString() ?? '';
    final race   = animal?['race']?.toString() ?? '';
    final dob    = animal?['date_naissance']?.toString();

    String age = '';
    if (dob != null) {
      final date = DateTime.tryParse(dob);
      if (date != null) {
        final diff = DateTime.now().difference(date);
        final years = (diff.inDays / 365).floor();
        final months = ((diff.inDays % 365) / 30).floor();
        age = years > 0 ? '$years an${years > 1 ? "s" : ""}' : '$months mois';
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle bar
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFDDE1E7),
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),

          Row(children: [
            Icon(found ? Icons.check_circle_rounded : Icons.help_outline_rounded,
                color: found ? _teal : const Color(0xFFE08080), size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('Puce ${widget.chip}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 16,
                    fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E)))),
          ]),
          const SizedBox(height: 16),

          if (found) ...[
            // Carte animal
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _teal.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _teal.withValues(alpha: 0.15),
                  ),
                  child: photo.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Icon(Icons.pets, color: _teal, size: 28)))
                      : Icon(Icons.pets, color: _teal, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom, style: const TextStyle(fontFamily: 'Galey',
                        fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2A2E))),
                    if (espece.isNotEmpty || race.isNotEmpty)
                      Text([espece, race].where((s) => s.isNotEmpty).join(' · '),
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                              color: _teal, fontWeight: FontWeight.w600)),
                    if (age.isNotEmpty)
                      Text(age, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: Colors.grey.shade500)),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 16),

            // Boutons selon statut
            if (_loadingStatus)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(color: _teal, strokeWidth: 2),
              ))
            else if (_existingStatus == 'active') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _ouvrirFiche,
                  icon: const Icon(Icons.medical_information_outlined),
                  label: const Text('Consulter le carnet de santé',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ] else if (_existingStatus == 'demande') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.schedule_rounded, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Demande en attente d\'approbation par le propriétaire.',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4))),
                ]),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _demanderAcces,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_outlined),
                  label: Text(_saving ? 'Envoi…' : 'Demander l\'accès au carnet',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text('Le propriétaire devra approuver votre demande.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
            ],
            const SizedBox(height: 10),

            // Partager la fiche (seulement si accès actif)
            if (_existingStatus == 'active')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showVetShareSheet(context, animal['id']?.toString() ?? '');
                  },
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Partager la fiche',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0C5C6C),
                    side: const BorderSide(color: Color(0xFF0C5C6C)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
          ] else ...[
            Text('Aucun animal enregistré sur PetsMatch avec ce numéro de puce.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                    color: Colors.grey.shade500, height: 1.5)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5C6C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('OK', style: TextStyle(fontFamily: 'Galey', fontSize: 15)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─── Puce reconnue — animal d'un autre propriétaire ────────────────────────────
// Identité en lecture seule uniquement (jamais la fiche complète d'un tiers :
// pas de données santé/reproduction) + carte du propriétaire actuel.

const Map<String, String> _ownerProfileTypeLabels = {
  'particulier': 'Particulier',
  'eleveur': 'Éleveur',
  'association': 'Association',
  'veterinaire': 'Vétérinaire',
  'sante': 'Ostéo/Vétérinaire',
  'education': 'Éducateur',
  'garde': 'Pet Sitter',
  'toilettage': 'Toiletteur',
  'photographe': 'Photographe',
  'pension': 'Pension',
};

class _OwnerAnimalResultSheet extends StatelessWidget {
  final Map<String, dynamic> animal;
  final Map<String, dynamic>? ownerProfile;
  final String? ownerUid;

  const _OwnerAnimalResultSheet({required this.animal, this.ownerProfile, this.ownerUid});

  static const _teal = Color(0xFF0C5C6C);

  String get _age {
    final dob = animal['date_naissance']?.toString();
    if (dob == null) return '';
    final date = DateTime.tryParse(dob);
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    final years = (diff.inDays / 365).floor();
    final months = ((diff.inDays % 365) / 30).floor();
    return years > 0 ? '$years an${years > 1 ? "s" : ""}' : '$months mois';
  }

  String get _ownerName {
    final p = ownerProfile;
    if (p == null) return 'Propriétaire inconnu';
    if (p['profile_type'] == 'particulier') {
      final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
      return n.isNotEmpty ? n : 'Particulier';
    }
    final nom = (p['nom'] as String?)?.trim();
    return (nom != null && nom.isNotEmpty) ? nom : 'Professionnel';
  }

  Future<void> _contacter(BuildContext context) async {
    if (ownerUid == null || ownerUid!.isEmpty) return;
    try {
      final convId = await MessagingHelper.openOrCreateConversation(
        otherUid: ownerUid!,
        categorie: 'communaute',
        myProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
      );
      if (!context.mounted) return;
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: convId, eleveurId: ownerUid!),
      ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final photo = animal['photo_url']?.toString() ?? '';
    final nom = animal['nom']?.toString() ?? 'Animal';
    final espece = animal['espece']?.toString() ?? '';
    final race = animal['race']?.toString() ?? '';
    final couleur = animal['couleur']?.toString() ?? '';
    final puce = animal['identification']?.toString() ?? '';
    final subtitle = [espece, race].where((s) => s.isNotEmpty).join(' · ');
    final ownerPhoto = ownerProfile?['photo_url']?.toString() ?? '';
    final ownerType = ownerProfile?['profile_type']?.toString() ?? '';
    final ownerLabel = _ownerProfileTypeLabels[ownerType] ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFDDE1E7), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),

          Row(children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF6E9E57), size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('Puce $puce',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E)))),
          ]),
          const SizedBox(height: 4),
          const Text('Cet animal appartient à un autre compte PetsMatch — identité en lecture seule.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B), height: 1.4)),
          const SizedBox(height: 16),

          // ── Identité de l'animal (lecture seule) ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _teal.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: _teal.withValues(alpha: 0.15)),
                child: photo.isNotEmpty
                    ? ClipRRect(borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(Icons.pets, color: _teal, size: 28)))
                    : const Icon(Icons.pets, color: _teal, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2A2E))),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal, fontWeight: FontWeight.w600)),
                if (_age.isNotEmpty || couleur.isNotEmpty)
                  Text([_age, couleur].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Propriétaire actuel ──
          const Text('Propriétaire', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF4F6F5), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _teal.withValues(alpha: 0.15),
                backgroundImage: ownerPhoto.isNotEmpty ? CachedNetworkImageProvider(ownerPhoto) : null,
                child: ownerPhoto.isEmpty ? const Icon(Icons.person, color: _teal) : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_ownerName, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E))),
                if (ownerLabel.isNotEmpty)
                  Text(ownerLabel, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
              ])),
            ]),
          ),
          const SizedBox(height: 20),

          if (ownerUid != null && ownerUid!.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _contacter(context),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('Contacter le propriétaire', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6F767B),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Fermer', style: TextStyle(fontFamily: 'Galey')),
              ),
            ),
        ]),
      ),
    );
  }
}

// ─── Feuille de résultats ─────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final List<String> lines;

  const _ResultCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha:0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 13, color: color,
                )),
                const SizedBox(height: 4),
                ...lines.where((l) => l.isNotEmpty).map((l) => Text(l,
                  style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 13, color: Color(0xFF3D4852),
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
