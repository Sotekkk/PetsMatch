import 'package:flutter/material.dart';

enum VerificationLevel { none, verifie, premium }

VerificationLevel getVerificationLevel({
  bool isValidate = false,
  String? siret,
  String? statutPro,
  bool isPremium = false,
}) {
  if (isPremium) return VerificationLevel.premium;
  final verified = (statutPro == 'actif' || isValidate) && (siret?.isNotEmpty == true);
  if (verified) return VerificationLevel.verifie;
  return VerificationLevel.none;
}

class VerificationBadge extends StatelessWidget {
  final VerificationLevel level;
  final double fontSize;

  const VerificationBadge({super.key, required this.level, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    if (level == VerificationLevel.none) return const SizedBox.shrink();

    final isPremium = level == VerificationLevel.premium;
    final color  = isPremium ? const Color(0xFFD97706) : const Color(0xFF2563EB);
    final bg     = isPremium ? const Color(0xFFFEF3C7) : const Color(0xFFDBEAFE);
    final icon   = isPremium ? '★' : '✓';
    final label  = isPremium ? 'Premium' : 'Vérifié';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.8, vertical: fontSize * 0.3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w700)),
        SizedBox(width: fontSize * 0.3),
        Text(label, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w600, fontFamily: 'Galey')),
      ]),
    );
  }
}
