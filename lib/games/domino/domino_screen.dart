import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/wake_lock.dart';
import '../../core/sound_player.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';

// ── Tile model ────────────────────────────────────────────────────────────────
class DominoTile {
  final int a, b;
  bool faceUp;
  DominoTile(this.a, this.b, {this.faceUp = false});

  int get total => a + b;
  bool get isDouble => a == b;

  bool matches(int v) => a == v || b == v;

  // Return end value that matches, oriented correctly: a is the matching end
  DominoTile orient(int end) =>
      b == end && a != end ? DominoTile(b, a) : DominoTile(a, b);

  Map<String, dynamic> toJson() => {'a': a, 'b': b};
  factory DominoTile.fromJson(Map<String, dynamic> j) =>
      DominoTile(j['a'] as int, j['b'] as int, faceUp: true);

  @override String toString() => '[$a|$b]';
}

// Generate full double-6 set (28 tiles)
List<DominoTile> _fullSet() {
  final tiles = <DominoTile>[];
  for (int i = 0; i <= 6; i++) {
    for (int j = i; j <= 6; j++) {
      tiles.add(DominoTile(i, j));
    }
  }
  return tiles;
}

class DominoScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const DominoScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<DominoScreen> createState() => _DominoState();
}

class _DominoState extends State<DominoScreen> with GameMixin {
  final _net     = Network();
  final _session = SessionState();
  final _rng     = math.Random();

  // ── Game state ────────────────────────────────────────────────────────────
  List<DominoTile> _boneyard     = [];
  List<DominoTile> _myHand       = [];
  List<DominoTile> _opponentHand = [];  // just count for non-host; full for host
  List<DominoTile> _chain        = [];  // played chain, left-to-right

  int  _leftEnd  = -1;   // open left end of chain
  int  _rightEnd = -1;   // open right end of chain
  int  _turn     = 1;    // 1=host, 2=joiner
  int  _winner   = 0;    // 0=ongoing, 1=host, 2=joiner, 3=draw
  bool _gameOver = false;
  int  _myScore  = 0;
  int  _opScore  = 0;
  int  _opCount       = 0;    // opponent tile count
  int  _boneyardCount = 14;   // boneyard size (joiner reads from sync)
  bool _awaitingHost  = false; // joiner: move sent, ignore input until next DOM_SYNC

  @override List<Player> get gamePlayers => widget.players;

  bool get _isMyTurn => _net.myIdx == 0 ? _turn == 1 : _turn == 2;

  @override void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    WakeLock.acquire();
    if (_net.isHost) {
      _initGame();
    } else {
      // Joiner: request state in case the host's initial DOM_SYNC arrived
      // before this screen subscribed (broadcast stream, no buffering).
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _myHand.isEmpty) _net.send('DOM_SYNC_REQ');
      });
    }
  }

  // ── Solo CPU AI ─────────────────────────────────────────────────────────────
  void _triggerCpuAI() {
    if (!_net.isSolo || _gameOver || _turn != 2) return;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _gameOver || _turn != 2) return;
      _cpuTakeTurn();
    });
  }

  void _cpuTakeTurn() {
    if (!mounted || _gameOver || _turn != 2) return;
    for (final tile in List<DominoTile>.from(_opponentHand)) {
      if (_chain.isEmpty) {
        _applyPlay(tile, 'right', fromPlayer: 2);
        setState(() {});
        return;
      }
      if (tile.matches(_rightEnd)) {
        _applyPlay(tile, 'right', fromPlayer: 2);
        setState(() {});
        return;
      }
      if (tile.matches(_leftEnd)) {
        _applyPlay(tile, 'left', fromPlayer: 2);
        setState(() {});
        return;
      }
    }
    if (_boneyard.isNotEmpty) {
      _applyDraw(fromPlayer: 2);
      setState(() {});
      // Delay before retrying so each draw is visible in the UI
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _cpuTakeTurn();
      });
      return;
    }
    _applyPass(fromPlayer: 2);
    setState(() {});
  }

  void _initGame() {
    final all = _fullSet()..shuffle(_rng);
    // Deal 7 each
    final hand1 = all.sublist(0, 7);
    final hand2 = all.sublist(7, 14);
    final bone  = all.sublist(14);

    _myHand       = hand1;
    _opponentHand = hand2;
    _boneyard     = bone;
    _chain        = [];
    _leftEnd = _rightEnd = -1;
    _winner  = 0;
    _gameOver = false;
    _opCount  = 7;
    _turn = _net.isHost ? _session.nextStarterFor(2) : widget.firstPlayer;

    _broadcastSync();
    _triggerCpuAI();
  }

  void _broadcastSync() {
    _net.send('DOM_SYNC', {
      'hand2':   _opponentHand.map((t) => t.toJson()).toList(),
      'bone':    _boneyard.length,
      'opCount': _myHand.length,   // host hand count = opponent count for joiner
      'chain':   _chain.map((t) => t.toJson()).toList(),
      'leftEnd': _leftEnd,
      'rightEnd':_rightEnd,
      'turn':    _turn,
      'winner':  _winner,
      'score1':  _myScore,
      'score2':  _opScore,
    });
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    if (!mounted) return;
    switch (msg['type'] as String) {
      case 'DOM_SYNC':
        if (!_net.isHost) {
          final wasMyTurn = _isMyTurn;
          setState(() {
            _awaitingHost = false;
            _myHand    = (msg['hand2'] as List).map((j) => DominoTile.fromJson(j as Map<String, dynamic>)).toList();
            _chain     = (msg['chain'] as List).map((j) => DominoTile.fromJson(j as Map<String, dynamic>)).toList();
            _leftEnd   = msg['leftEnd'] as int;
            _rightEnd  = msg['rightEnd'] as int;
            _turn      = msg['turn'] as int;
            _winner    = msg['winner'] as int;
            _gameOver  = _winner != 0;
            _myScore   = msg['score2'] as int;
            _opScore   = msg['score1'] as int;
            _opCount        = msg['opCount'] as int? ?? _opCount;
            _boneyardCount  = msg['bone'] as int? ?? _boneyardCount;
          });
          if (!wasMyTurn && _isMyTurn && !_gameOver) turnChanged();
        }
        break;

      case 'DOM_OP_COUNT':
        setState(() => _opCount = msg['n'] as int);
        break;

      case 'DOM_PLAY':
        if (_net.isHost) {
          final tile = DominoTile.fromJson(msg['tile'] as Map<String, dynamic>);
          final side = msg['side'] as String;
          // Validate: joiner's turn, tile in joiner's hand, fits chosen end.
          final inHand = _opponentHand.any((t) => t.a == tile.a && t.b == tile.b);
          final fits = _chain.isEmpty || (side == 'left' ? tile.matches(_leftEnd)
              : side == 'right' && tile.matches(_rightEnd));
          if (!_isJoinerMove(fromIdx) || !inHand || !fits) {
            _broadcastSync(); // re-sync so the joiner clears its waiting flag
            break;
          }
          _applyPlay(tile, side, fromPlayer: 2);
          setState(() {});
        }
        break;

      case 'DOM_DRAW':
        if (_net.isHost) {
          // Validate: joiner's turn and no playable tile in hand.
          if (!_isJoinerMove(fromIdx) || _canPlay(_opponentHand)) {
            _broadcastSync();
            break;
          }
          _applyDraw(fromPlayer: 2);
          setState(() {});
        }
        break;

      case 'DOM_PASS':
        if (_net.isHost) {
          // Validate: joiner's turn, no playable tile and boneyard empty.
          if (!_isJoinerMove(fromIdx) || _canPlay(_opponentHand) || _boneyard.isNotEmpty) {
            _broadcastSync();
            break;
          }
          _applyPass(fromPlayer: 2);
          setState(() {});
        }
        break;

      case 'GAME_RESET':
        GameOverActions.handleMessage(msg, _reset);
        break;

      case 'DOM_SYNC_REQ':
        if (_net.isHost) _broadcastSync();
        break;
    }
  }

  // ── Game logic (host only) ────────────────────────────────────────────────

  /// Host: true if a joiner move message may be applied now.
  bool _isJoinerMove(int fromIdx) => fromIdx == 1 && _turn == 2 && !_gameOver;

  void _applyPlay(DominoTile tile, String side, {required int fromPlayer}) {
    final hand = fromPlayer == 1 ? _myHand : _opponentHand;
    hand.removeWhere((t) => t.a == tile.a && t.b == tile.b);

    if (_chain.isEmpty) {
      _chain.add(DominoTile(tile.a, tile.b));
      _leftEnd  = tile.a;
      _rightEnd = tile.b;
    } else if (side == 'left') {
      final oriented = tile.orient(_leftEnd);
      _chain.insert(0, DominoTile(oriented.b, oriented.a)); // new left is oriented.a
      _leftEnd = oriented.b;
    } else {
      final oriented = tile.orient(_rightEnd);
      _chain.add(DominoTile(oriented.a, oriented.b));
      _rightEnd = oriented.b;
    }

    SoundPlayer.i.uiClick();
    _checkGameOver();
    if (!_gameOver) {
      _turn = _turn == 1 ? 2 : 1;
      _maybeAutoAction();
    }
    _broadcastSync();
    _net.send('DOM_OP_COUNT', {'n': _myHand.length});
  }

  void _applyDraw({required int fromPlayer}) {
    if (_boneyard.isEmpty) {
      _applyPass(fromPlayer: fromPlayer);
      return;
    }
    final drawn = _boneyard.removeLast();
    final hand  = fromPlayer == 1 ? _myHand : _opponentHand;
    hand.add(drawn);
    SoundPlayer.i.uiSelect();
    _maybeAutoAction();
    _broadcastSync();
    _net.send('DOM_OP_COUNT', {'n': _myHand.length});
  }

  void _applyPass({required int fromPlayer}) {
    _turn = _turn == 1 ? 2 : 1;
    _checkGameOver();
    _broadcastSync();
  }

  void _maybeAutoAction() {
    // If current player can't play, auto-draw or pass for AI-less game
    // (Both players are real in this game, so nothing to do here)
  }

  void _checkGameOver() {
    if (_myHand.isEmpty) {
      _winner = 1;
      _gameOver = true;
      _myScore += _opponentHand.fold(0, (s, t) => s + t.total);
      _session.advanceGame();
    } else if (_opponentHand.isEmpty) {
      _winner = 2;
      _gameOver = true;
      _opScore += _myHand.fold(0, (s, t) => s + t.total);
      _session.advanceGame();
    } else if (_boneyard.isEmpty) {
      // Check if both players are blocked
      final p1Can = _canPlay(_myHand);
      final p2Can = _canPlay(_opponentHand);
      if (!p1Can && !p2Can) {
        final p1Sum = _myHand.fold(0, (s, t) => s + t.total);
        final p2Sum = _opponentHand.fold(0, (s, t) => s + t.total);
        if (p1Sum < p2Sum) {
          _winner = 1;
          _myScore += p2Sum;  // winner scores loser's remaining pips
        } else if (p2Sum < p1Sum) {
          _winner = 2;
          _opScore += p1Sum;
        } else {
          _winner = 3; // draw
        }
        _gameOver = true;
        _session.advanceGame();
      }
    }
  }

  bool _canPlay(List<DominoTile> hand) {
    if (_chain.isEmpty) return true;
    return hand.any((t) => t.matches(_leftEnd) || t.matches(_rightEnd));
  }

  List<String> _playableSides(DominoTile tile) {
    if (_chain.isEmpty) return ['left'];
    final sides = <String>[];
    if (tile.matches(_leftEnd))  sides.add('left');
    if (tile.matches(_rightEnd)) sides.add('right');
    return sides;
  }

  // ── UI actions ─────────────────────────────────────────────────────────────

  void _onTapTile(DominoTile tile) {
    if (_gameOver || !_isMyTurn || _awaitingHost) return;
    final sides = _playableSides(tile);
    if (sides.isEmpty) return;
    if (sides.length == 1) {
      _doPlay(tile, sides.first);
    } else {
      // Both ends match — ask which side
      showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: kBg2,
        title: Text(L.domino.yourTurn, style: const TextStyle(color: kText)),
        content: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _doPlay(tile, 'left'); },
            child: Text(L.domino.leftSide),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _doPlay(tile, 'right'); },
            child: Text(L.domino.rightSide),
          ),
        ]),
      ));
    }
  }

  void _doPlay(DominoTile tile, String side) {
    if (_gameOver || !_isMyTurn || _awaitingHost) return;
    if (_net.isHost) {
      _applyPlay(tile, side, fromPlayer: 1);
      _triggerCpuAI();
    } else {
      _awaitingHost = true;
      _net.send('DOM_PLAY', {'tile': tile.toJson(), 'side': side});
    }
    setState(() {});
  }

  void _onDraw() {
    if (_gameOver || !_isMyTurn || _awaitingHost) return;
    if (_net.isHost) {
      _applyDraw(fromPlayer: 1);
      _triggerCpuAI();
    } else {
      _awaitingHost = true;
      _net.send('DOM_DRAW');
    }
    setState(() {});
  }

  void _onPass() {
    if (_gameOver || !_isMyTurn || _awaitingHost) return;
    if (_net.isHost) {
      _applyPass(fromPlayer: 1);
      _triggerCpuAI();
    } else {
      _awaitingHost = true;
      _net.send('DOM_PASS');
    }
    setState(() {});
  }

  void _reset() {
    resetConfetti();
    resetStats();
    _awaitingHost = false;
    if (_net.isHost) _initGame();
    // Redraw so the old game-over banner disappears and input is re-enabled
    // (also reached via REMATCH_REQ, which calls this callback directly).
    if (mounted) setState(() {});
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _broadcastSync();
          else _net.send('DOM_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  @override void dispose() { super.dispose(); }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override Widget build(BuildContext context) {
    final myIdx = _net.myIdx;
    final p     = widget.players;
    final canPlay = _isMyTurn && !_gameOver && _myHand.any((t) => _playableSides(t).isNotEmpty);
    // Joiner doesn't know boneyard size; we track boneyard only on host.
    // Use _opCount field as boneyard proxy for joiner (it's broadcast via DOM_SYNC 'bone').
    final boneyardNotEmpty = _net.isHost ? _boneyard.isNotEmpty : (_boneyardCount > 0);
    final canDraw = _isMyTurn && !_gameOver && !canPlay && boneyardNotEmpty;

    return GameScaffold(
      key: scaffoldKey,
      title: L.domino.gameName,
      players: p,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      typingName: typingName,
      rules: L.domino.rules,
      child: Column(children: [
        PlayerBar(
          players: p,
          activeIdx: _turn - 1,
          scores: _net.isHost ? [_myScore, _opScore] : [_opScore, _myScore],
          scoreLabel: 'pts',
        ),
        GameStatusBar(text: L.domino.tilesLeft.fmt({'n': '${_net.isHost ? _boneyard.length : _boneyardCount}'})),

        // Opponent tile count
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '${p[1 - myIdx].name}: $_opCount ${L.domino.gameName}',
            style: const TextStyle(color: kMuted, fontSize: 13),
          ),
        ),

        // Chain
        Expanded(
          flex: 2,
          child: _chain.isEmpty
              ? Center(child: Text(L.domino.yourTurn,
                  style: const TextStyle(color: kMuted, fontSize: 16)))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: _chain.map((t) => _TileWidget(tile: t, small: true)).toList(),
                  ),
                ),
        ),

        // My hand
        Container(
          height: 110,
          color: Colors.black26,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: _myHand.map((tile) {
                final sides = _playableSides(tile);
                final playable = _isMyTurn && !_gameOver && sides.isNotEmpty;
                return GestureDetector(
                  onTap: playable ? () => _onTapTile(tile) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: playable ? [
                        BoxShadow(color: kPurple.withValues(alpha: .5), blurRadius: 8)
                      ] : null,
                    ),
                    child: _TileWidget(tile: tile, highlight: playable),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Action row
        if (!_gameOver)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (!canPlay && _isMyTurn) ...[
                ElevatedButton.icon(
                  onPressed: canDraw ? _onDraw : null,
                  icon: const Text('🎴', style: TextStyle(fontFamilyFallback: ['NotoColorEmoji'])),
                  label: Text(L.domino.draw),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: !canDraw && _isMyTurn ? _onPass : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: Text(L.domino.pass),
                ),
              ],
              if (!_isMyTurn)
                Text(
                  L.domino.opponentTurn.fmt({'player': p[1 - myIdx].name}),
                  style: const TextStyle(color: kMuted),
                ),
            ]),
          ),

        if (_gameOver) ...[
          GameResultBanner(
            players: p,
            winnerIdx: _winner == 3 ? -1 : _winner - 1,
            onFirstRender: () {
              final wi = _winner == 3 ? -1 : _winner - 1;
              fireConfettiOnce(wi);
              recordResult('domino', wi);
            },
            scores: _net.isHost
                ? [(label: p[0].name, value: '$_myScore'), (label: p[1].name, value: '$_opScore')]
                : [(label: p[0].name, value: '$_opScore'), (label: p[1].name, value: '$_myScore')],
          ),
          GameOverActions(players: p, onReset: _reset),
        ],
      ]),
    );
  }
}

// ── Tile widget ───────────────────────────────────────────────────────────────
class _TileWidget extends StatelessWidget {
  final DominoTile tile;
  final bool small;
  final bool highlight;
  const _TileWidget({required this.tile, this.small = false, this.highlight = false});

  @override Widget build(BuildContext context) {
    final sz = small ? 28.0 : 42.0;
    final fs = small ? 11.0 : 16.0;
    return Container(
      width: sz * 2 + 4,
      height: sz + 4,
      margin: small ? const EdgeInsets.only(right: 3) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: highlight ? kPurple.withValues(alpha: .15) : kCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight ? kPurple : kBorder,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: sz, child: Center(
          child: Text('${tile.a}', style: TextStyle(
            fontSize: fs, fontWeight: FontWeight.bold, color: kText)))),
        Container(width: 1, height: sz * .6, color: kBorder),
        SizedBox(width: sz, child: Center(
          child: Text('${tile.b}', style: TextStyle(
            fontSize: fs, fontWeight: FontWeight.bold, color: kText)))),
      ]),
    );
  }
}
