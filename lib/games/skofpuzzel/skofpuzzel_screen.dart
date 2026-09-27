import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

// ── Constants ────────────────────────────────────────────────────────────────
const _kSize   = 4; // 4×4 = 15-puzzle
const _kTiles  = _kSize * _kSize; // 16, tile 0 = blank

// ── Screen ────────────────────────────────────────────────────────────────────
class SkofpuzzelScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const SkofpuzzelScreen(
      {super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<SkofpuzzelScreen> createState() => _SkofpuzzelState();
}

class _SkofpuzzelState extends State<SkofpuzzelScreen> with GameMixin {
  final _net  = Network();

  // Board: indices 0.._kTiles-1, value = tile number (0=blank, 1–15=tiles)
  List<int> _board = List.generate(_kTiles, (i) => i);

  // Opponent board state (just for showing progress, not full board)
  int _opponentMoves = 0;
  bool _opponentSolved = false;

  // My state
  int  _moves   = 0;
  bool _solved  = false;
  int  _winner  = 0; // 0=playing, 1=p1(host), 2=p2(joiner), -1=draw
  bool _started = false;

  // Timer
  Stopwatch _stopwatch = Stopwatch();
  Timer?    _uiTimer;
  int       _elapsedSec = 0;

  // Preview phase: show solved board briefly before scrambling
  bool _previewing = false; // true = showing solved image, false = scrambled/playing

  // Photo
  Uint8List? _photoBytes; // full photo — host sends compressed to clients
  bool       _usePhoto   = false;
  // Personal best (solo only)
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
      // Show mode choice dialog, then setup
      WidgetsBinding.instance.addPostFrameCallback((_) => _showModeDialog());
    }
  }

  @override
  void dispose() {
    msgSub?.cancel();
    _uiTimer?.cancel();
    WakeLock.release();
    super.dispose();
  }

  // ── Personal best ────────────────────────────────────────────────────────────
  Future<void> _loadBest() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _personalBest = p.getInt('skofpuzzel_best') ?? 0);
  }

  Future<void> _saveBest(int secs) async {
    if (_personalBest == 0 || secs < _personalBest) {
      final p = await SharedPreferences.getInstance();
      await p.setInt('skofpuzzel_best', secs);
      if (mounted) setState(() { _personalBest = secs; _newBest = true; });
      SoundPlayer.i.newBest();
    }
  }

  // ── Host setup ────────────────────────────────────────────────────────────────
  // ── Mode choice dialog (host only) ───────────────────────────────────────────
  void _showModeDialog() {
    final s = L.skofpuzzel;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(s.gameName,
          style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.chooseMode, style: const TextStyle(color: kMuted, fontSize: 14)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _ModeBtn(
              label: s.useNumbers,
              selected: !_usePhoto,
              onTap: () => setState(() => _usePhoto = false),
            )),
            const SizedBox(width: 8),
            Expanded(child: _ModeBtn(
              label: s.usePhoto,
              selected: _usePhoto,
              onTap: () async {
                Navigator.pop(context);
                await _pickPhoto();
                if (mounted) {
                  // If user cancelled photo picker, fall back to numbers mode
                  if (_photoBytes == null) _usePhoto = false;
                  _hostSetup();
                }
                return; // skip the bottom button flow
              },
            )),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _hostSetup();
            },
            child: Text(s.startGame,
              style: const TextStyle(color: kPurple2, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _hostSetup() {
    final seed = math.Random().nextInt(1 << 30);
    final shuffled = _generateSolvable(seed);
    if (!_isSolo) {
      _net.send('SKO_INIT', {'seed': seed});
    }
    // Show solved board first as preview
    setState(() {
      _board      = List.generate(_kTiles, (i) => i); // solved order
      _previewing = true;
      _started    = false;
    });
    // After 2s: scramble and start
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _board      = shuffled;
        _previewing = false;
        _started    = true;
      });
      _beginTimer();
    });
  }

  // ── Shuffle: generate a solvable 15-puzzle ───────────────────────────────────
  List<int> _generateSolvable(int seed) {
    final rng = math.Random(seed);
    List<int> tiles = List.generate(_kTiles, (i) => i);
    // Fisher-Yates shuffle, then check solvability
    do {
      for (int i = _kTiles - 1; i > 0; i--) {
        final j = rng.nextInt(i + 1);
        final tmp = tiles[i]; tiles[i] = tiles[j]; tiles[j] = tmp;
      }
    } while (!_isSolvable(tiles) || _isSolved(tiles));
    return tiles;
  }

  // Goal is tiles[i] == i with the blank (0) top-left. Every move swaps the
  // blank with a neighbour: flips permutation parity and changes the blank's
  // taxicab distance to index 0 by 1. So solvable iff:
  //   inversions (incl. blank) + blank_row + blank_col is even
  bool _isSolvable(List<int> tiles) {
    int inversions = 0;
    for (int i = 0; i < _kTiles; i++) {
      for (int j = i + 1; j < _kTiles; j++) {
        if (tiles[i] > tiles[j]) inversions++;
      }
    }
    final blank = tiles.indexOf(0);
    final dist = blank ~/ _kSize + blank % _kSize;
    return (inversions + dist) % 2 == 0;
  }

  bool _isSolved(List<int> tiles) {
    for (int i = 0; i < _kTiles; i++) {
      if (tiles[i] != i) return false;
    }
    return true;
  }

  // ── Timer ─────────────────────────────────────────────────────────────────────
  void _beginTimer() {
    _stopwatch.start();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSec = _stopwatch.elapsed.inSeconds);
    });
  }

  void _stopTimer() {
    _stopwatch.stop();
    _uiTimer?.cancel();
    setState(() => _elapsedSec = _stopwatch.elapsed.inSeconds);
  }

  // ── Photo picking (host only) ─────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600, maxHeight: 600, imageQuality: 75);
    if (xf == null || !mounted) return;
    final bytes = await xf.readAsBytes();
    setState(() { _photoBytes = bytes; _usePhoto = true; });
    if (!_isSolo) {
      // Send compressed photo to all players
      final b64 = base64Encode(bytes);
      _net.send('SKO_PHOTO', {'data': b64});
    }
  }

  // ── Tile move ─────────────────────────────────────────────────────────────────
  void _tap(int idx) {
    if (_solved || _winner != 0 || _previewing || !_started) return;
    final blank = _board.indexOf(0);
    if (!_isAdjacent(idx, blank)) return;
    SoundPlayer.i.sudokuDuelCell();
    setState(() {
      _board[blank] = _board[idx];
      _board[idx]   = 0;
      _moves++;
    });
    if (!_isSolo) {
      _net.send('SKO_MOVE', {'idx': idx, 'blank': blank});
    }
    _checkSolved();
  }

  bool _isAdjacent(int a, int b) {
    final ar = a ~/ _kSize, ac = a % _kSize;
    final br = b ~/ _kSize, bc = b % _kSize;
    return (ar == br && (ac - bc).abs() == 1) ||
           (ac == bc && (ar - br).abs() == 1);
  }

  void _checkSolved() {
    if (!_isSolved(_board)) return;
    _stopTimer();
    SoundPlayer.i.sudokuDuelSolved();
    setState(() => _solved = true);
    if (_isSolo) {
      _saveBest(_elapsedSec);
      setState(() => _winner = 1);
    } else {
      _net.send('SKO_SOLVED', {'time': _elapsedSec});
      // Only the host declares the winner to avoid conflicts
      if (_isHost) {
        _declareWinner(1);
      }
      // Joiner waits for SKO_WINNER from host
    }
  }

  void _declareWinner(int w) {
    if (_winner != 0) return;
    setState(() => _winner = w);
    if (_isHost) _net.send('SKO_WINNER', {'w': w});
  }

  // ── Message handling ──────────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {

      case 'SKO_INIT':
        if (!_isHost) {
          final seed = msg['seed'] as int;
          final shuffled = _generateSolvable(seed);
          // Show solved board as preview first
          setState(() {
            _board      = List.generate(_kTiles, (i) => i);
            _previewing = true;
            _started    = false;
          });
          Future.delayed(const Duration(seconds: 2), () {
            if (!mounted) return;
            setState(() {
              _board      = shuffled;
              _previewing = false;
              _started    = true;
            });
            _beginTimer();
          });
        }
        break;

      case 'SKO_PHOTO':
        if (!_isHost) {
          final bytes = base64Decode(msg['data'] as String);
          setState(() {
            _photoBytes  = bytes;
            _usePhoto    = true;
          });
        }
        break;

      case 'SKO_MOVE':
        // Opponent's move — just track their progress
        setState(() => _opponentMoves++);
        break;

      case 'SKO_SOLVED':
        setState(() => _opponentSolved = true);
        // If I've also solved, compare times; otherwise they won
        if (_solved) {
          final myTime   = _elapsedSec;
          final theirTime = msg['time'] as int;
          if (_isHost) {
            _declareWinner(myTime <= theirTime ? 1 : 2);
          }
        } else {
          // They finished before me
          _declareWinner(fromIdx == 0 ? 1 : 2);
        }
        break;

      case 'SKO_WINNER':
        if (!_isHost) {
          setState(() => _winner = msg['w'] as int);
        }
        break;

      case 'SKO_SYNC':
        // Host sends full state on reconnect
        if (!_isHost && mounted) {
          final b = (msg['board'] as List).cast<int>();
          setState(() {
            _board          = b;
            _moves          = msg['moves'] as int;
            _opponentMoves  = msg['opmoves'] as int;
            _solved         = msg['solved'] as bool;
            _opponentSolved = msg['opsolved'] as bool;
            _winner         = msg['winner'] as int;
            _started        = msg['started'] as bool? ?? _started;
            _elapsedSec     = msg['elapsed'] as int? ?? _elapsedSec;
            _usePhoto       = msg['usePhoto'] as bool? ?? _usePhoto;
          });
          // Restart timer if game is in progress
          if (_started && !_solved && _winner == 0) {
            _uiTimer?.cancel();
            _stopwatch.reset();
            _stopwatch.start();
            _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
              if (!mounted) return;
              setState(() => _elapsedSec++);
            });
          }
        }
        break;

      case 'SKO_SYNC_REQ':
        if (_isHost) _net.send('SKO_SYNC', _syncMap());
        break;

      case 'GAME_RESET':
        if (!_isHost) setState(() => _reset());
        break;

    }
  }

  Map<String, dynamic> _syncMap() => {
    'board':    _board,
    'moves':    _moves,
    'opmoves':  _opponentMoves,
    'solved':   _solved,
    'opsolved': _opponentSolved,
    'winner':   _winner,
    'started':  _started,
    'elapsed':  _elapsedSec,
    'usePhoto': _usePhoto,
  };

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_isHost) _net.send('SKO_SYNC', _syncMap());
          else _net.send('SKO_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  void _reset() {
    resetConfetti();
    resetStats();
    _uiTimer?.cancel();
    _stopwatch.reset();
    setState(() {
      _moves          = 0;
      _opponentMoves  = 0;
      _solved         = false;
      _opponentSolved = false;
      _winner         = 0;
      _started        = false;
      _elapsedSec     = 0;
      _newBest        = false;
    });
    if (_isHost) _hostSetup();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = L.skofpuzzel;
    final isTwoPlayer = !_isSolo && widget.players.length >= 2;

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
        if (isTwoPlayer)
          PlayerBar(
            players: widget.players,
            activeIdx: -1,
            scores: [
              _net.myIdx == 0 ? _moves : _opponentMoves,
              _net.myIdx == 1 ? _moves : _opponentMoves,
            ],
            scoreLabel: s.movesLabel.fmt({'n': ''}),
          ),
          GameStatusBar(text: _winner == 0 ? _timerText : null),

        // Solo timer + moves
        if (_isSolo)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_timerText,
                  style: const TextStyle(color: kText, fontSize: 16,
                    fontWeight: FontWeight.bold)),
                Text(s.movesLabel.fmt({'n': _moves}),
                  style: const TextStyle(color: kMuted, fontSize: 14)),
                if (_personalBest > 0)
                  Text(s.personalBest.fmt({'time': _personalBest}),
                    style: const TextStyle(color: kMuted, fontSize: 13)),
              ],
            ),
          ),

        // Puzzle grid
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(16),
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(builder: (_, constraints) {
              final size = constraints.maxWidth;
              return _buildGrid(size);
            }),
          ),
        ))),

        // Result
        if (_winner != 0) ...[
          if (_isSolo) ...[
            Center(child: Column(children: [
              Text(s.solved,
                style: const TextStyle(color: kText, fontSize: 22,
                  fontWeight: FontWeight.bold)),
              Text(s.yourTime.fmt({'time': _elapsedSec}),
                style: const TextStyle(color: kMuted, fontSize: 16)),
              if (_newBest)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(s.newBest,
                    style: const TextStyle(color: kPurple2, fontSize: 15,
                      fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
            ])),
          ] else
            GameResultBanner(
              players: widget.players,
              winnerIdx: _winner <= 0 ? -1 : _winner - 1,
              onFirstRender: () {
                final wi = _winner <= 0 ? -1 : _winner - 1;
                fireConfettiOnce(wi);
                recordResult('skofpuzzel', wi);
                if (_isHost) SessionState().advanceGame();
              },
            ),
          GameOverActions(players: widget.players, onReset: _reset),
        ] else
          const SizedBox(height: 8),
      ]),
    );
  }

  String get _timerText {
    final m = _elapsedSec ~/ 60;
    final s = _elapsedSec % 60;
    return m > 0
        ? '$m:${s.toString().padLeft(2, '0')}'
        : '${_elapsedSec}s';
  }

  Widget _buildGrid(double size) {
    final tileSize = size / _kSize;
    return Stack(children: [
      // Background
      Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: kBg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
      ),
      // Tiles
      for (int i = 0; i < _kTiles; i++)
        _buildTile(i, tileSize, size),
      // Preview overlay — "memorise it!" banner
      if (_previewing)
        Positioned.fill(child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: kPurple2.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('👀  2…', style: TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            )),
          ),
        )),
    ]);
  }

  Widget _buildTile(int idx, double tileSize, double gridSize) {
    final tileNum = _board[idx];
    if (tileNum == 0) return const SizedBox.shrink(); // blank

    final row = idx ~/ _kSize;
    final col = idx % _kSize;
    final gap = 3.0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      left: col * tileSize + gap,
      top:  row * tileSize + gap,
      width:  tileSize - gap * 2,
      height: tileSize - gap * 2,
      child: GestureDetector(
        onTap: () => _tap(idx),
        child: _TileWidget(
          tileNum:   tileNum,
          tileSize:  tileSize - gap * 2,
          gridN:     _kSize,
          photoBytes: _usePhoto ? _photoBytes : null,
          solved:    _solved,
        ),
      ),
    );
  }
}

// ── Tile widget ───────────────────────────────────────────────────────────────
class _TileWidget extends StatelessWidget {
  final int       tileNum;
  final double    tileSize;
  final int       gridN;
  final Uint8List? photoBytes;
  final bool      solved;

  const _TileWidget({
    required this.tileNum,
    required this.tileSize,
    required this.gridN,
    required this.photoBytes,
    required this.solved,
  });

  @override
  Widget build(BuildContext context) {
    final correctRow = tileNum ~/ gridN;
    final correctCol = tileNum % gridN;

    if (photoBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _PhotoTile(
          bytes:      photoBytes!,
          tileSize:   tileSize,
          gridN:      gridN,
          srcRow:     correctRow,
          srcCol:     correctCol,
          solved:     solved,
        ),
      );
    }

    // Number tile
    final shade = (tileNum % 3 == 0)
        ? kPurple
        : (tileNum % 3 == 1 ? kPurple2 : const Color(0xFF7C5CBF));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(shade, Colors.white, 0.15)!,
            shade,
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4, offset: const Offset(1, 2)),
        ],
      ),
      child: Center(
        child: Text(
          '$tileNum',
          style: TextStyle(
            color: Colors.white,
            fontSize: tileSize * 0.38,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Photo tile — crops the correct section of the image ──────────────────────
class _PhotoTile extends StatelessWidget {
  final Uint8List bytes;
  final double tileSize;
  final int gridN, srcRow, srcCol;
  final bool solved;

  const _PhotoTile({
    required this.bytes, required this.tileSize, required this.gridN,
    required this.srcRow, required this.srcCol, required this.solved,
  });

  @override
  Widget build(BuildContext context) {
    // We want to show the (srcCol, srcRow) segment of the full image
    // by scaling the image to gridN * tileSize and offsetting
    final fullSize = tileSize * gridN;
    final offsetX  = -srcCol * tileSize;
    final offsetY  = -srcRow * tileSize;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: tileSize, height: tileSize,
        child: OverflowBox(
          maxWidth: fullSize, maxHeight: fullSize,
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(offsetX, offsetY),
            child: Image.memory(bytes,
              width: fullSize, height: fullSize,
              fit: BoxFit.fill),
          ),
        ),
      ),
    );
  }
}

// ── Mode button ───────────────────────────────────────────────────────────────
class _ModeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeBtn({required this.label, required this.selected, required this.onTap});

  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kPurple2.withValues(alpha: .2) : Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? kPurple2 : kBorder, width: selected ? 2 : 1),
        ),
        child: Center(child: Text(label,
          style: TextStyle(
            color: selected ? kText : kMuted,
            fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal))),
      ),
    );
  }
}
