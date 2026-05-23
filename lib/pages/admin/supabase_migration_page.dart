import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseMigrationPage extends StatefulWidget {
  const SupabaseMigrationPage({super.key});
  @override
  State<SupabaseMigrationPage> createState() => _SupabaseMigrationPageState();
}

class _SupabaseMigrationPageState extends State<SupabaseMigrationPage> {
  static const _teal = Color(0xFF0C5C6C);

  final _db  = FirebaseFirestore.instance;
  final _supa = Supabase.instance.client;

  bool _running = false;
  final _logs = <_LogEntry>[];
  int _total = 0;
  int _done  = 0;

  void _log(String msg, {bool error = false}) {
    setState(() => _logs.add(_LogEntry(msg, error: error)));
  }

  // ── Helpers ────────────────────────────────────────────────

  // Extrait le nom de colonne manquante depuis le message d'erreur Supabase
  String? _missingCol(String msg) =>
      RegExp(r"find the '?(\w+)'? column").firstMatch(msg)?.group(1);

  // Upsert robuste : déplace les champs inconnus dans extra_data et réessaie
  Future<void> _upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final movedToExtra = <String>{};
    bool retry = true;
    while (retry) {
      retry = false;
      try {
        for (var i = 0; i < rows.length; i += 200) {
          final end = (i + 200).clamp(0, rows.length);
          await _supa.from(table).upsert(rows.sublist(i, end));
        }
      } on PostgrestException catch (e) {
        final col = _missingCol(e.message ?? '');
        if (col != null && !movedToExtra.contains(col)) {
          movedToExtra.add(col);
          _log('  ⚠️ Colonne "$col" inconnue dans $table → stockée dans extra_data');
          // Déplace la valeur du champ manquant dans extra_data
          rows = rows.map((r) {
            final row = Map<String, dynamic>.from(r);
            if (row.containsKey(col)) {
              final extra = Map<String, dynamic>.from(
                  (row['extra_data'] as Map<String, dynamic>?) ?? {});
              extra[col] = row.remove(col);
              row['extra_data'] = extra;
            }
            return row;
          }).toList();
          retry = true;
        } else {
          rethrow;
        }
      }
    }
    if (movedToExtra.isNotEmpty) {
      _log('  📦 Champs dans extra_data : ${movedToExtra.join(", ")}');
    }
  }

  static final _frDateRe  = RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$');

  // Convertit "" ou valeur non-entière → null pour les champs INTEGER
  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  // Convertit "" ou valeur non-numérique → null pour les champs NUMERIC
  double? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
  static final _camelRe   = RegExp(r'[A-Z]');

  // camelCase → snake_case
  String _snake(String k) =>
      k.replaceAllMapped(_camelRe, (m) => '_${m.group(0)!.toLowerCase()}');

  // Convertit Timestamp Firestore ou String date → String ISO
  dynamic _convert(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is String && _frDateRe.hasMatch(v.trim())) return _toIsoDate(v);
    if (v is Map)  return v.map((k, val) => MapEntry(k as String, _convert(val)));
    if (v is List) return v.map(_convert).toList();
    return v;
  }

  // Convertit "28/6/1992" ou "28/06/1992" → "1992-06-28" (null si invalide)
  String? _toIsoDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toIso8601String().substring(0, 10);
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    // Déjà ISO
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return s.substring(0, 10);
    // Format DD/MM/YYYY ou D/M/YYYY
    final parts = s.split('/');
    if (parts.length == 3) {
      final day   = parts[0].padLeft(2, '0');
      final month = parts[1].padLeft(2, '0');
      final year  = parts[2].padLeft(4, '0');
      return '$year-$month-$day';
    }
    return null;
  }

  Map<String, dynamic> _clean(Map<String, dynamic> data) =>
      data.map((k, v) => MapEntry(k, _convert(v)));

  // ── Collections principales ────────────────────────────────

  Future<void> _migrateUsers() async {
    _log('👤 Migration users...');
    final snap = await _db.collection('users').get();
    final rows = snap.docs.map((d) {
      final data = _clean(d.data());
      return {
        'uid':                          d.id,
        'firstname':                    data['firstname'],
        'lastname':                     data['lastname'],
        'email':                        data['email'],
        'date_of_birth':                _toIsoDate(data['dateofbirth']),
        'phone_number':                 data['phone_number'],
        'code_iso':                     data['codeISO'],
        'adress':                       data['adress'],
        'rue':                          data['rue'],
        'ville':                        data['ville'],
        'code_postal':                  data['codePostal'],
        'pays':                         data['pays'],
        'profile_picture_url':          data['profilePictureUrl'],
        'bio':                          data['desc'],
        'is_elevage':                   data['isElevage'] ?? false,
        'is_validate':                  data['isValidate'] ?? false,
        'name_elevage':                 data['nameElevage'],
        'adress_elevage':               data['adressElevage'],
        'rue_elevage':                  data['rueElevage'],
        'ville_elevage':                data['villeElevage'],
        'code_postal_elevage':          data['codePostalElevage'],
        'pays_elevage':                 data['paysElevage'],
        'departement_elevage':          data['departementElevage'],
        'region_elevage':               data['regionElevage'],
        'code_iso_elevage':             data['codeISOElevage'],
        'numero_elevage':               data['numeroElevage'],
        'profile_picture_url_elevage':  data['profilePictureUrlElevage'],
        'desc_entreprise':              data['descEntreprise'],
        'document_elevage':             data['documentElevage'],
        'validate_account_elevage':     data['validateAccountElevage'] ?? false,
        'rejection_reason':             data['rejectionReason'],
        'verification_status':          data['verificationStatus'],
        'kbis_url':                     data['kbisUrl'],
        'especes_elevees':              data['especesElevees'] ?? [],
        'is_dog':                       data['isDog'] ?? false,
        'is_cat':                       data['isCat'] ?? false,
        'dog_breeds':                   data['dogBreeds'] ?? [],
        'cat_breeds':                   data['catBreeds'] ?? [],
        'is_pub':                       data['isPub'] ?? data['isPud'] ?? false,
        'is_pro':                       data['isPro'] ?? false,
        'cat_pro':                      data['catPro'],
        'siret':                        data['siret'],
        'numero_tva':                   data['numeroTVA'],
        'profession_pro':               data['professionPro'],
        'is_partenaire':                data['isPartenaire'] ?? false,
        'acaced_numero':                data['acacedNumero'],
        'acaced_date_obtention':        _toIsoDate(data['acacedDateObtention']),
        'acaced_doc_url':               data['acacedDocUrl'],
        'is_admin':                     data['isAdmin'] ?? false,
        'is_dev':                       data['isDev'] ?? false,
        'lat':                          data['lat'],
        'lng':                          data['lng'],
        'valid_until':                  _toIsoDate(data['validUntil']),
        'reminder_15_sent':             data['reminder15Sent'] ?? false,
        'reminder_21_sent':             data['reminder21Sent'] ?? false,
        'fcm_token':                    data['fcmToken'],
        'apns_token':                   data['apnsToken'],
        'is_online':                    data['isOnline'] ?? false,
        'last_active':                  data['lastActive'],
      };
    }).toList();

    await _upsert('users', rows);
    setState(() { _done += snap.docs.length; _total += snap.docs.length; });
    _log('  ✓ ${snap.docs.length} users migrés');
  }

  Future<void> _migrateAnimaux() async {
    _log('🐾 Migration animaux...');
    final snap = await _db.collection('animaux').get();
    final rows = snap.docs.map((d) {
      final data = _clean(d.data());
      return {
        'id':                   d.id,
        'uid_eleveur':          data['uidEleveur'],
        'nom':                  data['nom'],
        'espece':               data['espece'],
        'race':                 data['race'],
        'sexe':                 data['sexe'],
        'statut':               data['statut'] ?? 'present',
        'photo_url':            data['photoUrl'],
        'couleur':              data['couleur'],
        'identification':       data['identification'],
        'taille':               data['taille'],
        'poids':                data['poids'],
        'notes':                data['notes'],
        'description':          data['description'],
        'date_naissance':       _toIsoDate(data['dateNaissance']),
        'sterilise':            data['sterilise'] ?? false,
        'type_poil':            data['typePoil'],
        'pedigree':             data['pedigree'] ?? false,
        'club_registre':        data['clubRegistre'],
        'pedigree_lof':         data['pedigreeLof'],
        'pedigree_url':         data['pedigreeUrl'],
        'passeport_europeen':   data['passeportEuropeen'],
        'nom_pere':             data['nomPere'],
        'puce_pere':            data['pucePere'],
        'nom_mere':             data['nomMere'],
        'puce_mere':            data['puceMere'],
        'race_mere':            data['raceMere'],
        'date_naissance_mere':  _toIsoDate(data['dateNaissanceMere']),
        'date_entree':          _toIsoDate(data['dateEntree']),
        'date_sortie':          _toIsoDate(data['dateSortie']),
        'provenance_nom':       data['provenanceNom'],
        'provenance_qualite':   data['provenanceQualite'],
        'provenance_adresse':   data['provenanceAdresse'],
        'importation_ref':      data['importationRef'],
        'destinataire_nom':     data['destinataireNom'],
        'destinataire_qualite': data['destinataireQualite'],
        'destinataire_adresse': data['destinataireAdresse'],
        'cause_mort':           data['causeMort'],
        'documents':            data['documents'] ?? [],
        'contacts_urgence':     data['contactsUrgence'] ?? [],
        'created_at':           data['createdAt'],
      };
    }).where((r) => r['uid_eleveur'] != null).toList();

    await _upsert('animaux', rows);
    setState(() { _done += snap.docs.length; _total += snap.docs.length; });
    _log('  ✓ ${snap.docs.length} animaux migrés');

    // Sous-collections
    await _migrateAnimalSubcollections(snap.docs);
  }

  Future<void> _migrateAnimalSubcollections(List<QueryDocumentSnapshot> docs) async {
    final subcols = ['vaccinations', 'traitements', 'visites', 'vermifuges',
      'antiparasitaires', 'allergies', 'poids', 'chaleurs', 'saillies', 'gestations'];

    for (final col in subcols) {
      final rows = <Map<String, dynamic>>[];
      for (final doc in docs) {
        final sub = await doc.reference.collection(col).get();
        for (final s in sub.docs) {
          final data = _clean(s.data());
          final snakeData = data.map((k, v) => MapEntry(_snake(k), v));
          rows.add({'id': s.id, 'animal_id': doc.id, ...snakeData});
        }
      }
      if (rows.isNotEmpty) {
        await _upsert(col, rows);
        _log('  ✓ $col: ${rows.length} entrées');
      }
    }
  }

  Future<void> _migrateAnnonces() async {
    _log('📢 Migration annonces...');
    final snap = await _db.collection('annonces').get();
    final rows = snap.docs.map((d) {
      final data = _clean(d.data());
      return {
        'id':                   d.id,
        'uid_eleveur':          data['uidEleveur'],
        'nom_eleveur':          data['nomEleveur'],
        'ville_eleveur':        data['villeEleveur'],
        'departement_eleveur':  data['departementEleveur'],
        'region_eleveur':       data['regionEleveur'],
        'pays_eleveur':         data['paysEleveur'],
        'type':                 data['type'],
        'type_vente':           data['typeVente'],
        'espece':               data['espece'],
        'race':                 data['race'],
        'titre':                data['titre'],
        'description':          data['description'],
        'photos':               data['photos'] ?? [],
        'prix':                 _toNum(data['prix']),
        'prix_negociable':      data['prixNegociable'] ?? false,
        'statut':               data['statut'] ?? 'disponible',
        'date_naissance':       _toIsoDate(data['dateNaissance']),
        'date_naissance_animal':_toIsoDate(data['dateNaissanceAnimal']),
        'sexe':                 data['sexe'],
        'couleur':              data['couleur'],
        'sterilise':            data['sterilise'] ?? false,
        'semaines':             _toInt(data['semaines']),
        'nombre_bebes':         _toInt(data['nombreBebes']),
        'animaux_portee':       data['animauxPortee'] ?? [],
        'prix_min_portee':      _toNum(data['prixMinPortee']),
        'prix_max_portee':      _toNum(data['prixMaxPortee']),
        'mere_animal_id':       data['mereAnimalId'],
        'mere_photo_url':       data['merePhotoUrl'],
        'mere_nom':             data['mereNom'],
        'mere_puce':            data['merePuce'],
        'mere_registre':        data['mereRegistre'],
        'pere_animal_id':       data['pereAnimalId'],
        'pere_photo_url':       data['perePhotoUrl'],
        'pere_nom':             data['pereNom'],
        'pere_puce':            data['perePuce'],
        'pere_registre':        data['pereRegistre'],
        'registre_type':        data['registreType'],
        'numero_registre':      data['numeroRegistre'],
        'club_pedigree':        data['clubPedigree'],
        'studbook':             data['studbook'],
        'vaccines':             data['vaccines'] ?? false,
        'vermifuge':            data['vermifuge'] ?? false,
        'identification':       data['identification'] ?? false,
        'bilan_sante':          data['bilanSante'] ?? false,
        'etalon_animal_id':     data['etalonAnimalId'],
        'saillie_prix':         _toNum(data['sailliePrix']),
        'saillie_conditions':   data['saillieConditions'],
        'vues':                 _toInt(data['vues']) ?? 0,
        'contacts':             _toInt(data['contacts']) ?? 0,
        'lat':                  data['lat'],
        'lng':                  data['lng'],
        'created_at':           data['createdAt'],
        'updated_at':           data['updatedAt'],
        'expires_at':           data['expiresAt'],
      };
    }).where((r) => r['uid_eleveur'] != null).toList();

    await _upsert('annonces', rows);
    setState(() { _done += snap.docs.length; _total += snap.docs.length; });
    _log('  ✓ ${snap.docs.length} annonces migrées');
  }

  Future<void> _migrateConversations() async {
    _log('💬 Migration conversations...');
    final snap = await _db.collection('conversations').get();
    final rows = snap.docs.map((d) {
      final data = _clean(d.data());
      return {
        'id':               d.id,
        'participant_ids':  data['participantIds'] ?? '',
        'participants':     data['participants'] ?? [],
        'last_message':     data['lastMessage'] ?? '',
        'unread_count':     data['unreadCount'] ?? {},
        'updated_at':       data['timestamp'],
      };
    }).toList();

    await _upsert('conversations', rows);
    setState(() { _done += snap.docs.length; _total += snap.docs.length; });
    _log('  ✓ ${snap.docs.length} conversations migrées');

    // Messages
    _log('  💬 Migration messages...');
    int totalMsgs = 0;
    for (final doc in snap.docs) {
      final msgs = await doc.reference.collection('messages').get();
      final msgRows = msgs.docs.map((m) {
        final data = _clean(m.data());
        return {
          'id':               m.id,
          'conversation_id':  doc.id,
          'sender_id':        data['senderId'] ?? '',
          'text':             data['text'],
          'image_url':        data['imageUrl'],
          'is_read':          data['isRead'] ?? false,
          'created_at':       data['timestamp'],
        };
      }).toList();
      if (msgRows.isNotEmpty) await _upsert('messages', msgRows);
      totalMsgs += msgs.docs.length;
    }
    _log('  ✓ $totalMsgs messages migrés');
  }

  Future<void> _migratePosts() async {
    _log('📸 Migration posts...');
    final snap = await _db.collection('post').get();
    final rows = snap.docs.map((d) {
      final data = _clean(d.data());
      return {
        'id':               d.id,
        'uid_eleveur':      data['uidEleveur'] ?? '',
        'contenu':          data['desc'],
        'title':            data['title'],
        'media_stockage':   data['mediaStockage'] ?? [],
        'tags':             data['tags'] ?? [],
        'is_photo':         data['isPhoto'] ?? true,
        'is_boost':         data['isBoost'] ?? false,
        'is_urgent':        data['isUrgent'] ?? false,
        'is_cat':           data['isCat'] ?? false,
        'is_dog':           data['isDog'] ?? false,
        'is_sell':          data['isSell'] ?? false,
        'is_sailli':        data['isSailli'] ?? false,
        'is_retraite':      data['isRetraite'] ?? false,
        'is_loof':          data['isLoof'] ?? false,
        'is_lof':           data['isLof'] ?? false,
        'is_vaccined':      data['isVaccined'] ?? false,
        'is_male':          data['isMale'] ?? false,
        'is_pro':           data['isPro'] ?? false,
        'is_adult':         data['isAdult'] ?? false,
        'more_eight_weeks': data['moreEightWeeks'] ?? false,
        'date_of_birth':    _toIsoDate(data['dateOfBirth']),
        'puce_number':      data['puceNumber'],
        'number_porter':    _toInt(data['numberPorter']),
        'created_at':       data['timestamp'],
      };
    }).where((r) => (r['uid_eleveur'] as String).isNotEmpty).toList();

    await _upsert('posts', rows);
    setState(() { _done += snap.docs.length; _total += snap.docs.length; });
    _log('  ✓ ${snap.docs.length} posts migrés');
  }

  Future<void> _migrateUserSubcollections() async {
    _log('📋 Migration sous-collections éleveurs...');
    final users = await _db.collection('users').get();

    int rsCount = 0, factCount = 0, contratCount = 0, subCount = 0;

    for (final user in users.docs) {
      // Registre sanitaire
      final rs = await user.reference.collection('registreSanitaire').get();
      final rsRows = rs.docs.map((d) {
        final data = _clean(d.data());
        return {
          'id': d.id, 'uid_eleveur': user.id,
          'animal_nom': data['animalNom'], 'espece': data['espece'],
          'date_naissance': _toIsoDate(data['dateNaissance']), 'identification': data['identification'],
          'sexe': data['sexe'], 'type_acte': data['typeActe'],
          'date_acte': _toIsoDate(data['dateActe']), 'intervenant': data['intervenant'],
          'description': data['description'], 'ordonnance_num': data['ordonnanceNum'],
        };
      }).toList();
      if (rsRows.isNotEmpty) { await _upsert('registre_sanitaire', rsRows); rsCount += rsRows.length; }

      // Factures
      final facts = await user.reference.collection('factures').get();
      final factRows = facts.docs.map((d) {
        final data = _clean(d.data());
        // Convertir les champs numériques des factures
        return {
          'id': d.id, 'uid_eleveur': user.id,
          ...data.map((k, v) {
            if (['total_ht','total_tva','total_ttc'].contains(k)) return MapEntry(k, _toNum(v));
            return MapEntry(k, v);
          }),
        };
      }).toList();
      if (factRows.isNotEmpty) { await _upsert('factures', factRows); factCount += factRows.length; }

      // Contrats
      final contrats = await user.reference.collection('contrats').get();
      final contratRows = contrats.docs.map((d) {
        final data = _clean(d.data());
        return {
          'id': d.id, 'uid_eleveur': user.id,
          'nom': data['nom'], 'type': data['type'],
          'storage_path': data['storagePath'], 'url': data['url'],
          'ext': data['ext'], 'statut': data['statut'],
          'date_upload': data['dateUpload'],
        };
      }).toList();
      if (contratRows.isNotEmpty) { await _upsert('contrats', contratRows); contratCount += contratRows.length; }

      // Subscriptions
      final subs = await user.reference.collection('subscriptions').get();
      final subRows = subs.docs.map((d) {
        final data = _clean(d.data());
        return {
          'id': d.id, 'uid': user.id,
          'plan_type': data['planType'], 'status': data['status'],
          'start_date': data['startDate'], 'end_date': data['endDate'],
        };
      }).toList();
      if (subRows.isNotEmpty) { await _upsert('subscriptions', subRows); subCount += subRows.length; }
    }

    _log('  ✓ Registre sanitaire: $rsCount | Factures: $factCount | Contrats: $contratCount | Subs: $subCount');
  }

  // ── Migration complète ─────────────────────────────────────

  Future<void> _runMigration() async {
    setState(() { _running = true; _logs.clear(); _done = 0; _total = 0; });
    _log('🚀 Début de la migration Firestore → Supabase');
    try {
      await _migrateUsers();
      await _migrateAnimaux();
      await _migrateAnnonces();
      await _migrateConversations();
      await _migratePosts();
      await _migrateUserSubcollections();
      _log('');
      _log('✅ Migration terminée ! $_total documents migrés.', error: false);
    } catch (e) {
      _log('❌ Erreur : $e', error: true);
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Migration Firestore → Supabase',
            style: TextStyle(fontFamily: 'Galey', fontSize: 16,
                fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        // Bouton
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            if (_running)
              const LinearProgressIndicator(
                  color: Color(0xFF0C5C6C),
                  backgroundColor: Color(0xFFE0F2F1))
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _runMigration,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Lancer la migration',
                      style: TextStyle(fontFamily: 'Galey',
                          fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            if (_done > 0) ...[
              const SizedBox(height: 8),
              Text('$_done documents traités',
                  style: const TextStyle(fontFamily: 'Galey',
                      fontSize: 13, color: Color(0xFF6F767B))),
            ],
          ]),
        ),

        // Logs
        Expanded(
          child: Container(
            color: const Color(0xFF1A1A2E),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _logs.length,
              itemBuilder: (_, i) {
                final entry = _logs[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(entry.msg,
                      style: TextStyle(
                          fontFamily: 'monospace', fontSize: 12,
                          color: entry.error
                              ? const Color(0xFFFF6B6B)
                              : entry.msg.startsWith('✅')
                                  ? const Color(0xFF6BE88A)
                                  : Colors.white70)),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _LogEntry {
  final String msg;
  final bool error;
  const _LogEntry(this.msg, {this.error = false});
}
