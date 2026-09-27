import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';

// A short random prefix generated once per app run — makes msgIds unique across devices.
final String _kDevicePrefix = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');

class ChatMessage {
  final String sender, text;
  final Color color;
  final bool mine;
  final String? avatarPath;
  final Uint8List? avatarBytes;
  final String msgId;       // unique ID for read-receipt ACK
  bool read;                // true once remote has ACKed this outgoing message

  ChatMessage({
    required this.sender,
    required this.text,
    required this.color,
    required this.mine,
    this.avatarPath,
    this.avatarBytes,
    String? msgId,
    this.read = false,
  }) : msgId = msgId ?? '${_kDevicePrefix}_${DateTime.now().microsecondsSinceEpoch}';
}

// ── Small round avatar ────────────────────────────────────────────────────────
class AvatarBubble extends StatelessWidget {
  final Color color;
  final String? avatarPath;
  final Uint8List? avatarBytes;
  final double size;
  const AvatarBubble({super.key, required this.color,
    this.avatarPath, this.avatarBytes, this.size = 28});

  @override Widget build(BuildContext ctx) {
    ImageProvider? img;
    if (avatarBytes != null) {
      img = MemoryImage(avatarBytes!);
    } else if (avatarPath != null) {
      final f = File(avatarPath!);
      if (f.existsSync()) img = FileImage(f);
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .4),
        border: Border.all(color: color.withValues(alpha: .7), width: 1.5),
        image: img != null ? DecorationImage(image: img, fit: BoxFit.cover) : null,
      ),
    );
  }
}

// ── Animated typing dots ──────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override State<_TypingDots> createState() => _TypingDotsState();
}
class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 900))
      ..repeat();
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Opacity(
              opacity: _dotOpacity(t, i),
              child: Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: kMuted, shape: BoxShape.circle)),
            ),
          ],
        ]);
      },
    );
  }

  double _dotOpacity(double t, int i) {
    final phase = (t - i * 0.25).clamp(0.0, 1.0);
    if (phase < 0.3) return 0.3 + (phase / 0.3) * 0.7;
    if (phase < 0.6) return 1.0;
    return 1.0 - ((phase - 0.6) / 0.4) * 0.7;
  }
}

// ── Main overlay widget ───────────────────────────────────────────────────────
class ChatOverlay extends StatefulWidget {
  final List<ChatMessage> messages;
  final void Function(String) onSend;
  final VoidCallback onClose;
  final String? myAvatarPath;
  final String? typingName;       // non-null = someone is typing
  final VoidCallback? onTyping;   // called when local user types
  final List<String> Function()? getPendingReadIds; // IDs to ACK on open

  const ChatOverlay({
    super.key,
    required this.messages,
    required this.onSend,
    required this.onClose,
    this.myAvatarPath,
    this.typingName,
    this.onTyping,
    this.getPendingReadIds,
  });

  @override State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();

  @override void initState() {
    super.initState();
    // ACK all pending unread messages as soon as panel opens
    _ctrl.addListener(_onTextChanged);
  }

  @override void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_ctrl.text.isNotEmpty) widget.onTyping?.call();
  }

  @override void didUpdateWidget(ChatOverlay old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length ||
        widget.typingName != old.typingName) {
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onSend(t);
    _ctrl.clear();
  }

  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: kBg2.withValues(alpha: .97),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kBorder),
      boxShadow: [const BoxShadow(color: Colors.black54, blurRadius: 16)],
    ),
    child: Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kPurple2.withValues(alpha: .3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(children: [
          Text(L.common.chatTitle, style: const TextStyle(
            color: kText, fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          GestureDetector(onTap: widget.onClose,
            child: const Icon(Icons.close, color: kMuted, size: 18)),
        ]),
      ),

      // Messages
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(8),
          itemCount: widget.messages.length + (widget.typingName != null ? 1 : 0),
          itemBuilder: (_, i) {
            // Last item = typing indicator bubble
            if (widget.typingName != null && i == widget.messages.length) {
              return _buildTypingBubble(widget.typingName!);
            }
            final m = widget.messages[i];
            return _buildMessageBubble(m);
          },
        ),
      ),

      // Quick-reaction emoji row
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: kBorder))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['👍', '😂', '🎉', '👏', '😢', '🔥'].map((emoji) =>
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onSend(emoji);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 20,
                  fontFamilyFallback: ['NotoColorEmoji'])),
              ),
            ),
          ).toList(),
        ),
      ),

      // Input
      Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLength: 80,
              style: const TextStyle(color: kText, fontSize: 13),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: L.common.chatHint,
                hintStyle: const TextStyle(color: kMuted, fontSize: 12),
                filled: true, fillColor: Colors.white10,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: kBorder)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: kPurple2, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.send, color: Colors.white, size: 16),
            ),
          ),
        ]),
      ),
    ]),
  );

  Widget _buildMessageBubble(ChatMessage m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: m.mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!m.mine) ...[
            AvatarBubble(color: m.color, avatarPath: m.avatarPath,
                avatarBytes: m.avatarBytes, size: 24),
            const SizedBox(width: 5),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: const BoxConstraints(maxWidth: 160),
            decoration: BoxDecoration(
              color: m.mine ? kPurple2.withValues(alpha: .4) : Colors.white.withValues(alpha: .08),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(m.mine ? 12 : 2),
                bottomRight: Radius.circular(m.mine ? 2 : 12),
              ),
              border: Border.all(color: m.color.withValues(alpha: .35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!m.mine) Text(m.sender,
                style: TextStyle(color: m.color, fontSize: 10,
                  fontWeight: FontWeight.bold)),
              Text(m.text, style: const TextStyle(color: kText, fontSize: 12)),
              if (m.mine) ...[
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: _ReadTick(read: m.read),
                ),
              ],
            ]),
          ),
          if (m.mine) ...[
            const SizedBox(width: 5),
            AvatarBubble(color: m.color, avatarPath: m.avatarPath,
                avatarBytes: m.avatarBytes, size: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingBubble(String name) {
    return Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: 29), // avatar placeholder width
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(2),
                bottomRight: Radius.circular(12),
              ),
              border: Border.all(color: kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L.common.isTyping.fmt({'player': name}),
                  style: const TextStyle(color: kMuted, fontSize: 10,
                    fontStyle: FontStyle.italic)),
                const SizedBox(height: 4),
                const _TypingDots(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Read tick widget (✓ sent, ✓✓ read) ───────────────────────────────────────
class _ReadTick extends StatelessWidget {
  final bool read;
  const _ReadTick({required this.read});

  @override Widget build(BuildContext context) {
    final color = read ? kPurple : kMuted;
    if (read) {
      // Double tick — two overlapping check icons
      return SizedBox(
        width: 20, height: 10,
        child: Stack(children: [
          Positioned(left: 0, child: Icon(Icons.check, size: 10, color: color)),
          Positioned(left: 6, child: Icon(Icons.check, size: 10, color: color)),
        ]),
      );
    } else {
      return Icon(Icons.check, size: 10, color: color);
    }
  }
}
