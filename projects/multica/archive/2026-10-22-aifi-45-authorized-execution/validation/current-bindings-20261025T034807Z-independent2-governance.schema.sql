--
-- PostgreSQL database dump
--

\restrict d7gEuzej9v7m7C6Tu1qkZhkj03lHN8RxQVa6znKBppwoVi7DgGGYgfQgNudouaz

-- Dumped from database version 17.10 (Debian 17.10-1.pgdg12+1)
-- Dumped by pg_dump version 17.10 (Debian 17.10-1.pgdg12+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: capture_attachment_wakeup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.capture_attachment_wakeup() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE before_row jsonb; after_row jsonb; row_data jsonb; before_target uuid; after_target uuid;
 target_type text; source_id uuid; source_agent uuid; owner_issue uuid; event_type text;
BEGIN
 IF TG_OP<>'INSERT' THEN before_row:=to_jsonb(OLD); before_target:=COALESCE(OLD.comment_id,OLD.issue_id); END IF;
 IF TG_OP<>'DELETE' THEN after_row:=to_jsonb(NEW); after_target:=COALESCE(NEW.comment_id,NEW.issue_id); END IF;
 IF before_target IS NOT DISTINCT FROM after_target THEN RETURN COALESCE(NEW,OLD); END IF;
 source_id := NULLIF(current_setting('multica.source_task_id',true),'')::uuid;
 SELECT agent_id INTO source_agent FROM agent_task_queue WHERE id=source_id;
 FOR row_data,event_type IN SELECT * FROM (VALUES (before_row,'attachment.detached'),(after_row,'attachment.attached')) v(r,e)
 LOOP
  -- Source-context snapshots and chat attachments are outside this issue contract.
  IF row_data IS NULL OR row_data->>'source_context_id' IS NOT NULL OR row_data->>'chat_session_id' IS NOT NULL THEN CONTINUE; END IF;
  owner_issue := (row_data->>'issue_id')::uuid;
  target_type := CASE WHEN row_data->>'comment_id' IS NOT NULL THEN 'comment' ELSE 'issue' END;
  IF target_type='comment' THEN
   SELECT issue_id INTO owner_issue FROM comment WHERE id=(row_data->>'comment_id')::uuid AND workspace_id=(row_data->>'workspace_id')::uuid;
  END IF;
  PERFORM capture_issue_wakeup(owner_issue,event_type,gen_random_uuid()::text,source_agent,source_id,
   jsonb_build_object('attachment_id',row_data->'id','target_type',target_type,
    'target_id',COALESCE(row_data->>'comment_id',row_data->>'issue_id')));
 END LOOP;
 RETURN COALESCE(NEW,OLD);
END $$;


--
-- Name: capture_comment_wakeup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.capture_comment_wakeup() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE c comment; event_type text; source_id uuid; source_agent uuid; payload jsonb; root_id uuid;
BEGIN
 c := CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
 IF NOT EXISTS (SELECT 1 FROM issue_wakeup WHERE issue_id=c.issue_id AND enabled AND kind='event') THEN RETURN c; END IF;
 source_id := NULLIF(current_setting('multica.source_task_id',true),'')::uuid;
 IF TG_OP='INSERT' THEN
  event_type := 'comment.created';
  source_id := COALESCE(source_id,c.source_task_id);
  source_agent := CASE WHEN c.author_type='agent' THEN c.author_id END;
 ELSIF TG_OP='DELETE' THEN
  -- Pruning an existing tombstone is storage cleanup, not another deletion.
  IF OLD.deleted_at IS NOT NULL THEN RETURN OLD; END IF;
  event_type := 'comment.deleted';
 ELSIF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
  event_type := 'comment.deleted';
 ELSIF NEW.deleted_at IS NOT NULL THEN RETURN NEW;
 ELSIF OLD.resolved_at IS NULL AND NEW.resolved_at IS NOT NULL THEN event_type := 'comment.resolved';
 ELSIF OLD.resolved_at IS NOT NULL AND NEW.resolved_at IS NULL THEN event_type := 'comment.unresolved';
 ELSIF NEW.content IS DISTINCT FROM OLD.content THEN event_type := 'comment.updated';
 ELSE RETURN NEW;
 END IF;
 IF source_id IS NOT NULL THEN SELECT agent_id INTO source_agent FROM agent_task_queue WHERE id=source_id; END IF;
 -- Keep author and actor distinct: an admin editing an agent's comment is
 -- not an event produced by that agent's original run.
 IF TG_OP<>'INSERT' AND source_id IS NULL THEN
  source_agent := CASE WHEN current_setting('multica.actor_type',true)='agent' THEN NULLIF(current_setting('multica.actor_id',true),'')::uuid END;
 END IF;
 root_id := c.id;
 IF c.parent_id IS NOT NULL THEN
  WITH RECURSIVE ancestors AS (
   SELECT id,parent_id,1 AS depth FROM comment WHERE id=c.parent_id AND issue_id=c.issue_id AND workspace_id=c.workspace_id
   UNION ALL SELECT p.id,p.parent_id,a.depth+1 FROM comment p JOIN ancestors a ON p.id=a.parent_id
    WHERE p.issue_id=c.issue_id AND p.workspace_id=c.workspace_id AND a.depth<256
  ) SELECT id INTO root_id FROM ancestors ORDER BY depth DESC LIMIT 1;
 END IF;
 payload := jsonb_build_object('comment_id',c.id,'parent_comment_id',c.parent_id,'thread_id',COALESCE(root_id,c.id),
  'author_type',c.author_type,'author_id',c.author_id);
 IF TG_OP='INSERT' THEN payload := payload || jsonb_build_object('actor_type',c.author_type,'actor_id',c.author_id); END IF;
 PERFORM capture_issue_wakeup(c.issue_id,event_type,gen_random_uuid()::text,source_agent,source_id,payload);
 RETURN c;
END $$;


--
-- Name: capture_issue_collaboration_wakeup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.capture_issue_collaboration_wakeup() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE source_id uuid; source_agent uuid; fields jsonb; field_name text; event_type text;
 before_row jsonb; after_row jsonb; event_key text;
BEGIN
 -- Avoid serializing potentially large issue documents on the ordinary path.
 IF NOT EXISTS (SELECT 1 FROM issue_wakeup WHERE issue_id=NEW.id AND enabled AND kind='event') THEN RETURN NEW; END IF;
 before_row := to_jsonb(OLD); after_row := to_jsonb(NEW); event_key := gen_random_uuid()::text;
 SELECT jsonb_agg(k ORDER BY k) INTO fields FROM unnest(ARRAY[
  'title','description','status','priority','assignee_type','assignee_id','parent_issue_id','project_id',
  'due_date','start_date','stage','properties','metadata','acceptance_criteria','context_refs','triage_state']) k
 WHERE before_row->k IS DISTINCT FROM after_row->k;
 IF fields IS NULL THEN RETURN NEW; END IF;
 source_id := NULLIF(current_setting('multica.source_task_id',true),'')::uuid;
 SELECT agent_id INTO source_agent FROM agent_task_queue WHERE id=source_id;
 IF source_agent IS NULL AND current_setting('multica.actor_type',true)='agent' THEN
  source_agent := NULLIF(current_setting('multica.actor_id',true),'')::uuid;
 END IF;
 PERFORM capture_issue_wakeup(NEW.id,'issue.updated',event_key||':updated',source_agent,source_id,jsonb_build_object('changed_fields',fields));
 FOR field_name,event_type IN SELECT * FROM (VALUES
  ('status','issue.status_changed'),('assignee_id','issue.assignee_changed'),
  ('parent_issue_id','issue.parent_changed'),('project_id','issue.project_changed'),
  ('properties','issue.properties_changed'),('metadata','issue.metadata_changed')) v(f,e)
 LOOP
  IF fields ? field_name OR (field_name='assignee_id' AND fields ? 'assignee_type') THEN
   PERFORM capture_issue_wakeup(NEW.id,event_type,event_key||':'||field_name,source_agent,source_id,
    CASE WHEN field_name IN ('metadata','properties') THEN
     jsonb_build_object('changed_fields',(SELECT jsonb_agg(k ORDER BY k) FROM
      (SELECT jsonb_object_keys(before_row->field_name) k UNION SELECT jsonb_object_keys(after_row->field_name)) keys
      WHERE (before_row->field_name)->k IS DISTINCT FROM (after_row->field_name)->k))
    WHEN field_name='status' THEN jsonb_build_object('previous_status',OLD.status,'status',NEW.status,
     'previous_category',(SELECT category FROM issue_status WHERE workspace_id=OLD.workspace_id AND key=OLD.status),
     'category',(SELECT category FROM issue_status WHERE workspace_id=NEW.workspace_id AND key=NEW.status))
    WHEN field_name='assignee_id' THEN jsonb_build_object('previous_assignee_id',OLD.assignee_id,'assignee_id',NEW.assignee_id,
     'previous_assignee_type',OLD.assignee_type,'assignee_type',NEW.assignee_type)
    ELSE jsonb_build_object('previous_'||field_name,before_row->field_name,field_name,after_row->field_name) END);
  END IF;
 END LOOP;
 RETURN NEW;
END $$;


--
-- Name: capture_issue_label_wakeup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.capture_issue_label_wakeup() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE row_data jsonb := CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END; source_id uuid; source_agent uuid;
BEGIN
 source_id := NULLIF(current_setting('multica.source_task_id',true),'')::uuid;
 SELECT agent_id INTO source_agent FROM agent_task_queue WHERE id=source_id;
 PERFORM capture_issue_wakeup((row_data->>'issue_id')::uuid,'issue.labels_changed',gen_random_uuid()::text,source_agent,source_id,
  jsonb_build_object('label_id',row_data->'label_id','action',CASE WHEN TG_OP='INSERT' THEN 'added' ELSE 'removed' END));
 RETURN COALESCE(NEW,OLD);
END $$;


--
-- Name: capture_issue_wakeup(uuid, text, text, uuid, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.capture_issue_wakeup(p_issue uuid, p_type text, p_key text, p_agent uuid, p_task uuid, p_payload jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE w issue_wakeup; owner_workspace uuid; evidence jsonb; violated_constraint text;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM issue_wakeup WHERE issue_id=p_issue AND enabled AND kind='event' AND p_type=ANY(event_types)) THEN RETURN; END IF;
 IF p_agent IS NULL AND current_setting('multica.actor_type',true)='agent' THEN
  p_agent := NULLIF(current_setting('multica.actor_id',true),'')::uuid;
 END IF;
 SELECT i.workspace_id INTO owner_workspace FROM issue i
 WHERE i.id=p_issue AND i.status NOT IN ('done','cancelled') AND NOT EXISTS
 (SELECT 1 FROM issue_status s WHERE s.workspace_id=i.workspace_id AND s.key=i.status AND s.category IN ('done','closed'));
 IF owner_workspace IS NULL THEN RETURN; END IF;
 evidence := jsonb_build_object('event_id',p_key,'event_type',p_type,'version',1,
  'occurred_at',clock_timestamp(),'workspace_id',owner_workspace,'issue_id',p_issue,
  'source_task_id',p_task,'agent_id',p_agent,
  'actor_type',COALESCE(NULLIF(current_setting('multica.actor_type',true),''),CASE WHEN p_agent IS NOT NULL THEN 'agent' ELSE 'system' END),
  'actor_id',COALESCE(NULLIF(current_setting('multica.actor_id',true),''),p_agent::text)) || p_payload;
 FOR w IN SELECT * FROM issue_wakeup WHERE issue_id=p_issue AND workspace_id=owner_workspace AND enabled AND kind='event'
   AND p_type=ANY(event_types)
   AND (filter_actor_type IS NULL OR (filter_actor_type=evidence->>'actor_type' AND filter_actor_id::text=evidence->>'actor_id'))
   AND (filter_agent_id IS NULL OR filter_agent_id=p_agent)
   AND (filter_task_id IS NULL OR filter_task_id=p_task)
   AND (p_task IS NULL OR source_task_id IS DISTINCT FROM p_task)
   AND NOT EXISTS (SELECT 1 FROM agent_task_queue t WHERE t.id=p_task AND t.context->>'wakeup_id'=issue_wakeup.id::text)
   AND (p_type NOT LIKE 'issue.%' OR agent_id IS NULL OR agent_id IS DISTINCT FROM NULLIF(current_setting('multica.handed_to_agent',true),'')::uuid)
   ORDER BY id
 LOOP
  -- One pending notification per event type. Preserve the first key for
  -- duplicate suppression and the latest source reference for state reads.
  BEGIN
   INSERT INTO issue_wakeup_receipt(id,wakeup_id,revision,event_key,event_type,payload,coalesce_key)
    VALUES(gen_random_uuid(),w.id,w.revision,p_key,p_type,
     evidence || jsonb_build_object('coalesced_count',1,'first_occurred_at',evidence->'occurred_at'),p_type)
   ON CONFLICT(wakeup_id,revision,coalesce_key) WHERE processed_at IS NULL AND coalesce_key IS NOT NULL
   -- Rotate the receipt identity on merge. An older dispatcher that read
   -- without FOR UPDATE can only consume its observed version, leaving the
   -- replacement pending instead of silently consuming unseen evidence.
   DO UPDATE SET id=EXCLUDED.id,payload=EXCLUDED.payload || jsonb_build_object(
    'coalesced_count',COALESCE((issue_wakeup_receipt.payload->>'coalesced_count')::bigint,1)+1,
    'first_occurred_at',issue_wakeup_receipt.payload->'first_occurred_at')
   WHERE issue_wakeup_receipt.event_key<>p_key AND issue_wakeup_receipt.payload->>'event_id' IS DISTINCT FROM p_key;
  EXCEPTION WHEN unique_violation THEN
   GET STACKED DIAGNOSTICS violated_constraint = CONSTRAINT_NAME;
   -- A retained receipt already handled this exact source fact. This also
   -- fences the locked registration snapshot against terminal-task capture.
   IF violated_constraint <> 'issue_wakeup_receipt_key_idx' THEN RAISE; END IF;
  END;

 END LOOP;
END $$;


--
-- Name: capture_reaction_wakeup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.capture_reaction_wakeup() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE row_data jsonb := CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 owner_issue uuid; source_id uuid; source_agent uuid; target_type text; target_id uuid; payload jsonb;
BEGIN
 IF TG_TABLE_NAME='comment_reaction' THEN
  target_type := 'comment'; target_id := (row_data->>'comment_id')::uuid;
  SELECT issue_id INTO owner_issue FROM comment WHERE id=target_id AND workspace_id=(row_data->>'workspace_id')::uuid;
 ELSE target_type := 'issue'; target_id := (row_data->>'issue_id')::uuid; owner_issue := target_id;
 END IF;
 source_id := NULLIF(current_setting('multica.source_task_id',true),'')::uuid;
 IF source_id IS NOT NULL THEN SELECT agent_id INTO source_agent FROM agent_task_queue WHERE id=source_id;
 ELSIF TG_OP='INSERT' AND row_data->>'actor_type'='agent' THEN source_agent := (row_data->>'actor_id')::uuid;
 END IF;
 payload := jsonb_build_object('reaction_id',row_data->'id','target_type',target_type,'target_id',target_id,'emoji',row_data->'emoji',
  'reaction_actor_type',row_data->'actor_type','reaction_actor_id',row_data->'actor_id');
 IF TG_OP='INSERT' THEN payload := payload || jsonb_build_object('actor_type',row_data->'actor_type','actor_id',row_data->'actor_id'); END IF;
 PERFORM capture_issue_wakeup(owner_issue,CASE WHEN TG_OP='INSERT' THEN 'reaction.added' ELSE 'reaction.removed' END,
  gen_random_uuid()::text,source_agent,source_id,payload);
 RETURN COALESCE(NEW,OLD);
END $$;


--
-- Name: capture_task_wakeup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.capture_task_wakeup() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE event_type text; event_key text; old_status text;
BEGIN
 IF NEW.issue_id IS NULL THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' THEN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  old_status := OLD.status;
 END IF;
 event_type := CASE NEW.status WHEN 'running' THEN 'task.started' ELSE 'task.'||NEW.status END;
 IF NEW.status NOT IN ('queued','dispatched','running','deferred','waiting_local_directory','completed','failed','cancelled') THEN RETURN NEW; END IF;
 -- Terminal keys also match the locked registration check. Repeated queue /
 -- defer transitions are separate facts and must not share a lifetime key.
 event_key := CASE WHEN NEW.status IN ('completed','failed','cancelled') THEN NEW.id::text||':'||NEW.status ELSE gen_random_uuid()::text END;
 PERFORM capture_issue_wakeup(NEW.issue_id,event_type,event_key,NEW.agent_id,NEW.id,
  jsonb_build_object('task_id',NEW.id,'agent_id',NEW.agent_id,'status',NEW.status,'previous_status',old_status,
   'retry_of_task_id',NEW.retry_of_task_id,'rerun_of_task_id',NEW.rerun_of_task_id));
 RETURN NEW;
END $$;


--
-- Name: clear_runtime_mcp_overlay_on_terminal_state(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clear_runtime_mcp_overlay_on_terminal_state() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.status IN ('completed', 'failed', 'cancelled')
       AND OLD.status IS DISTINCT FROM NEW.status
       AND (NEW.runtime_mcp_overlay IS NOT NULL OR NEW.runtime_connected_apps IS NOT NULL) THEN
        NEW.runtime_mcp_overlay := NULL;
        NEW.runtime_connected_apps := NULL;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: comment_thread_root_id(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.comment_thread_root_id(comment_id uuid) RETURNS uuid
    LANGUAGE sql STABLE STRICT
    AS $$
    WITH RECURSIVE ancestors AS (
        SELECT c.id, c.parent_id, c.issue_id, ARRAY[c.id] AS path
        FROM comment c WHERE c.id = comment_id
        UNION ALL
        SELECT p.id, p.parent_id, p.issue_id, a.path || p.id
        FROM ancestors a JOIN comment p ON p.id = a.parent_id AND p.issue_id = a.issue_id
        WHERE NOT p.id = ANY(a.path)
    )
    SELECT COALESCE(
        (SELECT id FROM ancestors ORDER BY cardinality(path) DESC LIMIT 1),
        comment_id
    )
$$;


--
-- Name: enforce_channel_message_task_context_revision(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_channel_message_task_context_revision() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    task_revision BIGINT;
BEGIN
    IF OLD.task_id IS NOT NULL
       OR NEW.task_id IS NULL
       OR NEW.role <> 'user' THEN
        RETURN NEW;
    END IF;

    SELECT COALESCE(task.channel_context_revision, 1)
    INTO task_revision
    FROM agent_task_queue AS task
    WHERE task.id = NEW.task_id;

    IF task_revision IS NOT NULL
       AND COALESCE(NEW.channel_context_revision, 1) <> task_revision THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: enqueue_task_usage_hourly_dirty_for_atq(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enqueue_task_usage_hourly_dirty_for_atq() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.runtime_id IS DISTINCT FROM NEW.runtime_id
           OR OLD.issue_id IS DISTINCT FROM NEW.issue_id THEN
            -- OLD side. NULL runtime_id rows are not aggregated (no
            -- runtime → no bucket); skip those.
            IF OLD.runtime_id IS NOT NULL THEN
                INSERT INTO task_usage_hourly_dirty (
                    bucket_hour, workspace_id, runtime_id, agent_id,
                    project_id, provider, model
                )
                SELECT DISTINCT
                    task_usage_hour_bucket(tu.created_at),
                    a.workspace_id,
                    OLD.runtime_id,
                    OLD.agent_id,
                    i_old.project_id,
                    tu.provider,
                    tu.model
                  FROM task_usage tu
                  JOIN agent a ON a.id = OLD.agent_id
                  LEFT JOIN issue i_old ON i_old.id = OLD.issue_id
                 WHERE tu.task_id = OLD.id
                ON CONFLICT ON CONSTRAINT uq_task_usage_hourly_dirty_key DO UPDATE
                    SET enqueued_at = GREATEST(task_usage_hourly_dirty.enqueued_at, EXCLUDED.enqueued_at);
            END IF;

            IF NEW.runtime_id IS NOT NULL THEN
                INSERT INTO task_usage_hourly_dirty (
                    bucket_hour, workspace_id, runtime_id, agent_id,
                    project_id, provider, model
                )
                SELECT DISTINCT
                    task_usage_hour_bucket(tu.created_at),
                    a.workspace_id,
                    NEW.runtime_id,
                    NEW.agent_id,
                    i_new.project_id,
                    tu.provider,
                    tu.model
                  FROM task_usage tu
                  JOIN agent a ON a.id = NEW.agent_id
                  LEFT JOIN issue i_new ON i_new.id = NEW.issue_id
                 WHERE tu.task_id = NEW.id
                ON CONFLICT ON CONSTRAINT uq_task_usage_hourly_dirty_key DO UPDATE
                    SET enqueued_at = GREATEST(task_usage_hourly_dirty.enqueued_at, EXCLUDED.enqueued_at);
            END IF;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.runtime_id IS NOT NULL THEN
            INSERT INTO task_usage_hourly_dirty (
                bucket_hour, workspace_id, runtime_id, agent_id,
                project_id, provider, model
            )
            SELECT DISTINCT
                task_usage_hour_bucket(tu.created_at),
                a.workspace_id,
                OLD.runtime_id,
                OLD.agent_id,
                i.project_id,
                tu.provider,
                tu.model
              FROM task_usage tu
              JOIN agent a ON a.id = OLD.agent_id
              LEFT JOIN issue i ON i.id = OLD.issue_id
             WHERE tu.task_id = OLD.id
            ON CONFLICT ON CONSTRAINT uq_task_usage_hourly_dirty_key DO UPDATE
                SET enqueued_at = GREATEST(task_usage_hourly_dirty.enqueued_at, EXCLUDED.enqueued_at);
        END IF;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: enqueue_task_usage_hourly_dirty_for_issue_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enqueue_task_usage_hourly_dirty_for_issue_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO task_usage_hourly_dirty (
        bucket_hour, workspace_id, runtime_id, agent_id,
        project_id, provider, model
    )
    SELECT DISTINCT
        task_usage_hour_bucket(tu.created_at),
        OLD.workspace_id,
        atq.runtime_id,
        atq.agent_id,
        OLD.project_id,
        tu.provider,
        tu.model
      FROM agent_task_queue atq
      JOIN task_usage tu ON tu.task_id = atq.id
     WHERE atq.issue_id = OLD.id
       AND atq.runtime_id IS NOT NULL
    ON CONFLICT ON CONSTRAINT uq_task_usage_hourly_dirty_key DO UPDATE
        SET enqueued_at = GREATEST(task_usage_hourly_dirty.enqueued_at, EXCLUDED.enqueued_at);
    RETURN OLD;
END;
$$;


--
-- Name: enqueue_task_usage_hourly_dirty_for_issue_project(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enqueue_task_usage_hourly_dirty_for_issue_project() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.project_id IS DISTINCT FROM NEW.project_id THEN
        -- OLD project buckets.
        INSERT INTO task_usage_hourly_dirty (
            bucket_hour, workspace_id, runtime_id, agent_id,
            project_id, provider, model
        )
        SELECT DISTINCT
            task_usage_hour_bucket(tu.created_at),
            NEW.workspace_id,
            atq.runtime_id,
            atq.agent_id,
            OLD.project_id,
            tu.provider,
            tu.model
          FROM agent_task_queue atq
          JOIN task_usage tu ON tu.task_id = atq.id
         WHERE atq.issue_id = NEW.id
           AND atq.runtime_id IS NOT NULL
        ON CONFLICT ON CONSTRAINT uq_task_usage_hourly_dirty_key DO UPDATE
            SET enqueued_at = GREATEST(task_usage_hourly_dirty.enqueued_at, EXCLUDED.enqueued_at);

        -- NEW project buckets.
        INSERT INTO task_usage_hourly_dirty (
            bucket_hour, workspace_id, runtime_id, agent_id,
            project_id, provider, model
        )
        SELECT DISTINCT
            task_usage_hour_bucket(tu.created_at),
            NEW.workspace_id,
            atq.runtime_id,
            atq.agent_id,
            NEW.project_id,
            tu.provider,
            tu.model
          FROM agent_task_queue atq
          JOIN task_usage tu ON tu.task_id = atq.id
         WHERE atq.issue_id = NEW.id
           AND atq.runtime_id IS NOT NULL
        ON CONFLICT ON CONSTRAINT uq_task_usage_hourly_dirty_key DO UPDATE
            SET enqueued_at = GREATEST(task_usage_hourly_dirty.enqueued_at, EXCLUDED.enqueued_at);
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: enqueue_task_usage_hourly_dirty_for_tu(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enqueue_task_usage_hourly_dirty_for_tu() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO task_usage_hourly_dirty (
        bucket_hour, workspace_id, runtime_id, agent_id,
        project_id, provider, model
    )
    SELECT
        task_usage_hour_bucket(OLD.created_at),
        a.workspace_id,
        atq.runtime_id,
        atq.agent_id,
        i.project_id,
        OLD.provider,
        OLD.model
      FROM agent_task_queue atq
      JOIN agent a ON a.id = atq.agent_id
      LEFT JOIN issue i ON i.id = atq.issue_id
     WHERE atq.id = OLD.task_id
       AND atq.runtime_id IS NOT NULL
    ON CONFLICT ON CONSTRAINT uq_task_usage_hourly_dirty_key DO UPDATE
        SET enqueued_at = GREATEST(task_usage_hourly_dirty.enqueued_at, EXCLUDED.enqueued_at);
    RETURN OLD;
END;
$$;


--
-- Name: guard_issue_wakeup_capacity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_issue_wakeup_capacity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 IF NOT NEW.enabled OR NEW.system_rule IS NOT NULL THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND OLD.enabled AND OLD.issue_id=NEW.issue_id AND OLD.workspace_id=NEW.workspace_id THEN RETURN NEW; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('issue-wakeup-capacity:'||NEW.workspace_id::text,0));
 IF (SELECT count(*) FROM (SELECT 1 FROM issue_wakeup WHERE workspace_id=NEW.workspace_id AND issue_id=NEW.issue_id AND enabled AND system_rule IS NULL AND id<>NEW.id LIMIT 32) slots)>=32 THEN
  RAISE EXCEPTION 'An issue can have at most 32 enabled wakeups' USING ERRCODE='23514',CONSTRAINT='issue_wakeup_active_limit';
 END IF;
 IF (SELECT count(*) FROM (SELECT 1 FROM issue_wakeup WHERE workspace_id=NEW.workspace_id AND enabled AND system_rule IS NULL AND id<>NEW.id LIMIT 1000) slots)>=1000 THEN
  RAISE EXCEPTION 'A workspace can have at most 1000 enabled wakeups' USING ERRCODE='23514',CONSTRAINT='issue_wakeup_active_limit';
 END IF;
 RETURN NEW;
END $$;


--
-- Name: issue_effective_status(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue_effective_status(p_workspace_id uuid, p_status text) RETURNS text
    LANGUAGE sql STABLE PARALLEL SAFE
    AS $$
    SELECT CASE
        WHEN p_status IN ('backlog', 'todo', 'in_progress', 'in_review', 'done', 'blocked', 'cancelled')
            THEN p_status
        ELSE COALESCE((
            SELECT CASE s.category
                WHEN 'done' THEN 'done'
                WHEN 'closed' THEN 'cancelled'
                ELSE p_status
            END
            FROM issue_status s
            WHERE s.workspace_id = p_workspace_id AND s.key = p_status
        ), p_status)
    END
$$;


--
-- Name: issue_status_category(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue_status_category(p_category text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT CASE p_category
        WHEN 'backlog' THEN 'unstarted' WHEN 'todo' THEN 'unstarted'
        WHEN 'in_progress' THEN 'started' WHEN 'in_review' THEN 'started'
        WHEN 'blocked' THEN 'started' WHEN 'cancelled' THEN 'closed'
        ELSE p_category END
$$;


--
-- Name: lock_task_owner_rows(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lock_task_owner_rows(p_agent_id uuid, p_issue_id uuid, p_runtime_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    required int := (CASE WHEN p_agent_id IS NULL THEN 0 ELSE 1 END)
                  + (CASE WHEN p_issue_id IS NULL THEN 0 ELSE 1 END)
                  + (CASE WHEN p_runtime_id IS NULL THEN 0 ELSE 1 END);
    resolved int;
    distinct_workspaces int;
    locked int;
BEGIN
    -- A row with no owner reference at all cannot belong to any workspace.
    IF required = 0 THEN
        RETURN TRUE;
    END IF;

    WITH owners AS (
        SELECT a.workspace_id FROM agent a WHERE a.id = p_agent_id
        UNION ALL
        SELECT i.workspace_id FROM issue i WHERE i.id = p_issue_id
        UNION ALL
        SELECT r.workspace_id FROM agent_runtime r WHERE r.id = p_runtime_id
    )
    SELECT count(*), count(DISTINCT workspace_id)
    INTO resolved, distinct_workspaces
    FROM owners;

    -- An owner reference that no longer resolves means its row has been deleted —
    -- by a teardown or a merge that already committed, most likely. Refuse without
    -- leaning on the foreign key to report it.
    IF resolved <> required THEN
        RETURN FALSE;
    END IF;

    -- Step 1: the workspaces.
    WITH locked_workspaces AS (
        SELECT w.id
        FROM workspace w
        WHERE w.id IN (
            SELECT a.workspace_id FROM agent a WHERE a.id = p_agent_id
            UNION
            SELECT i.workspace_id FROM issue i WHERE i.id = p_issue_id
            UNION
            SELECT r.workspace_id FROM agent_runtime r WHERE r.id = p_runtime_id
        )
        ORDER BY w.id
        FOR KEY SHARE
    )
    SELECT count(*) INTO locked FROM locked_workspaces;

    IF locked <> distinct_workspaces THEN
        RETURN FALSE;
    END IF;

    -- Step 2: the owner rows, agent then issue then runtime. Re-checking existence
    -- here is what closes the merge window: whoever is deleting one of these rows
    -- holds FOR UPDATE on it, so this either waits for them or finds the row gone.
    locked := 0;

    IF p_agent_id IS NOT NULL THEN
        PERFORM 1 FROM agent WHERE id = p_agent_id FOR KEY SHARE;
        IF FOUND THEN locked := locked + 1; END IF;
    END IF;

    IF p_issue_id IS NOT NULL THEN
        PERFORM 1 FROM issue WHERE id = p_issue_id FOR KEY SHARE;
        IF FOUND THEN locked := locked + 1; END IF;
    END IF;

    IF p_runtime_id IS NOT NULL THEN
        PERFORM 1 FROM agent_runtime WHERE id = p_runtime_id FOR KEY SHARE;
        IF FOUND THEN locked := locked + 1; END IF;
    END IF;

    RETURN locked = required;
END;
$$;


--
-- Name: mirror_dingtalk_group_presence_bot_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mirror_dingtalk_group_presence_bot_identity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.bot_name = '' AND NEW.bot_identity_issue = '' THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM dingtalk_bot_identity identity
        WHERE identity.installation_id = NEW.installation_id
          AND identity.workspace_id = NEW.workspace_id
          AND identity.bot_name = NEW.bot_name
          AND identity.bot_identity_issue = NEW.bot_identity_issue
    ) THEN
        RETURN NEW;
    END IF;

    INSERT INTO dingtalk_bot_identity (
        workspace_id, installation_id, bot_name, bot_identity_issue
    ) VALUES (
        NEW.workspace_id, NEW.installation_id, NEW.bot_name, NEW.bot_identity_issue
    )
    ON CONFLICT (installation_id) DO UPDATE SET
        workspace_id = EXCLUDED.workspace_id,
        bot_name = CASE
            WHEN EXCLUDED.bot_name <> '' THEN EXCLUDED.bot_name
            ELSE dingtalk_bot_identity.bot_name
        END,
        bot_identity_issue = CASE
            WHEN EXCLUDED.bot_identity_issue <> '' THEN EXCLUDED.bot_identity_issue
            WHEN EXCLUDED.bot_name <> '' THEN ''
            ELSE dingtalk_bot_identity.bot_identity_issue
        END,
        updated_at = now();

    RETURN NEW;
END;
$$;


--
-- Name: mirror_legacy_dingtalk_group_route_presence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mirror_legacy_dingtalk_group_route_presence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    is_activity BOOLEAN;
BEGIN
    is_activity := TG_OP = 'INSERT';
    IF TG_OP = 'UPDATE' THEN
        is_activity := NEW.revision = OLD.revision;
    END IF;

    INSERT INTO dingtalk_group_presence (
        workspace_id,
        installation_id,
        conversation_id,
        conversation_title,
        first_seen_at,
        last_active_at,
        mention_count
    ) VALUES (
        NEW.workspace_id,
        NEW.installation_id,
        NEW.conversation_id,
        NEW.conversation_title,
        NEW.discovered_at,
        CASE WHEN is_activity THEN now() ELSE NULL END,
        CASE WHEN is_activity THEN 1 ELSE 0 END
    )
    ON CONFLICT (installation_id, conversation_id) DO UPDATE SET
        workspace_id = EXCLUDED.workspace_id,
        conversation_title = CASE
            WHEN EXCLUDED.conversation_title <> '' THEN EXCLUDED.conversation_title
            ELSE dingtalk_group_presence.conversation_title
        END,
        first_seen_at = LEAST(dingtalk_group_presence.first_seen_at, EXCLUDED.first_seen_at),
        last_active_at = CASE
            WHEN is_activity THEN now()
            ELSE dingtalk_group_presence.last_active_at
        END,
        mention_count = dingtalk_group_presence.mention_count + CASE WHEN is_activity THEN 1 ELSE 0 END,
        updated_at = now();

    RETURN NEW;
END;
$$;


--
-- Name: prune_task_usage_hourly_dirty(interval); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prune_task_usage_hourly_dirty(p_retention interval DEFAULT '7 days'::interval) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows BIGINT;
BEGIN
    DELETE FROM task_usage_hourly_dirty
     WHERE enqueued_at < now() - p_retention;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$$;


--
-- Name: record_issue_child_event(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_issue_child_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE old_closed boolean; new_closed boolean; source uuid;
BEGIN
 source := NULLIF(current_setting('multica.source_task_id',true),'')::uuid;
 IF TG_OP='INSERT' THEN
  INSERT INTO issue_child_event(workspace_id,parent_id,child_id,kind,source_task_id) VALUES(NEW.workspace_id,NEW.parent_issue_id,NEW.id,'attached',source);
  RETURN NULL;
 END IF;
 IF OLD.parent_issue_id IS DISTINCT FROM NEW.parent_issue_id THEN
  IF OLD.parent_issue_id IS NOT NULL THEN
   INSERT INTO issue_child_event(workspace_id,parent_id,child_id,kind,source_task_id) VALUES(OLD.workspace_id,OLD.parent_issue_id,OLD.id,'detached',source);
  END IF;
  IF NEW.parent_issue_id IS NOT NULL THEN
   INSERT INTO issue_child_event(workspace_id,parent_id,child_id,kind,source_task_id) VALUES(NEW.workspace_id,NEW.parent_issue_id,NEW.id,'attached',source);
  END IF;
  RETURN NULL;
 END IF;
 IF OLD.status IS DISTINCT FROM NEW.status THEN
  new_closed := NEW.status IN ('done','cancelled') OR EXISTS(SELECT 1 FROM issue_status s WHERE s.workspace_id=NEW.workspace_id AND s.key=NEW.status AND s.category IN ('done','closed'));
  old_closed := OLD.status IN ('done','cancelled') OR EXISTS(SELECT 1 FROM issue_status s WHERE s.workspace_id=OLD.workspace_id AND s.key=OLD.status AND s.category IN ('done','closed'));
  IF new_closed AND NOT old_closed THEN
   INSERT INTO issue_child_event(workspace_id,parent_id,child_id,kind,source_task_id) VALUES(NEW.workspace_id,NEW.parent_issue_id,NEW.id,'closed',source);
  ELSIF old_closed AND NOT new_closed THEN
   INSERT INTO issue_child_event(workspace_id,parent_id,child_id,kind,source_task_id) VALUES(NEW.workspace_id,NEW.parent_issue_id,NEW.id,'reopened',source);
  END IF;
 END IF;
 IF OLD.stage IS DISTINCT FROM NEW.stage THEN
  INSERT INTO issue_child_event(workspace_id,parent_id,child_id,kind,source_task_id) VALUES(NEW.workspace_id,NEW.parent_issue_id,NEW.id,'restaged',source);
 END IF;
 RETURN NULL;
END $$;


--
-- Name: record_search_index_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_search_index_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    changed_id UUID;
    changed_workspace_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        changed_id := OLD.id;
        changed_workspace_id := OLD.workspace_id;
    ELSE
        changed_id := NEW.id;
        changed_workspace_id := NEW.workspace_id;
    END IF;

    INSERT INTO search_index_change (entity_type, entity_id, workspace_id, change_xid, changed_at)
    VALUES (TG_ARGV[0], changed_id, changed_workspace_id, pg_current_xact_id(), now())
    ON CONFLICT (entity_type, entity_id) DO UPDATE
        SET workspace_id = EXCLUDED.workspace_id,
            change_xid = EXCLUDED.change_xid,
            changed_at = EXCLUDED.changed_at;
    RETURN NULL;
END
$$;


--
-- Name: rollup_task_usage_hourly(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rollup_task_usage_hourly() RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_lock_ok BOOLEAN;
    v_from    TIMESTAMPTZ;
    v_to      TIMESTAMPTZ;
    v_rows    BIGINT := 0;
BEGIN
    SELECT pg_try_advisory_xact_lock(4246) INTO v_lock_ok;
    IF NOT v_lock_ok THEN
        RETURN 0;
    END IF;

    BEGIN
        UPDATE task_usage_hourly_rollup_state
           SET last_run_started_at = now(),
               last_error          = NULL
         WHERE id = 1
        RETURNING watermark_at INTO v_from;

        -- Cap each tick at a one-day window. In steady state v_from is
        -- recent, so LEAST picks `now() - 5 min` and nothing changes. But
        -- if the worker was paused (incident, migration freeze) the
        -- watermark can fall far behind; without the cap a single catch-up
        -- tick would recompute a multi-week window in one statement while
        -- holding lock 4246, blocking every other tick. Capped, catch-up
        -- advances in bounded one-day steps over successive ticks.
        v_to := LEAST(now() - INTERVAL '5 minutes', v_from + INTERVAL '1 day');

        IF v_from < v_to THEN
            v_rows := rollup_task_usage_hourly_window(v_from, v_to);

            UPDATE task_usage_hourly_rollup_state
               SET watermark_at         = v_to,
                   last_run_finished_at = now(),
                   last_run_rows        = v_rows
             WHERE id = 1;
        ELSE
            UPDATE task_usage_hourly_rollup_state
               SET last_run_finished_at = now(),
                   last_run_rows        = 0
             WHERE id = 1;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        UPDATE task_usage_hourly_rollup_state
           SET last_error           = SQLERRM,
               last_run_finished_at = now()
         WHERE id = 1;
        RAISE;
    END;

    -- TTL prune. Idempotent, and in steady state a no-op because each tick
    -- already drains the queue. It runs under the transaction-scoped lock —
    -- see the note at the top for what that costs after a long pause.
    PERFORM prune_task_usage_hourly_dirty();
    RETURN v_rows;
END;
$$;


--
-- Name: rollup_task_usage_hourly_window(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rollup_task_usage_hourly_window(p_from timestamp with time zone, p_to timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows BIGINT;
BEGIN
    IF p_from >= p_to THEN
        RETURN 0;
    END IF;

    WITH
    dirty_from_updates AS (
        SELECT DISTINCT
            task_usage_hour_bucket(tu.created_at) AS bucket_hour,
            a.workspace_id                        AS workspace_id,
            atq.runtime_id                        AS runtime_id,
            atq.agent_id                          AS agent_id,
            i.project_id                          AS project_id,
            tu.provider                           AS provider,
            tu.model                              AS model
          FROM task_usage tu
          JOIN agent_task_queue atq ON atq.id      = tu.task_id
          JOIN agent            a   ON a.id        = atq.agent_id
          LEFT JOIN issue       i   ON i.id        = atq.issue_id
         WHERE atq.runtime_id IS NOT NULL
           AND (
                (tu.updated_at >= p_from AND tu.updated_at < p_to)
                -- Legacy updated_at-NULL rows; partial index from 078.
                OR (tu.updated_at IS NULL
                    AND tu.created_at >= p_from
                    AND tu.created_at <  p_to)
           )
    ),
    dirty_from_queue AS (
        SELECT bucket_hour, workspace_id, runtime_id, agent_id,
               project_id, provider, model
          FROM task_usage_hourly_dirty
         WHERE enqueued_at < p_to
    ),
    dirty_keys AS (
        SELECT * FROM dirty_from_updates
        UNION
        SELECT * FROM dirty_from_queue
    ),
    recomputed AS (
        SELECT
            dk.bucket_hour,
            dk.workspace_id,
            dk.runtime_id,
            dk.agent_id,
            dk.project_id,
            dk.provider,
            dk.model,
            SUM(tu.input_tokens)::bigint       AS input_tokens,
            SUM(tu.output_tokens)::bigint      AS output_tokens,
            SUM(tu.cache_read_tokens)::bigint  AS cache_read_tokens,
            SUM(tu.cache_write_tokens)::bigint AS cache_write_tokens,
            -- Authoritative half: only rows the provider priced.
            COALESCE(SUM(tu.cost_usd_ticks), 0)::bigint AS cost_usd_ticks,
            -- Estimated half: tokens from rows the provider did not price.
            COALESCE(SUM(tu.input_tokens)       FILTER (WHERE tu.cost_usd_ticks IS NULL), 0)::bigint AS uncosted_input_tokens,
            COALESCE(SUM(tu.output_tokens)      FILTER (WHERE tu.cost_usd_ticks IS NULL), 0)::bigint AS uncosted_output_tokens,
            COALESCE(SUM(tu.cache_read_tokens)  FILTER (WHERE tu.cost_usd_ticks IS NULL), 0)::bigint AS uncosted_cache_read_tokens,
            COALESCE(SUM(tu.cache_write_tokens) FILTER (WHERE tu.cost_usd_ticks IS NULL), 0)::bigint AS uncosted_cache_write_tokens,
            COUNT(DISTINCT tu.task_id)::bigint AS task_count,
            COUNT(*)::bigint                   AS event_count
          FROM dirty_keys dk
          JOIN agent_task_queue atq ON atq.runtime_id  = dk.runtime_id
                                    AND atq.agent_id    = dk.agent_id
          JOIN agent            a   ON a.id            = atq.agent_id
                                    AND a.workspace_id = dk.workspace_id
          LEFT JOIN issue       i   ON i.id            = atq.issue_id
          JOIN task_usage       tu  ON tu.task_id      = atq.id
                                    AND tu.provider    = dk.provider
                                    AND tu.model       = dk.model
                                    AND task_usage_hour_bucket(tu.created_at) = dk.bucket_hour
         WHERE (i.project_id IS NOT DISTINCT FROM dk.project_id)
         GROUP BY 1, 2, 3, 4, 5, 6, 7
    ),
    upserted AS (
        INSERT INTO task_usage_hourly AS d (
            bucket_hour, workspace_id, runtime_id, agent_id,
            project_id, provider, model,
            input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
            cost_usd_ticks,
            uncosted_input_tokens, uncosted_output_tokens,
            uncosted_cache_read_tokens, uncosted_cache_write_tokens,
            task_count, event_count
        )
        SELECT
            bucket_hour, workspace_id, runtime_id, agent_id,
            project_id, provider, model,
            input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
            cost_usd_ticks,
            uncosted_input_tokens, uncosted_output_tokens,
            uncosted_cache_read_tokens, uncosted_cache_write_tokens,
            task_count, event_count
          FROM recomputed
        ON CONFLICT ON CONSTRAINT uq_task_usage_hourly_key DO UPDATE
            SET input_tokens                = EXCLUDED.input_tokens,
                output_tokens               = EXCLUDED.output_tokens,
                cache_read_tokens           = EXCLUDED.cache_read_tokens,
                cache_write_tokens          = EXCLUDED.cache_write_tokens,
                cost_usd_ticks              = EXCLUDED.cost_usd_ticks,
                uncosted_input_tokens       = EXCLUDED.uncosted_input_tokens,
                uncosted_output_tokens      = EXCLUDED.uncosted_output_tokens,
                uncosted_cache_read_tokens  = EXCLUDED.uncosted_cache_read_tokens,
                uncosted_cache_write_tokens = EXCLUDED.uncosted_cache_write_tokens,
                task_count                  = EXCLUDED.task_count,
                event_count                 = EXCLUDED.event_count,
                updated_at                  = now()
        RETURNING 1
    ),
    deleted_empty AS (
        DELETE FROM task_usage_hourly d
         USING dirty_keys dk
         WHERE d.bucket_hour  = dk.bucket_hour
           AND d.workspace_id = dk.workspace_id
           AND d.runtime_id   = dk.runtime_id
           AND d.agent_id     = dk.agent_id
           AND d.project_id IS NOT DISTINCT FROM dk.project_id
           AND d.provider     = dk.provider
           AND d.model        = dk.model
           AND NOT EXISTS (
               SELECT 1 FROM recomputed r
                WHERE r.bucket_hour  = dk.bucket_hour
                  AND r.workspace_id = dk.workspace_id
                  AND r.runtime_id   = dk.runtime_id
                  AND r.agent_id     = dk.agent_id
                  AND r.project_id IS NOT DISTINCT FROM dk.project_id
                  AND r.provider     = dk.provider
                  AND r.model        = dk.model
           )
        RETURNING 1
    )
    SELECT (SELECT COUNT(*) FROM upserted) + (SELECT COUNT(*) FROM deleted_empty)
      INTO v_rows;

    DELETE FROM task_usage_hourly_dirty WHERE enqueued_at < p_to;

    RETURN v_rows;
END;
$$;


--
-- Name: set_agent_task_comment_thread(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_agent_task_comment_thread() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 NEW.comment_thread_id := COALESCE(NULLIF(NEW.context->>'wakeup_id','')::uuid,comment_thread_root_id(NEW.trigger_comment_id));
 RETURN NEW;
END
$$;


--
-- Name: task_usage_hour_bucket(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.task_usage_hour_bucket(ts timestamp with time zone) RETURNS timestamp with time zone
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT (date_trunc('hour', ts AT TIME ZONE 'UTC')) AT TIME ZONE 'UTC';
$$;


--
-- Name: task_usage_hourly_rollup_lag_seconds(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.task_usage_hourly_rollup_lag_seconds() RETURNS double precision
    LANGUAGE sql STABLE
    AS $$
    SELECT EXTRACT(EPOCH FROM (now() - last_run_finished_at))
      FROM task_usage_hourly_rollup_state
     WHERE id = 1;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    issue_id uuid,
    actor_type text,
    actor_id uuid,
    action text NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT activity_log_actor_type_check CHECK ((actor_type = ANY (ARRAY['member'::text, 'agent'::text, 'system'::text])))
);


--
-- Name: agent; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    avatar_url text,
    runtime_mode text NOT NULL,
    runtime_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    visibility text DEFAULT 'private'::text NOT NULL,
    status text DEFAULT 'offline'::text NOT NULL,
    max_concurrent_tasks integer DEFAULT 6 NOT NULL,
    owner_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    runtime_id uuid,
    instructions text DEFAULT ''::text NOT NULL,
    archived_at timestamp with time zone,
    archived_by uuid,
    custom_env jsonb DEFAULT '{}'::jsonb NOT NULL,
    custom_args jsonb DEFAULT '[]'::jsonb NOT NULL,
    mcp_config jsonb,
    model text,
    thinking_level text,
    composio_toolkit_allowlist text[],
    permission_mode text DEFAULT 'private'::text NOT NULL,
    kind text DEFAULT 'user'::text NOT NULL,
    system_key text,
    disabled_runtime_skills jsonb DEFAULT '[]'::jsonb NOT NULL,
    service_tier text,
    conversation_starters jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT agent_conversation_starters_check CHECK (((jsonb_typeof(conversation_starters) = 'array'::text) AND (jsonb_array_length(conversation_starters) <= 3))),
    CONSTRAINT agent_description_length CHECK ((char_length(description) <= 255)),
    CONSTRAINT agent_kind_check CHECK ((kind = ANY (ARRAY['user'::text, 'system'::text]))),
    CONSTRAINT agent_permission_mode_check CHECK ((permission_mode = ANY (ARRAY['private'::text, 'public_to'::text]))),
    CONSTRAINT agent_runtime_mode_check CHECK ((runtime_mode = ANY (ARRAY['local'::text, 'cloud'::text]))),
    CONSTRAINT agent_status_check CHECK ((status = ANY (ARRAY['idle'::text, 'working'::text, 'blocked'::text, 'error'::text, 'offline'::text]))),
    CONSTRAINT agent_visibility_check CHECK ((visibility = ANY (ARRAY['workspace'::text, 'private'::text])))
);


--
-- Name: COLUMN agent.composio_toolkit_allowlist; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent.composio_toolkit_allowlist IS 'Composio toolkit slugs this agent is allowed to mount as MCP. NULL or empty array = no MCP overlay. Mounted for any run that passes the agent invocation-permission gate (MUL-3963); the overlay uses the agent OWNER''s active Composio connection, so sharing the agent (public_to) shares these apps with whoever may invoke it. No longer gated on originator == owner. Stored as TEXT[] so the dispatch path can intersect against the owner''s active connections with a single SQL ANY() filter.';


--
-- Name: COLUMN agent.permission_mode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent.permission_mode IS 'Agent invocation permission mode (MUL-3963). private = owner only; public_to = allow-list in agent_invocation_target. Replaces visibility as the authorization source for triggering runs; visibility is now a derived legacy field. Default private = deny-by-default.';


--
-- Name: agent_builder_draft; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_builder_draft (
    chat_session_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    draft jsonb DEFAULT '{}'::jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: agent_invocation_target; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_invocation_target (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    agent_id uuid NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT agent_invocation_target_target_type_check CHECK ((target_type = ANY (ARRAY['workspace'::text, 'member'::text, 'team'::text])))
);


--
-- Name: TABLE agent_invocation_target; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.agent_invocation_target IS 'Allow-list of who may invoke a public_to agent (MUL-3963). One row per (agent, target_type, target); targets stack and canInvokeAgent OR-matches. workspace rows store the agent workspace_id in target_id; member rows store the user id; team rows are reserved and inert in V1. Rows only matter when agent.permission_mode = public_to. No DB foreign keys: agent_id / created_by / member target_id relationships are maintained in the application layer (see migration comment).';


--
-- Name: agent_mcp_server; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_mcp_server (
    agent_id uuid NOT NULL,
    server_id uuid NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: agent_runtime; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_runtime (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    daemon_id text,
    name text NOT NULL,
    runtime_mode text NOT NULL,
    provider text NOT NULL,
    status text DEFAULT 'offline'::text NOT NULL,
    device_info text DEFAULT ''::text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_seen_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    owner_id uuid,
    legacy_daemon_id text,
    visibility text DEFAULT 'private'::text NOT NULL,
    profile_id uuid,
    custom_name text,
    CONSTRAINT agent_runtime_runtime_mode_check CHECK ((runtime_mode = ANY (ARRAY['local'::text, 'cloud'::text]))),
    CONSTRAINT agent_runtime_status_check CHECK ((status = ANY (ARRAY['online'::text, 'offline'::text]))),
    CONSTRAINT agent_runtime_visibility_check CHECK ((visibility = ANY (ARRAY['private'::text, 'public'::text])))
);


--
-- Name: agent_skill; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_skill (
    agent_id uuid NOT NULL,
    skill_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    enabled boolean DEFAULT true NOT NULL
);


--
-- Name: agent_task_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_task_queue (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    agent_id uuid NOT NULL,
    issue_id uuid,
    status text DEFAULT 'queued'::text NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    dispatched_at timestamp with time zone,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    result jsonb,
    error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    context jsonb,
    runtime_id uuid,
    session_id text,
    work_dir text,
    trigger_comment_id uuid,
    chat_session_id uuid,
    autopilot_run_id uuid,
    attempt integer DEFAULT 1 NOT NULL,
    max_attempts integer DEFAULT 2 NOT NULL,
    parent_task_id uuid,
    failure_reason text,
    trigger_summary text,
    force_fresh_session boolean DEFAULT false NOT NULL,
    is_leader_task boolean DEFAULT false NOT NULL,
    wait_reason text,
    initiator_user_id uuid,
    handoff_note text,
    prepare_lease_expires_at timestamp with time zone,
    squad_id uuid,
    runtime_mcp_overlay jsonb,
    escalation_for_task_id uuid,
    fire_at timestamp with time zone,
    originator_user_id uuid,
    runtime_connected_apps jsonb,
    coalesced_comment_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    delivered_comment_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    chat_input_task_id uuid,
    chat_finalize_deferred_at timestamp with time zone,
    originator_source text,
    delegated_from_task_id uuid,
    retry_of_task_id uuid,
    rerun_of_task_id uuid,
    rule_version_id uuid,
    trigger_evidence_kind text,
    trigger_evidence_ref_id uuid,
    accountable_user_id uuid,
    session_rollout_missing boolean DEFAULT false NOT NULL,
    retired_session_id text,
    quick_actions_disabled boolean DEFAULT false NOT NULL,
    regenerate_quick_actions_for uuid,
    branch_name text,
    durable_work_dir text,
    channel_context_revision bigint,
    comment_thread_id uuid,
    cancelled_by_type text,
    cancelled_by_id uuid,
    cancelled_by_name text,
    issue_snapshot jsonb,
    workflow_step text,
    cr_id text,
    pipeline_node_run_id uuid,
    project_id uuid,
    approval_workspace_id uuid,
    CONSTRAINT agent_task_queue_accountable_matches_originator CHECK (((originator_user_id IS NULL) OR ((accountable_user_id IS NOT NULL) AND (accountable_user_id = originator_user_id)))),
    CONSTRAINT agent_task_queue_approval_workspace_ck CHECK (((trigger_evidence_kind IS DISTINCT FROM 'approval_continuation'::text) OR (approval_workspace_id IS NOT NULL))),
    CONSTRAINT agent_task_queue_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'dispatched'::text, 'running'::text, 'completed'::text, 'failed'::text, 'cancelled'::text, 'waiting_local_directory'::text, 'deferred'::text])))
);


--
-- Name: COLUMN agent_task_queue.runtime_mcp_overlay; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.runtime_mcp_overlay IS 'Per-task MCP servers computed at dispatch time, merged on top of agent.mcp_config. Currently used by Composio integration to inject the initiator user''s session URL. Cleared after task completes via trg_clear_runtime_mcp_overlay.';


--
-- Name: COLUMN agent_task_queue.originator_user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.originator_user_id IS 'Top-of-chain human originator for this run. For human-triggered tasks (comment by a member, chat, quick-create) equals that member. For agent-fanout tasks inherited from the parent task''s originator_user_id via comment.source_task_id. NULL when no human is in the chain (autopilot, system-driven). Used by canInvokeAgent to judge A2A by the originator; the Composio overlay now follows invocation permission and uses the agent owner''s connection, so this is audit/attribution + A2A gating, NOT a Composio owner==originator gate (MUL-3963).';


--
-- Name: COLUMN agent_task_queue.runtime_connected_apps; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.runtime_connected_apps IS 'Non-secret per-task connected app metadata corresponding to runtime_mcp_overlay, used by the daemon brief to tell agents which app capabilities are mounted. Cleared with runtime_mcp_overlay after task completion.';


--
-- Name: COLUMN agent_task_queue.originator_source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.originator_source IS 'Waterfall level that resolved originator_user_id for this run: direct_human | delegation | comment_source | rule_owner | owner_fallback | backfill | unattributed. Audit/visibility metadata only — never consulted for authorization. TEXT with no CHECK so new trigger paths can add a source without a migration (MUL-4302 §7). NULL on pre-migration rows.';


--
-- Name: COLUMN agent_task_queue.delegated_from_task_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.delegated_from_task_id IS 'For originator_source=delegation: the parent task whose accountable human was copied onto this run. Value is copied, not chained, so delegation cycles are harmless (MUL-4302 §3.2). No FK; app-layer integrity only.';


--
-- Name: COLUMN agent_task_queue.retry_of_task_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.retry_of_task_id IS 'System transient-failure retry lineage: the task this run re-attempts. Inherits the parent attribution unchanged. Kept distinct from rerun_of_task_id so retry vs rerun report separately (MUL-4302 §5). No FK.';


--
-- Name: COLUMN agent_task_queue.rerun_of_task_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.rerun_of_task_id IS 'Human manual-rerun lineage: the historical task a member re-ran. The rerun itself is a NEW direct_human attribution to the rerunning member; this column preserves the link to the original (MUL-4302 §5). No FK.';


--
-- Name: COLUMN agent_task_queue.rule_version_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.rule_version_id IS 'For originator_source=rule_owner: the published autopilot rule version snapshot whose publisher is the accountable human. No FK; snapshot table wiring lands in a later Phase 1 increment (MUL-4302 §3.4/§7).';


--
-- Name: COLUMN agent_task_queue.trigger_evidence_kind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.trigger_evidence_kind IS 'Uniform kind tag for the direct cause of this run (comment | issue_assignment | autopilot_run | rule_version | rerun | ...), paired with trigger_evidence_ref_id. Free TEXT so new evidence kinds need no migration (MUL-4302 §2).';


--
-- Name: COLUMN agent_task_queue.trigger_evidence_ref_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.trigger_evidence_ref_id IS 'The row id referenced by trigger_evidence_kind (a comment id, autopilot_run id, rule_version id, source task id, ...). No FK; resolvable per-kind in the app layer (MUL-4302 §2).';


--
-- Name: COLUMN agent_task_queue.accountable_user_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.agent_task_queue.accountable_user_id IS 'The one human accountable for this run, for audit / visibility / cost only — NEVER consulted for authorization (that is originator_user_id). Invariant: when originator_user_id IS NOT NULL, this equals it; the two diverge only when originator_user_id IS NULL (autopilot rule_owner / degraded owner_fallback name an accountable human while authorization carries none). No FK, no cascade (MUL-4302 §1/§7). NULL means no accountable human was resolved: a pre-migration row, OR a NEW row whose audit source is not-yet-resolved / unattributed (e.g. run_only autopilot until rule_owner lands) — NOT pre-migration only.';


--
-- Name: agent_to_label; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_to_label (
    agent_id uuid NOT NULL,
    label_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: approval_record; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_record (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    cr_id text NOT NULL,
    stage text NOT NULL,
    decision text NOT NULL,
    approver_user_id uuid NOT NULL,
    evidence_digest text NOT NULL,
    key_id text NOT NULL,
    signature text NOT NULL,
    reject_reason text DEFAULT ''::text NOT NULL,
    grant_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    delivered_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT approval_record_decision_check CHECK ((decision = ANY (ARRAY['approve'::text, 'reject'::text])))
);


--
-- Name: attachment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attachment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    issue_id uuid,
    comment_id uuid,
    uploader_type text NOT NULL,
    uploader_id uuid NOT NULL,
    filename text NOT NULL,
    url text NOT NULL,
    content_type text NOT NULL,
    size_bytes bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    chat_session_id uuid,
    chat_message_id uuid,
    task_id uuid,
    source_context_id uuid,
    CONSTRAINT attachment_uploader_type_check CHECK ((uploader_type = ANY (ARRAY['member'::text, 'agent'::text])))
);


--
-- Name: autopilot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.autopilot (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    assignee_id uuid NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    execution_mode text DEFAULT 'create_issue'::text NOT NULL,
    issue_title_template text,
    created_by_type text NOT NULL,
    created_by_id uuid NOT NULL,
    last_run_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    assignee_type text DEFAULT 'agent'::text NOT NULL,
    project_id uuid,
    pause_reason text,
    CONSTRAINT autopilot_assignee_type_check CHECK ((assignee_type = ANY (ARRAY['agent'::text, 'squad'::text]))),
    CONSTRAINT autopilot_created_by_type_check CHECK ((created_by_type = ANY (ARRAY['member'::text, 'agent'::text]))),
    CONSTRAINT autopilot_execution_mode_check CHECK ((execution_mode = ANY (ARRAY['create_issue'::text, 'run_only'::text]))),
    CONSTRAINT autopilot_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'archived'::text])))
);


--
-- Name: autopilot_collaborator; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.autopilot_collaborator (
    autopilot_id uuid NOT NULL,
    user_type text NOT NULL,
    user_id uuid NOT NULL,
    granted_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT autopilot_collaborator_user_type_check CHECK ((user_type = 'member'::text))
);


--
-- Name: autopilot_quota_period; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.autopilot_quota_period (
    workspace_id uuid NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    used_count bigint DEFAULT 0 NOT NULL,
    reserved_count bigint DEFAULT 0 NOT NULL,
    blocked_counts jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    rejection_notified_at timestamp with time zone,
    CONSTRAINT autopilot_quota_period_check CHECK ((period_start < period_end)),
    CONSTRAINT autopilot_quota_period_reserved_count_check CHECK ((reserved_count >= 0)),
    CONSTRAINT autopilot_quota_period_used_count_check CHECK ((used_count >= 0))
);


--
-- Name: autopilot_quota_reservation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.autopilot_quota_reservation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    policy_revision bigint NOT NULL,
    subscription_version bigint NOT NULL,
    source text NOT NULL,
    idempotency_key text NOT NULL,
    state text DEFAULT 'reserved'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    finalized_at timestamp with time zone,
    CONSTRAINT autopilot_quota_reservation_check CHECK ((period_start < period_end)),
    CONSTRAINT autopilot_quota_reservation_state_check CHECK ((state = ANY (ARRAY['reserved'::text, 'consumed'::text, 'released'::text])))
);


--
-- Name: autopilot_rule_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.autopilot_rule_version (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    autopilot_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    published_by_type text NOT NULL,
    published_by_id uuid,
    config_summary jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE autopilot_rule_version; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.autopilot_rule_version IS 'Append-only snapshot of autopilot rule publishes (MUL-4302 §3.4). One row per substantive publish (create / enable / resume / trigger-condition / target / instructions change), recording the publisher + effective-config summary. Dispatch resolves the latest row for an autopilot as the run''s rule_owner accountable human. No FK, no cascade.';


--
-- Name: autopilot_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.autopilot_run (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    autopilot_id uuid NOT NULL,
    trigger_id uuid,
    source text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    issue_id uuid,
    task_id uuid,
    triggered_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    failure_reason text,
    trigger_payload jsonb,
    result jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    squad_id uuid,
    planned_at timestamp with time zone,
    webhook_delivery_id uuid,
    quota_reservation_id uuid,
    reason_code text,
    CONSTRAINT autopilot_run_source_check CHECK ((source = ANY (ARRAY['schedule'::text, 'manual'::text, 'webhook'::text, 'api'::text]))),
    CONSTRAINT autopilot_run_status_check CHECK ((status = ANY (ARRAY['issue_created'::text, 'running'::text, 'completed'::text, 'failed'::text, 'skipped'::text])))
);


--
-- Name: autopilot_subscriber; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.autopilot_subscriber (
    autopilot_id uuid NOT NULL,
    user_type text NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT autopilot_subscriber_user_type_check CHECK ((user_type = 'member'::text))
);


--
-- Name: autopilot_trigger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.autopilot_trigger (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    autopilot_id uuid NOT NULL,
    kind text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    cron_expression text,
    timezone text DEFAULT 'UTC'::text,
    next_run_at timestamp with time zone,
    webhook_token text,
    label text,
    last_fired_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    provider text DEFAULT 'generic'::text NOT NULL,
    signing_secret text,
    event_filters jsonb,
    published_by_type text,
    published_by_id uuid,
    created_by_type text,
    created_by_id uuid,
    CONSTRAINT autopilot_trigger_kind_check CHECK ((kind = ANY (ARRAY['schedule'::text, 'webhook'::text, 'api'::text]))),
    CONSTRAINT autopilot_trigger_provider_check CHECK ((provider = ANY (ARRAY['generic'::text, 'github'::text])))
);


--
-- Name: COLUMN autopilot_trigger.published_by_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.autopilot_trigger.published_by_type IS 'Actor type of the trigger''s current responsible publisher: member | agent. Set to the creator at creation and re-stamped to the editor on any substantive edit governing this trigger. CONFIG audit only — since MUL-6951 it decides nothing about the runs this trigger fires. NULL on triggers predating MUL-4302.';


--
-- Name: COLUMN autopilot_trigger.published_by_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.autopilot_trigger.published_by_id IS 'The member/agent currently responsible for this trigger''s effective config (creator, then last substantive editor). CONFIG audit only: since MUL-6951 the runs this trigger fires act as, and are accountable to, created_by_id instead, so an edit recorded here never moves a run''s authority. No FK, app-layer integrity (MUL-4302).';


--
-- Name: COLUMN autopilot_trigger.created_by_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.autopilot_trigger.created_by_type IS 'Actor type of created_by_id: member | agent. Only ''member'' yields a run principal. NULL only for a legacy trigger that neither backfill (migrations 449, 467) could fill.';


--
-- Name: COLUMN autopilot_trigger.created_by_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.autopilot_trigger.created_by_id IS 'The member a schedule/webhook run fires AS: dispatch admission, the task''s originator/accountable, and every delegated run all resolve to this one human (MUL-6951). For a trigger created since MUL-6951 it is the creator, written at creation. For a legacy trigger it is a best-effort principal inferred once by backfill and frozen (the last publisher, migration 449, else the autopilot''s creator, migration 467), not proof of who created it. Ordinary edits never rewrite it, so editing the trigger cannot re-authorize its runs as the editor. NULL means no principal and the dispatch fails closed. No FK; workspace membership is re-validated on every dispatch.';


--
-- Name: channel_binding_token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_binding_token (
    token_hash text NOT NULL,
    workspace_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    channel_type text NOT NULL,
    channel_user_id text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    consumed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT channel_binding_token_ttl_cap CHECK ((expires_at <= (created_at + '00:15:00'::interval)))
);


--
-- Name: channel_chat_context_generation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_chat_context_generation (
    chat_session_id uuid NOT NULL,
    revision bigint NOT NULL,
    history_start_message_id text,
    history_end_message_id text,
    history_boundary_pending boolean DEFAULT false NOT NULL,
    pending_fresh boolean DEFAULT false NOT NULL,
    initiator_user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_message_id text,
    last_thread_id text,
    last_sender_id text
);


--
-- Name: channel_chat_session_binding; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_chat_session_binding (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chat_session_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    channel_type text NOT NULL,
    channel_chat_id text NOT NULL,
    chat_type text NOT NULL,
    last_message_id text,
    last_thread_id text,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pending_fresh boolean DEFAULT false NOT NULL,
    context_revision bigint DEFAULT 1 NOT NULL,
    route_revision bigint DEFAULT 1 NOT NULL,
    retired_at timestamp with time zone,
    history_start_message_id text,
    history_end_message_id text,
    history_boundary_pending boolean DEFAULT false NOT NULL,
    CONSTRAINT channel_chat_session_binding_chat_type_check CHECK ((chat_type = ANY (ARRAY['p2p'::text, 'group'::text])))
);


--
-- Name: channel_inbound_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_inbound_audit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    installation_id uuid,
    channel_type text NOT NULL,
    channel_chat_id text,
    event_type text NOT NULL,
    channel_event_id text,
    channel_message_id text,
    drop_reason text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: channel_inbound_message_dedup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_inbound_message_dedup (
    installation_id uuid NOT NULL,
    message_id text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    claim_token uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: channel_installation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_installation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    agent_id uuid NOT NULL,
    channel_type text NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    ws_lease_token text,
    ws_lease_expires_at timestamp with time zone,
    installer_user_id uuid NOT NULL,
    installed_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT channel_installation_status_check CHECK ((status = ANY (ARRAY['active'::text, 'revoked'::text])))
);


--
-- Name: channel_media_pending_object; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_media_pending_object (
    storage_key text NOT NULL,
    workspace_id uuid NOT NULL,
    chat_message_id uuid NOT NULL,
    storage_url text NOT NULL,
    installation_id uuid,
    state text DEFAULT 'pending'::text NOT NULL,
    lease_token uuid,
    lease_expires_at timestamp with time zone,
    attempt integer DEFAULT 0 NOT NULL,
    next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
    last_error text,
    tombstone_pass integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT channel_media_pending_object_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'deleting'::text, 'tombstoned'::text])))
);


--
-- Name: channel_outbound_card_message; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_outbound_card_message (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chat_session_id uuid NOT NULL,
    task_id uuid,
    channel_type text NOT NULL,
    channel_chat_id text NOT NULL,
    channel_card_message_id text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    last_patched_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT channel_outbound_card_message_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'streaming'::text, 'final'::text, 'error'::text])))
);


--
-- Name: channel_outbound_message; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_outbound_message (
    installation_id uuid NOT NULL,
    channel_type text NOT NULL,
    channel_message_id text NOT NULL,
    binding_id uuid NOT NULL,
    route_revision bigint NOT NULL,
    task_id uuid,
    outbound_kind text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: channel_reply_delivery; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_reply_delivery (
    turn_id uuid NOT NULL,
    task_id uuid NOT NULL,
    binding_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    channel_type text NOT NULL,
    chat_id text NOT NULL,
    phase text NOT NULL,
    send_state text NOT NULL,
    message_id text DEFAULT ''::text NOT NULL,
    chunks_sent integer DEFAULT 0 NOT NULL,
    owner_token uuid,
    owner_expires_at timestamp with time zone,
    settled_reason text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    attempt_depth integer DEFAULT 0 NOT NULL,
    CONSTRAINT channel_reply_delivery_attempt_depth_check CHECK ((attempt_depth >= 0)),
    CONSTRAINT channel_reply_delivery_chunks_sent_check CHECK ((chunks_sent >= 0)),
    CONSTRAINT channel_reply_delivery_phase_check CHECK ((phase = ANY (ARRAY['streaming'::text, 'terminal'::text, 'settled'::text]))),
    CONSTRAINT channel_reply_delivery_send_state_check CHECK ((send_state = ANY (ARRAY['none'::text, 'in_flight'::text, 'known'::text, 'unknown'::text])))
);


--
-- Name: channel_task_delivery; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_task_delivery (
    task_id uuid NOT NULL,
    binding_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    channel_type text NOT NULL,
    channel_chat_id text NOT NULL,
    chat_type text NOT NULL,
    channel_message_id text,
    channel_thread_id text,
    route_revision bigint NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    channel_sender_id text
);


--
-- Name: channel_typing_reaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_typing_reaction (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    chat_session_id uuid NOT NULL,
    chat_message_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    channel_message_id text NOT NULL,
    installation_snapshot jsonb NOT NULL,
    reaction_id text DEFAULT ''::text NOT NULL,
    add_finished boolean DEFAULT false NOT NULL,
    cleanup_required boolean DEFAULT false NOT NULL,
    cleaned_at timestamp with time zone,
    retry_after timestamp with time zone DEFAULT now() NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    abandoned_at timestamp with time zone,
    quota_slot integer
);


--
-- Name: channel_user_binding; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_user_binding (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    multica_user_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    channel_type text NOT NULL,
    channel_user_id text NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    bound_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_draft_restore; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_draft_restore (
    id uuid NOT NULL,
    chat_session_id uuid NOT NULL,
    task_id uuid NOT NULL,
    content text NOT NULL,
    attachment_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_idempotency; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_idempotency (
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    scope_type text NOT NULL,
    scope_id uuid NOT NULL,
    key text NOT NULL,
    fingerprint text NOT NULL,
    response_status integer NOT NULL,
    response_body jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chat_idempotency_scope_type_check CHECK ((scope_type = ANY (ARRAY['discussion_message'::text, 'merge_forward_messages'::text, 'discussion_promotion'::text])))
);


--
-- Name: chat_message; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_message (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chat_session_id uuid NOT NULL,
    role text NOT NULL,
    content text NOT NULL,
    task_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    failure_reason text,
    elapsed_ms bigint,
    message_kind text DEFAULT 'message'::text NOT NULL,
    channel_media_pending_until timestamp with time zone,
    channel_ingested boolean DEFAULT false NOT NULL,
    quick_actions jsonb DEFAULT '[]'::jsonb NOT NULL,
    channel_context_revision bigint,
    channel_outbound_type text,
    channel_outbound_installation_id uuid,
    channel_outbound_chat_id text,
    channel_outbound_message_ids text[],
    channel_typing_settled boolean DEFAULT false NOT NULL,
    author_type text,
    author_id uuid,
    CONSTRAINT chat_message_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text])))
);


--
-- Name: chat_pinned_agent; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_pinned_agent (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    agent_id uuid NOT NULL,
    "position" double precision DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: chat_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_session (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    agent_id uuid,
    creator_id uuid NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    session_id text,
    work_dir text,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    unread_since timestamp with time zone,
    runtime_id uuid,
    last_read_at timestamp with time zone DEFAULT now() NOT NULL,
    is_agent_intro boolean DEFAULT false NOT NULL,
    pinned_at timestamp with time zone,
    project_id uuid,
    explicitly_created_at timestamp with time zone,
    base_model text,
    base_thinking_level text,
    model_override text,
    thinking_level_override text,
    kind text DEFAULT 'private'::text NOT NULL,
    CONSTRAINT chat_session_kind_check CHECK ((kind = ANY (ARRAY['private'::text, 'project_shared'::text]))),
    CONSTRAINT chat_session_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])))
);


--
-- Name: client_usage_daily; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_usage_daily (
    user_id uuid NOT NULL,
    client_type text NOT NULL,
    install_id uuid NOT NULL,
    activity_date date NOT NULL,
    workspace_id uuid,
    client_version text NOT NULL,
    os text NOT NULL,
    first_active_at timestamp with time zone NOT NULL,
    last_active_at timestamp with time zone NOT NULL,
    runtime_probed_at timestamp with time zone,
    probe_result text,
    runtime_count integer,
    provider_summary jsonb,
    online_count integer,
    offline_count integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT client_usage_daily_check CHECK ((first_active_at <= last_active_at)),
    CONSTRAINT client_usage_daily_check1 CHECK ((((runtime_probed_at IS NULL) AND (probe_result IS NULL) AND (runtime_count IS NULL) AND (provider_summary IS NULL) AND (online_count IS NULL) AND (offline_count IS NULL)) OR ((runtime_probed_at IS NOT NULL) AND (probe_result = 'error'::text) AND (runtime_count IS NULL) AND (provider_summary IS NULL) AND (online_count IS NULL) AND (offline_count IS NULL)) OR ((runtime_probed_at IS NOT NULL) AND (probe_result = 'success'::text) AND (runtime_count IS NOT NULL) AND (provider_summary IS NOT NULL) AND (online_count IS NOT NULL) AND (offline_count IS NOT NULL) AND ((online_count + offline_count) = runtime_count) AND (jsonb_typeof(provider_summary) = 'object'::text)))),
    CONSTRAINT client_usage_daily_client_type_check CHECK ((client_type = ANY (ARRAY['web'::text, 'desktop'::text]))),
    CONSTRAINT client_usage_daily_offline_count_check CHECK ((offline_count >= 0)),
    CONSTRAINT client_usage_daily_online_count_check CHECK ((online_count >= 0)),
    CONSTRAINT client_usage_daily_probe_result_check CHECK ((probe_result = ANY (ARRAY['success'::text, 'error'::text]))),
    CONSTRAINT client_usage_daily_runtime_count_check CHECK ((runtime_count >= 0))
);


--
-- Name: comment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    issue_id uuid NOT NULL,
    author_type text NOT NULL,
    author_id uuid NOT NULL,
    content text NOT NULL,
    type text DEFAULT 'comment'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    parent_id uuid,
    workspace_id uuid NOT NULL,
    resolved_at timestamp with time zone,
    resolved_by_type text,
    resolved_by_id uuid,
    source_task_id uuid,
    quick_action_id uuid,
    via_plugin_id uuid,
    revision bigint DEFAULT 1 NOT NULL,
    recovery_settled_at timestamp with time zone,
    deleted_at timestamp with time zone,
    suppressed_agent_ids uuid[],
    CONSTRAINT comment_author_type_check CHECK ((author_type = ANY (ARRAY['member'::text, 'agent'::text, 'system'::text, 'plugin'::text]))),
    CONSTRAINT comment_resolved_consistency CHECK ((((resolved_at IS NULL) AND (resolved_by_type IS NULL) AND (resolved_by_id IS NULL)) OR ((resolved_at IS NOT NULL) AND (resolved_by_type IS NOT NULL) AND (resolved_by_id IS NOT NULL)))),
    CONSTRAINT comment_type_check CHECK ((type = ANY (ARRAY['comment'::text, 'status_change'::text, 'progress_update'::text, 'system'::text])))
);


--
-- Name: comment_reaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment_reaction (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    comment_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    actor_type text NOT NULL,
    actor_id uuid NOT NULL,
    emoji text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT comment_reaction_actor_type_check CHECK ((actor_type = ANY (ARRAY['member'::text, 'agent'::text])))
);


--
-- Name: contact_sales_inquiry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_sales_inquiry (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    business_email text NOT NULL,
    company_name text NOT NULL,
    company_size text NOT NULL,
    country_region text NOT NULL,
    use_case text NOT NULL,
    goals text DEFAULT ''::text NOT NULL,
    consent_outreach boolean DEFAULT false NOT NULL,
    consent_updates boolean DEFAULT false NOT NULL,
    submitter_ip inet,
    user_agent text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cr; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cr (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    cr_id text NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    status text NOT NULL,
    owners jsonb DEFAULT '{}'::jsonb NOT NULL,
    target_version text DEFAULT ''::text NOT NULL,
    projected_commit text DEFAULT ''::text NOT NULL,
    needs_reconcile boolean DEFAULT false NOT NULL,
    shell_issue_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    execution_authorization_head_id uuid
);


--
-- Name: cr_sync_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cr_sync_event (
    id bigint NOT NULL,
    cr_id text NOT NULL,
    commit_sha text DEFAULT ''::text NOT NULL,
    event_kind text NOT NULL,
    payload jsonb NOT NULL,
    evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    actor text DEFAULT ''::text NOT NULL,
    occurred_at timestamp with time zone NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    workspace_id uuid NOT NULL
);


--
-- Name: cr_sync_event_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cr_sync_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cr_sync_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cr_sync_event_id_seq OWNED BY public.cr_sync_event.id;


--
-- Name: daemon_connection; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daemon_connection (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    agent_id uuid NOT NULL,
    daemon_id text NOT NULL,
    status text DEFAULT 'disconnected'::text NOT NULL,
    last_heartbeat_at timestamp with time zone,
    runtime_info jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT daemon_connection_status_check CHECK ((status = ANY (ARRAY['connected'::text, 'disconnected'::text])))
);


--
-- Name: daemon_token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daemon_token (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    token_hash text NOT NULL,
    workspace_id uuid NOT NULL,
    daemon_id text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: dingtalk_bot_identity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dingtalk_bot_identity (
    workspace_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    bot_name text DEFAULT ''::text NOT NULL,
    bot_identity_issue text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: dingtalk_group_presence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dingtalk_group_presence (
    workspace_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    conversation_id text NOT NULL,
    conversation_title text DEFAULT ''::text NOT NULL,
    bot_name text DEFAULT ''::text NOT NULL,
    bot_identity_issue text DEFAULT ''::text NOT NULL,
    first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_active_at timestamp with time zone,
    mention_count bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT dingtalk_group_presence_mention_count_check CHECK ((mention_count >= 0))
);


--
-- Name: dingtalk_group_route; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dingtalk_group_route (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    conversation_id text NOT NULL,
    conversation_title text DEFAULT ''::text NOT NULL,
    agent_id uuid NOT NULL,
    revision bigint DEFAULT 1 NOT NULL,
    discovered_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: drift_finding; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drift_finding (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    repository_id text NOT NULL,
    spec_id text,
    cr_id text,
    kind text NOT NULL,
    severity text NOT NULL,
    summary text NOT NULL,
    evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    found_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    CONSTRAINT drift_finding_check CHECK (((kind <> ALL (ARRAY['bypass-commit'::text, 'wip-on-trunk'::text])) OR ((COALESCE((evidence ->> 'repository_id'::text), ''::text) <> ''::text) AND (COALESCE((evidence ->> 'trunk'::text), ''::text) <> ''::text) AND (COALESCE((evidence ->> 'commit_sha'::text), ''::text) <> ''::text) AND (COALESCE((evidence ->> 'commit_subject'::text), ''::text) <> ''::text) AND (COALESCE((evidence ->> 'scanned_at'::text), ''::text) <> ''::text)))),
    CONSTRAINT drift_finding_kind_check CHECK ((kind = ANY (ARRAY['alignment-drift'::text, 'impact-stale'::text, 'bypass-commit'::text, 'wip-on-trunk'::text]))),
    CONSTRAINT drift_finding_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warn'::text, 'block'::text]))),
    CONSTRAINT drift_finding_status_check CHECK ((status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'resolved'::text, 'wontfix'::text])))
);


--
-- Name: feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feedback (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    workspace_id uuid,
    message text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: github_installation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_installation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    installation_id bigint NOT NULL,
    account_login text NOT NULL,
    account_type text DEFAULT 'User'::text NOT NULL,
    account_avatar_url text,
    connected_by_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT github_installation_account_type_check CHECK ((account_type = ANY (ARRAY['User'::text, 'Organization'::text])))
);


--
-- Name: github_pending_check_suite; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_pending_check_suite (
    workspace_id uuid NOT NULL,
    installation_id bigint NOT NULL,
    repo_owner text NOT NULL,
    repo_name text NOT NULL,
    pr_number integer NOT NULL,
    suite_id bigint NOT NULL,
    head_sha text NOT NULL,
    app_id bigint NOT NULL,
    conclusion text,
    status text NOT NULL,
    suite_updated_at timestamp with time zone NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: github_pending_installation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_pending_installation (
    installation_id bigint NOT NULL,
    account_login text NOT NULL,
    account_type text DEFAULT 'User'::text NOT NULL,
    account_avatar_url text,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT github_pending_installation_account_login_check CHECK ((account_login <> ''::text)),
    CONSTRAINT github_pending_installation_account_type_check CHECK ((account_type = ANY (ARRAY['User'::text, 'Organization'::text])))
);


--
-- Name: github_pull_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_pull_request (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    installation_id bigint NOT NULL,
    repo_owner text NOT NULL,
    repo_name text NOT NULL,
    pr_number integer NOT NULL,
    title text NOT NULL,
    state text NOT NULL,
    html_url text NOT NULL,
    branch text,
    author_login text,
    author_avatar_url text,
    merged_at timestamp with time zone,
    closed_at timestamp with time zone,
    pr_created_at timestamp with time zone NOT NULL,
    pr_updated_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    head_sha text DEFAULT ''::text NOT NULL,
    mergeable_state text,
    additions integer DEFAULT 0 NOT NULL,
    deletions integer DEFAULT 0 NOT NULL,
    changed_files integer DEFAULT 0 NOT NULL,
    api_mergeable text,
    api_merge_state_status text,
    checks_rollup_state text,
    snapshot_head_sha text DEFAULT ''::text NOT NULL,
    snapshot_fetched_at timestamp with time zone,
    CONSTRAINT github_pull_request_state_check CHECK ((state = ANY (ARRAY['open'::text, 'closed'::text, 'merged'::text, 'draft'::text])))
);


--
-- Name: github_pull_request_check_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_pull_request_check_run (
    pr_id uuid NOT NULL,
    head_sha text NOT NULL,
    ordinal integer NOT NULL,
    name text NOT NULL,
    status text NOT NULL,
    conclusion text,
    details_url text,
    is_status_context boolean DEFAULT false NOT NULL
);


--
-- Name: github_pull_request_check_suite; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.github_pull_request_check_suite (
    pr_id uuid NOT NULL,
    suite_id bigint NOT NULL,
    head_sha text NOT NULL,
    app_id bigint NOT NULL,
    conclusion text,
    status text NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: inbox_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbox_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    recipient_type text NOT NULL,
    recipient_id uuid NOT NULL,
    type text NOT NULL,
    severity text DEFAULT 'info'::text NOT NULL,
    issue_id uuid,
    title text NOT NULL,
    body text,
    read boolean DEFAULT false NOT NULL,
    archived boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    actor_type text,
    actor_id uuid,
    details jsonb DEFAULT '{}'::jsonb,
    CONSTRAINT inbox_item_recipient_type_check CHECK ((recipient_type = ANY (ARRAY['member'::text, 'agent'::text]))),
    CONSTRAINT inbox_item_severity_check CHECK ((severity = ANY (ARRAY['action_required'::text, 'attention'::text, 'info'::text])))
);


--
-- Name: instance_telemetry_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instance_telemetry_state (
    singleton boolean DEFAULT true NOT NULL,
    instance_id uuid DEFAULT gen_random_uuid() NOT NULL,
    last_successful_day date,
    pending_day date,
    pending_body bytea,
    next_attempt_at timestamp with time zone,
    attempt_count integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT instance_telemetry_state_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT instance_telemetry_state_check CHECK ((((pending_day IS NULL) AND (pending_body IS NULL) AND (next_attempt_at IS NULL) AND (attempt_count = 0)) OR ((pending_day IS NOT NULL) AND (pending_body IS NOT NULL) AND (next_attempt_at IS NOT NULL)))),
    CONSTRAINT instance_telemetry_state_singleton_check CHECK (singleton)
);


--
-- Name: issue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    status text DEFAULT 'backlog'::text NOT NULL,
    priority text DEFAULT 'none'::text NOT NULL,
    assignee_type text,
    assignee_id uuid,
    creator_type text NOT NULL,
    creator_id uuid NOT NULL,
    parent_issue_id uuid,
    acceptance_criteria jsonb DEFAULT '[]'::jsonb NOT NULL,
    context_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
    "position" double precision DEFAULT 0 NOT NULL,
    due_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    number integer DEFAULT 0 NOT NULL,
    project_id uuid,
    origin_type text,
    origin_id uuid,
    first_executed_at timestamp with time zone,
    start_date date,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    stage integer,
    properties jsonb DEFAULT '{}'::jsonb NOT NULL,
    revision bigint DEFAULT 1 NOT NULL,
    last_activity_at timestamp with time zone,
    triage_state text,
    duplicate_of_issue_id uuid,
    CONSTRAINT issue_assignee_type_check CHECK ((assignee_type = ANY (ARRAY['member'::text, 'agent'::text, 'squad'::text]))),
    CONSTRAINT issue_creator_type_check CHECK ((creator_type = ANY (ARRAY['member'::text, 'agent'::text]))),
    CONSTRAINT issue_metadata_is_object CHECK ((jsonb_typeof(metadata) = 'object'::text)),
    CONSTRAINT issue_metadata_size_limit CHECK ((pg_column_size(metadata) <= 8192)),
    CONSTRAINT issue_origin_type_check CHECK ((origin_type = ANY (ARRAY['autopilot'::text, 'quick_create'::text, 'lark_chat'::text, 'slack_chat'::text, 'agent_create'::text, 'project_chat'::text, 'project_discussion'::text, 'dingtalk_chat'::text, 'wecom_chat'::text, 'telegram_chat'::text]))),
    CONSTRAINT issue_priority_check CHECK ((priority = ANY (ARRAY['urgent'::text, 'high'::text, 'medium'::text, 'low'::text, 'none'::text]))),
    CONSTRAINT issue_properties_is_object CHECK ((jsonb_typeof(properties) = 'object'::text)),
    CONSTRAINT issue_properties_size_limit CHECK ((pg_column_size(properties) <= 16384)),
    CONSTRAINT issue_stage_check CHECK (((stage IS NULL) OR (stage >= 1))),
    CONSTRAINT issue_status_format_check CHECK ((status ~ '^[a-z0-9][a-z0-9_]{0,31}$'::text)),
    CONSTRAINT issue_triage_state_known CHECK (((triage_state IS NULL) OR (triage_state = 'pending'::text)))
);


--
-- Name: issue_child_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_child_event (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    parent_id uuid NOT NULL,
    child_id uuid NOT NULL,
    kind text NOT NULL,
    source_task_id uuid,
    created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    claimed_at timestamp with time zone,
    processed_at timestamp with time zone,
    CONSTRAINT issue_child_event_kind_check CHECK ((kind = ANY (ARRAY['closed'::text, 'reopened'::text, 'attached'::text, 'detached'::text, 'restaged'::text])))
);


--
-- Name: issue_dependency; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_dependency (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    issue_id uuid NOT NULL,
    depends_on_issue_id uuid NOT NULL,
    type text NOT NULL,
    CONSTRAINT issue_dependency_type_check CHECK ((type = ANY (ARRAY['blocks'::text, 'blocked_by'::text, 'related'::text])))
);


--
-- Name: issue_label; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_label (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    color text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    resource_type text DEFAULT 'issue'::text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    CONSTRAINT issue_label_resource_type_check CHECK ((resource_type = ANY (ARRAY['issue'::text, 'agent'::text, 'skill'::text])))
);


--
-- Name: issue_pr_automation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_pr_automation (
    issue_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    auto_complete_disabled boolean DEFAULT false NOT NULL,
    updated_by_type text,
    updated_by_id uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: issue_property; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_property (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    type text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    "position" double precision DEFAULT 0 NOT NULL,
    archived_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    icon text DEFAULT ''::text NOT NULL,
    CONSTRAINT issue_property_config_check CHECK ((jsonb_typeof(config) = 'object'::text)),
    CONSTRAINT issue_property_type_check CHECK ((type = ANY (ARRAY['text'::text, 'number'::text, 'select'::text, 'multi_select'::text, 'date'::text, 'checkbox'::text, 'url'::text, 'actor'::text, 'multi_actor'::text, 'multi_text'::text, 'multi_url'::text])))
);


--
-- Name: issue_pull_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_pull_request (
    issue_id uuid NOT NULL,
    pull_request_id uuid NOT NULL,
    linked_by_type text,
    linked_by_id uuid,
    linked_at timestamp with time zone DEFAULT now() NOT NULL,
    close_intent boolean DEFAULT false NOT NULL
);


--
-- Name: issue_pull_request_exclusion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_pull_request_exclusion (
    issue_id uuid NOT NULL,
    pull_request_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    excluded_by_type text,
    excluded_by_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: issue_reaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_reaction (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    issue_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    actor_type text NOT NULL,
    actor_id uuid NOT NULL,
    emoji text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT issue_reaction_actor_type_check CHECK ((actor_type = ANY (ARRAY['member'::text, 'agent'::text])))
);


--
-- Name: issue_source_context; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_source_context (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    issue_id uuid,
    origin_task_id uuid,
    source_issue_id uuid NOT NULL,
    anchor_comment_id uuid NOT NULL,
    captured_by_user_id uuid NOT NULL,
    snapshot_version smallint NOT NULL,
    snapshot jsonb NOT NULL,
    capture_digest text NOT NULL,
    state text NOT NULL,
    captured_at timestamp with time zone DEFAULT now() NOT NULL,
    attached_at timestamp with time zone,
    CONSTRAINT issue_source_context_check CHECK ((((state = 'pending'::text) AND (issue_id IS NULL) AND (origin_task_id IS NOT NULL) AND (attached_at IS NULL)) OR ((state = 'attached'::text) AND (issue_id IS NOT NULL) AND (attached_at IS NOT NULL)) OR ((state = 'abandoned'::text) AND (issue_id IS NULL) AND (attached_at IS NULL)))),
    CONSTRAINT issue_source_context_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'attached'::text, 'abandoned'::text])))
);


--
-- Name: issue_source_context_object_intent; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_source_context_object_intent (
    storage_key text NOT NULL,
    workspace_id uuid NOT NULL,
    source_context_id uuid NOT NULL,
    attachment_id uuid NOT NULL,
    object_url text NOT NULL,
    state text DEFAULT 'pending'::text NOT NULL,
    lease_token uuid,
    lease_expires_at timestamp with time zone,
    next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT issue_source_context_object_intent_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'deleting'::text])))
);


--
-- Name: issue_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_status (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    key text NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    category text NOT NULL,
    color text NOT NULL,
    is_system boolean DEFAULT false NOT NULL,
    "position" double precision DEFAULT 0 NOT NULL,
    archived_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    icon text DEFAULT ''::text NOT NULL,
    CONSTRAINT issue_status_category_check CHECK ((category = ANY (ARRAY['unstarted'::text, 'started'::text, 'done'::text, 'closed'::text]))),
    CONSTRAINT issue_status_color_check CHECK ((color ~ '^#[0-9a-f]{6}$'::text)),
    CONSTRAINT issue_status_description_check CHECK ((char_length(description) <= 256)),
    CONSTRAINT issue_status_key_check CHECK ((key ~ '^[a-z0-9][a-z0-9_]{0,31}$'::text)),
    CONSTRAINT issue_status_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 64))),
    CONSTRAINT issue_status_system_is_canonical CHECK (((NOT is_system) OR ((((((((key = 'backlog'::text) AND (category = 'unstarted'::text)) OR ((key = 'todo'::text) AND (category = 'unstarted'::text))) OR ((key = 'in_progress'::text) AND (category = 'started'::text))) OR ((key = 'in_review'::text) AND (category = 'started'::text))) OR ((key = 'blocked'::text) AND (category = 'started'::text))) OR ((key = 'done'::text) AND (category = 'done'::text))) OR ((key = 'cancelled'::text) AND (category = 'closed'::text))))),
    CONSTRAINT issue_status_system_not_archivable CHECK (((NOT is_system) OR (archived_at IS NULL)))
);


--
-- Name: issue_subscriber; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_subscriber (
    issue_id uuid NOT NULL,
    user_type text NOT NULL,
    user_id uuid NOT NULL,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    unsubscribed_at timestamp with time zone,
    opt_out_scope text,
    CONSTRAINT issue_subscriber_opt_out_scope_check CHECK ((opt_out_scope = ANY (ARRAY['issue'::text, 'subtree'::text]))),
    CONSTRAINT issue_subscriber_reason_check CHECK ((reason = ANY (ARRAY['creator'::text, 'assignee'::text, 'commenter'::text, 'mentioned'::text, 'manual'::text, 'autopilot'::text, 'delegated'::text]))),
    CONSTRAINT issue_subscriber_user_type_check CHECK ((user_type = ANY (ARRAY['member'::text, 'agent'::text])))
);


--
-- Name: issue_to_label; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_to_label (
    issue_id uuid NOT NULL,
    label_id uuid NOT NULL
);


--
-- Name: issue_vcs_pull_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_vcs_pull_request (
    issue_id uuid NOT NULL,
    pull_request_id uuid NOT NULL,
    close_intent boolean DEFAULT false NOT NULL,
    linked_by_type text,
    linked_by_id uuid,
    linked_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: issue_view; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_view (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    owner_id uuid NOT NULL,
    name text NOT NULL,
    scope_type text NOT NULL,
    scope_id uuid,
    scope_variant text,
    visibility text DEFAULT 'private'::text NOT NULL,
    definition_version integer DEFAULT 1 NOT NULL,
    query jsonb NOT NULL,
    display jsonb DEFAULT '{}'::jsonb NOT NULL,
    revision integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT issue_view_check CHECK ((((scope_type = 'project'::text) AND (scope_id IS NOT NULL)) OR ((scope_type = ANY (ARRAY['workspace'::text, 'my'::text])) AND (scope_id IS NULL)))),
    CONSTRAINT issue_view_check2 CHECK (((scope_type <> 'my'::text) OR (visibility = 'private'::text))),
    CONSTRAINT issue_view_display_check CHECK ((jsonb_typeof(display) = 'object'::text)),
    CONSTRAINT issue_view_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 80))),
    CONSTRAINT issue_view_query_check CHECK ((jsonb_typeof(query) = 'object'::text)),
    CONSTRAINT issue_view_scope_type_check CHECK ((scope_type = ANY (ARRAY['workspace'::text, 'my'::text, 'project'::text]))),
    CONSTRAINT issue_view_scope_variant_check CHECK ((scope_variant = ANY (ARRAY['assigned'::text, 'created'::text, 'involved'::text, 'any'::text, 'members'::text, 'agents'::text]))),
    CONSTRAINT issue_view_scope_variant_pairing CHECK ((((scope_type = 'my'::text) AND (scope_variant = ANY (ARRAY['assigned'::text, 'created'::text, 'involved'::text, 'any'::text]))) OR ((scope_type = 'workspace'::text) AND ((scope_variant IS NULL) OR (scope_variant = ANY (ARRAY['members'::text, 'agents'::text])))) OR ((scope_type = 'project'::text) AND ((scope_variant IS NULL) OR (scope_variant = ANY (ARRAY['members'::text, 'agents'::text])))))),
    CONSTRAINT issue_view_visibility_check CHECK ((visibility = ANY (ARRAY['private'::text, 'workspace'::text])))
);


--
-- Name: issue_view_preference; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_view_preference (
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    scope_type text NOT NULL,
    scope_id uuid NOT NULL,
    prefs jsonb DEFAULT '{}'::jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT issue_view_preference_prefs_check CHECK ((jsonb_typeof(prefs) = 'object'::text)),
    CONSTRAINT issue_view_preference_scope_type_check CHECK ((scope_type = ANY (ARRAY['workspace'::text, 'my'::text, 'project'::text])))
);


--
-- Name: issue_wakeup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_wakeup (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    issue_id uuid NOT NULL,
    agent_id uuid,
    created_by uuid,
    source_task_id uuid,
    parent_comment_id uuid,
    instruction text NOT NULL,
    kind text NOT NULL,
    mode text NOT NULL,
    event_types text[] DEFAULT '{}'::text[] NOT NULL,
    filter_agent_id uuid,
    filter_task_id uuid,
    interval_seconds bigint,
    cron_expression text,
    timezone text DEFAULT 'UTC'::text NOT NULL,
    next_fire_at timestamp with time zone,
    enabled boolean DEFAULT true NOT NULL,
    disabled_at timestamp with time zone,
    revision bigint DEFAULT 1 NOT NULL,
    last_task_id uuid,
    last_error text,
    created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    filter_actor_type text,
    filter_actor_id uuid,
    expires_at timestamp with time zone,
    expiry_seconds bigint,
    on_timeout text,
    timed_out_at timestamp with time zone,
    system_rule text,
    customized_at timestamp with time zone,
    condition jsonb,
    condition_state text DEFAULT ''::text NOT NULL,
    max_fires integer,
    fire_count integer DEFAULT 0 NOT NULL,
    paused_reason text,
    CONSTRAINT issue_wakeup_kind_check CHECK ((kind = ANY (ARRAY['event'::text, 'at'::text, 'every'::text, 'cron'::text]))),
    CONSTRAINT issue_wakeup_max_fires_check CHECK (((max_fires >= 1) AND (max_fires <= 1000))),
    CONSTRAINT issue_wakeup_mode_check CHECK ((mode = ANY (ARRAY['once'::text, 'continuous'::text]))),
    CONSTRAINT issue_wakeup_on_timeout_check CHECK ((on_timeout = ANY (ARRAY['wake'::text, 'end'::text]))),
    CONSTRAINT issue_wakeup_paused_reason_check CHECK ((paused_reason = ANY (ARRAY['max_fires'::text, 'loop'::text, 'rate'::text]))),
    CONSTRAINT issue_wakeup_system_rule_check CHECK ((system_rule = 'child_done'::text))
);


--
-- Name: issue_wakeup_receipt; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_wakeup_receipt (
    id uuid NOT NULL,
    wakeup_id uuid NOT NULL,
    revision bigint NOT NULL,
    event_key text NOT NULL,
    event_type text NOT NULL,
    payload jsonb NOT NULL,
    task_id uuid,
    processed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    coalesce_key text
);


--
-- Name: issue_workflow; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.issue_workflow (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    initial_status_key text NOT NULL,
    steps jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    CONSTRAINT issue_workflow_description_check CHECK ((char_length(description) <= 256)),
    CONSTRAINT issue_workflow_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 64))),
    CONSTRAINT issue_workflow_steps_check CHECK ((jsonb_typeof(steps) = 'array'::text))
);


--
-- Name: lark_binding_token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lark_binding_token (
    token_hash text NOT NULL,
    workspace_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    lark_open_id text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    consumed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lark_binding_token_ttl_cap CHECK ((expires_at <= (created_at + '00:15:00'::interval)))
);


--
-- Name: lark_chat_session_binding; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lark_chat_session_binding (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chat_session_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    lark_chat_id text NOT NULL,
    lark_chat_type text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_lark_message_id text,
    last_lark_thread_id text,
    CONSTRAINT lark_chat_session_binding_lark_chat_type_check CHECK ((lark_chat_type = ANY (ARRAY['p2p'::text, 'group'::text])))
);


--
-- Name: lark_inbound_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lark_inbound_audit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    installation_id uuid,
    lark_chat_id text,
    event_type text NOT NULL,
    lark_event_id text,
    lark_message_id text,
    drop_reason text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: lark_inbound_message_dedup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lark_inbound_message_dedup (
    installation_id uuid NOT NULL,
    message_id text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    claim_token uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: lark_installation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lark_installation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    agent_id uuid NOT NULL,
    app_id text NOT NULL,
    app_secret_encrypted bytea NOT NULL,
    tenant_key text,
    bot_open_id text NOT NULL,
    installer_user_id uuid NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    ws_lease_token text,
    ws_lease_expires_at timestamp with time zone,
    installed_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    bot_union_id text,
    region text DEFAULT 'feishu'::text NOT NULL,
    CONSTRAINT lark_installation_region_check CHECK ((region = ANY (ARRAY['feishu'::text, 'lark'::text]))),
    CONSTRAINT lark_installation_status_check CHECK ((status = ANY (ARRAY['active'::text, 'revoked'::text])))
);


--
-- Name: lark_outbound_card_message; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lark_outbound_card_message (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chat_session_id uuid NOT NULL,
    task_id uuid,
    lark_chat_id text NOT NULL,
    lark_card_message_id text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    last_patched_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lark_outbound_card_message_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'streaming'::text, 'final'::text, 'error'::text])))
);


--
-- Name: lark_user_binding; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lark_user_binding (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    multica_user_id uuid NOT NULL,
    installation_id uuid NOT NULL,
    lark_open_id text NOT NULL,
    union_id text,
    bound_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: maintenance_job; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maintenance_job (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    job_type text NOT NULL,
    job_version integer NOT NULL,
    scope_key text NOT NULL,
    idempotency_key text NOT NULL,
    request_hash text NOT NULL,
    status text NOT NULL,
    revision bigint DEFAULT 0 NOT NULL,
    dry_run boolean DEFAULT true NOT NULL,
    options jsonb NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    checkpoint jsonb DEFAULT '{}'::jsonb NOT NULL,
    progress jsonb DEFAULT '{}'::jsonb NOT NULL,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_error text DEFAULT ''::text NOT NULL,
    next_allowed_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    CONSTRAINT maintenance_job_check CHECK (((jsonb_typeof(options) = 'object'::text) AND (jsonb_typeof(parameters) = 'object'::text) AND (jsonb_typeof(checkpoint) = 'object'::text) AND (jsonb_typeof(progress) = 'object'::text) AND (jsonb_typeof(result) = 'object'::text))),
    CONSTRAINT maintenance_job_job_version_check CHECK ((job_version > 0)),
    CONSTRAINT maintenance_job_status_check CHECK ((status = ANY (ARRAY['ready'::text, 'paused'::text, 'completed'::text, 'cancelled'::text])))
);


--
-- Name: maturity_snapshot; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maturity_snapshot (
    workspace_id uuid NOT NULL,
    bucket_date date NOT NULL,
    scope text NOT NULL,
    scope_id text NOT NULL,
    metrics jsonb DEFAULT '{}'::jsonb NOT NULL,
    scores jsonb DEFAULT '{}'::jsonb NOT NULL,
    config_rev text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT maturity_snapshot_check CHECK ((((scope = 'org'::text) AND (scope_id = '·'::text)) OR ((scope = ANY (ARRAY['user'::text, 'project'::text])) AND (scope_id <> '·'::text)))),
    CONSTRAINT maturity_snapshot_config_rev_check CHECK ((config_rev ~ '^[0-9a-f]{40}$'::text)),
    CONSTRAINT maturity_snapshot_scope_check CHECK ((scope = ANY (ARRAY['org'::text, 'user'::text, 'project'::text])))
);


--
-- Name: member; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT member_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'member'::text])))
);


--
-- Name: notification_preference; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_preference (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    preferences jsonb DEFAULT '{}'::jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: personal_access_token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.personal_access_token (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    token_hash text NOT NULL,
    token_prefix text NOT NULL,
    expires_at timestamp with time zone,
    last_used_at timestamp with time zone,
    revoked boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pinned_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pinned_item (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    item_type text NOT NULL,
    item_id uuid NOT NULL,
    "position" double precision DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pinned_item_item_type_check CHECK ((item_type = ANY (ARRAY['issue'::text, 'project'::text, 'view'::text])))
);


--
-- Name: pipeline_node_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pipeline_node_run (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    run_id uuid NOT NULL,
    node_id uuid NOT NULL,
    ref text,
    kind text NOT NULL,
    seq integer NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    attempt integer DEFAULT 1 NOT NULL,
    approval_id uuid,
    output_note text,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    CONSTRAINT pipeline_node_run_kind_check CHECK ((kind = ANY (ARRAY['skill'::text, 'human_approval'::text, 'code_generation'::text]))),
    CONSTRAINT pipeline_node_run_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'passed'::text, 'blocked'::text, 'skipped'::text, 'failed'::text])))
);


--
-- Name: pipeline_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pipeline_run (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    pipeline_id text NOT NULL,
    cr_id text,
    issue_id uuid,
    status text DEFAULT 'running'::text NOT NULL,
    inputs jsonb DEFAULT '{}'::jsonb NOT NULL,
    execution_context jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    CONSTRAINT pipeline_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'waiting_approval'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: plugin_hook_schedule; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_hook_schedule (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    installation_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    hook_key text NOT NULL,
    cron_expression text NOT NULL,
    timezone text NOT NULL,
    generation uuid DEFAULT gen_random_uuid() NOT NULL,
    activated_at timestamp with time zone DEFAULT now() NOT NULL,
    next_run_at timestamp with time zone,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugin_hook_schedule_cron_expression_check CHECK (((char_length(cron_expression) >= 1) AND (char_length(cron_expression) <= 255))),
    CONSTRAINT plugin_hook_schedule_hook_key_check CHECK (((char_length(hook_key) >= 1) AND (char_length(hook_key) <= 128))),
    CONSTRAINT plugin_hook_schedule_timezone_check CHECK (((char_length(timezone) >= 1) AND (char_length(timezone) <= 255)))
);


--
-- Name: plugin_installation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_installation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    plugin_key text NOT NULL,
    version text NOT NULL,
    manifest jsonb NOT NULL,
    granted_scopes jsonb DEFAULT '[]'::jsonb NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    installed_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    token_hash text,
    token_rotated_at timestamp with time zone,
    mcp_approvals jsonb DEFAULT '{}'::jsonb NOT NULL,
    package_version_id uuid NOT NULL,
    CONSTRAINT plugin_installation_config_check CHECK ((jsonb_typeof(config) = 'object'::text)),
    CONSTRAINT plugin_installation_granted_scopes_check CHECK ((jsonb_typeof(granted_scopes) = 'array'::text)),
    CONSTRAINT plugin_installation_manifest_check CHECK ((jsonb_typeof(manifest) = 'object'::text)),
    CONSTRAINT plugin_installation_mcp_approvals_check CHECK ((jsonb_typeof(mcp_approvals) = 'object'::text)),
    CONSTRAINT plugin_installation_plugin_key_check CHECK (((char_length(plugin_key) >= 3) AND (char_length(plugin_key) <= 255))),
    CONSTRAINT plugin_installation_version_check CHECK (((char_length(version) >= 1) AND (char_length(version) <= 64)))
);


--
-- Name: plugin_invocation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_invocation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    installation_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    hook_key text NOT NULL,
    trigger text NOT NULL,
    status text NOT NULL,
    event_type text,
    attempt integer DEFAULT 1 NOT NULL,
    latency_ms integer DEFAULT 0 NOT NULL,
    error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    delivery_id text,
    planned_at timestamp with time zone,
    CONSTRAINT plugin_invocation_attempt_check CHECK (((attempt >= 1) AND (attempt <= 10))),
    CONSTRAINT plugin_invocation_delivery_id_check CHECK (((delivery_id IS NULL) OR ((char_length(delivery_id) >= 1) AND (char_length(delivery_id) <= 128)))),
    CONSTRAINT plugin_invocation_error_check CHECK (((error IS NULL) OR (char_length(error) <= 500))),
    CONSTRAINT plugin_invocation_hook_key_check CHECK (((char_length(hook_key) >= 1) AND (char_length(hook_key) <= 128))),
    CONSTRAINT plugin_invocation_latency_ms_check CHECK ((latency_ms >= 0)),
    CONSTRAINT plugin_invocation_status_check CHECK ((status = ANY (ARRAY['ok'::text, 'failed'::text, 'timeout'::text, 'refused'::text]))),
    CONSTRAINT plugin_invocation_trigger_check CHECK ((trigger = ANY (ARRAY['ui'::text, 'manual'::text, 'event'::text, 'agent'::text, 'schedule'::text])))
);


--
-- Name: plugin_package; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_package (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    plugin_key text NOT NULL,
    name text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugin_package_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 160))),
    CONSTRAINT plugin_package_plugin_key_check CHECK (((char_length(plugin_key) >= 3) AND (char_length(plugin_key) <= 255)))
);


--
-- Name: plugin_package_file; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_package_file (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    version_id uuid NOT NULL,
    path text NOT NULL,
    content bytea NOT NULL,
    size_bytes bigint NOT NULL,
    sha256 text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugin_package_file_path_check CHECK (((char_length(path) >= 1) AND (char_length(path) <= 1024))),
    CONSTRAINT plugin_package_file_sha256_check CHECK ((char_length(sha256) = 64)),
    CONSTRAINT plugin_package_file_size_bytes_check CHECK ((size_bytes >= 0))
);


--
-- Name: plugin_package_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_package_version (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    package_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    version text NOT NULL,
    manifest jsonb NOT NULL,
    digest text NOT NULL,
    size_bytes bigint NOT NULL,
    published_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugin_package_version_digest_check CHECK ((char_length(digest) = 64)),
    CONSTRAINT plugin_package_version_manifest_check CHECK ((jsonb_typeof(manifest) = 'object'::text)),
    CONSTRAINT plugin_package_version_size_bytes_check CHECK ((size_bytes >= 0)),
    CONSTRAINT plugin_package_version_version_check CHECK (((char_length(version) >= 1) AND (char_length(version) <= 64)))
);


--
-- Name: plugin_secret; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_secret (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    installation_id uuid NOT NULL,
    key text NOT NULL,
    ciphertext bytea NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugin_secret_ciphertext_check CHECK ((octet_length(ciphertext) > 0)),
    CONSTRAINT plugin_secret_key_check CHECK (((char_length(key) >= 1) AND (char_length(key) <= 128)))
);


--
-- Name: plugin_storage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plugin_storage (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    installation_id uuid NOT NULL,
    scope_type text NOT NULL,
    scope_id uuid NOT NULL,
    key text NOT NULL,
    value text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plugin_storage_key_check CHECK (((octet_length(key) >= 1) AND (octet_length(key) <= 1024))),
    CONSTRAINT plugin_storage_scope_type_check CHECK ((scope_type = ANY (ARRAY['workspace'::text, 'user'::text]))),
    CONSTRAINT plugin_storage_value_check CHECK ((octet_length(value) <= 102400))
);


--
-- Name: project; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    icon text,
    status text DEFAULT 'planned'::text NOT NULL,
    lead_type text,
    lead_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    priority text DEFAULT 'none'::text NOT NULL,
    start_date date,
    due_date date,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    workflow_id uuid,
    CONSTRAINT project_lead_type_check CHECK ((lead_type = ANY (ARRAY['member'::text, 'agent'::text]))),
    CONSTRAINT project_priority_check CHECK ((priority = ANY (ARRAY['urgent'::text, 'high'::text, 'medium'::text, 'low'::text, 'none'::text]))),
    CONSTRAINT project_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'in_progress'::text, 'paused'::text, 'completed'::text, 'cancelled'::text])))
);


--
-- Name: project_chat_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_chat_session (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    project_id uuid NOT NULL,
    agent_id uuid NOT NULL,
    issue_id uuid,
    base_model text,
    base_thinking_level text,
    model_override text,
    thinking_level_override text,
    status text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT project_chat_session_status_ck CHECK ((status = ANY (ARRAY['active'::text, 'closed'::text])))
);


--
-- Name: project_presenter_grant; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_presenter_grant (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    project_id uuid NOT NULL,
    user_id uuid NOT NULL,
    status text NOT NULL,
    granted_by uuid,
    resolved_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    CONSTRAINT project_presenter_grant_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'rejected'::text, 'released'::text, 'revoked'::text, 'transferred'::text])))
);


--
-- Name: project_resource; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_resource (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    resource_type text NOT NULL,
    resource_ref jsonb NOT NULL,
    label text,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid
);


--
-- Name: quick_action; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quick_action (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    assignee_type text NOT NULL,
    assignee_id uuid,
    prompt text NOT NULL,
    visibility text DEFAULT 'public'::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    last_used_at timestamp with time zone,
    use_count bigint DEFAULT 0 NOT NULL,
    created_by_type text NOT NULL,
    created_by_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT quick_action_assignee_type_check CHECK ((((assignee_type = ''::text) AND (assignee_id IS NULL)) OR ((assignee_type = ANY (ARRAY['agent'::text, 'squad'::text])) AND (assignee_id IS NOT NULL)))),
    CONSTRAINT quick_action_created_by_type_check CHECK ((created_by_type = ANY (ARRAY['member'::text, 'agent'::text]))),
    CONSTRAINT quick_action_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text]))),
    CONSTRAINT quick_action_visibility_check CHECK ((visibility = ANY (ARRAY['private'::text, 'public'::text])))
);


--
-- Name: runtime_profile; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.runtime_profile (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    display_name text NOT NULL,
    protocol_family text NOT NULL,
    command_name text NOT NULL,
    description text,
    fixed_args jsonb DEFAULT '[]'::jsonb NOT NULL,
    visibility text DEFAULT 'workspace'::text NOT NULL,
    created_by uuid,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    runtime_type text DEFAULT ''::text NOT NULL,
    CONSTRAINT runtime_profile_visibility_check CHECK ((visibility = ANY (ARRAY['workspace'::text, 'private'::text])))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: search_index_change; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.search_index_change (
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    change_xid xid8 NOT NULL,
    changed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT search_index_change_entity_type_check CHECK ((entity_type = ANY (ARRAY['issue'::text, 'comment'::text, 'project'::text])))
);


--
-- Name: search_index_prune_mark; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.search_index_prune_mark (
    singleton boolean DEFAULT true NOT NULL,
    pruned_through_xid xid8 NOT NULL,
    CONSTRAINT search_index_prune_mark_singleton_check CHECK (singleton)
);


--
-- Name: seat_capacity_outbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seat_capacity_outbox (
    workspace_id uuid NOT NULL,
    operation_token uuid NOT NULL,
    action text NOT NULL,
    subject_id uuid,
    member_id uuid,
    invitation_id uuid,
    share_link_id uuid,
    user_id uuid,
    expires_at timestamp with time zone,
    delivered_at timestamp with time zone,
    attempt_count integer DEFAULT 0 NOT NULL,
    next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
    lease_token uuid,
    last_error text,
    dead_lettered_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT seat_capacity_outbox_action_check CHECK ((action = ANY (ARRAY['reserve_invitation'::text, 'consume_invitation'::text, 'claim_share_join'::text, 'confirm'::text, 'release'::text, 'release_member'::text]))),
    CONSTRAINT seat_capacity_outbox_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT seat_capacity_outbox_check CHECK (((action <> 'reserve_invitation'::text) OR ((invitation_id IS NOT NULL) AND (expires_at IS NOT NULL)))),
    CONSTRAINT seat_capacity_outbox_check1 CHECK (((action <> 'consume_invitation'::text) OR ((invitation_id IS NOT NULL) AND (user_id IS NOT NULL)))),
    CONSTRAINT seat_capacity_outbox_check2 CHECK (((action <> 'claim_share_join'::text) OR ((share_link_id IS NOT NULL) AND (user_id IS NOT NULL)))),
    CONSTRAINT seat_capacity_outbox_check3 CHECK (((action <> 'confirm'::text) OR (member_id IS NOT NULL))),
    CONSTRAINT seat_capacity_outbox_check4 CHECK (((action <> 'release_member'::text) OR (member_id IS NOT NULL)))
);


--
-- Name: skill; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skill (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    plugin_installation_id uuid,
    visibility text DEFAULT 'private'::text NOT NULL,
    version text DEFAULT '0.1.0'::text NOT NULL,
    owner_actor text,
    CONSTRAINT skill_visibility_check CHECK ((visibility = ANY (ARRAY['private'::text, 'org'::text])))
);


--
-- Name: skill_file; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skill_file (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    skill_id uuid NOT NULL,
    path text NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: skill_to_label; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skill_to_label (
    skill_id uuid NOT NULL,
    label_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: skill_usage_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.skill_usage_event (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    skill_ref text NOT NULL,
    task_id uuid,
    project_id uuid,
    used_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE skill_usage_event; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.skill_usage_event IS 'Append-only skill usage telemetry. used_at is DISPATCH-TIME MATERIALIZATION, not completion-time use (PRD FR-7): a claim writes one row per skill ref and retries write more rows, so every aggregation must join agent_task_queue with status=''completed'' and count DISTINCT task_id per skill_ref.';


--
-- Name: squad; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.squad (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    leader_id uuid NOT NULL,
    creator_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    archived_at timestamp with time zone,
    archived_by uuid,
    avatar_url text,
    instructions text DEFAULT ''::text NOT NULL
);


--
-- Name: squad_member; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.squad_member (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    squad_id uuid NOT NULL,
    member_type text NOT NULL,
    member_id uuid NOT NULL,
    role text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT squad_member_member_type_check CHECK ((member_type = ANY (ARRAY['agent'::text, 'member'::text])))
);


--
-- Name: sys_cron_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sys_cron_executions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    job_name text NOT NULL,
    scope_kind text DEFAULT 'global'::text NOT NULL,
    scope_id text DEFAULT 'global'::text NOT NULL,
    plan_time timestamp with time zone NOT NULL,
    status text NOT NULL,
    attempt integer DEFAULT 1 NOT NULL,
    max_attempts integer DEFAULT 3 NOT NULL,
    next_retry_at timestamp with time zone,
    runner_id text,
    lease_token uuid DEFAULT gen_random_uuid() NOT NULL,
    heartbeat_at timestamp with time zone,
    stale_after timestamp with time zone,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    duration_ms integer,
    rows_affected bigint,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_code text,
    error_msg text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_sys_cron_attempt CHECK (((attempt >= 1) AND (max_attempts >= attempt))),
    CONSTRAINT chk_sys_cron_duration CHECK (((duration_ms IS NULL) OR (duration_ms >= 0))),
    CONSTRAINT chk_sys_cron_status CHECK ((status = ANY (ARRAY['RUNNING'::text, 'SUCCESS'::text, 'FAILED'::text])))
);


--
-- Name: task_message; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_message (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    task_id uuid NOT NULL,
    seq integer NOT NULL,
    type text NOT NULL,
    tool text,
    content text,
    input jsonb,
    output text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    output_truncated boolean,
    call_id text
);


--
-- Name: task_supplement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_supplement (
    task_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    issue_id uuid NOT NULL,
    comment_id uuid NOT NULL,
    author_id uuid NOT NULL,
    client_request_id uuid NOT NULL,
    status text NOT NULL,
    failure_reason text,
    attempt_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    delivered_at timestamp with time zone,
    CONSTRAINT task_supplement_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'delivering'::text, 'delivered'::text, 'failed'::text])))
);


--
-- Name: task_supplement_capability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_supplement_capability (
    task_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    issue_id uuid NOT NULL,
    capability text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: task_token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_token (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    token_hash text NOT NULL,
    task_id uuid NOT NULL,
    agent_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: task_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_usage (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    task_id uuid NOT NULL,
    provider text DEFAULT ''::text NOT NULL,
    model text NOT NULL,
    input_tokens bigint DEFAULT 0 NOT NULL,
    output_tokens bigint DEFAULT 0 NOT NULL,
    cache_read_tokens bigint DEFAULT 0 NOT NULL,
    cache_write_tokens bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    cost_usd_ticks bigint
);


--
-- Name: COLUMN task_usage.cost_usd_ticks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.task_usage.cost_usd_ticks IS 'Provider-reported cost in 1e-10 USD. NULL when the provider reports none; those rows are priced client-side from the static rate table.';


--
-- Name: task_usage_hourly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_usage_hourly (
    bucket_hour timestamp with time zone NOT NULL,
    workspace_id uuid NOT NULL,
    runtime_id uuid NOT NULL,
    agent_id uuid NOT NULL,
    project_id uuid,
    provider text NOT NULL,
    model text NOT NULL,
    input_tokens bigint DEFAULT 0 NOT NULL,
    output_tokens bigint DEFAULT 0 NOT NULL,
    cache_read_tokens bigint DEFAULT 0 NOT NULL,
    cache_write_tokens bigint DEFAULT 0 NOT NULL,
    task_count bigint DEFAULT 0 NOT NULL,
    event_count bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    cost_usd_ticks bigint DEFAULT 0 NOT NULL,
    uncosted_input_tokens bigint,
    uncosted_output_tokens bigint,
    uncosted_cache_read_tokens bigint,
    uncosted_cache_write_tokens bigint
);


--
-- Name: COLUMN task_usage_hourly.cost_usd_ticks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.task_usage_hourly.cost_usd_ticks IS 'Sum of provider-reported cost (1e-10 USD) over the rows in this bucket that had one; 0 when none did.';


--
-- Name: COLUMN task_usage_hourly.uncosted_input_tokens; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.task_usage_hourly.uncosted_input_tokens IS 'Input tokens from rows with no provider-reported cost — the portion still priced from the static rate table. NULL on buckets not yet recomputed since this column existed; readers COALESCE to input_tokens.';


--
-- Name: task_usage_hourly_dirty; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_usage_hourly_dirty (
    bucket_hour timestamp with time zone NOT NULL,
    workspace_id uuid NOT NULL,
    runtime_id uuid NOT NULL,
    agent_id uuid NOT NULL,
    project_id uuid,
    provider text NOT NULL,
    model text NOT NULL,
    enqueued_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: task_usage_hourly_rollup_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_usage_hourly_rollup_state (
    id smallint DEFAULT 1 NOT NULL,
    watermark_at timestamp with time zone DEFAULT '1970-01-01 00:00:00+00'::timestamp with time zone NOT NULL,
    last_run_started_at timestamp with time zone,
    last_run_finished_at timestamp with time zone,
    last_run_rows bigint DEFAULT 0 NOT NULL,
    last_error text,
    CONSTRAINT task_usage_hourly_rollup_state_id_check CHECK ((id = 1))
);


--
-- Name: user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."user" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    email text NOT NULL,
    avatar_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    onboarded_at timestamp with time zone,
    onboarding_questionnaire jsonb DEFAULT '{}'::jsonb NOT NULL,
    cloud_waitlist_email character varying(254),
    cloud_waitlist_reason text,
    starter_content_state text,
    language character varying(20) DEFAULT NULL::character varying,
    profile_description text DEFAULT ''::text NOT NULL,
    timezone text
);


--
-- Name: COLUMN "user".timezone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public."user".timezone IS 'User-preferred IANA timezone for report rendering (Viewing tz). NULL means "use the browser-detected tz at render time". Affects dashboards, charts, and any "today" label shown to this user. Does not affect data materialisation — all rollups remain in UTC.';


--
-- Name: user_composio_connection; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_composio_connection (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    toolkit_slug text NOT NULL,
    auth_config_id text NOT NULL,
    connected_account_id text NOT NULL,
    composio_user_id text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    connected_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: vcs_commit_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vcs_commit_status (
    connection_id uuid NOT NULL,
    sha text NOT NULL,
    context text NOT NULL,
    state text NOT NULL,
    target_url text,
    description text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: vcs_connection; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vcs_connection (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    provider text DEFAULT 'forgejo'::text NOT NULL,
    instance_url text NOT NULL,
    account_login text NOT NULL,
    access_token_encrypted text NOT NULL,
    webhook_secret_encrypted text NOT NULL,
    connected_by_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vcs_connection_provider_check CHECK ((provider = ANY (ARRAY['forgejo'::text, 'gitea'::text, 'gitlab'::text])))
);


--
-- Name: vcs_pull_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vcs_pull_request (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    connection_id uuid NOT NULL,
    provider text DEFAULT 'forgejo'::text NOT NULL,
    repo_owner text NOT NULL,
    repo_name text NOT NULL,
    pr_number integer NOT NULL,
    title text NOT NULL,
    state text NOT NULL,
    html_url text NOT NULL,
    branch text,
    head_sha text DEFAULT ''::text NOT NULL,
    author_login text,
    author_avatar_url text,
    merged_at timestamp with time zone,
    closed_at timestamp with time zone,
    pr_created_at timestamp with time zone NOT NULL,
    pr_updated_at timestamp with time zone NOT NULL,
    additions integer DEFAULT 0 NOT NULL,
    deletions integer DEFAULT 0 NOT NULL,
    changed_files integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vcs_pull_request_provider_check CHECK ((provider = ANY (ARRAY['forgejo'::text, 'gitea'::text, 'gitlab'::text]))),
    CONSTRAINT vcs_pull_request_state_check CHECK ((state = ANY (ARRAY['open'::text, 'closed'::text, 'merged'::text, 'draft'::text])))
);


--
-- Name: verification_code; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.verification_code (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    code text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    attempts integer DEFAULT 0 NOT NULL
);


--
-- Name: webhook_delivery; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_delivery (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    autopilot_id uuid NOT NULL,
    trigger_id uuid NOT NULL,
    provider text NOT NULL,
    event text DEFAULT 'webhook.received'::text NOT NULL,
    dedupe_key text,
    dedupe_source text,
    signature_status text DEFAULT 'not_required'::text NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    attempt_count integer DEFAULT 1 NOT NULL,
    selected_headers jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_type text,
    raw_body bytea,
    response_status integer,
    response_body text,
    autopilot_run_id uuid,
    replayed_from_delivery_id uuid,
    error text,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    last_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    available_at timestamp with time zone DEFAULT now() NOT NULL,
    lease_token uuid,
    lease_expires_at timestamp with time zone,
    dispatch_attempts integer DEFAULT 0 NOT NULL,
    reason_code text,
    replay_idempotency_key text,
    CONSTRAINT webhook_delivery_provider_check CHECK ((provider = ANY (ARRAY['generic'::text, 'github'::text]))),
    CONSTRAINT webhook_delivery_signature_status_check CHECK ((signature_status = ANY (ARRAY['not_required'::text, 'valid'::text, 'invalid'::text, 'missing'::text]))),
    CONSTRAINT webhook_delivery_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'dispatched'::text, 'rejected'::text, 'ignored'::text, 'failed'::text])))
);


--
-- Name: workspace; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    description text,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    context text,
    repos jsonb DEFAULT '[]'::jsonb NOT NULL,
    issue_prefix text DEFAULT ''::text NOT NULL,
    issue_counter integer DEFAULT 0 NOT NULL,
    avatar_url text,
    attribution_fail_closed boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN workspace.attribution_fail_closed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workspace.attribution_fail_closed IS 'When TRUE, an agent run that resolves to no precise accountable human (would be owner_fallback) is refused at enqueue instead of degrading to the agent owner (MUL-4302 §3.5). Default FALSE = owner_fallback. Never affects authorization (originator_user_id).';


--
-- Name: workspace_invitation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_invitation (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    inviter_id uuid NOT NULL,
    invitee_email text NOT NULL,
    invitee_user_id uuid,
    role text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '7 days'::interval) NOT NULL,
    CONSTRAINT workspace_invitation_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'member'::text]))),
    CONSTRAINT workspace_invitation_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text, 'expired'::text])))
);


--
-- Name: workspace_mcp_server; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_mcp_server (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL,
    config jsonb NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: workspace_share_link; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_share_link (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    code text NOT NULL,
    created_by uuid NOT NULL,
    role text DEFAULT 'member'::text NOT NULL,
    expires_at timestamp with time zone,
    max_uses integer,
    use_count integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT workspace_share_link_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'member'::text])))
);


--
-- Name: cr_sync_event id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cr_sync_event ALTER COLUMN id SET DEFAULT nextval('public.cr_sync_event_id_seq'::regclass);


--
-- Name: activity_log activity_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_log
    ADD CONSTRAINT activity_log_pkey PRIMARY KEY (id);


--
-- Name: agent_builder_draft agent_builder_draft_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_builder_draft
    ADD CONSTRAINT agent_builder_draft_pkey PRIMARY KEY (chat_session_id);


--
-- Name: agent_invocation_target agent_invocation_target_agent_id_target_type_target_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_invocation_target
    ADD CONSTRAINT agent_invocation_target_agent_id_target_type_target_id_key UNIQUE (agent_id, target_type, target_id);


--
-- Name: agent_invocation_target agent_invocation_target_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_invocation_target
    ADD CONSTRAINT agent_invocation_target_pkey PRIMARY KEY (id);


--
-- Name: agent_mcp_server agent_mcp_server_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_mcp_server
    ADD CONSTRAINT agent_mcp_server_pkey PRIMARY KEY (agent_id, server_id);


--
-- Name: agent agent_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT agent_pkey PRIMARY KEY (id);


--
-- Name: agent_runtime agent_runtime_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_runtime
    ADD CONSTRAINT agent_runtime_pkey PRIMARY KEY (id);


--
-- Name: agent_skill agent_skill_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_skill
    ADD CONSTRAINT agent_skill_pkey PRIMARY KEY (agent_id, skill_id);


--
-- Name: agent_task_queue agent_task_queue_active_requires_runtime; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_active_requires_runtime CHECK (((runtime_id IS NOT NULL) OR (completed_at IS NOT NULL))) NOT VALID;


--
-- Name: agent_task_queue agent_task_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_pkey PRIMARY KEY (id);


--
-- Name: agent_to_label agent_to_label_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_to_label
    ADD CONSTRAINT agent_to_label_pkey PRIMARY KEY (agent_id, label_id);


--
-- Name: agent agent_workspace_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT agent_workspace_name_unique UNIQUE (workspace_id, name);


--
-- Name: approval_record approval_record_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_record
    ADD CONSTRAINT approval_record_pkey PRIMARY KEY (id);


--
-- Name: attachment attachment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_pkey PRIMARY KEY (id);


--
-- Name: autopilot_collaborator autopilot_collaborator_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_collaborator
    ADD CONSTRAINT autopilot_collaborator_pkey PRIMARY KEY (autopilot_id, user_type, user_id);


--
-- Name: autopilot autopilot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot
    ADD CONSTRAINT autopilot_pkey PRIMARY KEY (id);


--
-- Name: autopilot_quota_period autopilot_quota_period_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_quota_period
    ADD CONSTRAINT autopilot_quota_period_pkey PRIMARY KEY (workspace_id, period_start, period_end);


--
-- Name: autopilot_quota_reservation autopilot_quota_reservation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_quota_reservation
    ADD CONSTRAINT autopilot_quota_reservation_pkey PRIMARY KEY (id);


--
-- Name: autopilot_rule_version autopilot_rule_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_rule_version
    ADD CONSTRAINT autopilot_rule_version_pkey PRIMARY KEY (id);


--
-- Name: autopilot_run autopilot_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_run
    ADD CONSTRAINT autopilot_run_pkey PRIMARY KEY (id);


--
-- Name: autopilot_subscriber autopilot_subscriber_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_subscriber
    ADD CONSTRAINT autopilot_subscriber_pkey PRIMARY KEY (autopilot_id, user_type, user_id);


--
-- Name: autopilot_trigger autopilot_trigger_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_trigger
    ADD CONSTRAINT autopilot_trigger_pkey PRIMARY KEY (id);


--
-- Name: channel_binding_token channel_binding_token_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_binding_token
    ADD CONSTRAINT channel_binding_token_pkey PRIMARY KEY (token_hash);


--
-- Name: channel_chat_session_binding channel_chat_session_binding_chat_session_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_chat_session_binding
    ADD CONSTRAINT channel_chat_session_binding_chat_session_id_key UNIQUE (chat_session_id);


--
-- Name: channel_chat_session_binding channel_chat_session_binding_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_chat_session_binding
    ADD CONSTRAINT channel_chat_session_binding_pkey PRIMARY KEY (id);


--
-- Name: channel_inbound_audit channel_inbound_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_inbound_audit
    ADD CONSTRAINT channel_inbound_audit_pkey PRIMARY KEY (id);


--
-- Name: channel_inbound_message_dedup channel_inbound_message_dedup_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_inbound_message_dedup
    ADD CONSTRAINT channel_inbound_message_dedup_pkey PRIMARY KEY (installation_id, message_id);


--
-- Name: channel_installation channel_installation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_installation
    ADD CONSTRAINT channel_installation_pkey PRIMARY KEY (id);


--
-- Name: channel_installation channel_installation_workspace_id_agent_id_channel_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_installation
    ADD CONSTRAINT channel_installation_workspace_id_agent_id_channel_type_key UNIQUE (workspace_id, agent_id, channel_type);


--
-- Name: channel_media_pending_object channel_media_pending_object_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_media_pending_object
    ADD CONSTRAINT channel_media_pending_object_pkey PRIMARY KEY (storage_key);


--
-- Name: channel_outbound_card_message channel_outbound_card_message_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_outbound_card_message
    ADD CONSTRAINT channel_outbound_card_message_pkey PRIMARY KEY (id);


--
-- Name: channel_task_delivery channel_task_delivery_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_task_delivery
    ADD CONSTRAINT channel_task_delivery_pkey PRIMARY KEY (task_id);


--
-- Name: channel_user_binding channel_user_binding_installation_id_channel_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_user_binding
    ADD CONSTRAINT channel_user_binding_installation_id_channel_user_id_key UNIQUE (installation_id, channel_user_id);


--
-- Name: channel_user_binding channel_user_binding_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_user_binding
    ADD CONSTRAINT channel_user_binding_pkey PRIMARY KEY (id);


--
-- Name: chat_draft_restore chat_draft_restore_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_draft_restore
    ADD CONSTRAINT chat_draft_restore_pkey PRIMARY KEY (id);


--
-- Name: chat_idempotency chat_idempotency_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_idempotency
    ADD CONSTRAINT chat_idempotency_pkey PRIMARY KEY (workspace_id, user_id, scope_type, scope_id, key);


--
-- Name: chat_message chat_message_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_message
    ADD CONSTRAINT chat_message_pkey PRIMARY KEY (id);


--
-- Name: chat_pinned_agent chat_pinned_agent_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_pinned_agent
    ADD CONSTRAINT chat_pinned_agent_pkey PRIMARY KEY (id);


--
-- Name: chat_pinned_agent chat_pinned_agent_workspace_id_user_id_agent_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_pinned_agent
    ADD CONSTRAINT chat_pinned_agent_workspace_id_user_id_agent_id_key UNIQUE (workspace_id, user_id, agent_id);


--
-- Name: chat_session chat_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_session
    ADD CONSTRAINT chat_session_pkey PRIMARY KEY (id);


--
-- Name: client_usage_daily client_usage_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_usage_daily
    ADD CONSTRAINT client_usage_daily_pkey PRIMARY KEY (user_id, client_type, install_id, activity_date);


--
-- Name: comment comment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_pkey PRIMARY KEY (id);


--
-- Name: comment_reaction comment_reaction_comment_id_actor_type_actor_id_emoji_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reaction
    ADD CONSTRAINT comment_reaction_comment_id_actor_type_actor_id_emoji_key UNIQUE (comment_id, actor_type, actor_id, emoji);


--
-- Name: comment_reaction comment_reaction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reaction
    ADD CONSTRAINT comment_reaction_pkey PRIMARY KEY (id);


--
-- Name: contact_sales_inquiry contact_sales_inquiry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_sales_inquiry
    ADD CONSTRAINT contact_sales_inquiry_pkey PRIMARY KEY (id);


--
-- Name: cr cr_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cr
    ADD CONSTRAINT cr_pkey PRIMARY KEY (id);


--
-- Name: cr_sync_event cr_sync_event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cr_sync_event
    ADD CONSTRAINT cr_sync_event_pkey PRIMARY KEY (id);


--
-- Name: cr cr_workspace_id_cr_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cr
    ADD CONSTRAINT cr_workspace_id_cr_id_key UNIQUE (workspace_id, cr_id);


--
-- Name: daemon_connection daemon_connection_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daemon_connection
    ADD CONSTRAINT daemon_connection_pkey PRIMARY KEY (id);


--
-- Name: daemon_token daemon_token_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daemon_token
    ADD CONSTRAINT daemon_token_pkey PRIMARY KEY (id);


--
-- Name: drift_finding drift_finding_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drift_finding
    ADD CONSTRAINT drift_finding_pkey PRIMARY KEY (id);


--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);


--
-- Name: github_installation github_installation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_installation
    ADD CONSTRAINT github_installation_pkey PRIMARY KEY (id);


--
-- Name: github_installation github_installation_workspace_id_installation_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_installation
    ADD CONSTRAINT github_installation_workspace_id_installation_id_key UNIQUE (workspace_id, installation_id);


--
-- Name: github_pending_check_suite github_pending_check_suite_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_pending_check_suite
    ADD CONSTRAINT github_pending_check_suite_pkey PRIMARY KEY (workspace_id, repo_owner, repo_name, pr_number, suite_id);


--
-- Name: github_pending_installation github_pending_installation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_pending_installation
    ADD CONSTRAINT github_pending_installation_pkey PRIMARY KEY (installation_id);


--
-- Name: github_pull_request_check_suite github_pull_request_check_suite_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_pull_request_check_suite
    ADD CONSTRAINT github_pull_request_check_suite_pkey PRIMARY KEY (pr_id, suite_id);


--
-- Name: github_pull_request github_pull_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_pull_request
    ADD CONSTRAINT github_pull_request_pkey PRIMARY KEY (id);


--
-- Name: github_pull_request github_pull_request_workspace_id_repo_owner_repo_name_pr_nu_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_pull_request
    ADD CONSTRAINT github_pull_request_workspace_id_repo_owner_repo_name_pr_nu_key UNIQUE (workspace_id, repo_owner, repo_name, pr_number);


--
-- Name: inbox_item inbox_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_item
    ADD CONSTRAINT inbox_item_pkey PRIMARY KEY (id);


--
-- Name: instance_telemetry_state instance_telemetry_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instance_telemetry_state
    ADD CONSTRAINT instance_telemetry_state_pkey PRIMARY KEY (singleton);


--
-- Name: issue_dependency issue_dependency_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_dependency
    ADD CONSTRAINT issue_dependency_pkey PRIMARY KEY (id);


--
-- Name: issue_label issue_label_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_label
    ADD CONSTRAINT issue_label_pkey PRIMARY KEY (id);


--
-- Name: issue issue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue
    ADD CONSTRAINT issue_pkey PRIMARY KEY (id);


--
-- Name: issue_pr_automation issue_pr_automation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_pr_automation
    ADD CONSTRAINT issue_pr_automation_pkey PRIMARY KEY (issue_id);


--
-- Name: issue_property issue_property_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_property
    ADD CONSTRAINT issue_property_pkey PRIMARY KEY (id);


--
-- Name: issue_pull_request_exclusion issue_pull_request_exclusion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_pull_request_exclusion
    ADD CONSTRAINT issue_pull_request_exclusion_pkey PRIMARY KEY (issue_id, pull_request_id);


--
-- Name: issue_pull_request issue_pull_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_pull_request
    ADD CONSTRAINT issue_pull_request_pkey PRIMARY KEY (issue_id, pull_request_id);


--
-- Name: issue_reaction issue_reaction_issue_id_actor_type_actor_id_emoji_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_reaction
    ADD CONSTRAINT issue_reaction_issue_id_actor_type_actor_id_emoji_key UNIQUE (issue_id, actor_type, actor_id, emoji);


--
-- Name: issue_reaction issue_reaction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_reaction
    ADD CONSTRAINT issue_reaction_pkey PRIMARY KEY (id);


--
-- Name: issue_status issue_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_status
    ADD CONSTRAINT issue_status_pkey PRIMARY KEY (id);


--
-- Name: issue_subscriber issue_subscriber_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_subscriber
    ADD CONSTRAINT issue_subscriber_pkey PRIMARY KEY (issue_id, user_type, user_id);


--
-- Name: issue_to_label issue_to_label_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_to_label
    ADD CONSTRAINT issue_to_label_pkey PRIMARY KEY (issue_id, label_id);


--
-- Name: issue_vcs_pull_request issue_vcs_pull_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_vcs_pull_request
    ADD CONSTRAINT issue_vcs_pull_request_pkey PRIMARY KEY (issue_id, pull_request_id);


--
-- Name: issue_view issue_view_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_view
    ADD CONSTRAINT issue_view_pkey PRIMARY KEY (id);


--
-- Name: issue_view_preference issue_view_preference_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_view_preference
    ADD CONSTRAINT issue_view_preference_pkey PRIMARY KEY (workspace_id, user_id, scope_type, scope_id);


--
-- Name: issue_wakeup issue_wakeup_actor_filter; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.issue_wakeup
    ADD CONSTRAINT issue_wakeup_actor_filter CHECK ((((filter_actor_type IS NULL) AND (filter_actor_id IS NULL)) OR ((filter_actor_type IS NOT NULL) AND (filter_actor_type = ANY (ARRAY['member'::text, 'agent'::text])) AND (filter_actor_id IS NOT NULL) AND (kind = 'event'::text)))) NOT VALID;


--
-- Name: issue_workflow issue_workflow_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_workflow
    ADD CONSTRAINT issue_workflow_pkey PRIMARY KEY (id);


--
-- Name: lark_binding_token lark_binding_token_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_binding_token
    ADD CONSTRAINT lark_binding_token_pkey PRIMARY KEY (token_hash);


--
-- Name: lark_chat_session_binding lark_chat_session_binding_chat_session_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_chat_session_binding
    ADD CONSTRAINT lark_chat_session_binding_chat_session_id_key UNIQUE (chat_session_id);


--
-- Name: lark_chat_session_binding lark_chat_session_binding_installation_id_lark_chat_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_chat_session_binding
    ADD CONSTRAINT lark_chat_session_binding_installation_id_lark_chat_id_key UNIQUE (installation_id, lark_chat_id);


--
-- Name: lark_chat_session_binding lark_chat_session_binding_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_chat_session_binding
    ADD CONSTRAINT lark_chat_session_binding_pkey PRIMARY KEY (id);


--
-- Name: lark_inbound_audit lark_inbound_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_inbound_audit
    ADD CONSTRAINT lark_inbound_audit_pkey PRIMARY KEY (id);


--
-- Name: lark_inbound_message_dedup lark_inbound_message_dedup_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_inbound_message_dedup
    ADD CONSTRAINT lark_inbound_message_dedup_pkey PRIMARY KEY (installation_id, message_id);


--
-- Name: lark_installation lark_installation_app_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_installation
    ADD CONSTRAINT lark_installation_app_id_key UNIQUE (app_id);


--
-- Name: lark_installation lark_installation_id_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_installation
    ADD CONSTRAINT lark_installation_id_workspace_id_key UNIQUE (id, workspace_id);


--
-- Name: lark_installation lark_installation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_installation
    ADD CONSTRAINT lark_installation_pkey PRIMARY KEY (id);


--
-- Name: lark_installation lark_installation_workspace_id_agent_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_installation
    ADD CONSTRAINT lark_installation_workspace_id_agent_id_key UNIQUE (workspace_id, agent_id);


--
-- Name: lark_outbound_card_message lark_outbound_card_message_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_outbound_card_message
    ADD CONSTRAINT lark_outbound_card_message_pkey PRIMARY KEY (id);


--
-- Name: lark_user_binding lark_user_binding_installation_id_lark_open_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_user_binding
    ADD CONSTRAINT lark_user_binding_installation_id_lark_open_id_key UNIQUE (installation_id, lark_open_id);


--
-- Name: lark_user_binding lark_user_binding_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_user_binding
    ADD CONSTRAINT lark_user_binding_pkey PRIMARY KEY (id);


--
-- Name: maturity_snapshot maturity_snapshot_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maturity_snapshot
    ADD CONSTRAINT maturity_snapshot_pkey PRIMARY KEY (workspace_id, bucket_date, scope, scope_id);


--
-- Name: member member_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member
    ADD CONSTRAINT member_pkey PRIMARY KEY (id);


--
-- Name: member member_workspace_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member
    ADD CONSTRAINT member_workspace_id_user_id_key UNIQUE (workspace_id, user_id);


--
-- Name: notification_preference notification_preference_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_preference
    ADD CONSTRAINT notification_preference_pkey PRIMARY KEY (id);


--
-- Name: notification_preference notification_preference_workspace_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_preference
    ADD CONSTRAINT notification_preference_workspace_id_user_id_key UNIQUE (workspace_id, user_id);


--
-- Name: personal_access_token personal_access_token_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_token
    ADD CONSTRAINT personal_access_token_pkey PRIMARY KEY (id);


--
-- Name: pinned_item pinned_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pinned_item
    ADD CONSTRAINT pinned_item_pkey PRIMARY KEY (id);


--
-- Name: pinned_item pinned_item_workspace_id_user_id_item_type_item_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pinned_item
    ADD CONSTRAINT pinned_item_workspace_id_user_id_item_type_item_id_key UNIQUE (workspace_id, user_id, item_type, item_id);


--
-- Name: pipeline_node_run pipeline_node_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_node_run
    ADD CONSTRAINT pipeline_node_run_pkey PRIMARY KEY (id);


--
-- Name: pipeline_node_run pipeline_node_run_run_id_node_id_attempt_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_node_run
    ADD CONSTRAINT pipeline_node_run_run_id_node_id_attempt_key UNIQUE (run_id, node_id, attempt);


--
-- Name: pipeline_run pipeline_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_run
    ADD CONSTRAINT pipeline_run_pkey PRIMARY KEY (id);


--
-- Name: plugin_hook_schedule plugin_hook_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_hook_schedule
    ADD CONSTRAINT plugin_hook_schedule_pkey PRIMARY KEY (id);


--
-- Name: plugin_installation plugin_installation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_installation
    ADD CONSTRAINT plugin_installation_pkey PRIMARY KEY (id);


--
-- Name: plugin_invocation plugin_invocation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_invocation
    ADD CONSTRAINT plugin_invocation_pkey PRIMARY KEY (id);


--
-- Name: plugin_package_file plugin_package_file_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_package_file
    ADD CONSTRAINT plugin_package_file_pkey PRIMARY KEY (id);


--
-- Name: plugin_package plugin_package_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_package
    ADD CONSTRAINT plugin_package_pkey PRIMARY KEY (id);


--
-- Name: plugin_package_version plugin_package_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_package_version
    ADD CONSTRAINT plugin_package_version_pkey PRIMARY KEY (id);


--
-- Name: plugin_secret plugin_secret_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_secret
    ADD CONSTRAINT plugin_secret_pkey PRIMARY KEY (id);


--
-- Name: plugin_storage plugin_storage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plugin_storage
    ADD CONSTRAINT plugin_storage_pkey PRIMARY KEY (id);


--
-- Name: project_chat_session project_chat_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_chat_session
    ADD CONSTRAINT project_chat_session_pkey PRIMARY KEY (id);


--
-- Name: project project_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_pkey PRIMARY KEY (id);


--
-- Name: project_presenter_grant project_presenter_grant_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_presenter_grant
    ADD CONSTRAINT project_presenter_grant_pkey PRIMARY KEY (id);


--
-- Name: project_resource project_resource_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_resource
    ADD CONSTRAINT project_resource_pkey PRIMARY KEY (id);


--
-- Name: project_resource project_resource_project_id_resource_type_resource_ref_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_resource
    ADD CONSTRAINT project_resource_project_id_resource_type_resource_ref_key UNIQUE (project_id, resource_type, resource_ref);


--
-- Name: quick_action quick_action_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quick_action
    ADD CONSTRAINT quick_action_pkey PRIMARY KEY (id);


--
-- Name: runtime_profile runtime_profile_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runtime_profile
    ADD CONSTRAINT runtime_profile_pkey PRIMARY KEY (id);


--
-- Name: runtime_profile runtime_profile_protocol_family_check; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.runtime_profile
    ADD CONSTRAINT runtime_profile_protocol_family_check CHECK ((protocol_family = ANY (ARRAY['claude'::text, 'codebuddy'::text, 'codex'::text, 'copilot'::text, 'opencode'::text, 'codearts'::text, 'openclaw'::text, 'hermes'::text, 'pi'::text, 'cursor'::text, 'kimi'::text, 'reasonix'::text, 'dsh'::text, 'kiro'::text, 'antigravity'::text, 'qoder'::text, 'qoderclicn'::text, 'traecli'::text, 'deveco'::text, 'grok'::text, 'qwen'::text, 'qwenpaw'::text, 'mcode'::text, 'muse'::text, 'dim'::text, 'zeroclaw'::text]))) NOT VALID;


--
-- Name: runtime_profile runtime_profile_workspace_id_display_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.runtime_profile
    ADD CONSTRAINT runtime_profile_workspace_id_display_name_key UNIQUE (workspace_id, display_name);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: search_index_change search_index_change_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_index_change
    ADD CONSTRAINT search_index_change_pkey PRIMARY KEY (entity_type, entity_id);


--
-- Name: search_index_prune_mark search_index_prune_mark_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.search_index_prune_mark
    ADD CONSTRAINT search_index_prune_mark_pkey PRIMARY KEY (singleton);


--
-- Name: seat_capacity_outbox seat_capacity_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seat_capacity_outbox
    ADD CONSTRAINT seat_capacity_outbox_pkey PRIMARY KEY (operation_token);


--
-- Name: skill_file skill_file_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_file
    ADD CONSTRAINT skill_file_pkey PRIMARY KEY (id);


--
-- Name: skill_file skill_file_skill_id_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_file
    ADD CONSTRAINT skill_file_skill_id_path_key UNIQUE (skill_id, path);


--
-- Name: skill skill_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill
    ADD CONSTRAINT skill_pkey PRIMARY KEY (id);


--
-- Name: skill_to_label skill_to_label_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_to_label
    ADD CONSTRAINT skill_to_label_pkey PRIMARY KEY (skill_id, label_id);


--
-- Name: skill_usage_event skill_usage_event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_usage_event
    ADD CONSTRAINT skill_usage_event_pkey PRIMARY KEY (id);


--
-- Name: skill skill_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill
    ADD CONSTRAINT skill_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: squad_member squad_member_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.squad_member
    ADD CONSTRAINT squad_member_pkey PRIMARY KEY (id);


--
-- Name: squad_member squad_member_squad_id_member_type_member_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.squad_member
    ADD CONSTRAINT squad_member_squad_id_member_type_member_id_key UNIQUE (squad_id, member_type, member_id);


--
-- Name: squad squad_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.squad
    ADD CONSTRAINT squad_pkey PRIMARY KEY (id);


--
-- Name: sys_cron_executions sys_cron_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_cron_executions
    ADD CONSTRAINT sys_cron_executions_pkey PRIMARY KEY (id);


--
-- Name: task_message task_message_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_message
    ADD CONSTRAINT task_message_pkey PRIMARY KEY (id);


--
-- Name: task_supplement task_supplement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_supplement
    ADD CONSTRAINT task_supplement_pkey PRIMARY KEY (comment_id, task_id);


--
-- Name: task_token task_token_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_token
    ADD CONSTRAINT task_token_pkey PRIMARY KEY (id);


--
-- Name: task_usage_hourly_rollup_state task_usage_hourly_rollup_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_usage_hourly_rollup_state
    ADD CONSTRAINT task_usage_hourly_rollup_state_pkey PRIMARY KEY (id);


--
-- Name: task_usage task_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_usage
    ADD CONSTRAINT task_usage_pkey PRIMARY KEY (id);


--
-- Name: task_usage task_usage_task_id_provider_model_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_usage
    ADD CONSTRAINT task_usage_task_id_provider_model_key UNIQUE (task_id, provider, model);


--
-- Name: daemon_connection uq_daemon_agent; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daemon_connection
    ADD CONSTRAINT uq_daemon_agent UNIQUE (agent_id, daemon_id);


--
-- Name: issue uq_issue_workspace_number; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue
    ADD CONSTRAINT uq_issue_workspace_number UNIQUE (workspace_id, number);


--
-- Name: sys_cron_executions uq_sys_cron_execution; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sys_cron_executions
    ADD CONSTRAINT uq_sys_cron_execution UNIQUE (job_name, scope_kind, scope_id, plan_time);


--
-- Name: task_usage_hourly_dirty uq_task_usage_hourly_dirty_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_usage_hourly_dirty
    ADD CONSTRAINT uq_task_usage_hourly_dirty_key UNIQUE NULLS NOT DISTINCT (bucket_hour, workspace_id, runtime_id, agent_id, project_id, provider, model);


--
-- Name: task_usage_hourly uq_task_usage_hourly_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_usage_hourly
    ADD CONSTRAINT uq_task_usage_hourly_key UNIQUE NULLS NOT DISTINCT (bucket_hour, workspace_id, runtime_id, agent_id, project_id, provider, model);


--
-- Name: user_composio_connection user_composio_connection_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_composio_connection
    ADD CONSTRAINT user_composio_connection_pkey PRIMARY KEY (id);


--
-- Name: user_composio_connection user_composio_connection_user_id_connected_account_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_composio_connection
    ADD CONSTRAINT user_composio_connection_user_id_connected_account_id_key UNIQUE (user_id, connected_account_id);


--
-- Name: user user_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_email_key UNIQUE (email);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: vcs_commit_status vcs_commit_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vcs_commit_status
    ADD CONSTRAINT vcs_commit_status_pkey PRIMARY KEY (connection_id, sha, context);


--
-- Name: vcs_connection vcs_connection_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vcs_connection
    ADD CONSTRAINT vcs_connection_pkey PRIMARY KEY (id);


--
-- Name: vcs_connection vcs_connection_workspace_id_instance_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vcs_connection
    ADD CONSTRAINT vcs_connection_workspace_id_instance_url_key UNIQUE (workspace_id, instance_url);


--
-- Name: vcs_pull_request vcs_pull_request_connection_id_repo_owner_repo_name_pr_numb_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vcs_pull_request
    ADD CONSTRAINT vcs_pull_request_connection_id_repo_owner_repo_name_pr_numb_key UNIQUE (connection_id, repo_owner, repo_name, pr_number);


--
-- Name: vcs_pull_request vcs_pull_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vcs_pull_request
    ADD CONSTRAINT vcs_pull_request_pkey PRIMARY KEY (id);


--
-- Name: verification_code verification_code_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.verification_code
    ADD CONSTRAINT verification_code_pkey PRIMARY KEY (id);


--
-- Name: webhook_delivery webhook_delivery_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_delivery
    ADD CONSTRAINT webhook_delivery_pkey PRIMARY KEY (id);


--
-- Name: workspace_invitation workspace_invitation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitation
    ADD CONSTRAINT workspace_invitation_pkey PRIMARY KEY (id);


--
-- Name: workspace_mcp_server workspace_mcp_server_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_mcp_server
    ADD CONSTRAINT workspace_mcp_server_pkey PRIMARY KEY (id);


--
-- Name: workspace workspace_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace
    ADD CONSTRAINT workspace_pkey PRIMARY KEY (id);


--
-- Name: workspace_share_link workspace_share_link_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_share_link
    ADD CONSTRAINT workspace_share_link_pkey PRIMARY KEY (id);


--
-- Name: workspace workspace_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace
    ADD CONSTRAINT workspace_slug_key UNIQUE (slug);


--
-- Name: agent_invocation_target_agent_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX agent_invocation_target_agent_id_idx ON public.agent_invocation_target USING btree (agent_id);


--
-- Name: agent_invocation_target_target_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX agent_invocation_target_target_idx ON public.agent_invocation_target USING btree (target_type, target_id);


--
-- Name: agent_runtime_workspace_daemon_profile_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX agent_runtime_workspace_daemon_profile_key ON public.agent_runtime USING btree (workspace_id, daemon_id, profile_id) WHERE (profile_id IS NOT NULL);


--
-- Name: agent_runtime_workspace_daemon_provider_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX agent_runtime_workspace_daemon_provider_key ON public.agent_runtime USING btree (workspace_id, daemon_id, provider) WHERE (profile_id IS NULL);


--
-- Name: agent_system_identity_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX agent_system_identity_unique ON public.agent USING btree (workspace_id, owner_id, runtime_id, system_key) WHERE (system_key IS NOT NULL);


--
-- Name: agent_task_queue_originator_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX agent_task_queue_originator_user_id_idx ON public.agent_task_queue USING btree (originator_user_id) WHERE (originator_user_id IS NOT NULL);


--
-- Name: agent_task_queue_squad_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX agent_task_queue_squad_id_idx ON public.agent_task_queue USING btree (squad_id) WHERE (squad_id IS NOT NULL);


--
-- Name: agent_task_wakeup_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX agent_task_wakeup_active_idx ON public.agent_task_queue USING btree (((context ->> 'wakeup_id'::text)), ((status = ANY (ARRAY['running'::text, 'waiting_local_directory'::text, 'dispatched'::text]))) DESC, created_at DESC, id DESC) WHERE (((context ->> 'wakeup_id'::text) IS NOT NULL) AND (status = ANY (ARRAY['queued'::text, 'deferred'::text, 'dispatched'::text, 'running'::text, 'waiting_local_directory'::text])));


--
-- Name: agent_task_wakeup_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX agent_task_wakeup_lookup_idx ON public.agent_task_queue USING btree (((context ->> 'wakeup_id'::text)), created_at DESC) WHERE ((context ->> 'wakeup_id'::text) IS NOT NULL);


--
-- Name: agent_task_wakeup_terminal_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX agent_task_wakeup_terminal_idx ON public.agent_task_queue USING btree (((context ->> 'wakeup_id'::text)), created_at DESC, id DESC) WHERE (((context ->> 'wakeup_id'::text) IS NOT NULL) AND (status <> ALL (ARRAY['queued'::text, 'deferred'::text, 'dispatched'::text, 'running'::text, 'waiting_local_directory'::text])));


--
-- Name: agent_to_label_label_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX agent_to_label_label_idx ON public.agent_to_label USING btree (label_id);


--
-- Name: approval_record_approve_ws_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX approval_record_approve_ws_uniq ON public.approval_record USING btree (workspace_id, cr_id, stage, evidence_digest) WHERE (decision = 'approve'::text);


--
-- Name: channel_chat_context_generation_session_revision_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX channel_chat_context_generation_session_revision_idx ON public.channel_chat_context_generation USING btree (chat_session_id, revision);


--
-- Name: channel_typing_reaction_abandoned_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channel_typing_reaction_abandoned_idx ON public.channel_typing_reaction USING btree (abandoned_at) WHERE (abandoned_at IS NOT NULL);


--
-- Name: channel_typing_reaction_expiry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channel_typing_reaction_expiry_idx ON public.channel_typing_reaction USING btree (created_at, id) WHERE ((cleaned_at IS NULL) AND (abandoned_at IS NULL));


--
-- Name: channel_typing_reaction_gc_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channel_typing_reaction_gc_idx ON public.channel_typing_reaction USING btree (cleaned_at) WHERE (cleaned_at IS NOT NULL);


--
-- Name: channel_typing_reaction_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX channel_typing_reaction_id_idx ON public.channel_typing_reaction USING btree (id);


--
-- Name: channel_typing_reaction_quota_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX channel_typing_reaction_quota_idx ON public.channel_typing_reaction USING btree (workspace_id, quota_slot) WHERE ((cleaned_at IS NULL) AND (abandoned_at IS NULL));


--
-- Name: channel_typing_reaction_retry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX channel_typing_reaction_retry_idx ON public.channel_typing_reaction USING btree (retry_after, chat_session_id) WHERE (cleaned_at IS NULL);


--
-- Name: chat_session_private_creator_active_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX chat_session_private_creator_active_unique ON public.chat_session USING btree (project_id, creator_id) WHERE ((project_id IS NOT NULL) AND (status = 'active'::text) AND (kind = 'private'::text));


--
-- Name: chat_session_project_shared_active_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX chat_session_project_shared_active_unique ON public.chat_session USING btree (workspace_id, project_id) WHERE ((kind = 'project_shared'::text) AND (status = 'active'::text));


--
-- Name: client_usage_daily_activity_client_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX client_usage_daily_activity_client_user_idx ON public.client_usage_daily USING btree (activity_date, client_type, user_id);


--
-- Name: client_usage_daily_workspace_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX client_usage_daily_workspace_idx ON public.client_usage_daily USING btree (workspace_id) WHERE (workspace_id IS NOT NULL);


--
-- Name: comment_issue_resolved_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comment_issue_resolved_at_idx ON public.comment USING btree (issue_id, resolved_at);


--
-- Name: cr_sync_event_trace_spec_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cr_sync_event_trace_spec_idx ON public.cr_sync_event USING btree (workspace_id, ((payload ->> 'spec_id'::text)), occurred_at, id) WHERE (event_kind = 'trace'::text);


--
-- Name: cr_sync_event_workspace_dedup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cr_sync_event_workspace_dedup_idx ON public.cr_sync_event USING btree (workspace_id, cr_id, commit_sha, event_kind);


--
-- Name: cr_sync_event_ws_unprocessed_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cr_sync_event_ws_unprocessed_idx ON public.cr_sync_event USING btree (workspace_id, cr_id, received_at) WHERE (processed_at IS NULL);


--
-- Name: drift_finding_dedup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX drift_finding_dedup_idx ON public.drift_finding USING btree (workspace_id, repository_id, kind, COALESCE(spec_id, ''::text), ((evidence ->> 'commit_sha'::text)));


--
-- Name: drift_finding_keyset_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX drift_finding_keyset_idx ON public.drift_finding USING btree (workspace_id, status, found_at DESC, id DESC);


--
-- Name: github_pull_request_check_run_pr_ordinal_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX github_pull_request_check_run_pr_ordinal_idx ON public.github_pull_request_check_run USING btree (pr_id, ordinal);


--
-- Name: idx_activity_log_issue_keyset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_log_issue_keyset ON public.activity_log USING btree (issue_id, created_at DESC, id DESC);


--
-- Name: idx_activity_log_member_assignee_frequency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_log_member_assignee_frequency ON public.activity_log USING btree (workspace_id, actor_id, ((details ->> 'to_type'::text)), ((details ->> 'to_id'::text))) WHERE ((actor_type = 'member'::text) AND (action = 'assignee_changed'::text) AND ((details ->> 'to_type'::text) IS NOT NULL) AND ((details ->> 'to_id'::text) IS NOT NULL));


--
-- Name: idx_activity_log_squad_no_action_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_log_squad_no_action_task ON public.activity_log USING btree (issue_id, actor_id, ((details ->> 'task_id'::text))) WHERE ((actor_type = 'agent'::text) AND (action = 'squad_leader_evaluated'::text) AND ((details ->> 'outcome'::text) = 'no_action'::text));


--
-- Name: idx_agent_mcp_server_server; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_mcp_server_server ON public.agent_mcp_server USING btree (server_id);


--
-- Name: idx_agent_runtime_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_runtime_id ON public.agent USING btree (runtime_id);


--
-- Name: idx_agent_runtime_offline_last_seen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_runtime_offline_last_seen ON public.agent_runtime USING btree (last_seen_at, id) WHERE (status = 'offline'::text);


--
-- Name: idx_agent_runtime_online_last_seen; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_runtime_online_last_seen ON public.agent_runtime USING btree (last_seen_at) WHERE (status = 'online'::text);


--
-- Name: idx_agent_runtime_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_runtime_status ON public.agent_runtime USING btree (workspace_id, status);


--
-- Name: idx_agent_runtime_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_runtime_workspace ON public.agent_runtime USING btree (workspace_id);


--
-- Name: idx_agent_runtime_workspace_id_keyset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_runtime_workspace_id_keyset ON public.agent_runtime USING btree (workspace_id, id);


--
-- Name: idx_agent_skill_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_skill_agent ON public.agent_skill USING btree (agent_id);


--
-- Name: idx_agent_skill_skill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_skill_skill ON public.agent_skill USING btree (skill_id);


--
-- Name: idx_agent_task_queue_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_agent ON public.agent_task_queue USING btree (agent_id, status);


--
-- Name: idx_agent_task_queue_agent_id_keyset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_agent_id_keyset ON public.agent_task_queue USING btree (agent_id, id);


--
-- Name: idx_agent_task_queue_agent_terminal_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_agent_terminal_latest ON public.agent_task_queue USING btree (agent_id, completed_at DESC NULLS LAST, created_at DESC, id DESC) WHERE (status = ANY (ARRAY['completed'::text, 'failed'::text]));


--
-- Name: idx_agent_task_queue_autopilot_run_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_autopilot_run_created_at ON public.agent_task_queue USING btree (autopilot_run_id, created_at) WHERE (autopilot_run_id IS NOT NULL);


--
-- Name: idx_agent_task_queue_chat_pending_v3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_chat_pending_v3 ON public.agent_task_queue USING btree (chat_session_id, created_at DESC) WHERE ((chat_session_id IS NOT NULL) AND (status = ANY (ARRAY['queued'::text, 'dispatched'::text, 'running'::text, 'waiting_local_directory'::text, 'deferred'::text])));


--
-- Name: idx_agent_task_queue_chat_retired_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_chat_retired_session ON public.agent_task_queue USING btree (chat_session_id, retired_session_id) WHERE ((chat_session_id IS NOT NULL) AND (retired_session_id IS NOT NULL));


--
-- Name: idx_agent_task_queue_chat_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_chat_session ON public.agent_task_queue USING btree (chat_session_id, created_at DESC) WHERE (chat_session_id IS NOT NULL);


--
-- Name: idx_agent_task_queue_chat_terminal_resume; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_chat_terminal_resume ON public.agent_task_queue USING btree (chat_session_id, session_id, completed_at DESC) WHERE ((chat_session_id IS NOT NULL) AND (status = ANY (ARRAY['completed'::text, 'failed'::text, 'cancelled'::text])));


--
-- Name: idx_agent_task_queue_claim_candidates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_claim_candidates ON public.agent_task_queue USING btree (runtime_id, priority DESC, created_at) WHERE (status = 'queued'::text);


--
-- Name: idx_agent_task_queue_cr_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_cr_id ON public.agent_task_queue USING btree (cr_id) WHERE (cr_id IS NOT NULL);


--
-- Name: idx_agent_task_queue_deferred_fire; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_deferred_fire ON public.agent_task_queue USING btree (runtime_id, fire_at) WHERE (status = 'deferred'::text);


--
-- Name: idx_agent_task_queue_delegated_failure_evidence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_delegated_failure_evidence ON public.agent_task_queue USING btree (trigger_evidence_ref_id, created_at DESC, id DESC) WHERE (trigger_evidence_kind = 'delegated_failure'::text);


--
-- Name: idx_agent_task_queue_dispatched_reclaim_v2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_dispatched_reclaim_v2 ON public.agent_task_queue USING btree (runtime_id, dispatched_at, priority DESC) WHERE ((status = 'dispatched'::text) AND (started_at IS NULL));


--
-- Name: idx_agent_task_queue_escalation_for; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_escalation_for ON public.agent_task_queue USING btree (escalation_for_task_id) WHERE (escalation_for_task_id IS NOT NULL);


--
-- Name: idx_agent_task_queue_history_page; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_history_page ON public.agent_task_queue USING btree (agent_id, created_at DESC, id DESC) WHERE (NOT ((escalation_for_task_id IS NOT NULL) AND (started_at IS NULL) AND (status = ANY (ARRAY['deferred'::text, 'cancelled'::text]))));


--
-- Name: idx_agent_task_queue_issue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_issue_id ON public.agent_task_queue USING btree (issue_id);


--
-- Name: idx_agent_task_queue_issue_id_keyset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_issue_id_keyset ON public.agent_task_queue USING btree (issue_id, id);


--
-- Name: idx_agent_task_queue_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_parent ON public.agent_task_queue USING btree (parent_task_id);


--
-- Name: idx_agent_task_queue_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_pending ON public.agent_task_queue USING btree (agent_id, priority DESC, created_at) WHERE (status = ANY (ARRAY['queued'::text, 'dispatched'::text]));


--
-- Name: idx_agent_task_queue_pipeline_node_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_agent_task_queue_pipeline_node_active ON public.agent_task_queue USING btree (pipeline_node_run_id) WHERE ((pipeline_node_run_id IS NOT NULL) AND (status = ANY (ARRAY['queued'::text, 'deferred'::text, 'dispatched'::text, 'waiting_local_directory'::text, 'running'::text])));


--
-- Name: idx_agent_task_queue_pipeline_node_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_pipeline_node_run ON public.agent_task_queue USING btree (pipeline_node_run_id) WHERE (pipeline_node_run_id IS NOT NULL);


--
-- Name: idx_agent_task_queue_queued_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_queued_created_at ON public.agent_task_queue USING btree (created_at) WHERE (status = 'queued'::text);


--
-- Name: idx_agent_task_queue_running_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_running_started_at ON public.agent_task_queue USING btree (started_at) WHERE (status = 'running'::text);


--
-- Name: idx_agent_task_queue_runtime_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_runtime_id ON public.agent_task_queue USING btree (runtime_id, id);


--
-- Name: idx_agent_task_queue_runtime_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_runtime_pending ON public.agent_task_queue USING btree (runtime_id, priority DESC, created_at) WHERE (status = ANY (ARRAY['queued'::text, 'dispatched'::text]));


--
-- Name: idx_agent_task_queue_telemetry_started; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_telemetry_started ON public.agent_task_queue USING btree (started_at) WHERE (started_at IS NOT NULL);


--
-- Name: idx_agent_task_queue_terminal_completed_at_v2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_terminal_completed_at_v2 ON public.agent_task_queue USING btree (completed_at) WHERE (status = ANY (ARRAY['completed'::text, 'failed'::text, 'cancelled'::text]));


--
-- Name: idx_agent_task_queue_trigger_comment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_task_queue_trigger_comment_id ON public.agent_task_queue USING btree (trigger_comment_id) WHERE (trigger_comment_id IS NOT NULL);


--
-- Name: idx_agent_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_workspace ON public.agent USING btree (workspace_id);


--
-- Name: idx_agent_workspace_id_keyset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_workspace_id_keyset ON public.agent USING btree (workspace_id, id);


--
-- Name: idx_approval_continuation_record_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_approval_continuation_record_active ON public.agent_task_queue USING btree (trigger_evidence_ref_id) WHERE ((trigger_evidence_kind = 'approval_continuation'::text) AND (status = ANY (ARRAY['queued'::text, 'deferred'::text, 'dispatched'::text, 'waiting_local_directory'::text, 'running'::text])));


--
-- Name: idx_approval_continuation_workspace_cr_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_approval_continuation_workspace_cr_pending ON public.agent_task_queue USING btree (approval_workspace_id, cr_id) WHERE ((trigger_evidence_kind = 'approval_continuation'::text) AND (status = ANY (ARRAY['queued'::text, 'deferred'::text])));


--
-- Name: idx_approval_record_cr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_record_cr ON public.approval_record USING btree (cr_id, stage);


--
-- Name: idx_atq_maturity_report_history; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_atq_maturity_report_history ON public.agent_task_queue USING btree (project_id, completed_at DESC, id DESC) WHERE ((status = 'completed'::text) AND (project_id IS NOT NULL) AND ((result ->> 'schema'::text) = 'ai-first.maturity-report/v1'::text));


--
-- Name: idx_atq_project_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_atq_project_active ON public.agent_task_queue USING btree (project_id) WHERE ((status = ANY (ARRAY['dispatched'::text, 'running'::text, 'waiting_local_directory'::text])) AND (project_id IS NOT NULL));


--
-- Name: idx_attachment_chat_message; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachment_chat_message ON public.attachment USING btree (chat_message_id) WHERE (chat_message_id IS NOT NULL);


--
-- Name: idx_attachment_chat_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachment_chat_session ON public.attachment USING btree (chat_session_id) WHERE (chat_session_id IS NOT NULL);


--
-- Name: idx_attachment_comment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachment_comment ON public.attachment USING btree (comment_id) WHERE (comment_id IS NOT NULL);


--
-- Name: idx_attachment_issue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachment_issue ON public.attachment USING btree (issue_id) WHERE (issue_id IS NOT NULL);


--
-- Name: idx_attachment_source_context; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachment_source_context ON public.attachment USING btree (source_context_id) WHERE (source_context_id IS NOT NULL);


--
-- Name: idx_attachment_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachment_task ON public.attachment USING btree (task_id) WHERE (task_id IS NOT NULL);


--
-- Name: idx_attachment_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachment_workspace ON public.attachment USING btree (workspace_id);


--
-- Name: idx_autopilot_assignee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_assignee ON public.autopilot USING btree (assignee_id);


--
-- Name: idx_autopilot_assignee_type_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_assignee_type_id ON public.autopilot USING btree (assignee_type, assignee_id);


--
-- Name: idx_autopilot_collaborator_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_collaborator_user ON public.autopilot_collaborator USING btree (user_type, user_id);


--
-- Name: idx_autopilot_project; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_project ON public.autopilot USING btree (project_id);


--
-- Name: idx_autopilot_quota_reservation_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_quota_reservation_state ON public.autopilot_quota_reservation USING btree (state, created_at) WHERE (state = 'reserved'::text);


--
-- Name: idx_autopilot_rule_version_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_rule_version_active ON public.autopilot_rule_version USING btree (workspace_id, autopilot_id, created_at DESC);


--
-- Name: idx_autopilot_run_autopilot; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_run_autopilot ON public.autopilot_run USING btree (autopilot_id, created_at DESC);


--
-- Name: idx_autopilot_run_issue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_run_issue ON public.autopilot_run USING btree (issue_id) WHERE (issue_id IS NOT NULL);


--
-- Name: idx_autopilot_run_squad_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_run_squad_id ON public.autopilot_run USING btree (squad_id) WHERE (squad_id IS NOT NULL);


--
-- Name: idx_autopilot_run_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_run_status ON public.autopilot_run USING btree (autopilot_id, status) WHERE (status = ANY (ARRAY['issue_created'::text, 'running'::text]));


--
-- Name: idx_autopilot_run_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_run_task_id ON public.autopilot_run USING btree (task_id);


--
-- Name: idx_autopilot_subscriber_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_subscriber_user ON public.autopilot_subscriber USING btree (user_type, user_id);


--
-- Name: idx_autopilot_trigger_autopilot; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_trigger_autopilot ON public.autopilot_trigger USING btree (autopilot_id);


--
-- Name: idx_autopilot_trigger_next_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_trigger_next_run ON public.autopilot_trigger USING btree (next_run_at) WHERE ((enabled = true) AND (kind = 'schedule'::text));


--
-- Name: idx_autopilot_trigger_webhook_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_autopilot_trigger_webhook_token ON public.autopilot_trigger USING btree (webhook_token) WHERE ((kind = 'webhook'::text) AND (webhook_token IS NOT NULL));


--
-- Name: idx_autopilot_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_autopilot_workspace ON public.autopilot USING btree (workspace_id);


--
-- Name: idx_channel_binding_token_installation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_binding_token_installation ON public.channel_binding_token USING btree (installation_id, expires_at);


--
-- Name: idx_channel_chat_session_binding_active_route; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_channel_chat_session_binding_active_route ON public.channel_chat_session_binding USING btree (installation_id, channel_chat_id) WHERE (retired_at IS NULL);


--
-- Name: idx_channel_inbound_audit_installation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_inbound_audit_installation ON public.channel_inbound_audit USING btree (installation_id, received_at DESC);


--
-- Name: idx_channel_inbound_audit_reason; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_inbound_audit_reason ON public.channel_inbound_audit USING btree (drop_reason, received_at DESC);


--
-- Name: idx_channel_inbound_dedup_received; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_inbound_dedup_received ON public.channel_inbound_message_dedup USING btree (received_at);


--
-- Name: idx_channel_installation_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_installation_agent ON public.channel_installation USING btree (agent_id);


--
-- Name: idx_channel_installation_lease; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_installation_lease ON public.channel_installation USING btree (ws_lease_expires_at) WHERE (status = 'active'::text);


--
-- Name: idx_channel_installation_type_appid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_channel_installation_type_appid ON public.channel_installation USING btree (channel_type, ((config ->> 'app_id'::text)));


--
-- Name: idx_channel_installation_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_installation_workspace ON public.channel_installation USING btree (workspace_id);


--
-- Name: idx_channel_media_pending_object_claim; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_media_pending_object_claim ON public.channel_media_pending_object USING btree (state, next_attempt_at);


--
-- Name: idx_channel_media_pending_object_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_media_pending_object_due ON public.channel_media_pending_object USING btree (next_attempt_at);


--
-- Name: idx_channel_outbound_card_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_outbound_card_session ON public.channel_outbound_card_message USING btree (chat_session_id, created_at DESC);


--
-- Name: idx_channel_outbound_card_task; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_channel_outbound_card_task ON public.channel_outbound_card_message USING btree (task_id) WHERE (task_id IS NOT NULL);


--
-- Name: idx_channel_outbound_message_binding_route; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_outbound_message_binding_route ON public.channel_outbound_message USING btree (binding_id, route_revision);


--
-- Name: idx_channel_outbound_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_channel_outbound_message_id ON public.channel_outbound_message USING btree (installation_id, channel_message_id);


--
-- Name: idx_channel_reply_delivery_binding; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_reply_delivery_binding ON public.channel_reply_delivery USING btree (binding_id);


--
-- Name: idx_channel_reply_delivery_installation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_reply_delivery_installation ON public.channel_reply_delivery USING btree (installation_id);


--
-- Name: idx_channel_reply_delivery_turn; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_channel_reply_delivery_turn ON public.channel_reply_delivery USING btree (turn_id);


--
-- Name: idx_channel_task_delivery_binding; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_task_delivery_binding ON public.channel_task_delivery USING btree (binding_id);


--
-- Name: idx_channel_task_delivery_installation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_task_delivery_installation ON public.channel_task_delivery USING btree (installation_id);


--
-- Name: idx_channel_user_binding_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_user_binding_user ON public.channel_user_binding USING btree (multica_user_id, workspace_id);


--
-- Name: idx_channel_user_binding_workspace_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_channel_user_binding_workspace_user ON public.channel_user_binding USING btree (workspace_id, channel_user_id);


--
-- Name: idx_chat_draft_restore_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_draft_restore_session ON public.chat_draft_restore USING btree (chat_session_id);


--
-- Name: idx_chat_draft_restore_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_draft_restore_task_id ON public.chat_draft_restore USING btree (task_id);


--
-- Name: idx_chat_idempotency_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_idempotency_created ON public.chat_idempotency USING btree (created_at);


--
-- Name: idx_chat_message_assistant_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_message_assistant_task ON public.chat_message USING btree (task_id, created_at DESC) WHERE (role = 'assistant'::text);


--
-- Name: idx_chat_message_input_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_message_input_owner ON public.chat_message USING btree (task_id, created_at) WHERE (role = 'user'::text);


--
-- Name: idx_chat_message_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_message_session ON public.chat_message USING btree (chat_session_id, created_at);


--
-- Name: idx_chat_pinned_agent_user_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_pinned_agent_user_ws ON public.chat_pinned_agent USING btree (workspace_id, user_id, "position");


--
-- Name: idx_chat_session_agent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_session_agent_id ON public.chat_session USING btree (agent_id);


--
-- Name: idx_chat_session_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_session_creator ON public.chat_session USING btree (creator_id, workspace_id);


--
-- Name: idx_chat_session_pinned; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_session_pinned ON public.chat_session USING btree (creator_id, workspace_id, pinned_at DESC) WHERE (pinned_at IS NOT NULL);


--
-- Name: idx_chat_session_project; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_session_project ON public.chat_session USING btree (project_id) WHERE (project_id IS NOT NULL);


--
-- Name: idx_chat_session_project_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_session_project_creator ON public.chat_session USING btree (project_id, creator_id) WHERE (project_id IS NOT NULL);


--
-- Name: idx_chat_session_runtime_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_session_runtime_id ON public.chat_session USING btree (runtime_id) WHERE (runtime_id IS NOT NULL);


--
-- Name: idx_chat_session_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_session_workspace ON public.chat_session USING btree (workspace_id);


--
-- Name: idx_comment_delegated_failure_unsettled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comment_delegated_failure_unsettled ON public.comment USING btree (created_at, id) WHERE ((author_type = 'system'::text) AND (type = 'progress_update'::text) AND (source_task_id IS NOT NULL) AND (recovery_settled_at IS NULL));


--
-- Name: idx_comment_issue_keyset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comment_issue_keyset ON public.comment USING btree (issue_id, created_at DESC, id DESC);


--
-- Name: idx_comment_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comment_parent_id ON public.comment USING btree (parent_id) WHERE (parent_id IS NOT NULL);


--
-- Name: idx_comment_reaction_comment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comment_reaction_comment_id ON public.comment_reaction USING btree (comment_id);


--
-- Name: idx_comment_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comment_workspace ON public.comment USING btree (workspace_id);


--
-- Name: idx_comment_workspace_issue_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comment_workspace_issue_parent ON public.comment USING btree (workspace_id, issue_id, parent_id) WHERE (parent_id IS NOT NULL);


--
-- Name: idx_contact_sales_inquiry_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_sales_inquiry_created ON public.contact_sales_inquiry USING btree (created_at DESC);


--
-- Name: idx_contact_sales_inquiry_email_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contact_sales_inquiry_email_created ON public.contact_sales_inquiry USING btree (business_email, created_at DESC);


--
-- Name: idx_cr_needs_reconcile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cr_needs_reconcile ON public.cr USING btree (needs_reconcile) WHERE needs_reconcile;


--
-- Name: idx_cr_workspace_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cr_workspace_status ON public.cr USING btree (workspace_id, status);


--
-- Name: idx_daemon_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_daemon_token_hash ON public.daemon_token USING btree (token_hash);


--
-- Name: idx_daemon_token_workspace_daemon; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daemon_token_workspace_daemon ON public.daemon_token USING btree (workspace_id, daemon_id);


--
-- Name: idx_dingtalk_bot_identity_installation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_dingtalk_bot_identity_installation ON public.dingtalk_bot_identity USING btree (installation_id);


--
-- Name: idx_dingtalk_bot_identity_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dingtalk_bot_identity_workspace ON public.dingtalk_bot_identity USING btree (workspace_id);


--
-- Name: idx_dingtalk_group_presence_installation_conversation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_dingtalk_group_presence_installation_conversation ON public.dingtalk_group_presence USING btree (installation_id, conversation_id);


--
-- Name: idx_dingtalk_group_presence_workspace_activity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dingtalk_group_presence_workspace_activity ON public.dingtalk_group_presence USING btree (workspace_id, last_active_at DESC NULLS LAST, installation_id, conversation_id);


--
-- Name: idx_dingtalk_group_route_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_dingtalk_group_route_id_unique ON public.dingtalk_group_route USING btree (id);


--
-- Name: idx_dingtalk_group_route_installation_conversation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_dingtalk_group_route_installation_conversation ON public.dingtalk_group_route USING btree (installation_id, conversation_id);


--
-- Name: idx_dingtalk_group_route_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dingtalk_group_route_workspace ON public.dingtalk_group_route USING btree (workspace_id);


--
-- Name: idx_feedback_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feedback_user_created ON public.feedback USING btree (user_id, created_at DESC);


--
-- Name: idx_github_installation_installation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_github_installation_installation_id ON public.github_installation USING btree (installation_id);


--
-- Name: idx_github_installation_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_github_installation_workspace ON public.github_installation USING btree (workspace_id);


--
-- Name: idx_github_pending_check_suite_received_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_github_pending_check_suite_received_at ON public.github_pending_check_suite USING btree (received_at);


--
-- Name: idx_github_pr_check_suite_aggregate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_github_pr_check_suite_aggregate ON public.github_pull_request_check_suite USING btree (pr_id, head_sha, app_id, updated_at DESC);


--
-- Name: idx_github_pull_request_head_sha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_github_pull_request_head_sha ON public.github_pull_request USING btree (head_sha);


--
-- Name: idx_github_pull_request_pr_owner_repo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_github_pull_request_pr_owner_repo ON public.github_pull_request USING btree (pr_number, repo_owner, repo_name);


--
-- Name: idx_github_pull_request_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_github_pull_request_workspace ON public.github_pull_request USING btree (workspace_id);


--
-- Name: idx_inbox_active_by_issue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inbox_active_by_issue ON public.inbox_item USING btree (workspace_id, recipient_type, recipient_id, issue_id) WHERE (archived = false);


--
-- Name: idx_inbox_item_issue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inbox_item_issue_id ON public.inbox_item USING btree (issue_id);


--
-- Name: idx_inbox_recipient; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inbox_recipient ON public.inbox_item USING btree (recipient_type, recipient_id, read);


--
-- Name: idx_inbox_recipient_archived_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inbox_recipient_archived_created ON public.inbox_item USING btree (workspace_id, recipient_type, recipient_id, archived, created_at DESC);


--
-- Name: idx_invitation_invitee_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invitation_invitee_email ON public.workspace_invitation USING btree (invitee_email) WHERE (status = 'pending'::text);


--
-- Name: idx_invitation_invitee_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invitation_invitee_user ON public.workspace_invitation USING btree (invitee_user_id) WHERE (status = 'pending'::text);


--
-- Name: idx_invitation_unique_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_invitation_unique_pending ON public.workspace_invitation USING btree (workspace_id, invitee_email) WHERE (status = 'pending'::text);


--
-- Name: idx_issue_assignee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_assignee ON public.issue USING btree (assignee_type, assignee_id);


--
-- Name: idx_issue_context_refs_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_context_refs_gin ON public.issue USING gin (context_refs jsonb_path_ops);


--
-- Name: idx_issue_dependency_depends_on_issue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_dependency_depends_on_issue_id ON public.issue_dependency USING btree (depends_on_issue_id);


--
-- Name: idx_issue_dependency_issue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_dependency_issue_id ON public.issue_dependency USING btree (issue_id);


--
-- Name: idx_issue_duplicate_of; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_duplicate_of ON public.issue USING btree (duplicate_of_issue_id) WHERE (duplicate_of_issue_id IS NOT NULL);


--
-- Name: idx_issue_first_executed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_first_executed_at ON public.issue USING btree (workspace_id, first_executed_at) WHERE (first_executed_at IS NOT NULL);


--
-- Name: idx_issue_metadata_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_metadata_gin ON public.issue USING gin (metadata jsonb_path_ops);


--
-- Name: idx_issue_origin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_origin ON public.issue USING btree (origin_type, origin_id) WHERE (origin_type IS NOT NULL);


--
-- Name: idx_issue_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_parent ON public.issue USING btree (parent_issue_id);


--
-- Name: idx_issue_pr_automation_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_pr_automation_workspace ON public.issue_pr_automation USING btree (workspace_id);


--
-- Name: idx_issue_project; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_project ON public.issue USING btree (project_id);


--
-- Name: idx_issue_project_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_project_status ON public.issue USING btree (project_id, workspace_id, status);


--
-- Name: idx_issue_properties_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_properties_gin ON public.issue USING gin (properties jsonb_path_ops);


--
-- Name: idx_issue_property_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_property_workspace ON public.issue_property USING btree (workspace_id);


--
-- Name: idx_issue_property_ws_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_issue_property_ws_name ON public.issue_property USING btree (workspace_id, lower(name));


--
-- Name: idx_issue_pull_request_exclusion_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_pull_request_exclusion_workspace ON public.issue_pull_request_exclusion USING btree (workspace_id);


--
-- Name: idx_issue_pull_request_pr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_pull_request_pr ON public.issue_pull_request USING btree (pull_request_id);


--
-- Name: idx_issue_reaction_issue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_reaction_issue_id ON public.issue_reaction USING btree (issue_id);


--
-- Name: idx_issue_source_context_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_issue_source_context_id ON public.issue_source_context USING btree (id);


--
-- Name: idx_issue_source_context_issue; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_issue_source_context_issue ON public.issue_source_context USING btree (issue_id) WHERE ((state = 'attached'::text) AND (issue_id IS NOT NULL));


--
-- Name: idx_issue_source_context_object_intent_context; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_source_context_object_intent_context ON public.issue_source_context_object_intent USING btree (source_context_id);


--
-- Name: idx_issue_source_context_object_intent_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_source_context_object_intent_due ON public.issue_source_context_object_intent USING btree (next_attempt_at) WHERE (state = ANY (ARRAY['pending'::text, 'deleting'::text]));


--
-- Name: idx_issue_source_context_object_intent_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_issue_source_context_object_intent_key ON public.issue_source_context_object_intent USING btree (storage_key);


--
-- Name: idx_issue_source_context_origin_task; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_issue_source_context_origin_task ON public.issue_source_context USING btree (origin_task_id) WHERE ((state = 'pending'::text) AND (origin_task_id IS NOT NULL));


--
-- Name: idx_issue_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_status ON public.issue USING btree (workspace_id, status);


--
-- Name: idx_issue_status_workspace_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_issue_status_workspace_key ON public.issue_status USING btree (workspace_id, key);


--
-- Name: idx_issue_status_workspace_name_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_issue_status_workspace_name_active ON public.issue_status USING btree (workspace_id, lower(name)) WHERE (archived_at IS NULL);


--
-- Name: idx_issue_subscriber_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_subscriber_user ON public.issue_subscriber USING btree (user_type, user_id);


--
-- Name: idx_issue_title_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_title_trgm ON public.issue USING gin (lower(title) public.gin_trgm_ops);


--
-- Name: idx_issue_triage_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_triage_state ON public.issue USING btree (workspace_id, created_at) WHERE (triage_state IS NOT NULL);


--
-- Name: idx_issue_vcs_pull_request_pr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_vcs_pull_request_pr ON public.issue_vcs_pull_request USING btree (pull_request_id);


--
-- Name: idx_issue_view_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_view_owner ON public.issue_view USING btree (workspace_id, scope_type, scope_id, owner_id);


--
-- Name: idx_issue_view_shared; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_view_shared ON public.issue_view USING btree (workspace_id, scope_type, scope_id) WHERE (visibility = 'workspace'::text);


--
-- Name: idx_issue_workflow_workspace_default; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_issue_workflow_workspace_default ON public.issue_workflow USING btree (workspace_id) WHERE is_default;


--
-- Name: idx_issue_workflow_workspace_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_issue_workflow_workspace_name ON public.issue_workflow USING btree (workspace_id, lower(name));


--
-- Name: idx_issue_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_workspace ON public.issue USING btree (workspace_id);


--
-- Name: idx_issue_workspace_assignee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_workspace_assignee ON public.issue USING btree (workspace_id, assignee_type, assignee_id);


--
-- Name: idx_issue_workspace_id_keyset; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_workspace_id_keyset ON public.issue USING btree (workspace_id, id);


--
-- Name: idx_issue_workspace_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_workspace_parent ON public.issue USING btree (workspace_id, parent_issue_id);


--
-- Name: idx_issue_workspace_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_workspace_position ON public.issue USING btree (workspace_id, "position", created_at DESC, id DESC);


--
-- Name: idx_issue_workspace_status_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_issue_workspace_status_position ON public.issue USING btree (workspace_id, status, "position");


--
-- Name: idx_lark_binding_token_installation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_binding_token_installation ON public.lark_binding_token USING btree (installation_id, expires_at);


--
-- Name: idx_lark_inbound_audit_installation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_inbound_audit_installation ON public.lark_inbound_audit USING btree (installation_id, received_at DESC);


--
-- Name: idx_lark_inbound_audit_reason; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_inbound_audit_reason ON public.lark_inbound_audit USING btree (drop_reason, received_at DESC);


--
-- Name: idx_lark_inbound_dedup_received; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_inbound_dedup_received ON public.lark_inbound_message_dedup USING btree (received_at);


--
-- Name: idx_lark_installation_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_installation_agent ON public.lark_installation USING btree (agent_id);


--
-- Name: idx_lark_installation_lease; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_installation_lease ON public.lark_installation USING btree (ws_lease_expires_at) WHERE (status = 'active'::text);


--
-- Name: idx_lark_installation_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_installation_workspace ON public.lark_installation USING btree (workspace_id);


--
-- Name: idx_lark_outbound_card_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_outbound_card_session ON public.lark_outbound_card_message USING btree (chat_session_id, created_at DESC);


--
-- Name: idx_lark_outbound_card_task; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_lark_outbound_card_task ON public.lark_outbound_card_message USING btree (task_id) WHERE (task_id IS NOT NULL);


--
-- Name: idx_lark_user_binding_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_user_binding_user ON public.lark_user_binding USING btree (multica_user_id, workspace_id);


--
-- Name: idx_lark_user_binding_workspace_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lark_user_binding_workspace_open ON public.lark_user_binding USING btree (workspace_id, lark_open_id);


--
-- Name: idx_maintenance_job_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_maintenance_job_active ON public.maintenance_job USING btree (job_type, scope_key) WHERE (status = ANY (ARRAY['ready'::text, 'paused'::text]));


--
-- Name: idx_maintenance_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_maintenance_job_id ON public.maintenance_job USING btree (id);


--
-- Name: idx_maintenance_job_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_maintenance_job_idempotency ON public.maintenance_job USING btree (idempotency_key);


--
-- Name: idx_member_user_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_user_workspace ON public.member USING btree (user_id, workspace_id);


--
-- Name: idx_member_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_workspace ON public.member USING btree (workspace_id);


--
-- Name: idx_one_pending_task_per_issue_agent_thread; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_one_pending_task_per_issue_agent_thread ON public.agent_task_queue USING btree (issue_id, agent_id, COALESCE(comment_thread_id, '00000000-0000-0000-0000-000000000000'::uuid)) WHERE ((status = ANY (ARRAY['queued'::text, 'dispatched'::text])) OR ((status = 'deferred'::text) AND ((context ->> 'channel_issue_media_pending'::text) = 'true'::text)));


--
-- Name: idx_pat_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_pat_token_hash ON public.personal_access_token USING btree (token_hash);


--
-- Name: idx_pat_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pat_user ON public.personal_access_token USING btree (user_id, revoked);


--
-- Name: idx_pinned_item_user_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pinned_item_user_ws ON public.pinned_item USING btree (workspace_id, user_id, "position");


--
-- Name: idx_pipeline_node_run_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pipeline_node_run_run ON public.pipeline_node_run USING btree (run_id);


--
-- Name: idx_pipeline_node_run_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pipeline_node_run_status ON public.pipeline_node_run USING btree (status) WHERE (status = ANY (ARRAY['running'::text, 'blocked'::text]));


--
-- Name: idx_pipeline_run_architecture_active_cr; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_pipeline_run_architecture_active_cr ON public.pipeline_run USING btree (workspace_id, pipeline_id, cr_id) WHERE ((cr_id IS NOT NULL) AND (status = ANY (ARRAY['running'::text, 'waiting_approval'::text])));


--
-- Name: idx_pipeline_run_cr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pipeline_run_cr ON public.pipeline_run USING btree (cr_id) WHERE (cr_id IS NOT NULL);


--
-- Name: idx_pipeline_run_promotion_active_issue; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_pipeline_run_promotion_active_issue ON public.pipeline_run USING btree (workspace_id, issue_id) WHERE ((pipeline_id = 'requirement-authoring'::text) AND (status = ANY (ARRAY['running'::text, 'waiting_approval'::text])));


--
-- Name: idx_pipeline_run_workspace_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pipeline_run_workspace_status ON public.pipeline_run USING btree (workspace_id, status);


--
-- Name: idx_plugin_hook_schedule_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plugin_hook_schedule_enabled ON public.plugin_hook_schedule USING btree (id) WHERE enabled;


--
-- Name: idx_plugin_hook_schedule_installation_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_plugin_hook_schedule_installation_key ON public.plugin_hook_schedule USING btree (installation_id, hook_key);


--
-- Name: idx_plugin_installation_package_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plugin_installation_package_version ON public.plugin_installation USING btree (package_version_id);


--
-- Name: idx_plugin_installation_workspace_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_plugin_installation_workspace_key ON public.plugin_installation USING btree (workspace_id, plugin_key);


--
-- Name: idx_plugin_invocation_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plugin_invocation_created_at ON public.plugin_invocation USING btree (created_at);


--
-- Name: idx_plugin_invocation_installation_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plugin_invocation_installation_created ON public.plugin_invocation USING btree (installation_id, created_at DESC);


--
-- Name: idx_plugin_package_file_path; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_plugin_package_file_path ON public.plugin_package_file USING btree (version_id, path);


--
-- Name: idx_plugin_package_version_package; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plugin_package_version_package ON public.plugin_package_version USING btree (package_id, created_at DESC);


--
-- Name: idx_plugin_package_version_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_plugin_package_version_unique ON public.plugin_package_version USING btree (package_id, version);


--
-- Name: idx_plugin_package_workspace_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_plugin_package_workspace_key ON public.plugin_package USING btree (workspace_id, plugin_key);


--
-- Name: idx_plugin_secret_installation_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_plugin_secret_installation_key ON public.plugin_secret USING btree (installation_id, key);


--
-- Name: idx_plugin_storage_scope_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_plugin_storage_scope_key ON public.plugin_storage USING btree (installation_id, scope_type, scope_id, key);


--
-- Name: idx_project_description_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_description_trgm ON public.project USING gin (lower(COALESCE(description, ''::text)) public.gin_trgm_ops);


--
-- Name: idx_project_resource_project; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_resource_project ON public.project_resource USING btree (project_id, "position");


--
-- Name: idx_project_resource_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_resource_workspace ON public.project_resource USING btree (workspace_id);


--
-- Name: idx_project_title_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_title_trgm ON public.project USING gin (lower(title) public.gin_trgm_ops);


--
-- Name: idx_project_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_project_workspace ON public.project USING btree (workspace_id);


--
-- Name: idx_quick_action_workspace_status_usage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_quick_action_workspace_status_usage ON public.quick_action USING btree (workspace_id, status, use_count DESC);


--
-- Name: idx_runtime_profile_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_runtime_profile_workspace ON public.runtime_profile USING btree (workspace_id);


--
-- Name: idx_search_index_change_changed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_search_index_change_changed_at ON public.search_index_change USING btree (changed_at);


--
-- Name: idx_search_index_change_workspace_xid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_search_index_change_workspace_xid ON public.search_index_change USING btree (workspace_id, change_xid, entity_type, entity_id);


--
-- Name: idx_seat_capacity_outbox_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_seat_capacity_outbox_due ON public.seat_capacity_outbox USING btree (next_attempt_at, created_at) WHERE (dead_lettered_at IS NULL);


--
-- Name: idx_seat_capacity_outbox_share_join; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_seat_capacity_outbox_share_join ON public.seat_capacity_outbox USING btree (workspace_id, share_link_id, user_id) WHERE ((share_link_id IS NOT NULL) AND (user_id IS NOT NULL));


--
-- Name: idx_skill_file_skill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_skill_file_skill ON public.skill_file USING btree (skill_id);


--
-- Name: idx_skill_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_skill_workspace ON public.skill USING btree (workspace_id);


--
-- Name: idx_squad_member_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_squad_member_entity ON public.squad_member USING btree (member_type, member_id);


--
-- Name: idx_squad_member_squad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_squad_member_squad ON public.squad_member USING btree (squad_id);


--
-- Name: idx_squad_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_squad_workspace ON public.squad USING btree (workspace_id);


--
-- Name: idx_sys_cron_exec_failed_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sys_cron_exec_failed_recent ON public.sys_cron_executions USING btree (job_name, plan_time DESC) WHERE (status = 'FAILED'::text);


--
-- Name: idx_sys_cron_exec_finished; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sys_cron_exec_finished ON public.sys_cron_executions USING btree (finished_at) WHERE (status = ANY (ARRAY['SUCCESS'::text, 'FAILED'::text]));


--
-- Name: idx_sys_cron_exec_running_stale; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sys_cron_exec_running_stale ON public.sys_cron_executions USING btree (stale_after) WHERE (status = 'RUNNING'::text);


--
-- Name: idx_task_chat_finalize_deferred; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_chat_finalize_deferred ON public.agent_task_queue USING btree (chat_finalize_deferred_at) WHERE (chat_finalize_deferred_at IS NOT NULL);


--
-- Name: idx_task_message_task_id_seq; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_message_task_id_seq ON public.task_message USING btree (task_id, seq);


--
-- Name: idx_task_token_agent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_token_agent_id ON public.task_token USING btree (agent_id);


--
-- Name: idx_task_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_task_token_hash ON public.task_token USING btree (token_hash);


--
-- Name: idx_task_token_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_token_task ON public.task_token USING btree (task_id);


--
-- Name: idx_task_token_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_token_workspace_id ON public.task_token USING btree (workspace_id);


--
-- Name: idx_task_usage_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_usage_created_at ON public.task_usage USING btree (created_at);


--
-- Name: idx_task_usage_created_at_legacy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_usage_created_at_legacy ON public.task_usage USING btree (created_at) WHERE (updated_at IS NULL);


--
-- Name: idx_task_usage_hourly_dirty_enqueued_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_usage_hourly_dirty_enqueued_at ON public.task_usage_hourly_dirty USING btree (enqueued_at);


--
-- Name: idx_task_usage_hourly_runtime_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_usage_hourly_runtime_time ON public.task_usage_hourly USING btree (runtime_id, bucket_hour DESC);


--
-- Name: idx_task_usage_hourly_workspace_agent_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_usage_hourly_workspace_agent_time ON public.task_usage_hourly USING btree (workspace_id, agent_id, bucket_hour DESC);


--
-- Name: idx_task_usage_hourly_workspace_project_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_usage_hourly_workspace_project_time ON public.task_usage_hourly USING btree (workspace_id, project_id, bucket_hour DESC) WHERE (project_id IS NOT NULL);


--
-- Name: idx_task_usage_hourly_workspace_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_usage_hourly_workspace_time ON public.task_usage_hourly USING btree (workspace_id, bucket_hour DESC);


--
-- Name: idx_task_usage_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_usage_task_id ON public.task_usage USING btree (task_id);


--
-- Name: idx_task_usage_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_task_usage_updated_at ON public.task_usage USING btree (updated_at);


--
-- Name: idx_user_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_created_at ON public."user" USING btree (created_at);


--
-- Name: idx_vcs_commit_status_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vcs_commit_status_lookup ON public.vcs_commit_status USING btree (connection_id, sha);


--
-- Name: idx_vcs_connection_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vcs_connection_workspace ON public.vcs_connection USING btree (workspace_id);


--
-- Name: idx_vcs_pull_request_connection; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vcs_pull_request_connection ON public.vcs_pull_request USING btree (connection_id);


--
-- Name: idx_vcs_pull_request_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vcs_pull_request_workspace ON public.vcs_pull_request USING btree (workspace_id);


--
-- Name: idx_verification_code_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_code_email ON public.verification_code USING btree (email, used, expires_at);


--
-- Name: idx_wakeup_event_issue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wakeup_event_issue ON public.issue_wakeup USING btree (issue_id) WHERE (enabled AND (kind = 'event'::text));


--
-- Name: idx_wakeup_workspace_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wakeup_workspace_enabled ON public.issue_wakeup USING btree (workspace_id, issue_id) WHERE enabled;


--
-- Name: idx_webhook_delivery_autopilot; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_delivery_autopilot ON public.webhook_delivery USING btree (autopilot_id, created_at DESC);


--
-- Name: idx_webhook_delivery_dedupe; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_webhook_delivery_dedupe ON public.webhook_delivery USING btree (trigger_id, dedupe_key) WHERE ((dedupe_key IS NOT NULL) AND (status <> ALL (ARRAY['rejected'::text, 'failed'::text])));


--
-- Name: idx_webhook_delivery_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_delivery_queue ON public.webhook_delivery USING btree (available_at, created_at) WHERE (status = 'queued'::text);


--
-- Name: idx_webhook_delivery_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_delivery_run ON public.webhook_delivery USING btree (autopilot_run_id) WHERE (autopilot_run_id IS NOT NULL);


--
-- Name: idx_workspace_mcp_server_workspace_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_workspace_mcp_server_workspace_name ON public.workspace_mcp_server USING btree (workspace_id, name);


--
-- Name: issue_child_event_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX issue_child_event_id_idx ON public.issue_child_event USING btree (id);


--
-- Name: issue_child_event_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX issue_child_event_pending_idx ON public.issue_child_event USING btree (parent_id, created_at) WHERE (processed_at IS NULL);


--
-- Name: issue_label_workspace_type_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX issue_label_workspace_type_idx ON public.issue_label USING btree (workspace_id, resource_type);


--
-- Name: issue_label_workspace_type_name_lower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX issue_label_workspace_type_name_lower_idx ON public.issue_label USING btree (workspace_id, resource_type, lower(name));


--
-- Name: issue_project_chat_session_origin_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX issue_project_chat_session_origin_uidx ON public.issue USING btree (workspace_id, origin_id) WHERE ((origin_type = 'project_chat'::text) AND (origin_id IS NOT NULL));


--
-- Name: issue_project_discussion_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX issue_project_discussion_unique ON public.issue USING btree (project_id) WHERE (origin_type = 'project_discussion'::text);


--
-- Name: issue_to_label_label_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX issue_to_label_label_idx ON public.issue_to_label USING btree (label_id);


--
-- Name: issue_wakeup_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX issue_wakeup_due_idx ON public.issue_wakeup USING btree (next_fire_at) WHERE enabled;


--
-- Name: issue_wakeup_expiry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX issue_wakeup_expiry_idx ON public.issue_wakeup USING btree (expires_at) WHERE (enabled AND (expires_at IS NOT NULL));


--
-- Name: issue_wakeup_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX issue_wakeup_id_idx ON public.issue_wakeup USING btree (id);


--
-- Name: issue_wakeup_issue_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX issue_wakeup_issue_idx ON public.issue_wakeup USING btree (issue_id, workspace_id);


--
-- Name: issue_wakeup_pending_event_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX issue_wakeup_pending_event_idx ON public.issue_wakeup_receipt USING btree (wakeup_id, revision, coalesce_key) WHERE ((processed_at IS NULL) AND (coalesce_key IS NOT NULL));


--
-- Name: issue_wakeup_receipt_expiry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX issue_wakeup_receipt_expiry_idx ON public.issue_wakeup_receipt USING btree (processed_at, id) WHERE (processed_at IS NOT NULL);


--
-- Name: issue_wakeup_receipt_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX issue_wakeup_receipt_id_idx ON public.issue_wakeup_receipt USING btree (id);


--
-- Name: issue_wakeup_receipt_key_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX issue_wakeup_receipt_key_idx ON public.issue_wakeup_receipt USING btree (wakeup_id, revision, event_key);


--
-- Name: issue_wakeup_receipt_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX issue_wakeup_receipt_pending_idx ON public.issue_wakeup_receipt USING btree (wakeup_id, created_at) WHERE (processed_at IS NULL);


--
-- Name: issue_wakeup_system_rule_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX issue_wakeup_system_rule_idx ON public.issue_wakeup USING btree (issue_id, system_rule) WHERE (system_rule IS NOT NULL);


--
-- Name: issue_wakeup_workspace_history_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX issue_wakeup_workspace_history_idx ON public.issue_wakeup USING btree (workspace_id, created_at DESC, id DESC);


--
-- Name: maturity_snapshot_scope_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX maturity_snapshot_scope_date_idx ON public.maturity_snapshot USING btree (workspace_id, scope, scope_id, bucket_date DESC);


--
-- Name: ppg_active_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ppg_active_uniq ON public.project_presenter_grant USING btree (project_id) WHERE (status = 'active'::text);


--
-- Name: ppg_pending_uniq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ppg_pending_uniq ON public.project_presenter_grant USING btree (project_id, user_id) WHERE (status = 'pending'::text);


--
-- Name: ppg_project_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ppg_project_idx ON public.project_presenter_grant USING btree (project_id, created_at DESC);


--
-- Name: project_chat_session_issue_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_chat_session_issue_uidx ON public.project_chat_session USING btree (issue_id) WHERE (issue_id IS NOT NULL);


--
-- Name: project_chat_session_project_active_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX project_chat_session_project_active_unique ON public.project_chat_session USING btree (workspace_id, project_id) WHERE (status = 'active'::text);


--
-- Name: project_chat_session_project_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_chat_session_project_index ON public.project_chat_session USING btree (workspace_id, project_id);


--
-- Name: skill_appeal_activity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX skill_appeal_activity_idx ON public.activity_log USING btree (((details ->> 'appeal_id'::text))) WHERE (action = ANY (ARRAY['skill_appeal_submitted'::text, 'skill_appeal_approved'::text, 'skill_appeal_rejected'::text]));


--
-- Name: skill_to_label_label_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX skill_to_label_label_idx ON public.skill_to_label USING btree (label_id);


--
-- Name: skill_usage_event_scope_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX skill_usage_event_scope_idx ON public.skill_usage_event USING btree (workspace_id, skill_ref, used_at);


--
-- Name: skill_usage_event_task_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX skill_usage_event_task_id_idx ON public.skill_usage_event USING btree (task_id);


--
-- Name: task_supplement_capability_task_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX task_supplement_capability_task_uidx ON public.task_supplement_capability USING btree (task_id);


--
-- Name: task_supplement_task_request_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX task_supplement_task_request_uidx ON public.task_supplement USING btree (task_id, client_request_id);


--
-- Name: uq_autopilot_quota_reservation_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_autopilot_quota_reservation_key ON public.autopilot_quota_reservation USING btree (workspace_id, period_start, period_end, idempotency_key) WHERE (state <> 'released'::text);


--
-- Name: uq_autopilot_run_quota_reservation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_autopilot_run_quota_reservation ON public.autopilot_run USING btree (quota_reservation_id) WHERE (quota_reservation_id IS NOT NULL);


--
-- Name: uq_autopilot_run_trigger_planned; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_autopilot_run_trigger_planned ON public.autopilot_run USING btree (trigger_id, planned_at) WHERE ((trigger_id IS NOT NULL) AND (planned_at IS NOT NULL));


--
-- Name: uq_autopilot_run_webhook_delivery; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_autopilot_run_webhook_delivery ON public.autopilot_run USING btree (webhook_delivery_id) WHERE (webhook_delivery_id IS NOT NULL);


--
-- Name: uq_webhook_delivery_replay_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_webhook_delivery_replay_idempotency ON public.webhook_delivery USING btree (replayed_from_delivery_id, replay_idempotency_key) WHERE ((replayed_from_delivery_id IS NOT NULL) AND (replay_idempotency_key IS NOT NULL));


--
-- Name: user_composio_connection_account_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_composio_connection_account_idx ON public.user_composio_connection USING btree (connected_account_id);


--
-- Name: user_composio_connection_user_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_composio_connection_user_status_idx ON public.user_composio_connection USING btree (user_id, status);


--
-- Name: workspace_share_link_active_ws_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX workspace_share_link_active_ws_uidx ON public.workspace_share_link USING btree (workspace_id) WHERE (is_active = true);


--
-- Name: workspace_share_link_code_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX workspace_share_link_code_uidx ON public.workspace_share_link USING btree (code);


--
-- Name: agent_task_queue agent_task_comment_thread; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER agent_task_comment_thread BEFORE INSERT OR UPDATE OF trigger_comment_id ON public.agent_task_queue FOR EACH ROW EXECUTE FUNCTION public.set_agent_task_comment_thread();


--
-- Name: attachment capture_attachment_wakeup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER capture_attachment_wakeup AFTER INSERT OR DELETE OR UPDATE OF issue_id, comment_id ON public.attachment FOR EACH ROW EXECUTE FUNCTION public.capture_attachment_wakeup();


--
-- Name: comment_reaction capture_comment_reaction_wakeup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER capture_comment_reaction_wakeup AFTER INSERT OR DELETE ON public.comment_reaction FOR EACH ROW EXECUTE FUNCTION public.capture_reaction_wakeup();


--
-- Name: comment capture_comment_wakeup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER capture_comment_wakeup AFTER INSERT OR DELETE OR UPDATE ON public.comment FOR EACH ROW EXECUTE FUNCTION public.capture_comment_wakeup();


--
-- Name: issue capture_issue_collaboration_wakeup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER capture_issue_collaboration_wakeup AFTER UPDATE ON public.issue FOR EACH ROW EXECUTE FUNCTION public.capture_issue_collaboration_wakeup();


--
-- Name: issue_to_label capture_issue_label_wakeup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER capture_issue_label_wakeup AFTER INSERT OR DELETE ON public.issue_to_label FOR EACH ROW EXECUTE FUNCTION public.capture_issue_label_wakeup();


--
-- Name: issue_reaction capture_issue_reaction_wakeup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER capture_issue_reaction_wakeup AFTER INSERT OR DELETE ON public.issue_reaction FOR EACH ROW EXECUTE FUNCTION public.capture_reaction_wakeup();


--
-- Name: agent_task_queue capture_task_wakeup; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER capture_task_wakeup AFTER INSERT OR UPDATE OF status ON public.agent_task_queue FOR EACH ROW EXECUTE FUNCTION public.capture_task_wakeup();


--
-- Name: issue_wakeup guard_issue_wakeup_capacity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER guard_issue_wakeup_capacity BEFORE INSERT OR UPDATE OF enabled, issue_id, workspace_id ON public.issue_wakeup FOR EACH ROW EXECUTE FUNCTION public.guard_issue_wakeup_capacity();


--
-- Name: issue issue_child_event_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER issue_child_event_insert AFTER INSERT ON public.issue FOR EACH ROW WHEN ((new.parent_issue_id IS NOT NULL)) EXECUTE FUNCTION public.record_issue_child_event();


--
-- Name: issue issue_child_event_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER issue_child_event_update AFTER UPDATE OF status, parent_issue_id, stage ON public.issue FOR EACH ROW WHEN (((old.parent_issue_id IS DISTINCT FROM new.parent_issue_id) OR ((new.parent_issue_id IS NOT NULL) AND ((old.status IS DISTINCT FROM new.status) OR (old.stage IS DISTINCT FROM new.stage))))) EXECUTE FUNCTION public.record_issue_child_event();


--
-- Name: dingtalk_group_presence mirror_dingtalk_group_presence_bot_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mirror_dingtalk_group_presence_bot_identity AFTER INSERT OR UPDATE OF bot_name, bot_identity_issue ON public.dingtalk_group_presence FOR EACH ROW EXECUTE FUNCTION public.mirror_dingtalk_group_presence_bot_identity();


--
-- Name: dingtalk_group_route mirror_legacy_dingtalk_group_route_presence; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mirror_legacy_dingtalk_group_route_presence AFTER INSERT OR UPDATE ON public.dingtalk_group_route FOR EACH ROW EXECUTE FUNCTION public.mirror_legacy_dingtalk_group_route_presence();


--
-- Name: agent_task_queue trg_atq_dirty_hourly; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_atq_dirty_hourly BEFORE DELETE OR UPDATE OF runtime_id, issue_id ON public.agent_task_queue FOR EACH ROW WHEN ((current_setting('multica.workspace_teardown'::text, true) IS DISTINCT FROM 'on'::text)) EXECUTE FUNCTION public.enqueue_task_usage_hourly_dirty_for_atq();


--
-- Name: agent_task_queue trg_clear_runtime_mcp_overlay; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_clear_runtime_mcp_overlay BEFORE UPDATE OF status ON public.agent_task_queue FOR EACH ROW EXECUTE FUNCTION public.clear_runtime_mcp_overlay_on_terminal_state();


--
-- Name: comment trg_comment_search_index_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_comment_search_index_change AFTER INSERT OR DELETE ON public.comment FOR EACH ROW WHEN ((current_setting('multica.workspace_teardown'::text, true) IS DISTINCT FROM 'on'::text)) EXECUTE FUNCTION public.record_search_index_change('comment');


--
-- Name: comment trg_comment_update_search_index_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_comment_update_search_index_change AFTER UPDATE OF content, deleted_at, issue_id, created_at ON public.comment FOR EACH ROW WHEN ((current_setting('multica.workspace_teardown'::text, true) IS DISTINCT FROM 'on'::text)) EXECUTE FUNCTION public.record_search_index_change('comment');


--
-- Name: chat_message trg_enforce_channel_message_task_context_revision; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_channel_message_task_context_revision BEFORE UPDATE OF task_id ON public.chat_message FOR EACH ROW WHEN (((old.task_id IS NULL) AND (new.task_id IS NOT NULL) AND (new.role = 'user'::text))) EXECUTE FUNCTION public.enforce_channel_message_task_context_revision();


--
-- Name: issue trg_issue_delete_dirty_hourly; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_issue_delete_dirty_hourly BEFORE DELETE ON public.issue FOR EACH ROW WHEN ((current_setting('multica.workspace_teardown'::text, true) IS DISTINCT FROM 'on'::text)) EXECUTE FUNCTION public.enqueue_task_usage_hourly_dirty_for_issue_delete();


--
-- Name: issue trg_issue_project_dirty_hourly; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_issue_project_dirty_hourly BEFORE UPDATE OF project_id ON public.issue FOR EACH ROW EXECUTE FUNCTION public.enqueue_task_usage_hourly_dirty_for_issue_project();


--
-- Name: issue trg_issue_search_index_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_issue_search_index_change AFTER INSERT OR DELETE OR UPDATE ON public.issue FOR EACH ROW WHEN ((current_setting('multica.workspace_teardown'::text, true) IS DISTINCT FROM 'on'::text)) EXECUTE FUNCTION public.record_search_index_change('issue');


--
-- Name: project trg_project_search_index_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_project_search_index_change AFTER INSERT OR DELETE OR UPDATE ON public.project FOR EACH ROW WHEN ((current_setting('multica.workspace_teardown'::text, true) IS DISTINCT FROM 'on'::text)) EXECUTE FUNCTION public.record_search_index_change('project');


--
-- Name: task_usage trg_tu_dirty_hourly; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_tu_dirty_hourly BEFORE DELETE ON public.task_usage FOR EACH ROW WHEN ((current_setting('multica.workspace_teardown'::text, true) IS DISTINCT FROM 'on'::text)) EXECUTE FUNCTION public.enqueue_task_usage_hourly_dirty_for_tu();


--
-- Name: activity_log activity_log_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_log
    ADD CONSTRAINT activity_log_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: activity_log activity_log_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_log
    ADD CONSTRAINT activity_log_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: agent agent_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT agent_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public."user"(id);


--
-- Name: agent agent_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT agent_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public."user"(id);


--
-- Name: agent agent_runtime_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT agent_runtime_id_fkey FOREIGN KEY (runtime_id) REFERENCES public.agent_runtime(id) ON DELETE RESTRICT;


--
-- Name: agent_runtime agent_runtime_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_runtime
    ADD CONSTRAINT agent_runtime_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public."user"(id);


--
-- Name: agent_runtime agent_runtime_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_runtime
    ADD CONSTRAINT agent_runtime_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: agent_skill agent_skill_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_skill
    ADD CONSTRAINT agent_skill_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.agent(id) ON DELETE CASCADE;


--
-- Name: agent_skill agent_skill_skill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_skill
    ADD CONSTRAINT agent_skill_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES public.skill(id) ON DELETE CASCADE;


--
-- Name: agent_task_queue agent_task_queue_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.agent(id) ON DELETE CASCADE;


--
-- Name: agent_task_queue agent_task_queue_autopilot_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_autopilot_run_id_fkey FOREIGN KEY (autopilot_run_id) REFERENCES public.autopilot_run(id) ON DELETE SET NULL;


--
-- Name: agent_task_queue agent_task_queue_chat_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_chat_session_id_fkey FOREIGN KEY (chat_session_id) REFERENCES public.chat_session(id) ON DELETE SET NULL;


--
-- Name: agent_task_queue agent_task_queue_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: agent_task_queue agent_task_queue_parent_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_parent_task_id_fkey FOREIGN KEY (parent_task_id) REFERENCES public.agent_task_queue(id) ON DELETE SET NULL;


--
-- Name: agent_task_queue agent_task_queue_pipeline_node_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_pipeline_node_run_id_fkey FOREIGN KEY (pipeline_node_run_id) REFERENCES public.pipeline_node_run(id) ON DELETE SET NULL;


--
-- Name: agent_task_queue agent_task_queue_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE SET NULL;


--
-- Name: agent_task_queue agent_task_queue_runtime_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_runtime_id_fkey FOREIGN KEY (runtime_id) REFERENCES public.agent_runtime(id) ON DELETE CASCADE;


--
-- Name: agent_task_queue agent_task_queue_trigger_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_task_queue
    ADD CONSTRAINT agent_task_queue_trigger_comment_id_fkey FOREIGN KEY (trigger_comment_id) REFERENCES public.comment(id) ON DELETE SET NULL;


--
-- Name: agent agent_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent
    ADD CONSTRAINT agent_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: approval_record approval_record_approver_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_record
    ADD CONSTRAINT approval_record_approver_user_id_fkey FOREIGN KEY (approver_user_id) REFERENCES public."user"(id);


--
-- Name: approval_record approval_record_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_record
    ADD CONSTRAINT approval_record_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: attachment attachment_chat_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_chat_message_id_fkey FOREIGN KEY (chat_message_id) REFERENCES public.chat_message(id) ON DELETE CASCADE;


--
-- Name: attachment attachment_chat_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_chat_session_id_fkey FOREIGN KEY (chat_session_id) REFERENCES public.chat_session(id) ON DELETE CASCADE;


--
-- Name: attachment attachment_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comment(id) ON DELETE CASCADE;


--
-- Name: attachment attachment_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: attachment attachment_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachment
    ADD CONSTRAINT attachment_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: autopilot autopilot_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot
    ADD CONSTRAINT autopilot_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE SET NULL;


--
-- Name: autopilot_run autopilot_run_autopilot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_run
    ADD CONSTRAINT autopilot_run_autopilot_id_fkey FOREIGN KEY (autopilot_id) REFERENCES public.autopilot(id) ON DELETE CASCADE;


--
-- Name: autopilot_run autopilot_run_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_run
    ADD CONSTRAINT autopilot_run_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE SET NULL;


--
-- Name: autopilot_run autopilot_run_squad_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_run
    ADD CONSTRAINT autopilot_run_squad_id_fkey FOREIGN KEY (squad_id) REFERENCES public.squad(id) ON DELETE SET NULL;


--
-- Name: autopilot_run autopilot_run_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_run
    ADD CONSTRAINT autopilot_run_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.agent_task_queue(id) ON DELETE SET NULL;


--
-- Name: autopilot_run autopilot_run_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_run
    ADD CONSTRAINT autopilot_run_trigger_id_fkey FOREIGN KEY (trigger_id) REFERENCES public.autopilot_trigger(id) ON DELETE SET NULL;


--
-- Name: autopilot_trigger autopilot_trigger_autopilot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot_trigger
    ADD CONSTRAINT autopilot_trigger_autopilot_id_fkey FOREIGN KEY (autopilot_id) REFERENCES public.autopilot(id) ON DELETE CASCADE;


--
-- Name: autopilot autopilot_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.autopilot
    ADD CONSTRAINT autopilot_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: chat_message chat_message_chat_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_message
    ADD CONSTRAINT chat_message_chat_session_id_fkey FOREIGN KEY (chat_session_id) REFERENCES public.chat_session(id) ON DELETE CASCADE;


--
-- Name: chat_session chat_session_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_session
    ADD CONSTRAINT chat_session_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.agent(id) ON DELETE SET NULL;


--
-- Name: chat_session chat_session_creator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_session
    ADD CONSTRAINT chat_session_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: chat_session chat_session_project_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_session
    ADD CONSTRAINT chat_session_project_fk FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: chat_session chat_session_runtime_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_session
    ADD CONSTRAINT chat_session_runtime_id_fkey FOREIGN KEY (runtime_id) REFERENCES public.agent_runtime(id) ON DELETE SET NULL;


--
-- Name: chat_session chat_session_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_session
    ADD CONSTRAINT chat_session_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: comment comment_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: comment comment_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.comment(id) ON DELETE CASCADE;


--
-- Name: comment_reaction comment_reaction_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reaction
    ADD CONSTRAINT comment_reaction_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comment(id) ON DELETE CASCADE;


--
-- Name: comment_reaction comment_reaction_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_reaction
    ADD CONSTRAINT comment_reaction_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: comment comment_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: cr cr_shell_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cr
    ADD CONSTRAINT cr_shell_issue_id_fkey FOREIGN KEY (shell_issue_id) REFERENCES public.issue(id) ON DELETE SET NULL;


--
-- Name: cr cr_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cr
    ADD CONSTRAINT cr_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: daemon_connection daemon_connection_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daemon_connection
    ADD CONSTRAINT daemon_connection_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.agent(id) ON DELETE CASCADE;


--
-- Name: daemon_token daemon_token_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daemon_token
    ADD CONSTRAINT daemon_token_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: feedback feedback_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: feedback feedback_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE SET NULL;


--
-- Name: github_installation github_installation_connected_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_installation
    ADD CONSTRAINT github_installation_connected_by_id_fkey FOREIGN KEY (connected_by_id) REFERENCES public."user"(id) ON DELETE SET NULL;


--
-- Name: github_installation github_installation_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_installation
    ADD CONSTRAINT github_installation_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: github_pull_request_check_suite github_pull_request_check_suite_pr_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_pull_request_check_suite
    ADD CONSTRAINT github_pull_request_check_suite_pr_id_fkey FOREIGN KEY (pr_id) REFERENCES public.github_pull_request(id) ON DELETE CASCADE;


--
-- Name: github_pull_request github_pull_request_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.github_pull_request
    ADD CONSTRAINT github_pull_request_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: inbox_item inbox_item_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_item
    ADD CONSTRAINT inbox_item_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: inbox_item inbox_item_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_item
    ADD CONSTRAINT inbox_item_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: issue_dependency issue_dependency_depends_on_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_dependency
    ADD CONSTRAINT issue_dependency_depends_on_issue_id_fkey FOREIGN KEY (depends_on_issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: issue_dependency issue_dependency_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_dependency
    ADD CONSTRAINT issue_dependency_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: issue_label issue_label_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_label
    ADD CONSTRAINT issue_label_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: issue issue_parent_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue
    ADD CONSTRAINT issue_parent_issue_id_fkey FOREIGN KEY (parent_issue_id) REFERENCES public.issue(id) ON DELETE SET NULL;


--
-- Name: issue issue_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue
    ADD CONSTRAINT issue_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE SET NULL;


--
-- Name: issue_pull_request issue_pull_request_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_pull_request
    ADD CONSTRAINT issue_pull_request_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: issue_pull_request issue_pull_request_pull_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_pull_request
    ADD CONSTRAINT issue_pull_request_pull_request_id_fkey FOREIGN KEY (pull_request_id) REFERENCES public.github_pull_request(id) ON DELETE CASCADE;


--
-- Name: issue_reaction issue_reaction_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_reaction
    ADD CONSTRAINT issue_reaction_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: issue_reaction issue_reaction_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_reaction
    ADD CONSTRAINT issue_reaction_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: issue_subscriber issue_subscriber_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_subscriber
    ADD CONSTRAINT issue_subscriber_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: issue_to_label issue_to_label_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_to_label
    ADD CONSTRAINT issue_to_label_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE CASCADE;


--
-- Name: issue_to_label issue_to_label_label_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue_to_label
    ADD CONSTRAINT issue_to_label_label_id_fkey FOREIGN KEY (label_id) REFERENCES public.issue_label(id) ON DELETE CASCADE;


--
-- Name: issue issue_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.issue
    ADD CONSTRAINT issue_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: lark_binding_token lark_binding_token_installation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_binding_token
    ADD CONSTRAINT lark_binding_token_installation_id_fkey FOREIGN KEY (installation_id) REFERENCES public.lark_installation(id) ON DELETE CASCADE;


--
-- Name: lark_binding_token lark_binding_token_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_binding_token
    ADD CONSTRAINT lark_binding_token_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: lark_chat_session_binding lark_chat_session_binding_chat_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_chat_session_binding
    ADD CONSTRAINT lark_chat_session_binding_chat_session_id_fkey FOREIGN KEY (chat_session_id) REFERENCES public.chat_session(id) ON DELETE CASCADE;


--
-- Name: lark_chat_session_binding lark_chat_session_binding_installation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_chat_session_binding
    ADD CONSTRAINT lark_chat_session_binding_installation_id_fkey FOREIGN KEY (installation_id) REFERENCES public.lark_installation(id) ON DELETE CASCADE;


--
-- Name: lark_inbound_audit lark_inbound_audit_installation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_inbound_audit
    ADD CONSTRAINT lark_inbound_audit_installation_id_fkey FOREIGN KEY (installation_id) REFERENCES public.lark_installation(id) ON DELETE SET NULL;


--
-- Name: lark_inbound_message_dedup lark_inbound_message_dedup_installation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_inbound_message_dedup
    ADD CONSTRAINT lark_inbound_message_dedup_installation_id_fkey FOREIGN KEY (installation_id) REFERENCES public.lark_installation(id) ON DELETE CASCADE;


--
-- Name: lark_installation lark_installation_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_installation
    ADD CONSTRAINT lark_installation_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.agent(id) ON DELETE CASCADE;


--
-- Name: lark_installation lark_installation_installer_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_installation
    ADD CONSTRAINT lark_installation_installer_user_id_fkey FOREIGN KEY (installer_user_id) REFERENCES public."user"(id) ON DELETE RESTRICT;


--
-- Name: lark_installation lark_installation_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_installation
    ADD CONSTRAINT lark_installation_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: lark_outbound_card_message lark_outbound_card_message_chat_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_outbound_card_message
    ADD CONSTRAINT lark_outbound_card_message_chat_session_id_fkey FOREIGN KEY (chat_session_id) REFERENCES public.chat_session(id) ON DELETE CASCADE;


--
-- Name: lark_outbound_card_message lark_outbound_card_message_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_outbound_card_message
    ADD CONSTRAINT lark_outbound_card_message_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.agent_task_queue(id) ON DELETE SET NULL;


--
-- Name: lark_user_binding lark_user_binding_installation_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_user_binding
    ADD CONSTRAINT lark_user_binding_installation_fk FOREIGN KEY (installation_id, workspace_id) REFERENCES public.lark_installation(id, workspace_id) ON DELETE CASCADE;


--
-- Name: lark_user_binding lark_user_binding_member_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lark_user_binding
    ADD CONSTRAINT lark_user_binding_member_fk FOREIGN KEY (workspace_id, multica_user_id) REFERENCES public.member(workspace_id, user_id) ON DELETE CASCADE;


--
-- Name: member member_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member
    ADD CONSTRAINT member_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: member member_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member
    ADD CONSTRAINT member_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: notification_preference notification_preference_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_preference
    ADD CONSTRAINT notification_preference_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: notification_preference notification_preference_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_preference
    ADD CONSTRAINT notification_preference_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: personal_access_token personal_access_token_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_token
    ADD CONSTRAINT personal_access_token_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: pinned_item pinned_item_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pinned_item
    ADD CONSTRAINT pinned_item_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: pinned_item pinned_item_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pinned_item
    ADD CONSTRAINT pinned_item_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: pipeline_node_run pipeline_node_run_approval_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_node_run
    ADD CONSTRAINT pipeline_node_run_approval_id_fkey FOREIGN KEY (approval_id) REFERENCES public.approval_record(id);


--
-- Name: pipeline_node_run pipeline_node_run_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_node_run
    ADD CONSTRAINT pipeline_node_run_run_id_fkey FOREIGN KEY (run_id) REFERENCES public.pipeline_run(id) ON DELETE CASCADE;


--
-- Name: pipeline_run pipeline_run_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_run
    ADD CONSTRAINT pipeline_run_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issue(id) ON DELETE SET NULL;


--
-- Name: pipeline_run pipeline_run_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_run
    ADD CONSTRAINT pipeline_run_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: project_presenter_grant project_presenter_grant_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_presenter_grant
    ADD CONSTRAINT project_presenter_grant_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: project_presenter_grant project_presenter_grant_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_presenter_grant
    ADD CONSTRAINT project_presenter_grant_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: project_presenter_grant project_presenter_grant_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_presenter_grant
    ADD CONSTRAINT project_presenter_grant_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: project_resource project_resource_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_resource
    ADD CONSTRAINT project_resource_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.project(id) ON DELETE CASCADE;


--
-- Name: project_resource project_resource_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_resource
    ADD CONSTRAINT project_resource_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: project project_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project
    ADD CONSTRAINT project_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: skill skill_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill
    ADD CONSTRAINT skill_created_by_fkey FOREIGN KEY (created_by) REFERENCES public."user"(id);


--
-- Name: skill_file skill_file_skill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill_file
    ADD CONSTRAINT skill_file_skill_id_fkey FOREIGN KEY (skill_id) REFERENCES public.skill(id) ON DELETE CASCADE;


--
-- Name: skill skill_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.skill
    ADD CONSTRAINT skill_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: squad squad_leader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.squad
    ADD CONSTRAINT squad_leader_id_fkey FOREIGN KEY (leader_id) REFERENCES public.agent(id) ON DELETE RESTRICT;


--
-- Name: squad_member squad_member_squad_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.squad_member
    ADD CONSTRAINT squad_member_squad_id_fkey FOREIGN KEY (squad_id) REFERENCES public.squad(id) ON DELETE CASCADE;


--
-- Name: squad squad_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.squad
    ADD CONSTRAINT squad_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: task_message task_message_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_message
    ADD CONSTRAINT task_message_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.agent_task_queue(id) ON DELETE CASCADE;


--
-- Name: task_token task_token_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_token
    ADD CONSTRAINT task_token_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES public.agent(id) ON DELETE CASCADE;


--
-- Name: task_token task_token_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_token
    ADD CONSTRAINT task_token_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.agent_task_queue(id) ON DELETE CASCADE;


--
-- Name: task_token task_token_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_token
    ADD CONSTRAINT task_token_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON DELETE CASCADE;


--
-- Name: task_token task_token_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_token
    ADD CONSTRAINT task_token_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: task_usage task_usage_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_usage
    ADD CONSTRAINT task_usage_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.agent_task_queue(id) ON DELETE CASCADE;


--
-- Name: webhook_delivery webhook_delivery_autopilot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_delivery
    ADD CONSTRAINT webhook_delivery_autopilot_id_fkey FOREIGN KEY (autopilot_id) REFERENCES public.autopilot(id) ON DELETE CASCADE;


--
-- Name: webhook_delivery webhook_delivery_autopilot_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_delivery
    ADD CONSTRAINT webhook_delivery_autopilot_run_id_fkey FOREIGN KEY (autopilot_run_id) REFERENCES public.autopilot_run(id) ON DELETE SET NULL;


--
-- Name: webhook_delivery webhook_delivery_replayed_from_delivery_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_delivery
    ADD CONSTRAINT webhook_delivery_replayed_from_delivery_id_fkey FOREIGN KEY (replayed_from_delivery_id) REFERENCES public.webhook_delivery(id) ON DELETE SET NULL;


--
-- Name: webhook_delivery webhook_delivery_trigger_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_delivery
    ADD CONSTRAINT webhook_delivery_trigger_id_fkey FOREIGN KEY (trigger_id) REFERENCES public.autopilot_trigger(id) ON DELETE CASCADE;


--
-- Name: webhook_delivery webhook_delivery_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_delivery
    ADD CONSTRAINT webhook_delivery_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- Name: workspace_invitation workspace_invitation_invitee_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitation
    ADD CONSTRAINT workspace_invitation_invitee_user_id_fkey FOREIGN KEY (invitee_user_id) REFERENCES public."user"(id);


--
-- Name: workspace_invitation workspace_invitation_inviter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitation
    ADD CONSTRAINT workspace_invitation_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES public."user"(id);


--
-- Name: workspace_invitation workspace_invitation_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitation
    ADD CONSTRAINT workspace_invitation_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspace(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict d7gEuzej9v7m7C6Tu1qkZhkj03lHN8RxQVa6znKBppwoVi7DgGGYgfQgNudouaz

