import 'dart:math';
import 'dart:async';
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
import 'unthaldspultsje_ai.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';

const _pairs = 16;
const _cols  = 8;
const _emojis = [
  '🦁','🐯','🦊','🐻','🐼','🐨','🐸','🦋',
  '🌈','⭐','🍕','🎈','🚀','🌺','🎸','🦄',
];

class UnthaldspultsjeScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const UnthaldspultsjeScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<UnthaldspultsjeScreen> createState() => _UnthaldspultsjeState();
}

class _UnthaldspultsjeState extends State<UnthaldspultsjeScreen> with GameMixin {
  final _net = Network();
  final _session = SessionState();
  UnthaldspultsjeAI? _ai;

  List<String> _symbols   = [];
  List<bool>   _flipped   = [];
  List<bool>   _matched   = [];
  List<int>    _owner     = [];

  int _first = -1, _second = -1;
  bool _locked = false;
  int _turn = 1;
  int _s1 = 0, _s2 = 0;
  bool _ready = false;
  int _gameGen = 0;  // bumped on reset to invalidate stale AI callbacks

  int get _myId => _net.myIdx == 0 ? 1 : 2;
  bool get _isMyTurn => _turn == _myId && _ready;
  bool get _over => _ready && _s1 + _s2 == _pairs;

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _turn = widget.firstPlayer;
    if (_net.isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _ai = UnthaldspultsjeAI(d);
    }
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_net.isHost) {
      final seed = Random().nextInt(1000000);
      _setup(seed);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _net.send('UNT_SEED', {'seed': seed});
        // If AI goes first in solo mode
        if (_net.isSolo && _turn == 2) _aiTakeTurn();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _net.send('UNT_REQ');
      });
    }
  }

  void _setup(int seed, {int? firstPlayer}) {
    final rng = Random(seed);
    final cards = [..._emojis, ..._emojis]..shuffle(rng);
    _symbols = cards;
    _flipped  = List.filled(_pairs * 2, false);
    _matched  = List.filled(_pairs * 2, false);
    _owner    = List.filled(_pairs * 2, 0);
    _first = _second = -1; _locked = false;
    _turn = firstPlayer ?? widget.firstPlayer; _s1 = 0; _s2 = 0; _ready = true;
    _gameGen++;
  }

  void _tap(int idx) {
    if (!_isMyTurn || _locked || !_ready) return;
    if (_matched[idx] || _flipped[idx]) return;
    if (_first == idx) return;
    SoundPlayer.i.unthaldspultsjeFlip();
    HapticFeedback.selectionClick();

    setState(() => _flipped[idx] = true);
    _net.send('UNT_FLIP', {'i': idx});
    // AI observes the revealed card
    _ai?.observe(idx, _symbols[idx]);

    if (_first == -1) {
      _first = idx;
    } else {
      _second = idx;
      _locked = true;
      final i1 = _first, i2 = _second;
      final match = _symbols[i1] == _symbols[i2];

      if (match) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          HapticFeedback.mediumImpact();
          setState(() {
            _matched[i1] = _matched[i2] = true;
            _owner[i1] = _owner[i2] = _myId;
            if (_myId == 1) _s1++; else _s2++;
            _first = _second = -1; _locked = false;
          });
          _net.send('UNT_MATCH', {'i1': i1, 'i2': i2, 'p': _myId});
          // Human matched again — AI still waiting; no turn change
        });
      } else {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!mounted) return;
          setState(() {
            _flipped[i1] = _flipped[i2] = false;
            _first = _second = -1; _locked = false;
            _turn = _myId == 1 ? 2 : 1;
          });
          _net.send('UNT_HIDE', {'i1': i1, 'i2': i2});
          // Turn switched to AI
          if (_net.isSolo) _aiTakeTurn();
        });
      }
    }
  }

  void _aiTakeTurn() {
    if (!_net.isSolo || _ai == null || _turn != 2 || _over) return;
    final gen = _gameGen;
    _ai!.takeTurn(
      symbols: _symbols,
      matched: _matched,
      flipped: _flipped,
      onFirstPick: (idx) {
        if (!mounted || _turn != 2 || _gameGen != gen) return;
        _ai!.observe(idx, _symbols[idx]);
        setState(() { _flipped[idx] = true; _first = idx; });
      },
      onSecondPick: (idx) {
        if (!mounted || _turn != 2 || _gameGen != gen) return;
        _ai!.observe(idx, _symbols[idx]);
        setState(() { _flipped[idx] = true; _second = idx; _locked = true; });
        final i1 = _first, i2 = idx;
        final match = _symbols[i1] == _symbols[i2];
        if (match) {
          Future.delayed(const Duration(milliseconds: 700), () {
            if (!mounted) return;
            setState(() {
              _matched[i1] = _matched[i2] = true;
              _owner[i1] = _owner[i2] = 2;
              _s2++; _first = _second = -1; _locked = false;
            });
            // AI matched — take another turn
            if (!_over) _aiTakeTurn();
          });
        } else {
          Future.delayed(const Duration(milliseconds: 900), () {
            if (!mounted) return;
            setState(() {
              _flipped[i1] = _flipped[i2] = false;
              _first = _second = -1; _locked = false;
              _turn = 1; // back to human
            });
          });
        }
      },
    );
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'UNT_REQ':
        if (_net.isHost && _ready) {
          _net.send('UNT_FULL', {
            'symbols': _symbols,
            'matched': _matched,
            'flipped': _flipped,
            'owner':   _owner,
            'turn':    _turn,
            's1': _s1, 's2': _s2,
          });
        }
        break;
      case 'UNT_FULL':
        setState(() {
          _symbols = List<String>.from(msg['symbols'] as List);
          _matched = List<bool>.from(msg['matched'] as List);
          _owner   = List<int>.from(msg['owner'] as List);
          // Use transmitted flipped state if present, else reconstruct from matched
          if (msg['flipped'] != null) {
            _flipped = List<bool>.from(msg['flipped'] as List);
          } else {
            _flipped = List.filled(_pairs * 2, false);
            for (int i = 0; i < _pairs * 2; i++) {
              if (_matched[i]) _flipped[i] = true;
            }
          }
          _turn = msg['turn'] as int;
          _s1 = msg['s1'] as int; _s2 = msg['s2'] as int;
          _first = _second = -1; _locked = false; _ready = true;
        });
        break;
      case 'UNT_SEED':
        setState(() => _setup(msg['seed'] as int));
        break;
      case 'UNT_FLIP':
        setState(() => _flipped[msg['i'] as int] = true);
        break;
      case 'UNT_MATCH':
        final i1 = msg['i1'] as int, i2 = msg['i2'] as int, p = msg['p'] as int;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          setState(() {
            _matched[i1] = _matched[i2] = true;
            _owner[i1] = _owner[i2] = p;
            if (p == 1) _s1++; else _s2++;
          });
        });
        break;
      case 'UNT_HIDE':
        final i1 = msg['i1'] as int, i2 = msg['i2'] as int;
        setState(() => _locked = true);
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!mounted) return;
          setState(() {
            _flipped[i1] = _flipped[i2] = false;
            _first = _second = -1; _locked = false;
            _turn = _turn == 1 ? 2 : 1;
          });
          if (_isMyTurn && !_over) turnChanged();
        });
        break;
      case 'GAME_RESET':
        if (!_net.isHost) {
          resetConfetti();
          resetStats();
          setState(() => _setup(msg['seed'] as int, firstPlayer: msg['first'] as int? ?? 1));
        }
        break;
    }
  }


  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          // UNT_REQ/UNT_FULL already implement full state sync
          if (_net.isHost) {
            // Re-broadcast full state to rejoiners
            if (_ready) {
              _net.send('UNT_FULL', {
                'symbols': _symbols,
                'matched': _matched,
                'flipped': _flipped,
                'owner':   _owner,
                'turn':    _turn,
                's1': _s1, 's2': _s2,
              });
            }
          } else {
            _net.send('UNT_REQ');
          }
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  @override Widget build(BuildContext ctx) {
    final p1 = widget.players[0], p2 = widget.players[1];
    int winner = 0;
    if (_over) winner = _s1 > _s2 ? 1 : _s2 > _s1 ? 2 : 3;

    return GameScaffold(
        key: scaffoldKey,
      title: L.unthaldspultsje.gameName,
      players: widget.players, chatMessages: chatMessages, onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.unthaldspultsje.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: _over ? -1 : _turn - 1,
          scores: [_s1, _s2],
          scoreLabel: L.common.pairsLabel,
        ),
        GameStatusBar(
          text: !_ready ? L.unthaldspultsje.loading
              : _over ? null
              : (_isMyTurn ? L.unthaldspultsje.yourTurn : L.unthaldspultsje.opponentTurn.fmt({'player': _turn==1?p1.name:p2.name})),
          textColor: _ready && !_over && _isMyTurn ? kGreen : null,
        ),

        // Card grid — fixed 8×4 grid, identical on all screen sizes for fairness
        Expanded(child: !_ready
          ? const Center(child: CircularProgressIndicator(color: kPurple))
          : Center(child: SingleChildScrollView(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _cols,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                  childAspectRatio: 1),
                itemCount: _pairs * 2,
                itemBuilder: (_, i) => _Card(
                  symbol: _symbols[i],
                  flipped: _flipped[i],
                  matched: _matched[i],
                  matchColor: _matched[i] ? (_owner[i]==1 ? p1.color : p2.color) : null,
                  canTap: _isMyTurn && !_matched[i] && !_flipped[i] && !_locked,
                  onTap: () => _tap(i),
                ),
              ),
            ))),

        if (_over) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: winner == 3 ? -1 : winner - 1,
            onFirstRender: () { final wi = winner == 3 ? -1 : winner - 1; fireConfettiOnce(wi); recordResult('unthaldspultsje', wi); if (_net.isHost) _session.advanceGame(); },
            scores: [
              (label: widget.players[0].name, value: '$_s1'),
              (label: widget.players[1].name, value: '$_s2'),
            ],
          ),
          GameOverActions(players: widget.players, sendReset: false, onReset: () {
            resetConfetti(); resetStats();
            _ai?.reset();
            final first = _session.nextStarterFor(2);
            final seed = Random().nextInt(1000000);
            setState(() => _setup(seed, firstPlayer: first));
            _net.send('GAME_RESET', {'seed': seed, 'first': first});
            if (_net.isSolo && first == 2) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _aiTakeTurn();
              });
            }
          }),
        ] else const SizedBox(height: 4),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final String symbol;
  final bool flipped, matched, canTap;
  final Color? matchColor;
  final VoidCallback onTap;
  const _Card({required this.symbol, required this.flipped,
    required this.matched, required this.canTap, this.matchColor, required this.onTap});

  @override Widget build(BuildContext ctx) => GestureDetector(
    onTap: canTap || flipped ? onTap : null,
    child: LayoutBuilder(builder: (_, c) {
      final sz = c.maxWidth;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: sz, height: sz,
        decoration: BoxDecoration(
          color: matched
            ? (matchColor ?? kGreen).withValues(alpha: .25)
            : flipped ? kPurple2.withValues(alpha: .45) : const Color(0xFF2A1A5E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: matched ? (matchColor ?? kGreen).withValues(alpha: .8)
              : flipped ? kPurple : kBorder,
            width: matched ? 2 : 1)),
        child: Padding(
          padding: EdgeInsets.all(sz * 0.03),
          child: FittedBox(
            fit: BoxFit.contain,
            child: flipped || matched
              ? Text(symbol, style: const TextStyle(fontFamilyFallback: ['NotoColorEmoji']))
              : Text('?', style: TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.bold,
                  fontSize: sz)),
          ),
        ),
      );
    }),
  );
}
