-- El Capricho Club - recupero sicuro tessera + eliminazione cliente + bonus 15 giorni
-- Eseguire nel SQL Editor di Supabase.

create extension if not exists pgcrypto;

alter table public.customers add column if not exists recovery_code_hash text;
alter table public.customers add column if not exists recovery_code_expires_at timestamptz;

-- I nuovi bonus di benvenuto scadono come gli altri punti.
create or replace function public.club_register(p_name text, p_phone text)
returns table (id uuid, member_code text, name text, points integer, client_token uuid)
language plpgsql security definer set search_path=public
as $$
declare v_customer public.customers%rowtype;
begin
  if nullif(trim(p_name),'') is null or char_length(trim(p_name))>120 then raise exception 'INVALID_NAME' using errcode='P0001'; end if;
  if nullif(trim(p_phone),'') is null or char_length(trim(p_phone))>40 then raise exception 'INVALID_PHONE' using errcode='P0001'; end if;
  insert into public.customers(name,phone) values(trim(p_name),trim(p_phone)) returning * into v_customer;
  insert into public.points_transactions(customer_id,points,amount_eur,description,expires_at)
  values(v_customer.id,10,null,'Bonus bienvenida',now()+interval '15 days');
  return query select v_customer.id,v_customer.member_code,v_customer.name,v_customer.points,v_customer.client_token;
exception when unique_violation then raise exception 'PHONE_EXISTS' using errcode='P0001';
end;$$;

-- L'admin genera un codice monouso di 6 cifre, valido 10 minuti.
create or replace function public.club_admin_create_recovery(p_customer uuid)
returns text
language plpgsql security definer set search_path=public
as $$
declare v_code text;
begin
  if not public.club_admin_allowed() then raise exception 'FORBIDDEN' using errcode='P0001'; end if;
  if not exists(select 1 from public.customers where id=p_customer) then raise exception 'CUSTOMER_NOT_FOUND' using errcode='P0001'; end if;
  v_code:=lpad((floor(random()*1000000))::integer::text,6,'0');
  update public.customers set recovery_code_hash=encode(digest(v_code,'sha256'),'hex'),recovery_code_expires_at=now()+interval '10 minutes' where id=p_customer;
  return v_code;
end;$$;

-- Il cliente recupera la tessera con telefono + codice ricevuto in cassa.
create or replace function public.club_recover(p_phone text,p_code text)
returns table(id uuid,member_code text,name text,points integer,client_token uuid)
language plpgsql security definer set search_path=public
as $$
declare v public.customers%rowtype; v_new_token uuid;
begin
  select * into v from public.customers where phone=trim(p_phone) and active=true limit 1;
  if v.id is null or v.recovery_code_hash is null or v.recovery_code_expires_at<now() or v.recovery_code_hash<>encode(digest(trim(p_code),'sha256'),'hex') then
    raise exception 'INVALID_RECOVERY' using errcode='P0001';
  end if;
  v_new_token:=gen_random_uuid();
  update public.customers set client_token=v_new_token,recovery_code_hash=null,recovery_code_expires_at=null where customers.id=v.id;
  return query select v.id,v.member_code,v.name,public.club_available_points(v.id),v_new_token;
end;$$;

-- Eliminazione completa, solo admin.
create or replace function public.club_admin_delete_customer(p_customer uuid)
returns boolean
language plpgsql security definer set search_path=public
as $$
begin
  if not public.club_admin_allowed() then raise exception 'FORBIDDEN' using errcode='P0001'; end if;
  if not exists(select 1 from public.customers where id=p_customer) then raise exception 'CUSTOMER_NOT_FOUND' using errcode='P0001'; end if;
  delete from public.redemptions where customer_id=p_customer;
  delete from public.points_transactions where customer_id=p_customer;
  delete from public.customers where id=p_customer;
  return true;
end;$$;

revoke all on function public.club_admin_create_recovery(uuid) from public;
revoke all on function public.club_recover(text,text) from public;
revoke all on function public.club_admin_delete_customer(uuid) from public;
grant execute on function public.club_admin_create_recovery(uuid) to authenticated;
grant execute on function public.club_recover(text,text) to anon,authenticated;
grant execute on function public.club_admin_delete_customer(uuid) to authenticated;