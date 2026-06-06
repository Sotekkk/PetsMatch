import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VetTokenView extends StatefulWidget {
  final String token;
  const VetTokenView({super.key, required this.token});

  @override
  State<VetTokenView> createState() => _VetTokenViewState();
}

class _VetTokenViewState extends State<VetTokenView> {
  static const _teal = Color(0xFF26A69A);

  _Status _status = _Status.loading;
  Map<String, dynamic>? _animal;
  Map<String, List<Map<String, dynamic>>> _health = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supa = Supabase.instance.client;
    try {
      final row = await supa
          .from('partage_tokens')
          .select('id, animal_id, expires_at, used_at')
          .eq('token', widget.token)
          .maybeSingle();

      if (row == null) { setState(() => _status = _Status.notFound); return; }

      final expires = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (expires == null || expires.isBefore(DateTime.now().toUtc())) {
        setState(() => _status = _Status.expired);
        return;
      }

      // Marquer used_at à la première consultation
      if (row['used_at'] == null) {
        await supa.from('partage_tokens')
            .update({'used_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', row['id']);
      }

      final animalData = await supa.from('animaux')
          .select('id, nom, espece, race, sexe, date_naissance, identification, couleur, photo_url, sterilise, description, poids, taille')
          .eq('id', row['animal_id']?.toString() ?? '')
          .maybeSingle();

      if (animalData == null) { setState(() => _status = _Status.notFound); return; }

      final tables = ['vaccinations','traitements','visites','vermifuges','antiparasitaires','allergies'];
      final results = await Future.wait(tables.map((t) =>
          supa.from(t).select('*').eq('animal_id', row['animal_id']?.toString() ?? '')
              .order('date', ascending: false)));

      final h = <String, List<Map<String, dynamic>>>{};
      for (var i = 0; i < tables.length; i++) {
        h[tables[i]] = (results[i] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      if (mounted) setState(() {
        _animal = Map<String, dynamic>.from(animalData);
        _health = h;
        _status = _Status.ok;
      });
    } catch (e) {
      if (mounted) setState(() => _status = _Status.notFound);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Carnet de santé partagé',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _Status.loading:
        return const Center(child: CircularProgressIndicator(color: _teal));
      case _Status.expired:
        return _centeredMessage('⏱️', 'Lien expiré',
            'Ce lien de partage a expiré (validité 72h).\nDemandez au propriétaire de générer un nouveau lien.',
            badge: '🔒 Accès expiré', badgeColor: Colors.red.shade100, badgeText: Colors.red.shade800);
      case _Status.notFound:
        return _centeredMessage('🔍', 'Lien introuvable',
            'Ce lien est invalide ou a déjà été supprimé.');
      case _Status.ok:
        return _buildContent();
    }
  }

  Widget _centeredMessage(String emoji, String title, String subtitle,
      {String? badge, Color? badgeColor, Color? badgeText}) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
            fontSize: 20, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                color: Colors.grey.shade500, height: 1.5)),
        if (badge != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor ?? Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(badge, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                fontWeight: FontWeight.w700, color: badgeText ?? Colors.grey.shade700)),
          ),
        ],
      ]),
    ));
  }

  Widget _buildContent() {
    final a = _animal!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Badge accès valide
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _teal.withValues(alpha: 0.20)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_open_outlined, size: 14, color: _teal),
            const SizedBox(width: 6),
            const Text('Accès temporaire · lecture seule',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                    fontWeight: FontWeight.w600, color: _teal)),
          ]),
        ),

        // Carte identité animal
        _card(child: Column(children: [
          Row(children: [
            _animalAvatar(a['photo_url']?.toString() ?? '', a['espece']?.toString() ?? ''),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['nom']?.toString() ?? 'Animal',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 18, color: Color(0xFF1F2A2E))),
              Text([a['espece'], a['race']].where((v) => v != null && v.toString().isNotEmpty)
                  .join(' · '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                      color: _teal, fontWeight: FontWeight.w600)),
              if (_ageStr(a['date_naissance']?.toString()).isNotEmpty)
                Text(_ageStr(a['date_naissance']?.toString()),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            ])),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 4, children: [
            if (a['identification'] != null && (a['identification'] as String).isNotEmpty)
              _infoChip('🔖 Puce', a['identification'].toString()),
            if (a['sexe'] != null)
              _infoChip('', a['sexe'] == 'male' ? '♂ Mâle' : a['sexe'] == 'femelle' ? '♀ Femelle' : a['sexe'].toString()),
            if (a['sterilise'] == true) _infoChip('', 'Stérilisé·e'),
            if (a['poids'] != null && (a['poids'].toString()).isNotEmpty)
              _infoChip('⚖️', '${a['poids']} kg'),
            if (a['couleur'] != null && (a['couleur'].toString()).isNotEmpty)
              _infoChip('🎨', a['couleur'].toString()),
          ]),
          if (a['description'] != null && (a['description'] as String).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(a['description'].toString(),
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          ],
        ])),
        const SizedBox(height: 12),

        // Sections santé
        for (final section in _sections) ...[
          _HealthSectionWidget(
            section: section,
            records: _health[section.key] ?? [],
          ),
          const SizedBox(height: 10),
        ],

        // Info bas
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 16, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Informations partagées à titre informatif. Ce lien expire 72h après sa création. '
              'Seul le propriétaire peut modifier le carnet.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.amber.shade800),
            )),
          ]),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: child,
  );

  Widget _animalAvatar(String photo, String espece) {
    const emojis = {'chien':'🐕','chat':'🐈','cheval':'🐴','lapin':'🐰','oiseau':'🦜',
        'nac':'🦎','ovin':'🐑','caprin':'🐐','porcin':'🐷','ane':'🐴'};
    return Container(
      width: 64, height: 64,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
          color: _teal.withValues(alpha: 0.10)),
      child: photo.isNotEmpty
          ? ClipRRect(borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Center(child: Text(emojis[espece] ?? '🐾',
                          style: const TextStyle(fontSize: 28)))))
          : Center(child: Text(emojis[espece] ?? '🐾',
              style: const TextStyle(fontSize: 28))),
    );
  }

  Widget _infoChip(String icon, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    if (icon.isNotEmpty) Text('$icon ', style: const TextStyle(fontSize: 11)),
    Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
  ]);

  String _ageStr(String? dob) {
    if (dob == null) return '';
    final d = DateTime.tryParse(dob);
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    final months = (diff.inDays / 30).floor();
    final years = (diff.inDays / 365).floor();
    if (diff.inDays < 60) return '${diff.inDays} jours';
    if (months < 24) return '$months mois';
    return '$years an${years > 1 ? "s" : ""}';
  }
}

// ─── Section santé dépliable ──────────────────────────────────────────────────

class _SectionDef {
  final String key, label, icon;
  final Color color;
  final List<List<String>> fields;
  const _SectionDef(this.key, this.label, this.icon, this.color, this.fields);
}

const _sections = [
  _SectionDef('vaccinations', 'Vaccinations', '💉', Color(0xFF6E9E57),
      [['Vaccin','vaccin'],['Date','date'],['Rappel','date_rappel'],['Vétérinaire','veterinaire'],['Lot','lot']]),
  _SectionDef('visites', 'Visites vétérinaires', '🏥', Color(0xFF26A69A),
      [['Motif','motif'],['Date','date'],['Vétérinaire','veterinaire'],['Diagnostic','diagnostic'],['Notes','notes']]),
  _SectionDef('traitements', 'Traitements', '💊', Color(0xFFE56C5A),
      [['Produit','produit'],['Date','date'],['Fin','date_fin'],['Dosage','dosage'],['Fréquence','frequence']]),
  _SectionDef('vermifuges', 'Vermifuges', '🐛', Color(0xFF8D6E63),
      [['Produit','produit'],['Date','date'],['Rappel','date_rappel']]),
  _SectionDef('antiparasitaires', 'Antiparasitaires', '🛡', Color(0xFF7B5EA7),
      [['Produit','produit'],['Date','date'],['Fin','date_fin']]),
  _SectionDef('allergies', 'Allergies', '⚠', Color(0xFFE25C5C),
      [['Allergie','allergie'],['Sévérité','severite'],['Description','description']]),
];

class _HealthSectionWidget extends StatefulWidget {
  final _SectionDef section;
  final List<Map<String, dynamic>> records;
  const _HealthSectionWidget({required this.section, required this.records});
  @override
  State<_HealthSectionWidget> createState() => _HealthSectionWidgetState();
}

class _HealthSectionWidgetState extends State<_HealthSectionWidget> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    final records = widget.records;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(s.icon, style: const TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.label, style: const TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1F2A2E))),
                Text('${records.length} enregistrement${records.length != 1 ? "s" : ""}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: s.color,
                        fontWeight: FontWeight.w600)),
              ])),
              Icon(_open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey.shade400),
            ]),
          ),
        ),
        if (_open) ...[
          const Divider(height: 1, color: Color(0xFFF5F5F5)),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('Aucun enregistrement',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                      color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
            )
          else
            ...records.map((r) => _RecordRow(record: r, fields: s.fields)),
        ],
      ]),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final Map<String, dynamic> record;
  final List<List<String>> fields;
  const _RecordRow({required this.record, required this.fields});

  String _fmt(dynamic v, String key) {
    if (v == null) return '';
    if (key.contains('date')) {
      try {
        return '${DateTime.parse(v.toString()).day.toString().padLeft(2,'0')}/'
            '${DateTime.parse(v.toString()).month.toString().padLeft(2,'0')}/'
            '${DateTime.parse(v.toString()).year}';
      } catch (_) {}
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final pairs = fields.where((f) {
      final val = record[f[1]];
      return val != null && val.toString().isNotEmpty;
    }).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFF5F5F5)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, runSpacing: 4, children: pairs.map((f) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f[0], style: const TextStyle(fontFamily: 'Galey', fontSize: 10,
                color: Colors.grey, fontWeight: FontWeight.w600)),
            Text(_fmt(record[f[1]], f[1]),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                    color: Color(0xFF1F2A2E), fontWeight: FontWeight.w500)),
          ],
        )).toList()),
        if (record['source'] == 'veterinaire') ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF26A69A).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('🩺 Renseigné par le vétérinaire',
                style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                    fontWeight: FontWeight.w600, color: Color(0xFF26A69A))),
          ),
        ],
      ]),
    );
  }
}

enum _Status { loading, expired, notFound, ok }
