import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../core/session.dart';
import '../../core/wake_lock.dart';
import '../../core/sound_player.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';

// ── Game constants ──────────────────────────────────────────────────────────
const _roundDuration   = 30.0;   // seconds per round
const _totalRounds     = 3;
const _targetsPerRound = 50;
const _targetRadius    = 0.045;  // normalised radius (fraction of field width)
const _spawnInterval   = 0.6;    // seconds between target spawns
const _countdownSecs   = 3;

// ── Phases ──────────────────────────────────────────────────────────────────
enum _Phase { countdown, playing, roundEnd, gameOver }

// ── Target model ────────────────────────────────────────────────────────────
class _Target {
  final String id;
  final double x, y;       // normalised 0..1
  final int playerIdx;     // which player's color (0-based)
  final double appearAt;   // seconds into round
  final double duration;   // how long visible
  bool tapped = false;
  bool missed = false;

  _Target({
    required this.id,
    required this.x,
    required this.y,
    required this.playerIdx,
    required this.appearAt,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'x': x, 'y': y,
    'p': playerIdx, 'a': appearAt, 'd': duration,
  };

  factory _Target.fromJson(Map<String, dynamic> j) => _Target(
    id: j['id'] as String,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    playerIdx: j['p'] as int,
    appearAt: (j['a'] as num).toDouble(),
    duration: (j['d'] as num).toDouble(),
  );
}

// ── Tap animation state ─────────────────────────────────────────────────────
class _TapEffect {
  final double x, y;
  final Color color;
  final bool correct;
  double age = 0;   // seconds since created
  _TapEffect({required this.x, required this.y, required this.color, required this.correct});
}

// ═════════════════════════════════════════════════════════════════════════════
class TikRazernijScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const TikRazernijScreen({
    super.key,
    required this.players,
    required this.firstPlayer,
    this.extra,
  });
  @override State<TikRazernijScreen> createState() => _TikRazernijState();
}

class _TikRazernijState extends State<TikRazernijScreen>
    with SingleTickerProviderStateMixin, GameMixin {
  final _net = Network();
  final _rng = math.Random();

  // Ghost player colors for solo mode (player is index 0, ghosts are 1+)
  static const _soloGhostColors = [Color(0xFFFF7043), Color(0xFF42A5F5)];

  /// Get player color by index — works for both multiplayer and solo (with ghost colors).
  Color _playerColor(int idx) {
    if (!_net.isSolo) {
      return widget.players[idx.clamp(0, widget.players.length - 1)].color;
    }
    // Solo: index 0 = human player, 1+ = ghost colors
    if (idx == 0) return widget.players[0].color;
    return _soloGhostColors[(idx - 1) % _soloGhostColors.length];
  }

  // ── State ─────────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.countdown;
  int _currentRound = 1;       // 1-based
  int _countdownValue = _countdownSecs;

  // Targets for the current round
  List<_Target> _targets = [];

  // Scores: per-round and total
  late List<int> _roundScores;
  late List<int> _totalScores;
  late List<int> _roundWins;   // how many rounds each player won
  int? _hostWinner;            // joiner: final winner as decided by host (-1 = draw)

  // Tap effects (visual feedback)
  final List<_TapEffect> _tapEffects = [];

  // Wrong-color flash (per player, local only)
  bool _wrongFlash = false;

  // Ticker for smooth animation
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  double _roundElapsed = 0;    // seconds into current round

  // Countdown timer
  Timer? _countdownTimer;

  @override List<Player> get gamePlayers => widget.players;

  // ── Init / Dispose ────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final n = widget.players.length;
    _roundScores = List.filled(n, 0);
    _totalScores = List.filled(n, 0);
    _roundWins   = List.filled(n, 0);

    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };

    _ticker = createTicker(_onTick);

    // Host generates and broadcasts targets; solo starts directly
    // Delay slightly so joiner has time to set up their message listener
    if (_net.isHost) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _startCountdown();
      });
    } else if (!_net.isSolo) {
      // Joiner: if we don't receive TIK_ROUND within 2s, request it
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _targets.isEmpty) {
          _net.send('TIK_SYNC_REQ');
        }
      });
    }
  }

  @override
  void dispose() {
    msgSub?.cancel();
    _ticker?.dispose();
    _countdownTimer?.cancel();
    WakeLock.release();
    super.dispose();
  }

  // ── Countdown phase ───────────────────────────────────────────────────────
  void _startCountdown() {
    setState(() {
      _phase = _Phase.countdown;
      _countdownValue = _countdownSecs;
      _roundElapsed = 0;
      _lastTick = Duration.zero;
      _roundScores = List.filled(widget.players.length, 0);
      _targets = _generateTargets();
      _tapEffects.clear();
    });

    // Broadcast round data
    if (!_net.isSolo) {
      _net.send('TIK_ROUND', {
        'round': _currentRound,
        'targets': _targets.map((t) => t.toJson()).toList(),
      });
    }

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() { _countdownValue--; });
      HapticFeedback.lightImpact();
      if (_countdownValue <= 0) {
        timer.cancel();
        _startPlaying();
      }
    });
  }

  void _startPlaying() {
    setState(() { _phase = _Phase.playing; });
    _lastTick = Duration.zero;
    _roundElapsed = 0;
    _ticker?.start();
  }

  // ── Target generation (host only) ─────────────────────────────────────────
  List<_Target> _generateTargets() {
    // Solo: use 3 "ghost" player slots so targets come in multiple colors
    // Player is always index 0; ghost colors at 1 and 2
    final n = _net.isSolo ? 3 : widget.players.length;
    final targets = <_Target>[];
    for (int i = 0; i < _targetsPerRound; i++) {
      final t = i / _targetsPerRound;
      // Duration starts at 1.5s, decreases to 0.7s by end of round
      final dur = 1.5 - 0.8 * t;
      final appearAt = i * _spawnInterval;

      // Assign to players evenly
      final playerIdx = i % n;

      // Random position avoiding edges
      double x, y;
      int attempts = 0;
      do {
        x = 0.1 + _rng.nextDouble() * 0.8;
        y = 0.1 + _rng.nextDouble() * 0.8;
        attempts++;
      } while (attempts < 20 && _tooClose(targets, x, y, appearAt, dur));

      targets.add(_Target(
        id: 'r${_currentRound}_$i',
        x: x, y: y,
        playerIdx: playerIdx,
        appearAt: appearAt,
        duration: dur,
      ));
    }
    return targets;
  }

  bool _tooClose(List<_Target> existing, double x, double y,
      double appearAt, double duration) {
    for (final t in existing) {
      // Only check targets that overlap in time
      if (t.appearAt + t.duration < appearAt || appearAt + duration < t.appearAt) continue;
      final dx = t.x - x;
      final dy = t.y - y;
      if (dx * dx + dy * dy < 0.025) return true; // ~0.16 apart minimum
    }
    return false;
  }

  // ── Ticker ────────────────────────────────────────────────────────────────
  void _onTick(Duration elapsed) {
    if (!mounted || _phase != _Phase.playing) return;
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    _roundElapsed += dt;

    // Update tap effects
    _tapEffects.removeWhere((e) {
      e.age += dt;
      return e.age > 0.4;
    });

    // Mark expired targets
    for (final t in _targets) {
      if (!t.tapped && !t.missed && _roundElapsed > t.appearAt + t.duration) {
        t.missed = true;
      }
    }

    // Check round end
    if (_roundElapsed >= _roundDuration) {
      _ticker?.stop();
      _endRound();
      return;
    }

    setState(() {});
  }

  // ── Round end ─────────────────────────────────────────────────────────────
  void _endRound() {
    // Joiner: the host is authoritative for totals, round wins and game over
    // (received via TIK_SCORES / TIK_GAME_OVER). Only stop playing locally.
    if (!_net.isHost && !_net.isSolo) {
      setState(() { _phase = _Phase.roundEnd; });
      return;
    }

    // Determine round winner
    int bestScore = -999;
    int bestIdx = 0;
    for (int i = 0; i < _roundScores.length; i++) {
      _totalScores[i] += _roundScores[i];
      if (_roundScores[i] > bestScore) {
        bestScore = _roundScores[i];
        bestIdx = i;
      }
    }

    // Check for round tie
    final tiedCount = _roundScores.where((s) => s == bestScore).length;
    if (tiedCount == 1) {
      _roundWins[bestIdx]++;
    }

    if (_net.isHost && !_net.isSolo) {
      _net.send('TIK_SCORES', {
        'scores': _totalScores,
        'roundScores': _roundScores,
        'roundWins': _roundWins,
      });
    }

    setState(() { _phase = _Phase.roundEnd; });

    // Check if game is over (best of 3)
    final maxWins = _roundWins.reduce(math.max);
    final winsNeeded = (_totalRounds / 2).ceil(); // 2 wins needed
    if (_currentRound >= _totalRounds || maxWins >= winsNeeded) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _finishGame();
      });
    } else {
      // Start next round after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _net.isHost) {
          _currentRound++;
          _startCountdown();
        }
      });
    }
  }

  void _finishGame() {
    // Overall winner = most round wins (best of 3); equal round wins = draw
    final finalWinner = _winnerIdx;

    if (_net.isHost && !_net.isSolo) {
      _net.send('TIK_GAME_OVER', {
        'winner': finalWinner,
        'scores': _totalScores,
        'roundWins': _roundWins,
      });
    }

    setState(() { _phase = _Phase.gameOver; });
  }

  // ── Tap handling ──────────────────────────────────────────────────────────
  void _onPointerDown(PointerDownEvent event, Size fieldSize) {
    if (_phase != _Phase.playing) return;

    final nx = event.localPosition.dx / fieldSize.width;
    final ny = event.localPosition.dy / fieldSize.height;

    // Find the closest visible, untapped target within tap radius
    _Target? hit;
    double bestDist = double.infinity;
    const tapRadius = _targetRadius * 1.5; // generous tap zone

    for (final t in _targets) {
      if (t.tapped || t.missed) continue;
      if (_roundElapsed < t.appearAt || _roundElapsed > t.appearAt + t.duration) continue;

      final dx = t.x - nx;
      final dy = t.y - ny;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < tapRadius && dist < bestDist) {
        bestDist = dist;
        hit = t;
      }
    }

    if (hit == null) return;

    hit.tapped = true;
    final myIdx = _net.myIdx.clamp(0, widget.players.length - 1);
    final correct = hit.playerIdx == myIdx;

    if (correct) {
      _roundScores[myIdx]++;
      HapticFeedback.lightImpact();
      SoundPlayer.i.uiClick();
    } else {
      _roundScores[myIdx]--;
      HapticFeedback.heavyImpact();
      SoundPlayer.i.uiBack();
      setState(() { _wrongFlash = true; });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() { _wrongFlash = false; });
      });
    }

    final playerColor = correct
        ? _playerColor(hit.playerIdx)
        : Colors.red;
    _tapEffects.add(_TapEffect(
      x: hit.x, y: hit.y,
      color: playerColor,
      correct: correct,
    ));

    // Send tap to host for validation (multiplayer)
    if (!_net.isSolo && !_net.isHost) {
      _net.send('TIK_TAP', {'id': hit.id});
    }

    // Host validates own taps directly; 'hit' removes the target everywhere
    if (_net.isHost && !_net.isSolo) {
      _net.send('TIK_SCORES', {
        'scores': _totalScores,
        'roundScores': _roundScores,
        'roundWins': _roundWins,
        'hit': hit.id,
        'by': myIdx,
      });
    }

    setState(() {});
  }

  // ── Network messages ──────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    final type = msg['type'] as String? ?? '';
    switch (type) {
      case 'TIK_ROUND':
        if (!_net.isHost) {
          final round = msg['round'] as int;
          final rawTargets = msg['targets'] as List;
          _ticker?.stop(); // local round timer may still be running
          setState(() {
            _currentRound = round;
            _targets = rawTargets
                .map((j) => _Target.fromJson(j as Map<String, dynamic>))
                .toList();
            _roundScores = List.filled(widget.players.length, 0);
            _tapEffects.clear();
            _phase = _Phase.countdown;
            _countdownValue = _countdownSecs;
          });
          // Start local countdown (synced approximately)
          _countdownTimer?.cancel();
          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted) { timer.cancel(); return; }
            setState(() { _countdownValue--; });
            HapticFeedback.lightImpact();
            if (_countdownValue <= 0) {
              timer.cancel();
              _startPlaying();
            }
          });
        }
        break;

      case 'TIK_TAP':
        // Host validates taps from joiners
        if (_net.isHost && _phase == _Phase.playing) {
          final id = msg['id'] as String;
          final target = _targets.where((t) => t.id == id).firstOrNull;
          if (target != null && !target.tapped && !target.missed) {
            target.tapped = true;
            final correct = target.playerIdx == fromIdx;
            if (correct) {
              _roundScores[fromIdx]++;
            } else {
              _roundScores[fromIdx]--;
            }
            // 'hit' removes the target on every device (3+ players: the
            // others must not be able to tap it any more)
            _net.send('TIK_SCORES', {
              'scores': _totalScores,
              'roundScores': _roundScores,
              'roundWins': _roundWins,
              'hit': id,
              'by': fromIdx,
            });
            setState(() {});
          } else {
            // Rejected (already taken / expired): the sender already counted
            // it locally — send it the real scores so it doesn't drift
            _net.sendTo(fromIdx, 'TIK_SCORES', {
              'scores': _totalScores,
              'roundScores': _roundScores,
              'roundWins': _roundWins,
              if (target != null) 'hit': id,
            });
          }
        }
        break;

      case 'TIK_SCORES':
        if (!_net.isHost) {
          setState(() {
            final scores = (msg['scores'] as List).cast<int>();
            final roundScores = (msg['roundScores'] as List).cast<int>();
            final roundWins = (msg['roundWins'] as List).cast<int>();
            for (int i = 0; i < scores.length && i < _totalScores.length; i++) {
              _totalScores[i] = scores[i];
            }
            for (int i = 0; i < roundScores.length && i < _roundScores.length; i++) {
              _roundScores[i] = roundScores[i];
            }
            for (int i = 0; i < roundWins.length && i < _roundWins.length; i++) {
              _roundWins[i] = roundWins[i];
            }
            // Target taken by someone (maybe another player): remove it here too
            final hitId = msg['hit'] as String?;
            if (hitId != null) {
              for (final t in _targets) {
                if (t.id == hitId && !t.tapped) {
                  t.tapped = true;
                  final by = msg['by'] as int?;
                  if (by != null && by != _net.myIdx) {
                    _tapEffects.add(_TapEffect(x: t.x, y: t.y,
                      color: _playerColor(by), correct: t.playerIdx == by));
                  }
                }
              }
            }
          });
        }
        break;

      case 'TIK_GAME_OVER':
        if (!_net.isHost) {
          final scores = (msg['scores'] as List).cast<int>();
          final roundWins = (msg['roundWins'] as List?)?.cast<int>();
          _ticker?.stop();
          _countdownTimer?.cancel();
          setState(() {
            for (int i = 0; i < scores.length && i < _totalScores.length; i++) {
              _totalScores[i] = scores[i];
            }
            if (roundWins != null) {
              for (int i = 0; i < roundWins.length && i < _roundWins.length; i++) {
                _roundWins[i] = roundWins[i];
              }
            }
            _hostWinner = msg['winner'] as int?;
            _phase = _Phase.gameOver;
          });
        }
        break;

      case 'TIK_SYNC_REQ':
        // Joiner missed TIK_ROUND — resend current targets
        if (_net.isHost && _targets.isNotEmpty) {
          _net.send('TIK_ROUND', {
            'round': _currentRound,
            'targets': _targets.map((t) => t.toJson()).toList(),
          });
        }
        break;

      case 'GAME_RESET':
        if (!_net.isHost) {
          resetConfetti();
          resetStats();
          setState(_resetLocal);
        }
        break;
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────
  void _resetLocal() {
    final n = widget.players.length;
    _currentRound = 1;
    _roundScores = List.filled(n, 0);
    _totalScores = List.filled(n, 0);
    _roundWins   = List.filled(n, 0);
    _hostWinner = null;
    _targets = [];
    _tapEffects.clear();
    _phase = _Phase.countdown;
    _countdownValue = _countdownSecs;
    _roundElapsed = 0;
    _lastTick = Duration.zero;
    _wrongFlash = false;
    _ticker?.stop();
  }

  void _reset() {
    resetConfetti();
    resetStats();
    setState(_resetLocal);
    if (_net.isHost) {
      _startCountdown();
    }
  }

  void _showReconnect() {
    showReconnectDialog(
      onMsg: _onMsg,
      onReconnected: () {
        if (_net.isHost) {
          _net.send('TIK_SCORES', {
            'scores': _totalScores,
            'roundScores': _roundScores,
            'roundWins': _roundWins,
          });
        }
      },
    );
  }

  // ── Winner calculation ────────────────────────────────────────────────────
  /// Best of 3: most round wins wins; equal round wins = draw (-1).
  /// Joiner uses the winner decided by the host.
  int get _winnerIdx {
    if (!_net.isHost && !_net.isSolo && _hostWinner != null) return _hostWinner!;
    int bestWins = -1;
    int bestIdx = 0;
    for (int i = 0; i < _roundWins.length; i++) {
      if (_roundWins[i] > bestWins) {
        bestWins = _roundWins[i];
        bestIdx = i;
      }
    }
    final tiedCount = _roundWins.where((w) => w == bestWins).length;
    return tiedCount > 1 ? -1 : bestIdx;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Status bar text
    String? statusText;
    switch (_phase) {
      case _Phase.countdown:
        statusText = _countdownValue > 0
            ? '$_countdownValue'
            : L.tikrazernij.go;
        break;
      case _Phase.playing:
        final remaining = (_roundDuration - _roundElapsed).ceil().clamp(0, 30);
        statusText = '${L.tikrazernij.round.fmt({'n': '$_currentRound'})} — ${L.tikrazernij.timeLeft.fmt({'n': '$remaining'})}';
        break;
      case _Phase.roundEnd:
        statusText = L.tikrazernij.roundOver;
        break;
      case _Phase.gameOver:
        statusText = null;
        break;
    }

    return GameScaffold(
      key: scaffoldKey,
      title: L.tikrazernij.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.tikrazernij.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: -1,
          scores: _phase == _Phase.playing ? _roundScores : _totalScores,
          scoreLabel: null,
        ),
        GameStatusBar(
          text: statusText,
          textColor: _phase == _Phase.countdown && _countdownValue <= 0
              ? kGreen : null,
        ),

        Expanded(child: _buildGameArea()),

        if (_phase == _Phase.gameOver) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winnerIdx,
            onFirstRender: () {
              fireConfettiOnce(_winnerIdx);
              recordResult('tikrazernij', _winnerIdx);
              if (_net.isHost) SessionState().advanceGame();
            },
            scores: widget.players.asMap().entries.map((e) =>
              (label: e.value.name, value: '${_totalScores[e.key]}'),
            ).toList(),
          ),
          GameOverActions(players: widget.players, onReset: _reset),
        ] else const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildGameArea() {
    return LayoutBuilder(builder: (_, constraints) {
      final fieldSize = Size(constraints.maxWidth, constraints.maxHeight);

      return Listener(
        onPointerDown: (e) => _onPointerDown(e, fieldSize),
        child: Stack(children: [
          // Game field
          CustomPaint(
            size: fieldSize,
            painter: _TikRazernijPainter(
              targets: _targets,
              tapEffects: _tapEffects,
              elapsed: _roundElapsed,
              players: widget.players,
              phase: _phase,
              countdownValue: _countdownValue,
              colorForIdx: _playerColor,
              wrongFlash: _wrongFlash,
            ),
          ),

          // Countdown overlay
          if (_phase == _Phase.countdown)
            Center(
              child: Text(
                _countdownValue > 0 ? '$_countdownValue' : L.tikrazernij.go,
                style: TextStyle(
                  fontSize: _countdownValue > 0 ? 96 : 72,
                  fontWeight: FontWeight.w900,
                  color: _countdownValue > 0 ? kText : kGreen,
                  shadows: [
                    Shadow(
                      color: (_countdownValue > 0 ? kPurple : kGreen).withValues(alpha: 0.6),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),

          // Round-end overlay
          if (_phase == _Phase.roundEnd)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                decoration: BoxDecoration(
                  color: kBg2.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kBorder),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(L.tikrazernij.roundOver,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kText)),
                  const SizedBox(height: 12),
                  ...widget.players.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${e.value.name}: ${_roundScores[e.key]}',
                      style: TextStyle(fontSize: 18, color: e.value.color, fontWeight: FontWeight.bold),
                    ),
                  )),
                ]),
              ),
            ),

          // "Tap your color!" hint at start
          if (_phase == _Phase.playing && _roundElapsed < 3)
            Positioned(
              bottom: 16, left: 0, right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _roundElapsed < 2 ? 1.0 : (3 - _roundElapsed).clamp(0.0, 1.0),
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: kBg2.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      L.tikrazernij.tapYourColor,
                      style: const TextStyle(color: kMuted, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),

          // Wrong-color flash overlay
          if (_wrongFlash)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: Colors.red.withValues(alpha: 0.15)),
              ),
            ),
        ]),
      );
    });
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────
class _TikRazernijPainter extends CustomPainter {
  final List<_Target> targets;
  final List<_TapEffect> tapEffects;
  final double elapsed;
  final List<Player> players;
  final _Phase phase;
  final int countdownValue;
  final Color Function(int) colorForIdx;
  final bool wrongFlash;

  const _TikRazernijPainter({
    required this.targets,
    required this.tapEffects,
    required this.elapsed,
    required this.players,
    required this.phase,
    required this.countdownValue,
    required this.colorForIdx,
    required this.wrongFlash,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Background
    final bgPaint = Paint()..color = const Color(0xFF0D0621);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // Subtle grid pattern
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    for (double gx = 0; gx < w; gx += 40) {
      canvas.drawLine(Offset(gx, 0), Offset(gx, h), gridPaint);
    }
    for (double gy = 0; gy < h; gy += 40) {
      canvas.drawLine(Offset(0, gy), Offset(w, gy), gridPaint);
    }

    // Field border
    final borderPaint = Paint()
      ..color = kBorder
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(8)),
      borderPaint,
    );

    if (phase != _Phase.playing && phase != _Phase.roundEnd) return;

    // Draw visible targets
    final baseR = _targetRadius * w;
    for (final t in targets) {
      if (t.tapped || t.missed) continue;
      if (elapsed < t.appearAt) continue;
      if (elapsed > t.appearAt + t.duration) continue;

      final age = elapsed - t.appearAt;
      final remaining = t.duration - age;

      // Scale-in animation (first 100ms)
      double scale = 1.0;
      if (age < 0.1) {
        scale = (age / 0.1).clamp(0.0, 1.0);
      }
      // Shrink + fade when about to expire (last 300ms)
      double alpha = 1.0;
      if (remaining < 0.3) {
        final f = (remaining / 0.3).clamp(0.0, 1.0);
        scale *= 0.7 + 0.3 * f;
        alpha = f;
      }

      final r = baseR * scale;
      final cx = t.x * w;
      final cy = t.y * h;
      final color = colorForIdx(t.playerIdx);

      // Glow
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.25 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(Offset(cx, cy), r * 1.8, glowPaint);

      // Target circle
      final grad = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        colors: [
          Color.lerp(color, Colors.white, 0.4)!.withValues(alpha: alpha),
          color.withValues(alpha: alpha),
        ],
      );
      final circlePaint = Paint()
        ..shader = grad.createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, circlePaint);

      // Inner ring for style
      final ringPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(Offset(cx, cy), r * 0.6, ringPaint);
    }

    // Draw tap effects
    for (final e in tapEffects) {
      final cx = e.x * w;
      final cy = e.y * h;
      final progress = (e.age / 0.4).clamp(0.0, 1.0);
      final easeOut = 1.0 - (1.0 - progress) * (1.0 - progress);

      if (e.correct) {
        // Expanding ring + fade
        final r = baseR * (1.0 + easeOut * 1.5);
        final opacity = (1.0 - easeOut).clamp(0.0, 1.0);
        final ringPaint = Paint()
          ..color = e.color.withValues(alpha: opacity * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(Offset(cx, cy), r, ringPaint);

        // Fill fade-out
        final fillPaint = Paint()
          ..color = e.color.withValues(alpha: opacity * 0.3);
        canvas.drawCircle(Offset(cx, cy), r * 0.8, fillPaint);
      } else {
        // Red X for wrong taps
        final opacity = (1.0 - easeOut).clamp(0.0, 1.0);
        final xSize = baseR * 0.8;
        final xPaint = Paint()
          ..color = Colors.red.withValues(alpha: opacity)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(cx - xSize, cy - xSize), Offset(cx + xSize, cy + xSize), xPaint);
        canvas.drawLine(
          Offset(cx + xSize, cy - xSize), Offset(cx - xSize, cy + xSize), xPaint);
      }
    }

    // Progress bar at bottom
    if (phase == _Phase.playing) {
      final progress = (elapsed / _roundDuration).clamp(0.0, 1.0);
      const barH = 4.0;
      final barY = h - barH;

      // Background
      final barBg = Paint()..color = Colors.white.withValues(alpha: 0.1);
      canvas.drawRect(Rect.fromLTWH(0, barY, w, barH), barBg);

      // Progress
      final barColor = progress > 0.8 ? Colors.red : kPurple;
      final barFg = Paint()..color = barColor.withValues(alpha: 0.7);
      canvas.drawRect(Rect.fromLTWH(0, barY, w * (1 - progress), barH), barFg);
    }
  }

  @override
  bool shouldRepaint(_TikRazernijPainter old) => true; // always repaint during ticker
}
