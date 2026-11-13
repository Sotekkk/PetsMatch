// Pet-sitter — « Dossier de la garde » depuis le RDV (13/11/2026), comme le
// dossier de séance du comportementaliste : contrat, devis, acompte, facture,
// compte rendu de visite et clés, chacun avec son état et son action.
// Une série (rdv.serie_id) est traitée comme une seule garde.
// Miroir site : website/src/components/garde/DossierGardeModal.tsx.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/garde_acceptation.dart';
import 'package:PetsMatch/pages/pro/visite_rapport_sheet.dart' show sendGardeNews;
import 'package:PetsMatch/pages/pro/education_devis_page.dart' show DevisPage, DevisPrefill;
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show FacturationPage;
import 'package:PetsMatch/pages/pro/cles_clients_page.dart' show ClesClientsPage;
import 'package:PetsMatch/utils/forfait_garde.dart';

const _teal = Color(0xFF0C5C6C);
const _vert = Color(0xFF6E9E57);
const _orange = Color(0xFFD9822B);

class _Etat {
  final String texte;
  final Color couleur;
  const _Etat(this.texte, this.couleur);
}

Future<void> showDossierGarde(BuildContext context, Map<String, dynamic> rdv, {VoidCallback? onChanged}) async {
  final supa = Supabase.instance.client;
  final pid = User_Info.activeProfileId;

  // Passages de la même garde (série), avec les libellés du RDV ouvert.
  var rdvs = <Map<String, dynamic>>[rdv];
  final serie = rdv['serie_id']?.toString() ?? '';
  if (serie.isNotEmpty) {
    try {
      final l = await supa.from('rdv').select().eq('serie_id', serie)
          .not('statut', 'in', '(annule,refuse)').order('date_heure');
      if ((l as List).isNotEmpty) {
        rdvs = [for (final r in l) {...Map<String, dynamic>.from(r as Map),
          for (final k in const ['_client_name', '_animal_nom', '_client_nom']) if (rdv[k] != null) k: rdv[k]}];
      }
    } catch (_) {}
  }
  final ids = [for (final r in rdvs) r['id'].toString()];
  final clientUid = rdv['client_uid']?.toString() ?? '';
  final clientPid = rdv['client_profile_id']?.toString() ?? '';

  Future<dynamic> sur(Future<dynamic> f) => f.then((v) => v, onError: (_) => null);
  final res = await Future.wait([
    clientUid.isEmpty ? Future.value(null) : sur(supa.from('documents_animaux').select('id, statut, metadata')
        .eq('uid_eleveur', rdv['pro_uid'] ?? '').eq('type', 'contrat_garde').eq('metadata->>client_uid', clientUid)
        .or(pid.isNotEmpty ? 'pro_profile_id.eq.$pid,pro_profile_id.is.null' : 'pro_profile_id.is.null')
        .order('created_at', ascending: false).limit(1)),
    sur(supa.from('devis').select('id, statut, total_ttc').inFilter('rdv_id', ids).order('created_at', ascending: false).limit(1)),
    sur(supa.from('factures').select('id, statut, type_facture, numero_affichage, total_ttc')
        .inFilter('source_rdv_id', ids).neq('statut', 'annulee').order('created_at', ascending: false)),
    // Acompte : facture du client sans RDV lié (les passages restent à facturer).
    clientPid.isEmpty || pid.isEmpty ? Future.value(null) : sur(supa.from('factures')
        .select('id, statut, numero_affichage, total_ttc, created_at')
        .eq('profile_id', pid).eq('client_profile_id', clientPid).eq('type_facture', 'acompte').neq('statut', 'annulee')
        .order('created_at', ascending: false).limit(1)),
    sur(supa.from('pension_updates').select('id').inFilter('rdv_id', ids)),
    clientUid.isEmpty ? Future.value(null) : sur(supa.from('cles_clients').select('id, date_restitution')
        .eq('pro_uid', rdv['pro_uid'] ?? '').eq('owner_uid', clientUid)),
  ]);
  Map<String, dynamic>? premier(dynamic l) => l is List && l.isNotEmpty ? Map<String, dynamic>.from(l.first as Map) : null;
  final contrat = premier(res[0]);
  final devis = premier(res[1]);
  final factures = res[2] is List ? [for (final f in res[2] as List) Map<String, dynamic>.from(f as Map)] : <Map<String, dynamic>>[];
  final facture = factures.where((f) => f['type_facture'] != 'acompte' && f['type_facture'] != 'avoir').firstOrNull;
  // Acompte rattaché à la garde ; sinon (avant la migration) le dernier du client.
  final acomptesLies = await acomptesGarde(ids);
  final acompte = acomptesLies.lastOrNull ?? premier(res[3]) ?? factures.where((f) => f['type_facture'] == 'acompte').firstOrNull;
  final nbRapports = res[4] is List ? (res[4] as List).length : 0;
  final cles = res[5] is List ? (res[5] as List) : const [];
  final clesEnCours = cles.where((c) => (c as Map)['date_restitution'] == null).length;
  if (!context.mounted) return;

  final c = await chiffrerGarde(rdvs);
  // Forfait du client : sa facture (à l'achat).
  final fg = c.forfait;
  Map<String, dynamic>? factureForfait;
  if (fg != null && fg.facture) {
    try {
      factureForfait = await supa.from('factures').select('statut, numero_affichage, total_ttc')
          .eq('id', fg.souscription['facture_id'].toString()).maybeSingle();
    } catch (_) {}
  }
  if (!context.mounted) return;
  String eur(num v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  _Etat etatContrat() => switch (contrat?['statut']) {
        'signe' => const _Etat('Signé par les deux parties', _vert),
        'partiellement_signe' => (contrat!['metadata'] as Map?)?['signature_eleveur'] != null
            ? const _Etat('Signé par vous — en attente du client', _orange)
            : const _Etat('Signé par le client — à signer par vous', _orange),
        'en_attente' || 'brouillon' => const _Etat('Préparé — à signer et envoyer', _orange),
        _ => const _Etat('À envoyer', Colors.grey),
      };
  _Etat etatDevis() => switch (devis?['statut']) {
        'accepte' => const _Etat('Accepté par le client', _vert),
        'envoye' => const _Etat('Envoyé — en attente de réponse', _orange),
        'refuse' => const _Etat('Refusé par le client', Colors.red),
        'brouillon' => const _Etat('Brouillon — à envoyer', _orange),
        _ => const _Etat('Facultatif — aucun devis', Colors.grey),
      };
  _Etat etatFacture(Map<String, dynamic>? f, String vide) => f == null
      ? _Etat(vide, Colors.grey)
      : f['statut'] == 'payee'
          ? _Etat('${f['numero_affichage'] ?? 'Facture'} — payée', _vert)
          : _Etat('${f['numero_affichage'] ?? 'Facture'} — ${eur((f['total_ttc'] as num?) ?? 0)}, en attente de paiement', _orange);

  final termine = rdvs.every((r) => r['statut'] == 'termine');
  final remiseCles = rdvs.any((r) => r['acces_logement'] == 'remise_cles');

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      Widget section(String t) => Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey)),
          );
      Widget ligne(IconData ic, String titre, _Etat e, String action, Future<void> Function() onTap) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(backgroundColor: _teal.withValues(alpha: 0.1), child: Icon(ic, color: _teal, size: 20)),
            title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(e.texte, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: e.couleur, fontWeight: FontWeight.w600)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(action, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: _teal)),
              const Icon(Icons.chevron_right, color: _teal),
            ]),
            onTap: () async {
              Navigator.pop(ctx);
              await onTap();
              onChanged?.call();
            },
          );
      final f = MediaQuery.of(ctx).size.height * 0.85;
      return SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: f),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 16, 20, 12), children: [
          const Text('Dossier de la garde', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: _teal)),
          const SizedBox(height: 2),
          Text('${rdv['_animal_nom'] ?? ''} · ${rdv['_client_name'] ?? ''}${rdvs.length > 1 ? ' · ${rdvs.length} passages' : ''}'
              '${c.totalHT > 0 ? ' · ${eur(c.totalHT)} HT' : ''}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
          section('Avant la garde'),
          ligne(Icons.draw_outlined, 'Contrat de garde', etatContrat(), contrat == null ? 'Envoyer' : 'Ouvrir',
              () => ouvrirContratGardeDepuisRdv(context, rdvs, totalHT: c.totalHT)),
          ligne(Icons.request_quote_outlined, 'Devis', etatDevis(), devis == null ? 'Créer' : 'Ouvrir', () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => devis != null
                ? DevisPage(modifierId: devis['id'].toString())
                : DevisPage(prefill: DevisPrefill(
                    rdvId: rdv['id']?.toString(),
                    animalId: rdv['animal_id']?.toString(),
                    clientUid: rdv['client_uid']?.toString(),
                    clientProfileId: rdv['client_profile_id']?.toString(),
                    clientNom: rdv['_client_name']?.toString(),
                    lignes: [for (final l in c.lignes) {
                      'description': [l.designation, l.description].where((x) => x.trim().isNotEmpty).join(' — '),
                      'quantite': l.quantite, 'prix_unitaire': l.prixTTC ?? l.prixHT,
                    }],
                  ))));
          }),
          if (fg != null)
            ligne(Icons.card_giftcard_outlined, 'Forfait ${fg.nom}',
                _Etat('${fg.utilises}/${fg.total} ${uniteForfaitGarde(fg.type)} utilisés · '
                    '${factureForfait == null ? 'à facturer' : factureForfait['statut'] == 'payee' ? 'payé' : 'facturé, en attente de paiement'}',
                    factureForfait?['statut'] == 'payee' ? _vert : _orange),
                factureForfait == null ? 'Facturer' : 'Voir',
                () async => factureForfait == null
                    ? facturerForfaitGarde(context, fg, rdv)
                    : Navigator.push(context, MaterialPageRoute(builder: (_) => const FacturationPage()))),
          ligne(Icons.savings_outlined, 'Acompte', etatFacture(acompte, 'Facultatif — aucun acompte'),
              acompte == null ? 'Demander' : 'Voir',
              () async => acompte == null
                  ? facturerGardeAcceptee(context, rdvs, acompte: true)
                  : Navigator.push(context, MaterialPageRoute(builder: (_) => const FacturationPage()))),
          if (remiseCles || cles.isNotEmpty)
            ligne(Icons.vpn_key_outlined, 'Clés du logement',
                cles.isEmpty
                    ? const _Etat('Remise des clés prévue — à enregistrer', _orange)
                    : clesEnCours > 0
                        ? _Etat('$clesEnCours clé${clesEnCours > 1 ? 's' : ''} en votre possession', _vert)
                        : const _Etat('Clés rendues', _vert),
                cles.isEmpty ? 'Enregistrer' : 'Voir',
                () async => cles.isEmpty
                    ? enregistrerCleGarde(context, rdv)
                    : Navigator.push(context, MaterialPageRoute(builder: (_) => const ClesClientsPage()))),
          section('Pendant et après la garde'),
          ligne(Icons.photo_camera_outlined, 'Compte rendu de visite',
              nbRapports > 0
                  ? _Etat('$nbRapports message${nbRapports > 1 ? 's' : ''} envoyé${nbRapports > 1 ? 's' : ''} au client', _vert)
                  : const _Etat('Nouvelles et photos au client — aucun envoi', Colors.grey),
              'Envoyer', () => sendGardeNews(context, rdv)),
          ligne(Icons.receipt_long_outlined, 'Facture',
              fg != null && c.nbAFacturer == 0 && facture == null
                  ? const _Etat('Tous les passages sont dans le forfait', _vert)
                  : etatFacture(facture, termine ? 'À faire${acompte != null ? ' (acompte déduit)' : ''}' : 'Après la prestation, ou d\'avance'),
              facture == null ? 'Facturer' : 'Voir',
              () async => facture == null
                  ? facturerGardeAcceptee(context, rdvs, acompte: false)
                  : Navigator.push(context, MaterialPageRoute(builder: (_) => const FacturationPage()))),
        ]),
      ));
    },
  );
}
