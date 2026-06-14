import '../supabase.dart';
import 'bible.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// "Today" in Ethiopia time (UTC+3) — matches the web + cron.
String addisDay() {
  final n = DateTime.now().toUtc().add(const Duration(hours: 3));
  return '${n.year}-${_two(n.month)}-${_two(n.day)}';
}

const _fallbackVerses = [
  {'book': 43, 'chapter': 3, 'verse': 16},
  {'book': 19, 'chapter': 23, 'verse': 1},
  {'book': 50, 'chapter': 4, 'verse': 13},
  {'book': 24, 'chapter': 29, 'verse': 11},
  {'book': 20, 'chapter': 3, 'verse': 5},
  {'book': 45, 'chapter': 8, 'verse': 28},
  {'book': 40, 'chapter': 11, 'verse': 28},
  {'book': 19, 'chapter': 46, 'verse': 1},
];

const _fallbackChapters = [
  {'book': 43, 'chapter': 1},
  {'book': 40, 'chapter': 5},
  {'book': 45, 'chapter': 8},
  {'book': 50, 'chapter': 2},
  {'book': 19, 'chapter': 23},
  {'book': 42, 'chapter': 15},
];

class DailyVerse {
  final int book, chapter, verse;
  final String label, text;
  DailyVerse(this.book, this.chapter, this.verse, this.label, this.text);
}

class TodaysReading {
  final int book, chapter;
  final String bookName;
  final List<String> verses;
  final bool alreadyReadToday;
  final int readingStreak;
  final String date;
  TodaysReading({
    required this.book,
    required this.chapter,
    required this.bookName,
    required this.verses,
    required this.alreadyReadToday,
    required this.readingStreak,
    required this.date,
  });
}

class DailyService {
  DailyService._();
  static final instance = DailyService._();
  final _bible = BibleService.instance;

  Future<DailyVerse?> getDailyVerse() async {
    final day = addisDay();
    List refs;
    try {
      final row = await supabase
          .from('daily_verse_pool')
          .select('refs')
          .eq('date', day)
          .maybeSingle();
      refs = (row?['refs'] as List?) ?? _fallbackVerses;
    } catch (_) {
      refs = _fallbackVerses;
    }
    if (refs.isEmpty) refs = _fallbackVerses;
    final windowIndex =
        DateTime.now().millisecondsSinceEpoch ~/ (12 * 3600 * 1000);

    // An admin may have overridden this window's verse.
    try {
      final ov = await supabase
          .from('daily_verse_override')
          .select('book, chapter, verse, window_index')
          .maybeSingle();
      if (ov != null && ov['window_index'] == windowIndex) {
        final v = await _resolveVerse(ov['book'] as int, ov['chapter'] as int, ov['verse'] as int);
        if (v != null) return v;
      }
    } catch (_) {}

    for (var offset = 0; offset < refs.length; offset++) {
      final pick = refs[(windowIndex + offset) % refs.length] as Map;
      final v = await _resolveVerse(pick['book'] as int, pick['chapter'] as int, pick['verse'] as int);
      if (v != null) return v;
    }
    return null;
  }

  Future<DailyVerse?> _resolveVerse(int book, int chapter, int verse) async {
    try {
      final b = await _bible.getBook(book);
      if (chapter < 1 || chapter > b.chapters.length) return null;
      final ch = b.chapters[chapter - 1];
      if (ch.verses.isEmpty) return null;
      final idx = (verse > ch.verses.length ? ch.verses.length : verse) - 1;
      final text = ch.verses[idx];
      final label = '${b.title.isNotEmpty ? b.title : 'Book $book'} $chapter:$verse';
      return DailyVerse(book, chapter, verse, label, text);
    } catch (_) {
      return null;
    }
  }

  /// Admin: override the current window's verse immediately.
  Future<bool> setDailyVerseOverride(int book, int chapter, int verse) async {
    final uid = supabase.auth.currentUser?.id;
    final windowIndex = DateTime.now().millisecondsSinceEpoch ~/ (12 * 3600 * 1000);
    try {
      await supabase.from('daily_verse_override').upsert({
        'id': 1,
        'book': book,
        'chapter': chapter,
        'verse': verse,
        'window_index': windowIndex,
        'set_by': uid,
        'set_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Admin: the Telegram queue, ordered top-first (top is sent at 6 AM EAT).
  Future<List<Map<String, dynamic>>> listTelegramQueue() async {
    try {
      final rows = await supabase
          .from('telegram_queue')
          .select('id, book, chapter, verse, source')
          .order('position', ascending: true);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Admin: append a manually-picked verse to the queue.
  Future<bool> addToTelegramQueue(int book, int chapter, int verse) async {
    final uid = supabase.auth.currentUser?.id;
    try {
      await supabase.from('telegram_queue').insert({
        'book': book,
        'chapter': chapter,
        'verse': verse,
        'source': 'manual',
        'set_by': uid,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeFromTelegramQueue(int id) async {
    try {
      await supabase.from('telegram_queue').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Persist a new order: positions become 0..n-1 in the given id order.
  Future<bool> reorderTelegramQueue(List<int> orderedIds) async {
    try {
      for (var i = 0; i < orderedIds.length; i++) {
        await supabase.from('telegram_queue').update({'position': i}).eq('id', orderedIds[i]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Admin: ask the server to generate `count` AI verses into the queue.
  Future<int> generateAiVerses(int count) async {
    try {
      final res = await supabase.functions.invoke('generate-verses', body: {'count': count});
      return (res.data?['added'] as List?)?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Admin: broadcast a verse to Telegram now; removes queue row [id] if given.
  /// Returns the number of subscribers it reached, or null on failure.
  Future<int?> sendVerseNow({int? id, required int book, required int chapter, required int verse}) async {
    try {
      final res = await supabase.functions.invoke('telegram-verse', body: {
        if (id != null) 'id': id,
        'book': book,
        'chapter': chapter,
        'verse': verse,
      });
      return (res.data?['sent'] as int?) ?? 0;
    } catch (_) {
      return null;
    }
  }

  Future<TodaysReading?> getTodaysReading() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    final day = addisDay();

    int book, chapter;
    try {
      final row = await supabase
          .from('daily_chapter')
          .select('book, chapter')
          .eq('date', day)
          .maybeSingle();
      if (row != null) {
        book = row['book'] as int;
        chapter = row['chapter'] as int;
      } else {
        final f = _fallbackChapters[day.hashCode.abs() % _fallbackChapters.length];
        book = f['book']!;
        chapter = f['chapter']!;
      }
    } catch (_) {
      final f = _fallbackChapters[day.hashCode.abs() % _fallbackChapters.length];
      book = f['book']!;
      chapter = f['chapter']!;
    }

    final results = await Future.wait([
      supabase
          .from('reading_progress')
          .select('book')
          .eq('user_id', uid)
          .eq('date', day)
          .maybeSingle(),
      supabase
          .from('reading_progress')
          .select('date')
          .eq('user_id', uid)
          .order('date', ascending: false)
          .limit(400),
    ]);
    final todayRow = results[0];
    final recent = (results[1] as List).map((r) => r['date'] as String).toSet();

    final b = await _bible.getBook(book);
    if (b.chapters.isEmpty) return null;
    // Guard against a bad chapter index (e.g. a generated value out of range).
    final chapterIdx = (chapter - 1).clamp(0, b.chapters.length - 1);
    chapter = chapterIdx + 1;
    final verses = b.chapters[chapterIdx].verses;

    return TodaysReading(
      book: book,
      chapter: chapter,
      bookName: b.title.isNotEmpty ? b.title : 'Book $book',
      verses: verses,
      alreadyReadToday: todayRow != null,
      readingStreak: _streak(recent, day),
      date: day,
    );
  }

  int _streak(Set<String> dates, String todayKey) {
    DateTime cur = DateTime.parse('${todayKey}T12:00:00Z');
    String fmt(DateTime d) =>
        '${d.year}-${_two(d.month)}-${_two(d.day)}';
    if (!dates.contains(fmt(cur))) {
      cur = cur.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (dates.contains(fmt(cur))) {
      streak++;
      cur = cur.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<void> markRead(int book, int chapter, String date) async {
    final uid = supabase.auth.currentUser!.id;
    await supabase.from('reading_progress').upsert({
      'user_id': uid,
      'date': date,
      'book': book,
      'chapter': chapter,
      'completed_at': DateTime.now().toIso8601String(),
    });
  }
}
