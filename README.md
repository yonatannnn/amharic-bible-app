# Amharic Bible App

A social, streak-based Bible app for Amharic readers — think a "verse-a-day" habit
you keep up *with a friend*. Two people keep a streak alive by each sharing a verse
every day, with chat, daily-chapter reading, and reminders.

> **Development note:** This project was built over several weeks (≈ May–June 2026).
> It was brought under version control later, so the commit dates here reflect when
> the code was imported into git rather than the day each line was originally written.

## Monorepo layout

| Path | Stack | What it is |
|------|-------|------------|
| `amharic-bible-api/` | NestJS + TypeScript | Amharic Bible content API (66 books served from JSON). |
| `web/` | Next.js (App Router) + TypeScript | The web app — auth, streaks, chat, reader, profile. |
| `web/supabase/` | Postgres / Supabase | Schema, RLS, SQL migrations, and edge functions. |
| `mobile/` | Flutter | The native mobile app (same backend). |
| `supabase/` | Supabase config | Project config. |
| `SPEC.md` | — | Original product spec. |

## How it works

- **Auth & profiles** via Supabase Auth.
- **Friendships** (request / accept) connect two readers.
- **Streaks** — both friends must share a verse each day to keep the streak;
  the streak day rolls over at **midnight (Africa/Addis_Ababa)** with an 11:00
  grace deadline, tracked entirely in Postgres functions (`register_verse_share`,
  `expire_streaks`) driven by a trigger on new messages.
- **Chat & verse sharing** — verse, text, and image messages between friends.
- **Daily chapter / verse** generated and cached server-side.
- **Reminders & push** via Supabase edge functions + `pg_cron`.

## Local setup

Each sub-project has its own README and a `.env.local.example`. In short:

```bash
# content API
cd amharic-bible-api && npm install && npm run start:dev

# web app
cd web && npm install && cp .env.local.example .env.local   # fill in Supabase keys
npm run dev

# mobile
cd mobile && flutter pub get && flutter run
```

Secrets (`.env.local`, service-role keys, `google-services.json`, signing keys)
are intentionally **not** committed — see `.gitignore`.
