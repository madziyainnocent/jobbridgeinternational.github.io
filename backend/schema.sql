-- JobBridge International recruitment platform
-- Apply in Supabase SQL Editor. Review policies before production launch.

create extension if not exists pgcrypto;

create type public.account_role as enum ('candidate','admin','recruiter');
create type public.application_status as enum (
  'received','under_review','shortlisted','interview_scheduled',
  'selected','documentation','work_permit','placed','rejected','withdrawn'
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text,
  phone text,
  nationality text,
  country_of_residence text,
  role public.account_role not null default 'candidate',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vacancies (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  employer_name text,
  destination_country text,
  location text,
  description text not null default '',
  requirements jsonb not null default '[]'::jsonb,
  employment_type text,
  is_published boolean not null default false,
  closing_date date,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.applications (
  id uuid primary key default gen_random_uuid(),
  reference_code text unique not null default ('JBI-' || upper(substr(encode(gen_random_bytes(6),'hex'),1,10))),
  candidate_id uuid not null references public.profiles(id) on delete cascade,
  vacancy_id uuid not null references public.vacancies(id),
  status public.application_status not null default 'received',
  cover_note text,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(candidate_id, vacancy_id)
);

create table public.application_events (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  old_status public.application_status,
  new_status public.application_status not null,
  note text,
  visible_to_candidate boolean not null default true,
  changed_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.candidate_documents (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  candidate_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null,
  document_type text not null,
  original_filename text not null,
  uploaded_at timestamptz not null default now()
);

create table public.conversation_logs (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid references public.profiles(id) on delete set null,
  channel text not null check (channel in ('website','whatsapp')),
  external_contact text,
  direction text not null check (direction in ('inbound','outbound')),
  message_text text not null,
  created_at timestamptz not null default now()
);

create index applications_candidate_idx on public.applications(candidate_id);
create index applications_status_idx on public.applications(status);
create index applications_vacancy_idx on public.applications(vacancy_id);
create index events_application_idx on public.application_events(application_id, created_at);
create index vacancies_published_idx on public.vacancies(is_published, closing_date);

create or replace function public.is_staff()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin','recruiter')
  );
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, full_name, email, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    new.email,
    new.raw_user_meta_data->>'phone'
  ) on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.vacancies enable row level security;
alter table public.applications enable row level security;
alter table public.application_events enable row level security;
alter table public.candidate_documents enable row level security;
alter table public.conversation_logs enable row level security;

create policy "Candidates read own profile; staff read all"
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_staff());
create policy "Candidates update own profile"
on public.profiles for update to authenticated
using (id = auth.uid() and role = 'candidate')
with check (id = auth.uid() and role = 'candidate');
create policy "Staff manage profiles"
on public.profiles for all to authenticated
using (public.is_staff()) with check (public.is_staff());

create policy "Public can view published vacancies"
on public.vacancies for select
using (is_published = true or public.is_staff());
create policy "Staff manage vacancies"
on public.vacancies for all to authenticated
using (public.is_staff()) with check (public.is_staff());

create policy "Candidates view own applications; staff view all"
on public.applications for select to authenticated
using (candidate_id = auth.uid() or public.is_staff());
create policy "Candidates submit own applications"
on public.applications for insert to authenticated
with check (candidate_id = auth.uid());
create policy "Staff update applications"
on public.applications for update to authenticated
using (public.is_staff()) with check (public.is_staff());

create policy "Candidates see visible events on own applications; staff see all"
on public.application_events for select to authenticated
using (
  public.is_staff() or (
    visible_to_candidate = true and exists (
      select 1 from public.applications a
      where a.id = application_id and a.candidate_id = auth.uid()
    )
  )
);
create policy "Staff add application events"
on public.application_events for insert to authenticated
with check (public.is_staff());

create policy "Candidates manage own document metadata; staff view all"
on public.candidate_documents for select to authenticated
using (candidate_id = auth.uid() or public.is_staff());
create policy "Candidates register own document metadata"
on public.candidate_documents for insert to authenticated
with check (candidate_id = auth.uid());
create policy "Staff manage document metadata"
on public.candidate_documents for all to authenticated
using (public.is_staff()) with check (public.is_staff());

create policy "Staff view conversation logs"
on public.conversation_logs for select to authenticated
using (public.is_staff());
create policy "Staff insert conversation logs"
on public.conversation_logs for insert to authenticated
with check (public.is_staff());

-- Create a private Storage bucket named candidate-documents in Supabase Storage.
-- Add Storage policies separately; never make candidate CVs publicly accessible.
-- Assign the first administrator manually in SQL after creating their account:
-- update public.profiles set role='admin' where email='YOUR-ADMIN-EMAIL';
