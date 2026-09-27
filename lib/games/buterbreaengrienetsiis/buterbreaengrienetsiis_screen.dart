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
import 'buterbreaengrienetsiis_ai.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';

class ButerBreaEnGrieneTsiisScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const ButerBreaEnGrieneTsiisScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<ButerBreaEnGrieneTsiisScreen> createState() => _ButerBreaEnGrieneTsiisState();
}

const _kLines = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]];

class _ButerBreaEnGrieneTsiisState extends State<ButerBreaEnGrieneTsiisScreen> with GameMixin {
  final _net = Network();
  final _session = SessionState();
  ButerBreaEnGrieneTsiisAI? _ai;

  // board[i] = 0 (empty), 1 (host/X), 2 (joiner/O)
  List<int> _board = List.filled(9, 0);
  int _turn = 1;          // 1 = host, 2 = joiner
  int _winner = 0;        // 0=none, 1=host, 2=joiner, 3=draw
  int _hostWins = 0, _joinWins = 0, _draws = 0;

  int get _myPiece => _net.myIdx == 0 ? 1 : 2;
  bool get _isMyTurn => _turn == _myPiece && _winner == 0;

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _turn = widget.firstPlayer;
    if (_net.isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _ai = ButerBreaEnGrieneTsiisAI(d);
    }
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_net.isSolo && widget.firstPlayer == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ai?.takeTurn(List<int>.from(_board));
      });
    }
  }

  @override void dispose() { _ai?.cancel(); super.dispose(); }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'BUT_MOVE':
        final idx = msg['i'] as int;
        if (idx < 0 || idx >= 9) break;
        setState(() {
          _board[idx] = msg['piece'] as int;
          _turn = msg['piece'] == 1 ? 2 : 1;
          _winner = _calcWinner();
          // Sync scores from sender (authoritative) — or increment locally for solo AI moves
          if (msg['hw'] != null) _hostWins = msg['hw'] as int;
          else if (_winner == 1) _hostWins++;
          if (msg['jw'] != null) _joinWins = msg['jw'] as int;
          else if (_winner == 2) _joinWins++;
          if (msg['d']  != null) _draws    = msg['d']  as int;
          else if (_winner == 3) _draws++;
        });
        if (_isMyTurn && _winner == 0) turnChanged();
        break;
      case 'GAME_RESET':
        if (!_net.isHost) {
          final first = msg['first'] as int? ?? 1;
          resetConfetti();
          resetStats();
          setState(() { _board = List.filled(9, 0); _turn = first; _winner = 0; });
        }
        break;
      case 'BUT_SYNC_REQ':
        if (_net.isHost) _sendSync();
        break;
      case 'BUT_SYNC':
        if (!_net.isHost) _applySync(msg);
        break;
    }
  }

  void _tap(int i) {
    if (!_isMyTurn || _board[i] != 0) return;
    if (_turn == 1) SoundPlayer.i.buterBreaEnGrieneTsiisPlaceX(); else SoundPlayer.i.buterBreaEnGrieneTsiisPlaceO();
    HapticFeedback.mediumImpact();
    setState(() {
      _board[i] = _myPiece;
      _turn = _myPiece == 1 ? 2 : 1;
      _winner = _calcWinner();
      if (_winner == 1) _hostWins++;
      else if (_winner == 2) _joinWins++;
      else if (_winner == 3) _draws++;
    });
    _net.send('BUT_MOVE', {'i': i, 'piece': _myPiece,
      'hw': _hostWins, 'jw': _joinWins, 'd': _draws});
    // In solo mode, trigger AI after human move
    if (_net.isSolo && _winner == 0) {
      _ai?.takeTurn(List<int>.from(_board));
    }
  }

  void _reset() {
    _ai?.cancel();
    resetConfetti();
    resetStats();
    final first = _session.nextStarterFor(2);
    _net.send('GAME_RESET', {'first': first});
    setState(() { _board = List.filled(9, 0); _turn = first; _winner = 0; });
    if (_net.isSolo && first == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ai?.takeTurn(List<int>.from(_board));
      });
    }
  }

  int _calcWinner() {
    for (final l in _kLines) {
      if (_board[l[0]] != 0 && _board[l[0]] == _board[l[1]] && _board[l[1]] == _board[l[2]]) {
        return _board[l[0]];
      }
    }
    if (_board.every((c) => c != 0)) return 3;
    return 0;
  }

  List<int> _winLine() {
    for (final l in _kLines) {
      if (_board[l[0]] != 0 && _board[l[0]] == _board[l[1]] && _board[l[1]] == _board[l[2]]) {
        return l;
      }
    }
    return [];
  }


  void _sendSync() {
    _net.send('BUT_SYNC', {
      'board': _board, 'turn': _turn, 'winner': _winner,
      'hw': _hostWins, 'jw': _joinWins, 'dr': _draws,
    });
  }

  void _applySync(Map<String, dynamic> msg) {
    setState(() {
      _board     = List<int>.from(msg['board'] as List);
      _turn      = msg['turn']   as int;
      _winner    = msg['winner'] as int;
      _hostWins  = msg['hw']     as int;
      _joinWins  = msg['jw']     as int;
      _draws     = msg['dr']     as int;
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
          else _net.send('BUT_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (r) => false)));
  }

  @override Widget build(BuildContext context) {
    final p1 = widget.players[0]; // host = X
    final p2 = widget.players[1]; // joiner = O
    final winLine = _winLine();

    return GameScaffold(
        key: scaffoldKey,
      title: L.buterbreaengrienetsiis.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.buterbreaengrienetsiis.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: _winner != 0 ? -1 : _turn - 1,
          scores: [_hostWins, _joinWins],
          scoreLabel: L.common.winsLabel,
        ),
        GameStatusBar(
          text: _winner == 0
              ? (_isMyTurn ? L.buterbreaengrienetsiis.yourTurnExcl : L.buterbreaengrienetsiis.opponentTurn.fmt({'player': _turn == 1 ? p1.name : p2.name}))
              : _winner == 3 ? L.buterbreaengrienetsiis.drawCount.fmt({'n': '$_draws'}) : null,
          textColor: _winner == 0 && _isMyTurn ? kGreen : null,
        ),

        // Board
        Expanded(child: Center(child: AspectRatio(
          aspectRatio: 1,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: 9,
              itemBuilder: (_, i) {
                final cell = _board[i];
                final isWin = winLine.contains(i);
                return GestureDetector(
                  onTap: () => _tap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isWin
                        ? (_winner == 1 ? p1.color : p2.color).withValues(alpha: .25)
                        : Colors.white.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isWin
                          ? (_winner == 1 ? p1.color : p2.color)
                          : kBorder,
                        width: isWin ? 2 : 1),
                    ),
                    child: cell == 0 ? null : LayoutBuilder(
                      builder: (_, c) => CustomPaint(
                        size: Size(c.maxWidth, c.maxHeight),
                        painter: _MarkPainter(
                          isX: cell == 1,
                          color: cell == 1 ? p1.color : p2.color,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ))),

        if (_winner != 0) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winner == 3 ? -1 : _winner - 1,
            onFirstRender: () { final wi = _winner == 3 ? -1 : _winner - 1; fireConfettiOnce(wi); recordResult('buterbreaengrienetsiis', wi); if (_net.isHost) _session.advanceGame(); },
            scores: [
              (label: L.common.wins.fmt({'player': widget.players[0].name}), value: '$_hostWins'),
              (label: L.buterbreaengrienetsiis.draws, value: '$_draws'),
              (label: L.common.wins.fmt({'player': widget.players[1].name}), value: '$_joinWins'),
            ],
          ),
          GameOverActions(players: widget.players, onReset: _reset, sendReset: false),
        ] else const SizedBox(height: 8),
      ]),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final bool isX;
  final Color color;
  const _MarkPainter({required this.isX, required this.color});

  @override void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.13
      ..style = PaintingStyle.stroke;
    final pad = size.width * 0.18;
    if (isX) {
      canvas.drawLine(Offset(pad, pad),
        Offset(size.width - pad, size.height - pad), p);
      canvas.drawLine(Offset(size.width - pad, pad),
        Offset(pad, size.height - pad), p);
    } else {
      canvas.drawOval(Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad), p);
    }
  }

  @override bool shouldRepaint(_MarkPainter old) => old.isX != isX || old.color != color;
}

