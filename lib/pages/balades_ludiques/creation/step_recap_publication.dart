part of 'creation_flow_page.dart';

class _StepRecapPublication extends StatelessWidget {
  final _CreationFlowPageState s;
  const _StepRecapPublication({required this.s});

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Récapitulatif', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.titreCtrl.text, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 10),
            _row('Espèce', blEspeceLabel(s.espece)),
            _row('Difficulté', blDifficulteLabel(s.difficulte)),
            _row('Durée', s.dureeCtrl.text.isEmpty ? '—' : blDureeLabel(int.tryParse(s.dureeCtrl.text))),
            _row('Distance', s.distanceCtrl.text.isEmpty ? '—' : '${s.distanceCtrl.text} km'),
            _row('Tarif', s.gratuit ? 'Gratuit' : '${s.prixCtrl.text} €'),
            _row('Étapes', '${s.points.length}'),
            if (s.famille || s.sportif || s.pmr)
              _row('Critères', [if (s.famille) 'Famille', if (s.sportif) 'Sportif', if (s.pmr) 'PMR'].join(', ')),
            if (User_Info.isAdmin && s.typeEvenement != 'communautaire')
              _row('Événement', s.typeEvenement == 'officiel_petsmatch' ? 'Officiel PetsMatch' : 'Partenaire — ${s.partenaireNomCtrl.text}'),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('Étapes du parcours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        ...s.points.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            CircleAvatar(radius: 11, backgroundColor: kBlTeal.withOpacity(0.1),
                child: Text('${e.key + 1}', style: const TextStyle(fontSize: 10, color: kBlTeal))),
            const SizedBox(width: 8),
            Icon(blTypeDefiIcon(e.value['type_defi']?.toString() ?? ''), size: 15, color: kBlGreen),
            const SizedBox(width: 6),
            Expanded(child: Text(e.value['titre']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
          ]),
        )),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(14)),
          child: const Row(children: [
            Icon(Icons.info_outline, color: kBlGreen, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text('Votre parcours sera visible par tous les utilisateurs dès la publication.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
          ]),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
