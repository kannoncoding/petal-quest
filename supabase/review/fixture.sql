-- MANUAL REVIEW FIXTURE ONLY. Synthetic tasks are NOT the approved production catalog.
-- Run only in a disposable LOCAL Supabase database after all four migrations.
-- This writes synthetic Auth rows, never contact real Auth services or a hosted project.
begin;
insert into auth.users(id,aud,role,is_anonymous) values
 ('10000000-0000-0000-0000-000000000001','authenticated','authenticated',false),
 ('10000000-0000-0000-0000-000000000002','authenticated','authenticated',false),
 ('10000000-0000-0000-0000-000000000003','authenticated','authenticated',true),
 ('20000000-0000-0000-0000-000000000001','authenticated','authenticated',false),
 ('20000000-0000-0000-0000-000000000003','authenticated','authenticated',true);
insert into public.families(id,name) values
 ('10000000-0000-0000-0000-000000000000','Synthetic family A'),
 ('20000000-0000-0000-0000-000000000000','Synthetic family B');
insert into public.family_actors(id,family_id,role) values
 ('11000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000000','parent'),
 ('11000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000000','parent'),
 ('11000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000000','teen'),
 ('22000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000000','parent'),
 ('22000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000000','teen');
insert into public.memberships(family_id,user_id,actor_id,role)
 select a.family_id,case a.id
 when '11000000-0000-0000-0000-000000000001'::uuid then '10000000-0000-0000-0000-000000000001'::uuid
 when '11000000-0000-0000-0000-000000000002'::uuid then '10000000-0000-0000-0000-000000000002'::uuid
 when '11000000-0000-0000-0000-000000000003'::uuid then '10000000-0000-0000-0000-000000000003'::uuid
 when '22000000-0000-0000-0000-000000000001'::uuid then '20000000-0000-0000-0000-000000000001'::uuid
 else '20000000-0000-0000-0000-000000000003'::uuid end,a.id,a.role
 from public.family_actors a where a.family_id in ('10000000-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000000');
insert into public.task_definitions(id,family_id,title,enabled) values
 ('13000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000000','SYNTHETIC review task A',true),
 ('23000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000000','SYNTHETIC review task B',true);
insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source)
 select family_id,id,1,10,'23:59:59',array[0,1,2,3,4,5,6],true,'SYNTHETIC LOCAL REVIEW ONLY'
 from public.task_definitions where id in ('13000000-0000-0000-0000-000000000001','23000000-0000-0000-0000-000000000001');
commit;

