"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { getBooks, getBook, type Book, type BookRef } from "@/lib/bible";
import { ClickableAvatar } from "./ClickableAvatar";

export type ChatMessage = {
  id: string;
  friendship_id: string;
  sender_id: string;
  type: "verse" | "text" | "image";
  book: number | null;
  chapter: number | null;
  verse_start: number | null;
  verse_end: number | null;
  text: string | null;
  image_url: string | null;
  created_at: string;
  read_at: string | null;
};

const bookCache = new Map<number, Book>();
async function bookCached(n: number) {
  if (bookCache.has(n)) return bookCache.get(n)!;
  const b = await getBook(n);
  bookCache.set(n, b);
  return b;
}

export function ChatRoom({
  friendshipId,
  myId,
  friend,
  initialMessages,
  initialStreak,
}: {
  friendshipId: string;
  myId: string;
  friend: { id: string; name: string; username: string; avatar_url: string | null };
  initialMessages: ChatMessage[];
  initialStreak: number;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [messages, setMessages] = useState<ChatMessage[]>(initialMessages);
  const [streak, setStreak] = useState(initialStreak);
  const [text, setText] = useState("");
  const [picking, setPicking] = useState(false);
  const [books, setBooks] = useState<BookRef[]>([]);
  const seen = useRef(new Set(initialMessages.map((m) => m.id)));
  const bottomRef = useRef<HTMLDivElement>(null);

  const bookName = useCallback(
    (n: number | null) => (n ? books.find((b) => b.num === n)?.name ?? `Book ${n}` : ""),
    [books],
  );

  useEffect(() => {
    getBooks().then(setBooks).catch(() => {});
  }, []);

  // mark the friend's messages as read
  const markRead = useCallback(async () => {
    await supabase
      .from("messages")
      .update({ read_at: new Date().toISOString() })
      .eq("friendship_id", friendshipId)
      .eq("sender_id", friend.id)
      .is("read_at", null);
  }, [supabase, friendshipId, friend.id]);

  useEffect(() => {
    markRead();
  }, [markRead]);

  const refreshStreak = useCallback(async () => {
    const { data } = await supabase
      .from("streaks")
      .select("count")
      .eq("friendship_id", friendshipId)
      .maybeSingle();
    if (data) setStreak(data.count);
  }, [supabase, friendshipId]);

  // realtime: new messages
  useEffect(() => {
    const channel = supabase
      .channel(`chat:${friendshipId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "messages",
          filter: `friendship_id=eq.${friendshipId}`,
        },
        (payload) => {
          const m = payload.new as ChatMessage;
          if (seen.current.has(m.id)) return;
          seen.current.add(m.id);
          setMessages((prev) => [...prev, m]);
          if (m.type === "verse") refreshStreak();
          if (m.sender_id === friend.id) markRead();
        },
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "messages",
          filter: `friendship_id=eq.${friendshipId}`,
        },
        (payload) => {
          const m = payload.new as ChatMessage;
          setMessages((prev) =>
            prev.map((x) => (x.id === m.id ? { ...x, read_at: m.read_at } : x)),
          );
        },
      )
      // live streak count — covers shares, breaks at 11 AM, and restores
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "streaks",
          filter: `friendship_id=eq.${friendshipId}`,
        },
        () => refreshStreak(),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [supabase, friendshipId, refreshStreak, markRead, friend.id]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: "end" });
  }, [messages]);

  async function sendText() {
    const body = text.trim();
    if (!body) return;
    setText("");
    const { data } = await supabase
      .from("messages")
      .insert({ friendship_id: friendshipId, sender_id: myId, type: "text", text: body })
      .select()
      .single();
    if (data) {
      seen.current.add(data.id);
      setMessages((prev) => [...prev, data as ChatMessage]);
    }
  }

  async function sendVerse(book: number, chapter: number, start: number, end: number) {
    setPicking(false);
    const { data } = await supabase
      .from("messages")
      .insert({
        friendship_id: friendshipId,
        sender_id: myId,
        type: "verse",
        book,
        chapter,
        verse_start: start,
        verse_end: end,
      })
      .select()
      .single();
    if (data) {
      seen.current.add(data.id);
      setMessages((prev) => [...prev, data as ChatMessage]);
      refreshStreak();
    }
  }

  return (
    <div className="flex h-full flex-col">
      {/* header */}
      <header className="flex shrink-0 items-center gap-3 border-b border-line bg-surface/90 px-4 py-2.5 backdrop-blur-sm">
        <Link
          href="/chat"
          className="-ml-1 grid h-9 w-9 place-items-center rounded-full text-lg text-ink-soft hover:bg-surface-2 lg:hidden"
        >
          ←
        </Link>
        <ClickableAvatar name={friend.name} url={friend.avatar_url} size={42} />
        <Link href={`/friend/${friendshipId}`} className="min-w-0 flex-1">
          <div className="truncate font-semibold leading-tight hover:underline">
            {friend.name}
          </div>
          <div className="truncate text-xs text-ink-faint">@{friend.username}</div>
        </Link>
        <div className="flex items-center gap-1 rounded-full bg-gradient-to-br from-ember/20 to-brand/15 px-3 py-1.5 font-display text-sm font-bold text-ink">
          🔥 {streak}
        </div>
      </header>

      {/* messages */}
      <div
        className="flex-1 overflow-y-auto px-4 py-5"
        style={{
          backgroundColor: "var(--canvas)",
          backgroundImage:
            "radial-gradient(circle at 20% 10%, color-mix(in srgb, var(--gold) 8%, transparent), transparent 45%), radial-gradient(circle at 85% 90%, color-mix(in srgb, var(--brand) 7%, transparent), transparent 45%)",
        }}
      >
        {messages.length === 0 ? (
          <div className="grid h-full place-items-center text-center text-ink-faint">
            <div className="max-w-xs">
              <div className="font-display text-5xl text-gold/50">✦</div>
              <p className="amharic mt-3 font-semibold text-ink-soft">
                ጅምር · A new beginning
              </p>
              <p className="mt-1 text-sm">
                Share a verse to start your streak with {friend.name}.
              </p>
            </div>
          </div>
        ) : (
          <div className="mx-auto max-w-2xl">
            {messages.map((m, i) => {
              const prev = messages[i - 1];
              const showDay =
                !prev || !sameDay(prev.created_at, m.created_at);
              const mine = m.sender_id === myId;
              return (
                <div key={m.id}>
                  {showDay && <DaySeparator iso={m.created_at} />}
                  <Bubble m={m} mine={mine} bookName={bookName} />
                </div>
              );
            })}
            <div ref={bottomRef} />
          </div>
        )}
      </div>

      {/* composer */}
      <div className="shrink-0 border-t border-line bg-surface px-3 py-2.5">
        <div className="mx-auto flex max-w-2xl items-end gap-2">
          <button
            onClick={() => setPicking(true)}
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-brand-soft text-xl text-brand transition hover:brightness-95"
            title="Share a verse"
          >
            📖
          </button>
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && sendText()}
            placeholder="Message…"
            className="h-11 flex-1 rounded-full border border-line bg-surface-2 px-4 text-[15px] outline-none focus:border-brand"
          />
          <button
            onClick={sendText}
            disabled={!text.trim()}
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-brand text-lg text-brand-ink shadow-card transition hover:brightness-110 disabled:opacity-40"
          >
            ➤
          </button>
        </div>
      </div>

      {picking && (
        <VersePicker books={books} onClose={() => setPicking(false)} onSend={sendVerse} />
      )}
    </div>
  );
}

/* ---------------- date helpers ---------------- */
function sameDay(a: string, b: string) {
  return new Date(a).toDateString() === new Date(b).toDateString();
}
function DaySeparator({ iso }: { iso: string }) {
  const d = new Date(iso);
  const today = new Date();
  const yest = new Date();
  yest.setDate(today.getDate() - 1);
  let label = d.toLocaleDateString("en-US", { month: "long", day: "numeric" });
  if (d.toDateString() === today.toDateString()) label = "Today";
  else if (d.toDateString() === yest.toDateString()) label = "Yesterday";
  return (
    <div className="my-4 flex items-center justify-center">
      <span className="rounded-full bg-surface/80 px-3 py-1 text-[11px] font-medium text-ink-faint shadow-card">
        {label}
      </span>
    </div>
  );
}
function fmtTime(iso: string) {
  return new Date(iso).toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
  });
}

/* ---------------- message bubble ---------------- */
function Bubble({
  m,
  mine,
  bookName,
}: {
  m: ChatMessage;
  mine: boolean;
  bookName: (n: number | null) => string;
}) {
  let content: React.ReactNode;
  if (m.type === "verse") {
    content = <VerseBubble m={m} mine={mine} bookName={bookName} />;
  } else if (m.type === "image" && m.image_url) {
    content = (
      <a
        href={m.image_url}
        target="_blank"
        rel="noopener noreferrer"
        className="block max-w-[70%] overflow-hidden rounded-2xl border border-line shadow-card"
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={m.image_url} alt={m.text ?? "verse image"} className="w-full" />
      </a>
    );
  } else {
    content = (
      <div
        className={`max-w-[80%] rounded-2xl px-3.5 py-2 text-[15px] leading-snug shadow-card ${
          mine
            ? "rounded-br-md bg-brand text-brand-ink"
            : "rounded-bl-md border border-line bg-surface text-ink"
        }`}
      >
        {m.text}
      </div>
    );
  }

  return (
    <div className={`mb-1.5 flex flex-col ${mine ? "items-end" : "items-start"}`}>
      {content}
      <div className="mt-0.5 flex items-center gap-1 px-1 text-[10px] text-ink-faint">
        <span>{fmtTime(m.created_at)}</span>
        {mine && (
          <span className={m.read_at ? "text-good" : "text-ink-faint"}>
            {m.read_at ? "✓✓" : "✓"}
          </span>
        )}
      </div>
    </div>
  );
}

function VerseBubble({
  m,
  mine,
  bookName,
}: {
  m: ChatMessage;
  mine: boolean;
  bookName: (n: number | null) => string;
}) {
  const [verseText, setVerseText] = useState<string | null>(null);
  useEffect(() => {
    if (!m.book || !m.chapter) return;
    bookCached(m.book)
      .then((b) => {
        const ch = b.chapters[m.chapter! - 1];
        const s = (m.verse_start ?? 1) - 1;
        const e = (m.verse_end ?? m.verse_start ?? 1) - 1;
        setVerseText(ch.verses.slice(s, e + 1).join(" "));
      })
      .catch(() => setVerseText("…"));
  }, [m]);

  const range =
    m.verse_end && m.verse_end !== m.verse_start
      ? `${m.verse_start}-${m.verse_end}`
      : `${m.verse_start}`;

  return (
    <div
      className={`max-w-[80%] overflow-hidden rounded-2xl border ${
        mine ? "rounded-br-md border-brand/30" : "rounded-bl-md border-line"
      } bg-surface`}
    >
      <div className="bg-gradient-to-br from-brand/15 to-gold/5 px-4 pb-3 pt-3">
        <div className="text-xs font-semibold text-brand">
          ✨ {bookName(m.book)} {m.chapter}:{range}
        </div>
        <p className="amharic mt-1.5 text-[15px] leading-relaxed text-ink">
          {verseText ?? "…"}
        </p>
      </div>
    </div>
  );
}

/* ---------------- verse picker modal ---------------- */
function VersePicker({
  books,
  onClose,
  onSend,
}: {
  books: BookRef[];
  onClose: () => void;
  onSend: (book: number, chapter: number, start: number, end: number) => void;
}) {
  const [book, setBook] = useState<number | null>(null);
  const [data, setData] = useState<Book | null>(null);
  const [chapter, setChapter] = useState<number | null>(null);
  const [start, setStart] = useState<number | null>(null);
  const [end, setEnd] = useState<number | null>(null);

  useEffect(() => {
    if (book == null) return;
    setData(null);
    setChapter(null);
    setStart(null);
    setEnd(null);
    bookCached(book).then(setData).catch(() => {});
  }, [book]);

  const chap = data && chapter ? data.chapters[chapter - 1] : null;

  function tapVerse(v: number) {
    if (start == null || (start != null && end != null)) {
      setStart(v);
      setEnd(v);
    } else if (v >= start) {
      setEnd(v);
    } else {
      setStart(v);
      setEnd(v);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 sm:items-center">
      <div className="flex h-[85dvh] w-full max-w-lg flex-col rounded-t-2xl bg-surface sm:rounded-2xl">
        <div className="flex items-center justify-between border-b border-line px-4 py-3">
          <h3 className="font-bold">Share a verse</h3>
          <button onClick={onClose} className="text-ink-soft">
            ✕
          </button>
        </div>

        <div className="flex gap-2 border-b border-line p-3">
          <select
            value={book ?? ""}
            onChange={(e) => setBook(e.target.value ? +e.target.value : null)}
            className="amharic flex-1 rounded-lg border border-line bg-surface-2 px-3 py-2 text-sm outline-none"
          >
            <option value="">Book…</option>
            {books.map((b) => (
              <option key={b.num} value={b.num}>
                {b.num}. {b.name}
              </option>
            ))}
          </select>
          <select
            value={chapter ?? ""}
            onChange={(e) => {
              setChapter(e.target.value ? +e.target.value : null);
              setStart(null);
              setEnd(null);
            }}
            disabled={!data}
            className="w-28 rounded-lg border border-line bg-surface-2 px-3 py-2 text-sm outline-none disabled:opacity-50"
          >
            <option value="">Ch…</option>
            {data?.chapters.map((_, i) => (
              <option key={i} value={i + 1}>
                {i + 1}
              </option>
            ))}
          </select>
        </div>

        <div className="flex-1 overflow-y-auto p-4">
          {!chap ? (
            <p className="mt-10 text-center text-sm text-ink-faint">
              Pick a book and chapter, then tap verses (tap two to select a range).
            </p>
          ) : (
            <div className="reader-text">
              {chap.verses.map((v, i) => {
                const n = i + 1;
                const selected =
                  start != null && end != null && n >= start && n <= end;
                return (
                  <span
                    key={i}
                    onClick={() => tapVerse(n)}
                    className={`cursor-pointer rounded-lg px-1 py-0.5 ${
                      selected ? "bg-brand text-white" : "hover:bg-surface-2"
                    }`}
                  >
                    <sup className="mr-1 select-none font-sans text-[0.7em] font-bold opacity-70">
                      {n}
                    </sup>
                    {v}{" "}
                  </span>
                );
              })}
            </div>
          )}
        </div>

        <div className="border-t border-line p-3">
          <button
            disabled={book == null || chapter == null || start == null}
            onClick={() => onSend(book!, chapter!, start!, end ?? start!)}
            className="w-full rounded-xl bg-brand px-4 py-3 text-sm font-semibold text-white disabled:opacity-40"
          >
            {start != null
              ? `Share verse${end && end !== start ? `s ${start}-${end}` : ` ${start}`} 🔥`
              : "Select a verse"}
          </button>
        </div>
      </div>
    </div>
  );
}

