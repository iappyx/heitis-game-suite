import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/wake_lock.dart';
import '../../core/sound_player.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';
import '../../l10n/app_localizations.dart';

// ── Word list ─────────────────────────────────────────────────────────────────
const _words = [
  // 3-letter
  'hûs', 'kat', 'hûn', 'iis', 'âld', 'nij',
  // 4-letter
  'beam', 'fyts', 'rein', 'snie', 'fisk', 'bern', 'boek', 'gêrs', 'tiid', 'bôle',
  // 5-letter
  'mûtse', 'broek', 'tafel', 'stoel', 'lampe', 'brêge', 'swiet',
  // 6-letter
  'tsjiis', 'swimme', 'rinne', 'sjonge', 'spylje',
  // nature & animals
  'hynder', 'skiep', 'foks', 'earn', 'bij', 'kikkert', 'blommen', 'fûgels',
  // everyday
  'moarn', 'wetter', 'brea', 'molke', 'freon', 'thús', 'moai', 'leave',
  // longer / harder
  'skoalle', 'famylje', 'simmerdei', 'berneboek', 'waarmte',
  'blêdzje', 'ferstean', 'dreame', 'genietsje', 'aventoer',
  'freonskip', 'bliidskip', 'tsiisbrêge', 'wolkjacht', 'nachtwacht',
];

const _wordsPerGame   = 10;
const _secondsPerWord = 20;

// ── Screen ────────────────────────────────────────────────────────────────────

class WurdspulScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;

  const WurdspulScreen({
    super.key,
    required this.players,
    required this.firstPlayer,
  });

  @override State<WurdspulScreen> createState() => _WurdspulState();
}

class _WurdspulState extends State<WurdspulScreen> with GameMixin {
  final Network _net = Network();
  final _rng         = math.Random();


  List<String> _wordQueue = [];
  int    _wordIdx    = 0;
  String _currentWord = '';
  List<String> _scrambled = [];
  List<String> _tapped    = [];
  List<int>    _tappedIdx = [];
  bool   _answered   = false;
  bool   _correct    = false;
  String _feedback   = '';
  Timer? _timer;
  Timer? _syncReqTimer; // joiner: retries WSP_SYNC_REQ until the first word arrives
  int    _secondsLeft = _secondsPerWord;

  // Host-only round arbitration: a word ends when someone answers correctly,
  // when every player has failed/skipped, or when the host's timer runs out.
  bool _roundOpen = false;
  final Set<int> _failed = {};
  int _roundSeq = 0; // guards delayed next-word calls against stale rounds

  final List<int> _scores = [0, 0];
  int _winner = 0; // 0=playing 1=p1 2=p2 3=draw

  int  _personalBest = 0;
  bool _newBest      = false;

  bool get _isSolo => _net.isSolo;
  bool get _isHost => _net.isHost;

  @override List<Player> get gamePlayers => widget.players;

  @override
  void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    if (_isSolo) _loadBest();
    if (_isHost) {
      _startGame();
    } else {
      _startSyncRequests();
    }
  }

  /// Joiner: the host's opening WSP_WORDS/WSP_WORD may be sent before this
  /// screen subscribes — ask for the state until a word has arrived.
  void _startSyncRequests() {
    _syncReqTimer?.cancel();
    int tries = 0;
    _syncReqTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (!mounted || _currentWord.isNotEmpty || tries >= 4) { t.cancel(); return; }
      tries++;
      _net.send('WSP_SYNC_REQ');
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _currentWord.isEmpty) _net.send('WSP_SYNC_REQ');
    });
  }

  @override
  void dispose() {
    msgSub?.cancel();
    _timer?.cancel();
    _syncReqTimer?.cancel();
    WakeLock.release();
    super.dispose();
  }

  Future<void> _loadBest() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _personalBest = p.getInt('wurdspul_best') ?? 0);
  }

  Future<void> _saveBest(int score) async {
    if (score > _personalBest) {
      final p = await SharedPreferences.getInstance();
      await p.setInt('wurdspul_best', score);
      if (mounted) setState(() { _personalBest = score; _newBest = true; });
    }
  }

  // ── Game flow ────────────────────────────────────────────────────────────────

  void _startGame() {
    final pool = List<String>.from(_words)..shuffle(_rng);
    _wordQueue = pool.take(_wordsPerGame).toList();
    if (!_isSolo) _net.send('WSP_WORDS', {'words': _wordQueue});
    _loadWord(0);
  }

  void _loadWord(int idx) {
    if (idx >= _wordsPerGame) { _endGame(); return; }
    final word = _wordQueue[idx];
    final sc   = _scramble(word);
    setState(() {
      _wordIdx     = idx;
      _currentWord = word;
      _scrambled   = sc;
      _tapped      = [];
      _tappedIdx   = [];
      _answered    = false;
      _correct     = false;
      _feedback    = '';
      _secondsLeft = _secondsPerWord;
    });
    _roundOpen = true;
    _failed.clear();
    _roundSeq++;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
    if (!_isSolo) _net.send('WSP_WORD', {'idx': idx, 'scrambled': sc});
  }

  List<String> _scramble(String word) {
    final letters = word.split('');
    for (int i = 0; i < 20; i++) {
      letters.shuffle(_rng);
      if (letters.join() != word) break;
    }
    return letters;
  }

  void _onTick(Timer t) {
    if (!mounted) { t.cancel(); return; }
    setState(() => _secondsLeft--);
    if (_secondsLeft <= 0) {
      t.cancel();
      if (_isHost) {
        // Host's timer decides: time's up ends the word for everyone
        if (_roundOpen) {
          if (!_answered) SoundPlayer.i.rupsenBust();
          _closeRound(-1);
        }
      } else if (!_answered) {
        _revealWrong();
      }
    }
  }

  KeyEventResult _handleHwKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _untapLast();
      return KeyEventResult.handled;
    }
    final label = key.keyLabel;
    if (label.length == 1 && RegExp(r'[a-zA-Z]').hasMatch(label)) {
      final letter = label.toLowerCase();
      // Find the first untapped occurrence of this letter in scrambled list
      for (int i = 0; i < _scrambled.length; i++) {
        if (_tappedIdx.contains(i)) continue;
        if (_scrambled[i].toLowerCase() == letter) {
          _tapLetter(i);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _tapLetter(int scramIdx) {
    if (_answered) return;
    SoundPlayer.i.sudokuDuelCell();
    setState(() {
      _tapped.add(_scrambled[scramIdx]);
      _tappedIdx.add(scramIdx);
    });
    if (_tapped.length == _currentWord.length) _checkAnswer();
  }

  void _untapLast() {
    if (_answered || _tapped.isEmpty) return;
    setState(() { _tapped.removeLast(); _tappedIdx.removeLast(); });
  }

  void _checkAnswer() {
    // Timer keeps running: the other player may still be solving this word
    if (_tapped.join() == _currentWord) _revealCorrect(); else _revealWrong();
  }

  String get _otherName {
    if (widget.players.length < 2) return '';
    return widget.players[_net.myIdx == 0 ? 1 : 0].name;
  }

  void _revealCorrect() {
    SoundPlayer.i.rupsenClaim();
    final myIdx = _net.myIdx;
    if (_isHost) {
      // Host awards its own point (if the round is still open)
      _closeRound(myIdx);
      return;
    }
    // Joiner: show optimistically, but the host awards the point
    setState(() { _answered = true; _correct = true; _feedback = L.wurdspul.correct; });
    _net.send('WSP_ANSWER', {'idx': _wordIdx, 'correct': true, 'player': myIdx});
  }

  void _revealWrong() {
    SoundPlayer.i.rupsenBust();
    if (_isHost) {
      if (!_roundOpen) return;
      _failed.add(_net.myIdx);
      if (_failed.length >= (_isSolo ? 1 : 2)) { _closeRound(-1); return; }
      setState(() { _answered = true; _correct = false;
        _feedback = L.wurdspul.wrongWaiting.fmt({'player': _otherName}); });
      return;
    }
    setState(() { _answered = true; _correct = false;
      _feedback = L.wurdspul.wrongWaiting.fmt({'player': _otherName}); });
    _net.send('WSP_ANSWER', {'idx': _wordIdx, 'correct': false, 'player': _net.myIdx});
  }

  /// Host: end the current word. [winner] = player idx who answered correctly,
  /// or -1 when nobody did (all failed/skipped or time ran out).
  void _closeRound(int winner) {
    if (!_isHost || !_roundOpen) return;
    _roundOpen = false;
    _timer?.cancel();
    if (winner >= 0) _scores[winner]++;
    _applyRoundResult(winner);
    if (!_isSolo) {
      _net.send('WSP_RESULT', {'idx': _wordIdx, 'winner': winner, 'scores': _scores});
    }
    final seq = _roundSeq;
    Future.delayed(Duration(milliseconds: winner >= 0 ? 1200 : 1600), () {
      if (mounted && _isHost && seq == _roundSeq && _winner == 0) _loadWord(_wordIdx + 1);
    });
  }

  /// Show the outcome of the current word on this device.
  void _applyRoundResult(int winner) {
    setState(() {
      _answered = true;
      if (winner == _net.myIdx) {
        _correct  = true;
        _feedback = L.wurdspul.correct;
      } else if (winner >= 0 && winner < widget.players.length) {
        _correct  = false;
        _feedback = L.wurdspul.otherFirst.fmt(
            {'player': widget.players[winner].name, 'word': _currentWord});
      } else {
        _correct  = false;
        _feedback = L.wurdspul.wrong.fmt({'word': _currentWord});
      }
    });
  }

  void _skip() { if (!_answered) _revealWrong(); }

  void _endGame() {
    _timer?.cancel();
    _roundOpen = false;
    int w;
    if (_isSolo) {
      w = 1;
      _saveBest(_scores[0]);
    } else {
      if (_scores[0] > _scores[1])      w = 1;
      else if (_scores[1] > _scores[0]) w = 2;
      else                               w = 3;
    }
    if (!_isSolo) _net.send('WSP_GAME_OVER', {'w': w, 'scores': _scores});
    setState(() => _winner = w);
  }

  void _reset() {
    _timer?.cancel();
    setState(() { _scores[0] = 0; _scores[1] = 0; _winner = 0; _newBest = false; });
    resetConfetti(); resetStats();
    if (_isHost) _startGame();
  }

  // ── Network ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _syncPayload() => {
    'words':    _wordQueue,
    'wordIdx':  _wordIdx,
    'scrambled':_scrambled,
    'scores':   _scores,
    'winner':   _winner,
    // Round state (host's own `_answered` must not lock the joiner's input)
    'answered': !_roundOpen,
    'correct':  _correct,
    'secsLeft': _secondsLeft,
  };

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'WSP_WORDS':
        if (!_isHost) _wordQueue = List<String>.from(msg['words'] as List);
        break;

      case 'WSP_SYNC_REQ':
        // Joiner started late or reconnected — host sends full current state
        if (_isHost && !_isSolo && _wordQueue.isNotEmpty) {
          _net.sendTo(fromIdx, 'WSP_SYNC', _syncPayload());
        }
        break;

      case 'WSP_SYNC':
        if (!_isHost) {
          final syncWords = List<String>.from(msg['words'] as List);
          final syncIdx   = msg['wordIdx'] as int;
          if (syncIdx >= syncWords.length) break;
          // Duplicate/late sync for the word we're already on: ignore it so
          // local progress (taps, answer, score, timer) isn't reset.
          if (_currentWord.isNotEmpty && syncIdx == _wordIdx &&
              syncWords.join(',') == _wordQueue.join(',')) {
            break;
          }
          _timer?.cancel();
          setState(() {
            _wordQueue   = syncWords;
            _wordIdx     = syncIdx;
            _currentWord = _wordQueue[_wordIdx];
            _scrambled   = List<String>.from(msg['scrambled'] as List);
            _scores[0]   = (msg['scores'] as List)[0] as int;
            _scores[1]   = (msg['scores'] as List)[1] as int;
            _winner      = msg['winner'] as int;
            _answered    = msg['answered'] as bool;
            _correct     = msg['correct'] as bool;
            _secondsLeft = msg['secsLeft'] as int;
            _tapped = []; _tappedIdx = [];
          });
          if (_winner == 0 && !_answered) {
            _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
          }
        }
        break;

      case 'WSP_WORD':
        if (!_isHost) {
          // Missed WSP_WORDS → queue empty/short: ask for full state instead
          if ((msg['idx'] as int) >= _wordQueue.length) {
            _net.send('WSP_SYNC_REQ');
            break;
          }
          setState(() {
            _wordIdx     = msg['idx'] as int;
            _currentWord = _wordQueue[_wordIdx];
            _scrambled   = List<String>.from(msg['scrambled'] as List);
            _tapped = []; _tappedIdx = [];
            _answered = false; _correct = false; _feedback = '';
            _secondsLeft = _secondsPerWord;
          });
          _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
        }
        break;

      case 'WSP_ANSWER':
        // Host arbitrates: first correct answer for the open word wins it
        if (!_isHost || !_roundOpen) break;
        if ((msg['idx'] as int? ?? -1) != _wordIdx) break;
        if (fromIdx < 0 || fromIdx >= _scores.length) break;
        if (msg['correct'] as bool) {
          _closeRound(fromIdx);
        } else {
          _failed.add(fromIdx);
          if (_failed.length >= 2) {
            if (!_answered) SoundPlayer.i.rupsenBust();
            _closeRound(-1);
          }
        }
        break;

      case 'WSP_RESULT':
        if (!_isHost) {
          if ((msg['idx'] as int) != _wordIdx) break;
          final winner = msg['winner'] as int;
          _timer?.cancel();
          if (winner != _net.myIdx && !_answered) SoundPlayer.i.rupsenBust();
          _scores[0] = (msg['scores'] as List)[0] as int;
          _scores[1] = (msg['scores'] as List)[1] as int;
          _applyRoundResult(winner);
        }
        break;

      case 'WSP_GAME_OVER':
        if (!_isHost) {
          setState(() {
            _winner = msg['w'] as int;
            _scores[0] = (msg['scores'] as List)[0] as int;
            _scores[1] = (msg['scores'] as List)[1] as int;
          });
        }
        break;

      case 'GAME_RESET':
        if (!_isHost) {
          resetConfetti();
          resetStats();
          setState(() { _scores[0] = 0; _scores[1] = 0; _winner = 0; });
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
          if (_isHost) {
            // Re-send words + current word to reconnected joiner
            if (_wordQueue.isNotEmpty) {
              _net.send('WSP_WORDS', {'words': _wordQueue});
              _net.send('WSP_SYNC', _syncPayload());
            }
          } else {
            _net.send('WSP_SYNC_REQ');
          }
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (r) => false),
      ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      key: scaffoldKey,
      title: L.wurdspul.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: (t) => sendChat(t),
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.wurdspul.rules,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          return _handleHwKey(event.logicalKey);
        },
        child: Column(children: [
        if (widget.players.length > 1)
          PlayerBar(players: widget.players, activeIdx: -1, scores: _scores),
        const GameStatusBar(),
        Expanded(child: _winner != 0 ? _buildResult() : _buildGame()),
      ])),
    );
  }

  Widget _buildResult() {
    final winnerIdx = _winner == 3 ? -1 : _winner - 1;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_isSolo) ...[
          const SizedBox(height: 24),
          Text(
            L.wurdspul.scoreLabel.fmt({'score': _scores[0]}),
            style: const TextStyle(color: kText, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_newBest)
            Text(L.wurdspul.newBest,
              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 20, fontWeight: FontWeight.bold))
          else
            Text(L.wurdspul.personalBest.fmt({'score': _personalBest}),
              style: const TextStyle(color: kMuted, fontSize: 16)),
        ] else
          GameResultBanner(
            players: widget.players,
            winnerIdx: winnerIdx,
            onFirstRender: () { fireConfettiOnce(winnerIdx); recordResult('wurdspul', winnerIdx); if (_isHost) SessionState().advanceGame(); },
          ),
        const SizedBox(height: 24),
        GameOverActions(players: widget.players, onReset: _reset),
      ],
    );
  }

  Widget _buildGame() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildHeader(),
        const SizedBox(height: 20),
        _buildScrambledLetters(),
        const SizedBox(height: 16),
        _buildAnswerSlots(),
        const SizedBox(height: 16),
        _buildFeedback(),
        const Spacer(),
        if (!_answered) TextButton(
          onPressed: _skip,
          child: Text(L.wurdspul.skip,
            style: const TextStyle(color: kMuted, fontSize: 14)),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildHeader() {
    final total = _wordQueue.isEmpty ? _wordsPerGame : _wordQueue.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(L.wurdspul.roundLabel.fmt({'n': _wordIdx + 1, 'total': total}),
          style: const TextStyle(color: kMuted, fontSize: 13)),
        SizedBox(width: 44, height: 44,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: _secondsLeft / _secondsPerWord,
              backgroundColor: kBorder,
              color: _secondsLeft <= 5 ? Colors.red : kPurple,
              strokeWidth: 4,
            ),
            Text('$_secondsLeft', style: TextStyle(
              color: _secondsLeft <= 5 ? Colors.red : kText,
              fontSize: 14, fontWeight: FontWeight.bold)),
          ])),
        if (_isSolo)
          Text(L.wurdspul.scoreLabel.fmt({'score': _scores[0]}),
            style: const TextStyle(color: kMuted, fontSize: 13))
        else
          const SizedBox(width: 60),
      ],
    );
  }

  Widget _buildScrambledLetters() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(children: [
        Text(L.wurdspul.scrambleLabel,
          style: const TextStyle(color: kMuted, fontSize: 13)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8, runSpacing: 8,
          alignment: WrapAlignment.center,
          children: List.generate(_scrambled.length, (i) {
            final used = _tappedIdx.contains(i);
            return GestureDetector(
              onTap: used || _answered ? null : () => _tapLetter(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 48, height: 52,
                decoration: BoxDecoration(
                  color: used ? kBorder : kPurple.withAlpha(220),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: used ? kBorder : kPurple, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(_scrambled[i].toUpperCase(),
                  style: TextStyle(
                    color: used ? kMuted : Colors.white,
                    fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            );
          }),
        ),
      ]),
    );
  }

  Widget _buildAnswerSlots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Wrap(spacing: 6,
          children: List.generate(_currentWord.length, (i) {
            final filled = i < _tapped.length;
            Color borderColor = kBorder;
            Color bgColor     = kCard;
            if (_answered && filled) {
              borderColor = _correct ? Colors.green : Colors.red;
              bgColor     = _correct ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30);
            }
            return Container(
              width: 42, height: 46,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                filled ? _tapped[i].toUpperCase() : '',
                style: TextStyle(
                  color: _answered ? (_correct ? Colors.green : Colors.red) : kText,
                  fontSize: 20, fontWeight: FontWeight.bold)),
            );
          }),
        ),
        if (_tapped.isNotEmpty && !_answered) ...[
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _untapLast,
            child: Container(
              width: 42, height: 46,
              decoration: BoxDecoration(
                color: kCard, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBorder, width: 2)),
              alignment: Alignment.center,
              child: const Icon(Icons.backspace_outlined, color: kMuted, size: 20),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFeedback() {
    if (_feedback.isEmpty) return const SizedBox(height: 24);
    return Text(_feedback,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: _correct ? Colors.green : Colors.red,
        fontSize: 16, fontWeight: FontWeight.bold));
  }
}
