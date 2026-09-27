import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network.dart';
import '../../widgets/game_mixin.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';
import '../../core/session.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../l10n/app_localizations.dart';
import 'sudokuduel_generator.dart';
import '../../core/sound_player.dart';

enum SudokuDuelMode { coop, race, territory }

class SudokuDuelScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  const SudokuDuelScreen({super.key, required this.players, required this.firstPlayer});
  @override State<SudokuDuelScreen> createState() => _SudokuDuelState();
}

class _SudokuDuelState extends State<SudokuDuelScreen> with GameMixin {
  final _net = Network();

  SudokuDuelMode? _mode;
  SudokuPuzzle? _puzzle;

  // Board state: 0 = empty/given, else 1–9
  late List<List<int>> _board;   // current values (including given)
  late List<List<bool>> _given;  // true = pre-filled clue cell
  late List<List<int>> _owner;   // 0=none, 1=p1, 2=p2 (who filled this cell)
  late List<List<bool>> _wrong;  // currently marked wrong
  late List<List<int>> _enteredBy; // 0=none, 1=p1, 2=p2 (who typed the current value)

  int _selected = -1; // flat index 0–80 of selected cell
  int _turn = 1;      // 1=p1/host  2=p2/joiner  (only used in race/territory)
  int _winner = 0;    // 0=none 1=p1 2=p2 3=coop solved
  bool _waitingForMode = true; // host chooses mode first

  int get _p1Cells => _owner.expand((r) => r).where((o) => o == 1).length;
  int get _p2Cells => _owner.expand((r) => r).where((o) => o == 2).length;
  /// Race/Territory: a cell filled correctly by anyone is locked for everyone.
  bool _isLocked(int r, int c) =>
      _mode != SudokuDuelMode.coop && _owner[r][c] != 0 && !_wrong[r][c];

  bool get _isMyTurn {
    if (_mode == SudokuDuelMode.coop) return true;
    return _turn == (_net.myIdx == 0 ? 1 : 2);
  }

  @override List<Player> get gamePlayers => widget.players;

  @override void dispose() {
    _net.onDisconnected = null;
    super.dispose();
  }

  @override void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    _initEmptyBoard();
    // Solo mode: skip mode picker, auto-start in coop (single-player solve)
    if (_net.isSolo) {
      _hostStartGame(SudokuDuelMode.coop);
    }
  }

  void _initEmptyBoard() {
    _board  = List.generate(9, (_) => List.filled(9, 0));
    _given  = List.generate(9, (_) => List.filled(9, false));
    _owner  = List.generate(9, (_) => List.filled(9, 0));
    _wrong  = List.generate(9, (_) => List.filled(9, false));
    _enteredBy = List.generate(9, (_) => List.filled(9, 0));
  }

  void _loadPuzzle(SudokuPuzzle p) {
    _puzzle = p;
    _initEmptyBoard();
    for (int r = 0; r < 9; r++) {
      for (int c = 0; c < 9; c++) {
        if (p.puzzle[r][c] != 0) {
          _board[r][c] = p.puzzle[r][c];
          _given[r][c] = true;
        }
      }
    }
  }

  // ── Host: pick mode and start ─────────────────────────────────────────────
  void _hostStartGame(SudokuDuelMode mode) {
    setState(() { _mode = mode; _waitingForMode = false; });
    generatePuzzleAsync(holes: 46).then((puzzle) {
      if (!mounted) return;
      final pJson = puzzle.toJson();
      setState(() => _loadPuzzle(puzzle));
      _net.send('SDK_START', {'mode': mode.index, 'puz': pJson});
    });
  }

  // ── Cell tap ──────────────────────────────────────────────────────────────
  void _onCellTap(int idx) {
    SoundPlayer.i.sudokuDuelCell();
    if (_puzzle == null || _winner != 0) return;
    if (!_isMyTurn && _mode != SudokuDuelMode.coop) return;
    final r = idx ~/ 9, c = idx % 9;
    if (_given[r][c]) return;
    if (_isLocked(r, c)) return;
    setState(() => _selected = idx);
  }

  KeyEventResult _handleHwKey(LogicalKeyboardKey key) {
    final digits = {
      LogicalKeyboardKey.digit1: 1, LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3, LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5, LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7, LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
      LogicalKeyboardKey.numpad1: 1, LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3, LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.numpad5: 5, LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.numpad7: 7, LogicalKeyboardKey.numpad8: 8,
      LogicalKeyboardKey.numpad9: 9,
    };
    if (digits.containsKey(key)) { _onNumber(digits[key]!); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _onNumber(0); return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Number input ──────────────────────────────────────────────────────────
  void _onNumber(int num) {
    // sound played after validation
    if (_selected == -1 || _puzzle == null || _winner != 0) return;
    if (!_isMyTurn && _mode != SudokuDuelMode.coop) return;
    final r = _selected ~/ 9, c = _selected % 9;
    if (_given[r][c]) return;
    if (_isLocked(r, c)) return; // race/territory: correct cells are final

    // Erase
    if (num == 0) {
      if (_board[r][c] == 0) return;
      // Race/territory: can only erase your own (not-yet-correct) entries
      final me = _net.myIdx == 0 ? 1 : 2;
      if (_mode != SudokuDuelMode.coop && _enteredBy[r][c] != me) return;
      setState(() { _board[r][c] = 0; _wrong[r][c] = false; _enteredBy[r][c] = 0; });
      _net.send('SDK_MOVE', {'r': r, 'c': c, 'v': 0, 'ok': false, 'by': 0});
      return;
    }

    final correct = _puzzle!.solution[r][c] == num;
    final me = _net.myIdx == 0 ? 1 : 2;

    setState(() {
      _board[r][c] = num;
      _wrong[r][c] = !correct;
      _enteredBy[r][c] = me;
      if (correct) {
        _owner[r][c] = me;
        if (_mode != SudokuDuelMode.coop) {
          _turn = _turn == 1 ? 2 : 1;
        }
      }
    });

    _net.send('SDK_MOVE', {
      'r': r, 'c': c, 'v': num, 'ok': correct, 'by': me,
    });

    if (correct) _checkBoardComplete();
  }

  void _checkBoardComplete() {
    if (_puzzle == null) return;
    // All non-given cells filled correctly?
    for (int r = 0; r < 9; r++) {
      for (int c = 0; c < 9; c++) {
        if (!_given[r][c] && _board[r][c] != _puzzle!.solution[r][c]) return;
      }
    }
    // Board complete
    SoundPlayer.i.sudokuDuelSolved();
    int w;
    if (_mode == SudokuDuelMode.coop) {
      w = 3;
    } else if (_mode == SudokuDuelMode.race || _mode == SudokuDuelMode.territory) {
      w = _p1Cells > _p2Cells ? 1 : _p2Cells > _p1Cells ? 2 : 3;
    } else {
      w = 3;
    }
    setState(() => _winner = w);
    _net.send('SDK_OVER', {'w': w, 'p1': _p1Cells, 'p2': _p2Cells});
  }

  // ── Messages ──────────────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'SDK_START':
        if (!_net.isHost) {
          final p = SudokuPuzzle.fromJson(msg['puz'] as Map<String, dynamic>);
          setState(() {
            _mode = SudokuDuelMode.values[msg['mode'] as int];
            _waitingForMode = false;
            _loadPuzzle(p);
          });
        }
        break;

      case 'SDK_MOVE':
        final r  = msg['r'] as int;
        final c  = msg['c'] as int;
        final v  = msg['v'] as int;
        var ok = msg['ok'] as bool;
        var by = msg['by'] as int;
        if (_net.isHost) {
          // Host validates joiner moves; on rejection resync the joiner
          if (_puzzle == null || _winner != 0) { _sendSync(); break; }
          final sender = fromIdx == 0 ? 1 : 2;
          final bool valid;
          if (_given[r][c]) {
            valid = false;
          } else if (_mode == SudokuDuelMode.coop) {
            valid = true;
          } else if (_turn != sender || _isLocked(r, c)) {
            valid = false;
          } else if (v == 0) {
            valid = _board[r][c] != 0 && _enteredBy[r][c] == sender;
          } else {
            valid = true;
          }
          if (!valid) { _sendSync(); break; }
          ok = v != 0 && _puzzle!.solution[r][c] == v;
          by = v == 0 ? 0 : sender;
        }
        setState(() {
          _board[r][c] = v;
          _wrong[r][c] = v != 0 && !ok;
          _enteredBy[r][c] = v == 0 ? 0 : (by != 0 ? by : (fromIdx == 0 ? 1 : 2));
          if (ok && v != 0) {
            _owner[r][c] = by;
            if (_mode != SudokuDuelMode.coop) _turn = _turn == 1 ? 2 : 1;
          }
        });
        if (ok && v != 0 && _net.isHost) _checkBoardComplete();
        break;

      case 'SDK_OVER':
        setState(() {
          _winner  = msg['w'] as int;
        });
        break;

      case 'GAME_RESET':
        if (!_net.isHost) {
          resetConfetti(); resetStats();
          _resetLocal(msg['first'] as int? ?? 1);
        }
        break;

      case 'SDK_SYNC_REQ':
        if (_net.isHost) _sendSync();
        break;

      case 'SDK_SYNC':
        if (!_net.isHost) _applySync(msg);
        break;

    }
  }

  void _resetLocal([int first = 1]) {
    _initEmptyBoard();
    _selected = -1; _turn = first; _winner = 0;
    _mode = null; _puzzle = null; _waitingForMode = true;
  }

  void _reset() {
    resetConfetti();
    resetStats();
    final first = SessionState().nextStarterFor(2);
    _net.send('GAME_RESET', {'first': first});
    setState(() => _resetLocal(first));
    // Solo: no mode picker, restart in coop just like initState
    if (_net.isSolo) {
      _hostStartGame(SudokuDuelMode.coop);
    }
    // Otherwise host will pick a new mode
  }

  void _sendSync() {
    if (_puzzle == null) return;
    _net.send('SDK_SYNC', {
      'mode': _mode?.index ?? -1,
      'puz':  _puzzle!.toJson(),
      'board': _board.map((r) => r.toList()).toList(),
      'owner': _owner.map((r) => r.toList()).toList(),
      'wrong': _wrong.map((r) => r.map((v) => v ? 1 : 0).toList()).toList(),
      'entered': _enteredBy.map((r) => r.toList()).toList(),
      'turn': _turn, 'w': _winner, 'waiting': _waitingForMode,
    });
  }

  void _applySync(Map<String, dynamic> msg) {
    setState(() {
      _waitingForMode = msg['waiting'] as bool;
      if (!_waitingForMode) {
        _mode = SudokuDuelMode.values[(msg['mode'] as int).clamp(0, 2)];
        final p = SudokuPuzzle.fromJson(msg['puz'] as Map<String, dynamic>);
        _loadPuzzle(p);
        final bRaw = msg['board'] as List;
        final oRaw = msg['owner'] as List;
        final wRaw = msg['wrong'] as List;
        _board = List.generate(9, (r) => List<int>.from(bRaw[r] as List));
        _owner = List.generate(9, (r) => List<int>.from(oRaw[r] as List));
        _wrong = List.generate(9, (r) =>
            (wRaw[r] as List).map((v) => (v as int) == 1).toList());
        final eRaw = msg['entered'] as List?;
        _enteredBy = eRaw == null
            ? List.generate(9, (r) => List.generate(9, (c) => _owner[r][c]))
            : List.generate(9, (r) => List<int>.from(eRaw[r] as List));
      }
      _turn   = msg['turn'] as int;
      _winner = msg['w'] as int;
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
          else _net.send('SDK_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override Widget build(BuildContext context) {
    final p1 = widget.players[0];
    final p2 = widget.players.length > 1 ? widget.players[1] : null;

    // Mode picker for host before game starts
    if (_waitingForMode && _net.isHost) {
      return GameScaffold(
        key: scaffoldKey,
        title: L.sudokuduel.gameName,
        players: widget.players,
        chatMessages: chatMessages,
        onSendChat: sendChat,
        typingName: typingName,
        onLocalTyping: onLocalTyping,
        onReadAck: sendReadAck,
        rules: L.sudokuduel.rules,
        child: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(L.sudokuduel.chooseMode,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _modeCard(SudokuDuelMode.coop,      L.sudokuduel.modeCoopTitle,      L.sudokuduel.modeCoopDesc,      '🤝'),
            const SizedBox(height: 12),
            _modeCard(SudokuDuelMode.race,      L.sudokuduel.modeRaceTitle,      L.sudokuduel.modeRaceDesc,      '🏁'),
            const SizedBox(height: 12),
            _modeCard(SudokuDuelMode.territory, L.sudokuduel.modeTerritoryTitle, L.sudokuduel.modeTerritoryDesc, '🗺️'),
          ]),
        )),
      );
    }

    if (_waitingForMode && !_net.isHost) {
      return GameScaffold(
        key: scaffoldKey,
        title: L.sudokuduel.gameName,
        players: widget.players,
        chatMessages: chatMessages,
        onSendChat: sendChat,
        typingName: typingName,
        onLocalTyping: onLocalTyping,
        onReadAck: sendReadAck,
        rules: L.sudokuduel.rules,
        child: const Center(child: CircularProgressIndicator(color: kPurple)),
      );
    }

    // Puzzle not yet loaded (brief window between mode pick and generation)
    if (_puzzle == null) {
      return GameScaffold(
        key: scaffoldKey,
        title: L.sudokuduel.gameName,
        players: widget.players,
        chatMessages: chatMessages,
        onSendChat: sendChat,
        typingName: typingName,
        onLocalTyping: onLocalTyping,
        onReadAck: sendReadAck,
        rules: L.sudokuduel.rules,
        child: const Center(child: CircularProgressIndicator(color: kPurple)),
      );
    }

    // Mode label
    final modeLabel = switch (_mode) {
      SudokuDuelMode.coop      => L.sudokuduel.modeCoopTitle,
      SudokuDuelMode.race      => L.sudokuduel.modeRaceTitle,
      SudokuDuelMode.territory => L.sudokuduel.modeTerritoryTitle,
      null                 => '',
    };

    String status;
    if (_winner == 0) {
      if (_mode == SudokuDuelMode.coop) {
        status = modeLabel;
      } else {
        final activePlayer = _turn == 1 ? p1 : (p2 ?? p1);
        status = _isMyTurn
            ? L.sudokuduel.yourTurn
            : L.common.opponentTurn.fmt({'player': activePlayer.name});
      }
    } else {
      status = L.sudokuduel.solved;
    }

    return GameScaffold(
        key: scaffoldKey,
      title: '${L.sudokuduel.gameName} · $modeLabel',
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      rules: L.sudokuduel.rules,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          return _handleHwKey(event.logicalKey);
        },
        child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: _winner != 0 || _mode == SudokuDuelMode.coop ? -1 : _turn - 1,
          scores: _net.isSolo ? [_p1Cells] : [_p1Cells, _p2Cells],
          scoreLabel: L.sudokuduel.cells,
        ),
        GameStatusBar(
          text: _winner == 0 ? status : null,
          textColor: _winner == 0 && _isMyTurn && _mode != SudokuDuelMode.coop ? kGreen : null,
        ),

        // Board
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: AspectRatio(
            aspectRatio: 1,
            child: _buildGrid(p1, p2 ?? p1),
          ),
        ))),

        // Number pad
        if (_winner == 0)
          _buildNumPad(),

        if (_winner != 0) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winner == 3 ? -1 : _winner - 1,
            onFirstRender: () { final wi = _winner == 3 ? -1 : _winner - 1; fireConfettiOnce(wi); recordResult('sudokuduel', wi); if (_net.isHost) SessionState().advanceGame(); },
            scores: [
              (label: widget.players[0].name, value: '$_p1Cells'),
              if (!_net.isSolo) (label: widget.players[1].name, value: '$_p2Cells'),
            ],
          ),
          GameOverActions(players: widget.players, onReset: _reset, sendReset: false),
        ] else const SizedBox(height: 4),
      ])),
    );
  }

  Widget _modeCard(SudokuDuelMode mode, String title, String desc, String icon) {
    return GestureDetector(
      onTap: () => _hostStartGame(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder)),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 2),
            Text(desc,  style: TextStyle(color: kMuted, fontSize: 13)),
          ])),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ]),
      ),
    );
  }

  Widget _buildGrid(Player p1, Player p2) {
    return LayoutBuilder(builder: (_, constraints) {
      final size = constraints.maxWidth;
      final cell = size / 9;
      return SizedBox(
        width: size,
        height: size,
        child: Stack(children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GridLinePainter(),
          ),
          Column(
            children: List.generate(9, (r) =>
              Row(
                children: List.generate(9, (c) =>
                  _buildCell(r, c, cell, p1, p2)),
              )),
          ),
        ]),
      );
    });
  }

  Widget _buildCell(int r, int c, double cell, Player p1, Player p2) {
    final idx   = r * 9 + c;
    final val   = _board[r][c];
    final isGiv = _given[r][c];
    final own   = _owner[r][c];
    final isBad = _wrong[r][c];
    final isSel = _selected == idx;
    final canAct = !isGiv && _winner == 0 &&
        (_mode == SudokuDuelMode.coop || _isMyTurn) &&
        !_isLocked(r, c);

    Color bg = Colors.transparent;
    if (isGiv) {
      bg = Colors.white.withValues(alpha: 0.07);
    } else if (own == 1) {
      bg = p1.color.withValues(alpha: isBad ? 0.15 : 0.22);
    } else if (own == 2) {
      bg = p2.color.withValues(alpha: isBad ? 0.15 : 0.22);
    }
    if (isSel) bg = Colors.white.withValues(alpha: 0.22);

    Color textColor;
    if (isGiv) {
      textColor = Colors.white;
    } else if (isBad) {
      textColor = Colors.red.shade300;
    } else if (own == 1) {
      textColor = p1.color;
    } else if (own == 2) {
      textColor = p2.color;
    } else {
      textColor = Colors.white70;
    }

    return GestureDetector(
      onTap: canAct ? () => _onCellTap(idx) : null,
      child: Container(
        width: cell,
        height: cell,
        decoration: BoxDecoration(
          color: bg,
          border: isSel ? Border.all(color: Colors.white70, width: 1.5) : null,
        ),
        alignment: Alignment.center,
        child: val == 0
            ? null
            : Text('$val', style: TextStyle(
                color: textColor,
                fontSize: cell * 0.52,
                fontWeight: isGiv ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildNumPad() {
    final canInput = _selected != -1 &&
        (_mode == SudokuDuelMode.coop || _isMyTurn) &&
        _winner == 0;

    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(
          children: [
            ...List.generate(9, (i) {
              final n = i + 1;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: canInput ? () => _onNumber(n) : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: canInput
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: kBorder),
                    ),
                    alignment: Alignment.center,
                    child: Text('$n', style: TextStyle(
                      color: canInput ? Colors.white : Colors.white24,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
                  ),
                ),
              ));
            }),
            const SizedBox(width: 4),
            SizedBox(
              width: 36,
              child: GestureDetector(
                onTap: canInput ? () => _onNumber(0) : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kBorder)),
                  alignment: Alignment.center,
                  child: Icon(Icons.backspace_outlined,
                      color: canInput ? Colors.white54 : Colors.white12, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grid lines painter ────────────────────────────────────────────────────────
class _GridLinePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final thin  = Paint()..color = Colors.white.withValues(alpha: 0.12)..strokeWidth = 0.5;
    final thick = Paint()..color = Colors.white.withValues(alpha: 0.4) ..strokeWidth = 1.5;
    final cell  = size.width / 9;

    for (int i = 0; i <= 9; i++) {
      final p = i * cell;
      final paint = (i % 3 == 0) ? thick : thin;
      canvas.drawLine(Offset(p, 0),           Offset(p, size.height), paint);
      canvas.drawLine(Offset(0, p),           Offset(size.width, p),  paint);
    }

    // Outer border
    final border = Paint()..color = kBorder..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(4)),
      border);
  }

  @override bool shouldRepaint(_GridLinePainter _) => false;
}
