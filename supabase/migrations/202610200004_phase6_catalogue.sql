begin;
alter table public.task_definitions add column catalogue_key text;
create unique index unique_family_catalogue_key on public.task_definitions(family_id,catalogue_key);
-- Exact committed Phase3 duties only; NULL deadlines remain unresolved and blocked.
create function petal_private.seed_family_catalogue(p_family_id uuid) returns void
language plpgsql security definer set search_path='' as $seed$
declare item jsonb; d uuid;
begin
 for item in select value from jsonb_array_elements($catalogue$[{"key":"duty-wd-001","title":"⚠️ 1st Attitude Check","points":15,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-001","title":"⚠️ 1st Attitude Check","points":15,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-002","title":"🎒 BagPack + Lunchbag + Shower + Room @4PM","points":11,"due_time":"16:00","weekdays":[1,2,3,4,5]},{"key":"duty-we-002","title":"➡️ Room + Laundry @11AM","points":12,"due_time":"11:00","weekdays":[6,0]},{"key":"duty-wd-003","title":"📚 Homework/Study @5:30PM","points":12,"due_time":"17:30","weekdays":[1,2,3,4,5]},{"key":"duty-we-003","title":"🚿 Shower +No Mess @1PM","points":11,"due_time":"13:00","weekdays":[6,0]},{"key":"duty-wd-004","title":"⚠️ 2nd Attitude Check","points":15,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-004","title":"📚 Check HS + Other Pendings / Study @2PM","points":11,"due_time":"14:00","weekdays":[6,0]},{"key":"duty-wd-005","title":"➡️ Next Day Prepare @6PM","points":11,"due_time":"18:00","weekdays":[1,2,3,4,5]},{"key":"duty-we-005","title":"⚠️ 2nd Attitude Check @5PM","points":15,"due_time":"17:00","weekdays":[6,0]},{"key":"duty-wd-006","title":"✨ House Help","points":11,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-006","title":"✨ House Help","points":11,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-007","title":"📖 Read a new book -or- Bible","points":1,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-007","title":"📖 Read a new book -or- Bible","points":1,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-008","title":"💧 Drink 3 glasses of water (House)","points":1,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-008","title":"💧 Drink 3 glasses of water (House)","points":1,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-009","title":"📝 Research & write by hand","points":1,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-009","title":"📝 Research & write by hand","points":1,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-010","title":"🎨 Draw / Create Dance","points":1,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-010","title":"🎨 Draw / Create Dance","points":1,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-011","title":"🧹 Clean up Closet / Shoes","points":2,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-011","title":"🧹 Clean up Closet / Shoes","points":2,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-012","title":"🎁 Declutter/give away items","points":2,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-012","title":"🎁 Declutter/give away items","points":2,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-013","title":"📚 Hikari Shop","points":2,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-013","title":"📚 Hikari Shop","points":2,"due_time":null,"weekdays":[6,0]},{"key":"duty-wd-014","title":"🙂 Final Attitude Check","points":15,"due_time":null,"weekdays":[1,2,3,4,5]},{"key":"duty-we-014","title":"🙂 Final Attitude Check","points":15,"due_time":null,"weekdays":[6,0]}]$catalogue$::jsonb) loop
 insert into public.task_definitions(family_id,title,enabled,catalogue_key) values(p_family_id,item->>'title',true,item->>'key') returning id into d;
 insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source)
 values(p_family_id,d,1,(item->>'points')::integer,(item->>'due_time')::time,array(select value::integer from jsonb_array_elements_text(item->'weekdays')),true,'Phase3 App-Rule-Catalogue.draft.json; Owner-Decisions P3-003/P3-006');
 end loop;
end $seed$;
revoke execute on function petal_private.seed_family_catalogue(uuid) from public,anon,authenticated;
create or replace function petal_private.create_family(p_name text) returns jsonb
language plpgsql security definer set search_path='' as $create$
declare u uuid:=petal_private.require_identity(true); f uuid; a uuid;
begin
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.memberships where user_id=u) then raise exception 'already_joined'; end if;
 insert into public.families(name) values(trim(p_name)) returning id into f;
 insert into public.family_actors(family_id,role) values(f,'parent') returning id into a;
 insert into public.memberships(family_id,user_id,role,actor_id) values(f,u,'parent',a);
 perform petal_private.seed_family_catalogue(f);
 return jsonb_build_object('family_id',f);
end $create$;
commit;
