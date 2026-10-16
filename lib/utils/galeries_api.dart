// Galeries privées photographe — côté appli : appels aux routes du site
// (/api/galeries/*, jeton Firebase vérifié côté serveur), génération des
// aperçus (compression ≈1600 px + filigrane facultatif) et envoi signé vers
// le bucket privé « galeries ». Miroir site : website/src/lib/galeries-client.ts.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive_io.dart' show ZipFileEncoder;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/utils/site_api.dart';

const kApercuMax = 1600;
const kApercuQualite = 78;

/// Statuts de galerie (miroir site lib/photographe.ts).
const List<(String, String)> kStatutsGalerie = [
  ('brouillon', 'Brouillon'),
  ('partagee', 'En attente de sélection'),
  ('selection_recue', 'Sélection reçue'),
  ('en_retouche', 'En retouche'),
  ('livree', 'Livrée'),
  ('archivee', 'Archivée'),
];

class GaleriesApi {
  /// Réponse JSON des routes du site ; une page HTML (route absente tant que
  /// le site n'est pas redéployé, erreur serveur) donne un message lisible.
  static Map<String, dynamic> _json(http.Response r) {
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } on FormatException {
      return {'error': 'Service momentanément indisponible (${r.statusCode}). Réessayez dans quelques minutes.'};
    }
  }

  static Future<Map<String, dynamic>> charger(String albumId) async {
    final r = await http.get(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId'), headers: await siteApiHeaders());
    final j = _json(r);
    if (r.statusCode != 200) throw Exception(j['error'] ?? 'Galerie indisponible');
    return j;
  }

  static Future<void> supprimerPhotos(String albumId, List<String> ids) async {
    final r = await http.delete(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/photos'),
        headers: await siteApiHeaders(), body: jsonEncode({'ids': ids}));
    if (r.statusCode != 200) throw Exception(_json(r)['error'] ?? 'Suppression impossible');
  }

  static Future<void> supprimerGalerie(String albumId) async {
    final r = await http.delete(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId'), headers: await siteApiHeaders());
    if (r.statusCode != 200) throw Exception(_json(r)['error'] ?? 'Suppression impossible');
  }

  /// Aperçu : réduit à kApercuMax (proportions conservées), filigrane en
  /// diagonale si [filigrane] non nul, JPEG compressé.
  static Future<({Uint8List octets, int largeur, int hauteur})> apercu(File f, String? filigrane) async {
    final reduit = await FlutterImageCompress.compressWithFile(f.path,
        minWidth: kApercuMax, minHeight: kApercuMax, quality: 92, format: CompressFormat.jpeg);
    if (reduit == null) throw Exception('Image illisible');
    final codec = await ui.instantiateImageCodec(reduit);
    var image = (await codec.getNextFrame()).image;
    // minWidth/minHeight garantissent un plancher : on borne au plafond.
    final ratio = math.min(1.0, kApercuMax / math.max(image.width, image.height));
    final w = (image.width * ratio).round(), h = (image.height * ratio).round();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..filterQuality = FilterQuality.high);
    if (filigrane != null && filigrane.isNotEmpty) {
      final taille = math.max(18.0, math.min(w, h) / 16);
      final tp = TextPainter(
        text: TextSpan(text: filigrane, style: TextStyle(fontSize: taille, fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.32),
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 1)])),
        textDirection: TextDirection.ltr,
      )..layout();
      c.save();
      c.translate(w / 2, h / 2);
      c.rotate(-math.pi / 6);
      final diag = math.sqrt(w * w + h * h.toDouble());
      final pasY = taille * 4, pasX = tp.width + taille * 3;
      var ligne = 0;
      for (var y = -diag / 2; y < diag / 2; y += pasY, ligne++) {
        for (var x = -diag / 2; x < diag / 2; x += pasX) {
          tp.paint(c, Offset(x + (ligne.isOdd ? pasX / 2 : 0) - tp.width / 2, y - tp.height / 2));
        }
      }
      c.restore();
    }
    image = await rec.endRecording().toImage(w, h);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final jpeg = await FlutterImageCompress.compressWithList(png, quality: kApercuQualite, format: CompressFormat.jpeg,
        minWidth: w, minHeight: h);
    return (octets: jpeg, largeur: w, hauteur: h);
  }

  /// Import par lots : préparation serveur (doublons écartés), aperçu, envoi
  /// signé, enregistrement. Renvoie (ajoutées, doublons, erreurs).
  static Future<({int ajoutees, int doublons, List<String> erreurs})> importer(
      String albumId, List<File> fichiers, String? filigrane, void Function(int fait, int total) progres) async {
    var ajoutees = 0, doublons = 0, fait = 0;
    final erreurs = <String>[];
    const lot = 20;
    final storage = Supabase.instance.client.storage.from('galeries');
    for (var i = 0; i < fichiers.length; i += lot) {
      final part = fichiers.sublist(i, math.min(i + lot, fichiers.length));
      final infos = [for (final f in part) {'nom': f.uri.pathSegments.last, 'taille': await f.length()}];
      final r = await http.post(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/photos'),
          headers: await siteApiHeaders(), body: jsonEncode({'action': 'preparer', 'fichiers': infos}));
      final j = _json(r);
      if (r.statusCode != 200) throw Exception(j['error'] ?? 'Import impossible');
      final cibles = (j['fichiers'] as List).cast<Map<String, dynamic>>();
      final prets = <Map<String, dynamic>>[];
      for (var k = 0; k < part.length; k++) {
        final cible = k < cibles.length ? cibles[k] : null;
        if (cible == null || cible['doublon'] == true || cible['path'] == null) {
          doublons++; fait++; progres(fait, fichiers.length); continue;
        }
        try {
          final a = await apercu(part[k], filigrane);
          await storage.uploadBinaryToSignedUrl(cible['path'] as String, cible['token'] as String, a.octets,
              const FileOptions(contentType: 'image/jpeg'));
          prets.add({'path': cible['path'], 'nom': infos[k]['nom'], 'taille': infos[k]['taille'], 'largeur': a.largeur, 'hauteur': a.hauteur});
        } catch (e) {
          erreurs.add('${infos[k]['nom']} : $e');
        }
        fait++; progres(fait, fichiers.length);
      }
      if (prets.isNotEmpty) {
        final e = await http.post(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/photos'),
            headers: await siteApiHeaders(), body: jsonEncode({'action': 'enregistrer', 'photos': prets}));
        if (e.statusCode == 200) {
          ajoutees += prets.length;
        } else {
          erreurs.add((_json(e)['error'] ?? 'Enregistrement impossible').toString());
        }
      }
    }
    return (ajoutees: ajoutees, doublons: doublons, erreurs: erreurs);
  }

  // ── Sélection (client) ───────────────────────────────────────────────

  static Future<void> choisir(String albumId, String photoId, bool choisie) async {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/selection'),
        headers: await siteApiHeaders(), body: jsonEncode({'photoId': photoId, 'choisie': choisie}));
    if (r.statusCode != 200) throw Exception(_json(r)['error'] ?? 'Sélection impossible');
  }

  static Future<void> confirmerSelection(String albumId, String commentaire) async {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/selection'),
        headers: await siteApiHeaders(), body: jsonEncode({'confirmer': true, 'commentaire': commentaire}));
    if (r.statusCode != 200) throw Exception(_json(r)['error'] ?? 'Confirmation impossible');
  }

  /// Coup de cœur du client (distinct de la sélection) : remonte dans
  /// Mes interactions > Shootings.
  static Future<void> aimer(String albumId, String photoId, bool aimee) async {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/aimer'),
        headers: await siteApiHeaders(), body: jsonEncode({'photoId': photoId, 'aimee': aimee}));
    if (r.statusCode != 200) throw Exception(_json(r)['error'] ?? 'Action impossible');
  }

  /// Lien « proches » (consultation seule, filigrane), créé au besoin, 90 jours.
  static Future<({String url, DateTime expire})> lienProches(String albumId) async {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/proches'), headers: await siteApiHeaders());
    final j = _json(r);
    if (r.statusCode != 200) throw Exception(j['error'] ?? 'Partage impossible');
    return (url: '$kSiteBaseUrl/galerie-proches/${j['token']}', expire: DateTime.parse(j['expire_at'].toString()).toLocal());
  }

  static Future<void> desactiverLienProches(String albumId) async {
    final r = await http.delete(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/proches'), headers: await siteApiHeaders());
    if (r.statusCode != 200) throw Exception(_json(r)['error'] ?? 'Action impossible');
  }

  /// Mes interactions > Shootings : photos aimées et sélectionnées des
  /// galeries partagées sur mon compte, pour le profil actif.
  static Future<List<Map<String, dynamic>>> mesFavoris(String profileId) async {
    final q = profileId.isNotEmpty ? '?profileId=${Uri.encodeComponent(profileId)}' : '';
    final r = await http.get(Uri.parse('$kSiteBaseUrl/api/galeries/mes-favoris$q'), headers: await siteApiHeaders());
    final j = _json(r);
    if (r.statusCode != 200) throw Exception(j['error'] ?? 'Chargement impossible');
    return (j['galeries'] as List).cast<Map<String, dynamic>>();
  }

  // ── Livraison (stockage temporaire, ZIP) ─────────────────────────────

  /// Liens de téléchargement (URL signées de 10 min) des ZIP livrés.
  static Future<List<Map<String, dynamic>>> liensLivraison(String albumId) async {
    final r = await http.get(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/livraison'), headers: await siteApiHeaders());
    final j = _json(r);
    if (r.statusCode != 200) throw Exception(j['error'] ?? 'Téléchargement indisponible');
    return (j['fichiers'] as List).cast<Map<String, dynamic>>();
  }

  /// Taille max d'une archive (limite d'envoi du stockage).
  static const partMax = 45 * 1024 * 1024;

  /// Photographe : regroupe les fichiers finaux en ZIP (45 Mo max chacun,
  /// sans recompression, écrits sur disque), les envoie au stockage
  /// temporaire privé puis publie la livraison.
  static Future<void> livrer(String albumId, List<File> fichiers, int jours, void Function(String) progres) async {
    final groupes = <List<File>>[];
    var courant = <File>[];
    var taille = 0;
    for (final f in fichiers) {
      final t = await f.length();
      if (courant.isNotEmpty && taille + t > partMax) { groupes.add(courant); courant = []; taille = 0; }
      courant.add(f); taille += t;
    }
    if (courant.isNotEmpty) groupes.add(courant);
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/livraison'),
        headers: await siteApiHeaders(), body: jsonEncode({'action': 'preparer', 'parts': groupes.length}));
    final j = _json(r);
    if (r.statusCode != 200) throw Exception(j['error'] ?? 'Livraison impossible');
    final cibles = (j['parts'] as List).cast<Map<String, dynamic>>();
    final dossier = await getTemporaryDirectory();
    final storage = Supabase.instance.client.storage.from('livraisons');
    final publies = <Map<String, dynamic>>[];
    for (var i = 0; i < groupes.length; i++) {
      progres('Compression ${i + 1} / ${groupes.length}…');
      final chemin = '${dossier.path}/livraison_${DateTime.now().microsecondsSinceEpoch}_$i.zip';
      final enc = ZipFileEncoder()..create(chemin, level: ZipFileEncoder.store);
      final noms = <String>{};
      for (final f in groupes[i]) {
        var nom = f.uri.pathSegments.last;
        var k = 2;
        while (noms.contains(nom)) {
          final p = nom.lastIndexOf('.');
          nom = p > 0 ? '${nom.substring(0, p)}-$k${nom.substring(p)}' : '$nom-$k';
          k++;
        }
        noms.add(nom);
        await enc.addFile(f, nom);
      }
      await enc.close();
      final zip = File(chemin);
      try {
        progres('Envoi ${i + 1} / ${groupes.length}…');
        await storage.uploadBinaryToSignedUrl(cibles[i]['path'] as String, cibles[i]['token'] as String,
            await zip.readAsBytes(), const FileOptions(contentType: 'application/zip'));
        publies.add({'path': cibles[i]['path'], 'taille': await zip.length(), 'nb': groupes[i].length});
      } finally {
        try { await zip.delete(); } catch (_) {}
      }
    }
    final p = await http.post(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/livraison'),
        headers: await siteApiHeaders(), body: jsonEncode({'action': 'publier', 'parts': publies, 'jours': jours}));
    if (p.statusCode != 200) throw Exception(_json(p)['error'] ?? 'Publication impossible');
  }

  static Future<void> actionLivraison(String albumId, String action, {int jours = 30}) async {
    final r = await http.post(Uri.parse('$kSiteBaseUrl/api/galeries/$albumId/livraison'),
        headers: await siteApiHeaders(), body: jsonEncode({'action': action, 'jours': jours}));
    if (r.statusCode != 200) throw Exception(_json(r)['error'] ?? 'Action impossible');
  }

  static String taille(num? o) {
    if (o == null || o == 0) return '';
    return o > 1024 * 1024 ? '${(o / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} Mo' : '${(o / 1024).round()} Ko';
  }
}
