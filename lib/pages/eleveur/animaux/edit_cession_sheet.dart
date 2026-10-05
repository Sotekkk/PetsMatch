import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/eleveur/animaux/acquereur_contact.dart' show fetchContactAcquereur;

const _teal = Color(0xFF0C5C6C);

/// Modifier une cession EN ATTENTE (pas encore signée par les deux parties)
/// sans la refaire : coordonnées de l'acquéreur, qualité, date, prix, notes.
/// Couvre les deux circuits — cession de l'app (`cessions`, statut animal
/// 'cession_en_cours') et cession du site sans ligne `cessions` (statut
/// animal 'en_attente_cession', sortie déjà inscrite au registre).
/// Miroir site : website/src/components/animaux/EditCessionModal.tsx.
///
/// Renvoie true si la cession a été modifiée.
Future<bool> showEditCessionSheet(
  BuildContext context, {
  required Map<String, dynamic> animal,
  required Map<String, dynamic>? cession,
  required String cedantUid,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _EditCessionSheet(animal: animal, cession: cession, cedantUid: cedantUid),
  );
  return res == true;
}

class _EditCessionSheet extends StatefulWidget {
  final Map<String, dynamic> animal;
  final Map<String, dynamic>? cession;
  final String cedantUid;
  const _EditCessionSheet({required this.animal, required this.cession, required this.cedantUid});

  @override
  State<_EditCessionSheet> createState() => _EditCessionSheetState();
}

class _EditCessionSheetState extends State<_EditCessionSheet> {
  final _supa = Supabase.instance.client;
  final _prenomCtrl  = TextEditingController();
  final _nomCtrl     = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _telCtrl     = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _prixCtrl    = TextEditingController();
  final _notesCtrl   = TextEditingController();
  String _qualite = 'particulier';
  DateTime _dateCession = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, dynamic> get _a => widget.animal;
  Map<String, dynamic>? get _c => widget.cession;
  bool get _dejaSigneAcq =>
      _c?['statut'] == 'signe_acquereur' || (_c?['signature_acquereur'] ?? '').toString().isNotEmpty;

  static String _s(dynamic v) => (v ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    _qualite = _s(_c?['qualite']).isNotEmpty ? _s(_c?['qualite'])
        : _s(_a['destinataire_qualite']).isNotEmpty ? _s(_a['destinataire_qualite']) : 'particulier';
    _prenomCtrl.text  = _s(_c?['prenom_acquereur']);
    _emailCtrl.text   = _s(_c?['email_acquereur']);
    _telCtrl.text     = _s(_c?['tel_acquereur']);
    _adresseCtrl.text = _s(_c?['adresse_acquereur']).isNotEmpty ? _s(_c?['adresse_acquereur']) : _s(_a['destinataire_adresse']);
    _dateCession = DateTime.tryParse(_s(_c?['date_cession']))
        ?? DateTime.tryParse(_s(_a['date_sortie'])) ?? DateTime.now();
    final prix = _c?['prix'] ?? _a['cession_prix'];
    _prixCtrl.text  = prix == null ? '' : (prix is num ? prix.toStringAsFixed(prix % 1 == 0 ? 0 : 2) : prix.toString());
    _notesCtrl.text = _s(_c?['notes']).isNotEmpty ? _s(_c?['notes']) : _s(_a['cession_notes']);
    _completer();
  }

  /// Complète avec toutes les sources connues (profil, réservation,
  /// certificat…) et sépare le nom du prénom (`nom_acquereur` = nom complet).
  Future<void> _completer() async {
    try {
      final c = await fetchContactAcquereur(_supa, _a);
      final p = _prenomCtrl.text.isNotEmpty ? _prenomCtrl.text : c.prenom;
      var n = c.nom.isNotEmpty ? c.nom
          : _s(_c?['nom_acquereur']).isNotEmpty ? _s(_c?['nom_acquereur']) : _s(_a['destinataire_nom']);
      if (p.isNotEmpty && n.toLowerCase().startsWith('${p.toLowerCase()} ')) n = n.substring(p.length).trim();
      final cp = RegExp(r'\b\d{5}\b');
      if (!mounted) return;
      setState(() {
        _prenomCtrl.text = p;
        _nomCtrl.text = n;
        if (_emailCtrl.text.isEmpty) _emailCtrl.text = c.email;
        if (_telCtrl.text.isEmpty) _telCtrl.text = c.tel;
        if (_adresseCtrl.text.isEmpty || (!cp.hasMatch(_adresseCtrl.text) && cp.hasMatch(c.adresse))) {
          _adresseCtrl.text = c.adresse.isNotEmpty ? c.adresse : _adresseCtrl.text;
        }
      });
    } catch (_) {
      if (_nomCtrl.text.isEmpty) _nomCtrl.text = _s(_c?['nom_acquereur']).isNotEmpty ? _s(_c?['nom_acquereur']) : _s(_a['destinataire_nom']);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_prenomCtrl, _nomCtrl, _emailCtrl, _telCtrl, _adresseCtrl, _prixCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Le nom de l\'acquéreur est requis.');
      return;
    }
    if (_dejaSigneAcq) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Déjà signé par l\'acquéreur'),
          content: const Text('Après modification, l\'acquéreur devra signer à nouveau le récapitulatif.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Modifier quand même')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() { _saving = true; _error = null; });
    String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final nomComplet = [_prenomCtrl.text.trim(), _nomCtrl.text.trim()].where((e) => e.isNotEmpty).join(' ');
    final prix = double.tryParse(_prixCtrl.text.trim().replaceAll(',', '.'));
    final dateStr = _dateCession.toIso8601String().split('T').first;
    try {
      if (_c?['id'] != null) {
        await _supa.from('cessions').update({
          'qualite':           _qualite,
          'prenom_acquereur':  orNull(_prenomCtrl),
          'nom_acquereur':     nomComplet,
          'email_acquereur':   orNull(_emailCtrl),
          'tel_acquereur':     orNull(_telCtrl),
          'adresse_acquereur': orNull(_adresseCtrl),
          'date_cession':      dateStr,
          'prix':              prix,
          'notes':             orNull(_notesCtrl),
          // Contenu modifié → la signature de l'acquéreur ne vaut plus.
          if (_dejaSigneAcq) ...{
            'statut': 'en_attente_acquereur',
            'signature_acquereur': null,
            'signed_acquereur_at': null,
          },
        }).eq('id', _c!['id']);
      }

      await _supa.from('animaux').update({
        'destinataire_qualite': _qualite,
        'destinataire_nom':     nomComplet,
        'destinataire_adresse': orNull(_adresseCtrl),
        'cession_prix':         prix,
        'cession_notes':        orNull(_notesCtrl),
        if (_s(_a['date_sortie']).isNotEmpty) 'date_sortie': dateStr,
        'acquereur_contact_manuel': {
          'prenom': _prenomCtrl.text.trim(), 'nom': _nomCtrl.text.trim(),
          'tel': _telCtrl.text.trim(), 'email': _emailCtrl.text.trim(),
          'adresse': _adresseCtrl.text.trim(),
        }..removeWhere((_, v) => v.isEmpty),
      }).eq('id', _a['id']);

      // Cession du site : la sortie est déjà inscrite au registre → on la corrige.
      await _supa.from('registre_mouvements').update({
        'destinataire_qualite': _qualite,
        'destinataire_nom':     nomComplet,
        'destinataire_adresse': orNull(_adresseCtrl),
        'date_mouvement':       dateStr,
      }).eq('animal_id', _a['id']).eq('uid_eleveur', widget.cedantUid)
        .eq('type', 'sortie').eq('motif', 'cession');

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Erreur : $e'; });
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final nomAnimal = _s(_a['nom']).isEmpty ? 'l\'animal' : _s(_a['nom']);
    const qualites = [
      ('particulier', 'Particulier'), ('eleveur', 'Éleveur'),
      ('refuge', 'Refuge / Association'), ('autre', 'Autre'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          Text('✏️ Modifier la cession — $nomAnimal',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text('Possible tant que la cession n\'est pas signée par les deux parties.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator(color: _teal)),
            )
          else ...[
            if (_dejaSigneAcq)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(10)),
                child: const Text('✍️ L\'acquéreur a déjà signé : s\'il y a une modification, il devra signer à nouveau.',
                    style: TextStyle(fontSize: 11, color: Color(0xFFB26A00))),
              ),
            Row(children: [
              Expanded(child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _dateCession,
                      firstDate: DateTime(2000), lastDate: DateTime(2100));
                  if (d != null) setState(() => _dateCession = d);
                },
                child: InputDecorator(
                  decoration: _dec('Date de cession'),
                  child: Text('${_dateCession.day.toString().padLeft(2, '0')}/${_dateCession.month.toString().padLeft(2, '0')}/${_dateCession.year}',
                      style: const TextStyle(fontSize: 14)),
                ),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _prixCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _dec('Prix (€)'))),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: qualites.map((q) {
              final active = _qualite == q.$1;
              return ChoiceChip(
                label: Text(q.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: active ? Colors.white : Colors.black87)),
                selected: active,
                selectedColor: _teal,
                showCheckmark: false,
                onSelected: (_) => setState(() => _qualite = q.$1),
              );
            }).toList()),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _prenomCtrl, textCapitalization: TextCapitalization.words,
                  decoration: _dec('Prénom'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _nomCtrl, textCapitalization: TextCapitalization.words,
                  decoration: _dec('Nom *'))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: _dec('Email')),
            const SizedBox(height: 8),
            TextField(controller: _telCtrl, keyboardType: TextInputType.phone, decoration: _dec('Téléphone')),
            const SizedBox(height: 8),
            TextField(controller: _adresseCtrl, decoration: _dec('Adresse (n° et rue, code postal, ville)')),
            const SizedBox(height: 8),
            TextField(controller: _notesCtrl, maxLines: 3, decoration: _dec('Notes / Conditions particulières')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey')),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              )),
            ]),
          ],
        ]),
      ),
    );
  }
}
