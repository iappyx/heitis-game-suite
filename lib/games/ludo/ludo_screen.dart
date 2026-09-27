import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/animated_die.dart';
import '../../core/network.dart';
import '../../core/player.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../screens/lobby_screen.dart';
import '../../widgets/game_mixin.dart';
import '../../widgets/game_scaffold.dart';
import '../../widgets/game_over_actions.dart';
import '../../widgets/game_result_banner.dart';
import '../../widgets/player_bar.dart';
import '../../widgets/game_status_bar.dart';
import '../../widgets/reconnect_dialog.dart';
import 'ludo_ai.dart';
import '../../core/solo_ai.dart';
import '../../core/sound_player.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Board geometry — 13×13 grid (cols 0-12, rows 0-12)
//
//  row 1:  N   H1  H1  N   N   R   R   S2  N   N   H2  H2  N
//  row 5:  N   S1  R   R   R   R   F2  R   R   R   R   R   N
//  row 6:  N   R   F1  F1  F1  F1  N   F3  F3  F3  F3  R   N
//  row 7:  N   R   R   R   R   R   F4  R   R   R   R   S3  N
//  row11:  N   H4  H4  N   N   S4  R   R   N   N   H3  H3  N
//  Centre (6,6) = empty — die widget sits here.
// ─────────────────────────────────────────────────────────────────────────────

const _kTrack = <(int,int)>[
  (1,5),(2,5),(3,5),(4,5),(5,5),   // 0-4   S1=0
  (5,4),(5,3),(5,2),(5,1),          // 5-8
  (6,1),                            // 9     turn-off Blue
  (7,1),                            // 10    S2=10
  (7,2),(7,3),(7,4),(7,5),          // 11-14
  (8,5),(9,5),(10,5),(11,5),        // 15-18
  (11,6),                           // 19    turn-off Green
  (11,7),                           // 20    S3=20
  (10,7),(9,7),(8,7),(7,7),         // 21-24
  (7,8),(7,9),(7,10),(7,11),        // 25-28
  (6,11),                           // 29    turn-off Yellow
  (5,11),                           // 30    S4=30
  (5,10),(5,9),(5,8),(5,7),         // 31-34
  (4,7),(3,7),(2,7),(1,7),          // 35-38
  (1,6),                            // 39    turn-off Red
];

const _kEntry   = [0, 10, 20, 30];
const _kTurnOff = [39, 9, 19, 29];

const _kHome = <List<(int,int)>>[
  [(2,6),(3,6),(4,6),(5,6)],         // F1 slot0 row6 →
  [(6,2),(6,3),(6,4),(6,5)],         // F2 slot1 col6 ↓
  [(10,6),(9,6),(8,6),(7,6)],        // F3 slot2 row6 ←
  [(6,10),(6,9),(6,8),(6,7)],        // F4 slot3 col6 ↑
];

// Nest top-left corners (2×2 block each)
const _kNestTL = <(int,int)>[(1,1),(10,1),(10,10),(1,10)];

// ─────────────────────────────────────────────────────────────────────────────
// Position encoding
//   -1    : in nest
//   0-39  : outer track index
//   40-43 : home column step 0-3  (43 = deepest)
// ─────────────────────────────────────────────────────────────────────────────
const _kPosNest   = -1;
const _kHomeStart = 40;
const _kHomeEnd   = 43;

(int,int) _squareForPos(int slot, int pos) {
  if (pos >= _kHomeStart && pos <= _kHomeEnd) return _kHome[slot][pos - _kHomeStart];
  if (pos >= 0 && pos < 40) return _kTrack[pos];
  return (6,6);
}

/// Compute final position after [steps] moves from [pos] for [slot].
/// Applies bounce-back in home column.
/// Does NOT check occupancy — caller checks final result.
int _computeTarget(int slot, int pos, int steps) {
  int cur = pos;
  for (int s = 0; s < steps; s++) {
    if (cur >= _kHomeStart) {
      cur++;
      if (cur > _kHomeEnd) cur = _kHomeEnd - (cur - _kHomeEnd);
    } else if (cur == _kTurnOff[slot]) {
      cur = _kHomeStart;
    } else {
      cur = (cur + 1) % 40;
    }
  }
  return cur;
}

/// Returns true if [piece pi of slot] can legally move with [roll].
/// [pieces] = current full board state.
bool _canMove(int slot, int pi, int roll, List<List<int>> pieces) {
  final pos = pieces[slot][pi];
  if (pos == _kPosNest) return roll == 6;
  if (pos == _kHomeEnd) return false; // deepest, can never move
  final target = _computeTarget(slot, pos, roll);
  // Cannot land on own square (bounce-back to self = stuck)
  if (target == pos) return false;
  // Cannot land on own piece in home column
  if (target >= _kHomeStart) {
    for (int p2 = 0; p2 < 4; p2++) {
      if (p2 != pi && pieces[slot][p2] == target) return false;
    }
  }
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Slot map
// ─────────────────────────────────────────────────────────────────────────────
List<int> _slotMap(int n) {
  if (n == 2) return [0, 2];
  if (n == 3) return [0, 1, 2];
  return [0, 1, 2, 3];
}

// ─────────────────────────────────────────────────────────────────────────────
// LudoScreen
// ─────────────────────────────────────────────────────────────────────────────
class LudoScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const LudoScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen>
    with TickerProviderStateMixin, GameMixin<LudoScreen> {

  final _net = Network();
  @override List<Player> get gamePlayers => widget.players;

  late List<int> _slots;
  late int _numPlayers;
  late int _myPlayerIndex;

  late List<List<int>> _pieces;
  int  _currentSlot      = 0;
  int  _lastRoll         = 0;
  bool _rolled           = false;
  bool _rolling          = false;
  int  _consecutiveSixes = 0;
  int  _winner           = -1;
  // All pieces this player may move (outside + home combined freely)
  List<int> _validPieces = [];
  // True when the player has rolled and all valid pieces are home-only
  // (pass is then available)
  bool _canPass          = false;
  // Joiner: move sent, ignore piece taps until the next LUD_SYNC arrives
  bool _awaitingSync     = false;

  AnimationController? _moveCtrl;
  List<(int,int)> _movePath      = [];
  int             _animSlot      = -1;
  int             _animPiece     = -1;
  List<List<int>> _preAnimPieces = [];

  final Map<int, ui.Image> _avatarImages = {};

  bool get _isMyTurn => _currentSlot == _mySlot;
  int  get _mySlot   => _slots[_myPlayerIndex];
  bool get _gameOver => _winner >= 0;
  int  _playerForSlot(int slot) => _slots.indexOf(slot);

  // AI for solo mode (one per AI player slot)
  List<LudoAI> _ais = [];
  bool get _isAiTurn => _net.isSolo && _currentSlot != _mySlot;

  void _maybeScheduleAI() {
    if (!_isAiTurn || _gameOver) return;
    final aiPlayerIdx = _playerForSlot(_currentSlot) - 1;
    if (aiPlayerIdx < 0 || aiPlayerIdx >= _ais.length) return;
    final ai = _ais[aiPlayerIdx];
    ai.takeTurn(
      slot:     _currentSlot,
      roll:     _lastRoll,
      rolled:   _rolled,
      canPass:  _canPass,
      pieces:   _pieces.map((pp) => List<int>.from(pp)).toList(),
      slots:    _slots,
    );
  }

  // Colour for a slot — uses lobby player colour
  Color _slotColor(int slot) {
    final pi = _playerForSlot(slot);
    if (pi >= 0 && pi < widget.players.length) return widget.players[pi].color;
    // Inactive slot fallback colours (not used as pieces, just for board drawing)
    const fallback = [Color(0xFFD32F2F), Color(0xFF1565C0),
                      Color(0xFF2E7D32), Color(0xFFF9A825)];
    return fallback[slot];
  }

  @override
  void initState() {
    super.initState();
    _numPlayers    = widget.players.length.clamp(2, 4);
    _myPlayerIndex = _net.myIdx.clamp(0, widget.players.length - 1);
    _slots         = _slotMap(_numPlayers);
    _initGame();
    _loadAvatars();
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
    _sendMyAvatar();
    if (_net.isSolo) {
      final diffIdx = (widget.extra?['difficulty'] as int?) ?? SoloDifficulty.medium.index;
      final diff = SoloDifficulty.values[diffIdx.clamp(0, 2)];
      _ais = List.generate(_numPlayers - 1, (_) => LudoAI(diff));
      _maybeScheduleAI();
    }
  }

  @override
  void dispose() {
    msgSub?.cancel();
    for (final ai in _ais) ai.cancel();
    _moveCtrl?.dispose();
    for (final img in _avatarImages.values) img.dispose();
    super.dispose();
  }

  // ── Avatar exchange ───────────────────────────────────────────────────────
  void _sendMyAvatar() {
    final b64 = SessionState().myAvatarB64;
    if (b64 == null) return;
    final me = widget.players[_myPlayerIndex];
    _net.send('LUD_AVATAR', {'name': me.name, 'avatar': b64});
  }

  void _handleAvatar(Map<String, dynamic> msg, int fromIdx) {
    final name = msg['name'] as String?;
    final b64  = msg['avatar'] as String?;
    if (name == null || b64 == null) return;
    try {
      final bytes = base64Decode(b64);
      SessionState().cacheAvatar(name, bytes);
      // Host rebroadcasts to all so every player gets every avatar
      if (_net.isHost) _net.send('LUD_AVATAR', {'name': name, 'avatar': b64});
      _refreshAvatars();
    } catch (_) {}
  }

  Future<void> _loadAvatars() async {
    final session = SessionState();
    for (int pi = 0; pi < widget.players.length; pi++) {
      if (_avatarImages.containsKey(pi)) continue;
      final player = widget.players[pi];
      Uint8List? bytes;
      if (player.avatarPath != null) {
        final file = File(player.avatarPath!);
        if (await file.exists()) {
          try { bytes = await file.readAsBytes(); } catch (_) {}
        }
      }
      bytes ??= session.avatarFor(player.name);
      if (bytes == null) continue;
      try {
        final codec = await ui.instantiateImageCodec(
            bytes, targetWidth: 64, targetHeight: 64);
        final frame = await codec.getNextFrame();
        if (mounted) setState(() => _avatarImages[pi] = frame.image);
      } catch (_) {}
    }
  }

  void _refreshAvatars() {
    final session = SessionState();
    bool needLoad = false;
    for (int pi = 0; pi < widget.players.length; pi++) {
      if (_avatarImages.containsKey(pi)) continue;
      if (session.avatarFor(widget.players[pi].name) != null) needLoad = true;
    }
    if (needLoad) _loadAvatars();
  }

  // ── Game init ─────────────────────────────────────────────────────────────
  void _initGame() {
    _pieces = List.generate(4, (_) => List.filled(4, _kPosNest));
    _currentSlot      = _slots[(widget.firstPlayer - 1).clamp(0, _slots.length - 1)];
    _lastRoll         = 0;
    _rolled           = false;
    _rolling          = false;
    _consecutiveSixes = 0;
    _winner           = -1;
    _validPieces      = [];
    _canPass          = false;
    _movePath         = [];
    _animSlot         = -1;
    _animPiece        = -1;
    _moveCtrl?.dispose();
    _moveCtrl         = null;
    _preAnimPieces    = [];
  }

  // ── Network ───────────────────────────────────────────────────────────────
  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    if (!mounted) return;
    final type = msg['type'] as String? ?? '';
    if (handleCommonMessages(msg, fromIdx)) {
      if (type == 'CHAT') _refreshAvatars();
      return;
    }
    switch (type) {
      case 'LUD_ROLL':   if (_net.isHost && _senderIsCurrent(fromIdx)) _hostDoRoll(); break;
      case 'LUD_MOVE':
        if (_net.isHost) {
          final slot = msg['slot'] as int? ?? -1;
          final pi   = msg['pi']   as int? ?? -1;
          final ok = _senderIsCurrent(fromIdx) && _hostDoMove(slot, pi);
          // Rejected (duplicate/out-of-turn/illegal): re-sync so the sender
          // clears its waiting flag.
          if (!ok) _sendSync();
        }
        break;
      case 'LUD_PASS':   if (_net.isHost && _senderIsCurrent(fromIdx)) _hostDoPass(); break;
      case 'LUD_SYNC':   _handleSync(msg);                      break;
      case 'LUD_SYNC_REQ':
        if (_net.isHost) _sendSync();
        break;
      case 'LUD_RESET':  resetConfetti(); resetStats(); _awaitingSync = false; setState(_initGame); if (_net.isSolo) _maybeScheduleAI(); break;
      case 'LUD_RESET_REQ': if (_net.isHost) _resetGame(); break;
      case 'LUD_AVATAR': _handleAvatar(msg, fromIdx);           break;
    }
  }

  /// Host: true if a remote message from [fromIdx] comes from the player
  /// whose turn it is. In solo mode all AI moves are injected with
  /// fromIdx 1, so only require that it is not the human's turn.
  bool _senderIsCurrent(int fromIdx) {
    if (_net.isSolo) return _currentSlot != _mySlot;
    return fromIdx != _myPlayerIndex && _playerForSlot(_currentSlot) == fromIdx;
  }

  // ── Roll ──────────────────────────────────────────────────────────────────
  void _requestRoll() {
    SoundPlayer.i.singleDieRoll();
    if (!_isMyTurn || _rolled || _gameOver || _animSlot >= 0) return;
    if (_net.isHost) _hostDoRoll();
    else _net.send('LUD_ROLL');
  }

  void _hostDoRoll() {
    if (_rolled || _gameOver) return;
    final roll = Random().nextInt(6) + 1;
    final newConsec = roll == 6 ? _consecutiveSixes + 1 : 0;
    if (newConsec >= 3) {
      _broadcastSync(roll: roll, slot: _nextSlot(_currentSlot),
          rolled: false, consec: 0);
      return;
    }
    _broadcastSync(roll: roll, slot: _currentSlot, rolled: true, consec: newConsec);
  }

  // ── Pass ──────────────────────────────────────────────────────────────────
  void _requestPass() {
    if (!_isMyTurn || !_rolled || !_canPass || _gameOver || _animSlot >= 0) return;
    if (_net.isHost) _hostDoPass();
    else _net.send('LUD_PASS');
  }

  void _hostDoPass() {
    if (!_rolled || _gameOver) return;
    _broadcastSync(roll: _lastRoll, slot: _nextSlot(_currentSlot),
        rolled: false, consec: 0);
  }

  // ── Move ──────────────────────────────────────────────────────────────────
  void _tapPiece(int slot, int pieceIdx) {
    SoundPlayer.i.ludoMove();
    if (!_isMyTurn || !_rolled || _gameOver || _animSlot >= 0 || _awaitingSync) return;
    if (slot != _mySlot || !_validPieces.contains(pieceIdx)) return;
    if (_net.isHost) {
      _hostDoMove(slot, pieceIdx);
    } else {
      _awaitingSync = true;
      _net.send('LUD_MOVE', {'slot': slot, 'pi': pieceIdx});
    }
  }

  /// Applies a move on the host. Returns false (and does nothing) if the move
  /// is not legal right now: not rolled yet, wrong slot, or illegal piece move.
  bool _hostDoMove(int slot, int pieceIdx) {
    if (!_rolled || _gameOver || slot != _currentSlot) return false;
    if (pieceIdx < 0 || pieceIdx > 3) return false;
    if (!_canMove(slot, pieceIdx, _lastRoll, _pieces)) return false;
    final roll   = _lastRoll;
    final oldPos = _pieces[slot][pieceIdx];
    final newPos = oldPos == _kPosNest
        ? _kEntry[slot]
        : _computeTarget(slot, oldPos, roll);

    final animPath = _buildPath(slot, oldPos, newPos);
    final newPieces = _pieces.map((pp) => List<int>.from(pp)).toList();

    // Captures: any opponent piece on the same outer track square
    if (newPos >= 0 && newPos < 40) {
      for (int s = 0; s < 4; s++) {
        if (s == slot) continue;
        for (int pi = 0; pi < 4; pi++) {
          if (newPieces[s][pi] == newPos) newPieces[s][pi] = _kPosNest;
        }
      }
    }
    newPieces[slot][pieceIdx] = newPos;

    // Win: all 4 pieces are in the home column
    int winner = -1;
    if (newPieces[slot].every((p) => p >= _kHomeStart)) winner = slot;

    final extraRoll = roll == 6;
    final nextSlot  = (winner >= 0 || extraRoll) ? slot : _nextSlot(slot);

    _broadcastSync(
      pieces: newPieces, roll: roll, slot: nextSlot,
      rolled: false, consec: extraRoll ? _consecutiveSixes : 0,
      winner: winner, animSlot: slot, animPiece: pieceIdx, animPath: animPath,
    );
    return true;
  }

  // ── Path building ─────────────────────────────────────────────────────────
  List<(int,int)> _buildPath(int slot, int oldPos, int newPos) {
    if (oldPos == _kPosNest) {
      return [_nestCenter(slot), _squareForPos(slot, newPos)];
    }
    final path = <(int,int)>[_squareForPos(slot, oldPos)];
    int cur = oldPos;
    for (int guard = 0; guard < 50; guard++) {
      if (cur == newPos) break;
      int next;
      if (cur >= _kHomeStart) {
        next = cur + 1;
        if (next > _kHomeEnd) next = _kHomeEnd - (next - _kHomeEnd);
      } else if (cur == _kTurnOff[slot]) {
        next = _kHomeStart;
      } else {
        next = (cur + 1) % 40;
      }
      cur = next;
      path.add(_squareForPos(slot, cur));
    }
    return path;
  }

  (int,int) _nestCenter(int slot) {
    final (nc,nr) = _kNestTL[slot];
    return (nc, nr); // top-left cell of nest
  }

  // ── Broadcast & sync ──────────────────────────────────────────────────────
  /// Sends a complete current-state snapshot to all peers (used on reconnect).
  void _sendSync() {
    _net.send('LUD_SYNC', {
      'pieces':    _pieces.map((pp) => pp.toList()).toList(),
      'roll':      _lastRoll,
      'slot':      _currentSlot,
      'rolled':    _rolled ? 1 : 0,
      'consec':    _consecutiveSixes,
      'winner':    _winner,
      'animSlot':  -1,  // no animation replay on reconnect
      'animPiece': -1,
      'path':      <int>[],
    });
  }

  void _showReconnect() {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _sendSync();
          else _net.send('LUD_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(
          context,
          fadeScaleRoute(const LobbyScreen()),
          (_) => false,
        ),
      ),
    );
  }

  void _broadcastSync({
    List<List<int>>? pieces,
    required int roll, required int slot, required bool rolled,
    int consec = 0, int winner = -1,
    int animSlot = -1, int animPiece = -1,
    List<(int,int)>? animPath,
  }) {
    pieces ??= _pieces;
    final flat = animPath?.expand((p) => [p.$1, p.$2]).toList() ?? <int>[];
    final payload = {
      'pieces': pieces.map((pp) => pp.toList()).toList(),
      'roll': roll, 'slot': slot, 'rolled': rolled ? 1 : 0,
      'consec': consec, 'winner': winner,
      'animSlot': animSlot, 'animPiece': animPiece, 'path': flat,
    };
    _net.send('LUD_SYNC', payload);
    _handleSync({'type': 'LUD_SYNC', ...payload});
  }

  void _handleSync(Map<String, dynamic> msg) {
    if (!mounted) return;
    final wasMyTurn = _isMyTurn;
    try {
      final rawPieces = msg['pieces'] as List;
      final newPieces = rawPieces
          .map((pp) => (pp as List).map((v) => v as int).toList())
          .toList();
      final roll      = msg['roll']      as int;
      final slot      = msg['slot']      as int;
      final rolled    = (msg['rolled']   as int) == 1;
      final consec    = msg['consec']    as int;
      final winner    = msg['winner']    as int;
      final animSlot  = msg['animSlot']  as int;
      final animPiece = msg['animPiece'] as int;
      final flat      = (msg['path'] as List).cast<int>();
      final animPath  = <(int,int)>[];
      for (int i = 0; i + 1 < flat.length; i += 2) {
        animPath.add((flat[i], flat[i+1]));
      }

      // Compute valid pieces: any piece that can legally move
      final valid = <int>[];
      if (rolled && winner < 0) {
        for (int pi = 0; pi < 4; pi++) {
          if (_canMove(slot, pi, roll, newPieces)) valid.add(pi);
        }
      }
      // canPass: player has rolled, has valid moves, but ALL valid pieces are in home
      // (so they may choose to pass instead of moving a home piece)
      final allHome = valid.isNotEmpty &&
          valid.every((pi) => newPieces[slot][pi] >= _kHomeStart);

      setState(() {
        _awaitingSync     = false;
        _currentSlot      = slot;
        _lastRoll         = roll;
        _rolled           = rolled;
        _rolling          = rolled;
        _consecutiveSixes = consec;
        _winner           = winner;
        _validPieces      = valid;
        _canPass          = allHome;

        if (animSlot >= 0 && animPath.isNotEmpty) {
          _preAnimPieces = _pieces.map((pp) => List<int>.from(pp)).toList();
          _pieces        = newPieces;
          _animSlot      = animSlot;
          _animPiece     = animPiece;
          _movePath      = animPath;
          _startMoveAnim();
        } else {
          _pieces = newPieces;
        }

        // Auto-advance if no valid moves at all
        // Roll of 6 with no valid moves: grant another roll (same slot), don't pass turn
        if (rolled && valid.isEmpty && winner < 0 && _animSlot < 0) {
          Future.delayed(const Duration(milliseconds: 900), () {
            if (!mounted || !_rolled || _validPieces.isNotEmpty) return;
            if (_net.isHost) {
              final nextSlot = _lastRoll == 6 ? _currentSlot : _nextSlot(_currentSlot);
              _broadcastSync(roll: _lastRoll,
                  slot: nextSlot, rolled: false, consec: 0);
            }
          });
        }
      });

      if (rolled) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _rolling = false);
        });
      }
      if (!wasMyTurn && _isMyTurn && !_gameOver) turnChanged();
      // Trigger AI if it's an AI player's turn
      if (_net.isSolo && winner < 0) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) _maybeScheduleAI();
        });
      }
    } catch (_) {}
  }

  void _startMoveAnim() {
    _moveCtrl?.dispose();
    final steps = max(1, _movePath.length - 1);
    _moveCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (steps * 110).clamp(150, 1400)),
    )
      ..addListener(() => setState(() {}))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() {
            _animSlot = -1; _animPiece = -1;
            _movePath = []; _preAnimPieces = [];
          });
        }
      })
      ..forward();
  }

  int _nextSlot(int cur) {
    final idx = _slots.indexOf(cur);
    return _slots[(idx + 1) % _slots.length];
  }

  void _resetGame() {
    for (final ai in _ais) ai.cancel();
    resetConfetti();
    resetStats();
    if (!_net.isHost) {
      _net.send('LUD_RESET_REQ', {});
      return;
    }
    _net.send('LUD_RESET');
    setState(_initGame);
    if (_net.isSolo) _maybeScheduleAI();
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final activeIdx = _playerForSlot(_currentSlot);

    return GameScaffold(
        key: scaffoldKey,
      title: L.ludo.gameName,
      players: widget.players,
      chatMessages: chatMessages,
      onSendChat: sendChat,
      typingName: typingName,
      onLocalTyping: onLocalTyping,
      onReadAck: sendReadAck,
      rules: L.ludo.rules,
      child: Column(children: [
        PlayerBar(players: widget.players, activeIdx: activeIdx),
        _buildStatusBar(),
        Expanded(
          child: LayoutBuilder(builder: (_, bc) {
            final boardSz = min(bc.maxWidth, bc.maxHeight);
            final cell    = boardSz / 13;
            final dieSize = cell * 1.3;
            final dieLeft = 6 * cell + (cell - dieSize) / 2;
            final dieTop  = 6 * cell + (cell - dieSize) / 2;
            return Center(
              child: SizedBox(
                width: boardSz, height: boardSz,
                child: Stack(children: [
                  GestureDetector(
                    onTapUp: (d) => _onBoardTap(d.localPosition, boardSz),
                    child: CustomPaint(
                      size: Size(boardSz, boardSz),
                      painter: _LudoPainter(
                        pieces:       _pieces,
                        preAnim:      _preAnimPieces,
                        animSlot:     _animSlot,
                        animPiece:    _animPiece,
                        animPath:     _movePath,
                        animT:        _moveCtrl?.value ?? 0.0,
                        validPieces:  _isMyTurn ? _validPieces : [],
                        mySlot:       _mySlot,
                        slots:        _slots,
                        players:      widget.players,
                        avatarImages: _avatarImages,
                        currentSlot:  _currentSlot,
                        slotColor:    _slotColor,
                      ),
                    ),
                  ),
                  Positioned(
                    left: dieLeft, top: dieTop,
                    width: dieSize, height: dieSize,
                    child: AnimatedDie(
                      value:   _lastRoll > 0 ? _lastRoll : 1,
                      rolling: _rolling,
                      size:    dieSize,
                      onTap:   (!_rolled && _isMyTurn && !_gameOver && _animSlot < 0)
                                 ? _requestRoll : null,
                    ),
                  ),
                ]),
              ),
            );
          }),
        ),
        if (_gameOver) ...[
          GameResultBanner(players: widget.players,
              winnerIdx: _playerForSlot(_winner),
              onFirstRender: () { fireConfettiOnce(_playerForSlot(_winner)); recordResult('ludo', _playerForSlot(_winner)); if (_net.isHost) SessionState().advanceGame(); }),
          GameOverActions(players: widget.players,
              sendReset: false,
              onReset: _resetGame),
        ],
      ]),
    );
  }

  Widget _buildStatusBar() {
    final s = L.ludo;
    String text; Color color = kMuted;
    if (_gameOver) {
      final wi = _playerForSlot(_winner);
      final wn = wi >= 0 && wi < widget.players.length
          ? widget.players[wi].name : '?';
      text  = L.common.wins.fmt({'player': wn});
      color = kText;
    } else if (_animSlot >= 0) {
      text = '…';
    } else if (_isMyTurn) {
      text  = _rolled
          ? s.rolledN.replaceAll('{n}', '$_lastRoll')
          : s.yourTurnRoll;
      color = kGreen;
    } else {
      final pi = _playerForSlot(_currentSlot);
      final nm = pi >= 0 && pi < widget.players.length
          ? widget.players[pi].name : 'P${_currentSlot+1}';
      text = s.opponentTurn.replaceAll('{player}', nm);
    }

    Widget? passAction;
    if (_canPass && _isMyTurn && !_gameOver && _animSlot < 0) {
      passAction = GestureDetector(
        onTap: _requestPass,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder)),
          child: Text(L.ludo.pass,
              style: const TextStyle(color: kMuted, fontSize: 12)),
        ),
      );
    }

    return GameStatusBar(text: text, textColor: color, action: passAction);
  }

  void _onBoardTap(Offset local, double boardPx) {
    if (!_isMyTurn || !_rolled || _gameOver || _animSlot >= 0) return;
    final cell = boardPx / 13;
    final col  = (local.dx / cell).floor();
    final row  = (local.dy / cell).floor();
    for (final pi in _validPieces) {
      final pos = _pieces[_mySlot][pi];
      if (pos == _kPosNest) {
        if (_inNestArea(_mySlot, col, row)) { _tapPiece(_mySlot, pi); return; }
      } else {
        final (pc,pr) = _squareForPos(_mySlot, pos);
        if (col == pc && row == pr) { _tapPiece(_mySlot, pi); return; }
      }
    }
  }

  bool _inNestArea(int slot, int col, int row) {
    final (nc,nr) = _kNestTL[slot];
    return col >= nc && col <= nc+1 && row >= nr && row <= nr+1;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────
class _LudoPainter extends CustomPainter {
  final List<List<int>>        pieces;
  final List<List<int>>        preAnim;
  final int                    animSlot;
  final int                    animPiece;
  final List<(int,int)>        animPath;
  final double                 animT;
  final List<int>              validPieces;
  final int                    mySlot;
  final List<int>              slots;
  final List<Player>           players;
  final Map<int,ui.Image>      avatarImages;
  final int                    currentSlot;
  final Color Function(int)    slotColor;

  const _LudoPainter({
    required this.pieces,
    required this.preAnim,
    required this.animSlot,
    required this.animPiece,
    required this.animPath,
    required this.animT,
    required this.validPieces,
    required this.mySlot,
    required this.slots,
    required this.players,
    required this.avatarImages,
    required this.currentSlot,
    required this.slotColor,
  });

  @override bool shouldRepaint(_LudoPainter o) =>
    pieces       != o.pieces       ||
    preAnim      != o.preAnim      ||
    animSlot     != o.animSlot     ||
    animPiece    != o.animPiece    ||
    animT        != o.animT        ||
    validPieces  != o.validPieces  ||
    currentSlot  != o.currentSlot  ||
    avatarImages != o.avatarImages;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 13;
    // Dark background matching kBg
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = kBg);
    _drawNests(canvas, cell);
    _drawTrackSquares(canvas, cell);
    _drawHomeSquares(canvas, cell);
    _drawPieces(canvas, cell);
  }

  // ── Nests ─────────────────────────────────────────────────────────────────
  void _drawNests(Canvas canvas, double cell) {
    const slotOffsets = [(0.5,0.5),(1.5,0.5),(0.5,1.5),(1.5,1.5)];
    for (int slot = 0; slot < 4; slot++) {
      final active  = slots.contains(slot);
      final isCurrent = slot == currentSlot;
      final col     = active ? slotColor(slot) : const Color(0xFF444455);
      final fillCol = active ? col.withValues(alpha: 0.15) : const Color(0xFF2A2A3A);
      final borderW = (active && isCurrent) ? 3.5 : 1.5;

      final (nc,nr) = _kNestTL[slot];
      final rect = Rect.fromLTWH(nc*cell, nr*cell, 2*cell, 2*cell);
      final rr   = RRect.fromRectAndRadius(rect, Radius.circular(cell*0.2));
      canvas.drawRRect(rr, Paint()..color = fillCol);
      // Glow for active current player
      if (active && isCurrent) {
        canvas.drawRRect(rr, Paint()
            ..color = col.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      }
      canvas.drawRRect(rr, Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderW);

      // 4 slot circles — only for active slots
      if (active) {
        for (final (ox,oy) in slotOffsets) {
          final cx = (nc+ox)*cell; final cy = (nr+oy)*cell;
          canvas.drawCircle(Offset(cx,cy), cell*0.32,
              Paint()..color = col.withValues(alpha: 0.18));
          canvas.drawCircle(Offset(cx,cy), cell*0.32,
              Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 1.0);
        }
      }
    }
  }

  // ── Outer track squares ───────────────────────────────────────────────────
  void _drawTrackSquares(Canvas canvas, double cell) {
    final r = cell * 0.36;
    for (int i = 0; i < 40; i++) {
      final (tc,tr) = _kTrack[i];
      final cx = (tc+.5)*cell; final cy = (tr+.5)*cell;

      // Find if this is an entry square for an active slot
      int entrySlot = -1;
      for (int s = 0; s < 4; s++) {
        if (_kEntry[s] == i && slots.contains(s)) { entrySlot = s; break; }
      }

      final fill   = entrySlot >= 0
          ? slotColor(entrySlot).withValues(alpha: 0.30)
          : Colors.white.withValues(alpha: 0.08);
      final border = entrySlot >= 0
          ? slotColor(entrySlot).withValues(alpha: 0.80)
          : Colors.white.withValues(alpha: 0.25);

      canvas.drawCircle(Offset(cx,cy), r, Paint()..color = fill);
      canvas.drawCircle(Offset(cx,cy), r,
          Paint()..color = border..style = PaintingStyle.stroke..strokeWidth = 1.2);
    }
  }

  // ── Home/finish squares ───────────────────────────────────────────────────
  void _drawHomeSquares(Canvas canvas, double cell) {
    final r = cell * 0.36;
    for (int slot = 0; slot < 4; slot++) {
      final active = slots.contains(slot);
      final col    = active ? slotColor(slot) : const Color(0xFF444455);
      for (final (hc,hr) in _kHome[slot]) {
        final cx = (hc+.5)*cell; final cy = (hr+.5)*cell;
        canvas.drawCircle(Offset(cx,cy), r,
            Paint()..color = col.withValues(alpha: active ? 0.35 : 0.12));
        canvas.drawCircle(Offset(cx,cy), r,
            Paint()..color = col.withValues(alpha: active ? 0.85 : 0.35)
                ..style = PaintingStyle.stroke..strokeWidth = 1.2);
      }
    }
  }

  // ── Pieces ────────────────────────────────────────────────────────────────
  void _drawPieces(Canvas canvas, double cell) {
    final animating = animSlot >= 0 ? {animSlot*10+animPiece} : <int>{};
    final disp = preAnim.isNotEmpty ? preAnim : pieces;

    final Map<(int,int), List<(int,int)>> grid = {};
    for (final slot in slots) {
      for (int pi = 0; pi < 4; pi++) {
        if (animating.contains(slot*10+pi)) continue;
        final pos = disp[slot][pi];
        final sq  = pos == _kPosNest
            ? _nestPieceCoord(slot, pi)
            : _squareForPos(slot, pos);
        (grid[sq] ??= []).add((slot,pi));
      }
    }
    for (final e in grid.entries) _drawStackAt(canvas, cell, e.key, e.value);

    if (animSlot >= 0 && animPath.isNotEmpty) {
      final t    = animT.clamp(0.0,1.0);
      final fIdx = t * (animPath.length-1);
      final lo   = fIdx.floor().clamp(0, animPath.length-2);
      final frac = fIdx - lo;
      final (c1,r1) = animPath[lo];
      final (c2,r2) = animPath[lo+1];
      final x = (c1+(c2-c1)*frac+.5)*cell;
      final y = (r1+(r2-r1)*frac+.5)*cell;
      final col = slotColor(animSlot);
      canvas.drawCircle(Offset(x,y), cell*0.42,
          Paint()..color = col.withValues(alpha: 0.40)
               ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      _drawOnePiece(canvas, cell, Offset(x,y), animSlot, animPiece);
    }
  }

  (int,int) _nestPieceCoord(int slot, int pi) {
    const offsets = [(0,0),(1,0),(0,1),(1,1)];
    final (nc,nr) = _kNestTL[slot];
    final (dc,dr) = offsets[pi];
    return (nc+dc, nr+dr);
  }

  void _drawStackAt(Canvas canvas, double cell, (int,int) sq,
      List<(int,int)> occ) {
    if (occ.isEmpty) return;
    final (c,r) = sq;
    final cx = (c+.5)*cell; final cy = (r+.5)*cell;
    if (occ.length == 1) {
      final (slot,pi) = occ.first;
      _drawOnePiece(canvas, cell, Offset(cx,cy), slot, pi);
    } else {
      final n = occ.length;
      for (int i = 0; i < n; i++) {
        final angle = (i/n)*2*pi - pi/2;
        final ox = cx + cos(angle)*cell*0.18;
        final oy = cy + sin(angle)*cell*0.18;
        final (slot,pi2) = occ[i];
        _drawOnePiece(canvas, cell, Offset(ox,oy), slot, pi2, small: true);
      }
    }
  }

  void _drawOnePiece(Canvas canvas, double cell, Offset center, int slot,
      int pieceIdx, {bool small = false}) {
    final isValid = validPieces.contains(pieceIdx) && slot == mySlot;
    final col = slotColor(slot);
    final r   = small ? cell*0.26 : cell*0.36;

    if (isValid) {
      // Glow in player's own colour
      canvas.drawCircle(center, r + 4,
          Paint()..color = col.withValues(alpha: 0.45)
               ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
    canvas.drawCircle(center, r, Paint()..color = col);
    canvas.drawCircle(center, r, Paint()
        ..color = Colors.white.withValues(alpha: isValid ? 0.95 : 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isValid ? 2.5 : 1.2);

    if (r >= cell*0.22) {
      final pi  = slots.contains(slot) ? slots.indexOf(slot) : -1;
      final img = pi >= 0 ? avatarImages[pi] : null;
      _drawFace(canvas, center, r*0.82, slot, pi, img);
    }
  }

  void _drawFace(Canvas canvas, Offset center, double r, int slot,
      int playerIdx, ui.Image? img) {
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));
    if (img != null) {
      final src = Rect.fromLTWH(0,0,img.width.toDouble(),img.height.toDouble());
      canvas.drawImageRect(img, src,
          Rect.fromCircle(center: center, radius: r), Paint());
    } else {
      final col = slotColor(slot);
      canvas.drawOval(Rect.fromCircle(center: center, radius: r),
          Paint()..color = col.withValues(alpha: 0.5));
      canvas.restore();
      final name = playerIdx >= 0 && playerIdx < players.length
          ? players[playerIdx].name : '?';
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
      final tp = TextPainter(
        text: TextSpan(text: initial, style: TextStyle(
          color: Colors.white, fontSize: r*1.1, fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx-tp.width/2, center.dy-tp.height/2));
      return;
    }
    canvas.restore();
  }
}
