-- Брикстон: схема для Supabase. Выполнить целиком в SQL Editor.
-- 1) ЗАМЕНИТЕ почту владельца на свою (ту, что создадите в Authentication -> Users)
create or replace function public.is_owner() returns boolean
language sql stable as $$
  select coalesce(auth.jwt() ->> 'email','') = 'ВАША_ПОЧТА@example.com'
$$;

create extension if not exists btree_gist;

create table if not exists public.config (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now()
);
insert into public.config (id, data) values (1, '{}') on conflict do nothing;

create table if not exists public.bookings (
  id text primary key,
  s text, m text not null, d date not null, t int not null, u int not null,
  p int not null default 0, sn text, mn text,
  n text not null check (length(n) between 2 and 100),
  ph text not null check (length(ph) <= 30),
  st text not null default 'ok',
  created_at timestamptz default now(),
  -- нельзя занять одного мастера на пересекающееся время
  constraint no_overlap exclude using gist (m with =, d with =, int4range(t, t + u) with &&)
);

alter table public.config   enable row level security;
alter table public.bookings enable row level security;

-- настройки (услуги, мастера, фото, график): читают все, меняет только владелец
create policy cfg_read  on public.config for select to anon, authenticated using (true);
create policy cfg_write on public.config for all to authenticated using (is_owner()) with check (is_owner());

-- записи: клиент может только создать; видит и меняет всё только владелец
create policy bk_insert on public.bookings for insert to anon, authenticated
  with check (st = 'ok' and d >= current_date - 1);
create policy bk_owner on public.bookings for all to authenticated
  using (is_owner()) with check (is_owner());

-- занятые слоты без имён и телефонов (для всех клиентов)
create or replace function public.busy(from_date date)
returns table (m text, d date, t int, u int)
language sql security definer set search_path = public as $$
  select m, d, t, u from bookings where d >= from_date
$$;

-- клиент видит только свои записи (по id, которые хранятся у него на телефоне)
create or replace function public.my_bookings(ids text[])
returns setof public.bookings
language sql security definer set search_path = public as $$
  select * from bookings where id = any(ids)
$$;

-- клиент отменяет свою запись
create or replace function public.cancel_booking(bid text)
returns void
language sql security definer set search_path = public as $$
  delete from bookings where id = bid
$$;

grant execute on function public.busy(date), public.my_bookings(text[]), public.cancel_booking(text) to anon, authenticated;
