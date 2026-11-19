-- BYSAM platformu: siteler, site dosyalari, yonetici yetkileri ve Storage bucket.
-- Supabase Dashboard > SQL Editor icinde bu dosyanin tamamini calistirin.

create extension if not exists pgcrypto;

-- 1) Yonetici listesi. Buraya sadece SQL Editor'den guvendiginiz auth kullanicisini ekleyin.
create table if not exists public.bysam_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.bysam_admins enable row level security;

create or replace function public.is_bysam_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.bysam_admins a
    where a.user_id = auth.uid()
  );
$$;

revoke all on function public.is_bysam_admin() from public;
grant execute on function public.is_bysam_admin() to anon, authenticated;

drop policy if exists "BYSAM admin can read own admin row" on public.bysam_admins;
create policy "BYSAM admin can read own admin row"
on public.bysam_admins for select to authenticated
using (user_id = auth.uid());

-- 2) Site kayitlari. Ozel uzantilar BYSAM arama sistemi icin mantiksal adreslerdir.
create table if not exists public.bysam_sites (
  id uuid primary key default gen_random_uuid(),
  site_name text not null check (char_length(site_name) between 1 and 80),
  slug text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  domain_extension text not null check (domain_extension in ('.bysam','.bysm','.kızmalımı','.etmez','.upset','.siber','.bry','.beray','.xmax')),
  domain text generated always as (slug || domain_extension) stored unique,
  description text,
  status text not null default 'draft' check (status in ('draft','published','disabled')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bysam_sites_status_idx on public.bysam_sites(status);
create index if not exists bysam_sites_name_idx on public.bysam_sites using gin (to_tsvector('simple', site_name));
alter table public.bysam_sites enable row level security;

drop policy if exists "BYSAM sites are visible when published or admin" on public.bysam_sites;
create policy "BYSAM sites are visible when published or admin"
on public.bysam_sites for select to anon, authenticated
using (status = 'published' or public.is_bysam_admin());

drop policy if exists "BYSAM admins create sites" on public.bysam_sites;
create policy "BYSAM admins create sites"
on public.bysam_sites for insert to authenticated
with check (public.is_bysam_admin() and (created_by is null or created_by = auth.uid()));

drop policy if exists "BYSAM admins update sites" on public.bysam_sites;
create policy "BYSAM admins update sites"
on public.bysam_sites for update to authenticated
using (public.is_bysam_admin())
with check (public.is_bysam_admin());

drop policy if exists "BYSAM admins delete sites" on public.bysam_sites;
create policy "BYSAM admins delete sites"
on public.bysam_sites for delete to authenticated
using (public.is_bysam_admin());

-- 3) Site dosyalarinin yolu ve metadata bilgisi.
create table if not exists public.bysam_site_files (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.bysam_sites(id) on delete cascade,
  file_path text not null,
  storage_path text not null unique,
  mime_type text not null default 'application/octet-stream',
  size_bytes bigint not null default 0 check (size_bytes >= 0),
  is_entry boolean not null default false,
  created_at timestamptz not null default now(),
  unique (site_id, file_path)
);

create unique index if not exists bysam_one_entry_per_site_idx
on public.bysam_site_files(site_id) where is_entry = true;
create index if not exists bysam_site_files_site_idx on public.bysam_site_files(site_id);
alter table public.bysam_site_files enable row level security;

drop policy if exists "BYSAM site files visible when published or admin" on public.bysam_site_files;
create policy "BYSAM site files visible when published or admin"
on public.bysam_site_files for select to anon, authenticated
using (
  public.is_bysam_admin()
  or exists (
    select 1 from public.bysam_sites s
    where s.id = bysam_site_files.site_id and s.status = 'published'
  )
);

drop policy if exists "BYSAM admins add site files" on public.bysam_site_files;
create policy "BYSAM admins add site files"
on public.bysam_site_files for insert to authenticated
with check (public.is_bysam_admin());

drop policy if exists "BYSAM admins update site files" on public.bysam_site_files;
create policy "BYSAM admins update site files"
on public.bysam_site_files for update to authenticated
using (public.is_bysam_admin())
with check (public.is_bysam_admin());

drop policy if exists "BYSAM admins delete site files" on public.bysam_site_files;
create policy "BYSAM admins delete site files"
on public.bysam_site_files for delete to authenticated
using (public.is_bysam_admin());

-- 4) updated_at otomatik guncellensin.
create or replace function public.bysam_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists bysam_sites_updated_at on public.bysam_sites;
create trigger bysam_sites_updated_at
before update on public.bysam_sites
for each row execute function public.bysam_set_updated_at();

-- 5) BYSAM web dosyalari icin public bucket.
-- Web sayfalari ziyaretciler tarafindan okunabilir; yukleme/silme yalnizca admin hesabina aciktir.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'bysam-sites',
  'bysam-sites',
  true,
  52428800,
  array[
    'text/html','text/css','text/javascript','application/javascript','application/json','text/plain','text/xml',
    'image/png','image/jpeg','image/webp','image/gif','image/svg+xml','image/x-icon',
    'font/woff','font/woff2','font/ttf','font/otf','application/pdf',
    'audio/mpeg','audio/wav','video/mp4','video/webm','application/octet-stream'
  ]
)
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Public bucket URL'leri okunabilir. Storage list/metadata ve yazma işlemleri RLS ile kısıtlanır.
drop policy if exists "BYSAM admins list site objects" on storage.objects;
create policy "BYSAM admins list site objects"
on storage.objects for select to authenticated
using (bucket_id = 'bysam-sites' and public.is_bysam_admin());

drop policy if exists "BYSAM admins upload site objects" on storage.objects;
create policy "BYSAM admins upload site objects"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'bysam-sites'
  and public.is_bysam_admin()
  and exists (
    select 1 from public.bysam_sites s
    where s.id::text = (storage.foldername(name))[1]
  )
);

drop policy if exists "BYSAM admins update site objects" on storage.objects;
create policy "BYSAM admins update site objects"
on storage.objects for update to authenticated
using (bucket_id = 'bysam-sites' and public.is_bysam_admin())
with check (bucket_id = 'bysam-sites' and public.is_bysam_admin());

drop policy if exists "BYSAM admins delete site objects" on storage.objects;
create policy "BYSAM admins delete site objects"
on storage.objects for delete to authenticated
using (bucket_id = 'bysam-sites' and public.is_bysam_admin());

-- 6) Gerekli tablo izinleri (gercek erisim ayrica RLS politikalarina tabidir).
grant select, insert, update, delete on public.bysam_sites to authenticated;
grant select on public.bysam_sites to anon;
grant select, insert, update, delete on public.bysam_site_files to authenticated;
grant select on public.bysam_site_files to anon;
grant select on public.bysam_admins to authenticated;

-- -----------------------------------------------------------------------------
-- ILK YONETICIYI EKLEME (bu bolumu kendi e-posta adresinle duzenleyip ayri calistir):
-- Once Supabase Dashboard > Authentication > Users > Add user ile kullanici olustur.
-- Ardindan asagidaki komutta e-posta adresini yaz ve SQL Editor'de calistir:
--
-- insert into public.bysam_admins (user_id)
-- select id from auth.users where lower(email) = lower('ADMIN_EPOSTA_ADRESIN')
-- on conflict (user_id) do nothing;
--
-- service_role / secret key'i admin.html dosyasina veya tarayiciya ASLA koyma.
