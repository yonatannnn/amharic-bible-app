import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../supabase.dart';
import '../theme.dart';
import '../services/friends.dart';
import '../widgets/friend_avatar.dart';
import '../providers.dart';
import 'chat_thread.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});
  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  List<FriendInfo>? _friends;
  final _last = <String, Map<String, dynamic>>{};
  final _unread = <String, int>{};
  RealtimeChannel? _channel;
  String get _uid => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = supabase
        .channel('chats-list')
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'messages',
            callback: (_) => _load())
        // streak counts live-update too (shares, breaks, restores)
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'streaks',
            callback: (_) {
              ref.invalidate(friendsProvider);
              _load();
            })
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    final friends = await ref.read(friendsProvider.future);
    _last.clear();
    _unread.clear();
    if (friends.isNotEmpty) {
      final fids = friends.map((f) => f.friendshipId).toList();
      final msgs = await supabase
          .from('messages')
          .select('friendship_id, type, text, sender_id, created_at, read_at')
          .inFilter('friendship_id', fids)
          .order('created_at', ascending: false)
          .limit(400);
      for (final m in (msgs as List)) {
        final fid = m['friendship_id'] as String;
        _last.putIfAbsent(fid, () => m as Map<String, dynamic>);
        if (m['sender_id'] != _uid && m['read_at'] == null) {
          _unread[fid] = (_unread[fid] ?? 0) + 1;
        }
      }
      friends.sort((a, b) {
        final ta = _last[a.friendshipId]?['created_at'] as String? ?? '';
        final tb = _last[b.friendshipId]?['created_at'] as String? ?? '';
        return tb.compareTo(ta);
      });
    }
    if (mounted) setState(() => _friends = friends);
  }

  String _preview(Map<String, dynamic>? m) {
    if (m == null) return 'Share a verse to start your streak';
    final mine = m['sender_id'] == _uid ? 'You: ' : '';
    if (m['type'] == 'verse') return '$mine📖 Shared a verse';
    if (m['type'] == 'image') return '$mine🖼 Photo';
    return '$mine${m['text'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    // Reload conversations whenever the shared friends list changes.
    ref.listen(friendsProvider, (prev, next) {
      if (next.hasValue) _load();
    });
    if (_friends == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_friends!.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('✦', style: display(context, size: 48, color: c.gold.withValues(alpha: 0.5))),
            const SizedBox(height: 12),
            Text('ገና ጓደኛ የለዎትም', style: amharic(context, size: 18, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Add a friend to start chatting.', style: TextStyle(color: c.inkSoft)),
          ]),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(friendsProvider);
            await _load();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text('• መልእክቶች · MESSAGES', style: TextStyle(color: c.gold, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const SizedBox(height: 6),
              Text('Chats', style: display(context, size: 28, weight: FontWeight.w700)),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(20)),
                child: Column(children: [
                  for (var i = 0; i < _friends!.length; i++) _row(c, _friends![i], i > 0),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(AppColors c, FriendInfo f, bool border) {
    final lm = _last[f.friendshipId];
    final un = _unread[f.friendshipId] ?? 0;
    final time = lm != null ? DateFormat('h:mm a').format(DateTime.parse(lm['created_at'] as String).toLocal()) : '';
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatThreadScreen(friendshipId: f.friendshipId, friend: f))).then((_) => _load()),
      child: Container(
        decoration: BoxDecoration(border: border ? Border(top: BorderSide(color: c.line)) : null),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          FriendAvatar(friend: f, radius: 25),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(f.display, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              Text(time, style: TextStyle(color: c.inkFaint, fontSize: 11)),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              Expanded(child: Text(_preview(lm),
                  style: TextStyle(color: un > 0 ? c.ink : c.inkFaint, fontWeight: un > 0 ? FontWeight.w600 : null, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              Text('🔥 ${f.streakCount}', style: TextStyle(color: c.inkSoft, fontSize: 12)),
              if (un > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  child: Text('$un', textAlign: TextAlign.center, style: TextStyle(color: c.brandInk, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }
}
