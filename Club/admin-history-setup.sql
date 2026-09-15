-- El Capricho Club - storico movimenti per pannello admin
-- Eseguire una sola volta nel SQL Editor di Supabase.

create or replace function public.club_admin_history(
  p_customer uuid,
  p_limit integer default 30
)
returns table (
  id bigint,
  points integer,
  amount_eur numeric,
  description text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.club_admin_allowed() then
    raise exception 'FORBIDDEN' using errcode = 'P0001';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    p_limit := 30;
  end if;

  return query
  select t.id, t.points, t.amount_eur, t.description, t.created_at
  from public.points_transactions t
  where t.customer_id = p_customer
  order by t.created_at desc, t.id desc
  limit p_limit;
end;
$$;

revoke all on function public.club_admin_history(uuid, integer) from public;
grant execute on function public.club_admin_history(uuid, integer) to authenticated;
