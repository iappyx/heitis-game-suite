import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/games_registry.dart';
import '../core/network.dart';
import '../core/sound_player.dart';
import '../core/theme.dart';
import '../core/wake_lock.dart';
import '../core/session.dart';
import '../l10n/app_localizations.dart';
import '../screens/lobby_screen.dart';
import '../screens/waiting_screen.dart';
import 'help_sheet.dart';
import '../screens/solo_setup_screen.dart';
import '../core/player.dart';
import 'chat_overlay.dart';
import '../core/debug.dart';
import '../screens/superuser_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Chat toast bubble
// ─────────────────────────────────────────────────────────────────────────────
class _ToastBubble {
  final ChatMessage msg;
  final String id;
  _ToastBubble(this.msg) : id = '${DateTime.now().microsecondsSinceEpoch}';
}

class ChatToastLayer extends StatefulWidget {
  final List<ChatMessage> incoming;
  const ChatToastLayer({super.key, required this.incoming});
  @override State<ChatToastLayer> createState() => _ChatToastLayerState();
}

class _ChatToastLayerState extends State<ChatToastLayer> {
  final _toasts = <_ToastBubble>[];
  int _lastLen = 0;

  @override void initState() {
    super.initState();
    // `incoming` is the persistent session chat history — only toast messages
    // that arrive after this layer was created.
    _lastLen = widget.incoming.length;
  }

  @override void didUpdateWidget(ChatToastLayer old) {
    super.didUpdateWidget(old);
    // History was cleared (CLEAR_CHAT) — resync so new messages toast again.
    if (widget.incoming.length < _lastLen) _lastLen = widget.incoming.length;
    if (widget.incoming.length > _lastLen) {
      for (int i = _lastLen; i < widget.incoming.length; i++) {
        final msg = widget.incoming[i];
        if (msg.mine) continue;
        final t = _ToastBubble(msg);
        setState(() => _toasts.add(t));
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _toasts.removeWhere((x) => x.id == t.id));
        });
      }
      _lastLen = widget.incoming.length;
    }
  }

  @override Widget build(BuildContext context) => Positioned(
    bottom: 72, left: 12, right: 200,
    child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _toasts.map((t) => _AnimatedToast(key: ValueKey(t.id), t: t)).toList()));
}

class _AnimatedToast extends StatefulWidget {
  final _ToastBubble t;
  const _AnimatedToast({super.key, required this.t});
  @override State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 3), () { if (mounted) _ctrl.reverse(); });
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final m = widget.t.msg;
    return FadeTransition(opacity: _fade,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 240),
          decoration: BoxDecoration(
            color: kBg2.withValues(alpha: .93), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: m.color.withValues(alpha: .5)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: m.color, shape: BoxShape.circle)),
            Flexible(child: Text('${m.sender}: ${m.text}',
              style: const TextStyle(color: kText, fontSize: 13),
              overflow: TextOverflow.ellipsis, maxLines: 2)),
          ]))));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GameScaffold
// ─────────────────────────────────────────────────────────────────────────────
class GameScaffold extends StatefulWidget {
  final List<Player> players;
  final Widget child;
  final List<ChatMessage> chatMessages;
  final void Function(String) onSendChat;
  final String? title;

  // New: typing + read-receipt callbacks
  final String? typingName;                     // who is currently typing (null = nobody)
  final VoidCallback? onLocalTyping;            // called when local user types in chat
  final void Function(List<String>)? onReadAck; // called with msgIds when chat is opened

  // Optional help/rules text for the ? button
  final String? rules;

  const GameScaffold({
    super.key,
    required this.players,
    required this.child,
    required this.chatMessages,
    required this.onSendChat,
    this.title,
    this.typingName,
    this.onLocalTyping,
    this.onReadAck,
    this.rules,
  });

  @override State<GameScaffold> createState() => GameScaffoldState();
}

class GameScaffoldState extends State<GameScaffold> {
  bool _showChat = false;
  int  _unread   = 0;
  int  _lastLen  = 0;
  final bool _isSolo = Network().isSolo;

  late final ConfettiController _confetti;

  @override void initState() {
    super.initState();
    _lastLen = widget.chatMessages.length;
    _confetti = ConfettiController(duration: const Duration(seconds: 3));
  }

  @override void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  /// Call from game screen at game-over: isDraw = true for smaller burst.
  void triggerConfetti({bool isDraw = false}) {
    _confetti.play();
    if (isDraw) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _confetti.stop();
      });
    }
  }

  @override void didUpdateWidget(GameScaffold old) {
    super.didUpdateWidget(old);
    final newLen = widget.chatMessages.length;
    if (newLen > _lastLen) {
      final newMsgs = widget.chatMessages.sublist(_lastLen);
      final incoming = newMsgs.where((m) => !m.mine).length;
      if (!_showChat && incoming > 0) setState(() => _unread += incoming);
      _lastLen = newLen;

      // If chat is already open, immediately ACK new incoming messages
      if (_showChat) _sendReadAck();
    }

    // If a message was just marked as read (from remote ACK), rebuild
    if (_showChat) setState(() {});
  }

  void _openChat() {
    HapticFeedback.lightImpact();
    setState(() { _showChat = true; _unread = 0; });
    _sendReadAck();
  }

  void _sendReadAck() {
    if (widget.onReadAck == null) return;
    final unread = widget.chatMessages
        .where((m) => !m.mine && !m.read && m.msgId.isNotEmpty)
        .toList();
    if (unread.isEmpty) return;
    final ids = unread.map((m) => m.msgId).toList();
    for (final m in unread) { m.read = true; }  // mark locally so we don't re-ACK
    widget.onReadAck!(ids);
  }

  void _exit() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kBg2,
      title: Text(L.common.leaveGame, style: const TextStyle(color: kText)),
      content: Text(L.common.leaveGameContent, style: const TextStyle(color: kMuted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text(L.common.stay, style: const TextStyle(color: kMuted))),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            SessionState().reset();
            await Network().leaveSession();
            await WakeLock.release();
            if (mounted) Navigator.pushAndRemoveUntil(context,
              fadeScaleRoute(const LobbyScreen()), (_) => false);
          },
          child: Text(L.common.backToStart, style: const TextStyle(color: kMuted))),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(context);
            final net = Network();
            final isSolo = net.isSolo;
            final human = widget.players[0];
            if (isSolo) {
              await net.reset();
              await WakeLock.release();
              if (mounted) Navigator.pushAndRemoveUntil(context,
                fadeScaleRoute(SoloSetupScreen(humanPlayer: human)),
                (_) => false);
            } else {
              await net.sendAndFlush('BACK_TO_SELECT');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(L.common.leaving),
                duration: const Duration(milliseconds: 300)));
              await Future.delayed(const Duration(milliseconds: 100));
              await WakeLock.release();
              if (mounted) Navigator.pushAndRemoveUntil(context,
                fadeScaleRoute(WaitingScreen(players: widget.players, isHost: net.isHost)),
                (_) => false);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: kPurple2),
          child: Text(L.common.pickNewGame, style: const TextStyle(color: Colors.white))),
      ],
    ));
  }

  @override Widget build(BuildContext context) {
    // Top action bar: exit | title | chat  (sits above the game content)
    final topBar = Container(
      color: kBg,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        _IconBtn(Icons.exit_to_app, onTap: _exit, tooltip: L.common.leaveGame),
        if (widget.title != null) Expanded(child: Center(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder)),
          child: _TitleWithIcon(title: widget.title!),
        ))) else const Spacer(),
        // Help / rules button
        if (widget.rules != null)
          _IconBtn(Icons.help_outline, tooltip: L.common.helpTitle, onTap: () {
            SoundPlayer.i.uiOpen();
            HelpSheet.show(
              context,
              gameName: widget.title ?? '',
              rules: widget.rules!,
            );
          }),
        // Mute button
        StatefulBuilder(builder: (ctx, setSt) => _IconBtn(
          SoundPlayer.i.muted ? Icons.volume_off : Icons.volume_up,
          tooltip: SoundPlayer.i.muted ? L.common.unmuteTooltip : L.common.muteTooltip,
          onTap: () async {
            await SoundPlayer.i.toggleMute();
            setSt(() {});
          },
        )),
        if (!_isSolo) Stack(children: [
          _IconBtn(Icons.chat_bubble_outline, tooltip: L.common.chatTooltip, onTap: () {
            if (_showChat) {
              setState(() => _showChat = false);
            } else {
              _openChat();
            }
          }),
          if (_unread > 0) Positioned(right: 0, top: 0,
            child: Container(width: 16, height: 16,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: Center(child: Text('$_unread',
                style: const TextStyle(color: Colors.white, fontSize: 10,
                  fontWeight: FontWeight.bold))))),
        ]),
      ]),
    );

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(child: Stack(children: [
        // Main layout: top bar + game content stacked vertically
        Column(children: [
          topBar,
          Expanded(child: widget.child),
        ]),

        // Confetti burst from top-center on win
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 24,
            gravity: 0.25,
            emissionFrequency: 0.05,
            colors: const [
              Color(0xFFE040FB), Color(0xFF7C4DFF), Color(0xFF40C4FF),
              Color(0xFF69F0AE), Color(0xFFFFD740), Color(0xFFFF6E40),
            ],
          ),
        ),

        // Toast bubbles from incoming chat
        if (!_isSolo) ChatToastLayer(incoming: widget.chatMessages),

        // Typing indicator (below top bar)
        if (!_isSolo && widget.typingName != null && !_showChat)
          Positioned(right: 8, top: 52,
            child: _TypingBadge(name: widget.typingName!)),

        // Chat overlay
        if (!_isSolo && _showChat) Builder(builder: (ctx) {
          final sw = MediaQuery.of(ctx).size.width;
          final chatW = (sw * 0.38).clamp(220.0, 300.0);
          return Positioned(
            right: 8, top: 52, bottom: 60, width: chatW,
            child: ChatOverlay(
              messages: widget.chatMessages,
              onSend: widget.onSendChat,
              onClose: () => setState(() => _showChat = false),
              typingName: widget.typingName,
              onTyping: widget.onLocalTyping,
            ));
        }),

        // Superuser floating button (only after 5-tap unlock in lobby)
        if (gSuperuserUnlocked)
          Positioned(
            left: 8, bottom: 8,
            child: GestureDetector(
              onTap: () => SuperuserScreen.show(context),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kPurple2.withValues(alpha: 0.6))),
                child: const Center(
                  child: Text('🛠', style: TextStyle(fontSize: 13,
                    fontFamilyFallback: ['NotoColorEmoji']))),
              ),
            ),
          ),
      ])),
    );
  }
}

// Small "X is typing…" badge shown below top bar when chat is closed
class _TypingBadge extends StatelessWidget {
  final String name;
  const _TypingBadge({required this.name});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: kBg2.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: kBorder)),
    child: Text(L.common.isTyping.fmt({'player': name}),
      style: const TextStyle(color: kMuted, fontSize: 10,
        fontStyle: FontStyle.italic)),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap; final String? tooltip;
  const _IconBtn(this.icon, {required this.onTap, this.tooltip});
  @override Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(width: 48, height: 48,
        decoration: BoxDecoration(color: Colors.black54,
          borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
        child: Icon(icon, color: kText, size: 20)));
    if (tooltip != null) {
      return Semantics(label: tooltip, child: Tooltip(message: tooltip!, child: btn));
    }
    return btn;
  }
}

/// Title row with an optional game icon.
/// Looks up the current game from [Network.currentGameInfo] and, if found,
/// shows the icon next to the title.
class _TitleWithIcon extends StatelessWidget {
  final String title;
  const _TitleWithIcon({required this.title});

  @override Widget build(BuildContext context) {
    final gameId = Network().currentGameInfo?['game'] as String?;
    String? gameIcon;
    if (gameId != null) {
      for (final g in kGames) {
        if (g.id == gameId) { gameIcon = g.icon; break; }
      }
    }

    final titleText = Text(title,
      style: const TextStyle(color: kText, fontSize: 13,
        fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis);

    if (gameIcon == null) return titleText;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(gameIcon, style: const TextStyle(fontSize: 18,
        fontFamilyFallback: ['NotoColorEmoji'])),
      const SizedBox(width: 6),
      Flexible(child: titleText),
    ]);
  }
}
