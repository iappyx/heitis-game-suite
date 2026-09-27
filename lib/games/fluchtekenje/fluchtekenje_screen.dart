import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../core/session.dart';
import '../../core/sound_player.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const _kDrawSecs   = 15;  // seconds per drawing phase
const _kWinScore   = 5;   // points needed to win
const _kVoteSecs   = 20;  // host resolves with the votes it has after this

// ── Phases ───────────────────────────────────────────────────────────────────
enum _Phase { drawing, revealing, results, gameOver }

// ═════════════════════════════════════════════════════════════════════════════
class FluchTekenjeScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const FluchTekenjeScreen({
    super.key,
    required this.players,
    required this.firstPlayer,
    this.extra,
  });
  @override State<FluchTekenjeScreen> createState() => _FluchTekenjeState();
}

class _FluchTekenjeState extends State<FluchTekenjeScreen> with GameMixin {
  final _net = Network();
  final _rng = math.Random();

  // ── State ─────────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.drawing;
  int _currentRound = 1;
  int _timeLeft = _kDrawSecs;
  Timer? _drawTimer;
  Timer? _syncReqTimer; // joiner: retries FLU_SYNC_REQ until round state arrives

  // Scores per player (index-aligned with widget.players)
  late List<int> _scores;

  // Current prompt
  String _prompt = '';

  // Used prompt indices (to avoid repeats)
  final List<int> _usedPrompts = [];

  // ── Drawing state (local) ─────────────────────────────────────────────────
  // Each stroke is a list of normalised Offset (0..1)
  final List<List<Offset>> _myStrokes = [];
  List<Offset>? _currentStroke;
  bool _strokesSent = false;

  // ── All drawings (populated after reveal) ─────────────────────────────────
  // Key: player index, Value: list of strokes (list of normalised Offsets)
  final Map<int, List<List<Offset>>> _allDrawings = {};

  // ── Voting state ──────────────────────────────────────────────────────────
  int _myVote = -1;              // player index voted for (-1 = not voted)
  late List<int> _votes;         // vote count per player (from host)
  int _roundWinnerIdx = -1;      // -1 = tie
  final Set<int> _voters = {};   // host: players whose vote has been counted
  Timer? _voteTimer;             // host: vote timeout
  bool _judged = false;          // 2 players: I gave my thumbs up/down

  // With exactly 2 players you can't vote for yourself, so voting is replaced
  // by judging the other player's drawing (thumbs up = 1 point for its artist)
  bool get _isJudgeMode => widget.players.length == 2;

  // ── Solo mode state ───────────────────────────────────────────────────────
  int _soloDrawCount = 0;
  bool _soloGameOver = false;

  @override List<Player> get gamePlayers => widget.players;

  // ── Init / Dispose ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final n = widget.players.length;
    _scores = List.filled(n, 0);
    _votes  = List.filled(n, 0);

    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };

    if (_net.isSolo) {
      _startSoloRound();
    } else if (_net.isHost) {
      _startRound();
    } else {
      _startSyncRequests();
    }
  }

  @override
  void dispose() {
    _drawTimer?.cancel();
    _voteTimer?.cancel();
    _syncReqTimer?.cancel();
    super.dispose();
  }

  /// Joiner: the host's opening FLU_START may be sent before this screen
  /// subscribes — ask for the current round state until a prompt arrives.
  void _startSyncRequests() {
    _syncReqTimer?.cancel();
    int tries = 0;
    _syncReqTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (!mounted || _prompt.isNotEmpty || tries >= 4) { t.cancel(); return; }
      tries++;
      _net.send('FLU_SYNC_REQ');
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _prompt.isEmpty) _net.send('FLU_SYNC_REQ');
    });
  }

  /// Host: full current round state for a joiner that missed it.
  Map<String, dynamic> _roundSyncPayload() {
    final drawings = <String, dynamic>{};
    if (_phase != _Phase.drawing) {
      for (final entry in _allDrawings.entries) {
        drawings['${entry.key}'] = _encodeStrokes(entry.value);
      }
      for (int i = 0; i < widget.players.length; i++) {
        drawings.putIfAbsent('$i', () => <List<double>>[]);
      }
    }
    return {
      'prompt':   _prompt,
      'round':    _currentRound,
      'phase':    _phase.index,
      'timeLeft': _timeLeft,
      'scores':   _scores,
      'votes':    _votes,
      'winner':   _roundWinnerIdx,
      'drawings': drawings,
    };
  }

  /// Joiner: apply FLU_SYNC. A duplicate/late sync for a round/phase we
  /// already have is ignored so local drawing/voting progress isn't reset.
  void _applyRoundSync(Map<String, dynamic> msg) {
    final prompt = msg['prompt'] as String? ?? '';
    final round  = msg['round'] as int? ?? 1;
    final phase  = _Phase.values[(msg['phase'] as int? ?? 0).clamp(0, _Phase.values.length - 1)];
    if (prompt.isEmpty) return;
    if (_prompt.isNotEmpty) {
      if (round < _currentRound) return;
      if (round == _currentRound && phase.index <= _phase.index) return;
    }
    final newRound = _prompt.isEmpty || round != _currentRound;

    final scoreList = (msg['scores'] as List).cast<int>();
    for (int i = 0; i < scoreList.length && i < _scores.length; i++) {
      _scores[i] = scoreList[i];
    }
    _prompt = prompt;
    _currentRound = round;
    if (newRound) {
      _myStrokes.clear();
      _currentStroke = null;
      _strokesSent = false;
      _allDrawings.clear();
      _myVote = -1;
      _votes = List.filled(widget.players.length, 0);
      _roundWinnerIdx = -1;
      _judged = false;
    }

    switch (phase) {
      case _Phase.drawing:
        _timeLeft = msg['timeLeft'] as int? ?? _kDrawSecs;
        setState(() { _phase = _Phase.drawing; });
        _startDrawTimer();
        turnChanged();
        break;
      case _Phase.revealing:
        _drawTimer?.cancel();
        // Too late to submit our drawing for this round — don't send it later
        _strokesSent = true;
        _applyReveal(Map<String, dynamic>.from(msg['drawings'] as Map));
        break;
      case _Phase.results:
        _drawTimer?.cancel();
        _strokesSent = true;
        _applyReveal(Map<String, dynamic>.from(msg['drawings'] as Map));
        final voteList = (msg['votes'] as List).cast<int>();
        for (int i = 0; i < voteList.length && i < _votes.length; i++) {
          _votes[i] = voteList[i];
        }
        _showResults(msg['winner'] as int? ?? -1);
        break;
      case _Phase.gameOver:
        _drawTimer?.cancel();
        setState(() { _phase = _Phase.gameOver; });
        break;
    }
  }

  // ── Prompt selection ──────────────────────────────────────────────────────
  String _pickPrompt() {
    final prompts = L.fluchtekenje.prompts;
    if (_usedPrompts.length >= prompts.length) _usedPrompts.clear();
    int idx;
    do {
      idx = _rng.nextInt(prompts.length);
    } while (_usedPrompts.contains(idx));
    _usedPrompts.add(idx);
    return prompts[idx];
  }

  // ── Round lifecycle ───────────────────────────────────────────────────────
  void _startRound() {
    _prompt = _pickPrompt();
    _myStrokes.clear();
    _currentStroke = null;
    _strokesSent = false;
    _allDrawings.clear();
    _myVote = -1;
    _votes = List.filled(widget.players.length, 0);
    _roundWinnerIdx = -1;
    _voters.clear();
    _voteTimer?.cancel();
    _judged = false;
    _timeLeft = _kDrawSecs;

    setState(() { _phase = _Phase.drawing; });

    // Broadcast prompt to all players
    _net.send('FLU_START', {'prompt': _prompt, 'round': _currentRound});

    _startDrawTimer();
    turnChanged();
  }

  void _startDrawTimer() {
    _drawTimer?.cancel();
    _drawTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() { _timeLeft--; });
      if (_timeLeft <= 3 && _timeLeft > 0) {
        HapticFeedback.lightImpact();
      }
      if (_timeLeft <= 0) {
        timer.cancel();
        if (_net.isSolo) {
          _onSoloTimeUp();
        } else {
          _onDrawingTimeUp();
        }
      }
    });
  }

  void _onDrawingTimeUp() {
    if (_phase != _Phase.drawing) return;
    HapticFeedback.mediumImpact();

    // Send strokes to host
    if (!_strokesSent) {
      _strokesSent = true;
      final data = _encodeStrokes(_myStrokes);
      _net.send('FLU_STROKES', {'strokes': data});
    }

    // Host: store own strokes and wait for others
    if (_net.isHost) {
      _allDrawings[_net.myIdx] = List.from(_myStrokes);
      // Check if all strokes received
      _checkAllStrokesReceived();
    }

    setState(() { _phase = _Phase.revealing; });
  }

  void _checkAllStrokesReceived() {
    if (!_net.isHost) return;
    // Wait for all players (give a 3-second grace period via delayed check)
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _phase == _Phase.results || _phase == _Phase.gameOver) return;
      _broadcastReveal();
    });
  }

  void _broadcastReveal() {
    if (!_net.isHost) return;
    // Encode all drawings
    final drawings = <String, dynamic>{};
    for (final entry in _allDrawings.entries) {
      drawings['${entry.key}'] = _encodeStrokes(entry.value);
    }
    // Fill missing players with empty drawings
    for (int i = 0; i < widget.players.length; i++) {
      drawings.putIfAbsent('$i', () => <List<double>>[]);
    }
    _net.send('FLU_REVEAL', {'drawings': drawings});

    // Start the vote timeout once (reveal may be broadcast twice)
    if (_voteTimer == null || !_voteTimer!.isActive) {
      _voteTimer = Timer(const Duration(seconds: _kVoteSecs), () {
        if (mounted) _resolveVotes();
      });
    }

    // Also apply locally
    _applyReveal(drawings);
  }

  void _applyReveal(Map<String, dynamic> drawings) {
    _allDrawings.clear();
    for (final entry in drawings.entries) {
      final idx = int.tryParse(entry.key);
      if (idx == null) continue;
      final raw = entry.value as List;
      _allDrawings[idx] = _decodeStrokes(raw);
    }
    setState(() { _phase = _Phase.revealing; });
  }

  void _onVoteReceived() {
    if (!_net.isHost) return;
    // Check if all players have voted (thumbs-down counts as a vote too)
    if (_voters.length >= widget.players.length) {
      _resolveVotes();
    }
  }

  void _resolveVotes() {
    // Only once per round (all votes in, or vote timeout)
    if (_phase != _Phase.revealing) return;
    _voteTimer?.cancel();

    int winnerIdx = -1;
    if (_isJudgeMode) {
      // Each thumbs-up gives that drawing's artist 1 point
      for (int i = 0; i < _votes.length; i++) {
        _scores[i] += _votes[i];
      }
      final scorers = [for (int i = 0; i < _votes.length; i++) if (_votes[i] > 0) i];
      if (scorers.length == 1) winnerIdx = scorers.first;
    } else {
      // Find player with most votes
      int maxVotes = 0;
      for (int i = 0; i < _votes.length; i++) {
        if (_votes[i] > maxVotes) {
          maxVotes = _votes[i];
          winnerIdx = i;
        }
      }
      // Check for tie
      final tiedCount = _votes.where((v) => v == maxVotes).length;
      if (tiedCount > 1 || maxVotes == 0) {
        winnerIdx = -1; // tie
      }

      if (winnerIdx >= 0) {
        _scores[winnerIdx]++;
      }
    }

    _roundWinnerIdx = winnerIdx;

    _net.send('FLU_RESULT', {
      'votes': _votes,
      'scores': _scores,
      'round': _currentRound,
      'winner': winnerIdx,
    });

    _showResults(winnerIdx);
  }

  void _showResults(int winnerIdx) {
    _roundWinnerIdx = winnerIdx;
    HapticFeedback.mediumImpact();
    setState(() { _phase = _Phase.results; });

    // Check if game is over
    final maxScore = _scores.reduce(math.max);
    if (maxScore >= _kWinScore) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() { _phase = _Phase.gameOver; });
        }
      });
    } else {
      // Start next round after delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _net.isHost) {
          _currentRound++;
          _startRound();
        }
      });
    }
  }

  // ── Solo mode ─────────────────────────────────────────────────────────────
  void _startSoloRound() {
    _prompt = _pickPrompt();
    _myStrokes.clear();
    _currentStroke = null;
    _timeLeft = _kDrawSecs;
    _soloGameOver = false;

    setState(() { _phase = _Phase.drawing; });
    _startDrawTimer();
  }

  void _onSoloDrawingDone() {
    if (_myStrokes.isEmpty) return; // must draw something first
    _drawTimer?.cancel();
    _soloDrawCount++;
    HapticFeedback.mediumImpact();

    // Immediately start next prompt
    _startSoloRound();
  }

  void _onSoloTimeUp() {
    setState(() {
      _soloGameOver = true;
      _phase = _Phase.gameOver;
      _scores[0] = _soloDrawCount;
    });
  }

  // ── Stroke encoding/decoding ──────────────────────────────────────────────
  List<List<double>> _encodeStrokes(List<List<Offset>> strokes) {
    final result = <List<double>>[];
    for (final stroke in strokes) {
      final points = <double>[];
      for (final p in stroke) {
        points.add((p.dx * 10000).roundToDouble() / 10000);
        points.add((p.dy * 10000).roundToDouble() / 10000);
      }
      result.add(points);
    }
    return result;
  }

  List<List<Offset>> _decodeStrokes(List<dynamic> raw) {
    final result = <List<Offset>>[];
    for (final strokeRaw in raw) {
      final points = <Offset>[];
      final vals = (strokeRaw as List).cast<num>();
      for (int i = 0; i + 1 < vals.length; i += 2) {
        points.add(Offset(vals[i].toDouble(), vals[i + 1].toDouble()));
      }
      result.add(points);
    }
    return result;
  }

  // ── Drawing input ─────────────────────────────────────────────────────────
  void _onPanStart(DragStartDetails details, Size canvasSize) {
    if (_phase != _Phase.drawing) return;
    final p = Offset(
      (details.localPosition.dx / canvasSize.width).clamp(0.0, 1.0),
      (details.localPosition.dy / canvasSize.height).clamp(0.0, 1.0),
    );
    _currentStroke = [p];
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (_phase != _Phase.drawing || _currentStroke == null) return;
    final p = Offset(
      (details.localPosition.dx / canvasSize.width).clamp(0.0, 1.0),
      (details.localPosition.dy / canvasSize.height).clamp(0.0, 1.0),
    );
    _currentStroke!.add(p);
    setState(() {});
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke == null) return;
    if (_currentStroke!.length > 1) {
      _myStrokes.add(List.from(_currentStroke!));
    }
    _currentStroke = null;
    setState(() {});
  }

  void _clearCanvas() {
    HapticFeedback.lightImpact();
    setState(() {
      _myStrokes.clear();
      _currentStroke = null;
    });
  }

  // ── Voting ────────────────────────────────────────────────────────────────
  void _castVote(int playerIdx) {
    if (_myVote >= 0) return; // already voted
    final myIdx = _net.myIdx.clamp(0, widget.players.length - 1);
    if (playerIdx == myIdx) {
      // Show snackbar: can't vote for own
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.fluchtekenje.cantVoteOwn),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 2),
      ));
      return;
    }

    HapticFeedback.mediumImpact();
    SoundPlayer.i.uiClick();
    _myVote = playerIdx;

    _net.send('FLU_VOTE', {'vote': playerIdx});

    // Host: count own vote
    if (_net.isHost) {
      _votes[playerIdx]++;
      _voters.add(_net.myIdx);
      _onVoteReceived();
    }

    setState(() {});
  }

  // 2 players: thumbs up/down on the other player's drawing
  void _judgeDrawing(bool drewIt) {
    if (_judged || _phase != _Phase.revealing) return;
    final otherIdx = 1 - _net.myIdx.clamp(0, 1);
    HapticFeedback.mediumImpact();
    SoundPlayer.i.uiClick();
    _judged = true;
    if (drewIt) _myVote = otherIdx;
    final vote = drewIt ? otherIdx : -1; // -1 = thumbs down

    _net.send('FLU_VOTE', {'vote': vote});

    // Host: count own judgement
    if (_net.isHost) {
      if (vote >= 0) _votes[vote]++;
      _voters.add(_net.myIdx);
      _onVoteReceived();
    }

    setState(() {});
  }

  // ── Network messages ────────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    final type = msg['type'] as String? ?? '';
    switch (type) {
      case 'FLU_START':
        if (!_net.isHost) {
          _prompt = msg['prompt'] as String? ?? '';
          _currentRound = msg['round'] as int? ?? 1;
          _myStrokes.clear();
          _currentStroke = null;
          _strokesSent = false;
          _allDrawings.clear();
          _myVote = -1;
          _votes = List.filled(widget.players.length, 0);
          _roundWinnerIdx = -1;
          _judged = false;
          _timeLeft = _kDrawSecs;
          setState(() { _phase = _Phase.drawing; });
          _startDrawTimer();
          turnChanged();
        }
        break;

      case 'FLU_SYNC_REQ':
        // Joiner missed FLU_START (or reconnected) — resend current round state
        if (_net.isHost && !_net.isSolo && _prompt.isNotEmpty) {
          _net.sendTo(fromIdx, 'FLU_SYNC', _roundSyncPayload());
        }
        break;

      case 'FLU_SYNC':
        if (!_net.isHost) _applyRoundSync(msg);
        break;

      case 'FLU_STROKES':
        // Not once results are shown: a very late drawing must not restart the
        // reveal / voting (the host is already 'revealing' during the grace period)
        if (_net.isHost &&
            (_phase == _Phase.drawing || _phase == _Phase.revealing)) {
          final raw = msg['strokes'] as List;
          _allDrawings[fromIdx] = _decodeStrokes(raw);
          // Check if we can reveal
          if (_allDrawings.length >= widget.players.length) {
            _broadcastReveal();
          }
        }
        break;

      case 'FLU_REVEAL':
        if (!_net.isHost) {
          final drawings = msg['drawings'] as Map<String, dynamic>;
          _applyReveal(drawings);
        }
        break;

      case 'FLU_VOTE':
        if (_net.isHost && _phase == _Phase.revealing && !_voters.contains(fromIdx)) {
          final vote = msg['vote'] as int;
          if (vote >= 0 && vote < _votes.length) {
            _votes[vote]++;
          }
          _voters.add(fromIdx);
          _onVoteReceived();
        }
        break;

      case 'FLU_RESULT':
        if (!_net.isHost) {
          final voteList = (msg['votes'] as List).cast<int>();
          final scoreList = (msg['scores'] as List).cast<int>();
          final winnerIdx = msg['winner'] as int? ?? -1;
          for (int i = 0; i < voteList.length && i < _votes.length; i++) {
            _votes[i] = voteList[i];
          }
          for (int i = 0; i < scoreList.length && i < _scores.length; i++) {
            _scores[i] = scoreList[i];
          }
          _currentRound = msg['round'] as int? ?? _currentRound;
          _showResults(winnerIdx);
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
    _scores = List.filled(n, 0);
    _votes  = List.filled(n, 0);
    _myStrokes.clear();
    _currentStroke = null;
    _strokesSent = false;
    _allDrawings.clear();
    _myVote = -1;
    _roundWinnerIdx = -1;
    _voters.clear();
    _voteTimer?.cancel();
    _judged = false;
    _timeLeft = _kDrawSecs;
    _phase = _Phase.drawing;
    _usedPrompts.clear();
    _soloDrawCount = 0;
    _soloGameOver = false;
    _drawTimer?.cancel();
  }

  void _reset() {
    resetConfetti();
    resetStats();
    setState(_resetLocal);
    if (_net.isSolo) {
      _startSoloRound();
    } else if (_net.isHost) {
      _startRound();
    }
  }

  void _showReconnect() {
    showReconnectDialog(
      onMsg: _onMsg,
      onReconnected: () {
        if (_net.isHost) {
          sendGameSync();
        } else {
          _net.send('FLU_SYNC_REQ');
        }
      },
    );
  }

  // ── Winner calculation ────────────────────────────────────────────────────
  int get _winnerIdx {
    int bestScore = -1;
    int bestIdx = 0;
    for (int i = 0; i < _scores.length; i++) {
      if (_scores[i] > bestScore) {
        bestScore = _scores[i];
        bestIdx = i;
      }
    }
    final tiedCount = _scores.where((s) => s == bestScore).length;
    return tiedCount > 1 ? -1 : bestIdx;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Solo mode
    if (_net.isSolo) return _buildSolo();

    // Status bar text
    String? statusText;
    switch (_phase) {
      case _Phase.drawing:
        statusText = '${L.fluchtekenje.drawing} "$_prompt" — ${L.fluchtekenje.timeLeft.fmt({'n': '$_timeLeft'})}';
        break;
      case _Phase.revealing:
        if (_isJudgeMode) {
          final other = widget.players[1 - _net.myIdx.clamp(0, 1)];
          statusText = _judged
              ? L.fluchtekenje.judgeWaiting
              : L.fluchtekenje.judgeNow.fmt({'player': other.name, 'prompt': _prompt});
        } else {
          statusText = _myVote >= 0
              ? L.fluchtekenje.votedFor.fmt({'player': widget.players[_myVote].name})
              : L.fluchtekenje.voteNow;
        }
        break;
      case _Phase.results:
        if (_isJudgeMode) {
          final scorers = _votes.where((v) => v > 0).length;
          statusText = scorers >= 2
              ? L.fluchtekenje.judgeBoth
              : _roundWinnerIdx >= 0
                  ? L.fluchtekenje.judgePoint.fmt({'player': widget.players[_roundWinnerIdx].name})
                  : L.fluchtekenje.judgeNone;
        } else {
          statusText = _roundWinnerIdx >= 0
              ? L.fluchtekenje.roundWinner.fmt({'player': widget.players[_roundWinnerIdx].name})
              : L.fluchtekenje.noVotes;
        }
        break;
      case _Phase.gameOver:
        statusText = null;
        break;
    }

    return GameScaffold(
      key: scaffoldKey,
      title: L.fluchtekenje.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.fluchtekenje.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: -1,
          scores: _scores,
        ),
        GameStatusBar(
          text: statusText,
          textColor: _phase == _Phase.drawing && _timeLeft <= 3
              ? Colors.red : null,
        ),

        Expanded(child: _buildPhaseContent()),

        if (_phase == _Phase.gameOver) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winnerIdx,
            onFirstRender: () {
              fireConfettiOnce(_winnerIdx);
              recordResult('fluchtekenje', _winnerIdx);
              if (_net.isHost) SessionState().advanceGame();
            },
            scores: widget.players.asMap().entries.map((e) =>
              (label: e.value.name, value: '${_scores[e.key]}'),
            ).toList(),
          ),
          GameOverActions(players: widget.players, onReset: _reset),
        ] else const SizedBox(height: 8),
      ]),
    );
  }

  // ── Phase content ─────────────────────────────────────────────────────────
  Widget _buildPhaseContent() {
    switch (_phase) {
      case _Phase.drawing:
        return _buildDrawingPhase();
      case _Phase.revealing:
        return _buildRevealPhase();
      case _Phase.results:
        return _buildResultsPhase();
      case _Phase.gameOver:
        return const SizedBox.shrink();
    }
  }

  // ── Drawing phase ─────────────────────────────────────────────────────────
  Widget _buildDrawingPhase() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        // Countdown bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _timeLeft / _kDrawSecs,
            backgroundColor: kBg2,
            color: _timeLeft <= 3 ? Colors.red : kPurple,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(builder: (_, constraints) {
                final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onPanStart: (d) => _onPanStart(d, canvasSize),
                  onPanUpdate: (d) => _onPanUpdate(d, canvasSize),
                  onPanEnd: _onPanEnd,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorder, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CustomPaint(
                        size: canvasSize,
                        painter: _StrokePainter(
                          strokes: _myStrokes,
                          currentStroke: _currentStroke,
                          color: widget.players[_net.myIdx.clamp(0, widget.players.length - 1)].color,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Clear button
        TextButton.icon(
          onPressed: _clearCanvas,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(L.fluchtekenje.clearCanvas),
          style: TextButton.styleFrom(foregroundColor: kMuted),
        ),
      ]),
    );
  }

  // ── Reveal / voting phase ─────────────────────────────────────────────────
  Widget _buildRevealPhase() {
    if (_allDrawings.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: kPurple),
          const SizedBox(height: 12),
          Text(L.fluchtekenje.waitingDrawings,
            style: const TextStyle(color: kMuted, fontSize: 14)),
        ]),
      );
    }

    if (_isJudgeMode) {
      final otherIdx = 1 - _net.myIdx.clamp(0, 1);
      return Column(children: [
        Expanded(child: _buildDrawingsGrid(votingEnabled: false)),
        // Thumbs up/down — only once the other drawing has arrived
        if (!_judged && _allDrawings.containsKey(otherIdx))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ElevatedButton.icon(
                onPressed: () => _judgeDrawing(true),
                icon: const Icon(Icons.thumb_up, size: 20),
                label: Text(L.fluchtekenje.judgeYes),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => _judgeDrawing(false),
                icon: const Icon(Icons.thumb_down, size: 20),
                label: Text(L.fluchtekenje.judgeNo),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kMuted,
                  side: const BorderSide(color: kMuted),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              ),
            ]),
          ),
      ]);
    }

    return _buildDrawingsGrid(votingEnabled: true);
  }

  // ── Results phase ─────────────────────────────────────────────────────────
  Widget _buildResultsPhase() {
    return _buildDrawingsGrid(votingEnabled: false, showVotes: true);
  }

  // ── Drawings grid ─────────────────────────────────────────────────────────
  Widget _buildDrawingsGrid({required bool votingEnabled, bool showVotes = false}) {
    final playerCount = widget.players.length;
    final cols = playerCount <= 2 ? playerCount : 2;
    final rows = (playerCount / cols).ceil();
    final myIdx = _net.myIdx.clamp(0, playerCount - 1);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: List.generate(rows, (row) {
          return Expanded(
            child: Row(
              children: List.generate(cols, (col) {
                final idx = row * cols + col;
                if (idx >= playerCount) return const Expanded(child: SizedBox.shrink());
                final player = widget.players[idx];
                final strokes = _allDrawings[idx] ?? [];
                final isVoted = _myVote == idx;
                final isOwn = idx == myIdx;

                return Expanded(
                  child: GestureDetector(
                    onTap: votingEnabled ? () => _castVote(idx) : null,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isVoted ? player.color : kBorder,
                          width: isVoted ? 3 : 1,
                        ),
                        boxShadow: isVoted ? [
                          BoxShadow(color: player.color.withValues(alpha: 0.3), blurRadius: 8),
                        ] : null,
                      ),
                      child: Column(children: [
                        // Drawing area — keep 1:1 aspect ratio to match drawing canvas
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                                child: LayoutBuilder(builder: (_, constraints) {
                                  return CustomPaint(
                                    size: Size(constraints.maxWidth, constraints.maxHeight),
                                    painter: _StrokePainter(
                                      strokes: strokes,
                                      currentStroke: null,
                                      color: player.color,
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                        // Player name + votes
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: player.color.withValues(alpha: 0.15),
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(width: 8, height: 8,
                                decoration: BoxDecoration(color: player.color, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  player.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isOwn ? kMuted : kText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (showVotes && idx < _votes.length) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${_votes[idx]}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: _roundWinnerIdx == idx || (_isJudgeMode && _votes[idx] > 0)
                                        ? kGreen : kMuted,
                                  ),
                                ),
                                const Text(' \u2B50',
                                  style: TextStyle(fontSize: 10,
                                    fontFamilyFallback: ['NotoColorEmoji'])),
                              ],
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  // ── Solo mode build ───────────────────────────────────────────────────────
  Widget _buildSolo() {
    String? statusText;
    if (!_soloGameOver) {
      statusText = '"$_prompt" — ${L.fluchtekenje.timeLeft.fmt({'n': '$_timeLeft'})}';
    }

    return GameScaffold(
      key: scaffoldKey,
      title: L.fluchtekenje.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.fluchtekenje.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: 0,
          scores: [_soloDrawCount],
        ),
        GameStatusBar(
          text: statusText,
          textColor: _timeLeft <= 3 ? Colors.red : null,
        ),

        if (!_soloGameOver)
          Expanded(child: _buildSoloDrawing())
        else
          const Expanded(child: SizedBox.shrink()),

        if (_soloGameOver) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: 0,
            onFirstRender: () {
              fireConfettiOnce(0);
              recordResult('fluchtekenje', 0);
            },
            scores: [
              (label: widget.players[0].name,
               value: L.fluchtekenje.soloComplete.fmt({'n': '$_soloDrawCount'})),
            ],
          ),
          GameOverActions(players: widget.players, onReset: _reset),
        ] else const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildSoloDrawing() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _timeLeft / _kDrawSecs,
            backgroundColor: kBg2,
            color: _timeLeft <= 3 ? Colors.red : kPurple,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(builder: (_, constraints) {
                final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onPanStart: (d) => _onPanStart(d, canvasSize),
                  onPanUpdate: (d) => _onPanUpdate(d, canvasSize),
                  onPanEnd: _onPanEnd,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorder, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CustomPaint(
                        size: canvasSize,
                        painter: _StrokePainter(
                          strokes: _myStrokes,
                          currentStroke: _currentStroke,
                          color: widget.players[0].color,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(
            onPressed: _clearCanvas,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(L.fluchtekenje.clearCanvas),
            style: TextButton.styleFrom(foregroundColor: kMuted),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _myStrokes.isEmpty ? null : _onSoloDrawingDone,
            icon: const Icon(Icons.check, size: 18),
            label: Text(L.fluchtekenje.drawing),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: Colors.black,
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Stroke painter ──────────────────────────────────────────────────────────
class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset>? currentStroke;
  final Color color;

  const _StrokePainter({
    required this.strokes,
    required this.currentStroke,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      _drawStroke(canvas, size, stroke, paint);
    }
    if (currentStroke != null && currentStroke!.isNotEmpty) {
      _drawStroke(canvas, size, currentStroke!, paint);
    }
  }

  void _drawStroke(Canvas canvas, Size size, List<Offset> points, Paint paint) {
    if (points.length < 2) {
      // Single dot
      if (points.length == 1) {
        canvas.drawCircle(
          Offset(points[0].dx * size.width, points[0].dy * size.height),
          2, paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
      }
      return;
    }

    final path = ui.Path();
    path.moveTo(points[0].dx * size.width, points[0].dy * size.height);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx * size.width, points[i].dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}
