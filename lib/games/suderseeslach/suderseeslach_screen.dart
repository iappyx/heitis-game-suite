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
import 'suderseeslach_ai.dart';
import '../../screens/solo_setup_screen.dart';
import '../../core/sound_player.dart';
import 'package:flutter/services.dart';

List<List<dynamic>> get _ships => [
  [5, L.suderseeslach.shipLemsteraak], [4, L.suderseeslach.shipGrutteTjalk], [3, L.suderseeslach.shipPream], [3, L.suderseeslach.shipSkutsje], [2, L.suderseeslach.shipFjouwerMaster],
];
const _G = 10; // grid size
enum _Phase { placing, waiting, battle, over }

class _Ship {
  final int len; final String name;
  int row = 0, col = 0; bool horiz = true; bool sunk = false;
  _Ship(this.len, this.name);
  List<List<int>> cells() => List.generate(len, (i) => horiz ? [row, col+i] : [row+i, col]);
  bool fitsGrid() => horiz ? col+len <= _G : row+len <= _G;
  bool overlaps(_Ship o) {
    final s = cells().map((c) => '${c[0]},${c[1]}').toSet();
    return o.cells().any((c) => s.contains('${c[0]},${c[1]}'));
  }
}

class SuderseeslachScreen extends StatefulWidget {
  final List<Player> players;
  final int firstPlayer;
  final Map<String, dynamic>? extra;
  const SuderseeslachScreen({super.key, required this.players, required this.firstPlayer, this.extra});
  @override State<SuderseeslachScreen> createState() => _SuderseeslachState();
}

class _SuderseeslachState extends State<SuderseeslachScreen> with GameMixin {
  final _net = Network();
  SuderseeslachAI? _ai;
  // AI's ships (for solo: we track what was "placed" so we can check hits)
  final _aiGrid = List.generate(10, (_) => List<String>.filled(10, ''));
  final _session = SessionState();
  _Phase _phase = _Phase.placing;
  late List<_Ship> _myShips;
  int _placingIdx = 0;
  bool _placingHoriz = true;
  bool _iReady = false, _theyReady = false;
  // my grid: ''=empty, 'S'=ship, 'H'=hit on ship, 'M'=miss
  final _my = List.generate(_G, (_) => List<String>.filled(_G, ''));
  // enemy grid: ''=unknown, 'H'=hit, 'M'=miss
  final _en = List.generate(_G, (_) => List<String>.filled(_G, ''));
  bool _myTurn = false; // host fires first
  int _winner = 0;

  @override List<Player> get gamePlayers => widget.players;
  @override void initState() {
    super.initState();
    _reset(); // also places AI ships if isSolo
    msgSub = _net.listen(_onMsg);
    _net.onDisconnected = () { if (mounted) _showReconnect(); };
  }

  void _reset({int? first}) {
    resetConfetti();
    resetStats();
    _myShips = _ships.map((s) => _Ship(s[0] as int, s[1] as String)).toList();
    _placingIdx = 0; _placingHoriz = true;
    _iReady = false; _theyReady = false;
    final f = first ?? widget.firstPlayer;
    _myTurn = (f == 1) ? (_net.myIdx == 0) : (_net.myIdx != 0);
    _winner = 0; _phase = _Phase.placing;
    for (var r in _my)    r.fillRange(0, _G, '');
    for (var r in _en)    r.fillRange(0, _G, '');
    for (var r in _aiGrid) r.fillRange(0, _G, '');
    if (_net.isSolo) {
      final d = SoloDifficulty.values[widget.extra?['difficulty'] as int? ?? 1];
      _ai = SuderseeslachAI(d);
      _soloPlaceAiShips();
    }
  }

  void _resetPlacement() {
    setState(() {
      _placingIdx = 0;
      _placingHoriz = true;
      for (var r in _my) r.fillRange(0, _G, '');
    });
  }

  void _placeTap(int r, int c) {
    SoundPlayer.i.suderseeslachPlace();
    HapticFeedback.lightImpact();
    if (_placingIdx >= _myShips.length) return;
    final ship = _myShips[_placingIdx]
      ..row = r ..col = c ..horiz = _placingHoriz;
    if (!ship.fitsGrid()) return;
    for (int i = 0; i < _placingIdx; i++) { if (ship.overlaps(_myShips[i])) return; }
    for (final cell in ship.cells()) _my[cell[0]][cell[1]] = 'S';
    setState(() { _placingIdx++; });
    if (_placingIdx >= _myShips.length) {
      _net.send('SSL_READY');
      setState(() { _iReady = true; _phase = _theyReady ? _Phase.battle : _Phase.waiting; });
      // In solo mode AI is already "ready" — go straight to battle
      if (_net.isSolo) {
        setState(() { _theyReady = true; _phase = _Phase.battle; });
        // If AI goes first, trigger its first shot
        if (!_myTurn) {
          _soloAiFire();
        }
      }
    }
  }

  void _fireTap(int r, int c) {
    SoundPlayer.i.suderseeslachMiss(); // overridden to hit/sunk by result
    HapticFeedback.mediumImpact();
    if (_phase != _Phase.battle || !_myTurn || _winner != 0) return;
    if (_en[r][c].isNotEmpty) return;
    setState(() { _myTurn = false; });
    _net.send('SSL_FIRE', {'r': r, 'c': c});
    // In solo mode, resolve the shot against AI grid immediately
    if (_net.isSolo) _soloResolveHumanShot(r, c);
  }

  // ── Solo helpers ─────────────────────────────────────────────────────────

  void _soloPlaceAiShips() {
    final shipLengths = _ships.map((s) => s[0] as int).toList();
    final placements = _ai!.placeShips(shipLengths);
    for (int i = 0; i < placements.length; i++) {
      final p = placements[i];
      final row = p[0] as int, col = p[1] as int, horiz = p[2] as bool;
      for (int j = 0; j < shipLengths[i]; j++) {
        if (horiz) _aiGrid[row][col + j] = 'S';
        else       _aiGrid[row + j][col] = 'S';
      }
    }
    // AI is immediately ready
    setState(() { _theyReady = true; });
  }

  void _soloResolveHumanShot(int r, int c) {
    final hit = _aiGrid[r][c] == 'S';
    if (hit) _aiGrid[r][c] = 'H';
    // Note: the AI only learns from its own shots — don't register the human's shot
    final allSunk = !_aiGrid.any((row) => row.any((cell) => cell == 'S'));
    if (hit) HapticFeedback.heavyImpact();
    setState(() {
      _en[r][c] = hit ? 'H' : 'M';
      if (allSunk) {
        _winner = 1; _phase = _Phase.over;
      } else if (hit) {
        _myTurn = true; // hit = shoot again
      } else {
        _myTurn = false;
        // AI takes its turn
        _soloAiFire();
      }
    });
  }

  void _soloAiFire() {
    if (_ai == null || _winner != 0) return;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || _winner != 0) return;
      final shot = _ai!.pickShot();
      int r = shot[0], c = shot[1];
      // Safety: never fire at an out-of-bounds or already-fired cell (would overwrite H/M)
      if (r < 0 || r >= _G || c < 0 || c >= _G || _my[r][c] == 'H' || _my[r][c] == 'M') {
        r = -1;
        for (int rr = 0; rr < _G && r < 0; rr++) {
          for (int cc = 0; cc < _G; cc++) {
            if (_my[rr][cc] != 'H' && _my[rr][cc] != 'M') { r = rr; c = cc; break; }
          }
        }
        if (r < 0) return; // nothing left to fire at
      }
      final hit = _my[r][c] == 'S';
      if (hit) _my[r][c] = 'H';
      else _my[r][c] = 'M';
      // Check ship sunk
      bool sunk = false;
      for (final ship in _myShips) {
        if (!ship.sunk && ship.cells().every((cl) => _my[cl[0]][cl[1]] == 'H')) {
          ship.sunk = true; sunk = true;
        }
      }
      final allSunk = _myShips.every((s) => s.sunk);
      _ai!.registerResult(r, c, hit, sunk);
      setState(() {
        if (allSunk) {
          _winner = 2; _phase = _Phase.over;
        } else if (hit) {
          // AI fires again on hit — schedule outside setState to avoid nested calls
        } else {
          _myTurn = true; // miss → human's turn
          turnChanged();
        }
      });
      if (!allSunk && hit) _soloAiFire();
    });
  }

  void _onMsg(Map<String, dynamic> msg, int fromIdx) {
    final type = msg['type'] as String;
    if (handleCommonMessages(msg, fromIdx)) return;
    switch (type) {

      case 'GAME_RESET':
        if (!_net.isHost) setState(() => _reset(first: msg['first'] as int?));
        break;
      case 'SSL_SYNC_REQ':
        if (_net.isHost) _sendSync();
        break;
      case 'SSL_SYNC':
        if (!_net.isHost) _applySync(msg);
        break;
      case 'SSL_READY':
        setState(() {
          _theyReady = true;
          if (_iReady) _phase = _Phase.battle;
          // if not yet ready ourselves, phase stays placing — when we finish placing,
          // _theyReady==true so we jump straight to battle
        });
        break;

      case 'SSL_FIRE': {
        // Opponent shot at our grid
        final r = msg['r'] as int, c = msg['c'] as int;
        if (r < 0 || r >= _G || c < 0 || c >= _G) break;
        final hit = _my[r][c] == 'S';
        setState(() { _my[r][c] = hit ? 'H' : 'M'; });
        // Check sunk
        String? sunk;
        for (final ship in _myShips) {
          if (!ship.sunk && ship.cells().every((cl) => _my[cl[0]][cl[1]] == 'H')) {
            ship.sunk = true; sunk = ship.name;
          }
        }
        final allSunk = _myShips.every((s) => s.sunk);
        _net.send('SSL_RESULT', {'r': r, 'c': c, 'hit': hit, 'sunk': sunk, 'allSunk': allSunk});
        setState(() {
          if (allSunk) {
            _winner = _net.myIdx == 0 ? 2 : 1;
            _phase = _Phase.over;
          } else if (hit) {
            _myTurn = false; // opponent hit → they fire again
          } else {
            _myTurn = true;  // opponent missed → now my turn
            turnChanged();
          }
        });
        break;
      }

      case 'SSL_RESULT': {
        // Result of my shot
        final r = msg['r'] as int, c = msg['c'] as int;
        final hit = msg['hit'] as bool;
        final allSunk = msg['allSunk'] as bool;
        if (hit) HapticFeedback.heavyImpact();
        setState(() {
          _en[r][c] = hit ? 'H' : 'M';
          if (allSunk) {
            _winner = _net.myIdx == 0 ? 1 : 2;
            _phase = _Phase.over;
          } else if (hit) {
            _myTurn = true; // hit = shoot again
          } else {
            _myTurn = false; // miss = opponent's turn
          }
        });
        break;
      }

    }
  }


  void _sendSync() {
    // Host sends both perspectives so the rejoining joiner gets the correct grids.
    // Ship positions are included so sunk detection keeps working after reconnect.
    _net.send('SSL_SYNC', {
      'phase':   _phase.index,
      'winner':  _winner,
      // myTurn is from host perspective; joiner perspective is the inverse
      'hostTurn': _myTurn ? 1 : 0,
      'iReady':  _iReady ? 1 : 0,
      'theyReady': _theyReady ? 1 : 0,
      // host_en = what host can see of joiner's grid (hits/misses the host fired)
      'host_en': _en.map((r) => r.toList()).toList(),
      // host_my = host's full grid including 'S' ship markers
      'host_my': _my.map((r) => r.toList()).toList(),
      // host_ships = host's ship layout so joiner can restore sunk state
      'host_ships': _myShips.map((s) => {
        'len': s.len, 'name': s.name,
        'row': s.row, 'col': s.col, 'horiz': s.horiz, 'sunk': s.sunk,
      }).toList(),
    });
  }

  void _applySync(Map<String, dynamic> msg) {
    setState(() {
      _phase    = _Phase.values[msg['phase'] as int];
      _winner   = msg['winner']    as int;
      _iReady   = (msg['iReady']   as int) == 1;
      _theyReady = (msg['theyReady'] as int) == 1;
      // Host's turn flag; joiner's turn is the opposite
      final hostTurn = (msg['hostTurn'] as int) == 1;
      _myTurn = _net.myIdx == 0 ? hostTurn : !hostTurn;

      // Restore host's full grid (including 'S' ship markers)
      final hostMyRaw = msg['host_my'] as List;
      final hostEnRaw = msg['host_en'] as List;

      // Restore host ships from payload (for sunk detection)
      final hostShipsRaw = msg['host_ships'] as List;

      if (_net.myIdx == 0) {
        // Host: restore own full grid and enemy view
        for (int r = 0; r < _G; r++) {
          final myRow = hostMyRaw[r] as List;
          final enRow = hostEnRaw[r] as List;
          for (int cc = 0; cc < _G; cc++) {
            _my[r][cc] = myRow[cc] as String;
            _en[r][cc] = enRow[cc] as String;
          }
        }
        // Restore host _myShips positions and sunk flags
        for (int i = 0; i < hostShipsRaw.length && i < _myShips.length; i++) {
          final s = hostShipsRaw[i] as Map<String, dynamic>;
          _myShips[i].row   = s['row']  as int;
          _myShips[i].col   = s['col']  as int;
          _myShips[i].horiz = s['horiz'] as bool;
          _myShips[i].sunk  = s['sunk']  as bool;
        }
      } else {
        // Joiner: host_my is what host fired at joiner → joiner's _my hit/miss overlay
        // Apply only H/M markers on top of joiner's existing 'S' cells
        for (int r = 0; r < _G; r++) {
          final row = hostEnRaw[r] as List;
          for (int cc = 0; cc < _G; cc++) {
            final v = row[cc] as String;
            if (v == 'H' || v == 'M') _my[r][cc] = v;
          }
        }
        // host_my is what joiner fired at host → joiner's _en
        // Strip 'S' markers — joiner must not see host's ship positions
        for (int r = 0; r < _G; r++) {
          final row = hostMyRaw[r] as List;
          for (int cc = 0; cc < _G; cc++) {
            final v = row[cc] as String;
            _en[r][cc] = (v == 'S') ? '' : v;
          }
        }
        // Recompute sunk state from the updated _my grid (which now has H markers)
        for (final ship in _myShips) {
          ship.sunk = ship.cells().every((cl) => _my[cl[0]][cl[1]] == 'H');
        }
      }
    });
  }

  void _showReconnect() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => ReconnectDialog(
        onReconnected: () {
          msgSub?.cancel();
          msgSub = _net.listen(_onMsg);
          _net.onDisconnected = () { if (mounted) _showReconnect(); };
          if (_net.isHost) _sendSync();
          else _net.send('SSL_SYNC_REQ');
        },
        onExit: () => Navigator.pushAndRemoveUntil(context,
          fadeScaleRoute(const LobbyScreen()), (_) => false)));
  }

  @override Widget build(BuildContext ctx) => GameScaffold(
        key: scaffoldKey,
    title: L.suderseeslach.gameName,
    players: widget.players, chatMessages: chatMessages, onSendChat: sendChat,
          typingName:    typingName,
          onLocalTyping: onLocalTyping,
          onReadAck:     sendReadAck,
      rules: L.suderseeslach.rules,
    child: Column(children: [
      PlayerBar(
        players: widget.players,
        activeIdx: _phase == _Phase.battle ? (_myTurn ? _net.myIdx.clamp(0,1) : 1 - _net.myIdx.clamp(0,1)) : -1,
      ),
      _buildStatusBar(),
      Expanded(child: _phase == _Phase.placing ? _placingView() : _battleView()),
      if (_phase == _Phase.over) ...[
        GameResultBanner(
          players: widget.players,
          winnerIdx: _winner - 1,
            onFirstRender: () { fireConfettiOnce(_winner - 1); recordResult('suderseeslach', _winner - 1); },
        ),
        GameOverActions(players: widget.players, sendReset: false, onReset: () {
          final first = _session.nextStarterFor(2);
          _session.advanceGame();
          _net.send('GAME_RESET', {'first': first});
          setState(() => _reset(first: first));
        }),
      ],
    ]),
  );

  Widget _buildStatusBar() {
    final s = _placingIdx < _myShips.length ? _myShips[_placingIdx] : null;
    String label;
    Color? color;
    switch (_phase) {
      case _Phase.placing:
        label = s == null ? '' : L.suderseeslach.placingShip.fmt({'name': s!.name, 'len': s!.len}); break;
      case _Phase.waiting: label = L.suderseeslach.waitingOpponent; break;
      case _Phase.battle:
        label = _myTurn ? L.suderseeslach.yourTurnShoot : L.suderseeslach.opponentTurn;
        if (_myTurn) color = kGreen;
        break;
      case _Phase.over:
        label = L.suderseeslach.winsExcl.fmt({'player': _winner==1 ? widget.players[0].name : (widget.players.length > 1 ? widget.players[1].name : 'AI')}); break;
    }

    Widget? rotateAction;
    if (_phase == _Phase.placing && s != null) {
      rotateAction = GestureDetector(
        onTap: () => setState(() => _placingHoriz = !_placingHoriz),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: kPurple2.withValues(alpha: .5), borderRadius: BorderRadius.circular(8)),
          child: Text(_placingHoriz ? L.suderseeslach.horizontal : L.suderseeslach.vertical,
            style: const TextStyle(color: kText, fontSize: 12))));
    }

    return GameStatusBar(text: label, textColor: color, action: rotateAction);
  }

  Widget _placingView() {
    final p = widget.players[_net.myIdx.clamp(0, widget.players.length-1)];
    return Column(children: [
      Expanded(child: Center(child: Padding(
        padding: const EdgeInsets.all(8),
        child: AspectRatio(aspectRatio: 1, child: _grid(_my, _placeTap, true, p.color))))),
      Padding(
        padding: const EdgeInsets.fromLTRB(10,0,10,8),
        child: Row(children: [
          Expanded(child: Wrap(spacing: 6, runSpacing: 4,
            children: _myShips.asMap().entries.map((e) {
              final done = e.key < _placingIdx, active = e.key == _placingIdx;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: done ? kGreen.withValues(alpha: .2) : active ? kPurple.withValues(alpha: .3) : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: active ? kPurple : Colors.transparent)),
                child: Text('${e.value.name}(${e.value.len})',
                  style: TextStyle(color: done ? kGreen : active ? kText : kMuted, fontSize: 11,
                    decoration: done ? TextDecoration.lineThrough : null)));
            }).toList())),
          if (_placingIdx > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: OutlinedButton(
                onPressed: _resetPlacement,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kMuted,
                  side: const BorderSide(color: kBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(L.suderseeslach.resetBoard, style: const TextStyle(fontSize: 11)),
              ),
            ),
        ])),
    ]);
  }

  Widget _battleView() {
    final myIdx = _net.myIdx.clamp(0, widget.players.length - 1);
    final me = widget.players[myIdx];
    final ene = widget.players[myIdx == 0 ? 1 : 0];
    return Row(children: [
      Expanded(child: Column(children: [
        Text(L.suderseeslach.yourWaters, style: TextStyle(color: me.color, fontSize: 11, fontWeight: FontWeight.bold)),
        Expanded(child: Padding(padding: const EdgeInsets.all(6),
          child: AspectRatio(aspectRatio: 1, child: _grid(_my, (_,__){}, true, me.color)))),
      ])),
      Container(width: 1, color: kBorder),
      Expanded(child: Column(children: [
        Text(L.suderseeslach.enemyWaters, style: TextStyle(color: ene.color, fontSize: 11, fontWeight: FontWeight.bold)),
        Expanded(child: Padding(padding: const EdgeInsets.all(6),
          child: AspectRatio(aspectRatio: 1,
            child: _grid(_en, _phase==_Phase.battle&&_myTurn&&_winner==0 ? _fireTap : (_,__){},
              false, ene.color)))),
        // game over actions shown in main build Column
      ])),
    ]);
  }

  Widget _grid(List<List<String>> grid, void Function(int,int) onTap,
      bool showShips, Color col) {
    return Column(children: [
      Row(children: [
        const SizedBox(width: 14),
        ...List.generate(_G, (i) => Expanded(child: Center(child: Text(
          String.fromCharCode(65+i),
          style: const TextStyle(color: kMuted, fontSize: 7))))),
      ]),
      Expanded(child: Row(children: [
        Column(children: List.generate(_G, (i) => Expanded(child: Center(child: Text(
          '${i+1}', style: const TextStyle(color: kMuted, fontSize: 7)))))),
        Expanded(child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _G, mainAxisSpacing: 1, crossAxisSpacing: 1),
          itemCount: _G * _G,
          itemBuilder: (_, idx) {
            final r = idx ~/ _G, c = idx % _G;
            final v = grid[r][c];
            Color bg = const Color(0xFF0D3B6E);
            if (showShips && v == 'S') bg = col.withValues(alpha: .55);
            if (v == 'H') bg = Colors.red.shade900;
            if (v == 'M') bg = const Color(0xFF071E3D);
            Widget? marker;
            if (v == 'H') marker = const Center(child: Text('✕',
              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)));
            if (v == 'M') marker = Center(child: Container(
              width: 7, height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .8),
                boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: .4), blurRadius: 3)])));
            return GestureDetector(
              onTap: () => onTap(r, c),
              child: Container(color: bg, child: marker));
          }),
        ),
      ])),
    ]);
  }
}
