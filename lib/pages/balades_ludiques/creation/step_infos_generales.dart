part of 'creation_flow_page.dart';

class _StepInfosGenerales extends StatefulWidget {
  final _CreationFlowPageState s;
  const _StepInfosGenerales({required this.s});

  @override
  State<_StepInfosGenerales> createState() => _StepInfosGeneralesState();
}

class _StepInfosGeneralesState extends State<_StepInfosGenerales> {
  Future<void> _pickCover() async {
    final f = await pickAndCropBanner();
    if (f != null) setState(() => widget.s.coverFile = f);
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 14),
        child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Infos générales', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18)),
        GestureDetector(
          onTap: _pickCover,
          child: Container(
            height: 140, margin: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(16),
              image: s.coverFile != null
                  ? DecorationImage(image: FileImage(s.coverFile!), fit: BoxFit.cover)
                  : (s.coverUrl != null ? DecorationImage(image: NetworkImage(s.coverUrl!), fit: BoxFit.cover) : null),
            ),
            child: (s.coverFile == null && s.coverUrl == null)
                ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.image_outlined, size: 32, color: kBlGreen),
                    SizedBox(height: 6),
                    Text('Photo de couverture', style: TextStyle(fontFamily: 'Galey', color: kBlGreen)),
                  ]))
                : null,
          ),
        ),
        _label('Titre *'),
        TextField(controller: s.titreCtrl, style: const TextStyle(fontFamily: 'Galey'),
            decoration: InputDecoration(hintText: 'Ex : La chasse aux écureuils du parc', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        _label('Description'),
        TextField(controller: s.descriptionCtrl, maxLines: 4, style: const TextStyle(fontFamily: 'Galey'),
            decoration: InputDecoration(hintText: 'Présentez votre parcours...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        _label('Espèce ciblée'),
        Wrap(spacing: 8, runSpacing: 8, children: kBlEspeces.map((e) => GestureDetector(
          onTap: () => setState(() => s.espece = e.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: s.espece == e.$1 ? kBlTeal : Colors.white,
              border: Border.all(color: s.espece == e.$1 ? kBlTeal : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${e.$3} ${e.$2}', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                color: s.espece == e.$1 ? Colors.white : kBlDark)),
          ),
        )).toList()),
        _label('Difficulté'),
        Wrap(spacing: 8, runSpacing: 8, children: kBlDifficultes.map((d) => GestureDetector(
          onTap: () => setState(() => s.difficulte = d.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: s.difficulte == d.$1 ? d.$3 : Colors.white,
              border: Border.all(color: s.difficulte == d.$1 ? d.$3 : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(d.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                color: s.difficulte == d.$1 ? Colors.white : kBlDark)),
          ),
        )).toList()),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Durée estimée (min)'),
            TextField(controller: s.dureeCtrl, keyboardType: TextInputType.number, style: const TextStyle(fontFamily: 'Galey'),
                decoration: InputDecoration(hintText: '45', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('Distance (km)'),
            TextField(controller: s.distanceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontFamily: 'Galey'),
                decoration: InputDecoration(hintText: '3.5', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          ])),
        ]),
        _label('Critères'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _toggleChip('👨‍👩‍👧 Famille', s.famille, (v) => setState(() => s.famille = v)),
          _toggleChip('🏃 Sportif', s.sportif, (v) => setState(() => s.sportif = v)),
          _toggleChip('♿ Accessible PMR', s.pmr, (v) => setState(() => s.pmr = v)),
        ]),
        Row(children: [
          Expanded(child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gratuit', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
            value: s.gratuit,
            activeThumbColor: kBlGreen,
            onChanged: (v) => setState(() => s.gratuit = v),
          )),
        ]),
        if (!s.gratuit) TextField(controller: s.prixCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontFamily: 'Galey'),
            decoration: InputDecoration(hintText: 'Prix en €', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        if (User_Info.isAdmin) ...[
          const Divider(height: 32),
          const Text('🏆 Événement officiel (admin)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          _label('Type'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ('communautaire', 'Communautaire'), ('officiel_petsmatch', 'Officiel PetsMatch'), ('officiel_partenaire', 'Officiel partenaire'),
          ].map((e) => GestureDetector(
            onTap: () => setState(() => s.typeEvenement = e.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: s.typeEvenement == e.$1 ? kBlOrange : Colors.white,
                border: Border.all(color: s.typeEvenement == e.$1 ? kBlOrange : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(e.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: s.typeEvenement == e.$1 ? Colors.white : kBlDark)),
            ),
          )).toList()),
          if (s.typeEvenement == 'officiel_partenaire')
            TextField(controller: s.partenaireNomCtrl, style: const TextStyle(fontFamily: 'Galey'),
                decoration: InputDecoration(hintText: 'Nom du partenaire', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          if (s.typeEvenement != 'communautaire') Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
                if (d != null) setState(() => s.eventDebut = d);
              },
              child: Text(s.eventDebut == null ? 'Date début' : '${s.eventDebut!.day}/${s.eventDebut!.month}/${s.eventDebut!.year}', style: const TextStyle(fontFamily: 'Galey')),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
                if (d != null) setState(() => s.eventFin = d);
              },
              child: Text(s.eventFin == null ? 'Date fin' : '${s.eventFin!.day}/${s.eventFin!.month}/${s.eventFin!.year}', style: const TextStyle(fontFamily: 'Galey')),
            )),
          ]),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _toggleChip(String label, bool value, ValueChanged<bool> onChanged) => GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: value ? kBlTeal : Colors.white,
            border: Border.all(color: value ? kBlTeal : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: value ? Colors.white : kBlDark)),
        ),
      );
}
