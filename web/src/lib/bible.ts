/**
 * Client for the deployed Amharic Bible content API.
 *
 * The API has no CORS headers, so browser calls in the web app go through the
 * Next.js rewrite at /bible-api/* (see next.config.ts) which proxies to Koyeb.
 * Server-side calls can hit the API directly.
 */

const DIRECT =
  process.env.NEXT_PUBLIC_BIBLE_API ??
  "https://faithful-marni-anatoli-b7663357.koyeb.app";

// In the browser we use the same-origin proxy to dodge CORS; on the server, direct.
const BASE =
  typeof window === "undefined" ? DIRECT : "/bible-api";

export type BookRef = { num: number; name: string };

export type Verse = string;

export type Chapter = {
  chapter: string;
  title: string;
  verses: Verse[];
};

export type Book = {
  title: string;
  abbv: string;
  chapters: Chapter[];
};

async function get<T>(path: string): Promise<T> {
  const isServer = typeof window === "undefined";
  let lastErr: unknown;
  // Retry with a short per-attempt timeout — the upstream host occasionally
  // stalls on IPv6/Cloudflare, so fail fast and try again rather than hang.
  const MAX = 5;
  for (let attempt = 0; attempt < MAX; attempt++) {
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 7000);
      const res = await fetch(`${BASE}${path}`, {
        signal: ctrl.signal,
        // Server caches immutable content; client relies on the in-memory Map
        // and skips the HTTP cache so a once-bad/partial response can't stick.
        ...(isServer
          ? { next: { revalidate: 60 * 60 * 24 } }
          : { cache: "no-store" as RequestCache }),
      });
      clearTimeout(timer);
      if (!res.ok) throw new Error(`Bible API ${res.status} for ${path}`);
      return (await res.json()) as T;
    } catch (e) {
      lastErr = e;
      if (attempt < MAX - 1)
        await new Promise((r) => setTimeout(r, 300 * (attempt + 1)));
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error(`Bible API failed for ${path}`);
}

/** All 66 books as { num, name }, parsed from the API's dictionary array. */
export async function getBooks(): Promise<BookRef[]> {
  const arr = await get<string[]>("/book");
  return arr
    .slice(1) // index 0 is a header string
    .map((s) => {
      const m = s.match(/^(\d+)\s*:\s*(.+)$/);
      return m ? { num: parseInt(m[1], 10), name: m[2].trim() } : null;
    })
    .filter((b): b is BookRef => b !== null)
    .sort((a, b) => a.num - b.num);
}

/** A whole book (all chapters + verses). */
export async function getBook(num: number): Promise<Book> {
  return get<Book>(`/book/${num}`);
}

/** A single chapter. */
export async function getChapter(book: number, chapter: number): Promise<Chapter> {
  return get<Chapter>(`/book/${book}/chapter/${chapter}`);
}

/** Static metadata: book name lookups without a network call after first load. */
export function formatRef(
  bookName: string,
  chapter: number,
  verseStart: number,
  verseEnd?: number,
): string {
  const range =
    verseEnd && verseEnd !== verseStart
      ? `${verseStart}-${verseEnd}`
      : `${verseStart}`;
  return `${bookName} ${chapter}:${range}`;
}
