import 'package:flutter/material.dart';

/// Sélecteur début/fin en deux `showDatePicker` indépendants — remplace
/// `showDateRangePicker`, dont le geste "taper deux fois la même date pour
/// un congé d'un seul jour" est peu fiable/pas évident (signalé : "je
/// n'arrive pas à mettre 1 seul jour"). Ici, ne pas toucher la date de fin
/// après avoir choisi le début revient trivialement à un congé d'un jour.
Future<DateTimeRange?> pickCongeDateRange(BuildContext context, {Color teal = const Color(0xFF0C5C6C)}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CongeDateRangeSheet(teal: teal),
  );
}

class _CongeDateRangeSheet extends StatefulWidget {
  final Color teal;
  const _CongeDateRangeSheet({required this.teal});

  @override
  State<_CongeDateRangeSheet> createState() => _CongeDateRangeSheetState();
}

class _CongeDateRangeSheetState extends State<_CongeDateRangeSheet> {
  DateTime? _debut;
  DateTime? _fin;

  String _fmt(DateTime? d) => d == null
      ? 'Choisir'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pick(bool isDebut) async {
    final now = DateTime.now();
    final initial = isDebut ? (_debut ?? now) : (_fin ?? _debut ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      locale: const Locale('fr'),
    );
    if (picked == null) return;
    setState(() {
      if (isDebut) {
        _debut = picked;
        // Congé d'un jour par défaut — l'utilisateur allonge la fin si besoin.
        if (_fin == null || _fin!.isBefore(picked)) _fin = picked;
      } else {
        _fin = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = _debut != null && _fin != null && !_fin!.isBefore(_debut!);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Dates du congé', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _pick(true),
              style: OutlinedButton.styleFrom(side: BorderSide(color: widget.teal), padding: const EdgeInsets.symmetric(vertical: 12)),
              child: Text('Début : ${_fmt(_debut)}', style: TextStyle(fontFamily: 'Galey', color: widget.teal, fontWeight: FontWeight.w600, fontSize: 13)),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(
              onPressed: () => _pick(false),
              style: OutlinedButton.styleFrom(side: BorderSide(color: widget.teal), padding: const EdgeInsets.symmetric(vertical: 12)),
              child: Text('Fin : ${_fmt(_fin)}', style: TextStyle(fontFamily: 'Galey', color: widget.teal, fontWeight: FontWeight.w600, fontSize: 13)),
            )),
          ]),
          const SizedBox(height: 8),
          Text('Un seul jour ? Choisis juste le début.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: valid ? () => Navigator.pop(context, DateTimeRange(start: _debut!, end: _fin!)) : null,
            style: ElevatedButton.styleFrom(backgroundColor: widget.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Valider', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          )),
        ]),
      ),
    );
  }
}
