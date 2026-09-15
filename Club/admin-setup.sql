-- El Capricho Club - pannello amministratore
-- Eseguire UNA SOLA VOLTA nel SQL Editor di Supabase.
-- L'accesso admin e' consentito solo all'email indicata qui sotto.

create or replace function public.club_admin_allowed()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'rosticceriaitalianatenerife@gmail.com';
$$;

create or replace function public.club_admin_search(p_query text default '')
returns table (
  id uuid,
  member_code text,
  name text,
  phone text,
  points integer,
  active boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.club_admin_allowed() then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  return query
  select c.id, c.member_code, c.name, c.phone, c.points, c.active
  from public.customers c
  where nullif(trim(p_query), '') is null
     or c.name ilike '%' || trim(p_query) || '%'
     or c.phone ilike '%' || trim(p_query) || '%'
     or c.member_code ilike '%' || trim(p_query) || '%'
  order by c.name
  limit 50;
end;
$$;

create or replace function public.club_admin_adjust_points(
  p_customer uuid,
  p_delta integer,
  p_description text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_points integer;
  v_new_points integer;
begin
  if not public.club_admin_allowed() then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if p_delta is null or p_delta = 0 or abs(p_delta) > 10000 then
    raise exception 'INVALID_DELTA' using errcode = 'P0001';
  end if;

  select c.points into v_points
  from public.customers c
  where c.id = p_customer
  for update;

  if v_points is null then
    raise exception 'CUSTOMER_NOT_FOUND' using errcode = 'P0001';
  end if;

  v_new_points := v_points + p_delta;
  if v_new_points < 0 then
    raise exception 'INSUFFICIENT_POINTS' using errcode = 'P0001';
  end if;

  update public.customers
  set points = v_new_points
  where id = p_customer;

  insert into public.points_transactions(customer_id, points, amount_eur, description)
  values (
    p_customer,
    p_delta,
    null,
    coalesce(nullif(trim(p_description), ''), case when p_delta > 0 then 'Aggiunta punti da pannello admin' else 'Riscatto/correzione da pannello admin' end)
  );

  return v_new_points;
end;
$$;

revoke all on function public.club_admin_allowed() from public;
revoke all on function public.club_admin_search(text) from public;
revoke all on function public.club_admin_adjust_points(uuid, integer, text) from public;

grant execute on function public.club_admin_allowed() to authenticated;
grant execute on function public.club_admin_search(text) to authenticated;
grant execute on function public.club_admin_adjust_points(uuid, integer, text) to authenticated;
