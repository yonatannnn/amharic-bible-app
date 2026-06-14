import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class BookRef {
  final int num;
  final String name;
  BookRef(this.num, this.name);
}

class Chapter {
  final String chapter;
  final String title;
  final List<String> verses;
  Chapter(this.chapter, this.title, this.verses);
}

class Book {
  final String title;
  final List<Chapter> chapters;
  Book(this.title, this.chapters);
}

class BibleService {
  BibleService._();
  static final BibleService instance = BibleService._();

  final Map<int, Book> _cache = {};
  List<BookRef>? _books;

  Future<dynamic> _get(String path) async {
    Object? lastErr;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final res = await http
            .get(Uri.parse('${Config.bibleApi}$path'))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) {
          throw Exception('Bible API ${res.statusCode}');
        }
        return jsonDecode(utf8.decode(res.bodyBytes));
      } catch (e) {
        lastErr = e;
        if (attempt < 4) {
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
    }
    throw lastErr ?? Exception('Bible API failed for $path');
  }

  Future<List<BookRef>> getBooks() async {
    if (_books != null) return _books!;
    final arr = (await _get('/book') as List).cast<String>();
    final reg = RegExp(r'^(\d+)\s*:\s*(.+)$');
    final list = <BookRef>[];
    for (final s in arr.skip(1)) {
      final m = reg.firstMatch(s);
      if (m != null) {
        list.add(BookRef(int.parse(m.group(1)!), m.group(2)!.trim()));
      }
    }
    list.sort((a, b) => a.num - b.num);
    _books = list;
    return list;
  }

  Future<Book> getBook(int num) async {
    if (_cache.containsKey(num)) return _cache[num]!;
    final j = await _get('/book/$num') as Map<String, dynamic>;
    final chapters = (j['chapters'] as List)
        .map((c) => Chapter(
              (c['chapter'] ?? '').toString(),
              (c['title'] ?? '').toString(),
              (c['verses'] as List).map((v) => v.toString()).toList(),
            ))
        .toList();
    final book = Book((j['title'] ?? '').toString(), chapters);
    _cache[num] = book;
    return book;
  }

  String? bookNameSync(int num) {
    return _books?.where((b) => b.num == num).firstOrNull?.name;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
