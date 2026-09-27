import 'dart:io';
import 'package:flutter/material.dart';
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
import 'fjouweropinrige_ai.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';

class FjouwerOpInRigeScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const FjouwerOpInRigeScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<FjouwerOpInRigeScreen> createState() => _FjouwerOpInRigeState();
}

class _FjouwerOpInRigeState extends State<FjouwerOpInRigeScreen> with GameMixin {
  static const _rows = 6, _cols = 7;
  final _net = Network();
  final _session = SessionState();
  FjouwerOpInRigeAI? _ai;

  late List<List<int>> _board; // 0=empty 1=host 2=joiner
  int _turn = 1, _winner = 0, _hostWins = 0, _joinWins = 0;
  List<List<int>> _winCells = [];

  int get _me => _net.myIdx == 0 ? 1 : 2;
  bool get _isMyTurn => _turn == _me && _winner == 0;

  /// Resolve avatar image for a player piece (1=host, 2=joiner).
  ImageProvider? _avatarFor(int piece) {
    final p = widget.players[piece - 1];
    // Local player: use file path
    if (p.avatarPath != null && File(p.avatarPath!).existsSync()) {
      return FileImage(File(p.avatarPath!));
    }
    // Remote player: use cached bytes from chat/session
    final bytes = _session.avatarFor(p.name);
    if (bytes != null) return MemoryImage(bytes);
    return null;
  }

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _initBoard();
    _turn = widget.firstPlayer;
    if (_net.isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _ai = FjouwerOpInRigeAI(d);
    }
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_net.isSolo && widget.firstPlayer == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ai?.takeTurn(_board.map((r) => r.toList()).toList());
      });
    }
  }

  @override void dispose() { _ai?.cancel(); super.dispose(); }

  void _initBoard() {
    resetConfetti();
    resetStats();
    _board = List.generate(_rows, (_) => List.filled(_cols, 0));
  }

  /// Returns false when the column is full (nothing dropped).
  bool _drop(int col, int piece, {required bool broadcast}) {
    int row = -1;
    for (int r = _rows-1; r >= 0; r--) {
      if (_board[r][col] == 0) { row = r; break; }
    }
    if (row == -1) return false;
    SoundPlayer.i.fjouwerOpInRigeDrop();
    if (broadcast) HapticFeedback.mediumImpact(); // only haptic for local player
    _board[row][col] = piece;
    _turn = piece == 1 ? 2 : 1;
    final wc = _checkWin(row, col, piece);
    if (wc.isNotEmpty) {
      _winCells = wc; _winner = piece;
      if (piece == 1) _hostWins++; else _joinWins++;
    } else if (_board[0].every((c) => c != 0)) {
      _winner = 3;
    }
    if (broadcast) _net.send('FJO_DROP', {'col': col, 'piece': piece});
    return true;
  }

  List<List<int>> _checkWin(int row, int col, int piece) {
    for (final d in [[0,1],[1,0],[1,1],[1,-1]]) {
      final cells = [[row,col]];
      for (final sign in [-1,1]) {
        int r = row+d[0]*sign, c = col+d[1]*sign;
        while (r>=0&&r<_rows&&c>=0&&c<_cols&&_board[r][c]==piece) {
          cells.add([r,c]); r+=d[0]*sign; c+=d[1]*sign;
        }
      }
      if (cells.length >= 4) return cells;
    }
    return [];
  }

  bool _isWin(int r, int c) => _winCells.any((w) => w[0]==r && w[1]==c);

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'FJO_DROP':
        final col = msg['col'] as int;
        if (col < 0 || col >= _cols) break;
        setState(() => _drop(col, msg['piece'] as int, broadcast: false));
        if (_isMyTurn && _winner == 0) turnChanged();
        break;
      case 'GAME_RESET':
        if (!_net.isHost) {
          final first = msg['first'] as int? ?? 1;
          setState(() { _initBoard(); _turn=first; _winner=0; _winCells=[]; });
        }
        break;
      case 'FJO_SYNC_REQ':
        if (_net.isHost) _sendSync();
        break;
      case 'FJO_SYNC':
        if (!_net.isHost) _applySync(msg);
        break;
    }
  }


  void _sendSync() {
    _net.send('FJO_SYNC', {
      'board':    _board.map((r) => r.toList()).toList(),
      'turn':     _turn,   'winner': _winner,
      'hw':       _hostWins, 'jw': _joinWins,
      'winCells': _winCells,
    });
  }

  void _applySync(Map<String, dynamic> msg) {
    setState(() {
      final raw = msg['board'] as List;
      _board    = List.generate(_rows, (r) => List<int>.from(raw[r] as List));
      _turn     = msg['turn']   as int;
      _winner   = msg['winner'] as int;
      _hostWins = msg['hw']     as int;
      _joinWins = msg['jw']     as int;
      _winCells = (msg['winCells'] as List)
          .map((e) => List<int>.from(e as List)).toList();
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
          else _net.send('FJO_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  @override Widget build(BuildContext ctx) {
    final p1 = widget.players[0], p2 = widget.players[1];
    final myColor = _me == 1 ? p1.color : p2.color;

    return GameScaffold(
        key: scaffoldKey,
      title: L.fjouweropinrige.gameName,
      players: widget.players, chatMessages: chatMessages, onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.fjouweropinrige.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: _winner != 0 ? -1 : _turn - 1,
          scores: [_hostWins, _joinWins],
          scoreLabel: L.common.winsLabel,
        ),
        GameStatusBar(
          text: _winner == 0
              ? (_isMyTurn ? L.fjouweropinrige.yourTurnExcl : L.fjouweropinrige.opponentTurn.fmt({'player': _turn==1?p1.name:p2.name}))
              : _winner == 3 ? L.fjouweropinrige.draw : null,
          textColor: _winner == 0 && _isMyTurn ? kGreen : null,
        ),
        const SizedBox(height: 4),

        // Board — tap anywhere in a column to drop
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AspectRatio(
            aspectRatio: _cols / _rows,
            child: LayoutBuilder(builder: (_, c) {
              final colW = c.maxWidth / _cols;
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0A3E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder, width: 2)),
                child: Stack(children: [
                  // The grid of circles
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(children: List.generate(_rows, (r) =>
                      Expanded(child: Row(children: List.generate(_cols, (col) {
                        final cell = _board[r][col];
                        final win = _isWin(r, col);
                        final color = cell==1 ? p1.color : cell==2 ? p2.color : null;
                        final avatar = cell != 0 ? _avatarFor(cell) : null;
                        return Expanded(child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color ?? Colors.black.withValues(alpha: .35),
                              border: Border.all(
                                color: win ? Colors.white : Colors.black26,
                                width: win ? 2.5 : 1),
                              boxShadow: win ? [BoxShadow(
                                color: color!.withValues(alpha: .7), blurRadius: 12)] : null,
                              image: avatar != null ? DecorationImage(
                                image: avatar, fit: BoxFit.cover,
                                colorFilter: ColorFilter.mode(
                                  color!.withValues(alpha: .25), BlendMode.srcOver)) : null),
                          )));
                      }))))),
                  ),
                  // Invisible column tap targets — full height of board
                  if (_isMyTurn && _winner == 0)
                    Row(children: List.generate(_cols, (col) =>
                      GestureDetector(
                        onTap: () {
                          bool dropped = false;
                          setState(() => dropped = _drop(col, _me, broadcast: true));
                          if (dropped && _net.isSolo && _winner == 0) {
                            _ai?.takeTurn(_board.map((r) => r.toList()).toList());
                          }
                        },
                        child: Container(
                          width: colW,
                          color: Colors.transparent,
                          // Show a subtle highlight on hover / top indicator
                          child: Column(children: [
                            Container(
                              height: 6,
                              margin: const EdgeInsets.only(top: 4, left: 4, right: 4),
                              decoration: BoxDecoration(
                                color: myColor.withValues(alpha: .5),
                                borderRadius: BorderRadius.circular(3))),
                            Expanded(child: Container(color: Colors.transparent)),
                          ]),
                        ),
                      ))),
                ]),
              );
            }),
          ),
        ))),

        if (_winner != 0) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winner == 3 ? -1 : _winner - 1,
            onFirstRender: () { final wi = _winner == 3 ? -1 : _winner - 1; fireConfettiOnce(wi); recordResult('fjouweropinrige', wi); if (_net.isHost) _session.advanceGame(); },
            scores: [
              (label: L.common.wins.fmt({'player': widget.players[0].name}), value: '$_hostWins'),
              (label: L.common.wins.fmt({'player': widget.players[1].name}), value: '$_joinWins'),
            ],
          ),
          GameOverActions(players: widget.players, sendReset: false, onReset: () {
            _ai?.cancel();
            final first = _session.nextStarterFor(2);
            _net.send('GAME_RESET', {'first': first});
            setState(() { _initBoard(); _turn=first; _winner=0; _winCells=[]; });
            if (_net.isSolo && first == 2) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _ai?.takeTurn(_board.map((r) => r.toList()).toList());
              });
            }
          }),
        ] else const SizedBox(height: 8),
      ]),
    );
  }
}

