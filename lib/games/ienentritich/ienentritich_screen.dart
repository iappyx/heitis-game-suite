import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../core/sound_player.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/session.dart';
import 'ienentritich_ai.dart';

// ── Card model ───────────────────────────────────────────────────────────────

class _Card {
  final int suit; // 0=spades, 1=hearts, 2=diamonds, 3=clubs
  final int rank; // 1=Ace, 2-10, 11=J, 12=Q, 13=K
  bool faceUp;
  _Card({required this.suit, required this.rank, this.faceUp = false});

  Map<String, int> toJson() => {'suit': suit, 'rank': rank};

  factory _Card.fromJson(Map<String, dynamic> j) =>
      _Card(suit: j['suit'] as int, rank: j['rank'] as int);

  @override
  bool operator ==(Object other) =>
      other is _Card && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => suit * 100 + rank;
}

String _rankStr(int r) => switch (r) {
  1 => 'A', 11 => 'J', 12 => 'Q', 13 => 'K', _ => '$r',
};

String _suitStr(int s) => ['\u2660', '\u2665', '\u2666', '\u2663'][s];

bool _isRed(int s) => s == 1 || s == 2;

int _cardValue(int rank) => rank == 1 ? 11 : rank >= 10 ? 10 : rank;

double _calcScore(List<_Card> hand) {
  if (hand.length != 3) return 0;
  // Check 3 of a kind
  if (hand[0].rank == hand[1].rank && hand[1].rank == hand[2].rank) return 30.5;
  double best = 0;
  for (int s = 0; s < 4; s++) {
    double sum = 0;
    for (final c in hand) {
      if (c.suit == s) sum += _cardValue(c.rank);
    }
    if (sum > best) best = sum;
  }
  return best;
}

List<Map<String, int>> _handToJson(List<_Card> h) => h.map((c) => c.toJson()).toList();
List<_Card> _handFromJson(List<dynamic> j) =>
    j.map((e) => _Card.fromJson(Map<String, dynamic>.from(e as Map))).toList();

// ── Phase enum ───────────────────────────────────────────────────────────────

enum _Phase { dealing, playing, knocked, roundOver, gameOver }

// ── Screen ───────────────────────────────────────────────────────────────────

class IenEnTritichScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const IenEnTritichScreen({
    super.key,
    required this.players,
    required this.firstPlayer,
    this.extra,
  });
  @override State<IenEnTritichScreen> createState() => _IenEnTritichState();
}

class _IenEnTritichState extends State<IenEnTritichScreen> with GameMixin {
  final _net = Network();
  final _rng = math.Random();

  // ── Game state ─────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.dealing;
  List<List<_Card>> _hands = [];       // per player, 3 cards each
  List<_Card> _center = [];            // 3 face-up center cards
  List<int> _coins = [];                // per player, start at 3 (gulden cents)
  int _pot = 0;                        // coins in the pot this round
  int? _roundWinner;                   // who won the pot this round
  int _turn = 0;                       // whose turn (0-based)
  int? _knocker;                       // who knocked (null if nobody)
  int _turnsAfterKnock = 0;            // how many turns happened after knock
  int _dealer = 0;                     // rotates each round
  Set<int> _eliminated = {};           // eliminated player indices
  int? _selectedHandIdx;               // selected card in hand
  int? _selectedCenterIdx;             // selected card in center
  List<double>? _roundScores;          // shown at round end
  List<int>? _roundLosers;             // who lost this round
  int? _winner;                        // final game winner
  String? _statusMsg;                  // transient status (e.g. "X knocked!")
  Timer? _statusTimer;

  // AI
  List<IenEnTritichAI> _ais = [];
  int _cpuStartIdx = 999; // index where AI players start (999 = no AI)
  int get _playerCount => widget.players.length;
  int get _myIdx => _net.myIdx.clamp(0, _playerCount - 1);
  bool get _isMyTurn => _phase == _Phase.playing || _phase == _Phase.knocked
      ? _turn == _myIdx
      : false;

  @override List<Player> get gamePlayers => widget.players;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };

    // Init coins (3 guilder cents each)
    _coins = List.filled(_playerCount, 3);
    _dealer = widget.firstPlayer.clamp(0, _playerCount - 1);

    // Setup AI opponents (solo mode: all non-human, multiplayer: cpuCount from extra)
    final cpuCount = _net.isSolo
        ? _playerCount - 1
        : (widget.extra?['cpuCount'] as int?) ?? 0;
    if (cpuCount > 0 && _net.isHost) {
      final diff = SoloDifficulty.values[(widget.extra?['difficulty'] as int?) ?? 1];
      // AI players are the last cpuCount indices in the players list
      final firstAiIdx = _playerCount - cpuCount;
      _ais = List.generate(cpuCount, (i) {
        final ai = IenEnTritichAI(diff);
        ai.playerIdx = firstAiIdx + i;
        return ai;
      });
    }
    _cpuStartIdx = _playerCount - cpuCount;

    // Host starts the first round
    if (_net.isHost) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _startRound();
      });
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    for (final ai in _ais) {
      ai.cancel();
    }
    super.dispose();
  }

  // ── Message handling ───────────────────────────────────────────────────────

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    final type = msg['type'] as String;
    switch (type) {
      case 'IEN_DEAL':
        _handleDeal(msg);
      case 'IEN_SWAP1':
        if (_net.isHost) _handleSwap1(msg);
      case 'IEN_SWAP3':
        if (_net.isHost) _handleSwap3(msg);
      case 'IEN_KNOCK':
        if (_net.isHost) _handleKnock(msg);
      case 'IEN_PASS':
        if (_net.isHost) _handlePass(msg);
      case 'IEN_STATE':
        _handleState(msg);
      case 'IEN_ROUND_OVER':
        _handleRoundOver(msg);
      case 'IEN_GAME_OVER':
        _handleGameOver(msg);
      case 'IEN_STATUS':
        _showStatus(msg['text'] as String);
      case 'GAME_RESET':
        GameOverActions.handleMessage(msg, _resetGame);
    }
  }

  // ── Round lifecycle (host only) ────────────────────────────────────────────

  void _startRound() {
    // Build and shuffle deck
    final deck = <_Card>[];
    for (int s = 0; s < 4; s++) {
      for (int r = 1; r <= 13; r++) {
        deck.add(_Card(suit: s, rank: r));
      }
    }
    deck.shuffle(_rng);

    // Deal 3 cards to each active player
    _hands = List.generate(_playerCount, (_) => []);
    int di = 0;
    for (int i = 0; i < _playerCount; i++) {
      if (_eliminated.contains(i)) {
        _hands[i] = [];
      } else {
        _hands[i] = [deck[di++], deck[di++], deck[di++]];
      }
    }
    // 3 center cards
    _center = [deck[di++], deck[di++], deck[di++]];

    _knocker = null;
    _turnsAfterKnock = 0;
    _selectedHandIdx = null;
    _selectedCenterIdx = null;
    _roundScores = null;
    _roundLosers = null;
    _roundWinner = null;

    // Each active player puts 1 coin in the pot
    _pot = 0;
    for (int i = 0; i < _playerCount; i++) {
      // A player without coins can't ante (they are eliminated in _endRound)
      if (!_eliminated.contains(i) && _coins[i] > 0) {
        _coins[i]--;
        _pot++;
      }
    }

    // Reset AI turn counters
    for (final ai in _ais) {
      ai.resetRound();
    }

    // First turn: left of dealer, skip eliminated
    _turn = _nextActivePlayer(_dealer);

    _phase = _Phase.playing;

    // Broadcast deal
    _broadcastDeal();
    _broadcastState();

    // If first turn is AI, trigger it
    _triggerAiIfNeeded();
  }

  void _broadcastDeal() {
    final payload = {
      'hands': _hands.map(_handToJson).toList(),
      'center': _handToJson(_center),
      'dealer': _dealer,
      'coins': _coins,
      'pot': _pot,
      'eliminated': _eliminated.toList(),
    };
    _net.send('IEN_DEAL', payload);
    // Apply locally for host
    setState(() {});
  }

  void _broadcastState() {
    final payload = {
      'hands': _hands.map(_handToJson).toList(),
      'center': _handToJson(_center),
      'turn': _turn,
      'knocker': _knocker,
      'coins': _coins,
      'pot': _pot,
      'phase': _phase.index,
      'eliminated': _eliminated.toList(),
    };
    _net.send('IEN_STATE', payload);
    setState(() {});
  }

  void _broadcastStatus(String text) {
    _net.send('IEN_STATUS', {'text': text});
    _showStatus(text);
  }

  // ── Handle incoming (host processes actions) ───────────────────────────────

  void _handleDeal(Map<String, dynamic> msg) {
    setState(() {
      _hands = (msg['hands'] as List)
          .map((h) => _handFromJson(h as List))
          .toList();
      _center = _handFromJson(msg['center'] as List);
      _dealer = msg['dealer'] as int;
      _coins = List<int>.from(msg['coins'] as List);
      _pot = msg['pot'] as int;
      _eliminated = Set<int>.from(msg['eliminated'] as List);
      _knocker = null;
      _turnsAfterKnock = 0;
      _selectedHandIdx = null;
      _selectedCenterIdx = null;
      _roundScores = null;
      _roundLosers = null;
      _roundWinner = null;
      _phase = _Phase.playing;
    });
  }

  void _handleState(Map<String, dynamic> msg) {
    final turn = msg['turn'] as int;
    if (turn < 0 || turn >= widget.players.length) return;
    final phaseIdx = msg['phase'] as int;
    if (phaseIdx < 0 || phaseIdx >= _Phase.values.length) return;
    final wasMyTurn = _isMyTurn;
    setState(() {
      _hands = (msg['hands'] as List)
          .map((h) => _handFromJson(h as List))
          .toList();
      _center = _handFromJson(msg['center'] as List);
      _turn = turn;
      _knocker = msg['knocker'] as int?;
      _coins = List<int>.from(msg['coins'] as List);
      _pot = msg['pot'] as int;
      _phase = _Phase.values[phaseIdx];
      _eliminated = Set<int>.from(msg['eliminated'] as List);
      _selectedHandIdx = null;
      _selectedCenterIdx = null;
    });
    if (!wasMyTurn && _isMyTurn) turnChanged();
  }

  void _handleSwap1(Map<String, dynamic> msg) {
    final idx = msg['idx'] as int? ?? msg['fromIdx'] as int? ?? 0;
    final handIdx = msg['handIdx'] as int;
    final centerIdx = msg['centerIdx'] as int;

    if (idx < 0 || idx >= _hands.length) return;
    if (idx != _turn) return; // not their turn
    if (_eliminated.contains(idx)) return;
    if (handIdx < 0 || handIdx >= _hands[idx].length) return;
    if (centerIdx < 0 || centerIdx >= _center.length) return;

    // Perform swap
    final tmp = _hands[idx][handIdx];
    _hands[idx][handIdx] = _center[centerIdx];
    _center[centerIdx] = tmp;

    SoundPlayer.i.uiClick();
    HapticFeedback.lightImpact();

    // Check for 31
    if (_calcScore(_hands[idx]) >= 31) {
      _broadcastStatus(L.ienentritich.thirtyOne);
      SoundPlayer.i.uiConfirm();
      _endRound();
      return;
    }

    _advanceTurn();
  }

  void _handleSwap3(Map<String, dynamic> msg) {
    final idx = msg['idx'] as int? ?? msg['fromIdx'] as int? ?? 0;
    if (idx < 0 || idx >= _hands.length) return;
    if (idx != _turn) return;
    if (_eliminated.contains(idx)) return;

    // Swap all 3
    final oldHand = List<_Card>.from(_hands[idx]);
    _hands[idx] = List<_Card>.from(_center);
    _center = oldHand;

    SoundPlayer.i.uiClick();
    HapticFeedback.lightImpact();

    // Check for 31
    if (_calcScore(_hands[idx]) >= 31) {
      _broadcastStatus(L.ienentritich.thirtyOne);
      SoundPlayer.i.uiConfirm();
      _endRound();
      return;
    }

    _advanceTurn();
  }

  void _handleKnock(Map<String, dynamic> msg) {
    final idx = msg['idx'] as int? ?? msg['fromIdx'] as int? ?? 0;
    if (idx < 0 || idx >= widget.players.length) return;
    if (idx != _turn) return;
    if (_eliminated.contains(idx)) return;
    if (_knocker != null) return; // already knocked

    _knocker = idx;
    _phase = _Phase.knocked;
    _turnsAfterKnock = 0;

    SoundPlayer.i.uiSelect();
    HapticFeedback.mediumImpact();

    final name = widget.players[idx].name;
    _broadcastStatus(L.ienentritich.knocked.fmt({'player': name}));

    // Advance turn manually — don't use _advanceTurn() which increments
    // the after-knock counter. The knock itself is NOT a "turn after knock".
    _turn = _nextActivePlayer(_turn);
    _selectedHandIdx = null;
    _selectedCenterIdx = null;
    _broadcastState();
    _triggerAiIfNeeded();
  }

  void _handlePass(Map<String, dynamic> msg) {
    final idx = msg['idx'] as int? ?? msg['fromIdx'] as int? ?? 0;
    if (idx < 0 || idx >= widget.players.length) return;
    if (idx != _turn) return;
    if (_eliminated.contains(idx)) return;

    SoundPlayer.i.uiClick();
    _advanceTurn();
  }

  void _advanceTurn() {
    if (_phase == _Phase.knocked) {
      _turnsAfterKnock++;
      // Count active players (not including knocker)
      final activePlayers = List.generate(_playerCount, (i) => i)
          .where((i) => !_eliminated.contains(i) && i != _knocker)
          .length;
      if (_turnsAfterKnock >= activePlayers) {
        // Everyone had their last turn
        _endRound();
        return;
      }
    }

    _turn = _nextActivePlayer(_turn);
    _selectedHandIdx = null;
    _selectedCenterIdx = null;

    _broadcastState();
    _triggerAiIfNeeded();
  }

  int _nextActivePlayer(int from) {
    int next = (from + 1) % _playerCount;
    int attempts = 0;
    while (_eliminated.contains(next) && attempts < _playerCount) {
      next = (next + 1) % _playerCount;
      attempts++;
    }
    return next;
  }

  void _endRound() {
    // Calculate scores
    final scores = List<double>.generate(_playerCount, (i) {
      if (_eliminated.contains(i) || _hands[i].isEmpty) return -1;
      return _calcScore(_hands[i]);
    });

    // Find highest score (round winner gets the pot)
    double highest = -1;
    int winnerIdx = -1;
    for (int i = 0; i < _playerCount; i++) {
      if (!_eliminated.contains(i) && scores[i] > highest) {
        highest = scores[i];
        winnerIdx = i;
      }
    }

    // Award pot to winner
    if (winnerIdx >= 0) {
      _coins[winnerIdx] += _pot;
      _roundWinner = winnerIdx;
    }
    _pot = 0;

    // Find lowest score — loser(s) lose a coin
    double lowest = double.infinity;
    for (int i = 0; i < _playerCount; i++) {
      if (!_eliminated.contains(i) && scores[i] >= 0 && scores[i] < lowest) {
        lowest = scores[i];
      }
    }

    // All tied for lowest lose a coin
    final losers = <int>[];
    for (int i = 0; i < _playerCount; i++) {
      if (!_eliminated.contains(i) && scores[i] == lowest) {
        losers.add(i);
      }
    }

    // Apply coin loss
    for (final i in losers) {
      _coins[i]--;
      if (_coins[i] <= 0) {
        _coins[i] = 0;
        _eliminated.add(i);
      }
    }

    // No coins left = eliminated (also players who anted their last coin
    // and did not win the pot back)
    for (int i = 0; i < _playerCount; i++) {
      if (!_eliminated.contains(i) && _coins[i] <= 0) {
        _coins[i] = 0;
        _eliminated.add(i);
      }
    }

    _roundScores = scores;
    _roundLosers = losers;
    _phase = _Phase.roundOver;

    // Broadcast round over
    final payload = {
      'hands': _hands.map(_handToJson).toList(),
      'center': _handToJson(_center),
      'scores': scores,
      'losers': losers,
      'coins': _coins,
      'pot': _pot,
      'roundWinner': winnerIdx,
      'eliminated': _eliminated.toList(),
    };
    _net.send('IEN_ROUND_OVER', payload);

    if (winnerIdx >= 0) {
      _broadcastStatus(L.ienentritich.roundWinner.fmt({'player': widget.players[winnerIdx].name}));
    }

    SoundPlayer.i.boppeslachRoundDone();
    HapticFeedback.heavyImpact();

    setState(() {});

    // Check if game is over
    final activePlayers = List.generate(_playerCount, (i) => i)
        .where((i) => !_eliminated.contains(i))
        .toList();

    if (activePlayers.length <= 1) {
      final winner = activePlayers.isNotEmpty ? activePlayers.first : _dealer;
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _finishGame(winner);
      });
    } else if (_ais.isNotEmpty && !activePlayers.any((i) => i < _cpuStartIdx)) {
      // All humans are eliminated — auto-resolve: the CPU with most coins wins
      final cpuWinner = activePlayers.reduce((a, b) => _coins[a] >= _coins[b] ? a : b);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _finishGame(cpuWinner);
      });
    } else {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _dealer = _nextActivePlayer(_dealer);
          _startRound();
        }
      });
    }
  }

  void _finishGame(int winnerIdx) {
    _winner = winnerIdx;
    _phase = _Phase.gameOver;
    final payload = {'winner': winnerIdx};
    _net.send('IEN_GAME_OVER', payload);
    fireConfettiOnce(winnerIdx);
    recordResult('ienentritich', winnerIdx);
    if (_net.isHost) SessionState().advanceGame();
    setState(() {});
  }

  void _handleRoundOver(Map<String, dynamic> msg) {
    setState(() {
      _hands = (msg['hands'] as List)
          .map((h) => _handFromJson(h as List))
          .toList();
      _center = _handFromJson(msg['center'] as List);
      _roundScores = List<double>.from(msg['scores'] as List);
      _roundLosers = List<int>.from(msg['losers'] as List);
      _coins = List<int>.from(msg['coins'] as List);
      _pot = msg['pot'] as int;
      _roundWinner = msg['roundWinner'] as int?;
      _eliminated = Set<int>.from(msg['eliminated'] as List);
      _phase = _Phase.roundOver;
    });
    SoundPlayer.i.boppeslachRoundDone();
    HapticFeedback.heavyImpact();
  }

  void _handleGameOver(Map<String, dynamic> msg) {
    final winnerIdx = msg['winner'] as int;
    setState(() {
      _winner = winnerIdx;
      _phase = _Phase.gameOver;
    });
    fireConfettiOnce(winnerIdx);
    recordResult('ienentritich', winnerIdx);
  }

  void _showStatus(String text) {
    setState(() => _statusMsg = text);
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _statusMsg = null);
    });
  }

  void _resetGame() {
    for (final ai in _ais) ai.cancel();
    setState(() {
      _coins = List.filled(_playerCount, 3);
      _pot = 0;
      _eliminated = {};
      _winner = null;
      _roundWinner = null;
      _phase = _Phase.dealing;
      _roundScores = null;
      _roundLosers = null;
      _selectedHandIdx = null;
      _selectedCenterIdx = null;
      _statusMsg = null;
      _knocker = null;
    });
    resetConfetti();
    resetStats();
    if (_net.isHost) {
      _dealer = widget.firstPlayer.clamp(0, _playerCount - 1);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _startRound();
      });
    }
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false),
      ));
  }

  // ── AI ─────────────────────────────────────────────────────────────────────

  bool get _isAiPlayer => _turn >= _cpuStartIdx;

  void _triggerAiIfNeeded() {
    if (_ais.isEmpty) return;
    if (!_isAiPlayer) return; // human's turn
    if (_eliminated.contains(_turn)) return;
    if (_phase != _Phase.playing && _phase != _Phase.knocked) return;

    final aiIndex = _turn - _cpuStartIdx;
    if (aiIndex < 0 || aiIndex >= _ais.length) return;

    final ai = _ais[aiIndex];
    final hand = _hands[_turn];
    final score = _calcScore(hand);
    final canKnock = _knocker == null;

    // Check if any human player is still in the game
    final anyHumanAlive = List.generate(_cpuStartIdx, (i) => i)
        .any((i) => !_eliminated.contains(i));

    ai.takeTurn(
      aiIdx: _turn,
      hand: _handToJson(hand),
      center: _handToJson(_center),
      currentScore: score,
      canKnock: canKnock,
      humanEliminated: !anyHumanAlive,
    );
  }

  // ── Player actions ─────────────────────────────────────────────────────────

  void _onTapHand(int idx) {
    if (!_isMyTurn) return;
    setState(() {
      if (_selectedHandIdx == idx) {
        _selectedHandIdx = null;
      } else {
        _selectedHandIdx = idx;
      }
      // If both selected, do swap
      if (_selectedHandIdx != null && _selectedCenterIdx != null) {
        _doSwap1(_selectedHandIdx!, _selectedCenterIdx!);
      }
    });
  }

  void _onTapCenter(int idx) {
    if (!_isMyTurn) return;
    setState(() {
      if (_selectedCenterIdx == idx) {
        _selectedCenterIdx = null;
      } else {
        _selectedCenterIdx = idx;
      }
      // If both selected, do swap
      if (_selectedHandIdx != null && _selectedCenterIdx != null) {
        _doSwap1(_selectedHandIdx!, _selectedCenterIdx!);
      }
    });
  }

  void _doSwap1(int handIdx, int centerIdx) {
    _selectedHandIdx = null;
    _selectedCenterIdx = null;
    if (_net.isHost) {
      _handleSwap1({'idx': _myIdx, 'handIdx': handIdx, 'centerIdx': centerIdx});
    } else {
      _net.send('IEN_SWAP1', {'idx': _myIdx, 'handIdx': handIdx, 'centerIdx': centerIdx});
    }
  }

  void _doSwapAll() {
    if (!_isMyTurn) return;
    _selectedHandIdx = null;
    _selectedCenterIdx = null;
    if (_net.isHost) {
      _handleSwap3({'idx': _myIdx});
    } else {
      _net.send('IEN_SWAP3', {'idx': _myIdx});
    }
  }

  void _doKnock() {
    if (!_isMyTurn) return;
    if (_knocker != null) return;
    _selectedHandIdx = null;
    _selectedCenterIdx = null;
    if (_net.isHost) {
      _handleKnock({'idx': _myIdx});
    } else {
      _net.send('IEN_KNOCK', {'idx': _myIdx});
    }
  }

  void _doPass() {
    if (!_isMyTurn) return;
    _selectedHandIdx = null;
    _selectedCenterIdx = null;
    if (_net.isHost) {
      _handlePass({'idx': _myIdx});
    } else {
      _net.send('IEN_PASS', {'idx': _myIdx});
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      key: scaffoldKey,
      players: gamePlayers,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      title: L.ienentritich.gameName,
      rules: L.ienentritich.rules,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_phase == _Phase.dealing) {
      return const Center(child: CircularProgressIndicator(color: kPurple));
    }
    if (_phase == _Phase.gameOver) {
      return _buildGameOver();
    }

    return LayoutBuilder(builder: (context, constraints) {
      final isRoundOver = _phase == _Phase.roundOver;
      return Column(children: [
        // Status bar
        GameStatusBar(
          text: _statusMsg ?? (!isRoundOver && _phase != _Phase.gameOver
              ? (_isMyTurn
                  ? L.ienentritich.yourTurn
                  : L.ienentritich.waitingFor.fmt({'player': widget.players[_turn].name}))
              : null),
          textColor: _statusMsg != null ? null : (_isMyTurn ? kGreen : kMuted),
        ),
        // Opponents area (compact)
        _buildOpponents(isRoundOver),

        // Spacer pushes center cards toward middle
        const Spacer(),
        // Knock warning
        if (_phase == _Phase.knocked && !isRoundOver)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Text(L.ienentritich.lastTurn,
                style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        // Pot display
        _buildPot(),
        const SizedBox(height: 6),
        // Center cards — the main focus
        _buildCenterCards(isRoundOver),

        // Spacer pushes my hand toward bottom
        const Spacer(),

        // Round over scores
        if (isRoundOver && _roundScores != null)
          _buildRoundOverScores(),
        // My score
        if (_myIdx < _hands.length && _hands[_myIdx].isNotEmpty && !isRoundOver)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${L.ienentritich.score}: ${_calcScore(_hands[_myIdx]).toStringAsFixed(_calcScore(_hands[_myIdx]) == 30.5 ? 1 : 0)}',
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
          ),
        // My hand
        _buildMyHand(isRoundOver),
        const SizedBox(height: 4),
        // Action buttons
        if (_isMyTurn && !isRoundOver)
          _buildActions(),
        const SizedBox(height: 8),
      ]);
    });
  }

  // ── Opponents ──────────────────────────────────────────────────────────────

  Widget _buildOpponents(bool revealAll) {
    final opponents = <int>[];
    for (int i = 0; i < _playerCount; i++) {
      if (i != _myIdx) opponents.add(i);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: opponents.map((i) => _buildOpponent(i, revealAll)).toList(),
      ),
    );
  }

  Widget _buildOpponent(int idx, bool revealAll) {
    final elim = _eliminated.contains(idx);
    final isSwimming = _coins.length > idx && _coins[idx] == 1 && !elim;
    final isTurn = idx == _turn && !revealAll && _phase != _Phase.gameOver;
    final name = widget.players[idx].name;
    final color = widget.players[idx].color;

    return Expanded(
      child: Opacity(
        opacity: elim ? 0.4 : 1.0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isTurn ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isTurn ? color.withValues(alpha: 0.6) : kBorder,
              width: isTurn ? 2 : 1,
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Name
            Text(name,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            // Lives
            _buildCoins(idx),
            if (isSwimming)
              Text(L.ienentritich.swimming,
                style: TextStyle(color: Colors.blue.shade300, fontSize: 9, fontStyle: FontStyle.italic)),
            if (elim)
              Text(L.ienentritich.eliminated,
                style: const TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            // Cards
            if (!elim && idx < _hands.length && _hands[idx].isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_hands[idx].length, (ci) {
                  if (revealAll) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: _buildFaceUp(_hands[idx][ci], 32, 44, small: true),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _buildFaceDown(32, 44),
                  );
                }),
              ),
            // Show score at round end
            if (revealAll && _roundScores != null && idx < _roundScores!.length && _roundScores![idx] >= 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _roundScores![idx].toStringAsFixed(_roundScores![idx] == 30.5 ? 1 : 0),
                  style: TextStyle(
                    color: (_roundLosers?.contains(idx) ?? false) ? Colors.red : kGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildCoins(int idx) {
    if (idx >= _coins.length) return const SizedBox();
    final coins = _coins[idx];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(coins.clamp(0, 8), (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: _GuldenCent(size: 16),
        );
      }),
    );
  }

  Widget _buildPot() {
    if (_pot <= 0) return const SizedBox();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1F0E).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8860B).withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${L.ienentritich.pot}: ', style: const TextStyle(color: kMuted, fontSize: 12)),
        ...List.generate(_pot.clamp(0, 6), (i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: _GuldenCent(size: 18),
        )),
        if (_pot > 6)
          Text(' +${_pot - 6}', style: const TextStyle(color: Color(0xFFDAA520), fontSize: 12)),
      ]),
    );
  }

  // ── Center cards ───────────────────────────────────────────────────────────

  Widget _buildCenterCards(bool roundOver) {
    if (_center.isEmpty) return const SizedBox();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_center.length, (i) {
        final selected = _selectedCenterIdx == i;
        return GestureDetector(
          onTap: roundOver ? null : () => _onTapCenter(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            transform: selected ? (Matrix4.identity()..translate(0.0, -8.0)) : Matrix4.identity(),
            child: _buildFaceUp(_center[i], 60, 84, selected: selected),
          ),
        );
      }),
    );
  }

  // ── My hand ────────────────────────────────────────────────────────────────

  Widget _buildMyHand(bool roundOver) {
    if (_myIdx >= _hands.length || _hands[_myIdx].isEmpty) {
      return const SizedBox(height: 84);
    }
    final hand = _hands[_myIdx];
    final isSwimming = _coins.length > _myIdx && _coins[_myIdx] == 1 && !_eliminated.contains(_myIdx);

    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Player name + coins
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.players[_myIdx].name,
          style: TextStyle(color: widget.players[_myIdx].color, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text('${L.ienentritich.lives}: ', style: const TextStyle(color: kMuted, fontSize: 11)),
        ...List.generate((_coins.length > _myIdx ? _coins[_myIdx] : 0).clamp(0, 8), (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: _GuldenCent(size: 20),
          );
        }),
        if (_coins.length > _myIdx && _coins[_myIdx] == 0)
          Text(' 0', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
        if (isSwimming) ...[
          const SizedBox(width: 6),
          Text(L.ienentritich.swimming,
            style: TextStyle(color: Colors.blue.shade300, fontSize: 11, fontStyle: FontStyle.italic)),
        ],
      ]),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(hand.length, (i) {
          final selected = _selectedHandIdx == i;
          return GestureDetector(
            onTap: roundOver ? null : () => _onTapHand(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              transform: selected ? (Matrix4.identity()..translate(0.0, -10.0)) : Matrix4.identity(),
              child: _buildFaceUp(hand[i], 65, 90, selected: selected),
            ),
          );
        }),
      ),
    ]);
  }

  // ── Action buttons ─────────────────────────────────────────────────────────

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Swap All
        _ActionButton(
          label: L.ienentritich.swapAll,
          icon: Icons.swap_horiz,
          onTap: _doSwapAll,
          color: kPurple2,
        ),
        const SizedBox(width: 12),
        // Knock (if nobody knocked yet) or Pass (keep hand as-is during last turn)
        if (_knocker == null)
          _ActionButton(
            label: L.ienentritich.knock,
            icon: Icons.front_hand,
            onTap: _doKnock,
            color: Colors.orange,
          )
        else
          _ActionButton(
            label: L.ienentritich.pass,
            icon: Icons.check,
            onTap: _doPass,
            color: kGreen,
          ),
      ]),
    );
  }

  // ── Round over scores ──────────────────────────────────────────────────────

  Widget _buildRoundOverScores() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(L.ienentritich.roundOver,
          style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...List.generate(_playerCount, (i) {
          final isLoser = _roundLosers?.contains(i) ?? false;
          final score = (_roundScores != null && i < _roundScores!.length) ? _roundScores![i] : -1.0;
          if (score < 0 && !isLoser) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(widget.players[i].name,
                style: TextStyle(
                  color: isLoser ? Colors.red : kText,
                  fontSize: 12,
                  fontWeight: isLoser ? FontWeight.bold : FontWeight.normal,
                )),
              const SizedBox(width: 8),
              Text(score >= 0 ? score.toStringAsFixed(score == 30.5 ? 1 : 0) : '-',
                style: TextStyle(color: isLoser ? Colors.red : kMuted, fontSize: 12)),
              if (i == _roundWinner) ...[
                const SizedBox(width: 4),
                _GuldenCent(size: 12),
                const Text(' pot!', style: TextStyle(color: Color(0xFFDAA520), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
              if (isLoser) ...[
                const SizedBox(width: 4),
                _GuldenCent(size: 12),
                const Text(' -1', style: TextStyle(color: Colors.red, fontSize: 10)),
              ],
            ]),
          );
        }),
      ]),
    );
  }

  // ── Game over ──────────────────────────────────────────────────────────────

  Widget _buildGameOver() {
    return Column(children: [
      const Spacer(),
      if (_winner != null)
        GameResultBanner(
          players: gamePlayers,
          winnerIdx: _winner!,
          onFirstRender: () { fireConfettiOnce(_winner!); recordResult('ienentritich', _winner!); },
        ),
      const SizedBox(height: 16),
      GameOverActions(players: gamePlayers, onReset: _resetGame),
      const Spacer(),
    ]);
  }

  // ── Card rendering ─────────────────────────────────────────────────────────

  Widget _buildFaceUp(_Card card, double w, double h, {bool selected = false, bool small = false}) {
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
                  fontSize: w * (small ? 0.26 : 0.22),
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                )),
              Text(_suitStr(card.suit),
                style: TextStyle(color: suitColor, fontSize: w * (small ? 0.22 : 0.18), height: 1.0)),
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
                    fontSize: w * (small ? 0.26 : 0.22),
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  )),
                Text(_suitStr(card.suit),
                  style: TextStyle(color: suitColor, fontSize: w * (small ? 0.22 : 0.18), height: 1.0)),
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
}

// ── Guilder cent coin widget ─────────────────────────────────────────────────

class _GuldenCent extends StatelessWidget {
  final double size;
  const _GuldenCent({this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: _CoinPainter());
  }
}

class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Outer rim — darker bronze
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF8B6914));

    // Main face — copper/bronze gradient
    final grad = RadialGradient(
      center: const Alignment(-0.25, -0.3),
      colors: [
        const Color(0xFFDAA520), // golden highlight
        const Color(0xFFCD853F), // bronze
        const Color(0xFFB8860B), // dark gold
      ],
    );
    canvas.drawCircle(c, r * 0.92, Paint()
      ..shader = grad.createShader(Rect.fromCircle(center: c, radius: r * 0.92)));

    // Inner ring
    canvas.drawCircle(c, r * 0.75, Paint()
      ..color = const Color(0xFF8B6914).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06);

    // "1c" text
    final textPainter = TextPainter(
      text: TextSpan(
        text: '1c',
        style: TextStyle(
          color: const Color(0xFF5C3D0E),
          fontSize: r * 0.75,
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(
      c.dx - textPainter.width / 2,
      c.dy - textPainter.height / 2,
    ));

    // Subtle specular highlight
    canvas.drawCircle(
      Offset(c.dx - r * 0.2, c.dy - r * 0.25),
      r * 0.25,
      Paint()..color = Colors.white.withValues(alpha: 0.2)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Action button widget ─────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _ActionButton({required this.label, required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}
