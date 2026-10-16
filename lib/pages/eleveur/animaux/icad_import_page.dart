// Import I-CAD (appli) : création / mise à jour des fiches animaux du
// profil actif depuis les exports CSV I-CAD. Analyse, puis validation par
// l'utilisateur ; registre d'entrées / sorties et historique de propriété
// mis à jour. Miroir site : /elevage/import-icad.
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/icad_import.dart';
import 'package:PetsMatch/utils/site_api.dart';
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:http/http.dart' as http;

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);
const _ambre = Color(0xFFD97706);
const _cols = 'id, nom, identification, espece, sexe, race, couleur, date_naissance, statut, date_entree, date_sortie, destinataire_nom, destinataire_adresse, uid_acquereur, profile_id_acquereur';
bool _estUuid(String s) => RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false).hasMatch(s);

class IcadImportPage extends StatefulWidget {
  const IcadImportPage({super.key});

  @override
  State<IcadImportPage> createState() => _IcadImportPageState();
}

class _IcadImportPageState extends State<IcadImportPage> {
  final _supa = Supabase.instance.client;
  IcadAnalyse? _analyse;
  final Set<String> _creer = {};
  /// Changements validés, un par ligne : « idFiche|champ ».
  final Set<String> _maj = {};
  String _etat = '';
  String? _bilan, _erreur;
  bool _modifie = false;

  String get _pid => User_Info.activeProfileId;

  Future<void> _choisir() async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv'], allowMultiple: true);
    final paths = (res?.files ?? []).map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() { _etat = 'Analyse…'; _erreur = null; _bilan = null; _analyse = null; });
    try {
      final icad = <IcadAnimal>[];
      for (final p in paths) {
        final octets = await File(p).readAsBytes();
        String texte;
        try { texte = utf8.decode(octets); } catch (_) { texte = latin1.decode(octets); }
        icad.addAll(lireCsvIcad(texte));
      }
      // Fiches du profil actif (historique de propriété), jamais tout le compte.
      final props = await _supa.from('animaux_proprietes').select('animal_id')
          .eq('uid_proprio', uid).eq('statut', 'actif').eq('profile_id_proprio', _pid);
      final ids = {for (final p in props as List) p['animal_id'].toString()}.toList();
      final fiches = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        for (final f in await _supa.from('animaux').select(_cols).inFilter('id', ids)) {
          fiches[f['id'].toString()] = Map<String, dynamic>.from(f);
        }
      }
      if (_pid.isNotEmpty) {
        for (final f in await _supa.from('animaux').select(_cols).eq('uid_eleveur', uid).eq('profile_id', _pid)) {
          fiches[f['id'].toString()] = Map<String, dynamic>.from(f);
        }
      }
      final puces = icad.map((a) => a.puce).where((p) => p.isNotEmpty).toList();
      final autres = <String>{};
      if (puces.isNotEmpty) {
        for (final x in await _supa.from('animaux').select('id, identification').inFilter('identification', puces)) {
          if (!fiches.containsKey(x['id'].toString())) autres.add(x['identification'].toString().replaceAll(RegExp(r'\D'), ''));
        }
      }
      // Nom du compte PetsMatch rattaché comme acquéreur (cessions faites dans l'appli).
      final liees = fiches.values.where((f) => (f['uid_acquereur']?.toString() ?? '').isNotEmpty).toList();
      if (liees.isNotEmpty) {
        try {
          final profils = List<Map<String, dynamic>>.from(await _supa.from('user_profiles_complet')
              .select('id, uid, firstname, lastname, nom, is_main').inFilter('uid', liees.map((f) => f['uid_acquereur']).toList()));
          for (final f in liees) {
            final p = profils.where((x) => x['id'] == f['profile_id_acquereur']).firstOrNull
                ?? profils.where((x) => x['uid'] == f['uid_acquereur'] && x['is_main'] == true).firstOrNull;
            if (p != null) {
              final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
              f['_compte_acquereur'] = n.isNotEmpty ? n : (p['nom']?.toString() ?? '');
            }
          }
        } catch (_) {}
      }
      final r = analyserIcad(icad, fiches.values.toList(), autres);
      setState(() {
        _analyse = r;
        _creer..clear()..addAll(r.nouvelles.map((a) => a.cle));
        _maj..clear()..addAll([for (final m in r.majs) for (final c in m.changements) '${m.fiche['id']}|${c.champ}']);
      });
    } catch (e) {
      setState(() => _erreur = e is FormatException ? e.message : 'Erreur : $e');
    }
    if (mounted) setState(() => _etat = '');
  }

  Future<void> _appliquer() async {
    final a = _analyse;
    if (a == null) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() => _etat = 'Enregistrement…');
    var crees = 0, majs = 0;
    final erreurs = <String>[];
    final today = DateTime.now().toIso8601String().substring(0, 10);
    var i = 0;
    for (final n in a.nouvelles.where((x) => _creer.contains(x.cle))) {
      final id = '${DateTime.now().millisecondsSinceEpoch}${i++}';
      final ligne = {
        'id': id, 'uid_eleveur': uid, if (_pid.isNotEmpty) 'profile_id': _pid,
        ...icadLigneNouvelle(n), 'updated_at': DateTime.now().toIso8601String(),
      };
      try {
        try {
          await _supa.from('animaux').insert(ligne);
        } on PostgrestException catch (e) {
          if (!e.message.contains('acquereur_contact_manuel')) rethrow;
          ligne.remove('acquereur_contact_manuel');
          await _supa.from('animaux').insert(ligne);
        }
        await _supa.from('animaux_proprietes').insert({
          'animal_id': id, 'uid_proprio': uid, if (_pid.isNotEmpty) 'profile_id_proprio': _pid,
          'date_debut': icadEntreeRegistre(n).isNotEmpty ? icadEntreeRegistre(n) : today,
          if (n.dateCession.isNotEmpty) 'date_fin': n.dateCession,
        });
        crees++;
      } catch (e) {
        erreurs.add('${n.nom} : $e');
      }
    }
    for (final m in a.majs) {
      final id = m.fiche['id'].toString();
      final choisis = {for (final c in m.changements) if (_maj.contains('$id|${c.champ}')) c.champ};
      if (choisis.isEmpty) continue;
      final champs = icadChampsMiseAJour(m, choisis);
      try {
        if (champs.isNotEmpty) {
          champs['updated_at'] = DateTime.now().toIso8601String();
          try {
            await _supa.from('animaux').update(champs).eq('id', id);
          } on PostgrestException catch (e) {
            if (!e.message.contains('acquereur_contact_manuel')) rethrow;
            champs.remove('acquereur_contact_manuel');
            await _supa.from('animaux').update(champs).eq('id', id);
          }
        }
        final acq = m.icad.acquereur;
        if (icadCorrectionCompte(m, choisis) && acq != null) {
          // Cession test vers un compte PetsMatch : annulée par le serveur.
          final r = await http.post(Uri.parse('$kSiteBaseUrl/api/icad/corriger-cession'), headers: await siteApiHeaders(),
              body: jsonEncode({
                'animalId': id,
                'acquereur': {'prenom': acq.prenom, 'nom': acq.nom, 'adresse': acq.adresse, 'email': acq.email, 'tel': acq.tel},
                'dateCession': choisis.contains('sortie') ? m.icad.dateCession : null,
              }));
          if (r.statusCode != 200) throw Exception((jsonDecode(r.body) as Map)['error'] ?? 'correction impossible');
        } else {
          // Sortie : la propriété du profil se clôt à la cession ; le registre suit.
          if (choisis.contains('sortie')) {
            await _supa.from('animaux_proprietes').update({'date_fin': m.icad.dateCession})
                .eq('animal_id', id).eq('uid_proprio', uid).isFilter('date_fin', null);
          }
          if (_estUuid(id) && (choisis.contains('sortie') || choisis.contains('acquereur'))) {
            await _supa.from('registre_mouvements').update({
              if (choisis.contains('sortie')) 'date_mouvement': m.icad.dateCession,
              if (choisis.contains('acquereur') && acq != null) ...{
                'destinataire_nom': '${acq.prenom} ${acq.nom}'.trim(),
                'destinataire_qualite': 'particulier',
                'destinataire_adresse': acq.adresse,
              },
            }).eq('animal_id', id).eq('uid_eleveur', uid).eq('type', 'sortie');
          }
        }
        majs++;
      } catch (e) {
        erreurs.add('${m.icad.nom} : $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _etat = '';
      _analyse = null;
      _modifie = crees + majs > 0;
      _bilan = '$crees fiche${crees > 1 ? 's' : ''} créée${crees > 1 ? 's' : ''}, $majs mise${majs > 1 ? 's' : ''} à jour.'
          '${erreurs.isNotEmpty ? ' Erreurs : ${erreurs.join(' ; ')}' : ''}';
    });
  }

  Widget _carte(String titre, List<Widget> enfants, {Color? bord}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: bord ?? const Color(0xFFE6E8E6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: bord != null ? _ambre : _ink)),
          const SizedBox(height: 6),
          ...enfants,
        ]),
      );
  Widget _txt(String t, {Color? c, double taille = 13}) =>
      Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: taille, color: c ?? _ink, height: 1.35));

  @override
  Widget build(BuildContext context) {
    final a = _analyse;
    String sx(String s) => s == 'male' ? 'Mâle' : s == 'femelle' ? 'Femelle' : '—';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) Navigator.pop(context, _modifie); },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F6),
        appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
            title: const Text('Importer depuis I-CAD', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
        bottomNavigationBar: a == null ? null : SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _etat.isNotEmpty || (_creer.isEmpty && _maj.isEmpty) ? null : _appliquer,
            style: FilledButton.styleFrom(backgroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(_etat.isNotEmpty ? _etat
                : 'Valider : ${_creer.length} création${_creer.length > 1 ? 's' : ''}, ${_maj.length} mise${_maj.length > 1 ? 's' : ''} à jour',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          ),
        )),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
          _txt('Sur i-cad.fr, exportez vos animaux « actuellement détenus » et « anciennement détenus » au format CSV. '
              'Les fiches existantes sont reconnues par la puce, ou à défaut par le prénom et la date de naissance. '
              'Rien n\'est enregistré avant votre validation.', c: Colors.grey.shade700),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _etat.isNotEmpty ? null : _choisir,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(_etat.isNotEmpty && a == null ? _etat : 'Choisir le ou les fichiers CSV', style: const TextStyle(fontFamily: 'Galey')),
          ),
          const SizedBox(height: 12),
          if (_erreur != null) _txt(_erreur!, c: const Color(0xFFB3261E)),
          if (_bilan != null) _carte('Import terminé', [_txt(_bilan!)]),
          if (a != null) ...[
            if (a.alertes.isNotEmpty) _carte('Points à vérifier (${a.alertes.length})', [for (final t in a.alertes) _txt('• $t')], bord: const Color(0xFFF5D9A8)),
            _carte('Fiches existantes à mettre à jour (${a.majs.length})', [
              if (a.majs.isEmpty) _txt('Aucune.', c: Colors.grey),
              for (final m in a.majs) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${m.fiche['nom'] ?? m.icad.nom} — reconnu par ${m.parPuce ? 'la puce' : 'le prénom et la date de naissance'}',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
                ),
                for (final c in m.changements)
                  CheckboxListTile(
                    dense: true, contentPadding: EdgeInsets.zero, activeColor: _teal, controlAffinity: ListTileControlAffinity.leading,
                    value: _maj.contains('${m.fiche['id']}|${c.champ}'),
                    onChanged: (v) => setState(() {
                      final k = '${m.fiche['id']}|${c.champ}';
                      v == true ? _maj.add(k) : _maj.remove(k);
                    }),
                    title: _txt('${c.libelle} : ${c.actuel} → ${c.icad}', taille: 12.5,
                        c: c.champ == 'acquereur' && (m.fiche['uid_acquereur']?.toString() ?? '').isNotEmpty ? _ambre : null),
                  ),
              ],
            ]),
            _carte('Nouvelles fiches à créer (${a.nouvelles.length})', [
              if (a.nouvelles.isEmpty) _txt('Aucune.', c: Colors.grey),
              for (final n in a.nouvelles)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero, activeColor: _teal, controlAffinity: ListTileControlAffinity.leading,
                  value: _creer.contains(n.cle),
                  onChanged: (v) => setState(() => v == true ? _creer.add(n.cle) : _creer.remove(n.cle)),
                  title: Text('${n.nom} · ${n.race} · ${sx(n.sexe)}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: _txt([
                    'Puce ${n.puce} · né le ${icadDate(n.dateNaissance)}',
                    '${icadNeALElevage(n) ? "Né à l'élevage" : 'Entré le ${icadDate(icadEntreeRegistre(n))}'}'
                        '${n.dateCession.isNotEmpty ? ', sorti le ${icadDate(n.dateCession)}${n.acquereur != null ? ' → ${n.acquereur!.prenom} ${n.acquereur!.nom}' : ''}' : ', présent'}',
                  ].join('\n'), taille: 12),
                ),
            ]),
            if (a.aJour.isNotEmpty)
              _carte('Déjà à jour (${a.aJour.length})', [_txt(a.aJour.map((f) => f['nom'] ?? '').join(', '), c: Colors.grey.shade700)]),
          ],
        ]),
      ),
    );
  }
}
