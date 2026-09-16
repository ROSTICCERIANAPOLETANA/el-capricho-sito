-- El Capricho Club v2
-- Regole: 1 EUR = 1 punto; i punti acquistati scadono dopo 15 giorni;
-- ogni 50 punti utilizzati = 5 EUR di sconto.
-- Eseguire UNA SOLA VOLTA nel SQL Editor di Supabase.

alter table public.points_transactions
  add column if not exists expires_at timestamptz;

-- I vecchi movimenti positivi ricevono 15 giorni dalla loro data originale.
update public.points_transactions
set expires_at = created_at + interval '15 days'
where points > 0 and expires_at is null;

create index if not exists points_transactions_customer_expiry_idx
  on public.points_transactions(customer_id, expires_at)
  where points > 0;

-- Saldo realmente disponibile: accrediti non scaduti + addebiti/riscatti.
create or replace function public.club_available_points(p_customer uuid)
returns integer
language sql
security definer
set search_path = public
stable
as $$
  select greatest(0, coalesce(sum(
    case
      when t.points > 0 and (t.expires_at is null or t.expires_at > now()) then t.points
      when t.points < 0 then t.points
      else 0
    end
  ),0)::integer)
  from public.points_transactions t
  where t.customer_id = p_customer;
$$;

create or replace function public.club_sync_points(p_customer uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_points integer;
begin
  v_points := public.club_available_points(p_customer);
  update public.customers set points=v_points where id=p_customer;
  return v_points;
end;
$$;

-- Accredito acquisto dal pannello cassa: 1 punto per ogni euro intero speso.
create or replace function public.club_admin_add_purchase(p_customer uuid, p_amount_eur numeric)
returns table(points_added integer, new_points integer, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_added integer;
  v_exp timestamptz := now() + interval '15 days';
  v_new integer;
begin
  if not public.club_admin_allowed() then raise exception 'FORBIDDEN' using errcode='P0001'; end if;
  if p_amount_eur is null or p_amount_eur <= 0 or p_amount_eur > 10000 then raise exception 'INVALID_AMOUNT' using errcode='P0001'; end if;
  v_added := floor(p_amount_eur)::integer;
  if v_added < 1 then raise exception 'AMOUNT_TOO_LOW' using errcode='P0001'; end if;

  insert into public.points_transactions(customer_id,points,amount_eur,description,expires_at)
  values(p_customer,v_added,p_amount_eur,'Acquisto - 1 punto per euro',v_exp);
  v_new := public.club_sync_points(p_customer);
  return query select v_added,v_new,v_exp;
end;
$$;

-- Riscatto: solo multipli di 50 punti; 50 punti = 5 EUR.
create or replace function public.club_admin_redeem_discount(p_customer uuid, p_points integer)
returns table(points_used integer, discount_eur numeric, new_points integer)
language plpgsql
security definer
set search_path = public
as $$
declare v_available integer; v_discount numeric; v_new integer;
begin
  if not public.club_admin_allowed() then raise exception 'FORBIDDEN' using errcode='P0001'; end if;
  if p_points is null or p_points < 50 or mod(p_points,50) <> 0 then raise exception 'INVALID_REDEMPTION' using errcode='P0001'; end if;
  v_available := public.club_sync_points(p_customer);
  if v_available < p_points then raise exception 'INSUFFICIENT_POINTS' using errcode='P0001'; end if;
  v_discount := p_points / 10.0;
  insert into public.points_transactions(customer_id,points,amount_eur,description,expires_at)
  values(p_customer,-p_points,null,'Sconto Club € '||to_char(v_discount,'FM999999990.00'),null);
  v_new := public.club_sync_points(p_customer);
  return query select p_points,v_discount,v_new;
end;
$$;

-- Dati cliente: sincronizza automaticamente il saldo e mostra la prossima scadenza.
create or replace function public.club_get(p_token uuid)
returns table(id uuid, member_code text, name text, points integer, expiring_points integer, next_expiry timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_points integer;
begin
  select c.id into v_id from public.customers c where c.client_token=p_token and c.active=true limit 1;
  if v_id is null then return; end if;
  v_points := public.club_sync_points(v_id);
  return query
  select c.id,c.member_code,c.name,v_points,
    coalesce((select sum(t.points)::integer from public.points_transactions t where t.customer_id=v_id and t.points>0 and t.expires_at>now() and t.expires_at<=now()+interval '15 days'),0),
    (select min(t.expires_at) from public.points_transactions t where t.customer_id=v_id and t.points>0 and t.expires_at>now())
  from public.customers c where c.id=v_id;
end;
$$;

-- Ricerca admin con saldo sincronizzato.
create or replace function public.club_admin_search(p_query text default '')
returns table(id uuid, member_code text, name text, phone text, points integer, active boolean)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.club_admin_allowed() then raise exception 'FORBIDDEN' using errcode='P0001'; end if;
  update public.customers c set points=public.club_available_points(c.id);
  return query select c.id,c.member_code,c.name,c.phone,c.points,c.active
  from public.customers c
  where nullif(trim(p_query),'') is null or c.name ilike '%'||trim(p_query)||'%' or c.phone ilike '%'||trim(p_query)||'%' or c.member_code ilike '%'||trim(p_query)||'%'
  order by c.name limit 50;
end;
$$;

revoke all on function public.club_available_points(uuid) from public;
revoke all on function public.club_sync_points(uuid) from public;
revoke all on function public.club_admin_add_purchase(uuid,numeric) from public;
revoke all on function public.club_admin_redeem_discount(uuid,integer) from public;

grant execute on function public.club_get(uuid) to anon,authenticated;
grant execute on function public.club_admin_add_purchase(uuid,numeric) to authenticated;
grant execute on function public.club_admin_redeem_discount(uuid,integer) to authenticated;
grant execute on function public.club_admin_search(text) to authenticated;
