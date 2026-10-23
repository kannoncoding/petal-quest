-- DEVELOPMENT OWNER, READ ONLY. Aggregate diagnostics for fictional Test Family 1 only.
-- Returns no tokens, user/device IDs, item text, notes, secret values or HTTP headers.
with scoped_family as (
 select id from public.families where name='Test Family 1'
), family as (
 select id from scoped_family where (select count(*) from scoped_family)=1
), item as (
 select i.id from public.school_items i join family f on f.id=i.family_id
 where i.title='Phase 10 fictional permission slip'
 order by i.created_at desc limit 1
), creation as (
 select h.id,h.family_id,h.actor_id,h.created_at from public.school_item_history h join item i on i.id=h.item_id
 where h.action='create' order by h.created_at desc limit 1
), event as (
 select e.id,e.created_at from petal_private.outbox e join creation c on c.id=e.source_id and c.family_id=e.family_id
 where e.topic='school.item_saved'
), school_notices as (
 select n.* from public.family_notices n join event e on e.id=n.source_event_id
), device_counts as (
 select d.app,count(*) registered,count(*) filter(where d.active and d.token is not null) active_with_token,
 count(*) filter(where d.active and exists(select 1 from public.memberships m where m.user_id=d.user_id and m.family_id=d.family_id and m.role=d.app and m.active)) active_matching_membership
 from petal_private.family_devices d join family f on f.id=d.family_id group by d.app
), school_delivery_counts as (
 select n.recipient_role,d.app,q.state,count(*) deliveries,
 min(q.attempts) min_attempts,max(q.attempts) max_attempts,min(q.next_attempt_at) next_attempt_utc
 from school_notices n join petal_private.family_notice_deliveries q on q.event_id=n.event_id
 join petal_private.family_devices d on d.installation_id=q.installation_id
 group by n.recipient_role,d.app,q.state
), recent_delivery_counts as (
 select d.app,e.topic,q.state,count(*) deliveries,
 count(*) filter(where n.created_at<clock_timestamp()-interval '30 minutes') older_than_30_minutes
 from petal_private.family_notice_deliveries q join public.family_notices n on n.event_id=q.event_id
 join petal_private.outbox e on e.id=n.source_event_id join petal_private.family_devices d on d.installation_id=q.installation_id
 join family f on f.id=n.family_id
 where q.next_attempt_at>clock_timestamp()-interval '2 hours' or n.created_at>clock_timestamp()-interval '2 hours'
 group by d.app,e.topic,q.state
)
select (select count(*) from scoped_family) matching_families,
 (select count(*) from item) matching_fictional_item,
 (select count(*) from creation) creation_history_rows,
 (select count(*) from event) creation_outbox_events,
 (select max(c.created_at) from creation c) creation_time_utc,
 (select coalesce(jsonb_agg(distinct m.role),'[]') from public.memberships m join creation c on c.actor_id=m.user_id and c.family_id=m.family_id where m.active) creator_current_roles,
 (select count(*) from school_notices where recipient_role='parent') school_parent_notices,
 (select count(*) from school_notices where recipient_role='teen') school_teen_notices,
 (select coalesce(jsonb_agg(to_jsonb(d)),'[]') from device_counts d) registered_devices_by_app,
 (select coalesce(jsonb_agg(to_jsonb(d)),'[]') from school_delivery_counts d) school_deliveries,
 (select coalesce(jsonb_agg(to_jsonb(d)),'[]') from recent_delivery_counts d) recent_family_deliveries;
