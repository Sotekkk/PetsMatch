// Pension — réservation d'un séjour par le client (au lieu d'un rendez-vous) :
// animal, dates d'arrivée / départ, date d'essai si la pension l'exige pour un
// premier séjour, estimation du prix (tarifs publics), message. Demande à
// accepter par la pension (route /api/pension/sejour). Miroir site :
// website/src/components/pension/ReservationSejourModal.tsx.
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/site_api.dart';
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart' show pensionTarifKeyForEspece, pensionTarifPourKey;
import 'package:PetsMatch/pages/pro/rdv_booking_page.dart';

const _ink = Color(0xFF1F2A2E);

class PensionReservationPage extends StatefulWidget {
  final String proUid;
  final String? proProfileId;
  final String proName;
  final Color categoryColor;
  const PensionReservationPage({super.key, required this.proUid, required this.proProfileId, required this.proName, required this.categoryColor});

  @override
  State<PensionReservationPage> createState() => _PensionReservationPageState();
}

class _PensionReservationPageState extends State<PensionReservationPage> {
  final _supa = Supabase.instance.client;
  final _message = TextEditingController();
  List<Map<String, dynamic>> _animaux = [];
  Map<String, dynamic>? _animal;
  DateTimeRange? _dates;
  DateTime? _essai;
  Map<String, dynamic>? _pension;
  bool? _premierSejour;
  bool _loading = true, _envoi = false;

  Color get _c => widget.categoryColor;
  String get _pid => widget.proProfileId ?? '';

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      // Animaux du profil actif (propriété en cours).
      var q = _supa.from('animaux_proprietes').select('animal_id').eq('uid_proprio', uid).isFilter('date_fin', null);
      if (User_Info.activeProfileId.isNotEmpty) q = q.eq('profile_id_proprio', User_Info.activeProfileId);
      final ids = [for (final r in await q) r['animal_id'].toString()];
      if (ids.isNotEmpty) {
        _animaux = List<Map<String, dynamic>>.from(await _supa.from('animaux').select('id, nom, espece, photo_url, statut')
            .inFilter('id', ids).not('statut', 'in', '(sorti,decede)').order('nom'));
      }
    } catch (_) {}
    await _infosPension();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _infosPension() async {
    if (_pid.isEmpty) return;
    try {
      final q = _animal != null ? '&animalId=${Uri.encodeComponent(_animal!['id'].toString())}' : '';
      final r = await http.get(Uri.parse('$kSiteBaseUrl/api/pension/sejour?pensionProfileId=${Uri.encodeComponent(_pid)}$q'),
          headers: await siteApiHeaders());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        _pension = Map<String, dynamic>.from(j['pension'] as Map);
        _premierSejour = j['premier_sejour'] as bool?;
      }
    } catch (_) {}
  }

  bool get _essaiRequis => _pension?['essai_requis'] == true && _premierSejour == true;

  /// Estimation : nuits × prix/nuit de l'espèce (tarifs publics de la pension).
  String? get _estimation {
    final tarifs = _pension?['tarifs'] as Map?;
    if (tarifs == null || _dates == null || _animal == null) return null;
    final key = pensionTarifKeyForEspece(_animal!['espece']?.toString());
    if (key == null) return null;
    final t = pensionTarifPourKey((tarifs['especes'] as List?) ?? const [], key);
    final prix = (t?['prix_seul'] as num?)?.toDouble();
    if (prix == null || prix <= 0) return null;
    final nuits = _dates!.end.difference(_dates!.start).inDays;
    if (nuits <= 0) return null;
    return '$nuits nuit${nuits > 1 ? 's' : ''} × ${prix.toStringAsFixed(0)} € = ${(nuits * prix).toStringAsFixed(0)} € environ (hors réductions et options)';
  }

  Future<void> _choisirDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _dates, helpText: 'Arrivée et départ', saveText: 'Valider', locale: const Locale('fr', 'FR'),
    );
    if (r != null) setState(() { _dates = r; if (_essai != null && !_essai!.isBefore(r.start)) _essai = null; });
  }

  Future<void> _choisirEssai() async {
    final now = DateTime.now();
    final fin = (_dates?.start ?? now.add(const Duration(days: 60))).subtract(const Duration(days: 1));
    if (fin.isBefore(DateTime(now.year, now.month, now.day))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Choisissez un séjour plus tard : l'essai doit avoir lieu avant l'arrivée.")));
      return;
    }
    final d = await showDatePicker(context: context, firstDate: DateTime(now.year, now.month, now.day), lastDate: fin,
        initialDate: _essai ?? fin, helpText: "Date de l'essai", locale: const Locale('fr', 'FR'));
    if (d != null) setState(() => _essai = d);
  }

  Future<void> _envoyer() async {
    if (_animal == null || _dates == null) return;
    if (_essaiRequis && _essai == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cette pension demande un essai avant le premier séjour : choisissez sa date.")));
      return;
    }
    setState(() => _envoi = true);
    final f = DateFormat('yyyy-MM-dd');
    try {
      final r = await http.post(Uri.parse('$kSiteBaseUrl/api/pension/sejour'), headers: await siteApiHeaders(), body: jsonEncode({
        'pensionProfileId': _pid, 'animalId': _animal!['id'], 'dateArrivee': f.format(_dates!.start), 'dateDepart': f.format(_dates!.end),
        if (_essaiRequis && _essai != null) 'essaiDate': f.format(_essai!),
        'message': _message.text.trim(),
        if (User_Info.activeProfileId.isNotEmpty) 'profileId': User_Info.activeProfileId,
      }));
      Map<String, dynamic> j;
      try { j = jsonDecode(r.body) as Map<String, dynamic>; } on FormatException { j = {'error': 'Service momentanément indisponible.'}; }
      if (r.statusCode != 200) throw Exception(j['error'] ?? 'Demande impossible');
      if (!mounted) return;
      await showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Demande envoyée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text('${widget.proName} va étudier votre demande de séjour. Vous serez prévenu dès qu\'elle sera acceptée.',
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Voir mes demandes')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      )).then((voir) {
        if (!mounted) return;
        if (voir == true) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MesSejoursPensionPage()));
        } else {
          Navigator.pop(context, true);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _envoi = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Widget _titre(String t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _ink)));

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('EEE d MMM', 'fr_FR');
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(backgroundColor: _c, foregroundColor: Colors.white, elevation: 0,
          title: Text('Réserver un séjour', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _c))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              Text(widget.proName, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
              _titre('Animal'),
              if (_animaux.isEmpty)
                Text('Ajoutez d\'abord votre animal dans « Mes animaux ».', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in _animaux)
                    ChoiceChip(
                      label: Text(a['nom']?.toString() ?? 'Animal', style: TextStyle(fontFamily: 'Galey', color: _animal?['id'] == a['id'] ? Colors.white : _ink)),
                      selected: _animal?['id'] == a['id'], showCheckmark: false, selectedColor: _c, backgroundColor: Colors.white,
                      onSelected: (_) async {
                        setState(() { _animal = a; _premierSejour = null; _essai = null; });
                        await _infosPension();
                        if (mounted) setState(() {});
                      },
                    ),
                ]),
              _titre('Dates du séjour'),
              OutlinedButton.icon(
                onPressed: _choisirDates,
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(_dates == null ? "Choisir l'arrivée et le départ"
                    : 'Du ${f.format(_dates!.start)} au ${f.format(_dates!.end)} · ${_dates!.end.difference(_dates!.start).inDays} nuit(s)',
                    style: const TextStyle(fontFamily: 'Galey')),
                style: OutlinedButton.styleFrom(foregroundColor: _c, minimumSize: const Size(double.infinity, 46), alignment: Alignment.centerLeft),
              ),
              if (_estimation != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('Estimation : $_estimation',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700))),
              if (_essaiRequis) ...[
                _titre("Essai avant le premier séjour"),
                Text((_pension?['essai_info']?.toString() ?? '').trim().isNotEmpty
                    ? _pension!['essai_info'].toString()
                    : "Cette pension demande une journée d'essai avant le premier séjour de votre animal.",
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _choisirEssai,
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: Text(_essai == null ? "Choisir la date de l'essai" : 'Essai le ${f.format(_essai!)}', style: const TextStyle(fontFamily: 'Galey')),
                  style: OutlinedButton.styleFrom(foregroundColor: _c, minimumSize: const Size(double.infinity, 46), alignment: Alignment.centerLeft),
                ),
              ],
              _titre('Message pour la pension (facultatif)'),
              TextField(controller: _message, maxLines: 3, minLines: 2,
                  decoration: const InputDecoration(hintText: 'Habitudes, horaires d\'arrivée, besoins particuliers…',
                      border: OutlineInputBorder(), filled: true, fillColor: Colors.white)),
              const SizedBox(height: 8),
              Text("La pension aura accès à la fiche de votre animal (santé, alimentation) pour préparer le séjour.",
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _envoi || _animal == null || _dates == null ? null : _envoyer,
                style: FilledButton.styleFrom(backgroundColor: _c, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(_envoi ? 'Envoi…' : 'Envoyer la demande de séjour', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RdvBookingPage(
                    proUid: widget.proUid, proName: widget.proName, categoryColor: _c, isPension: true, proProfileId: widget.proProfileId))),
                child: Text('Demander plutôt une visite de la pension', style: TextStyle(fontFamily: 'Galey', color: _c)),
              ),
            ]),
    );
  }
}

/// Client — mes demandes de séjour en pension (statut, annulation tant que la
/// pension n'a pas répondu). Miroir site : /mes-sejours.
class MesSejoursPensionPage extends StatefulWidget {
  const MesSejoursPensionPage({super.key});
  @override
  State<MesSejoursPensionPage> createState() => _MesSejoursPensionPageState();
}

class _MesSejoursPensionPageState extends State<MesSejoursPensionPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _demandes = [];
  final Map<String, String> _pensions = {};
  bool _loading = true;
  String? _enCours;
  static const _c = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      var q = _supa.from('pension_demandes').select().eq('client_uid', uid);
      // Profil actif : ses demandes (les anciennes sans profil restent visibles).
      if (User_Info.activeProfileId.isNotEmpty) {
        q = q.or('client_profile_id.eq.${User_Info.activeProfileId},client_profile_id.is.null');
      }
      _demandes = List<Map<String, dynamic>>.from(await q.order('date_arrivee', ascending: false));
      final ids = {for (final d in _demandes) if (d['pro_profile_id'] != null) d['pro_profile_id'].toString()}.toList();
      if (ids.isNotEmpty) {
        for (final p in await _supa.from('user_profiles').select('id, nom').inFilter('id', ids)) {
          _pensions[p['id'].toString()] = p['nom']?.toString() ?? 'Pension';
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _annuler(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Annuler la demande ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: Text('La pension sera prévenue que vous annulez la demande pour ${d['animal_nom'] ?? 'votre animal'}.',
          style: const TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler la demande')),
      ],
    ));
    if (ok != true) return;
    setState(() => _enCours = d['id'].toString());
    try {
      final r = await http.post(Uri.parse('$kSiteBaseUrl/api/pension/sejour'), headers: await siteApiHeaders(),
          body: jsonEncode({'action': 'annuler', 'demandeId': d['id']}));
      if (r.statusCode != 200) {
        String m = 'Annulation impossible';
        try { m = (jsonDecode(r.body) as Map)['error']?.toString() ?? m; } catch (_) {}
        throw Exception(m);
      }
      await _charger();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
    if (mounted) setState(() => _enCours = null);
  }

  (String, Color) _statut(String s) => switch (s) {
        'acceptee' => ('Confirmé', const Color(0xFF2E7D5E)),
        'refusee' => ('Non accepté', const Color(0xFFB3261E)),
        'annulee' => ('Annulé', Colors.grey),
        _ => ('En attente de la pension', const Color(0xFFD97706)),
      };

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('d MMM yyyy', 'fr_FR');
    String jour(dynamic v) { final d = DateTime.tryParse(v?.toString() ?? ''); return d == null ? '' : f.format(d); }
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(backgroundColor: _c, foregroundColor: Colors.white, elevation: 0,
          title: const Text('Mes séjours en pension', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _c))
          : _demandes.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
                  "Aucune demande de séjour. Réservez depuis la fiche d'une pension dans l'annuaire des pros.",
                  textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600))))
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _demandes.length,
                    separatorBuilder: (_, __) => const Divider(height: 24),
                    itemBuilder: (_, i) {
                      final d = _demandes[i];
                      final (lib, coul) = _statut(d['statut']?.toString() ?? '');
                      final id = d['id'].toString();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${d['animal_nom'] ?? 'Animal'} · ${_pensions[d['pro_profile_id']?.toString()] ?? 'Pension'}',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14.5, color: _ink))),
                          Text(lib, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12.5, color: coul)),
                        ]),
                        const SizedBox(height: 2),
                        Text('Du ${jour(d['date_arrivee'])} au ${jour(d['date_depart'])}'
                            '${d['essai_date'] != null ? ' · essai le ${jour(d['essai_date'])}' : ''}',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
                        if (d['statut'] == 'refusee' && (d['motif_refus']?.toString() ?? '').isNotEmpty)
                          Text('Motif : ${d['motif_refus']}', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
                        if (d['statut'] == 'demande')
                          Align(alignment: Alignment.centerLeft, child: TextButton(
                            onPressed: _enCours == id ? null : () => _annuler(d),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: const Color(0xFFB3261E)),
                            child: Text(_enCours == id ? 'Annulation…' : 'Annuler la demande',
                                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                          )),
                      ]);
                    },
                  ),
                ),
    );
  }
}
