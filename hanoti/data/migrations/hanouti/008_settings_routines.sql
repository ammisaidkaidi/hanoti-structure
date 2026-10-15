-- UNAPPLIED DECLARATIONS ONLY. Target: hanouti. No connection, execution or grants to business users.
-- SECURITY DEFINER deployment requires the restricted owner/runtime template; see ERP_ROUTINES.md.
BEGIN;

CREATE FUNCTION settings._validate_context(p_actor uuid, p_context jsonb)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_key text; v_value jsonb; v_id uuid;
BEGIN
PERFORM auth._require_active_actor(p_actor);
  IF p_context IS NULL OR jsonb_typeof(p_context)<>'object' THEN RAISE EXCEPTION 'Setting context must be an object' USING ERRCODE='22023'; END IF;
  FOR v_key,v_value IN SELECT key,value FROM jsonb_each(p_context) LOOP
    IF v_key NOT IN ('customer','supplier','product','warehouse','document_kind','currency','unit')
      OR jsonb_typeof(v_value)<>'string' THEN
      RAISE EXCEPTION 'Unsupported setting context' USING ERRCODE='22023';
    END IF;
    IF v_key IN ('customer','supplier','product','warehouse') THEN
      BEGIN v_id := (v_value #>> '{}')::uuid;
      EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'Invalid setting target' USING ERRCODE='22023'; END;
      IF (v_key='customer' AND NOT EXISTS(SELECT 1 FROM erp.customers WHERE id=v_id))
        OR (v_key='supplier' AND NOT EXISTS(SELECT 1 FROM erp.suppliers WHERE id=v_id))
        OR (v_key='product' AND NOT EXISTS(SELECT 1 FROM erp.products WHERE id=v_id))
        OR (v_key='warehouse' AND NOT EXISTS(SELECT 1 FROM erp.warehouses WHERE id=v_id)) THEN
        RAISE EXCEPTION 'Setting target unavailable' USING ERRCODE='22023';
      END IF;
    ELSIF (v_key='currency' AND (v_value #>> '{}') !~ '^[A-Z]{3}$') OR btrim(v_value #>> '{}')='' THEN
      RAISE EXCEPTION 'Invalid setting context value' USING ERRCODE='22023';
    END IF;
  END LOOP;
END;
$fn$;
REVOKE ALL ON FUNCTION settings._validate_context(uuid, jsonb) FROM PUBLIC;

CREATE FUNCTION settings._validate_value(p_definition settings.setting_definitions, p_value jsonb, p_context jsonb)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_key text; v_rule jsonb; v_element jsonb; v_number numeric; v_ok boolean := false;
BEGIN
IF p_value IS NULL THEN RAISE EXCEPTION 'SQL NULL is not a setting value' USING ERRCODE='22023'; END IF;
  -- Bounded declarative vocabulary, never arbitrary SQL, regexes or executable expressions.
  FOR v_key,v_rule IN SELECT key,value FROM jsonb_each(p_definition.validation_rules) LOOP
    IF v_key IN ('min_length','max_length') THEN
      IF p_definition.value_type NOT IN ('string','enum') OR jsonb_typeof(v_rule)<>'number'
        OR (v_rule::text)::numeric < 0 OR trunc((v_rule::text)::numeric)<>(v_rule::text)::numeric
        OR (v_rule::text)::numeric>1000000 THEN RAISE EXCEPTION 'Invalid string validation rule' USING ERRCODE='22023'; END IF;
    ELSIF v_key IN ('required_keys','allowed_keys') THEN
      IF p_definition.value_type<>'object' OR jsonb_typeof(v_rule)<>'array' THEN RAISE EXCEPTION 'Invalid object validation rule' USING ERRCODE='22023'; END IF;
      FOR v_element IN SELECT value FROM jsonb_array_elements(v_rule) LOOP
        IF jsonb_typeof(v_element)<>'string' OR btrim(v_element #>> '{}')='' THEN RAISE EXCEPTION 'Invalid object key rule' USING ERRCODE='22023'; END IF;
      END LOOP;
    ELSE RAISE EXCEPTION 'Unsupported validation rule' USING ERRCODE='22023';
    END IF;
  END LOOP;
  IF (p_definition.validation_rules->>'min_length')::numeric > (p_definition.validation_rules->>'max_length')::numeric THEN
    RAISE EXCEPTION 'Inconsistent length rules' USING ERRCODE='22023';
  END IF;
  IF p_definition.validation_rules ? 'required_keys' AND p_definition.validation_rules ? 'allowed_keys'
    AND NOT ((p_definition.validation_rules->'allowed_keys') @> (p_definition.validation_rules->'required_keys')) THEN
    RAISE EXCEPTION 'Inconsistent object key rules' USING ERRCODE='22023';
  END IF;
  IF p_definition.value_type='enum' THEN
    FOR v_element IN SELECT value FROM jsonb_array_elements(p_definition.enum_values) LOOP
      IF jsonb_typeof(v_element)<>'string' THEN RAISE EXCEPTION 'Enum values must be strings' USING ERRCODE='22023'; END IF;
    END LOOP;
  END IF;
  IF p_value='null'::jsonb THEN
    IF NOT p_definition.allow_null THEN RAISE EXCEPTION 'Explicit unset is not permitted' USING ERRCODE='22023'; END IF;
    RETURN;
  END IF;
  CASE p_definition.value_type
    WHEN 'boolean' THEN v_ok := jsonb_typeof(p_value)='boolean';
    WHEN 'integer' THEN
      v_ok := jsonb_typeof(p_value)='number';
      IF v_ok THEN v_number := (p_value::text)::numeric; v_ok := trunc(v_number)=v_number; END IF;
    WHEN 'decimal' THEN
      v_ok := jsonb_typeof(p_value)='number'; IF v_ok THEN v_number := (p_value::text)::numeric; END IF;
    WHEN 'string' THEN v_ok := jsonb_typeof(p_value)='string';
    WHEN 'enum' THEN v_ok := jsonb_typeof(p_value)='string' AND p_definition.enum_values @> jsonb_build_array(p_value);
    WHEN 'uuid' THEN
      v_ok := jsonb_typeof(p_value)='string';
      IF v_ok THEN
        BEGIN PERFORM (p_value #>> '{}')::uuid;
        EXCEPTION WHEN invalid_text_representation THEN v_ok := false; END;
      END IF;
    WHEN 'object' THEN v_ok := jsonb_typeof(p_value)='object';
    WHEN 'currency_amount' THEN
      v_ok := jsonb_typeof(p_value)='object';
      IF v_ok THEN
        v_ok := p_value ?& ARRAY['amount','currency'] AND (p_value-ARRAY['amount','currency'])='{}'::jsonb
          AND jsonb_typeof(p_value->'amount')='number' AND jsonb_typeof(p_value->'currency')='string'
          AND (p_value->>'currency') ~ '^[A-Z]{3}$'
          AND p_context ? 'currency' AND p_value->>'currency'=p_context->>'currency';
        IF v_ok THEN v_number := (p_value->>'amount')::numeric; END IF;
      END IF;
    ELSE v_ok := false;
  END CASE;
  IF v_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Setting value does not match its definition or currency' USING ERRCODE='22023'; END IF;
  IF v_number IS NOT NULL THEN
    IF v_number IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
      OR v_number<p_definition.minimum_value OR v_number>p_definition.maximum_value THEN
      RAISE EXCEPTION 'Setting numeric value is out of range' USING ERRCODE='22023';
    END IF;
  END IF;
  IF p_definition.value_type IN ('string','enum') THEN
    IF length(p_value #>> '{}') < (p_definition.validation_rules->>'min_length')::integer
      OR length(p_value #>> '{}') > (p_definition.validation_rules->>'max_length')::integer THEN
      RAISE EXCEPTION 'Setting string length is out of range' USING ERRCODE='22023';
    END IF;
  ELSIF p_definition.value_type='object' THEN
    FOR v_element IN SELECT value FROM jsonb_array_elements(coalesce(p_definition.validation_rules->'required_keys','[]'::jsonb)) LOOP
      IF NOT (p_value ? (v_element #>> '{}')) THEN RAISE EXCEPTION 'Required setting object key missing' USING ERRCODE='22023'; END IF;
    END LOOP;
    IF p_definition.validation_rules ? 'allowed_keys' THEN
      FOR v_key IN SELECT jsonb_object_keys(p_value) LOOP
        IF NOT ((p_definition.validation_rules->'allowed_keys') @> jsonb_build_array(v_key)) THEN
          RAISE EXCEPTION 'Unsupported setting object key' USING ERRCODE='22023';
        END IF;
      END LOOP;
    END IF;
  END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION settings._validate_value(settings.setting_definitions, jsonb, jsonb) FROM PUBLIC;

CREATE FUNCTION settings._resolve(p_actor uuid, p_key text, p_context jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_definition settings.setting_definitions%ROWTYPE;
v_effective jsonb; v_values jsonb := '{}'::jsonb; v_sources jsonb := '[]'::jsonb;
v_row record; v_scope text; v_value jsonb;
BEGIN
PERFORM settings._validate_context(p_actor,p_context);
  SELECT * INTO v_definition FROM settings.setting_definitions d WHERE d.key=p_key AND d.is_enabled;
  IF NOT FOUND THEN RAISE EXCEPTION 'Required setting is missing or disabled: %',p_key USING ERRCODE='22023'; END IF;
  IF cardinality(v_definition.document_kinds)>0 AND
    (NOT (p_context ? 'document_kind') OR NOT ((p_context->>'document_kind')=ANY(v_definition.document_kinds))) THEN
    RAISE EXCEPTION 'Setting does not support this document kind' USING ERRCODE='22023';
  END IF;
  IF v_definition.unit IS NOT NULL AND v_definition.unit IS DISTINCT FROM p_context->>'unit' THEN
    RAISE EXCEPTION 'Setting unit does not match context' USING ERRCODE='22023';
  END IF;
  PERFORM settings._validate_value(v_definition,v_definition.default_value,p_context);
  v_effective := v_definition.default_value;
  -- A live global row replaces the default baseline; default is not a second restriction.
  FOR v_row IN
    SELECT g.id,g.scope_type,g.value,g.version FROM settings.gsettings g
    WHERE g.setting_key=p_key AND g.valid_from<=statement_timestamp()
      AND (g.valid_until IS NULL OR g.valid_until>statement_timestamp())
      AND (g.scope_type='global' OR (g.scope_type='role' AND EXISTS (
        SELECT 1 FROM auth.user_roles ur WHERE ur.user_id=p_actor AND ur.role_id=g.role_id)))
    UNION ALL
    SELECT s.id,s.scope_type,s.value,s.version FROM settings.settings s
    WHERE s.setting_key=p_key AND s.valid_from<=statement_timestamp()
      AND (s.valid_until IS NULL OR s.valid_until>statement_timestamp())
      AND ((s.scope_type='user' AND s.scope_id=p_actor)
        OR (s.scope_type IN ('customer','supplier','product','warehouse') AND p_context ? s.scope_type
          AND s.scope_id=(p_context->>s.scope_type)::uuid))
  LOOP
    IF NOT (v_row.scope_type=ANY(v_definition.scope_precedence)) THEN
      RAISE EXCEPTION 'Stored setting has a disallowed scope' USING ERRCODE='22023';
    END IF;
    PERFORM settings._validate_value(v_definition,v_row.value,p_context);
    IF v_values ? v_row.scope_type AND v_values->v_row.scope_type IS DISTINCT FROM v_row.value THEN
      RAISE EXCEPTION 'Conflicting role settings' USING ERRCODE='22023';
    END IF;
    v_values := v_values || jsonb_build_object(v_row.scope_type,v_row.value);
    v_sources := v_sources || jsonb_build_array(jsonb_build_object('id',v_row.id,'scope',v_row.scope_type,'version',v_row.version));
  END LOOP;
  IF v_values ? 'global' THEN v_effective := v_values->'global'; END IF;
  FOREACH v_scope IN ARRAY v_definition.scope_precedence LOOP
    IF v_scope='global' OR NOT (v_values ? v_scope) THEN CONTINUE; END IF;
    v_value := v_values->v_scope;
    CASE v_definition.resolution_strategy
      WHEN 'most_specific' THEN v_effective := v_value;
      WHEN 'all_must_allow' THEN
        IF v_effective='null'::jsonb OR v_value='null'::jsonb THEN RAISE EXCEPTION 'Unset permission-like setting cannot allow an action' USING ERRCODE='22023'; END IF;
        v_effective := to_jsonb((v_effective::text)::boolean AND (v_value::text)::boolean);
      WHEN 'minimum_cap' THEN
        IF v_effective='null'::jsonb OR v_value='null'::jsonb THEN RAISE EXCEPTION 'Unset cap cannot be treated as unlimited' USING ERRCODE='22023'; END IF;
        IF v_definition.value_type='currency_amount' THEN
          IF (v_value->>'amount')::numeric < (v_effective->>'amount')::numeric THEN v_effective:=v_value; END IF;
        ELSE
          IF (v_value::text)::numeric < (v_effective::text)::numeric THEN v_effective:=v_value; END IF;
        END IF;
      ELSE RAISE EXCEPTION 'Unsupported scoped resolution' USING ERRCODE='22023';
    END CASE;
  END LOOP;
  IF v_definition.resolution_strategy IN ('all_must_allow','minimum_cap') AND v_effective='null'::jsonb THEN
    RAISE EXCEPTION 'Unresolved restrictive setting' USING ERRCODE='22023';
  END IF;
  RETURN jsonb_build_object('key',p_key,'value',v_effective,'definition_version',v_definition.version,'sources',v_sources);
END;
$fn$;
REVOKE ALL ON FUNCTION settings._resolve(uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION settings.resolve(p_actor uuid, p_key text, p_context jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
-- Generic inspection can reveal other parties' rules; only an all-scope settings.read grant qualifies.
  PERFORM auth._require_permission(p_actor,'settings.read','settings');
  RETURN settings._resolve(p_actor,p_key,p_context);
END;
$fn$;
REVOKE ALL ON FUNCTION settings.resolve(uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION settings._boolean(p_actor uuid, p_key text, p_context jsonb)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_result jsonb;
BEGIN
v_result := settings._resolve(p_actor,p_key,p_context);
  IF jsonb_typeof(v_result->'value')<>'boolean' THEN RAISE EXCEPTION 'Required setting must resolve to boolean' USING ERRCODE='22023'; END IF;
  RETURN (v_result->>'value')::boolean;
END;
$fn$;
REVOKE ALL ON FUNCTION settings._boolean(uuid, text, jsonb) FROM PUBLIC;

CREATE FUNCTION settings._number(p_actor uuid, p_key text, p_context jsonb)
RETURNS numeric
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_result jsonb;
BEGIN
v_result := settings._resolve(p_actor,p_key,p_context);
  IF jsonb_typeof(v_result->'value')<>'number' THEN RAISE EXCEPTION 'Required setting must resolve to number' USING ERRCODE='22023'; END IF;
  RETURN (v_result->>'value')::numeric;
END;
$fn$;
REVOKE ALL ON FUNCTION settings._number(uuid, text, jsonb) FROM PUBLIC;

COMMIT;
