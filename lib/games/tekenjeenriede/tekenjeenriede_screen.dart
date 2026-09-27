import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'tekenjeenriede_words.dart';

// ── Constants ─────────────────────────────────────────────────────────────────
const _kRoundSecs  = 80;  // seconds per round
const _kRounds     = 3;   // total rounds per player set (each player draws once per round)

// ── Stroke data ───────────────────────────────────────────────────────────────
// Points are always stored as NORMALISED coords (0..1) so strokes look the
// same regardless of whether sender/receiver has a phone or tablet screen.
class _Stroke {
  final List<Offset> points; // normalised 0..1
  final Color        color;
  final double       width;  // also normalised: fraction of canvas width
  final bool         isErase;
  _Stroke({required this.points, required this.color,
           required this.width, required this.isErase});

  // Normalise pixel coords coming from the drawer's canvas
  static _Stroke fromPixels({
    required List<Offset> pixelPoints,
    required Color color,
    required double pixelWidth,
    required bool isErase,
    required Size canvasSize,
  }) {
    final cw = canvasSize.width;
    final ch = canvasSize.height;
    return _Stroke(
      points:  pixelPoints.map((p) => Offset(p.dx / cw, p.dy / ch)).toList(),
      color:   color,
      width:   pixelWidth / cw, // store as fraction of width
      isErase: isErase,
    );
  }

  // Wire: points already normalised, width already normalised
  Map<String, dynamic> toWire() => {
    'pts': points.expand((p) => [p.dx, p.dy]).toList(),
    'c':   color.value,
    'w':   width,
    'e':   isErase,
  };

  factory _Stroke.fromWire(Map<String, dynamic> m) {
    final pts = (m['pts'] as List).map((v) => (v as num).toDouble()).toList();
    final offsets = <Offset>[];
    for (int i = 0; i < pts.length - 1; i += 2) {
      offsets.add(Offset(pts[i], pts[i + 1]));
    }
    return _Stroke(
      points:  offsets,
      color:   Color(m['c'] as int),
      width:   (m['w'] as num).toDouble(),
      isErase: m['e'] as bool,
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────
class TekenjeEnRiedeScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const TekenjeEnRiedeScreen(
      {super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<TekenjeEnRiedeScreen> createState() => _TekenjeEnRiedeState();
}

class _TekenjeEnRiedeState extends State<TekenjeEnRiedeScreen> with GameMixin {
  final _net  = Network();

  // ── Game logic ───────────────────────────────────────────────────────────────
  int  _round      = 1;   // 1-based
  int  _drawerIdx  = 0;   // index into widget.players
  String _word       = '';  // display: drawer sees actual word, guessers see '???'
  String _secretWord = '';  // always the actual word — used for answer checking
  List<String> _wordChoices = [];
  List<List<String>> _usedWords = [];

  // Scores: one per player
  late List<int> _scores;

  // Timer
  Timer?  _timer;
  int     _secsLeft = _kRoundSecs;

  // Phase: 'choosing' | 'drawing' | 'roundOver' | 'gameOver'
  String _phase = 'choosing';
  // Host-declared winner from PCT_GAME_OVER (0-based, -1 = draw); null until received
  int? _hostWinnerIdx;

  // Who guessed correctly this round (playerIdx set)
  Set<int> _guessedIdx = {};
  int?     _firstGuesserIdx;

  // Canvas
  final List<_Stroke>    _strokes    = [];
  _Stroke?               _currentStroke;
  final _canvasKey        = GlobalKey();
  Size?                  _canvasSize;

  // Drawing tools
  Color  _penColor = Colors.black;
  double _penWidth = 4.0;
  bool   _erasing  = false;

  // Input field
  final _guessCtrl = TextEditingController();
  bool  _myGuessCorrect = false;

  bool get _iAmDrawer => _drawerIdx == _net.myIdx;
  bool get _isHost    => _net.isHost;

  // Word language (chosen by host before game starts)
  String _wordLang = 'en'; // 'fy' | 'nl' | 'en'
  bool   _langConfirmed = false; // true once host picks or PCT_LANG received

  // Verbal mode: guess out loud instead of typing, no timer
  bool _verbal = false;
  Set<int> _verbalConfirmed = {}; // player indices who tapped "Got it!"

  // Progressive letter hints (host-driven)
  final Set<int> _revealedPositions = {};
  bool _hint1Sent = false; // 60% time remaining
  bool _hint2Sent = false; // 35% time remaining

  // Network: batch strokes to send every 50ms
  Timer?         _strokeFlushTimer;
  List<_Stroke>  _pendingStrokes = [];

  // ── In-canvas guess feed (wrong guesses shown on canvas, not in chat) ────────
  // Each entry: {name, guess, ts} — kept for _kGuessFeedSecs seconds then removed
  static const _kGuessFeedSecs = 6;
  static const _kGuessFeedMax  = 6; // max visible at once
  final List<Map<String, dynamic>> _recentGuesses = [];
  Timer? _guessFeedTimer;

  @override List<Player> get gamePlayers => widget.players;

  @override
  void initState() {
    super.initState();
    _scores = List.filled(widget.players.length, 0);
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    _drawerIdx = widget.firstPlayer - 1;
    _wordLang  = L.lang.name; // default to app language
    if (_isHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLangDialog());
    }
  }

  @override
  void dispose() {
    msgSub?.cancel();
    _timer?.cancel();
    _strokeFlushTimer?.cancel();
    _guessFeedTimer?.cancel();
    _guessCtrl.dispose();
    WakeLock.release();
    super.dispose();
  }

  // ── Game flow ─────────────────────────────────────────────────────────────────

  // ── Language picker (host only, shown once at start) ─────────────────────────
  void _showLangDialog() {
    final s = L.tekenjeenriede;
    String selected = _wordLang;
    bool verbal = _verbal;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          backgroundColor: kCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(s.chooseLang,
            style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s.chooseLangHint, style: const TextStyle(color: kMuted, fontSize: 13)),
            const SizedBox(height: 16),
            for (final lang in [('fy', '🇳🇱 Frysk'), ('nl', '🇳🇱 Nederlands'), ('en', '🇬🇧 English')])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () { HapticFeedback.selectionClick(); setDlg(() => selected = lang.$1); },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: selected == lang.$1 ? kPurple2.withValues(alpha: .2) : kBg2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected == lang.$1 ? kPurple2 : kBorder,
                        width: selected == lang.$1 ? 2 : 1),
                    ),
                    child: Text(lang.$2,
                      style: TextStyle(
                        color: selected == lang.$1 ? kPurple2 : kText,
                        fontSize: 16,
                        fontWeight: selected == lang.$1
                            ? FontWeight.bold : FontWeight.normal)),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(s.chooseMode, style: const TextStyle(color: kMuted, fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); setDlg(() => verbal = false); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: !verbal ? kPurple2.withValues(alpha: .2) : kBg2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: !verbal ? kPurple2 : kBorder,
                      width: !verbal ? 2 : 1)),
                  child: Column(children: [
                    Icon(Icons.keyboard, color: !verbal ? kPurple2 : kMuted, size: 22),
                    const SizedBox(height: 4),
                    Text(s.modeTyping, style: TextStyle(
                      color: !verbal ? kPurple2 : kMuted, fontSize: 12,
                      fontWeight: !verbal ? FontWeight.bold : FontWeight.normal),
                      textAlign: TextAlign.center),
                  ]),
                ),
              )),
              const SizedBox(width: 8),
              Expanded(child: GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); setDlg(() => verbal = true); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: verbal ? kPurple2.withValues(alpha: .2) : kBg2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: verbal ? kPurple2 : kBorder,
                      width: verbal ? 2 : 1)),
                  child: Column(children: [
                    Icon(Icons.record_voice_over, color: verbal ? kPurple2 : kMuted, size: 22),
                    const SizedBox(height: 4),
                    Text(s.modeVerbal, style: TextStyle(
                      color: verbal ? kPurple2 : kMuted, fontSize: 12,
                      fontWeight: verbal ? FontWeight.bold : FontWeight.normal),
                      textAlign: TextAlign.center),
                  ]),
                ),
              )),
            ]),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _wordLang = selected;
                  _langConfirmed = true;
                  _verbal = verbal;
                });
                // Broadcast chosen language + mode to all players
                _net.send('TEK_LANG', {'lang': selected, 'verbal': verbal});
                _beginChoosing();
              },
              child: Text(s.startGame,
                style: const TextStyle(color: kPurple2, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }),
    );
  }

  void _beginChoosing() {
    _timer?.cancel();
    final choices = kPickWordChoices(_wordLang, _usedWords);
    setState(() {
      _phase       = 'choosing';
      _word        = '';
      _secretWord  = '';
      _strokes.clear();
      _guessedIdx.clear(); _verbalConfirmed.clear();
      _firstGuesserIdx = null;
      _myGuessCorrect  = false;
      _secsLeft        = _kRoundSecs;
      _revealedPositions.clear();
      _hint1Sent = false;
      _hint2Sent = false;
      // Always store choices on host (needed to validate PCT_WORD_CHOSEN).
      // When host is NOT the drawer the UI never shows _wordChoices — they
      // are only used server-side for word validation.
      _wordChoices = choices;
    });
    _recentGuesses.clear();
    _guessFeedTimer?.cancel();
    _guessFeedTimer = null;

    // Broadcast drawer identity and round — NO choices in the broadcast.
    // Choices go exclusively to the drawer via sendTo (private channel).
    _net.send('TEK_CHOOSING', {
      'drawer': _drawerIdx,
      'round':  _round,
    });

    // Send choices only to the drawer (private — other players never see them).
    // When host IS the drawer, they already have choices in _wordChoices above.
    if (!_iAmDrawer) {
      _net.sendTo(_drawerIdx, 'TEK_CHOICES', {'choices': choices});
    }
  }

  // Called either directly (when I am the drawer) or from PCT_WORD_CHOSEN handler
  // (host resolving a joiner drawer's choice). No _iAmDrawer guard here.
  void _onWordChosen(String word) {
    _usedWords.add(kTekenjeEnRiedeWords.firstWhere(
      (w) => w.contains(word), orElse: () => [word, word, word]));
    setState(() {
      _secretWord = word;
      _word       = _iAmDrawer ? word : List.filled(word.length, '_').join(' ');
      _phase      = 'drawing';
    });
    // Send word ONLY to the drawer (if the drawer is a non-host joiner).
    // All other non-host players receive only the word length — they must guess.
    // The word is revealed to everyone at round-end via PCT_ROUND_OVER.
    for (int i = 0; i < widget.players.length; i++) {
      if (i == _net.myIdx) continue; // don't send to self (host)
      if (i == _drawerIdx) {
        // Drawer: gets the actual word so they can see what to draw
        _net.sendTo(i, 'TEK_START', {
          'len':    word.length,
          'drawer': _drawerIdx,
          'word':   word,
        });
      } else {
        // Guesser: only gets the length — no word!
        _net.sendTo(i, 'TEK_START', {
          'len':    word.length,
          'drawer': _drawerIdx,
        });
      }
    }
    if (!_verbal) _startTimer();
  }

  void _startTimer() {
    if (_verbal) return; // no timer in verbal mode
    _timer?.cancel();
    _secsLeft = _kRoundSecs;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secsLeft--);
      // Host: send progressive letter hints when no one has guessed yet
      if (_isHost && _guessedIdx.isEmpty && _secretWord.isNotEmpty) {
        final pct = _secsLeft / _kRoundSecs; // fraction remaining
        if (pct <= 0.60 && !_hint1Sent) {
          _hint1Sent = true;
          _sendLetterHint();
        } else if (pct <= 0.35 && !_hint2Sent) {
          _hint2Sent = true;
          _sendLetterHint();
        }
      }
      if (_secsLeft <= 0) {
        _timer?.cancel();
        _endRound(guessed: false);
      }
    });
  }

  /// Pick a random unrevealed letter position and broadcast it.
  void _sendLetterHint() {
    final len = _secretWord.length;
    // Build list of positions not yet revealed (skip spaces/hyphens)
    final candidates = <int>[];
    for (int i = 0; i < len; i++) {
      if (!_revealedPositions.contains(i) && _secretWord[i] != ' ' && _secretWord[i] != '-') {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) return;
    final pos = candidates[Random().nextInt(candidates.length)];
    _revealedPositions.add(pos);
    // Update host's own word display (if host is a guesser)
    if (!_iAmDrawer) {
      setState(() => _word = _buildHintDisplay());
    }
    // Broadcast to all players
    _net.send('TEK_HINT', {
      'pos': pos,
      'letter': _secretWord[pos],
    });
  }

  /// Build the underscore display with revealed letters filled in.
  String _buildHintDisplay() {
    final buf = StringBuffer();
    for (int i = 0; i < _secretWord.length; i++) {
      if (i > 0 && _secretWord[i] != ' ' && (i < 1 || _secretWord[i - 1] != ' ')) buf.write(' ');
      if (_secretWord[i] == ' ') {
        buf.write('   '); // wide gap between words
      } else if (_secretWord[i] == '-') {
        buf.write('-');
      } else if (_revealedPositions.contains(i)) {
        buf.write(_secretWord[i]);
      } else {
        buf.write('_');
      }
    }
    return buf.toString();
  }

  void _endRound({required bool guessed}) {
    _timer?.cancel();
    if (!_isHost) return; // only host drives round-end logic; joiner waits for PCT_ROUND_OVER
    if (_phase == 'roundOver' || _phase == 'gameOver') return;

    // Tally scores: first guesser gets 3, others get 2, drawer gets 1 per guesser
    for (final gi in _guessedIdx) {
      if (gi < 0 || gi >= _scores.length) continue;
      _scores[gi] += (gi == _firstGuesserIdx) ? 3 : 2;
    }
    if (_guessedIdx.isNotEmpty && _drawerIdx >= 0 && _drawerIdx < _scores.length) {
      _scores[_drawerIdx] += _guessedIdx.length;
    }

    // Advance drawer: rotate through all players each round
    final nextDrawer = (_drawerIdx + 1) % widget.players.length;
    // If we've looped back to the start player, increment the round
    final startDrawer = (widget.firstPlayer - 1) % widget.players.length;
    final completedCycle = nextDrawer == startDrawer;
    final nextRound = completedCycle ? _round + 1 : _round;
    final isGameOver = nextRound > _kRounds;

    setState(() {
      _phase = isGameOver ? 'gameOver' : 'roundOver';
      _word  = _secretWord; // reveal to host (was underscores if host was guesser)
    });

    _net.send('TEK_ROUND_OVER', {
      'word':       _secretWord,
      'scores':     _scores,
      'guessed':    _guessedIdx.toList(),
      'gameOver':   isGameOver,
      'nextDrawer': nextDrawer,
      'nextRound':  nextRound,
    });

    if (isGameOver) {
      _handleGameOver();
    } else {
      Future.delayed(const Duration(seconds: 4), () {
        if (!mounted || !_isHost) return;
        setState(() {
          _drawerIdx = nextDrawer;
          _round     = nextRound;
        });
        _beginChoosing();
      });
    }
  }

  void _handleGameOver() {
    // Only host declares the actual winner via PCT_GAME_OVER
    // Non-host receives winner via the message handler
    if (!_isHost) {
      setState(() => _phase = 'gameOver');
      return;
    }
    int winnerIdx = 0;
    for (int i = 1; i < _scores.length; i++) {
      if (_scores[i] > _scores[winnerIdx]) winnerIdx = i;
    }
    final topScore = _scores[winnerIdx];
    final tied = _scores.where((s) => s == topScore).length > 1;
    final w = tied ? -1 : winnerIdx + 1;
    _net.send('TEK_GAME_OVER', {'w': w, 'scores': _scores});
    setState(() => _phase = 'gameOver');
  }

  // ── Canvas drawing ────────────────────────────────────────────────────────────

  void _onDrawStart(DragStartDetails d) {
    if (!_iAmDrawer || _phase != 'drawing') return;
    final color = _erasing ? Colors.white : _penColor;
    final size = _canvasSize ?? const Size(300, 300);
    final clamped = Offset(
      d.localPosition.dx.clamp(0.0, size.width),
      d.localPosition.dy.clamp(0.0, size.height),
    );
    _currentStroke = _Stroke.fromPixels(
      pixelPoints: [clamped],
      color:       color,
      pixelWidth:  _erasing ? _penWidth * 3 : _penWidth,
      isErase:     _erasing,
      canvasSize:  size,
    );
  }

  void _onDrawUpdate(DragUpdateDetails d) {
    if (!_iAmDrawer || _currentStroke == null) return;
    final size = _canvasSize ?? const Size(300, 300);
    // Clamp to canvas bounds before normalising — prevents drawing outside canvas
    final clamped = Offset(
      d.localPosition.dx.clamp(0.0, size.width),
      d.localPosition.dy.clamp(0.0, size.height),
    );
    setState(() => _currentStroke!.points.add(
      Offset(clamped.dx / size.width, clamped.dy / size.height)));
  }

  void _onDrawEnd(DragEndDetails d) {
    if (!_iAmDrawer || _currentStroke == null) return;
    final stroke = _currentStroke!;
    setState(() {
      _strokes.add(stroke);
      _currentStroke = null;
    });
    _pendingStrokes.add(stroke);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _strokeFlushTimer ??= Timer(const Duration(milliseconds: 50), () {
      _strokeFlushTimer = null;
      if (_pendingStrokes.isEmpty || !mounted) return;
      final toSend = [..._pendingStrokes];
      _pendingStrokes.clear();
      _net.send('TEK_STROKES', {
        'strokes': toSend.map((s) => s.toWire()).toList(),
      });
    });
  }

  // Add a wrong guess to the in-canvas feed; old entries expire automatically.
  void _addGuessToFeed(String playerName, String guessText) {
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _recentGuesses.add({'name': playerName, 'guess': guessText, 'ts': now});
      // Keep only the most recent N guesses
      if (_recentGuesses.length > _kGuessFeedMax) {
        _recentGuesses.removeAt(0);
      }
    });
    // Restart cleanup timer
    _guessFeedTimer?.cancel();
    _guessFeedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final cutoff = DateTime.now().millisecondsSinceEpoch -
          (_kGuessFeedSecs * 1000);
      setState(() => _recentGuesses.removeWhere((g) => (g['ts'] as int) < cutoff));
      if (_recentGuesses.isEmpty) {
        _guessFeedTimer?.cancel();
        _guessFeedTimer = null;
      }
    });
  }

  void _clearCanvas() {
    setState(() => _strokes.clear());
    _net.send('TEK_CLEAR');
    SoundPlayer.i.uiClick();
  }

  // ── Guessing ──────────────────────────────────────────────────────────────────

  void _submitGuess(String text) {
    if (_iAmDrawer || _myGuessCorrect || _phase != 'drawing') return;
    final guess = text.trim();
    _guessCtrl.clear();
    if (guess.isEmpty) return;

    if (_isHost) {
      // Host always knows the word — validate locally
      final correct = guess.trim().toLowerCase() == _secretWord.toLowerCase();
      if (correct) {
        setState(() => _myGuessCorrect = true);
        SoundPlayer.i.rupsenClaim();
        if (!_guessedIdx.contains(_net.myIdx)) {
          _guessedIdx.add(_net.myIdx);
          _firstGuesserIdx ??= _net.myIdx;
          _net.send('TEK_CORRECT', {
            'player': _net.myIdx,
            'name':   widget.players[_net.myIdx].name,
          });
          final nonDrawers = widget.players.length - 1;
          if (_guessedIdx.length >= nonDrawers) _endRound(guessed: true);
        }
      } else {
        SoundPlayer.i.rupsenBust();
        // Broadcast wrong guess to all players + show locally (no loopback)
        _net.send('TEK_WRONG_GUESS', {
          'name':  widget.players[_net.myIdx].name,
          'guess': guess,
        });
        _addGuessToFeed(widget.players[_net.myIdx].name, guess);
      }
    } else {
      // Non-host: always send raw guess to host — host validates server-side.
      // Never compare against _secretWord locally (guessers don't receive it).
      _net.send('TEK_GUESS', {
        'player': _net.myIdx,
        'name':   widget.players[_net.myIdx].name,
        'guess':  guess,
      });
    }
  }

  // ── Message handling ──────────────────────────────────────────────────────────

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'CHAT':       handleIncomingChat(msg); clearTyping(); break;
      case 'CHAT_READ':  handleChatMessage(msg['type'] as String, msg, fromIdx); break;

      case 'TEK_VERBAL_CONFIRM':
        if (_verbal && _phase == 'drawing') {
          final idx = msg['idx'] as int? ?? fromIdx;
          setState(() => _verbalConfirmed.add(idx));
          if (_isHost) {
            // Broadcast to other players so they see the confirmation
            _net.send('TEK_VERBAL_CONFIRM', {'idx': idx});
            _checkVerbalComplete();
          }
        }
        break;

      case 'TEK_VERBAL_SKIP':
        if (_isHost && _verbal && _phase == 'drawing') {
          _endRound(guessed: false);
        }
        break;

      case 'TEK_LANG':
        // Host broadcast the word language + mode — all non-hosts update
        if (!_isHost) {
          setState(() {
            _wordLang = msg['lang'] as String;
            _verbal = msg['verbal'] as bool? ?? false;
            _langConfirmed = true;
          });
        }
        break;

      case 'TEK_CHOOSING':
        if (!_isHost) {
          final newDrawer = msg['drawer'] as int;
          setState(() {
            _drawerIdx      = newDrawer;
            _round          = msg['round'] as int;
            _phase          = 'choosing';
            _word           = '';
            _secretWord     = '';
            _strokes.clear();
            _guessedIdx.clear(); _verbalConfirmed.clear();
            _myGuessCorrect = false;
            _secsLeft       = _kRoundSecs;
            _revealedPositions.clear();
            _hint1Sent = false;
            _hint2Sent = false;
            // Choices are never in the broadcast — they arrive separately via PCT_CHOICES
            _wordChoices    = [];
          });
        }
        break;

      case 'TEK_CHOICES':
        // Drawer receives their private word choices (sent via sendTo — only drawer gets this)
        final rawChoices = msg['choices'];
        if (rawChoices is List) {
          try { setState(() => _wordChoices = rawChoices.cast<String>()); } catch (_) {}
        }
        break;

      case 'TEK_WORD_CHOSEN':
        // Drawer sent their chosen word index to host
        if (_isHost && _wordChoices.isNotEmpty) {
          final idx  = msg['idx'] as int;
          final word = _wordChoices[idx.clamp(0, _wordChoices.length - 1)];
          _onWordChosen(word);
        }
        break;

      case 'TEK_START':
        if (!_isHost) {
          final drawerFromMsg = msg['drawer'] as int;
          final isMe = _net.myIdx == drawerFromMsg;
          setState(() {
            _phase      = 'drawing';
            _secsLeft   = _kRoundSecs;
            if (isMe) {
              // Drawer: receive the actual word
              final actualWord = msg['word'] as String? ?? '';
              _secretWord = actualWord;
              _word       = actualWord;
            } else {
              // Guesser: never receives the word — host validates guesses server-side
              // Build underscore hint: _ _ _ _ (one underscore per letter)
              final len = msg['len'] as int;
              _secretWord = ''; // not used — host does all validation
              _word       = List.filled(len, '_').join(' ');
            }
          });
          _startTimer();
        }
        break;

      case 'TEK_STROKES':
        // Host forwards a joiner-drawer's strokes to the other joiners (3+
        // players); the drawer ignores its own echo (!_iAmDrawer below)
        if (_isHost && fromIdx == _drawerIdx && fromIdx != 0) {
          _net.send('TEK_STROKES', {'strokes': msg['strokes']});
        }
        // Non-drawer receives strokes
        if (!_iAmDrawer) {
          final raw = msg['strokes'] as List;
          if (raw.length > 500) break;
          final list = raw
              .cast<Map<String, dynamic>>()
              .map((s) => _Stroke.fromWire(s))
              .toList();
          setState(() {
            _strokes.addAll(list);
            if (_strokes.length > 10000) _strokes.removeRange(0, _strokes.length - 10000);
          });
        }
        break;

      case 'TEK_CLEAR':
        if (_isHost && fromIdx == _drawerIdx && fromIdx != 0) _net.send('TEK_CLEAR');
        if (!_iAmDrawer) setState(() => _strokes.clear());
        break;

      case 'TEK_GUESS':
        // Only host receives and validates guesses
        if (!_isHost) break;
        final gPlayer = msg['player'] as int;
        final gName   = msg['name'] as String;
        final gText   = msg['guess'] as String? ?? '';
        final correct = gText.trim().toLowerCase() == _secretWord.toLowerCase();

        if (correct && !_guessedIdx.contains(gPlayer)) {
          _guessedIdx.add(gPlayer);
          _firstGuesserIdx ??= gPlayer;
          // Tell guesser they got it right
          _net.sendTo(gPlayer, 'TEK_YOU_CORRECT', {});
          // Tell everyone else someone guessed (name only, no word)
          _net.send('TEK_CORRECT', {
            'player': gPlayer,
            'name':   gName,
          });
          SoundPlayer.i.rupsenClaim();
          final nonDrawers = widget.players.length - 1;
          if (_guessedIdx.length >= nonDrawers) _endRound(guessed: true);
        } else if (!correct) {
          // Broadcast wrong guess to all; also show in host's own feed (no loopback)
          _net.send('TEK_WRONG_GUESS', {'name': gName, 'guess': gText});
          _addGuessToFeed(gName, gText);
        }
        break;

      case 'TEK_YOU_CORRECT':
        // Host confirmed our guess was correct — we're a non-host guesser
        setState(() => _myGuessCorrect = true);
        SoundPlayer.i.rupsenClaim();
        break;

      case 'TEK_CORRECT':
        // A player guessed correctly — track it, play sound, no word reveal yet
        setState(() {
          _guessedIdx.add(msg['player'] as int);
          _firstGuesserIdx ??= msg['player'] as int;
          if (msg['player'] as int == _net.myIdx) _myGuessCorrect = true;
          // Do NOT reveal _word here — guessers see the word only at round end
        });
        if (msg['player'] as int != _net.myIdx) SoundPlayer.i.rupsenClaim();
        break;

      case 'TEK_WRONG_GUESS':
        // Show wrong guess in the in-canvas feed — NOT in chat
        _addGuessToFeed(
          msg['name']  as String,
          msg['guess'] as String,
        );
        break;

      case 'TEK_HINT':
        // Progressive letter hint from host — update guesser displays
        final pos    = msg['pos'] as int;
        final letter = msg['letter'] as String;
        _revealedPositions.add(pos);
        // Drawer already knows the word — only update guessers
        if (!_iAmDrawer && _phase == 'drawing') {
          // _word uses spaced format "_ _ _ _ _" — spaces in the original word
          // become "  " (space-space) so we must index by character, not by split.
          // Each character in the original word maps to index pos*2 in the spaced string.
          final charIdx = pos * 2;
          if (charIdx >= 0 && charIdx < _word.length) {
            final updated = _word.substring(0, charIdx) + letter +
                _word.substring(charIdx + 1);
            setState(() => _word = updated);
          }
        }
        break;

      case 'TEK_ROUND_OVER':
        if (!_isHost) {
          _timer?.cancel(); // stop local countdown — host is authoritative
          final rawScores = msg['scores'];
          if (rawScores is! List) break;
          List<int> scores;
          try { scores = rawScores.cast<int>(); } catch (_) { break; }
          if (scores.length != widget.players.length) break;
          final isGameOver = msg['gameOver'] as bool;
          setState(() {
            _scores    = scores;
            _phase     = isGameOver ? 'gameOver' : 'roundOver';
            _word      = msg['word'] as String; // reveal word
            _guessedIdx = Set<int>.from((msg['guessed'] as List).cast<int>());
          });
          if (isGameOver) {
            _handleGameOver();
          } else {
            // Advance drawer/round in sync with host after delay
            final nextDrawer = msg['nextDrawer'] as int;
            if (nextDrawer < 0 || nextDrawer >= widget.players.length) break;
            Future.delayed(const Duration(seconds: 4), () {
              if (!mounted) return;
              setState(() {
                _drawerIdx = nextDrawer;
                _round     = msg['nextRound'] as int;
              });
            });
          }
        }
        break;

      case 'TEK_GAME_OVER':
        if (!_isHost) {
          final rawScores = msg['scores'];
          if (rawScores is! List) break;
          List<int> scores;
          try { scores = rawScores.cast<int>(); } catch (_) { break; }
          if (scores.length != widget.players.length) break;
          final w = msg['w'];
          setState(() {
            _phase  = 'gameOver';
            _scores = scores;
            if (w is int) {
              _hostWinnerIdx = (w >= 1 && w <= widget.players.length) ? w - 1 : -1;
            }
          });
        }
        break;

      case 'TEK_SYNC':
        if (!_isHost && mounted) {
          final drawerIdx = msg['drawer'] as int;
          if (drawerIdx < 0 || drawerIdx >= widget.players.length) break;
          final rawScores = msg['scores'];
          if (rawScores is! List) break;
          List<int> scores;
          try { scores = rawScores.cast<int>(); } catch (_) { break; }
          if (scores.length != widget.players.length) break;
          final strokes = (msg['strokes'] as List)
              .cast<Map<String, dynamic>>()
              .map((s) => _Stroke.fromWire(s))
              .toList();
          setState(() {
            _drawerIdx = drawerIdx;
            _round     = msg['round'] as int;
            _phase     = msg['phase'] as String;
            _secsLeft  = msg['secs'] as int;
            _scores    = scores;
            _strokes
              ..clear()
              ..addAll(strokes);
          });
        }
        break;

      case 'TEK_SYNC_REQ':
        if (_isHost) {
          _net.send('TEK_SYNC', {
            'drawer': _drawerIdx,
            'round':  _round,
            'phase':  _phase,
            'secs':   _secsLeft,
            'scores': _scores,
            'strokes': _strokes.map((s) => s.toWire()).toList(),
          });
        }
        break;

      case 'GAME_RESET':
        if (!_isHost) {
          resetConfetti();
          resetStats();
          _timer?.cancel();
          setState(() {
            _round      = 1;
            _word       = '';
            _secretWord = '';
            _langConfirmed = false;
            _scores    = List.filled(widget.players.length, 0);
            _strokes.clear();
            _guessedIdx.clear(); _verbalConfirmed.clear();
            _myGuessCorrect = false;
            _secsLeft  = _kRoundSecs;
            _phase     = 'choosing';
            _revealedPositions.clear();
            _hint1Sent = false;
            _hint2Sent = false;
          });
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
            _net.send('TEK_SYNC', {
              'drawer': _drawerIdx,
              'round':  _round,
              'phase':  _phase,
              'secs':   _secsLeft,
              'scores': _scores,
              'strokes': _strokes.map((s) => s.toWire()).toList(),
            });
          } else {
            _net.send('TEK_SYNC_REQ');
          }
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  void _reset() {
    resetConfetti();
    resetStats();
    _timer?.cancel();
    setState(() {
      _round      = 1;
      _drawerIdx  = widget.firstPlayer - 1;
      _word       = '';
      _secretWord = '';
      _langConfirmed = false;
      _scores    = List.filled(widget.players.length, 0);
      _strokes.clear();
      _currentStroke = null;
      _pendingStrokes.clear();
      _guessedIdx.clear(); _verbalConfirmed.clear();
      _myGuessCorrect = false;
      _secsLeft  = _kRoundSecs;
      _phase     = 'choosing';
      _hostWinnerIdx = null;
      _revealedPositions.clear();
      _hint1Sent = false;
      _hint2Sent = false;
      _usedWords.clear();
    });
    if (_isHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showLangDialog());
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = L.tekenjeenriede;
    final drawerName = widget.players[_drawerIdx].name;
    int? winnerIdx;
    if (_phase == 'gameOver' && _scores.isNotEmpty) {
      if (!_isHost && _hostWinnerIdx != null) {
        winnerIdx = _hostWinnerIdx! >= 0 ? _hostWinnerIdx : null;
      } else {
        // More than one player on the top score = draw
        final maxScore = _scores.reduce((a, b) => a > b ? a : b);
        final topCount = _scores.where((sc) => sc == maxScore).length;
        winnerIdx = topCount == 1 ? _scores.indexOf(maxScore) : null;
      }
    }

    return GameScaffold(
      key: scaffoldKey,
      title: s.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: (t) => sendChat(t),
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: s.rules,
      child: Column(children: [
        PlayerBar(
          players: widget.players,
          activeIdx: _drawerIdx,
          scores: _scores,
          scoreLabel: null,
        ),
        GameStatusBar(
          text: _phase == 'drawing'
              ? _verbal
                  ? '${s.roundLabel.fmt({'n': _round, 'total': _kRounds})} · ${s.verbalHint}'
                  : '${s.roundLabel.fmt({'n': _round, 'total': _kRounds})} · ${_secsLeft}s'
              : s.roundLabel.fmt({'n': _round, 'total': _kRounds}),
        ),

        Expanded(child: Column(children: [
          // Phase: choosing
          if (_phase == 'choosing')
            _buildChoosing(drawerName),

          // Phase: drawing or roundOver
          if (_phase == 'drawing' || _phase == 'roundOver') ...[
            _buildWordHint(s),
            Expanded(child: _buildCanvas()),
            if (_iAmDrawer) ...[
              _buildDrawingTools(s),
              if (_verbal && _phase == 'drawing') _buildVerbalInput(s),
            ] else
              _buildGuessInput(s),
          ],

          // Phase: roundOver
          if (_phase == 'roundOver')
            _buildRoundOver(),

          // Phase: gameOver
          if (_phase == 'gameOver') ...[
            const SizedBox(height: 8),
            GameResultBanner(
              players: widget.players,
              winnerIdx: winnerIdx ?? -1,
              onFirstRender: () {
                fireConfettiOnce(winnerIdx ?? -1);
                recordResult('tekenjeenriede', winnerIdx ?? -1);
                if (_isHost) SessionState().advanceGame();
              },
              scores: [
                for (int i = 0; i < widget.players.length; i++)
                  (label: widget.players[i].name, value: '${_scores[i]}'),
              ],
            ),
            GameOverActions(players: widget.players, onReset: _reset),
          ],
        ])),
      ]),
    );
  }

  Widget _buildChoosing(String drawerName) {
    final s = L.tekenjeenriede;
    final langLabel = switch (_wordLang) {
      'fy' => '🇳🇱 Frysk',
      'nl' => '🇳🇱 Nederlands',
      _    => '🇬🇧 English',
    };
    return Expanded(child: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Language badge — only shown once language is confirmed
        if (_langConfirmed) Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: kPurple2.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kPurple2.withValues(alpha: .4))),
          child: Text(langLabel,
            style: const TextStyle(color: kPurple2, fontSize: 13,
              fontWeight: FontWeight.bold)),
        ),
        Text(
          _iAmDrawer ? s.chooseWord : s.drawingLabel.fmt({'player': drawerName}),
          style: const TextStyle(color: kText, fontSize: 18,
            fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 24),
        if (_iAmDrawer && _wordChoices.isNotEmpty)
          ..._wordChoices.map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ElevatedButton(
              onPressed: () {
                if (_isHost) {
                  _onWordChosen(w);
                } else {
                  final idx = _wordChoices.indexOf(w);
                  _net.send('TEK_WORD_CHOSEN', {'idx': idx});
                  // Wait for host to confirm via PCT_START — don't transition yet
                  // (show a brief loading state by clearing choices)
                  setState(() => _wordChoices = []);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPurple2,
                minimumSize: const Size(220, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
              child: Text(w,
                style: const TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.bold)),
            ),
          )),
        if (!_iAmDrawer)
          const CircularProgressIndicator(color: kPurple2),
      ]),
    )));
  }

  Widget _buildWordHint(StringsTekenjeEnRiede s) {
    // Drawer always sees the actual word. Guessers see the underscore pattern
    // (_word is set to '_ _ _ _ _' for guessers until PCT_ROUND_OVER reveals it).
    // After round ends _word is set to the actual word for everyone.
    final hint = _word.toUpperCase();
    final color = _iAmDrawer
        ? kPurple2
        : (_myGuessCorrect ? kGreen : kText);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(_iAmDrawer ? s.youDraw : s.youGuess.fmt({'player': widget.players[_drawerIdx].name}),
            style: const TextStyle(color: kMuted, fontSize: 13),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(hint,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 4)),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    // Fix aspect ratio to 4:3 on ALL devices so normalised 0..1 coords map
    // to exactly the same visual position regardless of phone vs tablet.
    const kAspect = 4.0 / 3.0;
    return Expanded(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Center(child: AspectRatio(
        aspectRatio: kAspect,
        child: LayoutBuilder(builder: (_, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          // Only update _canvasSize when it actually changes to avoid rebuild loops
          if (_canvasSize != size) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _canvasSize = size);
            });
          }
          return ClipRect(
            child: Stack(children: [
              // Drawing surface
              GestureDetector(
                onPanStart:  _iAmDrawer ? _onDrawStart : null,
                onPanUpdate: _iAmDrawer ? _onDrawUpdate : null,
                onPanEnd:    _iAmDrawer ? _onDrawEnd : null,
                child: CustomPaint(
                  size: size,
                  key: _canvasKey,
                  painter: _CanvasPainter(
                    strokes:       _strokes,
                    currentStroke: _currentStroke,
                    isDrawer:      _iAmDrawer,
                  ),
                ),
              ),
              // Guess feed overlay — bottom-left, fades in/out naturally as list changes
              if (_recentGuesses.isNotEmpty)
                Positioned(
                  left: 8, bottom: 8,
                  child: IgnorePointer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: _recentGuesses.map((g) {
                        final name  = g['name']  as String;
                        final guess = g['guess'] as String;
                        return Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12)),
                          child: RichText(text: TextSpan(children: [
                            TextSpan(
                              text: '$name: ',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                            TextSpan(
                              text: guess,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12)),
                          ])),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ]),
          );
        }),
      )),
    ));
  }

  Widget _buildDrawingTools(StringsTekenjeEnRiede s) {
    final colors = [
      Colors.black, Colors.white, Colors.red, Colors.orange,
      Colors.yellow, Colors.green, Colors.blue, Colors.purple,
      Colors.brown, const Color(0xFF00BCD4),
    ];
    final widths = [2.0, 4.0, 8.0, 14.0];

    return Container(
      color: kBg2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(children: [
        // Color row
        Row(children: [
          ...colors.map((c) => GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); setState(() { _penColor = c; _erasing = false; }); },
            child: Container(
              width: 26, height: 26,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _penColor == c && !_erasing
                      ? Colors.white : kBorder,
                  width: _penColor == c && !_erasing ? 2 : 1)),
            ),
          )),
          const Spacer(),
          // Eraser
          GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); setState(() => _erasing = !_erasing); },
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _erasing ? kPurple2.withValues(alpha: .3) : kCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _erasing ? kPurple2 : kBorder)),
              child: const Icon(Icons.auto_fix_normal, color: kText, size: 18)),
          ),
          const SizedBox(width: 8),
          // Clear
          GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); _clearCanvas(); },
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kBorder)),
              child: const Icon(Icons.delete_outline, color: kText, size: 18)),
          ),
        ]),
        const SizedBox(height: 6),
        // Width row
        Row(children: widths.map((w) => GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); setState(() => _penWidth = w); },
          child: Container(
            width: w * 3 + 16, height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _penWidth == w ? kPurple2.withValues(alpha: .2) : kCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _penWidth == w ? kPurple2 : kBorder)),
            child: Center(child: Container(
              width: w * 2, height: w * 2,
              decoration: BoxDecoration(
                color: _erasing ? Colors.white : _penColor,
                shape: BoxShape.circle))),
          ),
        )).toList()),
      ]),
    );
  }

  /// Verbal mode: player confirms they got it. Round ends when BOTH drawer + guesser confirmed.
  void _verbalConfirm() {
    if (_phase != 'drawing') return;
    if (_verbalConfirmed.contains(_net.myIdx)) return;
    HapticFeedback.mediumImpact();
    SoundPlayer.i.rupsenClaim();
    setState(() => _verbalConfirmed.add(_net.myIdx));
    if (_isHost) {
      _net.send('TEK_VERBAL_CONFIRM', {'idx': _net.myIdx});
      _checkVerbalComplete();
    } else {
      _net.send('TEK_VERBAL_CONFIRM', {'idx': _net.myIdx});
    }
  }

  /// Verbal mode: skip this word (either player can skip).
  void _verbalSkip() {
    if (_phase != 'drawing') return;
    HapticFeedback.lightImpact();
    if (_isHost) {
      _endRound(guessed: false);
    } else {
      _net.send('TEK_VERBAL_SKIP');
    }
  }

  /// Host checks if both drawer + at least one guesser confirmed.
  void _checkVerbalComplete() {
    if (!_isHost || _phase != 'drawing') return;
    final drawerConfirmed = _verbalConfirmed.contains(_drawerIdx);
    final anyGuesserConfirmed = _verbalConfirmed.any((i) => i != _drawerIdx);
    if (drawerConfirmed && anyGuesserConfirmed) {
      for (int i = 0; i < widget.players.length; i++) {
        if (i != _drawerIdx) _guessedIdx.add(i);
      }
      _firstGuesserIdx ??= _verbalConfirmed.firstWhere((i) => i != _drawerIdx);
      setState(() => _myGuessCorrect = true);
      _endRound(guessed: true);
    }
  }

  Widget _buildGuessInput(StringsTekenjeEnRiede s) {
    if (_verbal) return _buildVerbalInput(s);
    return Container(
      color: kBg2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: _myGuessCorrect
          ? Center(child: Text('✅ ${s.youGuessedIt}',
              style: const TextStyle(color: kGreen, fontSize: 18,
                fontWeight: FontWeight.bold)))
          : Row(children: [
              Expanded(child: TextField(
                controller: _guessCtrl,
                style: const TextStyle(color: kText),
                decoration: InputDecoration(
                  hintText: s.guessPlaceholder,
                  hintStyle: const TextStyle(color: kMuted),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10)),
                onSubmitted: _submitGuess,
              )),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); _submitGuess(_guessCtrl.text); },
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: kPurple2,
                    borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.send, color: Colors.white, size: 20)),
              ),
            ]),
    );
  }

  Widget _buildVerbalInput(StringsTekenjeEnRiede s) {
    final iConfirmed = _verbalConfirmed.contains(_net.myIdx);
    final drawerConfirmed = _verbalConfirmed.contains(_drawerIdx);
    final anyGuesserConfirmed = _verbalConfirmed.any((i) => i != _drawerIdx);

    // Hint text: show who already confirmed
    String? hint;
    if (iConfirmed) {
      hint = _iAmDrawer
          ? (anyGuesserConfirmed ? null : s.waitingForGuesser)
          : (drawerConfirmed ? null : s.waitingForDrawer);
    } else if (drawerConfirmed && !_iAmDrawer) {
      hint = s.drawerConfirmed;
    } else if (anyGuesserConfirmed && _iAmDrawer) {
      hint = s.guesserConfirmed;
    }

    return Container(
      color: kBg2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (hint != null) ...[
          Text(hint, style: const TextStyle(color: kGreen, fontSize: 13,
            fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
        ],
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: iConfirmed ? null : _verbalConfirm,
            icon: Icon(iConfirmed ? Icons.check : Icons.check_circle_outline, size: 20),
            label: Text(iConfirmed ? '✓' : s.gotIt, style: const TextStyle(fontSize: 15,
              fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: iConfirmed ? kGreen.withValues(alpha: .3) : kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
          )),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _verbalSkip,
            style: OutlinedButton.styleFrom(
              foregroundColor: kMuted,
              side: const BorderSide(color: kBorder),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
            child: Text(s.skip, style: const TextStyle(fontSize: 14)),
          ),
        ]),
      ]),
    );
  }

  Widget _buildRoundOver() {
    return Container(
      color: kBg2,
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Text('${L.tekenjeenriede.timeUp.fmt({'word': _word})}',
          style: const TextStyle(color: kText, fontSize: 16,
            fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(L.tekenjeenriede.roundLabel.fmt({'n': _round, 'total': _kRounds}),
          style: const TextStyle(color: kMuted, fontSize: 14)),
      ]),
    );
  }
}

// ── Canvas painter ────────────────────────────────────────────────────────────
class _CanvasPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke?      currentStroke;
  final bool          isDrawer;

  const _CanvasPainter({
    required this.strokes,
    required this.currentStroke,
    required this.isDrawer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // White drawing surface
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white);

    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, size);
    }
    if (currentStroke != null) _drawStroke(canvas, currentStroke!, size);

    // Hint text for drawer
    if (isDrawer && strokes.isEmpty && currentStroke == null) {
      final tp = TextPainter(
        text: TextSpan(
          text: L.tekenjeenriede.sketchHint,
          style: TextStyle(color: Colors.grey.shade300, fontSize: 20)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(canvas,
        Offset(size.width / 2 - tp.width / 2,
               size.height / 2 - tp.height / 2));
    }

    // Border
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = kBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
  }

  void _drawStroke(Canvas canvas, _Stroke stroke, Size size) {
    if (stroke.points.isEmpty) return;
    final cw = size.width;
    final ch = size.height;
    // Denormalise: convert 0..1 coords to pixels for this canvas
    final px = stroke.points.map((p) => Offset(p.dx * cw, p.dy * ch)).toList();
    final strokeWidthPx = stroke.width * cw;

    final paint = Paint()
      ..color = stroke.isErase ? Colors.white : stroke.color
      ..strokeWidth = strokeWidthPx
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (px.length == 1) {
      canvas.drawCircle(px.first, strokeWidthPx / 2, paint);
      return;
    }

    final path = Path()..moveTo(px.first.dx, px.first.dy);
    for (int i = 1; i < px.length; i++) {
      final prev = px[i - 1];
      final curr = px[i];
      final mx = (prev.dx + curr.dx) / 2;
      final my = (prev.dy + curr.dy) / 2;
      path.quadraticBezierTo(prev.dx, prev.dy, mx, my);
    }
    path.lineTo(px.last.dx, px.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
    old.strokes != strokes || old.currentStroke != currentStroke;
}
