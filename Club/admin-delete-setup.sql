-- El Capricho Club - eliminazione cliente dal pannello Admin
-- Eseguire una sola volta nel SQL Editor di Supabase.

create or replace function public.club_admin_delete_customer(p_customer uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.club_admin_allowed() then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.customers where id = p_customer) then
    raise exception 'CUSTOMER_NOT_FOUND' using errcode = 'P0001';
  end if;

  delete from public.redemptions where customer_id = p_customer;
  delete from public.points_transactions where customer_id = p_customer;
  delete from public.customers where id = p_customer;

  return true;
end;
$$;

revoke all on function public.club_admin_delete_customer(uuid) from public;
grant execute on function public.club_admin_delete_customer(uuid) to authenticated;