-- DEVELOPMENT ONLY: Petal Quest Dev hijtwgugzzpjjkuutyfy.
-- Initial Phase7 upgrade must already exist. Installs the expiry forward repair
-- and records owner approval: pain7-10, today's saved entries only, exact text.
-- Enables queuing only; worker/secrets/schedule/permission still required.
begin;
create or replace function petal_private.claim_high_pain_push(p_limit integer default 20) returns jsonb
language plpgsql security definer set search_path='' as $$
declare q petal_private.health_alert_recipients%rowtype; lease uuid; payload jsonb; deliveries jsonb:='[]'::jsonb; approved_text text;
begin
 select push_text into approved_text from petal_private.health_checkin_policy where singleton and include_backdated is not null;
 if approved_text is null then return jsonb_build_object('deliveries',deliveries); end if;
 for q in select r.* from petal_private.health_alert_recipients r
 join public.health_installations i on i.installation_id=r.installation_id and i.user_id=r.target_user_id and i.enrollment_generation=r.enrollment_generation and i.family_id=r.family_id
 where ((select include_backdated from petal_private.health_checkin_policy where singleton) or r.local_date=(clock_timestamp() at time zone 'America/Costa_Rica')::date) and r.delivered_at is null and (r.lease_until is null or r.lease_until<=clock_timestamp()) and r.local_date is not null
 and exists(select 1 from public.memberships p where p.family_id=r.family_id and p.user_id=r.recipient_user_id and p.role='parent' and p.active)
 and exists(select 1 from public.memberships t where t.family_id=i.family_id and t.user_id=i.user_id and t.actor_id=i.teen_id and t.role='teen' and t.active)
 and exists(select 1 from public.device_registrations d where d.family_id=r.family_id and d.user_id=r.recipient_user_id)
 order by r.created_at,r.id limit greatest(1,least(coalesce(p_limit,20),100)) for update of r skip locked
 loop
 lease:=gen_random_uuid();
 update petal_private.health_alert_recipients set lease_id=lease,lease_until=clock_timestamp()+interval '5 minutes',attempts=attempts+1 where id=q.id;
 select coalesce(jsonb_agg(d.push_token),'[]'::jsonb) into payload from public.device_registrations d
 where d.family_id=q.family_id and d.user_id=q.recipient_user_id
 and exists(select 1 from public.memberships p where p.family_id=d.family_id and p.user_id=d.user_id and p.role='parent' and p.active);
 deliveries:=deliveries||jsonb_build_array(jsonb_build_object('delivery_id',q.id,'lease_id',lease,'recipient_user_id',q.recipient_user_id,'local_date',q.local_date,'tokens',payload,'push_text',approved_text));
 end loop;
 return jsonb_build_object('deliveries',deliveries);
end $$;
update petal_private.health_checkin_policy
set include_backdated=false, push_text='High pain levels today - please check in'
where singleton;
notify pgrst, 'reload schema';
commit;
select include_backdated,push_text from petal_private.health_checkin_policy where singleton;
