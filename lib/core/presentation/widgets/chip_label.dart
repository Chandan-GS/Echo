import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChipLabel extends StatelessWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final bool isOutline;

  const ChipLabel({
    super.key,
    required this.text,
    this.backgroundColor = Colors.transparent,
    this.textColor = const Color.fromARGB(255, 128, 128, 128),
    this.isOutline = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isOutline ? Colors.transparent : backgroundColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: GoogleFonts.nunito(
          fontSize: 16,
          color: textColor,
          fontWeight: isOutline ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
    );
  }
}
