import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/particulier/alerte_perdu_form_page.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';

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
    await _searchAndNavigate(context, chip, eleveurUid: uid);
  }

  // Contexte formulaire : scan → retourne le numéro pour pré-remplir un champ.
  static Future<String?> scanForField(BuildContext context) => showScanner(context);

  // ── Recherche multi-tables ─────────────────────────────────────────────────

  static Future<void> _searchAndNavigate(
    BuildContext context,
    String chip, {
    String? eleveurUid,
  }) async {
    // Normalise (supprime espaces/tirets)
    final normalized = chip.replaceAll(RegExp(r'[\s\-]'), '');

    if (!context.mounted) return;
    _showLoading(context);

    Map<String, dynamic>? animal;
    Map<String, dynamic>? alerte;
    Map<String, dynamic>? trouve;

    try {
      // 1. Animaux de l'éleveur (Supabase)
      if (eleveurUid != null) {
        final rows = await _supa
            .from('animaux')
            .select()
            .eq('uid_eleveur', eleveurUid)
            .limit(50);
        for (final row in rows as List) {
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
            .select('id,nom_animal,espece,race,sexe,couleur,identification,uid_proprietaire,date_disparition,ville')
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
