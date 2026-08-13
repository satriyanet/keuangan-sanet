-- ============================================================
-- SKEMA DATABASE: Aplikasi Keuangan Perusahaan
-- Jalankan seluruh isi file ini di Supabase Dashboard > SQL Editor > New query
-- ============================================================

-- Ekstensi untuk hashing password
create extension if not exists pgcrypto;

-- ---------- Tabel pengguna aplikasi (bukan Supabase Auth) ----------
create table app_users (
  id uuid primary key default gen_random_uuid(),
  username text unique not null,
  password_hash text not null,
  role text not null check (role in ('owner','accounting')),
  created_at timestamptz default now()
);

-- Akun owner awal (username: satriya, password: Anjali#2210)
insert into app_users (username, password_hash, role)
values ('satriya', crypt('Anjali#2210', gen_salt('bf')), 'owner');

-- ---------- Tabel data keuangan ----------
create table transactions (
  id bigint generated always as identity primary key,
  date date not null,
  description text not null,
  category text,
  amount numeric not null,
  created_by text,
  created_at timestamptz default now()
);

create table receivables (
  id bigint generated always as identity primary key,
  name text not null,
  amount numeric not null,
  status text not null default 'lancar',
  created_at timestamptz default now()
);

create table payables (
  id bigint generated always as identity primary key,
  name text not null,
  amount numeric not null,
  status text not null default 'lancar',
  created_at timestamptz default now()
);

create table budgets (
  id bigint generated always as identity primary key,
  category text not null,
  amount numeric not null,
  created_at timestamptz default now()
);

-- ---------- Row Level Security ----------
alter table app_users enable row level security;
alter table transactions enable row level security;
alter table receivables enable row level security;
alter table payables enable row level security;
alter table budgets enable row level security;

-- app_users TIDAK bisa dibaca langsung oleh siapa pun (termasuk anon key).
-- Login/pembuatan akun hanya lewat fungsi khusus di bawah (security definer).
revoke all on app_users from anon, authenticated;

-- Tabel data: akses dibuka untuk anon key (lihat catatan keamanan di README)
create policy "anon full access" on transactions for all to anon using (true) with check (true);
create policy "anon full access" on receivables  for all to anon using (true) with check (true);
create policy "anon full access" on payables     for all to anon using (true) with check (true);
create policy "anon full access" on budgets      for all to anon using (true) with check (true);

-- ---------- Fungsi: login ----------
create or replace function login(p_username text, p_password text)
returns table(username text, role text)
language plpgsql
security definer
as $$
begin
  return query
  select u.username, u.role
  from app_users u
  where u.username = p_username
    and u.password_hash = crypt(p_password, u.password_hash);
end;
$$;
grant execute on function login(text, text) to anon;

-- ---------- Fungsi: buat akun baru (hanya oleh owner) ----------
create or replace function create_user(p_requester text, p_username text, p_password text, p_role text)
returns text
language plpgsql
security definer
as $$
declare
  requester_role text;
begin
  select role into requester_role from app_users where username = p_requester;
  if requester_role is distinct from 'owner' then
    raise exception 'Hanya owner yang dapat membuat akun baru';
  end if;
  if p_role not in ('owner','accounting') then
    raise exception 'Peran tidak valid';
  end if;
  if length(p_password) < 6 then
    raise exception 'Password minimal 6 karakter';
  end if;
  if exists (select 1 from app_users where username = p_username) then
    raise exception 'Username sudah digunakan';
  end if;
  insert into app_users(username, password_hash, role)
  values (p_username, crypt(p_password, gen_salt('bf')), p_role);
  return 'ok';
end;
$$;
grant execute on function create_user(text, text, text, text) to anon;

-- ---------- Fungsi: daftar pengguna (hanya oleh owner) ----------
create or replace function list_users(p_requester text)
returns table(username text, role text)
language plpgsql
security definer
as $$
declare
  requester_role text;
begin
  select role into requester_role from app_users where username = p_requester;
  if requester_role is distinct from 'owner' then
    raise exception 'Hanya owner yang dapat melihat daftar pengguna';
  end if;
  return query select u.username, u.role from app_users u order by u.created_at;
end;
$$;
grant execute on function list_users(text) to anon;

-- ---------- Fungsi: hapus pengguna (hanya oleh owner, tidak bisa hapus diri sendiri) ----------
create or replace function delete_user(p_requester text, p_target text)
returns text
language plpgsql
security definer
as $$
declare
  requester_role text;
begin
  select role into requester_role from app_users where username = p_requester;
  if requester_role is distinct from 'owner' then
    raise exception 'Hanya owner yang dapat menghapus akun';
  end if;
  if p_requester = p_target then
    raise exception 'Tidak dapat menghapus akun sendiri';
  end if;
  delete from app_users where username = p_target;
  return 'ok';
end;
$$;
grant execute on function delete_user(text, text) to anon;

-- ============================================================
-- CATATAN KEAMANAN (baca ini):
-- Skema ini memblokir pembacaan langsung tabel app_users, dan setiap
-- perubahan data melewati fungsi database. Namun karena aplikasi berjalan
-- 100% di browser (tanpa server sendiri) dan memakai "anon key" yang publik,
-- siapa pun yang menemukan anon key (mudah dilihat di source HTML) secara
-- teknis bisa memanggil fungsi-fungsi ini langsung lewat API tanpa lewat
-- tampilan login. Untuk tim kecil yang saling percaya ini biasanya cukup;
-- untuk keamanan tingkat lebih tinggi, langkah berikutnya adalah memakai
-- Supabase Auth (sesi login sungguhan) + Edge Functions.
-- ============================================================
