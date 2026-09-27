import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/wake_lock.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';
import 'klaverjassen_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Klaverjassen (Rotterdams) — 4 players, 2 teams
//
// Seating: 0=human1, 1=cpu_opponent, 2=human2_or_cpu_partner, 3=cpu_opponent2
// Teams:   team0 = players 0+2,  team1 = players 1+3
//
// With 2 real players:  player 0 (host) and player 2 (joiner) are partners.
//                       players 1 and 3 are CPU opponents.
// With 1 real player:   solo practice — player 0 is human, 1,2,3 are CPU.
// ─────────────────────────────────────────────────────────────────────────────

enum _RoundPhase { bidding, playing, result }

class KlaverjassenScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const KlaverjassenScreen({
    super.key,
    required this.players,
    required this.firstPlayer,
    this.extra,
  });
  @override State<KlaverjassenScreen> createState() => _KlaverjassenState();
}

class _KlaverjassenState extends State<KlaverjassenScreen> with GameMixin {
  final _net     = Network();
  final _session = SessionState();
  final _rng     = math.Random();

  // ── Game state ─────────────────────────────────────────────────────────────
  late KlaverjasState _state;
  // Joiner: _state is unset until the first KLA_STATE arrives
  bool _hasState = false;
  Timer? _syncReqTimer; // joiner: retries KLA_SYNC_REQ until state arrives
  _RoundPhase _phase = _RoundPhase.bidding;

  // Bidding
  int _dealerIdx    = 0;   // who dealt this round
  int _biddingTurn  = 0;   // who is currently being asked to bid (0..3)
  int _passCount    = 0;   // how many consecutive passes
  KSuit _proposedTrump = KSuit.hearts; // derived from first card dealt to p[left of dealer]
  bool _mustPlay    = false; // all passed → dealer must play

  // Round result
  int _roundTeamPts0 = 0, _roundTeamPts1 = 0;
  int _roundRoem0    = 0, _roundRoem1    = 0;
  bool _nat          = false;
  bool _pit          = false;
  int  _bidTeam      = 0;

  // Match
  int _matchRound = 0; // out of 16
  static const int kMatchRounds = 16;

  // Card selection
  int? _selectedCardIdx; // index into my hand

  // Trick-win animation: seat that won the trick (-1 = no animation)
  int _trickWinSeat = -1;

  // Last completed trick (for review in solo mode)
  List<KCard?>? _lastTrickCards;  // 4 cards from the last completed trick
  int _lastTrickWinner = -1;      // seat that won the last trick

  // CPU timers
  Timer? _cpuTimer;

  // Who is the local human player? Always idx 0 for host, idx 2 for joiner (partner seat)
  int get _humanIdx => _net.isHost ? 0 : 2;

  // Players are always [real1, cpu_opp1, real2_or_cpu, cpu_opp2]
  // But for display, widget.players has 2 real players (or 1 in solo)
  // CPU player names are generated
  List<String> get _seatNames {
    final p = widget.players;
    return [
      p[0].name,
      '${L.klaverjassen.cpuPlayer.fmt({'n': '1'})}',
      _isCpu(2) ? '${L.klaverjassen.cpuPlayer.fmt({'n': '2'})}' : p[1].name,
      '${L.klaverjassen.cpuPlayer.fmt({'n': '3'})}',
    ];
  }

  bool _isCpu(int seat) => seat == 1 || seat == 3 || (seat == 2 && (_net.isSolo || widget.players.length < 2));

  int _winner = 0; // 0=team0, 1=team1 (match winner)
  bool _matchOver = false;

  @override List<Player> get gamePlayers => widget.players;

  @override void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    WakeLock.acquire();
    if (_net.isHost) {
      _startNewRound(dealerIdx: 0);
    } else {
      _startSyncRequests();
    }
  }

  /// Joiner: the host's opening KLA_STATE may be sent before this screen
  /// subscribes — ask for the state until it has arrived.
  void _startSyncRequests() {
    _syncReqTimer?.cancel();
    int tries = 0;
    _syncReqTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (!mounted || _hasState || tries >= 4) { t.cancel(); return; }
      tries++;
      _net.send('KLA_SYNC_REQ');
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && !_hasState) _net.send('KLA_SYNC_REQ');
    });
  }

  @override void dispose() {
    _cpuTimer?.cancel();
    _syncReqTimer?.cancel();
    super.dispose();
  }

  // ── Round setup ────────────────────────────────────────────────────────────

  void _startNewRound({required int dealerIdx}) {
    final deck = kDeck()..shuffle(_rng);
    final hands = [
      deck.sublist(0, 8),
      deck.sublist(8, 16),
      deck.sublist(16, 24),
      deck.sublist(24, 32),
    ];
    _state = KlaverjasState(
      hands:       hands,
      trump:       KSuit.hearts, // placeholder, determined during bidding
      bidder:      -1,
      trickLeader: (dealerIdx + 1) % 4,
      matchScore:  _matchRound == 0 ? [0, 0] : (_state.matchScore),
      totalRounds: _matchRound,
    );
    _dealerIdx   = dealerIdx;
    _biddingTurn = (dealerIdx + 1) % 4;
    _passCount   = 0;
    _mustPlay    = false;
    _phase       = _RoundPhase.bidding;
    _nat         = false;
    _pit         = false;
    _selectedCardIdx = null;
    _lastTrickCards  = null;
    _lastTrickWinner = -1;

    // Proposed trump = suit of first card dealt to player left of dealer
    _proposedTrump = hands[_biddingTurn].first.suit;

    // Redraw now — if the human bids first no CPU timer will trigger a rebuild
    if (mounted) setState(() {});
    _broadcastFull();
    _scheduleCpuBid();
  }

  // ── Bidding ────────────────────────────────────────────────────────────────

  void _scheduleCpuBid() {
    if (!_net.isHost) return;
    if (_phase != _RoundPhase.bidding) return;
    if (!_isCpu(_biddingTurn)) return;

    _cpuTimer?.cancel();
    _cpuTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _phase != _RoundPhase.bidding) return;
      final ai   = KlaverjasAI(_biddingTurn);
      final bids = ai.decideBid(_state.hands[_biddingTurn], _proposedTrump);
      if (bids) {
        _applyBid(seat: _biddingTurn, plays: true);
      } else {
        _applyPass(seat: _biddingTurn);
      }
    });
  }

  void _applyBid({required int seat, required bool plays}) {
    if (!plays) {
      _applyPass(seat: seat);
      return;
    }
    setState(() {
      _state = KlaverjasState(
        hands:       _state.hands,
        trump:       _proposedTrump,
        bidder:      seat,
        trickLeader: (_dealerIdx + 1) % 4,
        matchScore:  _state.matchScore,
        totalRounds: _state.totalRounds,
      );
      _phase   = _RoundPhase.playing;
      _bidTeam = _state.teamOf(seat);
    });
    SoundPlayer.i.uiSelect();
    HapticFeedback.mediumImpact();
    _broadcastFull();
    _scheduleCpuPlay();
  }

  void _applyPass({required int seat}) {
    _passCount++;
    _biddingTurn = (_biddingTurn + 1) % 4;

    if (_passCount >= 4) {
      // All passed — dealer must play; pick trump freely (AI picks best, human chooses)
      _mustPlay = true;
      if (_isCpu(_dealerIdx)) {
        // CPU dealer: pick suit with most cards
        KSuit best = KSuit.hearts;
        int bestCount = 0;
        for (final s in KSuit.values) {
          final cnt = _state.hands[_dealerIdx].where((c) => c.suit == s).length;
          if (cnt > bestCount) { bestCount = cnt; best = s; }
        }
        _proposedTrump = best;
        _applyBid(seat: _dealerIdx, plays: true);
        return;
      } else {
        // Human dealer must choose trump
        setState(() {});
        _broadcastFull();
        return;
      }
    }

    setState(() {});
    _broadcastFull();
    _scheduleCpuBid();
  }

  void _humanBid(bool plays) {
    if (_phase != _RoundPhase.bidding) return;
    if (_biddingTurn != _humanIdx && !(_mustPlay && _dealerIdx == _humanIdx)) return;
    if (_net.isHost) {
      _applyBid(seat: _humanIdx, plays: plays);
    } else {
      _net.send('KLA_BID', {'plays': plays, 'trump': _proposedTrump.index});
    }
  }

  void _humanChooseTrump(KSuit suit) {
    if (!_mustPlay) return;
    _proposedTrump = suit;
    _humanBid(true);
  }

  // ── Playing ────────────────────────────────────────────────────────────────

  void _scheduleCpuPlay() {
    if (!_net.isHost) return;
    if (_phase != _RoundPhase.playing) return;

    // Find whose turn it is
    final toPlay = _nextToPlay();
    if (toPlay == null || !_isCpu(toPlay)) return;

    _cpuTimer?.cancel();
    final cpuDelay = _net.isSolo ? 1200 : 900;
    _cpuTimer = Timer(Duration(milliseconds: cpuDelay), () {
      if (!mounted || _phase != _RoundPhase.playing) return;
      final ai   = KlaverjasAI(toPlay);
      final card = ai.chooseCard(_state);
      _applyCard(seat: toPlay, card: card);
    });
  }

  // Returns the next seat that needs to play in current trick, or null if all played
  int? _nextToPlay() {
    for (int i = 0; i < 4; i++) {
      final seat = (_state.trickLeader + i) % 4;
      if (_state.currentTrick[seat] == null) return seat;
    }
    return null;
  }

  void _applyCard({required int seat, required KCard card}) {
    setState(() {
      _state.hands[seat].remove(card);
      _state.currentTrick[seat] = card;
    });
    SoundPlayer.i.uiClick();
    HapticFeedback.lightImpact();

    final allPlayed = _state.currentTrick.every((c) => c != null);
    if (allPlayed) {
      _cpuTimer?.cancel();
      // Store last trick for review (solo mode)
      _lastTrickCards  = List<KCard?>.from(_state.currentTrick);
      final winner = _state.trickWinner();
      _lastTrickWinner = winner;
      // Show cards before animating — longer pause in solo so human can follow
      final displayDelay = _net.isSolo ? 1200 : 600;
      _cpuTimer = Timer(Duration(milliseconds: displayDelay), () {
        if (!mounted) return;
        setState(() => _trickWinSeat = winner);
        _cpuTimer = Timer(const Duration(milliseconds: 550), () {
          if (mounted) _resolveTrick();
        });
      });
    } else {
      _broadcastFull();
      _scheduleCpuPlay();
    }
  }

  void _resolveTrick() {
    if (!mounted) return;
    final winner = _state.trickWinner();
    final winTeam = _state.teamOf(winner);

    // Points from cards
    int pts = 0;
    final trickCards = _state.currentTrick.whereType<KCard>().toList();
    for (final c in trickCards) pts += c.points(_state.trump);

    // Last trick bonus (+10)
    if (_state.tricksPlayed == 7) pts += 10;

    // Roem
    final roem = calcRoem(trickCards, _state.trump);
    int roemPts = roem.fold(0, (s, r) => s + r.points);

    // Sound: trick collected — distinctive sound when your team wins the trick
    if (_state.teamOf(winner) == _state.teamOf(_humanIdx)) {
      SoundPlayer.i.uiConfirm();
      HapticFeedback.mediumImpact();
    } else {
      SoundPlayer.i.uiClick();
    }

    setState(() {
      _trickWinSeat = -1;
      _state.teamPoints[winTeam] += pts;
      _state.teamRoem[winTeam]   += roemPts;
      _state.tricksPlayed++;
      _state.trickLeader = winner;
      _state.currentTrick = List.filled(4, null);
    });

    if (_state.roundOver) {
      _cpuTimer?.cancel();
      _cpuTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) _finishRound();
      });
    } else {
      _broadcastFull();
      _scheduleCpuPlay();
    }
  }

  void _finishRound() {
    if (!mounted) return;
    final bidTeam = _state.teamOf(_state.bidder);
    final p0 = _state.teamPoints[0] + _state.teamRoem[0];
    final p1 = _state.teamPoints[1] + _state.teamRoem[1];
    // Check pit (all 8 tricks to one team)
    final pitTeam = _checkPit();
    _pit = pitTeam >= 0;

    // Check nat
    final bidTeamTotal = bidTeam == 0 ? p0 : p1;
    final oppTeamTotal = bidTeam == 0 ? p1 : p0;
    _nat = bidTeamTotal < oppTeamTotal;

    setState(() {
      if (_pit) {
        // Non-bidding team swept all 8 tricks: they get their points + 100 pit bonus; bidding team 0
        _roundTeamPts0 = pitTeam == 0 ? _state.teamPoints[0] + _state.teamRoem[0] + 100 : 0;
        _roundTeamPts1 = pitTeam == 1 ? _state.teamPoints[1] + _state.teamRoem[1] + 100 : 0;
      } else if (_nat) {
        // Bidding team goes nat: 0 pts, opponents get everything + roem
        _roundTeamPts0 = bidTeam == 0 ? 0 : p0 + p1;
        _roundTeamPts1 = bidTeam == 1 ? 0 : p0 + p1;
      } else {
        _roundTeamPts0 = p0;
        _roundTeamPts1 = p1;
      }

      _roundRoem0 = _state.teamRoem[0];
      _roundRoem1 = _state.teamRoem[1];
      _state.matchScore[0] += _roundTeamPts0;
      _state.matchScore[1] += _roundTeamPts1;
      _matchRound++;
      _phase = _RoundPhase.result;
    });

    // Check match over — must be set BEFORE broadcastFull so joiner receives correct state
    if (_matchRound >= kMatchRounds) {
      _matchOver = true;
      _winner    = _state.matchScore[0] > _state.matchScore[1] ? 0
                 : _state.matchScore[1] > _state.matchScore[0] ? 1 : -1;
      if (_net.isHost) _session.advanceGame();
    }

    _broadcastFull();
    SoundPlayer.i.boppeslachRoundDone();
    HapticFeedback.heavyImpact();
  }

  int _checkPit() {
    // All 8 tricks to one team: would need to track per-trick winner
    // Simplified: if one team has 152+ raw card points (162 - 10 last trick minimum for other)
    if (_state.teamPoints[0] >= 162 && _state.teamPoints[1] == 0) return 0;
    if (_state.teamPoints[1] >= 162 && _state.teamPoints[0] == 0) return 1;
    return -1;
  }

  void _humanPlayCard() {
    if (_phase != _RoundPhase.playing) return;
    if (_selectedCardIdx == null) return;
    final toPlay = _nextToPlay();
    if (toPlay != _humanIdx) return;

    final hand  = _state.hands[_humanIdx];
    final legal = _state.legalCards(_humanIdx);
    final card  = hand[_selectedCardIdx!];
    if (!legal.contains(card)) {
      SoundPlayer.i.uiClick();
      return;
    }

    setState(() => _selectedCardIdx = null);

    if (_net.isHost) {
      _applyCard(seat: _humanIdx, card: card);
    } else {
      _net.send('KLA_PLAY', {'card': card.encode()});
    }
  }

  void _showLastTrick() {
    if (_lastTrickCards == null) return;
    final names = _seatNames;
    final cards = _lastTrickCards!;
    final winner = _lastTrickWinner;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: kBorder)),
        title: Text(L.klaverjassen.lastTrick,
            style: const TextStyle(color: kText, fontSize: 16)),
        content: SizedBox(
          width: 220,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (int s = 0; s < 4; s++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 70,
                    child: Text(names[s],
                      style: TextStyle(
                        color: s == winner ? kGreen : kMuted,
                        fontWeight: s == winner ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13))),
                  if (cards[s] != null)
                    SizedBox(width: 42, height: 58,
                      child: _CardFace(card: cards[s]!, trump: _state.trump))
                  else
                    const SizedBox(width: 42, height: 58),
                  if (s == winner) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.emoji_events, color: kGreen, size: 16),
                  ],
                ]),
              ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: kPurple)),
          ),
        ],
      ),
    );
  }

  void _nextRound() {
    if (_matchOver) return;
    // Ignore extra taps once the next round has already been dealt
    if (_phase != _RoundPhase.result) return;
    if (_net.isHost) {
      _startNewRound(dealerIdx: (_dealerIdx + 1) % 4);
    } else {
      _net.send('KLA_NEXT_ROUND_REQ');
    }
  }

  // ── Networking ─────────────────────────────────────────────────────────────

  void _broadcastFull() {
    if (!_net.isHost) return;
    _net.send('KLA_STATE', _encodeState());
  }

  Map<String, dynamic> _encodeState() => {
    'phase':      _phase.index,
    'hands':      _state.hands.map((h) => h.map((c) => c.encode()).toList()).toList(),
    'trick':      _state.currentTrick.map((c) => c?.encode() ?? -1).toList(),
    'leader':     _state.trickLeader,
    'trump':      _state.trump.index,
    'bidder':     _state.bidder,
    'tricks':     _state.tricksPlayed,
    'tp0':        _state.teamPoints[0],
    'tp1':        _state.teamPoints[1],
    'tr0':        _state.teamRoem[0],
    'tr1':        _state.teamRoem[1],
    'ms0':        _state.matchScore[0],
    'ms1':        _state.matchScore[1],
    'matchRound': _matchRound,
    'dealer':     _dealerIdx,
    'bidTurn':    _biddingTurn,
    'passCount':  _passCount,
    'mustPlay':   _mustPlay,
    'propTrump':  _proposedTrump.index,
    'nat':        _nat,
    'pit':        _pit,
    'bidTeam':    _bidTeam,
    'matchOver':  _matchOver,
    'winner':     _winner,
    'rp0':        _roundTeamPts0,
    'rp1':        _roundTeamPts1,
    'rr0':        _roundRoem0,
    'rr1':        _roundRoem1,
  };

  void _decodeState(Map<String, dynamic> msg) {
    final handData = msg['hands'] as List;
    final hands = handData
        .map((h) => (h as List).map((v) => KCard.decode(v as int)).toList())
        .toList();

    final trickData = msg['trick'] as List;
    final trick = trickData.map((v) => v == -1 ? null : KCard.decode(v as int)).toList();

    _state = KlaverjasState(
      hands:       hands,
      trump:       KSuit.values[msg['trump'] as int],
      bidder:      msg['bidder'] as int,
      trickLeader: msg['leader'] as int,
      tricksPlayed: msg['tricks'] as int,
      teamPoints:  [msg['tp0'] as int, msg['tp1'] as int],
      teamRoem:    [msg['tr0'] as int, msg['tr1'] as int],
      matchScore:  [msg['ms0'] as int, msg['ms1'] as int],
      totalRounds: msg['matchRound'] as int,
    );
    _state.currentTrick = trick;

    _phase           = _RoundPhase.values[msg['phase'] as int];
    _matchRound      = msg['matchRound'] as int;
    _dealerIdx       = msg['dealer'] as int;
    _biddingTurn     = msg['bidTurn'] as int;
    _passCount       = msg['passCount'] as int;
    _mustPlay        = msg['mustPlay'] as bool;
    _proposedTrump   = KSuit.values[msg['propTrump'] as int];
    _nat             = msg['nat'] as bool;
    _pit             = msg['pit'] as bool;
    _bidTeam         = msg['bidTeam'] as int;
    _matchOver       = msg['matchOver'] as bool;
    _winner          = msg['winner'] as int;
    _roundTeamPts0   = msg['rp0'] as int;
    _roundTeamPts1   = msg['rp1'] as int;
    _roundRoem0      = msg['rr0'] as int;
    _roundRoem1      = msg['rr1'] as int;
    _hasState        = true;
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    if (!mounted) return;
    switch (msg['type'] as String) {
      case 'KLA_STATE':
        if (!_net.isHost) setState(() => _decodeState(msg));
        break;

      case 'KLA_BID':
        if (_net.isHost) {
          final plays = msg['plays'] as bool;
          if (plays) {
            _proposedTrump = KSuit.values[msg['trump'] as int];
            _applyBid(seat: 2, plays: true);
          } else {
            _applyPass(seat: 2);
          }
        }
        break;

      case 'KLA_PLAY':
        if (_net.isHost) {
          final card = KCard.decode(msg['card'] as int);
          _applyCard(seat: 2, card: card);
        }
        break;

      case 'KLA_NEXT_ROUND_REQ':
        if (_net.isHost && _phase == _RoundPhase.result && !_matchOver) {
          _startNewRound(dealerIdx: (_dealerIdx + 1) % 4);
        }
        break;

      case 'GAME_RESET':
        GameOverActions.handleMessage(msg, _reset);
        break;

      case 'KLA_SYNC_REQ':
        // Joiner missed the opening KLA_STATE (or reconnected) — send full state
        if (_net.isHost && !_net.isSolo) _net.sendTo(fromIdx, 'KLA_STATE', _encodeState());
        break;
    }
  }

  void _reset() {
    resetConfetti();
    resetStats();
    _matchRound = 0;
    _matchOver  = false;
    if (_net.isHost) _startNewRound(dealerIdx: 0);
  }

  void _showReconnect() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _broadcastFull();
          else _net.send('KLA_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(
          context,
          fadeScaleRoute(const LobbyScreen()),
          (_) => false,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override Widget build(BuildContext context) {
    return GameScaffold(
      key: scaffoldKey,
      title: L.klaverjassen.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      typingName: typingName,
      rules: L.klaverjassen.rules,
      child: Column(children: [
        const GameStatusBar(),
        Expanded(child: !_net.isHost && !_hasState
          ? _buildWaiting()
          : switch (_phase) {
              _RoundPhase.bidding  => _buildBidding(),
              _RoundPhase.playing  => _buildPlaying(),
              _RoundPhase.result   => _buildResult(),
            }),
      ]),
    );
  }

  // Joiner: shown until the first KLA_STATE has arrived
  Widget _buildWaiting() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(color: kPurple),
      const SizedBox(height: 12),
      Text(L.common.waitingForHostResult,
          style: const TextStyle(color: kMuted, fontSize: 14)),
    ]),
  );

  // ── Bidding UI ─────────────────────────────────────────────────────────────

  Widget _buildBidding() {
    final isMyBidTurn = _biddingTurn == _humanIdx && !_isCpu(_humanIdx);
    final names = _seatNames;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Score row
        _ScoreBar(ms0: _state.matchScore[0], ms1: _state.matchScore[1],
            round: _matchRound, names: names),
        const SizedBox(height: 16),

        // Trump proposal
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kBg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder)),
          child: Column(children: [
            Text(L.klaverjassen.chooseTrump,
                style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _SuitBadge(suit: _proposedTrump, large: true),
              const SizedBox(width: 12),
              Text('${names[_biddingTurn]}…',
                  style: const TextStyle(color: kMuted, fontSize: 14)),
            ]),
            const SizedBox(height: 4),
            Text('${L.klaverjassen.pass}×$_passCount',
                style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),

        const SizedBox(height: 16),

        // Must play — human chooses trump
        if (_mustPlay && _dealerIdx == _humanIdx) ...[
          Text(L.klaverjassen.mustPlay, style: const TextStyle(color: Colors.orangeAccent)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, children: KSuit.values.map((s) =>
            GestureDetector(
              onTap: () => _humanChooseTrump(s),
              child: _SuitBadge(suit: s, large: true),
            )).toList()),
          const SizedBox(height: 16),
        ],

        // Bid / Pass buttons
        if (isMyBidTurn && !_mustPlay)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton.icon(
              onPressed: () => _humanBid(true),
              icon: const Icon(Icons.check, size: 18),
              label: Text(L.klaverjassen.play),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen.withValues(alpha: .3),
                side: BorderSide(color: kGreen),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () => _humanBid(false),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kMuted),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              child: Text(L.klaverjassen.pass, style: const TextStyle(color: kMuted)),
            ),
          ]),

        if (!isMyBidTurn && !_mustPlay)
          Text(
            L.klaverjassen.opponentTurn.fmt({'player': names[_biddingTurn]}),
            style: const TextStyle(color: kMuted)),

        const Spacer(),

        // My hand (preview only during bidding)
        _HandRow(
          cards: _state.hands[_humanIdx],
          trump: _proposedTrump,
          legalCards: [],
          selectedIdx: null,
          onTap: (_) {},
          bidMode: true,
        ),
      ]),
    );
  }

  // ── Playing UI ─────────────────────────────────────────────────────────────

  Widget _buildPlaying() {
    final names    = _seatNames;
    final toPlay   = _nextToPlay();
    final isMyTurn = toPlay == _humanIdx;
    final legal    = isMyTurn ? _state.legalCards(_humanIdx) : <KCard>[];
    final myHand   = _state.hands[_humanIdx];

    return Column(children: [
      // Score / trump bar
      _ScoreBar(ms0: _state.matchScore[0], ms1: _state.matchScore[1],
          round: _matchRound, names: names,
          trump: _state.trump, trickNo: _state.tricksPlayed),

      const SizedBox(height: 4),

      // Team scores
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          _TeamChip(label: '${names[0]} + ${names[2]}',
              pts: _state.teamPoints[0], roem: _state.teamRoem[0], isActive: _bidTeam == 0),
          const Spacer(),
          // Last trick review button (solo mode only)
          if (_net.isSolo && _lastTrickCards != null)
            GestureDetector(
              onTap: _showLastTrick,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kBg2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.history, color: kMuted, size: 14),
                  const SizedBox(width: 4),
                  Text(L.klaverjassen.lastTrick,
                      style: const TextStyle(color: kMuted, fontSize: 11)),
                ]),
              ),
            ),
          if (_net.isSolo && _lastTrickCards != null) const Spacer(),
          _TeamChip(label: '${names[1]} + ${names[3]}',
              pts: _state.teamPoints[1], roem: _state.teamRoem[1], isActive: _bidTeam == 1),
        ]),
      ),

      const SizedBox(height: 6),

      // Table — 4-seat trick display
      Expanded(
        child: _TrickTable(
          currentTrick: _state.currentTrick,
          seatNames: names,
          humanSeat: _humanIdx,
          trump: _state.trump,
          trickLeader: _state.trickLeader,
          toPlay: toPlay,
          winSeat: _trickWinSeat,
        ),
      ),

      // Status
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          isMyTurn
              ? L.klaverjassen.yourTurn
              : L.klaverjassen.opponentTurn.fmt({'player': names[toPlay ?? 0]}),
          style: TextStyle(
            color: isMyTurn ? kGreen : kMuted,
            fontWeight: isMyTurn ? FontWeight.bold : FontWeight.normal),
        ),
      ),

      // My hand
      _HandRow(
        cards: myHand,
        trump: _state.trump,
        legalCards: legal,
        selectedIdx: _selectedCardIdx,
        onTap: (i) {
          if (!isMyTurn) return;
          setState(() => _selectedCardIdx = _selectedCardIdx == i ? null : i);
        },
        bidMode: false,
      ),

      // Play button
      Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: ElevatedButton(
          onPressed: isMyTurn && _selectedCardIdx != null ? _humanPlayCard : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPurple,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: Text(L.klaverjassen.play,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    ]);
  }

  // ── Result UI ──────────────────────────────────────────────────────────────

  Widget _buildResult() {
    final names   = _seatNames;
    final bidName = names[_state.bidder];

    return Column(children: [
      Expanded(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [

          Text(L.klaverjassen.roundResult,
              style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          // Nat / Pit
          if (_nat) _StatusPill('NAT – $bidName – 0 pts', Colors.red.shade800),
          if (_pit) _StatusPill('PIT! +100 🎉', kGreen),

          const SizedBox(height: 12),

          // Round scores table
          _RoundScoreTable(
            name0: '${names[0]} + ${names[2]}',
            name1: '${names[1]} + ${names[3]}',
            pts0:  _roundTeamPts0, pts1: _roundTeamPts1,
            roem0: _roundRoem0,   roem1: _roundRoem1,
            ms0:   _state.matchScore[0], ms1: _state.matchScore[1],
            round: _matchRound,
          ),

          const SizedBox(height: 16),

          if (!_matchOver)
            ElevatedButton(
              onPressed: _nextRound,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPurple,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text('${L.klaverjassen.play} ▶  round ${_matchRound + 1}/16'),
            ),
        ]),
      )),

      if (_matchOver) ...[
        GameResultBanner(
          players: widget.players,
          winnerIdx: _winner < 0 ? -1
              : _winner == 0 ? (_humanIdx == 0 ? 0 : 1)
              : (_humanIdx == 0 ? 1 : 0),
          onFirstRender: () {
            final wi = _winner < 0 ? -1
                : _winner == 0 ? (_humanIdx == 0 ? 0 : 1)
                : (_humanIdx == 0 ? 1 : 0);
            fireConfettiOnce(wi);
            recordResult('klaverjassen', wi);
          },
          scores: [
            (label: '${names[0]}+${names[2]}', value: '${_state.matchScore[0]}'),
            (label: '${names[1]}+${names[3]}', value: '${_state.matchScore[1]}'),
          ],
        ),
        GameOverActions(players: widget.players, onReset: _reset),
      ],
    ]);
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  final int ms0, ms1, round;
  final List<String> names;
  final KSuit? trump;
  final int trickNo;
  const _ScoreBar({required this.ms0, required this.ms1, required this.round,
      required this.names, this.trump, this.trickNo = 0});

  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: kBg2, borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      Text('${names[0]}+${names[2]}: $ms0',
          style: const TextStyle(color: kText, fontSize: 12)),
      const Spacer(),
      if (trump != null) _SuitBadge(suit: trump!),
      if (trump != null) const SizedBox(width: 6),
      Text('Rd $round/16  ·  ${trickNo}/8',
          style: const TextStyle(color: kMuted, fontSize: 11)),
      const Spacer(),
      Text('${names[1]}+${names[3]}: $ms1',
          style: const TextStyle(color: kText, fontSize: 12)),
    ]),
  );
}

class _SuitBadge extends StatelessWidget {
  final KSuit suit;
  final bool large;
  const _SuitBadge({required this.suit, this.large = false});

  @override Widget build(BuildContext context) {
    final color = suit.isRed ? Colors.red.shade400 : Colors.white70;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 14 : 8, vertical: large ? 10 : 4),
      decoration: BoxDecoration(
        color: kBg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .5))),
      child: Text(suit.symbol,
          style: TextStyle(color: color, fontSize: large ? 28 : 16, fontWeight: FontWeight.bold)),
    );
  }
}

class _TeamChip extends StatelessWidget {
  final String label;
  final int pts;
  final int roem;
  final bool isActive;
  const _TeamChip({required this.label, required this.pts, this.roem = 0, required this.isActive});

  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: isActive ? kPurple.withValues(alpha: .2) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: isActive ? kPurple : kBorder)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(color: isActive ? kPurple2 : kMuted, fontSize: 11)),
      const SizedBox(height: 2),
      Text('${pts + roem}', style: TextStyle(
          color: isActive ? kText : kMuted, fontSize: 16, fontWeight: FontWeight.bold)),
      if (roem > 0)
        Text('($pts + $roem roem)', style: TextStyle(
            color: isActive ? kPurple2 : kMuted, fontSize: 10)),
    ]),
  );
}

class _TrickTable extends StatelessWidget {
  final List<KCard?> currentTrick;
  final List<String> seatNames;
  final int humanSeat, trickLeader;
  final KSuit trump;
  final int? toPlay;
  final int winSeat; // -1 = no animation, 0..3 = cards slide to this seat
  const _TrickTable({
    required this.currentTrick, required this.seatNames,
    required this.humanSeat, required this.trickLeader,
    required this.trump, required this.toPlay, this.winSeat = -1,
  });

  // Screen-relative alignment for each visual position
  static const _posAlign = {
    'top':    Alignment(0, -0.85),
    'bottom': Alignment(0, 0.85),
    'left':   Alignment(-0.55, 0),
    'right':  Alignment(0.55, 0),
  };

  String _posOf(int seat) {
    if (seat == humanSeat) return 'bottom';
    if (seat == (humanSeat + 2) % 4) return 'top';
    if (seat == (humanSeat + 1) % 4) return 'left';
    return 'right';
  }

  @override Widget build(BuildContext context) {
    final animating = winSeat >= 0;
    final targetPos = animating ? _posOf(winSeat) : null;
    final targetAlign = animating ? _posAlign[targetPos]! : Alignment.center;

    Widget seatLabel(int s) => Text(
      seatNames[s],
      style: TextStyle(
        color: winSeat == s ? kGreen : (toPlay == s ? kGreen : kMuted),
        fontSize: 11,
        fontWeight: (toPlay == s || winSeat == s) ? FontWeight.bold : FontWeight.normal),
    );

    Widget cardSlot(int s) {
      final card = currentTrick[s];
      final restAlign = _posAlign[_posOf(s)]!;
      final align = animating ? targetAlign : restAlign;

      return AnimatedAlign(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: align,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 350),
          opacity: (animating && s != winSeat) ? 0.5 : 1.0,
          child: SizedBox(
            width: 52, height: 72,
            child: card != null
                ? _CardFace(card: card, trump: trump)
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12)),
                  ),
          ),
        ),
      );
    }

    final partner = (humanSeat + 2) % 4;
    final left    = (humanSeat + 1) % 4;
    final right   = (humanSeat + 3) % 4;

    return Stack(children: [
      // Seat labels (fixed positions)
      Align(alignment: const Alignment(0, -1.0),  child: seatLabel(partner)),
      Align(alignment: const Alignment(0, 1.0),   child: seatLabel(humanSeat)),
      Align(alignment: const Alignment(-0.55, -0.22), child: seatLabel(left)),
      Align(alignment: const Alignment(0.55, -0.22),  child: seatLabel(right)),
      // Cards (animated)
      cardSlot(partner),
      cardSlot(left),
      cardSlot(right),
      cardSlot(humanSeat),
    ]);
  }
}

class _CardFace extends StatelessWidget {
  final KCard card;
  final KSuit trump;
  const _CardFace({required this.card, required this.trump});

  @override Widget build(BuildContext context) {
    final isTrump = card.suit == trump;
    final isRed   = card.suit.isRed;
    final color   = isRed ? Colors.red.shade400 : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: isTrump ? kPurple.withValues(alpha: .15) : Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isTrump ? kPurple : Colors.white24, width: isTrump ? 2 : 1)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(card.rank.label, style: TextStyle(
            color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(card.suit.symbol, style: TextStyle(color: color, fontSize: 14)),
      ]),
    );
  }
}

class _HandRow extends StatelessWidget {
  final List<KCard> cards;
  final KSuit trump;
  final List<KCard> legalCards;
  final int? selectedIdx;
  final void Function(int) onTap;
  final bool bidMode;
  const _HandRow({required this.cards, required this.trump, required this.legalCards,
      required this.selectedIdx, required this.onTap, required this.bidMode});

  @override Widget build(BuildContext context) {
    return Container(
      height: 100,
      color: Colors.black26,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: List.generate(cards.length, (i) {
            final c       = cards[i];
            final legal   = bidMode || legalCards.contains(c);
            final sel     = selectedIdx == i;
            final isRed   = c.suit.isRed;
            final isTrump = c.suit == trump;
            final color   = isRed ? Colors.red.shade400 : Colors.white;

            return GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 6),
                transform: sel
                    ? (Matrix4.identity()..translate(0.0, -10.0))
                    : Matrix4.identity(),
                width: 48,
                height: 70,
                decoration: BoxDecoration(
                  color: isTrump
                      ? kPurple.withValues(alpha: .15)
                      : Colors.white.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel
                        ? kPurple
                        : (legal && !bidMode)
                            ? Colors.white38
                            : Colors.white12,
                    width: sel ? 2.5 : 1,
                  ),
                ),
                child: Opacity(
                  opacity: (!bidMode && !legal) ? 0.3 : 1.0,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(c.rank.label, style: TextStyle(
                        color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(c.suit.symbol, style: TextStyle(color: color, fontSize: 13)),
                    if (isTrump) Text('★', style: TextStyle(color: kPurple2, fontSize: 10)),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill(this.label, this.color);
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .2),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color)),
    child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
  );
}

class _RoundScoreTable extends StatelessWidget {
  final String name0, name1;
  final int pts0, pts1, roem0, roem1, ms0, ms1, round;
  const _RoundScoreTable({
    required this.name0, required this.name1,
    required this.pts0, required this.pts1,
    required this.roem0, required this.roem1,
    required this.ms0, required this.ms1, required this.round,
  });

  @override Widget build(BuildContext context) {
    row(String lbl, String v0, String v1) => Row(children: [
      SizedBox(width: 80, child: Text(lbl, style: const TextStyle(color: kMuted, fontSize: 12))),
      Expanded(child: Text(v0, textAlign: TextAlign.center,
          style: const TextStyle(color: kText, fontWeight: FontWeight.bold))),
      Expanded(child: Text(v1, textAlign: TextAlign.center,
          style: const TextStyle(color: kText, fontWeight: FontWeight.bold))),
    ]);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 80),
          Expanded(child: Text(name0, textAlign: TextAlign.center,
              style: const TextStyle(color: kText, fontSize: 12), overflow: TextOverflow.ellipsis)),
          Expanded(child: Text(name1, textAlign: TextAlign.center,
              style: const TextStyle(color: kText, fontSize: 12), overflow: TextOverflow.ellipsis)),
        ]),
        const Divider(color: kBorder, height: 16),
        row('Punten', '$pts0', '$pts1'),
        const SizedBox(height: 4),
        row('Roem',   '$roem0', '$roem1'),
        const Divider(color: kBorder, height: 16),
        row('Totaal', '${ms0}', '${ms1}'),
      ]),
    );
  }
}
