-- El Capricho Club - punti FIFO / scadenza 15 giorni
-- Versione di riferimento aggiornata dopo test reale 10 -> 50 -> 0 -> 20.
alter table public.points_transactions add column if not exists expires_at timestamptz;
alter table public.points_transactions add column if not exists consumed_points integer not null default 0;
update public.points_transactions set expires_at=created_at+interval '15 days' where points>0 and expires_at is null;
alter table public.points_transactions drop constraint if exists points_transactions_consumed_points_check;
alter table public.points_transactions add constraint points_transactions_consumed_points_check check(consumed_points>=0 and (points<=0 or consumed_points<=points));
create index if not exists points_transactions_customer_expiry_idx on public.points_transactions(customer_id,expires_at) where points>0;

create or replace function public.club_available_points(p_customer uuid) returns integer language sql security definer set search_path=public stable as $$
 select greatest(0,coalesce(sum(case when t.points>0 and (t.expires_at is null or t.expires_at>now()) then greatest(t.points-t.consumed_points,0) else 0 end),0)::integer) from public.points_transactions t where t.customer_id=p_customer;
$$;
create or replace function public.club_sync_points(p_customer uuid) returns integer language plpgsql security definer set search_path=public as $$ declare v integer; begin v:=public.club_available_points(p_customer); update public.customers set points=v where id=p_customer; return v; end; $$;

create or replace function public.club_admin_add_purchase(p_customer uuid,p_amount_eur numeric) returns table(points_added integer,new_points integer,expires_at timestamptz) language plpgsql security definer set search_path=public as $$
declare v_added integer;v_exp timestamptz:=now()+interval '15 days';v_new integer;begin
 if not public.club_admin_allowed() then raise exception 'FORBIDDEN' using errcode='P0001';end if;
 if p_amount_eur is null or p_amount_eur<=0 or p_amount_eur>10000 then raise exception 'INVALID_AMOUNT' using errcode='P0001';end if;
 v_added:=floor(p_amount_eur)::integer;if v_added<1 then raise exception 'AMOUNT_TOO_LOW' using errcode='P0001';end if;
 insert into public.points_transactions(customer_id,points,amount_eur,description,expires_at) values(p_customer,v_added,p_amount_eur,'Acquisto - 1 punto per euro',v_exp);
 v_new:=public.club_sync_points(p_customer);return query select v_added,v_new,v_exp;end;$$;

create or replace function public.club_admin_redeem_discount(p_customer uuid,p_points integer) returns table(points_used integer,discount_eur numeric,new_points integer) language plpgsql security definer set search_path=public as $$
declare v_available integer;v_remaining integer;v_take integer;v_discount numeric;v_new integer;r record;begin
 if not public.club_admin_allowed() then raise exception 'FORBIDDEN' using errcode='P0001';end if;
 if p_points is null or p_points<50 or mod(p_points,50)<>0 then raise exception 'INVALID_REDEMPTION' using errcode='P0001';end if;
 v_available:=public.club_sync_points(p_customer);if v_available<p_points then raise exception 'INSUFFICIENT_POINTS' using errcode='P0001';end if;v_remaining:=p_points;
 for r in select t.id,t.points,t.consumed_points from public.points_transactions t where t.customer_id=p_customer and t.points>0 and (t.expires_at is null or t.expires_at>now()) and t.consumed_points<t.points order by t.expires_at asc nulls last,t.created_at asc,t.id asc for update loop
  exit when v_remaining<=0;v_take:=least(r.points-r.consumed_points,v_remaining);update public.points_transactions set consumed_points=consumed_points+v_take where id=r.id;v_remaining:=v_remaining-v_take;
 end loop;
 if v_remaining<>0 then raise exception 'INSUFFICIENT_POINTS' using errcode='P0001';end if;
 v_discount:=p_points/10.0;insert into public.points_transactions(customer_id,points,amount_eur,description,expires_at) values(p_customer,-p_points,null,'Sconto Club € '||to_char(v_discount,'FM999999990.00'),null);
 v_new:=public.club_sync_points(p_customer);return query select p_points,v_discount,v_new;end;$$;

create or replace function public.club_get(p_token uuid) returns table(id uuid,member_code text,name text,points integer,expiring_points integer,next_expiry timestamptz) language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_points integer;begin
 select c.id into v_id from public.customers c where c.client_token=p_token and c.active=true limit 1;if v_id is null then return;end if;v_points:=public.club_sync_points(v_id);
 return query select c.id,c.member_code,c.name,v_points,coalesce((select sum(greatest(t.points-t.consumed_points,0))::integer from public.points_transactions t where t.customer_id=v_id and t.points>0 and t.expires_at>now() and t.expires_at<=now()+interval '15 days' and t.consumed_points<t.points),0),(select min(t.expires_at) from public.points_transactions t where t.customer_id=v_id and t.points>0 and t.expires_at>now() and t.consumed_points<t.points) from public.customers c where c.id=v_id;end;$$;

revoke all on function public.club_available_points(uuid) from public;revoke all on function public.club_sync_points(uuid) from public;revoke all on function public.club_admin_add_purchase(uuid,numeric) from public;revoke all on function public.club_admin_redeem_discount(uuid,integer) from public;
grant execute on function public.club_get(uuid) to anon,authenticated;grant execute on function public.club_admin_add_purchase(uuid,numeric) to authenticated;grant execute on function public.club_admin_redeem_discount(uuid,integer) to authenticated;
notify pgrst,'reload schema';