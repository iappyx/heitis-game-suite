import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../core/network.dart';
import '../../widgets/game_mixin.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/session.dart';
import '../../core/wake_lock.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../l10n/app_localizations.dart';
import '../../core/sound_player.dart';

const _winScore   = 5;
const _flashMs    = 420;   // each colour flash duration
const _gapMs      = 120;   // gap between flashes
const _numColours = 4;

// The 4 echo colours — indices 0..3
const _kleurEchoColors = [
  Color(0xFFD946EF), // magenta
  Color(0xFF22D3EE), // cyan
  Color(0xFFA3E635), // lime
  Color(0xFFFB923C), // apricot
];
const _kleurEchoDark = [
  Color(0xFF701A75), // magenta dark
  Color(0xFF164E63), // cyan dark
  Color(0xFF365314), // lime dark
  Color(0xFF7C2D12), // apricot dark
];

// ── Phase enum ────────────────────────────────────────────────────────────────
enum _Phase { idle, showing, racing, roundOver }

class KleurEchoScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  const KleurEchoScreen({super.key, required this.players, required this.firstPlayer});
  @override State<KleurEchoScreen> createState() => _KleurEchoState();
}

class _KleurEchoState extends State<KleurEchoScreen> with GameMixin {
  final _net = Network();

  List<int> _sequence = [];
  int _round = 0;
  _Phase _phase = _Phase.idle;
  int _lit = -1;   // index of currently flashing colour (-1 = none)

  // Input tracking
  List<int> _myInput = [];
  bool _inputLocked = false;

  // Scores
  int _p1Score = 0, _p2Score = 0, _winner = 0;
  bool _roundScored = false; // prevents double-score if both players finish near-simultaneously

  // Flash ticker

  // Solo endurance state
  int _soloScore = 0;    // rounds survived this game
  int _bestScore = 0;    // personal best (loaded from prefs)
  bool _soloGameOver = false;

  @override List<Player> get gamePlayers => widget.players;

  @override void dispose() {
    _net.onDisconnected = null;
    super.dispose();
  }

  @override void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_net.isSolo) {
      _loadBestScore();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _startNextRound();
      });
    } else if (_net.isHost) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _startNextRound();
      });
    }
  }

  // ── Round management (host only) ───────────────────────────────────────────
  void _startNextRound() {
    if (!mounted) return;
    _round++;
    _sequence.add(math.Random().nextInt(_numColours));
    _myInput = [];
    _inputLocked = false;
    _roundScored = false; // reset so next round can be scored
    setState(() => _phase = _Phase.showing);
    _net.send('KLE_ROUND', {'seq': _sequence, 'round': _round});
    _playSequence();
  }

  void _playSequence() async {
    // sounds injected per colour flash below
    for (int i = 0; i < _sequence.length; i++) {
      await Future.delayed(Duration(milliseconds: i == 0 ? 300 : _gapMs));
      if (!mounted) return;
      final _flashColour = _sequence[i];
      setState(() => _lit = _flashColour);
      SoundPlayer.i.kleurEchoButton(_flashColour);
      await Future.delayed(const Duration(milliseconds: _flashMs));
      if (!mounted) return;
      setState(() => _lit = -1);
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _phase = _Phase.racing);
    _net.send('KLE_GO', {});
  }

  // ── Input handling ─────────────────────────────────────────────────────────
  void _onTapColour(int colIdx) {
    SoundPlayer.i.kleurEchoButton(colIdx);
    if (_net.isSolo) { _onTapColourSolo(colIdx); return; }
    if (_phase != _Phase.racing || _inputLocked) return;
    if (_winner != 0) return;

    setState(() => _lit = colIdx);
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _lit = -1);
    });

    _myInput.add(colIdx);

    // Check correctness up to this tap
    final expected = _sequence[_myInput.length - 1];
    if (colIdx != expected) {
      // Wrong — opponent scores
      _inputLocked = true;
      SoundPlayer.i.kleurEchoWrong();
      final opponentIdx = _net.myIdx == 0 ? 2 : 1;
      _net.send('KLE_WRONG', {'by': _net.myIdx, 'scorer': opponentIdx});
      if (_net.isHost) _handleScore(opponentIdx);
      return;
    }

    // Correct full sequence — send finish
    if (_myInput.length == _sequence.length) {
      _inputLocked = true;
      _net.send('KLE_DONE', {'by': _net.myIdx});
      if (_net.isHost) _handleScore(_net.myIdx + 1); // +1 to convert 0-idx to 1/2
    }
  }

  void _handleScore(int scorer) {
    // Host only. Guard against double-score if both players finish near-simultaneously.
    if (_roundScored) return;
    _roundScored = true;
    // scorer = 1 (host) or 2 (joiner)
    if (scorer == 1) _p1Score++; else _p2Score++;
    final hasWinner = _p1Score >= _winScore || _p2Score >= _winScore;
    final w = _p1Score >= _winScore ? 1 : _p2Score >= _winScore ? 2 : 0;
    setState(() {
      _winner = w;
      _phase  = _Phase.roundOver;
    });
    _net.send('KLE_SCORE', {
      'p1': _p1Score, 'p2': _p2Score, 'w': w, 'scorer': scorer,
    });
    if (!hasWinner) {
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) _startNextRound();
      });
    }
  }

  // ── Solo best score persistence ────────────────────────────────────────────
  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _bestScore = prefs.getInt('kleurecho_best') ?? 0);
  }

  Future<void> _saveBestScore(int score) async {
    if (score > _bestScore) {
      _bestScore = score;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('kleurecho_best', score);
    }
  }

  // ── Solo input handling ────────────────────────────────────────────────────
  void _onTapColourSolo(int colIdx) {
    if (_phase != _Phase.racing || _inputLocked || _soloGameOver) return;

    setState(() => _lit = colIdx);
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _lit = -1);
    });

    _myInput.add(colIdx);

    // Check correctness up to this tap
    final expected = _sequence[_myInput.length - 1];
    if (colIdx != expected) {
      // Wrong — game over
      _inputLocked = true;
      _saveBestScore(_soloScore);
      setState(() {
        _soloGameOver = true;
        _phase = _Phase.roundOver;
        _winner = -1; // solo loss — no winner
      });
      return;
    }

    // Completed the sequence — next round
    if (_myInput.length == _sequence.length) {
      _inputLocked = true;
      setState(() {
        _soloScore++;
        _phase = _Phase.roundOver;
      });
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && !_soloGameOver) _startNextRound();
      });
    }
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'KLE_ROUND':
        if (!_net.isHost) {
          setState(() {
            _sequence    = List<int>.from(msg['seq'] as List);
            _round       = msg['round'] as int;
            _phase       = _Phase.showing;
            _myInput     = [];
            _inputLocked = false;
          });
          _playSequence();
        }
        break;

      case 'KLE_GO':
        if (!_net.isHost) setState(() => _phase = _Phase.racing);
        break;

      case 'KLE_WRONG':
        // Host handles scoring; joiner just receives KLE_SCORE
        if (_net.isHost) {
          _handleScore(msg['scorer'] as int);
        }
        break;

      case 'KLE_DONE':
        // Joiner finished first — host resolves
        if (_net.isHost) {
          final finisher = (msg['by'] as int) + 1;
          _handleScore(finisher);
        }
        break;

      case 'KLE_SCORE':
        if (!_net.isHost) {
          setState(() {
            _p1Score = msg['p1'] as int;
            _p2Score = msg['p2'] as int;
            _winner  = msg['w']  as int;
            _phase   = _Phase.roundOver;
            _inputLocked = true;
          });
        }
        break;

      case 'GAME_RESET':
        if (!_net.isHost) {
          resetConfetti(); resetStats();
          _resetLocal();
        }
        break;

      case 'KLE_SYNC_REQ':
        if (_net.isHost) _sendSync();
        break;

      case 'KLE_SYNC':
        if (!_net.isHost) _applySync(msg);
        break;

    }
  }

  void _resetLocal() {
    _sequence = []; _round = 0; _myInput = [];
    _inputLocked = false; _phase = _Phase.idle;
    _p1Score = 0; _p2Score = 0; _winner = 0; _lit = -1;
    _soloScore = 0; _soloGameOver = false;
  }

  void _reset() {
    resetConfetti();
    resetStats();
    setState(_resetLocal);
    if (_net.isSolo) {
      _loadBestScore();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _startNextRound();
      });
    } else if (_net.isHost) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _startNextRound();
      });
    }
  }

  void _sendSync() {
    _net.send('KLE_SYNC', {
      'seq': _sequence, 'round': _round,
      'p1': _p1Score, 'p2': _p2Score, 'w': _winner,
      'phase': _phase.index,
    });
  }

  void _applySync(Map<String, dynamic> msg) {
    setState(() {
      _sequence = List<int>.from(msg['seq'] as List);
      _round    = msg['round'] as int;
      _p1Score  = msg['p1']   as int;
      _p2Score  = msg['p2']   as int;
      _winner   = msg['w']    as int;
      _phase    = _Phase.values[msg['phase'] as int];
    });
    // If we reconnected mid-round while in racing phase, the rejoiner has no
    // _myInput state and has never seen the sequence. Force a replay.
    if (_phase == _Phase.racing || _phase == _Phase.showing) {
      _myInput     = [];
      _inputLocked = false;
      setState(() => _phase = _Phase.showing);
      _playSequence();
    }
  }


  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _sendSync();
          else _net.send('KLE_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override Widget build(BuildContext context) {
    if (_net.isSolo) return _buildSolo(context);

    final String statusText;
    switch (_phase) {
      case _Phase.idle:      statusText = '…'; break;
      case _Phase.showing:   statusText = L.kleurecho.watch; break;
      case _Phase.racing:    statusText = L.kleurecho.race; break;
      case _Phase.roundOver: statusText = L.kleurecho.roundLabel.fmt({'n': '$_round'}); break;
    }

    return GameScaffold(
        key: scaffoldKey,
      title: L.kleurecho.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.kleurecho.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: -1,
          scores: [_p1Score, _p2Score],
          scoreLabel: null,
        ),
        GameStatusBar(text: _winner == 0 ? statusText : null),

        // Round indicator
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(
            _round > 0 ? L.kleurecho.roundLabel.fmt({'n': '$_round'}) : '',
            style: TextStyle(color: kMuted, fontSize: 13),
          ),
        ),

        // Sequence progress dots
        if (_sequence.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_sequence.length, (i) {
                final done = _phase == _Phase.racing && i < _myInput.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? _kleurEchoColors[_sequence[i]]
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                );
              }),
            ),
          ),

        // 2×2 colour grid
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(20),
          child: AspectRatio(
            aspectRatio: 1,
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: List.generate(4, (i) => _buildButton(i)),
            ),
          ),
        ))),

        if (_winner != 0) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winner - 1,
            onFirstRender: () { fireConfettiOnce(_winner - 1); recordResult('kleurecho', _winner - 1); if (_net.isHost) SessionState().advanceGame(); },
            scores: [
              (label: widget.players[0].name, value: '$_p1Score'),
              (label: widget.players[1].name, value: '$_p2Score'),
            ],
          ),
          GameOverActions(players: widget.players, onReset: _reset),
        ] else const SizedBox(height: 8),
      ]),
    );
  }

  // ── Solo endurance build ───────────────────────────────────────────────────
  Widget _buildSolo(BuildContext context) {
    final String statusText;
    if (_soloGameOver) {
      statusText = L.common.kleurEchoGameOver;
    } else {
      switch (_phase) {
        case _Phase.idle:      statusText = '…'; break;
        case _Phase.showing:   statusText = L.kleurecho.watch; break;
        case _Phase.racing:    statusText = L.kleurecho.yourTurn; break;
        case _Phase.roundOver: statusText = L.common.kleurEchoScore.fmt({'n': '$_soloScore'}); break;
      }
    }

    return GameScaffold(
      key: scaffoldKey,
      title: '${L.kleurecho.gameName} · ${L.common.kleurEchoEndurance}',
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.kleurecho.rules,
      child: Column(children: [
        // Score header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            // Current score
            Expanded(child: Column(children: [
              Text(L.common.kleurEchoScore.fmt({'n': '$_soloScore'}),
                style: const TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.bold)),
            ])),
            // Best score
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(L.common.kleurEchoBestScore.fmt({'n': '$_bestScore'}),
                style: TextStyle(color: kMuted, fontSize: 14)),
            ]),
          ]),
        ),

        // Status
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(statusText,
            style: TextStyle(
              color: _soloGameOver ? Colors.red.shade300 : kMuted,
              fontSize: 13)),
        ),

        // Sequence progress dots
        if (_sequence.isNotEmpty && !_soloGameOver)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_sequence.length, (i) {
                final done = _phase == _Phase.racing && i < _myInput.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? _kleurEchoColors[_sequence[i]]
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                );
              }),
            ),
          ),

        // 2×2 colour grid
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(20),
          child: AspectRatio(
            aspectRatio: 1,
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: List.generate(4, (i) => _buildButton(i)),
            ),
          ),
        ))),

        // Game Over panel
        if (_soloGameOver) ...[
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(L.common.kleurEchoGameOver,
                style: const TextStyle(color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(L.common.kleurEchoScore.fmt({'n': '$_soloScore'}),
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
              if (_soloScore >= _bestScore && _soloScore > 0) ...[
                const SizedBox(height: 4),
                Text('🏆 ${L.common.kleurEchoBestScore.fmt({'n': '$_soloScore'})}',
                  style: const TextStyle(color: Colors.amber, fontSize: 14)),
              ],
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                ElevatedButton.icon(
                  onPressed: _reset,
                  icon: const Text('🔄', style: TextStyle(
                    fontFamilyFallback: ['NotoColorEmoji'], fontSize: 16)),
                  label: Text(L.common.playAgain),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple2, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10)),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    WakeLock.release();
                    final human = widget.players[0];
                    await Network().reset();
                    if (context.mounted) Navigator.pushAndRemoveUntil(context,
                      fadeScaleRoute(
                        SoloSetupScreen(humanPlayer: human)),
                      (_) => false);
                  },
                  icon: const Icon(Icons.home_outlined, size: 16),
                  label: Text(L.common.gameSelect),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kMuted,
                    side: BorderSide(color: kBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10)),
                ),
              ]),
            ]),
          ),
        ] else const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildButton(int i) {
    final isLit = _lit == i;
    final canTap = _phase == _Phase.racing && !_inputLocked && _winner == 0;

    return GestureDetector(
      onTap: canTap ? () => _onTapColour(i) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isLit ? _kleurEchoColors[i] : _kleurEchoDark[i],
          boxShadow: isLit
              ? [BoxShadow(
                  color: _kleurEchoColors[i].withValues(alpha: 0.7),
                  blurRadius: 24, spreadRadius: 4)]
              : [BoxShadow(color: Colors.black38, blurRadius: 6)],
          border: Border.all(
            color: canTap
                ? _kleurEchoColors[i].withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.05),
            width: 2),
        ),
      ),
    );
  }
}
