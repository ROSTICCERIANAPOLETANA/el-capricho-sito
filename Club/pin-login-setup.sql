-- El Capricho Club - accesso autonomo cliente con telefono + PIN
-- Eseguire nel SQL Editor di Supabase.
create extension if not exists pgcrypto;
alter table public.customers add column if not exists pin_hash text;

create or replace function public.club_set_pin(p_token uuid,p_pin text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if p_pin !~ '^[0-9]{4}$' then raise exception 'INVALID_PIN' using errcode='P0001'; end if;
 update public.customers set pin_hash=crypt(p_pin,gen_salt('bf')) where client_token=p_token and active=true;
 if not found then raise exception 'INVALID_TOKEN' using errcode='P0001'; end if;
 return true;
end;$$;

create or replace function public.club_login(p_phone text,p_pin text)
returns table(id uuid,member_code text,name text,points integer,client_token uuid)
language plpgsql security definer set search_path=public as $$
declare v public.customers%rowtype;
begin
 if p_pin !~ '^[0-9]{4}$' then raise exception 'INVALID_LOGIN' using errcode='P0001'; end if;
 select * into v from public.customers c where trim(c.phone)=trim(p_phone) and c.active=true limit 1;
 if v.id is null or v.pin_hash is null or v.pin_hash<>crypt(p_pin,v.pin_hash) then raise exception 'INVALID_LOGIN' using errcode='P0001'; end if;
 update public.customers set client_token=gen_random_uuid() where id=v.id returning * into v;
 return query select v.id,v.member_code,v.name,public.club_available_points(v.id),v.client_token;
end;$$;

create or replace function public.club_register_pin(p_name text,p_phone text,p_pin text)
returns table(id uuid,member_code text,name text,points integer,client_token uuid)
language plpgsql security definer set search_path=public as $$
declare v public.customers%rowtype;
begin
 if nullif(trim(p_name),'') is null or char_length(trim(p_name))>120 then raise exception 'INVALID_NAME' using errcode='P0001'; end if;
 if nullif(trim(p_phone),'') is null or char_length(trim(p_phone))>40 then raise exception 'INVALID_PHONE' using errcode='P0001'; end if;
 if p_pin !~ '^[0-9]{4}$' then raise exception 'INVALID_PIN' using errcode='P0001'; end if;
 insert into public.customers(name,phone,pin_hash) values(trim(p_name),trim(p_phone),crypt(p_pin,gen_salt('bf'))) returning * into v;
 insert into public.points_transactions(customer_id,points,amount_eur,description,expires_at) values(v.id,10,null,'Bonus bienvenida',now()+interval '15 days');
 perform public.club_sync_points(v.id);
 return query select v.id,v.member_code,v.name,public.club_available_points(v.id),v.client_token;
exception when unique_violation then raise exception 'PHONE_EXISTS' using errcode='P0001';
end;$$;

revoke all on function public.club_set_pin(uuid,text) from public;
revoke all on function public.club_login(text,text) from public;
revoke all on function public.club_register_pin(text,text,text) from public;
grant execute on function public.club_set_pin(uuid,text) to anon,authenticated;
grant execute on function public.club_login(text,text) to anon,authenticated;
grant execute on function public.club_register_pin(text,text,text) to anon,authenticated;