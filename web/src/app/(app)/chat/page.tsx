import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getMyFriends } from "@/lib/friends";
import { ClickableAvatar } from "@/components/app/ClickableAvatar";
import { RealtimeRefresher } from "@/components/app/RealtimeRefresher";

export const metadata = { title: "Chats · መጽሐፍ ቅዱስ" };

type Msg = {
  friendship_id: string;
  type: string;
  text: string | null;
  sender_id: string;
  created_at: string;
  read_at: string | null;
};

function preview(m: Msg | undefined, myId: string): string {
  if (!m) return "Share a verse to start your streak";
  const mine = m.sender_id === myId ? "You: " : "";
  if (m.type === "verse") return `${mine}📖 Shared a verse`;
  if (m.type === "image") return `${mine}🖼 Photo`;
  return `${mine}${m.text ?? ""}`;
}

function timeLabel(iso: string): string {
  const d = new Date(iso);
  const today = new Date();
  if (d.toDateString() === today.toDateString())
    return d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export default async function ChatIndex() {
  const friends = await getMyFriends();

  if (friends.length === 0) {
    return (
      <div className="grid h-full place-items-center px-6 text-center">
        <div className="max-w-xs">
          <div className="font-display text-6xl text-gold/50">✦</div>
          <h1 className="amharic mt-4 text-xl font-bold">ገና ጓደኛ የለዎትም</h1>
          <p className="mt-1 text-sm text-ink-soft">
            Add a friend to start chatting and sharing verses.
          </p>
          <Link
            href="/friends"
            className="mt-5 inline-block rounded-xl bg-brand px-5 py-2.5 text-sm font-semibold text-brand-ink"
          >
            Find a friend
          </Link>
        </div>
      </div>
    );
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const myId = user!.id;
  const fids = friends.map((f) => f.friendshipId);

  const { data: msgs } = await supabase
    .from("messages")
    .select("friendship_id, type, text, sender_id, created_at, read_at")
    .in("friendship_id", fids)
    .order("created_at", { ascending: false })
    .limit(400);

  const last = new Map<string, Msg>();
  const unread = new Map<string, number>();
  for (const m of (msgs as Msg[]) ?? []) {
    if (!last.has(m.friendship_id)) last.set(m.friendship_id, m);
    if (m.sender_id !== myId && !m.read_at)
      unread.set(m.friendship_id, (unread.get(m.friendship_id) ?? 0) + 1);
  }

  const items = [...friends].sort((a, b) => {
    const ta = last.get(a.friendshipId)?.created_at ?? "";
    const tb = last.get(b.friendshipId)?.created_at ?? "";
    return tb.localeCompare(ta);
  });

  return (
    <div className="mx-auto max-w-2xl px-5 py-8">
      <RealtimeRefresher tables={["messages", "streaks"]} />
      <div className="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.18em] text-gold">
        <span className="h-1 w-1 rounded-full bg-gold" />
        መልእክቶች · Messages
      </div>
      <h1 className="mt-2 font-display text-3xl font-bold text-ink">Chats</h1>

      <div className="mt-6 overflow-hidden rounded-3xl border border-line bg-surface shadow-card">
        {items.map((f, i) => {
          const lm = last.get(f.friendshipId);
          const un = unread.get(f.friendshipId) ?? 0;
          return (
            <Link
              key={f.friendshipId}
              href={`/chat/${f.friendshipId}`}
              className={`flex items-center gap-3.5 px-4 py-3.5 transition hover:bg-surface-2 ${
                i > 0 ? "border-t border-line" : ""
              }`}
            >
              <ClickableAvatar
                name={f.friend.name ?? f.friend.username}
                url={f.friend.avatar_url}
                size={52}
              />
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <span className="truncate font-semibold text-ink">
                    {f.friend.name ?? f.friend.username}
                  </span>
                  {lm && (
                    <span className="shrink-0 text-[11px] text-ink-faint">
                      {timeLabel(lm.created_at)}
                    </span>
                  )}
                </div>
                <div className="flex items-center justify-between gap-2">
                  <span
                    className={`truncate text-sm ${
                      un > 0 ? "font-medium text-ink" : "text-ink-faint"
                    }`}
                  >
                    {preview(lm, myId)}
                  </span>
                  <span className="flex shrink-0 items-center gap-2">
                    <span className="text-xs font-bold text-ink-soft">
                      🔥 {f.streak?.count ?? 0}
                    </span>
                    {un > 0 && (
                      <span className="grid h-5 min-w-5 place-items-center rounded-full bg-brand px-1.5 text-[11px] font-bold text-brand-ink">
                        {un}
                      </span>
                    )}
                  </span>
                </div>
              </div>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
