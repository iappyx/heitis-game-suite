import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_status_bar.dart';
import '../../l10n/app_localizations.dart';

// ── Card model ───────────────────────────────────────────────────────────────

class _PatienceCard {
  final int suit; // 0=spades, 1=hearts, 2=diamonds, 3=clubs
  final int rank; // 1=Ace .. 13=King
  bool faceUp;
  _PatienceCard({required this.suit, required this.rank, this.faceUp = false});
}

String _rankStr(int r) => switch (r) {
  1 => 'A', 11 => 'J', 12 => 'Q', 13 => 'K', _ => '$r',
};

String _suitStr(int s) => ['♠', '♥', '♦', '♣'][s];

bool _isRed(int s) => s == 1 || s == 2;

// ── Selection source ─────────────────────────────────────────────────────────

enum _Source { tableau, waste, foundation }

class _Selection {
  final _Source source;
  final int pile;      // column/foundation index
  final int cardIndex; // index within that pile (for tableau stack moves)
  const _Selection(this.source, this.pile, this.cardIndex);
}

// ── Screen ───────────────────────────────────────────────────────────────────

class PatienceScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const PatienceScreen({
    super.key,
    required this.players,
    required this.firstPlayer,
    this.extra,
  });
  @override State<PatienceScreen> createState() => _PatienceState();
}

class _PatienceState extends State<PatienceScreen> with GameMixin {
  final _net = Network();

  // ── Game state ──────────────────────────────────────────────────────────────
  List<_PatienceCard> _stock = [];
  List<_PatienceCard> _waste = [];
  List<List<_PatienceCard>> _foundations = List.generate(4, (_) => []);
  List<List<_PatienceCard>> _tableau = List.generate(7, (_) => []);

  _Selection? _selected;
  int _moves = 0;
  bool _won = false;
  bool _autoCompleting = false;
  DateTime _startTime = DateTime.now();
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override List<Player> get gamePlayers => widget.players;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _deal();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
  }

  // ── Timer ──────────────────────────────────────────────────────────────────

  void _startTimer() {
    _startTime = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_won && mounted) {
        setState(() => _elapsed = DateTime.now().difference(_startTime));
      }
    });
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Deal ───────────────────────────────────────────────────────────────────

  void _deal() {
    final deck = <_PatienceCard>[];
    for (int s = 0; s < 4; s++) {
      for (int r = 1; r <= 13; r++) {
        deck.add(_PatienceCard(suit: s, rank: r));
      }
    }
    deck.shuffle(math.Random());

    _tableau = List.generate(7, (_) => []);
    _foundations = List.generate(4, (_) => []);
    _waste = [];
    _selected = null;
    _moves = 0;
    _won = false;
    _autoCompleting = false;

    int idx = 0;
    for (int col = 0; col < 7; col++) {
      for (int row = 0; row <= col; row++) {
        final card = deck[idx++];
        card.faceUp = (row == col);
        _tableau[col].add(card);
      }
    }
    _stock = deck.sublist(idx).reversed.toList();
    for (final c in _stock) {
      c.faceUp = false;
    }
  }

  // ── New game ───────────────────────────────────────────────────────────────

  void _newGame() {
    resetConfetti();
    resetStats();
    setState(() {
      _deal();
      _startTimer();
    });
  }

  // ── Stock tap ──────────────────────────────────────────────────────────────

  void _tapStock() {
    if (_won || _autoCompleting) return;
    setState(() {
      _selected = null;
      if (_stock.isNotEmpty) {
        final card = _stock.removeLast();
        card.faceUp = true;
        _waste.add(card);
        _moves++;
      } else if (_waste.isNotEmpty) {
        // Recycle waste back to stock
        _stock = _waste.reversed.toList();
        for (final c in _stock) {
          c.faceUp = false;
        }
        _waste = [];
      }
    });
    HapticFeedback.lightImpact();
  }

  // ── Card tap logic ─────────────────────────────────────────────────────────

  void _tapWaste() {
    if (_won || _autoCompleting || _waste.isEmpty) return;
    setState(() {
      if (_selected != null && _selected!.source == _Source.waste) {
        _selected = null; // deselect
      } else {
        _selected = _Selection(_Source.waste, 0, _waste.length - 1);
      }
    });
    HapticFeedback.lightImpact();
  }

  void _tapFoundation(int idx) {
    if (_won || _autoCompleting) return;
    final sel = _selected;
    if (sel == null) {
      // Select top of foundation (for moving back to tableau)
      if (_foundations[idx].isNotEmpty) {
        setState(() => _selected = _Selection(_Source.foundation, idx, _foundations[idx].length - 1));
        HapticFeedback.lightImpact();
      }
      return;
    }
    // Try to move selected card to this foundation
    final cards = _getSelectedCards();
    if (cards == null || cards.length != 1) {
      setState(() => _selected = null);
      return;
    }
    final card = cards.first;
    if (_canPlaceOnFoundation(card, idx)) {
      _removeSelected();
      _foundations[idx].add(card);
      _moves++;
      _selected = null;
      _flipTopCards();
      _checkWin();
      HapticFeedback.mediumImpact();
      if (!_won) _checkAutoComplete();
      setState(() {});
    } else {
      setState(() => _selected = null);
    }
  }

  void _tapTableau(int col, int cardIdx) {
    if (_won || _autoCompleting) return;
    final pile = _tableau[col];

    // Tapped a face-down card — can't select or move to it
    if (cardIdx < pile.length && !pile[cardIdx].faceUp) {
      setState(() => _selected = null);
      return;
    }

    final sel = _selected;
    if (sel == null) {
      // Select this card (and everything on top of it)
      if (cardIdx < pile.length && pile[cardIdx].faceUp) {
        setState(() => _selected = _Selection(_Source.tableau, col, cardIdx));
        HapticFeedback.lightImpact();
      }
      return;
    }

    // If tapping the same card, deselect
    if (sel.source == _Source.tableau && sel.pile == col && sel.cardIndex == cardIdx) {
      setState(() => _selected = null);
      return;
    }

    // Try to move selected cards to this column
    final cards = _getSelectedCards();
    if (cards == null || cards.isEmpty) {
      setState(() => _selected = null);
      return;
    }

    // Check if we can place on this column
    if (_canPlaceOnTableau(cards.first, col)) {
      _removeSelected();
      _tableau[col].addAll(cards);
      _moves++;
      _selected = null;
      _flipTopCards();
      _checkWin();
      HapticFeedback.mediumImpact();
      if (!_won) _checkAutoComplete();
      setState(() {});
    } else {
      setState(() => _selected = null);
    }
  }

  void _tapEmptyTableau(int col) {
    if (_won || _autoCompleting) return;
    final sel = _selected;
    if (sel == null) return;

    final cards = _getSelectedCards();
    if (cards == null || cards.isEmpty) {
      setState(() => _selected = null);
      return;
    }

    // Only Kings can go on empty columns
    if (cards.first.rank == 13) {
      _removeSelected();
      _tableau[col].addAll(cards);
      _moves++;
      _selected = null;
      _flipTopCards();
      HapticFeedback.mediumImpact();
      _checkAutoComplete();
      setState(() {});
    } else {
      setState(() => _selected = null);
    }
  }

  void _tapEmptyFoundation(int idx) {
    if (_won || _autoCompleting) return;
    final sel = _selected;
    if (sel == null) return;

    final cards = _getSelectedCards();
    if (cards == null || cards.length != 1) {
      setState(() => _selected = null);
      return;
    }

    if (cards.first.rank == 1) {
      _removeSelected();
      _foundations[idx].add(cards.first);
      _moves++;
      _selected = null;
      _flipTopCards();
      _checkWin();
      HapticFeedback.mediumImpact();
      if (!_won) _checkAutoComplete();
      setState(() {});
    } else {
      setState(() => _selected = null);
    }
  }

  // ── Move helpers ───────────────────────────────────────────────────────────

  List<_PatienceCard>? _getSelectedCards() {
    final sel = _selected;
    if (sel == null) return null;
    switch (sel.source) {
      case _Source.waste:
        if (_waste.isEmpty) return null;
        return [_waste.last];
      case _Source.foundation:
        if (_foundations[sel.pile].isEmpty) return null;
        return [_foundations[sel.pile].last];
      case _Source.tableau:
        final pile = _tableau[sel.pile];
        if (sel.cardIndex >= pile.length) return null;
        return pile.sublist(sel.cardIndex);
    }
  }

  void _removeSelected() {
    final sel = _selected!;
    switch (sel.source) {
      case _Source.waste:
        _waste.removeLast();
      case _Source.foundation:
        _foundations[sel.pile].removeLast();
      case _Source.tableau:
        _tableau[sel.pile].removeRange(sel.cardIndex, _tableau[sel.pile].length);
    }
  }

  bool _canPlaceOnFoundation(_PatienceCard card, int fIdx) {
    final pile = _foundations[fIdx];
    if (pile.isEmpty) return card.rank == 1;
    final top = pile.last;
    return top.suit == card.suit && card.rank == top.rank + 1;
  }

  bool _canPlaceOnTableau(_PatienceCard card, int col) {
    final pile = _tableau[col];
    if (pile.isEmpty) return card.rank == 13;
    final top = pile.last;
    if (!top.faceUp) return false;
    return _isRed(card.suit) != _isRed(top.suit) && card.rank == top.rank - 1;
  }

  void _flipTopCards() {
    for (final col in _tableau) {
      if (col.isNotEmpty && !col.last.faceUp) {
        col.last.faceUp = true;
      }
    }
  }

  // ── Win check ──────────────────────────────────────────────────────────────

  void _checkWin() {
    if (_foundations.every((f) => f.length == 13)) {
      _won = true;
      _timer?.cancel();
      _elapsed = DateTime.now().difference(_startTime);
      HapticFeedback.heavyImpact();
      fireConfettiOnce(0);
      recordResult('patience', 0);
    }
  }

  // ── Auto-complete ──────────────────────────────────────────────────────────

  void _checkAutoComplete() {
    // All cards face-up?
    final allFaceUp = _stock.isEmpty &&
        _waste.every((c) => c.faceUp) &&
        _tableau.every((col) => col.every((c) => c.faceUp));
    if (allFaceUp && !_won && !_autoCompleting) {
      _autoCompleting = true;
      _runAutoComplete();
    }
  }

  void _runAutoComplete() {
    if (!mounted || _won) return;
    bool moved = false;

    // Try to move any card to its foundation
    // Check waste first
    if (_waste.isNotEmpty) {
      final card = _waste.last;
      for (int f = 0; f < 4; f++) {
        if (_canPlaceOnFoundation(card, f)) {
          _waste.removeLast();
          _foundations[f].add(card);
          _moves++;
          moved = true;
          break;
        }
      }
    }

    // Check tableau columns
    if (!moved) {
      for (int col = 0; col < 7; col++) {
        if (_tableau[col].isEmpty) continue;
        final card = _tableau[col].last;
        for (int f = 0; f < 4; f++) {
          if (_canPlaceOnFoundation(card, f)) {
            _tableau[col].removeLast();
            _foundations[f].add(card);
            _moves++;
            moved = true;
            break;
          }
        }
        if (moved) break;
      }
    }

    if (moved) {
      _checkWin();
      setState(() {});
      if (!_won) {
        Future.delayed(const Duration(milliseconds: 80), () {
          if (mounted) _runAutoComplete();
        });
      }
    } else {
      setState(() => _autoCompleting = false);
    }
  }

  // ── Double-tap to auto-move to foundation ─────────────────────────────────

  void _tryAutoFoundation(_PatienceCard card, _Source source, int pile) {
    for (int f = 0; f < 4; f++) {
      if (_canPlaceOnFoundation(card, f)) {
        setState(() {
          switch (source) {
            case _Source.waste:
              _waste.removeLast();
            case _Source.tableau:
              _tableau[pile].removeLast();
            case _Source.foundation:
              return; // no-op
          }
          _foundations[f].add(card);
          _moves++;
          _selected = null;
          _flipTopCards();
          _checkWin();
          if (!_won) _checkAutoComplete();
        });
        HapticFeedback.mediumImpact();
        return;
      }
    }
  }

  // ── Card selected check ────────────────────────────────────────────────────

  bool _isSelected(int col, int cardIdx) {
    final sel = _selected;
    if (sel == null) return false;
    if (sel.source != _Source.tableau) return false;
    return sel.pile == col && cardIdx >= sel.cardIndex;
  }

  bool _isWasteSelected() {
    final sel = _selected;
    return sel != null && sel.source == _Source.waste;
  }

  bool _isFoundationSelected(int idx) {
    final sel = _selected;
    return sel != null && sel.source == _Source.foundation && sel.pile == idx;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      key: scaffoldKey,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      title: L.patience.gameName,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.patience.rules,
      child: LayoutBuilder(builder: (context, constraints) {
        return _buildGame(constraints);
      }),
    );
  }

  Widget _buildGame(BoxConstraints constraints) {
    final w = constraints.maxWidth;
    // Card sizing: fit 7 columns + gaps in width, or scale to height
    final cardW = ((w - 48) / 7).clamp(40.0, 70.0);
    final cardH = cardW * 1.42;
    final gap = ((w - cardW * 7) / 8).clamp(2.0, 8.0);

    return Column(children: [
      // ── Status bar ──────────────────────────────────────────────────────
      GameStatusBar(
        text: _autoCompleting
            ? '${L.patience.moves}: $_moves · ${L.patience.autoCompleting} · ${L.patience.time}: ${_formatTime(_elapsed)}'
            : _won
              ? '${L.patience.moves}: $_moves · ${L.patience.youWin} · ${L.patience.time}: ${_formatTime(_elapsed)}'
              : '${L.patience.moves}: $_moves · ${L.patience.time}: ${_formatTime(_elapsed)}',
        textColor: _won || _autoCompleting ? kGreen : null,
      ),

      // ── Top row: Stock, Waste, spacer, Foundations ──────────────────────
      Padding(
        padding: EdgeInsets.symmetric(horizontal: gap, vertical: 2),
        child: Row(children: [
          // Stock
          _buildCardSpot(
            child: _stock.isNotEmpty
                ? _buildFaceDown(cardW, cardH)
                : _buildEmptySpot(cardW, cardH, icon: Icons.refresh),
            onTap: _tapStock,
            width: cardW,
            height: cardH,
          ),
          SizedBox(width: gap),
          // Waste
          _buildCardSpot(
            child: _waste.isNotEmpty
                ? _buildFaceUp(_waste.last, cardW, cardH,
                    selected: _isWasteSelected())
                : _buildEmptySpot(cardW, cardH),
            onTap: _waste.isNotEmpty ? _tapWaste : null,
            onDoubleTap: _waste.isNotEmpty
                ? () => _tryAutoFoundation(_waste.last, _Source.waste, 0)
                : null,
            width: cardW,
            height: cardH,
          ),
          const Spacer(),
          // 4 Foundations
          ...List.generate(4, (i) {
            final pile = _foundations[i];
            return Padding(
              padding: EdgeInsets.only(left: i > 0 ? gap : 0),
              child: _buildCardSpot(
                child: pile.isNotEmpty
                    ? _buildFaceUp(pile.last, cardW, cardH,
                        selected: _isFoundationSelected(i))
                    : _buildEmptySpot(cardW, cardH,
                        label: _suitStr(i)),
                onTap: pile.isNotEmpty
                    ? () => _tapFoundation(i)
                    : () => _tapEmptyFoundation(i),
                width: cardW,
                height: cardH,
              ),
            );
          }),
        ]),
      ),

      const SizedBox(height: 4),

      // ── Tableau ─────────────────────────────────────────────────────────
      Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(7, (col) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: gap / 2),
                  child: _buildTableauColumn(col, cardW, cardH),
                ),
              );
            }),
          ),
        ),
      ),

      // ── New game button ─────────────────────────────────────────────────
      if (_won)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: ElevatedButton(
            onPressed: _newGame,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPurple2,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(L.patience.newGame,
              style: const TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.bold)),
          ),
        ),
    ]);
  }

  // ── Tableau column ─────────────────────────────────────────────────────────

  Widget _buildTableauColumn(int col, double cardW, double cardH) {
    final pile = _tableau[col];
    if (pile.isEmpty) {
      return GestureDetector(
        onTap: () => _tapEmptyTableau(col),
        child: _buildEmptySpot(cardW, cardH),
      );
    }

    // Calculate overlap: face-down cards get less space
    const faceDownOverlap = 6.0;
    const faceUpOverlap = 18.0;

    return LayoutBuilder(builder: (context, constraints) {
      // Calculate total height needed
      double totalH = cardH;
      for (int i = 0; i < pile.length - 1; i++) {
        totalH += pile[i].faceUp ? faceUpOverlap : faceDownOverlap;
      }

      // Scale down overlap if needed to fit
      double scale = 1.0;
      if (totalH > constraints.maxHeight && constraints.maxHeight > cardH) {
        final overlapSpace = totalH - cardH;
        final available = constraints.maxHeight - cardH;
        scale = available / overlapSpace;
      }

      final scaledDown = faceDownOverlap * scale;
      final scaledUp = faceUpOverlap * scale;

      return SizedBox(
        width: cardW,
        height: constraints.maxHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Empty spot behind everything (for dropping on empty after removing all)
            Positioned(
              top: 0,
              child: GestureDetector(
                onTap: () => _tapEmptyTableau(col),
                child: SizedBox(width: cardW, height: cardH),
              ),
            ),
            ...List.generate(pile.length, (i) {
              double top = 0;
              for (int j = 0; j < i; j++) {
                top += pile[j].faceUp ? scaledUp : scaledDown;
              }
              final card = pile[i];
              return Positioned(
                top: top,
                child: GestureDetector(
                  onTap: card.faceUp
                      ? () => _tapTableau(col, i)
                      : null,
                  onDoubleTap: (card.faceUp && i == pile.length - 1)
                      ? () => _tryAutoFoundation(card, _Source.tableau, col)
                      : null,
                  child: card.faceUp
                      ? _buildFaceUp(card, cardW, cardH,
                          selected: _isSelected(col, i))
                      : _buildFaceDown(cardW, cardH),
                ),
              );
            }),
          ],
        ),
      );
    });
  }

  // ── Card widgets ───────────────────────────────────────────────────────────

  Widget _buildCardSpot({
    required Widget child,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    required double width,
    required double height,
  }) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  Widget _buildFaceUp(_PatienceCard card, double w, double h, {bool selected = false}) {
    final red = _isRed(card.suit);
    final textColor = red ? const Color(0xFFEF4444) : const Color(0xFF1E293B);
    final suitColor = red ? const Color(0xFFEF4444) : const Color(0xFF1E293B);

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? kGreen : const Color(0xFFD1D5DB),
          width: selected ? 2.5 : 1,
        ),
        boxShadow: selected
            ? [BoxShadow(color: kGreen.withValues(alpha: 0.4), blurRadius: 6)]
            : [const BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))],
      ),
      child: Stack(children: [
        // Top-left rank + suit
        Positioned(
          left: 3,
          top: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_rankStr(card.rank),
                style: TextStyle(
                  color: textColor,
                  fontSize: w * 0.22,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                )),
              Text(_suitStr(card.suit),
                style: TextStyle(color: suitColor, fontSize: w * 0.18, height: 1.0)),
            ],
          ),
        ),
        // Center suit (large)
        Center(
          child: Text(
            _suitStr(card.suit),
            style: TextStyle(color: suitColor.withValues(alpha: 0.3), fontSize: w * 0.5),
          ),
        ),
        // Bottom-right rank + suit (inverted)
        Positioned(
          right: 3,
          bottom: 2,
          child: Transform.rotate(
            angle: math.pi,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_rankStr(card.rank),
                  style: TextStyle(
                    color: textColor,
                    fontSize: w * 0.22,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  )),
                Text(_suitStr(card.suit),
                  style: TextStyle(color: suitColor, fontSize: w * 0.18, height: 1.0)),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildFaceDown(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: kPurple2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kPurple.withValues(alpha: 0.5)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))],
      ),
      child: Center(
        child: Container(
          width: w * 0.65,
          height: h * 0.75,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: kPurple.withValues(alpha: 0.4), width: 1),
          ),
          child: Center(
            child: Icon(Icons.auto_awesome, color: kPurple.withValues(alpha: 0.5), size: w * 0.3),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySpot(double w, double h, {String? label, IconData? icon}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: kBorder.withValues(alpha: 0.4),
          width: 1,
          // Dashed border approximation — using a dotted style isn't built-in,
          // so we use a subtle solid border with reduced opacity.
        ),
      ),
      child: Center(
        child: label != null
            ? Text(label, style: TextStyle(
                color: kMuted.withValues(alpha: 0.5), fontSize: w * 0.4))
            : (icon != null
                ? Icon(icon, color: kMuted.withValues(alpha: 0.5), size: w * 0.35)
                : null),
      ),
    );
  }
}
