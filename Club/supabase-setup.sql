-- El Capricho Club: accesso cliente sicuro via RPC
-- Eseguire una sola volta nel SQL Editor di Supabase.

create extension if not exists pgcrypto;

alter table public.customers
  add column if not exists client_token uuid unique not null default gen_random_uuid();

-- Niente accesso diretto dal browser alle tabelle sensibili.
revoke all on table public.customers from anon, authenticated;
revoke all on table public.points_transactions from anon, authenticated;
revoke all on table public.redemptions from anon, authenticated;
revoke all on table public.rewards from anon, authenticated;

create or replace function public.club_register(p_name text, p_phone text)
returns table (
  id uuid,
  member_code text,
  name text,
  points integer,
  client_token uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer public.customers%rowtype;
begin
  if nullif(trim(p_name), '') is null or char_length(trim(p_name)) > 120 then
    raise exception 'INVALID_NAME' using errcode = 'P0001';
  end if;

  if nullif(trim(p_phone), '') is null or char_length(trim(p_phone)) > 40 then
    raise exception 'INVALID_PHONE' using errcode = 'P0001';
  end if;

  insert into public.customers(name, phone)
  values (trim(p_name), trim(p_phone))
  returning * into v_customer;

  insert into public.points_transactions(customer_id, points, amount_eur, description)
  values (v_customer.id, 10, null, 'Bonus bienvenida');

  return query
  select v_customer.id,
         v_customer.member_code,
         v_customer.name,
         v_customer.points,
         v_customer.client_token;
exception
  when unique_violation then
    raise exception 'PHONE_EXISTS' using errcode = 'P0001';
end;
$$;

create or replace function public.club_get(p_token uuid)
returns table (
  id uuid,
  member_code text,
  name text,
  points integer
)
language sql
security definer
set search_path = public
stable
as $$
  select c.id, c.member_code, c.name, c.points
  from public.customers c
  where c.client_token = p_token
    and c.active = true
  limit 1;
$$;

create or replace function public.club_rewards()
returns table (
  id bigint,
  name text,
  points_required integer
)
language sql
security definer
set search_path = public
stable
as $$
  select r.id, r.name, r.points_required
  from public.rewards r
  where r.active = true
  order by r.points_required, r.id;
$$;

revoke all on function public.club_register(text, text) from public;
revoke all on function public.club_get(uuid) from public;
revoke all on function public.club_rewards() from public;

grant execute on function public.club_register(text, text) to anon, authenticated;
grant execute on function public.club_get(uuid) to anon, authenticated;
grant execute on function public.club_rewards() to anon, authenticated;
