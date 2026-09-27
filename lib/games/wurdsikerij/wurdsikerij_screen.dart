import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/theme.dart';
import '../../core/session.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/reconnect_dialog.dart';
import '../../screens/lobby_screen.dart';
import '../../screens/solo_setup_screen.dart' show SoloDifficulty;
import '../../l10n/app_localizations.dart';

// ── Word banks ─────────────────────────────────────────────────────────────────
// Family-friendly nouns, 3–11 letters (the grid is 12×12). A word that is part
// of another chosen word is skipped by the generator, so overlaps are harmless.

const _kWordsFy = [
  'skoalle', 'wetter', 'blom', 'strân', 'winter', 'simmer', 'brea', 'hynder',
  'tafel', 'stoel', 'kleur', 'dream', 'boeken', 'trein', 'rivier', 'wolken',
  'beam', 'slange', 'piano', 'radio', 'feest', 'nacht', 'ljocht', 'muzyk',
  'ierde', 'stien', 'fûgel', 'dûns', 'wrâld', 'hûs',
  'hûn', 'kat', 'skiep', 'baarch', 'hin', 'ein', 'fisk', 'mûs', 'hazze', 'foks',
  'kikkert', 'stikelbaarch', 'sinne', 'moanne', 'stjer', 'rein', 'snie', 'wyn',
  'see', 'mar', 'boat', 'skip', 'fyts', 'auto', 'tsiis', 'bûter', 'molke',
  'apel', 'par', 'skuon', 'tosk', 'holle', 'hân', 'foet', 'noas', 'mûle',
  'boer', 'mem', 'heit', 'pake', 'beppe', 'broer', 'suster', 'freon', 'toer',
  'tsjerke', 'doarp', 'stêd', 'brêge', 'feart', 'sleat', 'greide', 'fjild',
  'bosk', 'tún', 'finster', 'doar', 'dak', 'bêd', 'keamer', 'lampe', 'klok',
  'spultsje', 'bal', 'iis', 'keatsen', 'fierljeppen', 'skûtsje',
];

const _kWordsNl = [
  'appel', 'school', 'boeken', 'water', 'bloem', 'vogel', 'strand', 'winter',
  'zomer', 'fiets', 'brood', 'kaart', 'molen', 'beker', 'paard', 'tafel',
  'stoel', 'kleur', 'droom', 'lezen', 'regen', 'wolken', 'bomen', 'slang',
  'piano', 'radio', 'trein', 'daken', 'varen', 'rivier', 'bergen', 'lopen',
  'groep', 'feest', 'nacht', 'licht', 'muziek', 'prins', 'huis',
  'hond', 'kat', 'koe', 'schaap', 'varken', 'kip', 'eend', 'vis', 'muis',
  'haas', 'vos', 'egel', 'kikker', 'zon', 'maan', 'ster', 'sneeuw', 'wind',
  'zee', 'meer', 'boot', 'schip', 'auto', 'kaas', 'boter', 'melk', 'peer',
  'hoed', 'jas', 'schoen', 'tand', 'hoofd', 'hand', 'voet', 'neus', 'mond',
  'boer', 'oma', 'opa', 'broer', 'zus', 'vriend', 'toren', 'kerk', 'dorp',
  'stad', 'brug', 'sloot', 'weide', 'bos', 'tuin', 'raam', 'deur', 'bed',
  'kamer', 'keuken', 'lamp', 'klok', 'spel', 'bal', 'ijs', 'schaats',
  'vliegtuig',
];

const _kWordsEn = [
  'apple', 'school', 'books', 'water', 'house', 'flower', 'bird', 'beach',
  'winter', 'summer', 'bread', 'horse', 'table', 'chair', 'color', 'dream',
  'games', 'train', 'river', 'cloud', 'stone', 'piano', 'tiger', 'queen',
  'crown', 'smile', 'dance', 'music', 'night', 'light', 'stars', 'ocean',
  'plant', 'happy', 'world', 'brain', 'earth', 'magic', 'party', 'snake',
  'dog', 'cat', 'cow', 'sheep', 'pig', 'hen', 'duck', 'fish', 'mouse',
  'rabbit', 'fox', 'frog', 'sun', 'moon', 'snow', 'wind', 'sea', 'lake',
  'boat', 'ship', 'car', 'cheese', 'butter', 'milk', 'pear', 'hat', 'coat',
  'shoe', 'tooth', 'head', 'hand', 'foot', 'nose', 'mouth', 'farmer',
  'grandma', 'grandpa', 'brother', 'sister', 'friend', 'tower', 'church',
  'village', 'city', 'bridge', 'meadow', 'forest', 'garden', 'window', 'door',
  'bed', 'kitchen', 'lamp', 'clock', 'pen', 'ball', 'ice', 'skate', 'airplane',
];

List<String> _wordBankForLang(AppLang lang) => switch (lang) {
  AppLang.fy => _kWordsFy,
  AppLang.nl => _kWordsNl,
  AppLang.en => _kWordsEn,
};

// ── Directions ────────────────────────────────────────────────────────────────
// (row step, col step). Easy: → ↓. Medium (default, multiplayer): + ↘ ↗.
// Hard: all eight, so words can also run backwards.

const _kDirsEasy   = [(0, 1), (1, 0)];
const _kDirsMedium = [(0, 1), (1, 0), (1, 1), (-1, 1)];
const _kDirsHard   = [(0, 1), (1, 0), (1, 1), (-1, 1), (0, -1), (-1, 0), (-1, -1), (1, -1)];

class _WordPlacement {
  final String word;
  final int row, col;   // first letter
  final int dr, dc;     // step per letter
  const _WordPlacement(this.word, this.row, this.col, this.dr, this.dc);

  (int, int) cell(int i) => (row + dr * i, col + dc * i);

  Map<String, dynamic> toJson() => {
    'word': word, 'row': row, 'col': col, 'dr': dr, 'dc': dc,
  };
  factory _WordPlacement.fromJson(Map<String, dynamic> j) => _WordPlacement(
    j['word'] as String, j['row'] as int, j['col'] as int,
    j['dr'] as int, j['dc'] as int,
  );
}

// ── Grid generation ──────────────────────────────────────────────────────────

class _GridData {
  final List<List<String>> grid;
  final List<String> words;
  final List<_WordPlacement> placements;
  const _GridData(this.grid, this.words, this.placements);
}

_GridData _generateGrid(AppLang lang, SoloDifficulty difficulty,
    {int size = 12, int wordCount = 10}) {
  final rng = math.Random();
  final bankLower = _wordBankForLang(lang);
  final bank = bankLower.map((w) => w.toUpperCase())
      .where((w) => w.length <= size).toList()..shuffle(rng);
  final dirs = switch (difficulty) {
    SoloDifficulty.easy   => _kDirsEasy,
    SoloDifficulty.medium => _kDirsMedium,
    SoloDifficulty.hard   => _kDirsHard,
  };

  final placed = <_WordPlacement>[];
  final grid = List.generate(size, (_) => List.filled(size, ''));

  bool fits(String word, int r, int c, int dr, int dc) {
    for (int i = 0; i < word.length; i++) {
      final gr = r + dr * i, gc = c + dc * i;
      if (gr < 0 || gr >= size || gc < 0 || gc >= size) return false;
      final existing = grid[gr][gc];
      if (existing.isNotEmpty && existing != word[i]) return false;
    }
    return true;
  }

  // A word hidden inside another (or its reverse) would be found twice.
  bool overlapsChosen(String word) => placed.any((p) {
    final other = p.word, rev = other.split('').reversed.join();
    return other.contains(word) || rev.contains(word) ||
        word.contains(other) || word.contains(rev);
  });

  // Directions are dealt round-robin (shuffled) so every grid gets a mix.
  final order = List.of(dirs)..shuffle(rng);
  for (final word in bank) {
    if (placed.length >= wordCount) break;
    if (overlapsChosen(word)) continue;
    final want = order[placed.length % order.length];
    final tryDirs = [want, ...(List.of(dirs)..shuffle(rng))];
    _WordPlacement? spot;
    for (final (dr, dc) in tryDirs) {
      for (int t = 0; t < 60 && spot == null; t++) {
        final r = rng.nextInt(size), c = rng.nextInt(size);
        if (fits(word, r, c, dr, dc)) spot = _WordPlacement(word, r, c, dr, dc);
      }
      if (spot != null) break;
    }
    if (spot == null) continue;
    for (int i = 0; i < word.length; i++) {
      final (gr, gc) = spot.cell(i);
      grid[gr][gc] = word[i];
    }
    placed.add(spot);
  }

  // Filler letters follow the language's own letter mix (taken from its word
  // bank), so accented letters like Â or Û don't give a word away.
  final pool = bankLower.join().toUpperCase();
  for (int r = 0; r < size; r++) {
    for (int c = 0; c < size; c++) {
      if (grid[r][c].isEmpty) grid[r][c] = pool[rng.nextInt(pool.length)];
    }
  }

  return _GridData(grid, placed.map((p) => p.word).toList(), placed);
}

// ── Wurdsikerij Screen ──────────────────────────────────────────────────────

class WurdsikerijScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const WurdsikerijScreen({
    super.key,
    required this.players,
    required this.firstPlayer,
    this.extra,
  });
  @override State<WurdsikerijScreen> createState() => _WurdsikerijState();
}

class _WurdsikerijState extends State<WurdsikerijScreen> with GameMixin {
  final _net = Network();

  // Grid state
  List<List<String>> _grid = [];
  List<String> _words = [];
  List<_WordPlacement> _placements = [];
  Map<String, int> _foundWords = {}; // word → playerIdx who found it
  bool _gameOver = false;

  // Selection state
  (int, int)? _selectStart; // (row, col) of first tap
  String? _statusMsg;

  // Timer for solo mode
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timerTick;

  // Joiner: retries WSK_SYNC_REQ until the grid arrives (the host's initial
  // WSK_GRID can be sent before this screen subscribes to the stream).
  Timer? _syncReqTimer;

  @override List<Player> get gamePlayers => widget.players;

  @override void initState() {
    super.initState();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };

    if (_net.isHost || _net.isSolo) {
      _generateAndSend();
    } else {
      _startSyncRequests();
    }

    if (_net.isSolo) {
      _stopwatch.start();
      _timerTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override void dispose() {
    _timerTick?.cancel();
    _syncReqTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  /// Joiner: ask the host for the current grid shortly after subscribing and
  /// keep asking every 1.5 s (max 4 tries) until it arrives.
  void _startSyncRequests() {
    _syncReqTimer?.cancel();
    int tries = 0;
    _syncReqTimer = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (!mounted || _grid.isNotEmpty || tries >= 4) { t.cancel(); return; }
      tries++;
      _net.send('WSK_SYNC_REQ');
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _grid.isEmpty) _net.send('WSK_SYNC_REQ');
    });
  }

  void _generateAndSend() {
    final difficulty = SoloDifficulty.values[
        widget.extra?['difficulty'] as int? ?? SoloDifficulty.medium.index];
    final data = _generateGrid(L.lang, difficulty);
    setState(() {
      _grid = data.grid;
      _words = data.words;
      _placements = data.placements;
      _foundWords = {};
      _gameOver = false;
      _selectStart = null;
    });

    if (!_net.isSolo) {
      _net.send('WSK_GRID', {
        'grid': _grid.map((r) => r.toList()).toList(),
        'words': _words,
        'positions': _placements.map((p) => p.toJson()).toList(),
      });
    }
  }

  // ── Cell tap ──────────────────────────────────────────────────────────────

  void _onCellTap(int row, int col) {
    if (_gameOver) return;
    if (_grid.isEmpty) return;

    if (_selectStart == null) {
      // First tap
      setState(() {
        _selectStart = (row, col);
        _statusMsg = L.wurdsikerij.tapLast;
      });
      HapticFeedback.selectionClick();
    } else {
      // Second tap — check if it forms a valid word
      final (sr, sc) = _selectStart!;
      setState(() { _selectStart = null; _statusMsg = null; });

      // Must be a straight line: same row, same column or a 45° diagonal
      final dRow = row - sr, dCol = col - sc;
      if (dRow == 0 && dCol == 0) return;
      if (dRow != 0 && dCol != 0 && dRow.abs() != dCol.abs()) {
        setState(() => _statusMsg = L.wurdsikerij.notAWord);
        _clearStatus();
        return;
      }

      // Read the letters from the first tap to the second; either end may be
      // tapped first, so also try the word the other way round.
      final len = math.max(dRow.abs(), dCol.abs()) + 1;
      final stepR = dRow.sign, stepC = dCol.sign;
      var extracted = '';
      for (int i = 0; i < len; i++) {
        extracted += _grid[sr + stepR * i][sc + stepC * i];
      }
      if (!_words.contains(extracted)) {
        extracted = extracted.split('').reversed.join();
      }

      // Check if this matches a hidden word
      if (_words.contains(extracted) && !_foundWords.containsKey(extracted)) {
        final myIdx = _net.myIdx.clamp(0, widget.players.length - 1);
        // Joiner: optimistic local credit + claim; the host arbitrates the owner.
        // Host: first claim processed wins; broadcast the authoritative result.
        _wordFound(extracted, myIdx);
        if (_net.isHost) {
          _broadcastFound(extracted);
        } else {
          _net.send('WSK_FOUND', {'word': extracted, 'playerIdx': myIdx});
        }
        HapticFeedback.mediumImpact();
      } else {
        setState(() => _statusMsg = L.wurdsikerij.notAWord);
        _clearStatus();
      }
    }
  }

  void _wordFound(String word, int playerIdx) {
    setState(() {
      _foundWords[word] = playerIdx;
    });
    // Only the host decides when the game is over (joiners wait for its result)
    if (_net.isHost && _foundWords.length >= _words.length) {
      _endGame();
    }
  }

  /// Host: send the authoritative owner of [word] plus the full found list.
  void _broadcastFound(String word) {
    if (_net.isSolo) return;
    _net.send('WSK_FOUND', {
      'word': word,
      'playerIdx': _foundWords[word] ?? -1,
      'found': _foundWords.map((k, v) => MapEntry(k, v)),
      'over': _gameOver,
    });
  }

  void _endGame() {
    if (_gameOver) return;
    _stopwatch.stop();
    setState(() => _gameOver = true);
  }

  void _clearStatus() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _statusMsg = null);
    });
  }

  // ── Network messages ──────────────────────────────────────────────────────

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (msg['type'] as String) {
      case 'WSK_GRID':
        final gridRaw = msg['grid'] as List;
        final wordsRaw = msg['words'] as List;
        final posRaw = msg['positions'] as List;
        setState(() {
          _grid = gridRaw.map((r) =>
              (r as List).map((c) => c as String).toList()).toList();
          _words = wordsRaw.cast<String>();
          _placements = posRaw.map((p) =>
              _WordPlacement.fromJson(Map<String, dynamic>.from(p as Map))).toList();
          _foundWords = {};
          _gameOver = false;
          _selectStart = null;
        });

      case 'WSK_FOUND':
        final word = msg['word'] as String;
        if (_net.isHost) {
          // Joiner claim: the first claim the host processes owns the word
          if (!_words.contains(word)) break;
          if (!_foundWords.containsKey(word) && !_gameOver) {
            _wordFound(word, fromIdx.clamp(0, widget.players.length - 1));
          }
          _broadcastFound(word);
        } else {
          // Authoritative result from the host: its owners override ours;
          // keep our own not-yet-confirmed claims until the host answers.
          final foundRaw = msg['found'] as Map?;
          if (foundRaw == null) break;
          final hostFound = foundRaw.map((k, v) => MapEntry(k as String, v as int));
          final myIdx = _net.myIdx.clamp(0, widget.players.length - 1);
          setState(() {
            _foundWords = {
              for (final e in _foundWords.entries)
                if (e.value == myIdx && !hostFound.containsKey(e.key)) e.key: e.value,
              ...hostFound,
            };
          });
          if (msg['over'] as bool? ?? false) _endGame();
        }
        break;

      case 'GAME_RESET':
        if (!_net.isHost) {
          resetConfetti();
          resetStats();
          setState(() {
            _grid = [];
            _words = [];
            _placements = [];
            _foundWords = {};
            _gameOver = false;
            _selectStart = null;
          });
        }

      case 'WSK_SYNC':
        if (!_net.isHost) _applySync(msg);

      case 'WSK_SYNC_REQ':
        if (_net.isHost && !_net.isSolo) _sendSync(toIdx: fromIdx);
    }
  }

  void _sendSync({int? toIdx}) {
    if (_grid.isEmpty) return;
    final payload = <String, dynamic>{
      'grid': _grid.map((r) => r.toList()).toList(),
      'words': _words,
      'positions': _placements.map((p) => p.toJson()).toList(),
      'found': _foundWords.map((k, v) => MapEntry(k, v)),
      'over': _gameOver,
    };
    // Answer a request only to the asker so other joiners aren't disturbed
    if (toIdx != null && toIdx > 0) {
      _net.sendTo(toIdx, 'WSK_SYNC', payload);
    } else {
      _net.send('WSK_SYNC', payload);
    }
  }

  void _applySync(Map<String, dynamic> msg) {
    final gridRaw = msg['grid'] as List;
    final wordsRaw = msg['words'] as List;
    final posRaw = msg['positions'] as List;
    final foundRaw = msg['found'] as Map;
    final newWords = wordsRaw.cast<String>();
    // A late/duplicate sync for the same grid must not drop words this
    // joiner already found locally (host may not have processed them yet).
    final sameGrid = _words.isNotEmpty && _words.join(',') == newWords.join(',');
    final keepFound = sameGrid ? Map<String, int>.from(_foundWords) : <String, int>{};
    final wasOver = sameGrid && _gameOver;
    setState(() {
      _grid = gridRaw.map((r) =>
          (r as List).map((c) => c as String).toList()).toList();
      _words = wordsRaw.cast<String>();
      _placements = posRaw.map((p) =>
          _WordPlacement.fromJson(Map<String, dynamic>.from(p as Map))).toList();
      _foundWords = {
        ...keepFound,
        ...foundRaw.map((k, v) => MapEntry(k as String, v as int)),
      };
      _gameOver = (msg['over'] as bool) || wasOver;
    });
  }

  void _reset() {
    resetConfetti();
    resetStats();
    _net.send('GAME_RESET');
    _stopwatch.reset();
    if (_net.isSolo) {
      _stopwatch.start();
    }
    _generateAndSend();
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _sendSync();
          else _net.send('WSK_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Get the set of (row, col) cells that belong to found words, mapped to player index.
  Map<(int, int), int> get _foundCells {
    final cells = <(int, int), int>{};
    for (final placement in _placements) {
      if (!_foundWords.containsKey(placement.word)) continue;
      final pIdx = _foundWords[placement.word]!;
      for (int i = 0; i < placement.word.length; i++) {
        cells[placement.cell(i)] = pIdx;
      }
    }
    return cells;
  }

  int _playerFoundCount(int playerIdx) =>
      _foundWords.values.where((v) => v == playerIdx).length;

  int get _winnerIdx {
    if (!_gameOver) return -2; // not over
    if (_net.isSolo) return 0; // solo always wins
    if (widget.players.length == 1) return 0;

    // Find player with most words
    int bestIdx = 0;
    int bestCount = 0;
    bool tie = false;
    for (int i = 0; i < widget.players.length; i++) {
      final c = _playerFoundCount(i);
      if (c > bestCount) { bestCount = c; bestIdx = i; tie = false; }
      else if (c == bestCount && i != bestIdx) { tie = true; }
    }
    return tie ? -1 : bestIdx; // -1 for draw
  }

  String get _timerText {
    final secs = _stopwatch.elapsed.inSeconds;
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override Widget build(BuildContext context) {
    // Loading state
    if (_grid.isEmpty) {
      return GameScaffold(
        key: scaffoldKey,
        title: L.wurdsikerij.gameName,
        players: widget.players,
        chatMessages: chatMessages,
        onSendChat: sendChat,
        typingName: typingName,
        onLocalTyping: onLocalTyping,
        onReadAck: sendReadAck,
        rules: L.wurdsikerij.rules,
        child: const Center(child: CircularProgressIndicator(color: kPurple)),
      );
    }

    final foundCells = _foundCells;
    final scores = List.generate(
      widget.players.length,
      (i) => _playerFoundCount(i),
    );

    return GameScaffold(
      key: scaffoldKey,
      title: L.wurdsikerij.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.wurdsikerij.rules,
      child: Column(children: [
        // Player bar
        PlayerBar(
          players: widget.players,
          activeIdx: -1,
          scores: scores,
          scoreLabel: ' ${L.wurdsikerij.wordsFound}',
        ),
        GameStatusBar(text: _net.isSolo ? '${L.wurdsikerij.timeLabel}: $_timerText' : null),

        // Status message
        if (_statusMsg != null && !_gameOver)
          Container(
            width: double.infinity,
            color: kPurple2.withValues(alpha: 0.2),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(_statusMsg!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kText, fontSize: 13,
                fontStyle: FontStyle.italic)),
          )
        else if (!_gameOver && _selectStart == null)
          Container(
            width: double.infinity,
            color: Colors.black26,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(L.wurdsikerij.tapFirst,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted, fontSize: 12)),
          ),

        // Grid
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(builder: (_, constraints) {
              final gridSize = constraints.maxWidth;
              final cellSize = gridSize / _grid.length;
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: kBorder, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Column(
                    children: List.generate(_grid.length, (r) =>
                      Row(
                        children: List.generate(_grid[r].length, (c) {
                          final isFound = foundCells.containsKey((r, c));
                          final finderIdx = foundCells[(r, c)];
                          final isSelected = _selectStart != null &&
                              _selectStart!.$1 == r && _selectStart!.$2 == c;

                          Color bg = Colors.transparent;
                          Color textColor = kText;

                          if (isFound && finderIdx != null) {
                            final pColor = finderIdx < widget.players.length
                                ? widget.players[finderIdx].color
                                : kPurple;
                            bg = pColor.withValues(alpha: 0.3);
                            textColor = pColor;
                          }
                          if (isSelected) {
                            bg = kPurple.withValues(alpha: 0.4);
                            textColor = Colors.white;
                          }

                          return GestureDetector(
                            onTap: () => _onCellTap(r, c),
                            child: Container(
                              width: cellSize,
                              height: cellSize,
                              decoration: BoxDecoration(
                                color: bg,
                                border: Border.all(
                                  color: isSelected
                                      ? kPurple
                                      : Colors.white.withValues(alpha: 0.08),
                                  width: isSelected ? 1.5 : 0.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _grid[r][c],
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: cellSize * 0.48,
                                  fontWeight: isFound
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ))),

        // Word list
        Container(
          constraints: const BoxConstraints(maxHeight: 100),
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
          ),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              children: _words.map((word) {
                final found = _foundWords.containsKey(word);
                final finderIdx = _foundWords[word];
                final color = found && finderIdx != null &&
                        finderIdx < widget.players.length
                    ? widget.players[finderIdx].color
                    : kMuted;
                return Text(
                  word,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: found ? FontWeight.bold : FontWeight.normal,
                    decoration: found ? TextDecoration.lineThrough : null,
                    decorationColor: color,
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Game over
        if (_gameOver) ...[
          GameResultBanner(
            players: widget.players,
            winnerIdx: _winnerIdx,
            onFirstRender: () {
              final wi = _winnerIdx;
              fireConfettiOnce(wi);
              recordResult('wurdsikerij', wi);
              if (_net.isHost) SessionState().advanceGame();
            },
            scores: [
              ...List.generate(widget.players.length, (i) =>
                (label: widget.players[i].name,
                 value: '${_playerFoundCount(i)}')),
              if (_net.isSolo)
                (label: L.wurdsikerij.timeLabel, value: _timerText),
            ],
          ),
          GameOverActions(
            players: widget.players,
            onReset: _reset,
            sendReset: false,
          ),
        ] else
          const SizedBox(height: 4),
      ]),
    );
  }
}
