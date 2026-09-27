import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'rekkenje_state.dart';

class RekkenjeConfigDialog extends StatefulWidget {
  const RekkenjeConfigDialog({super.key});
  @override State<RekkenjeConfigDialog> createState() => _RekkenjeConfigState();
}

class _RekkenjeConfigState extends State<RekkenjeConfigDialog> {
  RekkenjeOp _op            = RekkenjeOp.addition;
  int    _maxVal        = 20;
  int    _rounds        = 3;
  int    _questionsPerRound = 10;
  int    _secondsPerRound   = 60;

  @override Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFF1A0A2E),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [

        Text(L.rekkenje.setupTitle,
          style: TextStyle(color: Color(0xFFF0E6FF),
            fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(L.rekkenje.setupSubtitle,
          style: TextStyle(color: Color(0x73F0E6FF), fontSize: 12)),
        const SizedBox(height: 20),

        // Operation
        _sectionLabel(L.rekkenje.sectionOperation),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8,
          children: RekkenjeOp.values.map((op) => _chip(
            kOpLabel[op]!, op == _op,
            () => setState(() => _op = op))).toList()),
        const SizedBox(height: 16),

        // Number range
        _sectionLabel(L.rekkenje.sectionNumberRange),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8,
          children: kRanges.map((r) => _chip(
            '0–$r', r == _maxVal,
            () => setState(() => _maxVal = r))).toList()),
        const SizedBox(height: 16),

        // Rounds
        _sectionLabel(L.rekkenje.sectionRounds),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8,
          children: [1, 2, 3, 5, 8].map((v) => _chip(
            '$v', v == _rounds,
            () => setState(() => _rounds = v))).toList()),
        const SizedBox(height: 16),

        // Questions per round
        _sectionLabel(L.rekkenje.sectionQuestions),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8,
          children: [5, 10, 15, 20, 25].map((v) => _chip(
            '$v', v == _questionsPerRound,
            () => setState(() => _questionsPerRound = v))).toList()),
        const SizedBox(height: 16),

        // Time per round
        _sectionLabel(L.rekkenje.sectionTime),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8,
          children: [30, 60, 90, 120, 180].map((v) => _chip(
            '${v ~/ 60 > 0 ? "${v ~/ 60}m" : ""}${v % 60 > 0 ? "${v % 60}s" : ""}',
            v == _secondsPerRound,
            () => setState(() => _secondsPerRound = v))).toList()),

        const SizedBox(height: 24),

        // Summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kPurple.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder)),
          child: Row(children: [
            const Text('📋 ', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 16)),
            Expanded(child: Text(
              '${kOpLabel[_op]!}  •  0–$_maxVal  •  ${L.rekkenje.summaryRounds.fmt({'n': _rounds})}  •  '
              '${L.rekkenje.summaryQuestions.fmt({'n': _questionsPerRound})}  •  ${L.rekkenje.summarySecondsPerRound.fmt({'n': _secondsPerRound})}',
              style: const TextStyle(color: Color(0xFFF0E6FF), fontSize: 12))),
          ])),
        const SizedBox(height: 20),

        // Buttons
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF0E6FF),
              side: const BorderSide(color: Color(0x4DA855F7)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
            child: Text(L.rekkenje.cancelBtn))),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(context, RekkenjeConfig(
              op:                 _op,
              maxVal:             _maxVal,
              rounds:             _rounds,
              questionsPerRound:  _questionsPerRound,
              secondsPerRound:    _secondsPerRound,
            )),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPurple2, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
            child: Text(L.rekkenje.startBtn,
              style: TextStyle(fontWeight: FontWeight.bold)))),
        ]),
      ])));

  Widget _sectionLabel(String t) => Text(t.toUpperCase(),
    style: const TextStyle(color: Color(0x73F0E6FF), fontSize: 10,
      letterSpacing: 1, fontWeight: FontWeight.bold));

  Widget _chip(String label, bool selected, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kPurple2 : Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? kPurple : Colors.white.withValues(alpha: .1),
            width: selected ? 2 : 1)),
        child: Text(label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0x73F0E6FF),
            fontSize: 13, fontWeight: selected ? FontWeight.bold : FontWeight.normal))));
}
