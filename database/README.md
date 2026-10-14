# NOVA — база данных

Схема установлена в Supabase 14 октября 2026 года. Фронтенд index.html пока остаётся локальным демо: создание базы само по себе не подключает формы и кнопки приложения.

## Что установлено

23 таблицы в public, RLS на каждой, приватная таблица ролей private.app_admins, три закрытых бакета Storage, подписки Realtime на 12 таблиц.

- Аккаунт: profiles, user_settings. Профиль и настройки создаются автоматически триггером auth.users. Никаких демонстрационных чатов. username уникален без учёта регистра.
- Переписка: nova_groups (kind personal/group/channel), group_members, messages, message_reactions. Пара пользователей получает один личный диалог. Роли owner/admin/member. В канале пишут только owner/admin. Есть ответы, редактирование, client_id для повторных запросов, типы voice/round/image/video/file.
- Соцсеть: posts, post_likes, post_comments, user_follows, follow_requests, user_interests. Закрытые профили требуют одобрения подписки. Лента учитывает членство в каналах и подписки; рекомендации по совпадению topics включаются отдельно и соблюдают приватность.
- Медиа: stories, story_views, clips, clip_likes. Истёкшие сторис скрываются от зрителей через RLS; физического удаления медиа по расписанию пока нет.
- Остальное: user_blocks, close_friends, favorites, notifications, reports, live_streams, nova_schema_versions. Уведомления в базе создаются для новых сообщений с учётом mute и настроек. Это не браузерный push.

## Миграция

20261014_nova_v1.sql — однократное расширение существовавшей черновой схемы NOVA. Она УЖЕ выполнена в проекте. Не запускать повторно и не использовать как bootstrap пустого проекта: нужны прежние восемь таблиц и групповые функции. Версия хранится в nova_schema_versions. Дальнейшие изменения оформлять отдельными нумерованными миграциями.

Миграция заменяет прежние permissive-политики public итоговыми правилами, но не удаляет данные. Клиентские права ограничены также на уровне отдельных колонок: нельзя изменить sender_id сообщения, владельца группы или свою роль. Приватные таблицы не доступны через клиентский ключ.

## Подключение index.html

Использовать supabase-js v2 с Project URL и публичным publishable/anon key, Supabase Auth и сессией пользователя. Нельзя добавлять service_role, секретный ключ или пароль базы в HTML.

Почта, телефон, пароль, подтверждения и MFA относятся к Supabase Auth, а не к profiles. Для смены email/телефона нужны Auth updateUser и подтверждение. SMS-вход требует подключения SMS-провайдера; рабочие почтовые доставки требуют проверки SMTP и лимитов. Эти провайдеры пока не настраивались.

Настройки темы/уведомлений хранить в user_settings. reduced_motion, font_size, read_receipts, last_seen_visibility и message_previews должен учитывать клиент; поля настроек сами не реализуют интерфейс и присутствие. Ограничение allow_messages проверяется RPC открытия личного диалога. Блокировка проверяется базой при отправке в личный диалог.

## Основные RPC

| RPC | Аргументы | Назначение |
|---|---|---|
| nova_create_chat | p_kind: group/channel, p_name, p_private | Создание чата и owner атомарно |
| nova_create_group | p_name, p_is_private | Совместимость с прежними группами |
| nova_open_direct | p_user: UUID | Открыть единственный личный диалог пары |
| nova_join_group | p_invite_code | Присоединиться по приглашению |
| nova_subscribe | p_channel: UUID | Подписка на открытый канал |
| nova_leave_group | p_group_id | Выход; владелец сначала передаёт права |
| nova_transfer_ownership | p_group_id, p_new_owner_id | Передача владельцем прав участнику |
| nova_manage_member | p_group, p_user, p_role: admin/member/remove | Управление владельцем |
| nova_follow | p_target | Подписка либо запрос закрытому профилю |
| nova_accept_follow | p_user | Принять запрос в собственный профиль |
| nova_feed | p_before, p_limit, p_recommend | Лента под RLS, до 100 записей |

Прямой insert/update ролей group_members запрещён. Название личного чата формирует интерфейс по профилю собеседника; сохранённое имя контейнера — «Личный диалог». profiles не содержит email/телефон. Базовые имя, username, bio и аватар доступны вошедшим пользователям; is_private закрывает публикации профиля.

Сообщение: insert messages с group_id, sender_id равным текущему auth.uid(), body и постоянным client_id UUID на одну попытку отправки. Для медиа добавить attachment_path, attachment_type (image/video/audio/file), message_kind (voice/round и т.д.). body может быть пустым при наличии вложения. reply_to должен принадлежать тому же чату. Для отображения авторов отдельно запрашивать profiles по их ID.

Realtime включён для messages, group_members, nova_groups, message_reactions, posts, post_likes, post_comments, stories, story_views, clips, clip_likes, notifications. Подписываться после входа с фильтром по нужной сущности. После переподключения перечитывать данные из БД. Удаления обрабатывать перечитыванием; не ожидать полного старого текста в DELETE-событии.

## Storage

Все бакеты private. Использовать download либо короткоживущие signed URL; не getPublicUrl. Выданный signed URL действует до истечения срока, поэтому рекомендуемый срок — 60 секунд, а не часы. Сохранять object path, а не временный URL. Загрузка — с уникальным UUID именем, upsert:false.

| Бакет | Путь | Лимит | Доступ |
|---|---|---|---|
| nova-avatars | USER_UUID/FILE_UUID.webp | 10 MiB | Чтение после входа; запись/удаление своего пути |
| nova-chat-media | GROUP_UUID/USER_UUID/FILE_UUID.ext | 50 MiB | Чтение участникам; загрузка с правом публикации |
| nova-social-media | USER_UUID/FILE_UUID.ext | 50 MiB | Владелец или зритель доступной публикации/сторис/клипа |

Для соцмедиа сначала загрузить файл, затем сохранить media_path в posts/stories/clips. Сторонний пользователь не может читать непривязанный файл. Истечение сторис закрывает доступ через RLS, но уже выданная ссылка живёт до своего TTL. Загрузка и проверка бинарных файлов, запись микрофона/камеры и воспроизведение ещё требуют подключения интерфейса.

## Администрирование и эфиры

private.app_admins пока пустая. Никто не получает роль автоматически, в том числе по metadata или email. Назначать владельца можно только после регистрации его аккаунта NOVA и проверки UUID, отдельной операцией в SQL Editor. Админ-панель не создана; роль пока даёт только модерацию reports и не открывает чужую переписку.

live_streams хранит метаданные и playback_url; он не транслирует видео. Для эфиров/звонков потребуется отдельная WebRTC/стриминговая инфраструктура.

## Проверки

Сценарии ниже прошли в SQL Editor с ролью authenticated и подменой JWT sub для трёх тестовых UUID, затем выполнен ROLLBACK. Проверены создание профилей/настроек, чаты, канал, подписки/лента, закрытый профиль, блокировки, уведомления, Storage RLS, запрет повышения роли и доступа anon. Это проверки БД, а не сквозные тесты входа по email и загрузки реальных файлов через браузер.

Запускать на пустом тестовом проекте с установленной схемой: проверки количества строк намеренно предполагают отсутствие других пользователей. Не удалять реальные данные ради этих проверок.


```sql
begin;
insert into auth.users(id,aud,role,email,raw_user_meta_data) values('11111111-1111-4111-8111-111111111111','authenticated','authenticated','nova-test-a@example.invalid','{}'),('22222222-2222-4222-8222-222222222222','authenticated','authenticated','nova-test-b@example.invalid','{}'),('33333333-3333-4333-8333-333333333333','authenticated','authenticated','nova-test-c@example.invalid','{}');
do $$begin assert (select count(*)=3 from public.profiles),'Profile bootstrap';assert (select count(*)=3 from public.user_settings),'Settings bootstrap';assert not exists(select 1 from pg_tables t join pg_class c on c.relname=t.tablename join pg_namespace n on n.oid=c.relnamespace and n.nspname=t.schemaname where t.schemaname='public' and not c.relrowsecurity),'RLS missing';assert (select count(*)=3 from storage.buckets where id like 'nova-%' and not public),'Private buckets';end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('nova.test.group',public.nova_create_group('Test group',true)::text,true);
select set_config('nova.test.invite',(select invite_code from public.nova_groups where id=current_setting('nova.test.group')::uuid),true);
select set_config('nova.test.channel',public.nova_create_chat('channel','Test channel',false)::text,true);
select set_config('nova.test.direct',public.nova_open_direct('22222222-2222-4222-8222-222222222222')::text,true);
insert into public.messages(id,group_id,sender_id,body) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',current_setting('nova.test.group')::uuid,auth.uid(),'Secret group message');
insert into public.posts(id,author_id,channel_id,body) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab',auth.uid(),current_setting('nova.test.channel')::uuid,'Channel post');
insert into public.clips(id,user_id,video_url,visibility) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaac',auth.uid(),'test.mp4','private'),('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaad',auth.uid(),'public.mp4','public');
insert into storage.objects(bucket_id,name) values('nova-chat-media',current_setting('nova.test.group')||'/'||auth.uid()::text||'/test.txt');
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$declare denied boolean=false;begin assert not exists(select 1 from public.messages),'Non-member message leak';assert (select count(*)=1 from public.clips),'Clip privacy';begin insert into public.messages(group_id,sender_id,body) values(current_setting('nova.test.group')::uuid,auth.uid(),'intrusion');exception when insufficient_privilege then denied=true;end;assert denied,'Non-member send allowed';assert not exists(select 1 from storage.objects where bucket_id='nova-chat-media'),'Non-member file leak';end$$;
select public.nova_join_group(current_setting('nova.test.invite'));
select public.nova_subscribe(current_setting('nova.test.channel')::uuid);
do $$declare denied boolean=false;begin assert (select count(*)=1 from public.messages),'Member cannot read';assert (select count(*)=1 from storage.objects where bucket_id='nova-chat-media'),'Member cannot read file';assert (select count(*)=1 from public.nova_feed()),'Feed missing subscribed post';begin insert into public.messages(group_id,sender_id,body) values(current_setting('nova.test.channel')::uuid,auth.uid(),'Channel intrusion');exception when insufficient_privilege then denied=true;end;assert denied,'Subscriber can publish';denied=false;begin update public.group_members set role='owner' where user_id=auth.uid();exception when insufficient_privilege then denied=true;end;assert denied,'Role escalation';end$$;
insert into public.messages(group_id,sender_id,body) values(current_setting('nova.test.group')::uuid,auth.uid(),'Member reply');
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
do $$begin assert (select count(*)=1 from public.notifications),'Notification missing';end$$;
insert into public.messages(group_id,sender_id,body,attachment_path,attachment_type,message_kind) values(current_setting('nova.test.group')::uuid,auth.uid(),'',current_setting('nova.test.group')||'/'||auth.uid()::text||'/voice.webm','audio','voice');
insert into storage.objects(bucket_id,name) values('nova-social-media',auth.uid()::text||'/clip.mp4');
update public.clips set media_path=auth.uid()::text||'/clip.mp4' where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaad';
insert into public.stories(user_id,media_type,text_content,audience,created_at,expires_at) values(auth.uid(),'text','expired','public',now()-interval '25 hours',now()-interval '1 hour'),(auth.uid(),'text','visible','public',now(),now()+interval '24 hours');
do $$declare denied boolean=false;begin begin insert into public.messages(group_id,sender_id,body) values(current_setting('nova.test.group')::uuid,'22222222-2222-4222-8222-222222222222','impersonation');exception when insufficient_privilege then denied=true;end;assert denied,'Sender impersonation';denied=false;begin update public.messages set group_id=current_setting('nova.test.direct')::uuid where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';exception when insufficient_privilege then denied=true;end;assert denied,'Message identity rewrite';end$$;
update public.profiles set is_private=true where id=auth.uid();
insert into public.user_blocks(user_id,blocked_id) values(auth.uid(),'22222222-2222-4222-8222-222222222222');
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$declare denied boolean=false;begin assert not exists(select 1 from public.clips),'Blocked/private clip leak';begin insert into public.messages(group_id,sender_id,body) values(current_setting('nova.test.direct')::uuid,auth.uid(),'Blocked DM');exception when raise_exception then denied=true;end;assert denied,'Block did not prevent DM';end$$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
delete from public.user_blocks where user_id=auth.uid();
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
select public.nova_follow('11111111-1111-4111-8111-111111111111');
do $$begin assert not exists(select 1 from public.user_follows),'Private follow bypass';assert (select count(*)=1 from public.follow_requests),'Follow request missing';end$$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select public.nova_accept_follow('22222222-2222-4222-8222-222222222222');
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
do $$begin assert (select count(*)=1 from public.clips),'Accepted follower visibility';assert (select count(*)=1 from public.stories),'Story expiration';assert (select count(*)=1 from storage.objects where bucket_id='nova-social-media'),'Follower social file access';end$$;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
do $$declare denied boolean=false;begin assert not exists(select 1 from public.messages),'Outsider message leak';assert not exists(select 1 from public.notifications),'Outsider notification leak';assert not exists(select 1 from storage.objects where bucket_id='nova-social-media'),'Private social media leak';assert not exists(select 1 from storage.objects where bucket_id='nova-chat-media'),'Outsider file leak';assert not exists(select 1 from public.user_settings where user_id<>auth.uid()),'Settings leak';begin perform public.nova_manage_member(current_setting('nova.test.group')::uuid,auth.uid(),'admin');exception when raise_exception then denied=true;end;assert denied,'Outsider member management';end$$;
reset role;
set local role anon;
do $$declare denied boolean=false;begin begin perform 1 from public.messages;exception when insufficient_privilege then denied=true;end;assert denied,'Anon message access';denied=false;begin perform public.nova_create_group('unauthorized',true);exception when insufficient_privilege then denied=true;end;assert denied,'Anon RPC execution';end$$;
reset role;
rollback;
select 'PASS: profiles, settings, chats, channel permissions, subscriptions/feed, private follows, blocks, notifications, Storage RLS, role isolation, anon denial. Test data rolled back.' as verification;

```
