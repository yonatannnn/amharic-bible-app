import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../theme.dart';
import '../services/friends.dart';
import '../providers.dart';
import '../screens/verse_image.dart';

/// One selectable verse with a superscript number. Shared by Home + Reader so
/// the reading experience is identical everywhere.
class VerseTile extends StatelessWidget {
  final int n;
  final String text;
  final double size;
  final bool selected;
  final VoidCallback onTap;
  const VerseTile({
    super.key,
    required this.n,
    required this.text,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 2),
        padding: EdgeInsets.symmetric(vertical: 4, horizontal: selected ? 8 : 0),
        decoration: BoxDecoration(
          color: selected ? c.brand.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text.rich(
          TextSpan(children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.top,
              child: Padding(
                padding: const EdgeInsets.only(right: 5, top: 1),
                child: Text('$n',
                    style: TextStyle(
                      fontSize: size * 0.54,
                      color: selected ? c.brand : c.gold.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w800,
                    )),
              ),
            ),
            TextSpan(text: text),
          ]),
          style: amharic(context, size: size, height: 1.78),
        ),
      ),
    );
  }
}

/// Range-selection logic shared by Home + Reader.
/// Returns the new [start, end] (or [null, null] to clear).
List<int?> nextSelection(int? start, int? end, int n) {
  if (start == null) return [n, n];
  if (start == end) {
    if (n == start) return [null, null];
    return [n < start ? n : start, n > end! ? n : end];
  }
  return [n, n];
}

/// Floating action bar for a selected verse range.
/// Internal sharing (send to a friend) is the PRIMARY action; copy / external
/// share live behind the "more" button.
class VerseShareBar extends ConsumerStatefulWidget {
  final int book, chapter, start, end;
  final String ref, text;
  final VoidCallback onClear;
  const VerseShareBar({
    super.key,
    required this.book,
    required this.chapter,
    required this.start,
    required this.end,
    required this.ref,
    required this.text,
    required this.onClear,
  });

  @override
  ConsumerState<VerseShareBar> createState() => _VerseShareBarState();
}

class _VerseShareBarState extends ConsumerState<VerseShareBar> {
  bool _loading = false;

  /// The button label never changes (no flicker). Work happens on tap:
  /// load friends from the shared provider (cached → usually instant).
  Future<void> _onSend() async {
    setState(() => _loading = true);
    final friends = await ref.read(friendsProvider.future);
    if (!mounted) return;
    setState(() => _loading = false);
    if (friends.isEmpty) {
      _otherOptions();
    } else if (friends.length == 1) {
      _send(friends.first);
    } else {
      _pickFriend(friends);
    }
  }

  Future<void> _send(FriendInfo f) async {
    await FriendsService.instance
        .shareVerse(f.friendshipId, widget.book, widget.chapter, widget.start, widget.end);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Shared with ${f.display} 🔥'), behavior: SnackBarBehavior.floating),
    );
    widget.onClear();
  }

  void _pickFriend(List<FriendInfo> friends) {
    final c = colorsOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Text('Send to a friend', style: display(context, size: 16, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final f in friends)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: c.good,
                backgroundImage: f.avatarUrl != null ? NetworkImage(f.avatarUrl!) : null,
                child: f.avatarUrl == null ? Text(f.display[0].toUpperCase(), style: const TextStyle(color: Colors.white)) : null,
              ),
              title: Text(f.display),
              trailing: Text('🔥 ${f.streakCount}', style: TextStyle(color: c.inkSoft)),
              onTap: () {
                Navigator.pop(ctx);
                _send(f);
              },
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  void _otherOptions() {
    final c = colorsOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.ref, style: TextStyle(color: c.brand, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.image_outlined, color: c.ink),
            title: const Text('Make image'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => VerseImageScreen(ref: widget.ref, text: widget.text),
              ));
              widget.onClear();
            },
          ),
          ListTile(
            leading: Icon(Icons.copy, color: c.ink),
            title: const Text('Copy'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: '“${widget.text}”\n— ${widget.ref}'));
              Navigator.pop(ctx);
              widget.onClear();
            },
          ),
          ListTile(
            leading: Icon(Icons.ios_share, color: c.ink),
            title: const Text('Share externally'),
            onTap: () {
              SharePlus.instance.share(ShareParams(text: '“${widget.text}”\n— ${widget.ref}'));
              Navigator.pop(ctx);
              widget.onClear();
            },
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(widget.ref, style: TextStyle(color: c.brand, fontWeight: FontWeight.w700, fontSize: 13))),
          GestureDetector(
            onTap: widget.onClear,
            child: Icon(Icons.close, color: c.inkFaint, size: 20),
          ),
        ]),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(widget.text, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: amharic(context, size: 13, color: c.inkSoft)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _loading ? null : _onSend,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand, foregroundColor: c.brandInk,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _loading
                  ? SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: c.brandInk))
                  : const Text('🔥', style: TextStyle(fontSize: 15)),
              label: const Text('Send to a friend'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _otherOptions,
            style: IconButton.styleFrom(
              backgroundColor: c.surface2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(Icons.more_horiz, color: c.inkSoft),
          ),
        ]),
      ]),
    );
  }
}
