import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network.dart';
import '../../widgets/game_mixin.dart';
import '../../core/animated_die.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/lobby_screen.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../core/sound_player.dart';

// ─── Row colors ────────────────────────────────────────────────────────────────
const _kOrange = Color(0xFFF97316);
const _kPink   = Color(0xFFEC4899);
const _kTeal   = Color(0xFF14B8A6);
const _kLilac  = Color(0xFF818CF8);
const _rowColors = [_kOrange, _kPink, _kTeal, _kLilac];
List<String> get _rowNames => [L.kruske.rowOrange, L.kruske.rowPink, L.kruske.rowTeal, L.kruske.rowLilac];

// Orange & Pink count UP: 2..12; Teal & Lilac count DOWN: 12..2
List<int> _rowValues(int row) =>
    (row < 2) ? List.generate(11, (i) => i + 2)
              : List.generate(11, (i) => 12 - i);

// Triangular scoring: 1→1, 2→3, 3→6 … 12→78
int _score(int crosses) {
  if (crosses <= 0) return 0;
  return crosses * (crosses + 1) ~/ 2;
}

// ─── Per-player scoresheet ─────────────────────────────────────────────────────
class KruskeSheet {
  // crossed[row][col]: true = crossed
  final crossed = List.generate(4, (_) => List.filled(11, false));
  int penalties = 0;

  bool rowLocked(int row) => _rowLocked[row];
  final _rowLocked = [false, false, false, false];

  // Can player cross col in row? Must be to the right of last crossed.
  bool canCross(int row, int col) {
    if (_rowLocked[row]) return false;
    // To cross the last cell (col 10 = lock move), need ≥5 crosses already
    if (col == 10) {
      if (crosses(row) < 5) return false;
    }
    // Can only cross cells strictly to the right of the rightmost already-crossed cell
    return col > lastCrossed(row);
  }

  // Can col be crossed in row after [white] ([row, col] or null) has been crossed first?
  bool canCrossAfter(List<int>? white, int row, int col) {
    if (white == null || white[0] != row) return canCross(row, col);
    if (_rowLocked[row] || white[1] == 10) return false; // white cross locks the row
    if (col == 10 && crosses(row) + 1 < 5) return false;
    return col > white[1];
  }

  int lastCrossed(int row) {
    int last = -1;
    for (int c = 0; c < 11; c++) if (crossed[row][c]) last = c;
    return last;
  }

  int crosses(int row) => crossed[row].where((v) => v).length;

  void cross(int row, int col) {
    crossed[row][col] = true;
    if (col == 10) _rowLocked[row] = true;
  }

  // The lock symbol counts as an extra cross for the player who locked the row.
  int rowScore(int row) => _score(crosses(row) + (_rowLocked[row] ? 1 : 0));
  int penaltyScore() => penalties * -5;
  int total() {
    int t = 0;
    for (int r = 0; r < 4; r++) t += rowScore(r);
    t += penaltyScore();
    return t;
  }

  Map<String, dynamic> toJson() => {
    'crossed': crossed.map((r) => r.map((v) => v ? 1 : 0).toList()).toList(),
    'locked':  _rowLocked.map((v) => v ? 1 : 0).toList(),
    'pen':     penalties,
  };

  void applyJson(Map<String, dynamic> j) {
    final c = j['crossed'] as List;
    for (int r = 0; r < 4; r++) {
      final row = c[r] as List;
      for (int col = 0; col < 11; col++) crossed[r][col] = row[col] == 1;
    }
    final l = j['locked'] as List;
    for (int r = 0; r < 4; r++) _rowLocked[r] = l[r] == 1;
    penalties = j['pen'] as int;
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────────
class KruskeScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  const KruskeScreen({super.key, required this.players, required this.firstPlayer});
  @override State<KruskeScreen> createState() => _KruskeState();
}

enum _Phase { waiting, rolling, choosing, done }

class _KruskeState extends State<KruskeScreen> with GameMixin {
  final _net     = Network();

  late final List<KruskeSheet> _sheets;
  late int _activeIdx;          // whose turn it is (0-based)
  _Phase _phase = _Phase.waiting;

  // Dice: [white1, white2, orange, pink, teal, lilac]
  List<int> _dice = [1, 1, 1, 1, 1, 1];
  // Per-die rolling animation flag
  List<bool> _rolling = List.filled(6, false);
  bool get _anyRolling => _rolling.any((r) => r);

  // Which locks are "freshly" triggered this roll
  var _newLocks = <int>{};

  // Per-player: has this player submitted their choice this round?
  late List<bool> _submitted;

  // My pending selection: active player can pick up to 2 (white sum + color combo)
  // pendingWhite = [row, col] for white-sum cross, pendingColor = [row, col] for color cross
  // passive players can only pick pendingWhite
  List<int>? _pendingWhite;   // white-sum cross selection [row, col]
  List<int>? _pendingColor;

  // Global locked rows (union of all players' locks)
  final _globalLocked = [false, false, false, false];
  int _globalLockedCount = 0;

  // Game over?
  bool _gameOver = false;

  int get _myIdx => _net.myIdx.clamp(0, widget.players.length - 1);
  bool get _isActive => _activeIdx == _myIdx;
  bool get _isHost   => _net.isHost;

  // White sum
  int get _whiteSum => _dice[0] + _dice[1];

  // Colored combos for active player: list of [row, col] pairs
  List<List<int>> get _colorCombos {
    final combos = <List<int>>[];
    for (int r = 0; r < 4; r++) {
      if (_globalLocked[r]) continue;
      final colorDie = _dice[r + 2];
      for (int w = 0; w < 2; w++) {
        final val = colorDie + _dice[w];
        final vals = _rowValues(r);
        final col  = vals.indexOf(val);
        if (col >= 0 && _sheets[_myIdx].canCrossAfter(_pendingWhite, r, col)) {
          combos.add([r, col]);
        }
      }
    }
    return combos;
  }

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _sheets    = List.generate(widget.players.length, (_) => KruskeSheet());
    _submitted = List.filled(widget.players.length, false);
    _activeIdx = widget.firstPlayer - 1;
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    // Active player sees Roll button immediately; others wait
    _phase = _isActive ? _Phase.rolling : _Phase.waiting;
  }

  // ── Message handler ──────────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    final type = msg['type'] as String? ?? '';
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (type) {

      // Active player sends KRU_ROLL; host rebroadcasts to all then applies locally
      case 'KRU_ROLL':
        final dice = List<int>.from(msg['dice'] as List);
        if (_isHost) {
          // Rebroadcast to joiners so they animate too
          _net.send('KRU_ROLL', {'dice': dice});
          // Host applies locally (may already have animation running if host is active)
          _animateThenApply(dice);
        } else {
          // Joiner: received rebroadcast from host — animate and apply
          _animateThenApply(dice);
        }
        break;

      // A player (including host to themselves via broadcast) submitted a choice
      case 'KRU_CHOICE':
        if (_isHost) _hostApplyChoice(msg, fromIdx);
        break;

      // Host broadcasts the resolved round state to everyone

      case 'KRU_ROUND':
        _applyRoundState(msg);
        break;
      case 'KRU_SYNC_REQ':
        if (_isHost) _sendSync();
        break;

      case 'GAME_RESET':
        if (!_isHost) _resetGame();
        break;
    }
  }

  // ── Host: collect choices, resolve round ────────────────────────────────────
  void _hostApplyChoice(Map<String, dynamic> msg, int fromIdx) {
    // fromIdx=0 means from host itself (loopback), 1..N from joiners
    final playerIdx = fromIdx; // 0=host, 1..N=joiners — matches myIdx
    if (playerIdx < 0 || playerIdx >= _submitted.length) return;
    if (_submitted[playerIdx]) return;

    setState(() => _submitted[playerIdx] = true);

    // Store the choice
    final pen = msg['penalty'] as bool? ?? false;
    final whiteRow = msg['whiteRow'] as int?;
    final whiteCol = msg['whiteCol'] as int?;
    final colorRow = msg['colorRow'] as int?;
    final colorCol = msg['colorCol'] as int?;

    if (pen) {
      _sheets[playerIdx].penalties = (_sheets[playerIdx].penalties + 1).clamp(0, 4);
    } else {
      // White first, then colour (active player only) — each validated against
      // the sheet as it is at that moment, so left-to-right order always holds.
      final sheet = _sheets[playerIdx];
      if (whiteRow != null && whiteCol != null &&
          whiteRow >= 0 && whiteRow < 4 && whiteCol >= 0 && whiteCol < 11 &&
          !_globalLocked[whiteRow] && sheet.canCross(whiteRow, whiteCol)) {
        sheet.cross(whiteRow, whiteCol);
      }
      if (colorRow != null && colorCol != null && playerIdx == _activeIdx &&
          colorRow >= 0 && colorRow < 4 && colorCol >= 0 && colorCol < 11 &&
          !_globalLocked[colorRow] && sheet.canCross(colorRow, colorCol)) {
        sheet.cross(colorRow, colorCol);
      }
    }

    // Check if all players have submitted
    // In solo mode: the AI player (idx 1) never submits — mark it done automatically
    if (_net.isSolo) {
      for (int i = 1; i < _submitted.length; i++) _submitted[i] = true;
    }
    if (_submitted.every((s) => s)) {
      _hostResolveRound();
    }
  }

  void _hostResolveRound() {
    // Update global locked rows
    final newLocks = <int>{};
    for (int r = 0; r < 4; r++) {
      final wasLocked = _globalLocked[r];
      for (final sheet in _sheets) {
        if (sheet.rowLocked(r)) _globalLocked[r] = true;
      }
      if (!wasLocked && _globalLocked[r]) newLocks.add(r);
    }
    _globalLockedCount = _globalLocked.where((v) => v).length;

    // Check game-over conditions
    bool over = _globalLockedCount >= 2;
    for (final s in _sheets) if (s.penalties >= 4) over = true;

    // Advance active player (skip if game over)
    if (!over) {
      _activeIdx = (_activeIdx + 1) % widget.players.length;
      // In solo mode: skip AI players (indices 1+), wrap back to 0 (human)
      if (_net.isSolo) {
        _activeIdx = 0; // only one human player in solo
      }
    }

    _gameOver = over;

    // Build and broadcast round state
    final payload = {
      'sheets':      _sheets.map((s) => s.toJson()).toList(),
      'globalLocked': _globalLocked.map((v) => v ? 1 : 0).toList(),
      'activeIdx':   _activeIdx,
      'gameOver':    over,
      'newLocks':    newLocks.toList(),
    };
    _net.send('KRU_ROUND', payload);
    // Also apply locally (host doesn't receive its own broadcast)
    _applyRoundState({'type': 'KRU_ROUND', ...payload});
  }

  void _applyRoundState(Map<String, dynamic> msg) {
    final wasMyTurn = _isActive;
    setState(() {
      final sheets = msg['sheets'] as List;
      for (int i = 0; i < _sheets.length && i < sheets.length; i++) {
        _sheets[i].applyJson(sheets[i] as Map<String, dynamic>);
      }
      final gl = msg['globalLocked'] as List;
      for (int r = 0; r < 4; r++) _globalLocked[r] = gl[r] == 1;
      _globalLockedCount = _globalLocked.where((v) => v).length;
      _activeIdx = msg['activeIdx'] as int;
      _gameOver  = msg['gameOver'] as bool;
      _newLocks  = Set<int>.from((msg['newLocks'] as List).map((v) => v as int));
      // Restore dice if present (sync payload from reconnect includes them)
      if (msg['dice'] != null) {
        _dice = List<int>.from(msg['dice'] as List);
      }
      _rolling   = List.filled(6, false);
      _submitted = List.filled(widget.players.length, false);
      _pendingWhite = _pendingColor = null;

      // Simple: active player sees Roll button, everyone else waits
      _phase = _gameOver ? _Phase.done
             : _isActive  ? _Phase.rolling
             :               _Phase.waiting;
    });
    if (!wasMyTurn && _isActive && !_gameOver) turnChanged();
  }

  // ── Any active player rolls ──────────────────────────────────────────────────
  void _doRoll() {
    if (!_isActive || _anyRolling || _phase != _Phase.rolling) return;
    SoundPlayer.i.diceRoll();
    final rng = Random();
    final newDice = List.generate(6, (_) => rng.nextInt(6) + 1);
    setState(() => _rolling = List.filled(6, true));

    if (_isHost) {
      // Host doesn't receive its own broadcast, so trigger locally and broadcast
      _net.send('KRU_ROLL', {'dice': newDice}); // to joiners
      _animateThenApply(newDice);              // self-apply after animation
    } else {
      // Joiner: send to host who rebroadcasts back to everyone including us
      _net.send('KRU_ROLL', {'dice': newDice});
      // _animateThenApply will be triggered when we receive the host's rebroadcast
    }
  }

  // Called when KRU_ROLL is received (on all devices via host rebroadcast).
  // If animation is already running (active player started it in _doRoll),
  // just schedule the apply. If not (passive players), start it first.
  void _animateThenApply(List<int> dice) {
    if (!_anyRolling) setState(() => _rolling = List.filled(6, true));
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) _applyRoll(dice);
    });
  }

  void _applyRoll(List<int> dice) {
    setState(() {
      _dice    = dice;
      _rolling = List.filled(6, false);
      _phase   = _Phase.choosing;
      _submitted = List.filled(widget.players.length, false);
      _pendingWhite = _pendingColor = null;
      _newLocks.clear();
    });
  }

  // ── Player submits choice ────────────────────────────────────────────────────
  void _submitChoice({int? whiteRow, int? whiteCol, int? colorRow, int? colorCol, bool penalty = false}) {
    if (_phase != _Phase.choosing) return;
    final payload = <String, dynamic>{
      'whiteRow': whiteRow, 'whiteCol': whiteCol,
      'colorRow': colorRow, 'colorCol': colorCol,
      'penalty':  penalty,
    };
    setState(() { _pendingWhite = _pendingColor = null; });
    if (_isHost) {
      _hostApplyChoice({...payload, '_from': 0}, 0);
      // If round not resolved yet (waiting for joiners), show waiting state
      if (_phase == _Phase.choosing) setState(() => _phase = _Phase.waiting);
    } else {
      _net.send('KRU_CHOICE', payload);
      setState(() => _phase = _Phase.waiting);
    }
  }

  void _tapCell(int row, int col) {
    SoundPlayer.i.kruskeCross();
    if (_phase != _Phase.choosing) return;
    if (_globalLocked[row]) return;

    final sheet = _sheets[_myIdx];
    final vals  = _rowValues(row);

    // Is this cell reachable via white sum?
    final isWhite = col < vals.length && vals[col] == _whiteSum && sheet.canCross(row, col);

    // Is this cell reachable via a color+white combo (active player only)?
    bool isColor = false;
    if (_isActive) {
      for (final rc in _colorCombos) {
        if (rc[0] == row && rc[1] == col) { isColor = true; break; }
      }
    }

    if (!isWhite && !isColor) return;

    // Determine if this cell is already pending
    final isWhitePending = _pendingWhite != null &&
        _pendingWhite![0] == row && _pendingWhite![1] == col;
    final isColorPending = _pendingColor != null &&
        _pendingColor![0] == row && _pendingColor![1] == col;

    setState(() {
      if (isColorPending) {
        // Tap on current color selection: untoggle it
        _pendingColor = null;
      } else if (isWhitePending) {
        // Tap on current white selection: untoggle it
        _pendingWhite = null;
      } else if (isColor && !isWhite) {
        // Pure color cell: assign to color slot (replace any previous color)
        _pendingColor = [row, col];
      } else if (isWhite && !isColor) {
        // Pure white cell: assign to white slot (replace any previous white)
        _pendingWhite = [row, col];
        _dropInvalidColor();
      } else {
        // Ambiguous (qualifies as both white and color):
        // Fill color slot first if empty, otherwise fill white slot.
        // This lets the player pick the same number for both slots
        // by tapping the cell in one row for color and another row for white.
        if (_pendingColor == null) {
          _pendingColor = [row, col];
        } else {
          _pendingWhite = [row, col];
          _dropInvalidColor();
        }
      }
    });
  }

  // Colour cross is applied after the white cross; drop it if it no longer fits.
  void _dropInvalidColor() {
    final c = _pendingColor;
    if (c != null && !_sheets[_myIdx].canCrossAfter(_pendingWhite, c[0], c[1])) {
      _pendingColor = null;
    }
  }

  void _confirmChoice({bool penalty = false}) {
    if (penalty) {
      _submitChoice(penalty: true);
    } else {
      // Submit white and/or color choice (active player may have both)
      _submitChoice(
        whiteRow: _pendingWhite?[0], whiteCol: _pendingWhite?[1],
        colorRow: _pendingColor?[0], colorCol: _pendingColor?[1],
      );
    }
  }


  void _resetGame() {
    resetConfetti();
    resetStats();
    // Only host drives the reset — it broadcasts KRU_ROUND with blank state.
    // Both host and joiner then apply via _applyRoundState so phase is
    // set correctly on every device (incl. the case where a joiner is first active).
    if (!_isHost) return; // joiner waits for KRU_ROUND broadcast
    final blankSheets = _sheets.map((_) => {
      'crossed': List.generate(4, (_) => List.filled(11, 0)),
      'locked':  [0, 0, 0, 0],
      'pen':     0,
    }).toList();
    setState(() { _dice = [1,1,1,1,1,1]; });
    final payload = {
      'sheets':       blankSheets,
      'globalLocked': [0, 0, 0, 0],
      'activeIdx':    widget.firstPlayer - 1,
      'gameOver':     false,
      'newLocks':     <int>[],
    };
    _net.send('KRU_ROUND', payload);
    _applyRoundState({'type': 'KRU_ROUND', ...payload});
  }

  void _sendSync() {
    _net.send('KRU_ROUND', {
      'sheets':       _sheets.map((s) => s.toJson()).toList(),
      'globalLocked': _globalLocked.map((v) => v ? 1 : 0).toList(),
      'activeIdx':    _activeIdx,
      'gameOver':     _gameOver,
      'newLocks':     <int>[],
      'dice':         _dice.toList(),
    });
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _sendSync();
          else _net.send('KRU_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override Widget build(BuildContext context) => GameScaffold(
        key: scaffoldKey,
    title: L.kruske.gameName,
    players: widget.players, chatMessages: chatMessages, onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.kruske.rules,
    child: Column(children: [
      PlayerBar(
        players: widget.players,
        activeIdx: _activeIdx,
        scores: List.generate(widget.players.length, (i) => _sheets[i].total()),
        scoreLabel: ' ${L.kruske.ptsUnit}',
      ),
      GameStatusBar(
        text: () {
          switch (_phase) {
            case _Phase.waiting: return L.kruske.yourTurn.fmt({'player': widget.players[_activeIdx].name});
            case _Phase.rolling: return _isActive ? L.kruske.yourTurnRoll : L.kruske.isRolling.fmt({'player': widget.players[_activeIdx].name});
            case _Phase.choosing: return _submitted[_myIdx] ? L.kruske.waitingSubmit : (_isActive ? L.kruske.chooseCells : L.kruske.chooseOrPass);
            case _Phase.done: return L.kruske.gameOver;
          }
        }(),
        textColor: (_phase == _Phase.rolling && _isActive) ||
            (_phase == _Phase.choosing && !_submitted[_myIdx]) ? kGreen : null,
      ),
      Expanded(child: _gameOver ? _buildGameOver() : _buildMain()),
    ]),
  );

  Widget _buildMain() => Row(children: [
    // Left: dice + action
    SizedBox(width: 200, child: _buildDicePanel()),
    // Right: scoresheets
    Expanded(child: _buildScoreArea()),
  ]);

  // ── Dice panel ───────────────────────────────────────────────────────────────
  Widget _buildDicePanel() => Container(
    decoration: const BoxDecoration(border: Border(right: BorderSide(color: kBorder))),
    padding: const EdgeInsets.all(12),
    child: Column(children: [
      Text(L.kruske.diceLabel, style: const TextStyle(color: kMuted, fontSize: 10,
        fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      const SizedBox(height: 12),

      // White dice
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedDie(value: _dice[0], rolling: _rolling[0], white: true, size: 44),
        const SizedBox(width: 8),
        AnimatedDie(value: _dice[1], rolling: _rolling[1], white: true, size: 44),
      ]),
      const SizedBox(height: 6),
      Text(L.kruske.sumLabel.fmt({'n': _whiteSum}), style: const TextStyle(color: kMuted, fontSize: 11)),
      const SizedBox(height: 12),

      // Colored dice
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
        children: List.generate(4, (i) => AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _globalLocked[i] ? 0.35 : 1.0,
          child: AnimatedDie(
            key: ValueKey('kdie_$i'),
            value: _dice[i + 2],
            rolling: _rolling[i + 2],
            bgColor: _rowColors[i],
            size: 40,
          )))),

      const SizedBox(height: 16),
      const Divider(color: kBorder),
      const SizedBox(height: 12),

      // Roll button (active player on any device)
      if (_phase == _Phase.rolling && _isActive)
        ElevatedButton(
          onPressed: _anyRolling ? null : _doRoll,
          style: ElevatedButton.styleFrom(backgroundColor: kPurple2,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text(L.kruske.rollBtn, style: TextStyle(fontWeight: FontWeight.bold)))
      else if (_phase == _Phase.choosing && !_submitted[_myIdx]) ...[
        // Penalty: only the active player can take a penalty
        if (_isActive) ...[
          GestureDetector(
            onTap: () => _confirmChoice(penalty: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(L.kruske.penaltyBtn, style: TextStyle(color: Colors.redAccent,
                  fontWeight: FontWeight.bold, fontSize: 12)),
                Text(L.kruske.penaltiesUsed.fmt({'n': _sheets[_myIdx].penalties}),
                  style: const TextStyle(color: kMuted, fontSize: 10)),
              ]))),
          const SizedBox(height: 10),
        ],
        // Confirm (active: needs ≥1 selection; passive: can confirm with 0 = Pass)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (!_isActive)
            TextButton(
              onPressed: () => _submitChoice(),
              child: Text(L.kruske.passBtn, style: TextStyle(color: kMuted, fontSize: 12))),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: (_pendingWhite != null || _pendingColor != null) ? _confirmChoice : null,
            style: ElevatedButton.styleFrom(backgroundColor: kPurple2,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(L.kruske.confirmBtn, style: TextStyle(fontWeight: FontWeight.bold))),
        ]),
      ] else if (_phase == _Phase.choosing && _submitted[_myIdx]) ...[
        Text(L.kruske.waitingOthers, style: TextStyle(color: kMuted,
          fontSize: 11, fontStyle: FontStyle.italic)),
      ],

      const Spacer(),
      // Locked rows indicator
      if (_globalLockedCount > 0)
        Column(children: List.generate(4, (r) => _globalLocked[r]
          ? Container(margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _rowColors[r].withValues(alpha: .25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _rowColors[r].withValues(alpha: .6))),
              child: Text(L.kruske.rowLocked.fmt({'row': _rowNames[r]}),
                style: TextStyle(color: _rowColors[r], fontSize: 10,
                  fontWeight: FontWeight.bold)))
          : const SizedBox.shrink())),
    ]),
  );

  // ── Score area ───────────────────────────────────────────────────────────────
  Widget _buildScoreArea() => SingleChildScrollView(
    padding: const EdgeInsets.all(10),
    child: Column(children: [
      // My sheet on top, others below
      _buildPlayerSheet(_myIdx, isMe: true),
      const SizedBox(height: 10),
      ...List.generate(widget.players.length, (i) {
        if (i == _myIdx) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildPlayerSheet(i, isMe: false));
      }),
    ]),
  );

  Widget _buildPlayerSheet(int pIdx, {required bool isMe}) {
    final p     = widget.players[pIdx];
    final sheet = _sheets[pIdx];
    return Container(
      decoration: BoxDecoration(
        color: isMe ? Colors.white.withValues(alpha: .04) : Colors.white.withValues(alpha: .02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isMe ? p.color.withValues(alpha: .5) : kBorder)),
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        // Name + score
        Row(children: [
          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
          Text(isMe ? '${p.name} ${L.kruske.youSuffix}' : p.name,
            style: TextStyle(color: p.color, fontSize: 12, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${L.kruske.scoreLabel} ${sheet.total()}',
            style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text('${L.kruske.penLabel} ${sheet.penalties}',
            style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        // 4 rows
        ...List.generate(4, (row) => _buildRow(row, pIdx, isMe)),
      ]),
    );
  }

  Widget _buildRow(int row, int pIdx, bool isMe) {
    final sheet    = _sheets[pIdx];
    final color    = _rowColors[row];
    final vals     = _rowValues(row);
    final locked   = _globalLocked[row];
    final mySheet  = _sheets[_myIdx];

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        // Row color label
        Container(width: 12, height: 12, margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        // Cells
        Expanded(child: Row(children: [
          ...List.generate(11, (col) {
            final val      = vals[col];
            final crossed  = sheet.crossed[row][col];
            final isLock   = col == 10; // last cell = lock cell
            final isMine   = isMe;

            // Highlight eligible cells for my sheet
            bool canTap = false;

            if (isMine && _phase == _Phase.choosing && !locked) {
              if (val == _whiteSum && mySheet.canCross(row, col)) {
                canTap = true;
              }
              if (_isActive) {
                for (final rc in _colorCombos) {
                  if (rc[0] == row && rc[1] == col) { canTap = true; }
                }
              }
            }

            final isPendingWhite = isMine && _pendingWhite != null && _pendingWhite![0] == row && _pendingWhite![1] == col;
            final isPendingColor = isMine && _pendingColor != null && _pendingColor![0] == row && _pendingColor![1] == col;
            final isPending = isPendingWhite || isPendingColor;

            return Expanded(child: GestureDetector(
              onTap: isMine ? () => _tapCell(row, col) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: 28,
                decoration: BoxDecoration(
                  color: crossed
                      ? color.withValues(alpha: .4)
                      : isPending
                          ? color.withValues(alpha: .5)
                          : (canTap ? color.withValues(alpha: .15) : Colors.white.withValues(alpha: .04)),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isPending
                        ? color
                        : (canTap ? color.withValues(alpha: .6) : Colors.white.withValues(alpha: .12)),
                    width: isPending ? 2 : 1)),
                child: Center(child: crossed
                  ? Text('✕', style: TextStyle(color: color,
                      fontSize: 12, fontWeight: FontWeight.bold))
                  : locked && isLock
                    ? Text('🔒', style: const TextStyle(fontFamilyFallback: ['NotoColorEmoji'], fontSize: 9))
                    : Text('$val', style: TextStyle(
                        color: canTap ? kText : kMuted,
                        fontSize: isLock ? 9 : 11,
                        fontWeight: canTap ? FontWeight.bold : FontWeight.normal))),
              )));
          }),
          // Score
          SizedBox(width: 28, child: Center(child: Text('${sheet.rowScore(row)}',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)))),
        ])),
      ]),
    );
  }

  // ── Game over ─────────────────────────────────────────────────────────────────
  Widget _buildGameOver() {
    final sorted = List.generate(widget.players.length, (i) => i)
      ..sort((a, b) => _sheets[b].total().compareTo(_sheets[a].total()));
    final topScore = _sheets[sorted[0]].total();
    final tied = sorted.where((i) => _sheets[i].total() == topScore).length > 1;
    final winnerIdx = tied ? -1 : sorted[0]; // -1 = draw

    return SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      GameResultBanner(
        players: widget.players,
        winnerIdx: winnerIdx,
            onFirstRender: () { fireConfettiOnce(winnerIdx); recordResult('kruske', winnerIdx); if (_net.isHost) SessionState().advanceGame(); },
        scores: sorted.map((i) {
          final p = widget.players[i];
          return (label: p.name, value: '${_sheets[i].total()} pts');
        }).toList(),
      ),
      // Detailed score breakdown
      Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kBg2, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ...sorted.map((i) {
            final p = widget.players[i];
            final s = _sheets[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: p.color, shape: BoxShape.circle)),
                Text(p.name, style: TextStyle(color: p.color, fontWeight: FontWeight.bold)),
                const Spacer(),
                ...List.generate(4, (r) => SizedBox(width: 32, child: Text(
                  '${s.rowScore(r)}', textAlign: TextAlign.center,
                  style: TextStyle(color: _rowColors[r], fontSize: 12)))),
                const SizedBox(width: 4),
                Text('−${s.penalties * 5}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                const SizedBox(width: 8),
                Text('= ${s.total()}',
                  style: const TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 13)),
              ]));
          }),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (r) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 32, height: 6,
              decoration: BoxDecoration(color: _rowColors[r], borderRadius: BorderRadius.circular(3))))),
        ]),
      ),
      GameOverActions(players: widget.players, onReset: _resetGame),
    ]));
  }
}
