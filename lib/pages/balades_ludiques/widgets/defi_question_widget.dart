import 'package:flutter/material.dart';
import '../balades_ludiques_shared.dart';

class DefiQuestionWidget extends StatefulWidget {
  final String question;
  final String reponseAttendue;
  final Future<void> Function(String reponse) onValidated;

  const DefiQuestionWidget({super.key, required this.question, required this.reponseAttendue, required this.onValidated});

  @override
  State<DefiQuestionWidget> createState() => _DefiQuestionWidgetState();
}

class _DefiQuestionWidgetState extends State<DefiQuestionWidget> {
  final _ctrl = TextEditingController();
  bool _erreur = false;
  bool _busy = false;

  Future<void> _submit() async {
    final saisie = _ctrl.text.trim().toLowerCase();
    final attendu = widget.reponseAttendue.trim().toLowerCase();
    if (saisie.isEmpty) return;
    if (saisie != attendu) {
      setState(() => _erreur = true);
      return;
    }
    setState(() { _erreur = false; _busy = true; });
    await widget.onValidated(_ctrl.text.trim());
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.question, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
      const SizedBox(height: 14),
      TextField(
        controller: _ctrl,
        onChanged: (_) { if (_erreur) setState(() => _erreur = false); },
        style: const TextStyle(fontFamily: 'Galey'),
        decoration: InputDecoration(
          hintText: 'Votre réponse',
          errorText: _erreur ? 'Ce n\'est pas la bonne réponse, réessayez.' : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: kBlOrange, padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Valider l\'étape', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
    ]);
  }
}
