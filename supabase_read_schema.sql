-- ============================================================================
-- PrePora READ-MIRROR SCHEMA (Supabase)
-- This Supabase handles READS ONLY so the Firestore free-tier read quota is
-- never the bottleneck. Storage stays on the existing Storage-Settings
-- Supabase accounts (those are untouched).
--
-- Paste this into: Supabase Dashboard -> SQL Editor -> Run
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper: common timestamp
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto;

-- ============================================================================
-- users  (mirrors Firestore /users)
-- ============================================================================
create table if not exists public.users (
  id        text primary key,                 -- Firestore doc id (uid)
  data      jsonb not null default '{}'::jsonb,
  role      text,
  email     text,
  name      text,
  blocked   boolean,
  verified  boolean,
  free_trial_active boolean,
  free_trial_ends_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists users_role_idx on public.users (role);
create index if not exists users_email_idx on public.users (email);
create index if not exists users_trial_idx on public.users (free_trial_active, free_trial_ends_at);

-- ============================================================================
-- folders  (mirrors Firestore /folders)
-- ============================================================================
create table if not exists public.folders (
  id        text primary key,
  data      jsonb not null default '{}'::jsonb,
  name      text,
  locked    boolean,
  invisible boolean,
  updating  boolean,
  group_link text,
  inherit_group boolean,
  created_at timestamptz not null default now()
);
create index if not exists folders_created_idx on public.folders (created_at);

-- ============================================================================
-- contents  (mirrors Firestore /folders/{folderId}/contents)
-- ============================================================================
create table if not exists public.contents (
  id        text primary key,
  folder_id text not null,
  parent_content_id text,
  data      jsonb not null default '{}'::jsonb,
  name      text,
  title     text,
  type      text,
  url       text,
  youtube_url text,
  group_link text,
  locked    boolean,
  invisible boolean,
  updating  boolean,
  "order"   double precision,
  created_at timestamptz not null default now()
);
create index if not exists contents_folder_idx on public.contents (folder_id);
create index if not exists contents_parent_idx on public.contents (parent_content_id);
create index if not exists contents_type_idx on public.contents (type);

-- ============================================================================
-- web_sessions  (mirrors Firestore /web_sessions)  -- QR web-link flow
-- ============================================================================
create table if not exists public.web_sessions (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  session_id text,
  uid        text,
  status     text,
  web_browser text,
  user_email text,
  user_role  text,
  android_device_id text,
  created_at timestamptz not null default now(),
  last_active timestamptz,
  disconnected_at timestamptz
);
create index if not exists web_sessions_uid_idx on public.web_sessions (uid);
create index if not exists web_sessions_status_idx on public.web_sessions (status, uid);
create index if not exists web_sessions_created_idx on public.web_sessions (created_at);

-- ============================================================================
-- login_attempts  (mirrors Firestore /login_attempts)
-- ============================================================================
create table if not exists public.login_attempts (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  uid        text,
  device_id  text,
  device_model text,
  timestamp  timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists login_attempts_uid_idx on public.login_attempts (uid, timestamp desc);

-- ============================================================================
-- notifications  (mirrors Firestore /notifications)
-- ============================================================================
create table if not exists public.notifications (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  uid        text,
  read       boolean,
  message    text,
  user_name  text,
  type       text,
  created_at timestamptz not null default now()
);
create index if not exists notifications_uid_idx on public.notifications (uid, created_at desc);
create index if not exists notifications_uid_type_idx on public.notifications (uid, type);

-- ============================================================================
-- admin_notifications  (mirrors Firestore /admin_notifications)
-- ============================================================================
create table if not exists public.admin_notifications (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  read       boolean,
  message    text,
  type       text,
  created_at timestamptz not null default now()
);
create index if not exists admin_notifications_created_idx on public.admin_notifications (created_at desc);
create index if not exists admin_notifications_read_idx on public.admin_notifications (read);

-- ============================================================================
-- notices  (mirrors Firestore /notices)
-- ============================================================================
create table if not exists public.notices (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  title      text,
  file_type  text,
  added_by   text,
  created_at timestamptz not null default now()
);
create index if not exists notices_created_idx on public.notices (created_at desc);

-- ============================================================================
-- feedbacks  (mirrors Firestore /feedbacks)
-- ============================================================================
create table if not exists public.feedbacks (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  uid        text,
  status     text,
  viewed     boolean,
  message    text,
  reply      text,
  created_at timestamptz not null default now()
);
create index if not exists feedbacks_uid_idx on public.feedbacks (uid, created_at desc);
create index if not exists feedbacks_status_idx on public.feedbacks (status);

-- ============================================================================
-- settings  (mirrors Firestore /settings)  -- docs: general, notification_config
-- ============================================================================
create table if not exists public.settings (
  id    text primary key,                      -- 'general', 'notification_config'
  data  jsonb not null default '{}'::jsonb,
  paid_access boolean,
  price double precision,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- app_updates  (mirrors Firestore /app_updates)
-- ============================================================================
create table if not exists public.app_updates (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  version    text,
  link       text,
  created_at timestamptz not null default now()
);
create index if not exists app_updates_created_idx on public.app_updates (created_at desc);

-- ============================================================================
-- student_activities  (mirrors Firestore /student_activities)
-- ============================================================================
create table if not exists public.student_activities (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  uid        text,
  started_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists student_activities_uid_idx on public.student_activities (uid);

-- ============================================================================
-- assistant_access  (mirrors Firestore /Assistant_access)
-- ============================================================================
create table if not exists public.assistant_access (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  uid        text,
  folder_id  text,
  created_at timestamptz not null default now()
);
create index if not exists assistant_access_uid_idx on public.assistant_access (uid);
create index if not exists assistant_access_folder_idx on public.assistant_access (folder_id);

-- ============================================================================
-- content_assistant_access  (mirrors Firestore /content_Assistant_access)
-- ============================================================================
create table if not exists public.content_assistant_access (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  user_id    text,
  folder_id  text,
  content_id text,
  created_at timestamptz not null default now()
);
create index if not exists content_access_user_idx on public.content_assistant_access (user_id);
create index if not exists content_access_folder_content_idx on public.content_assistant_access (folder_id, content_id);

-- ============================================================================
-- assistant_logins  (mirrors Firestore /Assistant_logins)
-- ============================================================================
create table if not exists public.assistant_logins (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  folder_id  text,
  uid        text,
  name       text,
  timestamp  timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists assistant_logins_folder_idx on public.assistant_logins (folder_id, timestamp desc);

-- ============================================================================
-- login_history  (mirrors Firestore /login_history/{uid}/logins)
-- ============================================================================
create table if not exists public.login_history (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  uid        text,
  device     text,
  ip         text,
  timestamp  timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists login_history_uid_idx on public.login_history (uid, timestamp desc);

-- ============================================================================
-- ai_api_keys  (mirrors Firestore /ai_api_keys)
-- ============================================================================
create table if not exists public.ai_api_keys (
  id         text primary key,
  data       jsonb not null default '{}'::jsonb,
  api_key    text,
  base_url   text,
  model      text,
  provider   text,
  is_active  boolean,
  created_at timestamptz not null default now()
);
create index if not exists ai_api_keys_active_idx on public.ai_api_keys (is_active);

-- ============================================================================
-- notes  (mirrors Firestore /users/{uid}/notes)
-- ============================================================================
create table if not exists public.notes (
  id           text primary key,
  uid          text not null,
  data         jsonb not null default '{}'::jsonb,
  content      text,
  lecture_name text,
  updated_at   timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists notes_uid_idx on public.notes (uid, updated_at desc);

-- ============================================================================
-- conversations  (mirrors Firestore /users/{uid}/conversations)
-- ============================================================================
create table if not exists public.conversations (
  id           text primary key,
  uid          text not null,
  data         jsonb not null default '{}'::jsonb,
  title        text,
  last_message text,
  updated_at   timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists conversations_uid_idx on public.conversations (uid, updated_at desc);

-- ============================================================================
-- messages  (mirrors Firestore /users/{uid}/conversations/{convId}/messages)
-- ============================================================================
create table if not exists public.messages (
  id              text primary key,
  conversation_id text not null,
  data            jsonb not null default '{}'::jsonb,
  role            text,
  content         text,
  timestamp       timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists messages_conv_idx on public.messages (conversation_id, timestamp);

-- ============================================================================
-- RLS: ENABLE + POLICIES
-- Reads (SELECT)   -> anon (the app uses the anon key; this is the read path)
-- Writes           -> service_role ONLY (backfill scripts / dual-write proxy)
-- If you later want the app itself to write, add authenticated/anon upsert
-- policies per table. Keeping writes service-role-only is safer by default.
-- ============================================================================
alter table public.users                 enable row level security;
alter table public.folders               enable row level security;
alter table public.contents              enable row level security;
alter table public.web_sessions          enable row level security;
alter table public.login_attempts        enable row level security;
alter table public.notifications         enable row level security;
alter table public.admin_notifications   enable row level security;
alter table public.notices               enable row level security;
alter table public.feedbacks             enable row level security;
alter table public.settings              enable row level security;
alter table public.app_updates           enable row level security;
alter table public.student_activities    enable row level security;
alter table public.assistant_access      enable row level security;
alter table public.content_assistant_access enable row level security;
alter table public.assistant_logins      enable row level security;
alter table public.login_history         enable row level security;
alter table public.ai_api_keys           enable row level security;
alter table public.notes                 enable row level security;
alter table public.conversations         enable row level security;
alter table public.messages              enable row level security;

-- Service role bypasses RLS automatically, so no policy needed for it.

do $$
declare t text;
begin
  foreach t in array array[
    'users','folders','contents','web_sessions','login_attempts','notifications',
    'admin_notifications','notices','feedbacks','settings','app_updates',
    'student_activities','assistant_access','content_assistant_access',
    'assistant_logins','login_history','ai_api_keys','notes','conversations','messages'
  ] loop
    execute format('create policy %I_select on public.%I for select to anon using (true);', t, t);
  end loop;
end $$;

-- ============================================================================
-- DEFAULT READ-MIRROR ACCOUNT (the one the app uses for reads)
-- Stored in a settings row so the app can fetch it even before Firestore is up.
-- ============================================================================
insert into public.settings (id, data)
values ('read_mirror', '{"projectUrl":"https://qluwnxsmnxvvqoiejtbr.supabase.co","anonKey":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFsdXdueHNtbnh2dnFvaWVqdGJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwMDAzNTEsImV4cCI6MjEwMjU3NjM1MX0.lYGxH02Kb0qS2Lm46Mc5lQoOyd7VR1-6WWSBA2TXfr8","serviceRoleKey":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFsdXdueHNtbnh2dnFvaWVqdGJyIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzAwMDM1MSwiZXhwIjoyMTAyNTc2MzUxfQ.O0f1MwOmaXkBUKO1I4v6heUtjyFK9Ru2O64yy3wViwg","isActive":true}')
on conflict (id) do update set data = excluded.data;

-- ============================================================================
-- Optional: storage buckets are NOT created here. Storage uses the existing
-- Storage-Settings Supabase accounts only (untouched).
-- ============================================================================