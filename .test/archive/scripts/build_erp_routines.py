from pathlib import Path
import json
ROOT=Path('/home/user/hanouti/data')
registry=[]
files={}
def fn(file,name,args,types,returns,body,public=False,declare='',volatility='VOLATILE'):
    signature=f'{name}({", ".join(types)})'
    registry.append({'name':name,'signature':signature,'file':file,'exposed':public})
    ddl=f'''CREATE FUNCTION {name}({args})
RETURNS {returns}
LANGUAGE plpgsql {volatility} SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
'''
    if declare:ddl+='DECLARE\n'+declare.strip()+'\n'
    ddl+='BEGIN\n'+body.strip()+'\nEND;\n$fn$;\n'
    ddl+=f'REVOKE ALL ON FUNCTION {signature} FROM PUBLIC;\n'
    files.setdefault(file,[]).append(ddl)
A='007_authorization_routines.sql'
S='008_settings_routines.sql'
E='009_erp_routines.sql'
fn(A,'auth._require_active_actor','p_actor uuid',['uuid'],'void',"""
  IF p_actor IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p_actor AND u.status='active') THEN
    RAISE EXCEPTION 'Active authenticated actor required' USING ERRCODE='42501';
  END IF;
""")
fn(A,'auth._party_member','p_actor uuid, p_party_type text, p_party_id uuid',['uuid','text','uuid'],'boolean',"""
  RETURN EXISTS (
    SELECT 1 FROM auth.party_memberships m
    WHERE m.user_id=p_actor AND m.party_type=p_party_type AND m.party_id=p_party_id
      AND m.status='active' AND m.can_act_on_behalf AND m.verified_at <= statement_timestamp()
      AND m.revoked_at IS NULL AND m.valid_from <= statement_timestamp()
      AND (m.valid_until IS NULL OR m.valid_until > statement_timestamp())
      AND ((p_party_type='customer' AND EXISTS (SELECT 1 FROM erp.customers c WHERE c.id=p_party_id AND c.is_active))
        OR (p_party_type='supplier' AND EXISTS (SELECT 1 FROM erp.suppliers s WHERE s.id=p_party_id AND s.is_active)))
  );
""")
fn(A,'auth.has_permission',"p_actor uuid, p_code text, p_resource_type text, p_owner uuid DEFAULT NULL, p_party_type text DEFAULT NULL, p_party_id uuid DEFAULT NULL",['uuid','text','text','uuid','text','uuid'],'boolean',"""
  IF p_actor IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p_actor AND u.status='active') THEN RETURN false; END IF;
  IF (p_party_type IS NULL) <> (p_party_id IS NULL) OR (p_party_type IS NOT NULL AND p_party_type NOT IN ('customer','supplier')) THEN RETURN false; END IF;
  SELECT * INTO v_permission FROM auth.permissions p WHERE p.code=p_code AND p.resource_type=p_resource_type;
  IF NOT FOUND THEN RETURN false; END IF;
  v_member := auth._party_member(p_actor,p_party_type,p_party_id);
  FOR v_rule IN
    SELECT rp.effect,rp.record_scope FROM auth.role_permissions rp
      JOIN auth.user_roles ur ON ur.role_id=rp.role_id
      WHERE ur.user_id=p_actor AND rp.permission_id=v_permission.id
        AND rp.revoked_at IS NULL AND rp.valid_from <= statement_timestamp()
        AND (rp.valid_until IS NULL OR rp.valid_until > statement_timestamp())
    UNION ALL
    SELECT sp.effect,sp.record_scope FROM auth.subject_permissions sp
      WHERE sp.permission_id=v_permission.id AND sp.revoked_at IS NULL
        AND sp.valid_from <= statement_timestamp()
        AND (sp.valid_until IS NULL OR sp.valid_until > statement_timestamp())
        AND ((sp.subject_type='user' AND sp.user_id=p_actor)
          OR (v_member AND p_party_type='customer' AND sp.subject_type='customer' AND sp.customer_id=p_party_id)
          OR (v_member AND p_party_type='supplier' AND sp.subject_type='supplier' AND sp.supplier_id=p_party_id))
  LOOP
    -- Unsupported/assigned rules cannot be interpreted safely, including unresolved denies.
    IF v_rule.record_scope='assigned' OR NOT (v_rule.record_scope=ANY(v_permission.supported_scopes)) THEN RETURN false; END IF;
    IF v_rule.record_scope='all'
       OR (v_rule.record_scope='self' AND p_owner=p_actor)
       OR (v_rule.record_scope='own_party' AND v_member) THEN
      IF v_rule.effect='deny' THEN RETURN false; END IF;
      v_allow := true;
    END IF;
  END LOOP;
  RETURN v_allow;
""",True,'''v_permission auth.permissions%ROWTYPE;
v_rule record;
v_member boolean;
v_allow boolean := false;''')
fn(A,'auth._require_permission',"p_actor uuid, p_code text, p_resource_type text, p_owner uuid DEFAULT NULL, p_party_type text DEFAULT NULL, p_party_id uuid DEFAULT NULL",['uuid','text','text','uuid','text','uuid'],'void',"""
  IF NOT auth.has_permission(p_actor,p_code,p_resource_type,p_owner,p_party_type,p_party_id) THEN
    RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501';
  END IF;
""")
fn(S,'settings._validate_context','p_actor uuid, p_context jsonb',['uuid','jsonb'],'void',"""
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
""",declare='v_key text; v_value jsonb; v_id uuid;')
fn(S,'settings._validate_value','p_definition settings.setting_definitions, p_value jsonb, p_context jsonb',['settings.setting_definitions','jsonb','jsonb'],'void',"""
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
""",declare='v_key text; v_rule jsonb; v_element jsonb; v_number numeric; v_ok boolean := false;')
fn(S,'settings._resolve','p_actor uuid, p_key text, p_context jsonb',['uuid','text','jsonb'],'jsonb',"""
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
""",declare='''v_definition settings.setting_definitions%ROWTYPE;
v_effective jsonb; v_values jsonb := '{}'::jsonb; v_sources jsonb := '[]'::jsonb;
v_row record; v_scope text; v_value jsonb;''')
fn(S,'settings.resolve',"p_actor uuid, p_key text, p_context jsonb DEFAULT '{}'::jsonb",['uuid','text','jsonb'],'jsonb',"""
  -- Generic inspection can reveal other parties' rules; only an all-scope settings.read grant qualifies.
  PERFORM auth._require_permission(p_actor,'settings.read','settings');
  RETURN settings._resolve(p_actor,p_key,p_context);
""",True)
fn(S,'settings._boolean','p_actor uuid, p_key text, p_context jsonb',['uuid','text','jsonb'],'boolean',"""
  v_result := settings._resolve(p_actor,p_key,p_context);
  IF jsonb_typeof(v_result->'value')<>'boolean' THEN RAISE EXCEPTION 'Required setting must resolve to boolean' USING ERRCODE='22023'; END IF;
  RETURN (v_result->>'value')::boolean;
""",declare='v_result jsonb;')
fn(S,'settings._number','p_actor uuid, p_key text, p_context jsonb',['uuid','text','jsonb'],'numeric',"""
  v_result := settings._resolve(p_actor,p_key,p_context);
  IF jsonb_typeof(v_result->'value')<>'number' THEN RAISE EXCEPTION 'Required setting must resolve to number' USING ERRCODE='22023'; END IF;
  RETURN (v_result->>'value')::numeric;
""",declare='v_result jsonb;')
fn(E,'erp._require_write_context','p_actor uuid, p_reason text',['uuid','text'],'void',"""
  PERFORM auth._require_active_actor(p_actor);
  IF p_reason IS NULL OR btrim(p_reason)='' OR length(p_reason)>2000 THEN RAISE EXCEPTION 'A nonblank reason of at most 2000 characters is required' USING ERRCODE='22023'; END IF;
  -- Product-row locks serialize ledger writers; READ COMMITTED refreshes the aggregate after waiting.
  IF current_setting('transaction_isolation')<>'read committed' THEN
    RAISE EXCEPTION 'ERP write routines require READ COMMITTED' USING ERRCODE='25001';
  END IF;
""")
fn(E,'erp._audit','p_actor uuid, p_action text, p_entity_type text, p_entity_id uuid, p_metadata jsonb',['uuid','text','text','uuid','jsonb'],'void',"""
  INSERT INTO app.audit_events(source_schema,actor_user_id,action,entity_type,entity_id,metadata,occurred_at)
  VALUES ('erp',p_actor,p_action,p_entity_type,p_entity_id::text,p_metadata,clock_timestamp());
""")
fn(E,'erp._validate_quantity','p_actor uuid, p_quantity numeric, p_context jsonb',['uuid','numeric','jsonb'],'void',"""
  IF p_quantity IS NULL OR p_quantity IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
    OR p_quantity=0 OR abs(p_quantity)>=1000000000000000 OR p_quantity<>round(p_quantity,3) THEN
    RAISE EXCEPTION 'Quantity must be finite, nonzero and fit NUMERIC(18,3) exactly' USING ERRCODE='22023';
  END IF;
  v_places := settings._number(p_actor,'quantity.decimal_places',p_context);
  IF trunc(v_places)<>v_places OR v_places<0 OR v_places>3 THEN RAISE EXCEPTION 'Unsupported quantity precision' USING ERRCODE='22023'; END IF;
  IF p_quantity<>round(p_quantity,v_places::integer)
    OR (NOT settings._boolean(p_actor,'quantity.allow_fractional',p_context) AND p_quantity<>trunc(p_quantity)) THEN
    RAISE EXCEPTION 'Quantity violates the effective precision policy' USING ERRCODE='22023';
  END IF;
""",declare='v_places numeric;')
fn(E,'erp.stock_balance','p_actor uuid, p_product uuid, p_warehouse uuid',['uuid','uuid','uuid'],'numeric',"""
  PERFORM auth._require_permission(p_actor,'stock.read','stock');
  IF NOT EXISTS(SELECT 1 FROM erp.products WHERE id=p_product AND kind='stock') OR NOT EXISTS(SELECT 1 FROM erp.warehouses WHERE id=p_warehouse) THEN
    RAISE EXCEPTION 'Stock target unavailable' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(sum(m.quantity_delta),0) INTO v_balance FROM erp.stock_movements m WHERE m.product_id=p_product AND m.warehouse_id=p_warehouse;
  RETURN v_balance;
""",True,'v_balance numeric;')
fn(E,'erp._check_stock_result','p_actor uuid, p_product uuid, p_warehouse uuid, p_delta numeric, p_context jsonb',['uuid','uuid','uuid','numeric','jsonb'],'jsonb',"""
  v_negative := settings._resolve(p_actor,'stock.allow_negative_balance',p_context);
  v_available := settings._resolve(p_actor,'stock.require_available_quantity',p_context);
  IF jsonb_typeof(v_negative->'value')<>'boolean' OR jsonb_typeof(v_available->'value')<>'boolean' THEN RAISE EXCEPTION 'Invalid stock policy type' USING ERRCODE='22023'; END IF;
  SELECT coalesce(sum(quantity_delta),0) INTO v_balance FROM erp.stock_movements WHERE product_id=p_product AND warehouse_id=p_warehouse;
  IF v_balance+p_delta<0 AND ((v_negative->>'value')::boolean IS NOT TRUE OR (v_available->>'value')::boolean) THEN
    RAISE EXCEPTION 'Insufficient stock under the effective policy' USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('before',v_balance,'after',v_balance+p_delta,'negative_balance_policy',v_negative,'available_quantity_policy',v_available);
""",declare='v_balance numeric; v_negative jsonb; v_available jsonb;')
fn(E,'erp.adjust_stock','p_actor uuid, p_product uuid, p_warehouse uuid, p_delta numeric, p_key text, p_reason text',['uuid','uuid','uuid','numeric','text','text'],'uuid',"""
  PERFORM erp._require_write_context(p_actor,p_reason);
  PERFORM auth._require_permission(p_actor,'stock.adjust','stock');
  IF p_key IS NULL OR btrim(p_key)='' OR length(p_key)>120 THEN RAISE EXCEPTION 'Invalid idempotency key' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('hanouti.stock:'||p_key,0));
  SELECT * INTO v_existing FROM erp.stock_movements WHERE idempotency_key='adj:'||p_key;
  IF FOUND THEN
    IF v_existing.kind IS DISTINCT FROM 'adjustment' OR v_existing.product_id IS DISTINCT FROM p_product
      OR v_existing.warehouse_id IS DISTINCT FROM p_warehouse OR v_existing.quantity_delta IS DISTINCT FROM p_delta
      OR v_existing.recorded_by_user_id IS DISTINCT FROM p_actor OR v_existing.reason IS DISTINCT FROM p_reason THEN
      RAISE EXCEPTION 'Idempotency key conflicts with an earlier request' USING ERRCODE='23505';
    END IF;
    RETURN v_existing.id;
  END IF;
  PERFORM 1 FROM erp.products WHERE id=p_product AND is_active AND kind='stock' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active stock product required' USING ERRCODE='22023'; END IF;
  PERFORM 1 FROM erp.warehouses WHERE id=p_warehouse AND is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active warehouse required' USING ERRCODE='22023'; END IF;
  v_context := jsonb_build_object('product',p_product,'warehouse',p_warehouse,'document_kind','stock_adjustment');
  PERFORM erp._validate_quantity(p_actor,p_delta,v_context);
  IF settings._boolean(p_actor,'stock.require_adjustment_approval',v_context) THEN
    RAISE EXCEPTION 'Approval workflow required; direct adjustment is disabled' USING ERRCODE='42501';
  END IF;
  v_effect := erp._check_stock_result(p_actor,p_product,p_warehouse,p_delta,v_context);
  INSERT INTO erp.stock_movements(product_id,warehouse_id,kind,quantity_delta,idempotency_key,reason,recorded_by_user_id,occurred_at)
  VALUES(p_product,p_warehouse,'adjustment',p_delta,'adj:'||p_key,p_reason,p_actor,clock_timestamp()) RETURNING id INTO v_id;
  PERFORM erp._audit(p_actor,'stock.adjust','stock_movement',v_id,jsonb_build_object('product_id',p_product,'warehouse_id',p_warehouse,'quantity_delta',p_delta,'reason',p_reason,'stock',v_effect));
  RETURN v_id;
""",True,'v_existing erp.stock_movements%ROWTYPE; v_context jsonb; v_effect jsonb; v_id uuid;')
fn(E,'erp.transfer_stock','p_actor uuid, p_product uuid, p_from uuid, p_to uuid, p_quantity numeric, p_key text, p_reason text',['uuid','uuid','uuid','uuid','numeric','text','text'],'uuid',"""
  PERFORM erp._require_write_context(p_actor,p_reason);
  PERFORM auth._require_permission(p_actor,'stock.transfer','stock');
  IF p_from IS NULL OR p_to IS NULL OR p_from=p_to THEN RAISE EXCEPTION 'Transfer requires two different warehouses' USING ERRCODE='22023'; END IF;
  IF p_key IS NULL OR btrim(p_key)='' OR length(p_key)>120 THEN RAISE EXCEPTION 'Invalid idempotency key' USING ERRCODE='22023'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('hanouti.stock:'||p_key,0));
  SELECT * INTO v_out FROM erp.stock_movements WHERE idempotency_key='out:'||p_key;
  SELECT * INTO v_in FROM erp.stock_movements WHERE idempotency_key='in:'||p_key;
  IF v_out.id IS NOT NULL OR v_in.id IS NOT NULL THEN
    IF v_out.id IS NULL OR v_in.id IS NULL OR v_out.kind IS DISTINCT FROM 'transfer_out' OR v_in.kind IS DISTINCT FROM 'transfer_in'
      OR v_out.transfer_group_id IS NULL OR v_out.transfer_group_id IS DISTINCT FROM v_in.transfer_group_id
      OR v_out.product_id IS DISTINCT FROM p_product OR v_in.product_id IS DISTINCT FROM p_product
      OR v_out.warehouse_id IS DISTINCT FROM p_from OR v_in.warehouse_id IS DISTINCT FROM p_to
      OR v_out.quantity_delta IS DISTINCT FROM -p_quantity OR v_in.quantity_delta IS DISTINCT FROM p_quantity
      OR v_out.recorded_by_user_id IS DISTINCT FROM p_actor OR v_in.recorded_by_user_id IS DISTINCT FROM p_actor
      OR v_out.reason IS DISTINCT FROM p_reason OR v_in.reason IS DISTINCT FROM p_reason THEN
      RAISE EXCEPTION 'Idempotency key conflicts with an earlier request' USING ERRCODE='23505';
    END IF;
    RETURN v_out.transfer_group_id;
  END IF;
  PERFORM 1 FROM erp.products WHERE id=p_product AND is_active AND kind='stock' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active stock product required' USING ERRCODE='22023'; END IF;
  -- Ordered warehouse locks avoid inversions between opposite transfers.
  PERFORM 1 FROM erp.warehouses WHERE id IN(p_from,p_to) AND is_active ORDER BY id FOR SHARE;
  IF (SELECT count(*) FROM erp.warehouses WHERE id IN(p_from,p_to) AND is_active)<>2 THEN RAISE EXCEPTION 'Active warehouses required' USING ERRCODE='22023'; END IF;
  IF p_quantity IS NULL OR p_quantity<=0 THEN RAISE EXCEPTION 'Transfer quantity must be positive' USING ERRCODE='22023'; END IF;
  v_from_context:=jsonb_build_object('product',p_product,'warehouse',p_from,'document_kind','stock_transfer');
  v_to_context:=jsonb_build_object('product',p_product,'warehouse',p_to,'document_kind','stock_transfer');
  PERFORM erp._validate_quantity(p_actor,p_quantity,v_from_context);
  PERFORM erp._validate_quantity(p_actor,p_quantity,v_to_context);
  IF settings._boolean(p_actor,'stock.require_transfer_approval',v_from_context)
    OR settings._boolean(p_actor,'stock.require_transfer_approval',v_to_context) THEN
    RAISE EXCEPTION 'Approval workflow required; direct transfer is disabled' USING ERRCODE='42501';
  END IF;
  v_from_effect:=erp._check_stock_result(p_actor,p_product,p_from,-p_quantity,v_from_context);
  v_to_effect:=erp._check_stock_result(p_actor,p_product,p_to,p_quantity,v_to_context);
  v_group:=gen_random_uuid();
  INSERT INTO erp.stock_movements(product_id,warehouse_id,kind,quantity_delta,transfer_group_id,idempotency_key,reason,recorded_by_user_id,occurred_at)
  VALUES(p_product,p_from,'transfer_out',-p_quantity,v_group,'out:'||p_key,p_reason,p_actor,clock_timestamp()),
        (p_product,p_to,'transfer_in',p_quantity,v_group,'in:'||p_key,p_reason,p_actor,clock_timestamp());
  PERFORM erp._audit(p_actor,'stock.transfer','stock_transfer',v_group,jsonb_build_object('product_id',p_product,'from_warehouse',p_from,'to_warehouse',p_to,'quantity',p_quantity,'reason',p_reason,'source_stock',v_from_effect,'destination_stock',v_to_effect));
  RETURN v_group;
""",True,'v_out erp.stock_movements%ROWTYPE; v_in erp.stock_movements%ROWTYPE; v_from_context jsonb; v_to_context jsonb; v_from_effect jsonb; v_to_effect jsonb; v_group uuid;')
# More routines are appended below before file emission.
fn(E,'erp._save_order_draft','p_actor uuid, p_kind text, p_document jsonb, p_reason text, p_order_id uuid, p_expected_updated_at timestamptz',['uuid','text','jsonb','text','uuid','timestamptz'],'jsonb',"""
  PERFORM erp._require_write_context(p_actor,p_reason);
  IF p_kind IS NULL OR p_kind NOT IN ('sales','purchase') OR p_document IS NULL OR jsonb_typeof(p_document)<>'object' THEN RAISE EXCEPTION 'Invalid draft document' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_document) k WHERE k NOT IN ('order_number','customer_id','supplier_id','warehouse_id','currency_code','notes','expected_on','lines')) THEN RAISE EXCEPTION 'Unsupported draft field' USING ERRCODE='22023'; END IF;
  IF (p_kind='sales' AND (p_document ? 'supplier_id' OR p_document ? 'expected_on')) OR (p_kind='purchase' AND p_document ? 'customer_id') THEN RAISE EXCEPTION 'Field belongs to another document kind' USING ERRCODE='22023'; END IF;
  IF jsonb_typeof(p_document->'order_number') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_document->'currency_code') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_document->'warehouse_id') IS DISTINCT FROM 'string'
    OR jsonb_typeof(p_document->'lines') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Draft header and lines are required' USING ERRCODE='22023'; END IF;
  IF btrim(p_document->>'order_number')='' OR length(p_document->>'order_number')>64
    OR (p_document->>'currency_code') !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Invalid order number or currency' USING ERRCODE='22023'; END IF;
  IF p_document ? 'notes' AND jsonb_typeof(p_document->'notes') NOT IN ('string','null') THEN RAISE EXCEPTION 'Notes must be text or null' USING ERRCODE='22023'; END IF;
  IF length(p_document->>'notes')>4000 OR jsonb_array_length(p_document->'lines')>1000 THEN RAISE EXCEPTION 'Draft size limit exceeded' USING ERRCODE='22023'; END IF;
  v_party_type:=CASE WHEN p_kind='sales' THEN 'customer' ELSE 'supplier' END;
  v_party_key:=v_party_type||'_id';
  IF p_document ? v_party_key AND jsonb_typeof(p_document->v_party_key) NOT IN ('string','null') THEN RAISE EXCEPTION 'Invalid party field' USING ERRCODE='22023'; END IF;
  v_party:=(p_document->>v_party_key)::uuid;
  v_warehouse:=(p_document->>'warehouse_id')::uuid;
  v_currency:=p_document->>'currency_code';
  IF p_kind='purchase' AND v_party IS NULL THEN RAISE EXCEPTION 'Supplier required' USING ERRCODE='22023'; END IF;
  IF p_document ? 'expected_on' AND p_document->'expected_on'<>'null'::jsonb THEN
    IF jsonb_typeof(p_document->'expected_on')<>'string' OR (p_document->>'expected_on') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'Invalid expected date' USING ERRCODE='22023'; END IF;
    v_expected_on:=(p_document->>'expected_on')::date;
  END IF;
  v_owner:=p_actor;
  v_id:=p_order_id;
  IF v_id IS NOT NULL THEN
    IF p_kind='sales' THEN
      SELECT created_by_user_id,updated_at,status,order_number,customer_id,warehouse_id,currency_code
        INTO v_old FROM erp.sales_orders WHERE id=v_id FOR UPDATE;
    ELSE
      SELECT created_by_user_id,updated_at,status,order_number,supplier_id AS customer_id,warehouse_id,currency_code
        INTO v_old FROM erp.purchase_orders WHERE id=v_id FOR UPDATE;
    END IF;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='42501'; END IF;
    v_owner:=v_old.created_by_user_id;
    PERFORM auth._require_permission(p_actor,'order.'||p_kind||'.update_draft',p_kind||'_order',v_owner,
      CASE WHEN v_old.customer_id IS NULL THEN NULL ELSE v_party_type END,v_old.customer_id);
    IF v_old.status<>'draft' THEN RAISE EXCEPTION 'Only drafts may be edited' USING ERRCODE='23514'; END IF;
    IF p_expected_updated_at IS NULL OR p_expected_updated_at IS DISTINCT FROM v_old.updated_at THEN RAISE EXCEPTION 'Draft changed; reload before editing' USING ERRCODE='40001'; END IF;
    IF v_old.order_number IS DISTINCT FROM p_document->>'order_number' OR v_old.customer_id IS DISTINCT FROM v_party
      OR v_old.warehouse_id IS DISTINCT FROM v_warehouse OR v_old.currency_code IS DISTINCT FROM v_currency THEN
      RAISE EXCEPTION 'Draft identity, party, warehouse and currency cannot be reassigned by this routine' USING ERRCODE='22023';
    END IF;
    IF (p_kind='sales' AND EXISTS(SELECT 1 FROM erp.payments WHERE sales_order_id=v_id))
      OR (p_kind='sales' AND EXISTS(SELECT 1 FROM erp.stock_movements m JOIN erp.sales_order_items i ON i.id=m.sales_order_item_id WHERE i.sales_order_id=v_id))
      OR (p_kind='purchase' AND EXISTS(SELECT 1 FROM erp.stock_movements m JOIN erp.purchase_order_items i ON i.id=m.purchase_order_item_id WHERE i.purchase_order_id=v_id)) THEN
      RAISE EXCEPTION 'Draft has downstream records and cannot be replaced' USING ERRCODE='23514';
    END IF;
    v_updated:=greatest(clock_timestamp(),v_old.updated_at+interval '1 microsecond');
  ELSE
    IF p_expected_updated_at IS NOT NULL THEN RAISE EXCEPTION 'New drafts cannot have an edit token' USING ERRCODE='22023'; END IF;
    PERFORM auth._require_permission(p_actor,'order.'||p_kind||'.create_draft',p_kind||'_order',p_actor,
      CASE WHEN v_party IS NULL THEN NULL ELSE v_party_type END,v_party);
    v_id:=gen_random_uuid(); v_updated:=clock_timestamp();
  END IF;
  PERFORM 1 FROM erp.warehouses WHERE id=v_warehouse AND is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active warehouse required' USING ERRCODE='22023'; END IF;
  IF v_party IS NOT NULL THEN
    IF p_kind='sales' THEN SELECT jsonb_build_object('name',name) INTO v_snapshot FROM erp.customers WHERE id=v_party AND is_active;
    ELSE SELECT jsonb_build_object('name',name) INTO v_snapshot FROM erp.suppliers WHERE id=v_party AND is_active; END IF;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active party required' USING ERRCODE='22023'; END IF;
  ELSE v_snapshot:='{}'::jsonb;
  END IF;
  IF p_order_id IS NULL THEN
    IF p_kind='sales' THEN
      INSERT INTO erp.sales_orders(id,order_number,customer_id,warehouse_id,currency_code,customer_snapshot,notes,created_by_user_id,updated_at)
        VALUES(v_id,p_document->>'order_number',v_party,v_warehouse,v_currency,v_snapshot,p_document->>'notes',p_actor,v_updated);
    ELSE
      INSERT INTO erp.purchase_orders(id,order_number,supplier_id,warehouse_id,currency_code,supplier_snapshot,notes,expected_on,created_by_user_id,updated_at)
        VALUES(v_id,p_document->>'order_number',v_party,v_warehouse,v_currency,v_snapshot,p_document->>'notes',v_expected_on,p_actor,v_updated);
    END IF;
  ELSE
    IF p_kind='sales' THEN
      DELETE FROM erp.sales_order_items WHERE sales_order_id=v_id;
      UPDATE erp.sales_orders SET notes=p_document->>'notes',updated_at=v_updated WHERE id=v_id;
    ELSE
      DELETE FROM erp.purchase_order_items WHERE purchase_order_id=v_id;
      UPDATE erp.purchase_orders SET notes=p_document->>'notes',expected_on=v_expected_on,updated_at=v_updated WHERE id=v_id;
    END IF;
  END IF;
  v_base:=jsonb_build_object('warehouse',v_warehouse,'currency',v_currency,'document_kind',p_kind||'_order');
  IF v_party IS NOT NULL THEN v_base:=v_base||jsonb_build_object(v_party_type,v_party); END IF;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_document->'lines') LOOP
    v_position:=v_position+1;
    IF jsonb_typeof(v_line)<>'object' THEN RAISE EXCEPTION 'Each draft line must be an object' USING ERRCODE='22023'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(v_line) k WHERE k NOT IN ('product_id','quantity','unit_price','unit_cost','discount_amount','tax_amount'))
      OR (p_kind='sales' AND v_line ? 'unit_cost') OR (p_kind='purchase' AND v_line ? 'unit_price') THEN RAISE EXCEPTION 'Unsupported draft line field' USING ERRCODE='22023'; END IF;
    IF jsonb_typeof(v_line->'product_id') IS DISTINCT FROM 'string' OR jsonb_typeof(v_line->'quantity') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Product and numeric quantity required' USING ERRCODE='22023'; END IF;
    v_product_id:=(v_line->>'product_id')::uuid;
    SELECT id,sku,name,unit_code,sale_price,currency_code INTO v_product FROM erp.products WHERE id=v_product_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active product required' USING ERRCODE='22023'; END IF;
    v_context:=v_base||jsonb_build_object('product',v_product_id);
    v_quantity:=(v_line->>'quantity')::numeric;
    PERFORM erp._validate_quantity(p_actor,v_quantity,v_context);
    IF v_quantity<=0 THEN RAISE EXCEPTION 'Order quantities must be positive; use a separately reviewed return workflow' USING ERRCODE='23514'; END IF;
    v_price_key:=CASE WHEN p_kind='sales' THEN 'unit_price' ELSE 'unit_cost' END;
    IF v_line ? v_price_key THEN
      IF jsonb_typeof(v_line->v_price_key)<>'number' THEN RAISE EXCEPTION 'Price or cost must be numeric' USING ERRCODE='22023'; END IF;
      v_price:=(v_line->>v_price_key)::numeric;
    ELSIF p_kind='sales' THEN v_price:=v_product.sale_price;
    ELSE RAISE EXCEPTION 'Purchase unit_cost required' USING ERRCODE='22023'; END IF;
    IF (v_line ? 'discount_amount' AND jsonb_typeof(v_line->'discount_amount')<>'number')
      OR (v_line ? 'tax_amount' AND jsonb_typeof(v_line->'tax_amount')<>'number') THEN RAISE EXCEPTION 'Discount and tax amounts must be numeric' USING ERRCODE='22023'; END IF;
    v_discount:=coalesce((v_line->>'discount_amount')::numeric,0);
    v_tax:=coalesce((v_line->>'tax_amount')::numeric,0);
    FOREACH v_amount IN ARRAY ARRAY[v_price,v_discount,v_tax] LOOP
      IF v_amount IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) OR v_amount<0 OR v_amount>=100000000000000 OR v_amount<>round(v_amount,4) THEN RAISE EXCEPTION 'Money must fit nonnegative NUMERIC(18,4) exactly' USING ERRCODE='22023'; END IF;
    END LOOP;
    IF v_price=0 AND NOT settings._boolean(p_actor,'pricing.allow_zero_unit_price',v_context) THEN RAISE EXCEPTION 'Zero price or cost is disabled' USING ERRCODE='23514'; END IF;
    IF p_kind='sales' THEN
      IF v_product.currency_code<>v_currency THEN RAISE EXCEPTION 'No currency conversion is configured for catalog sales prices' USING ERRCODE='22023'; END IF;
      IF v_price<>v_product.sale_price THEN
        IF NOT settings._boolean(p_actor,'pricing.allow_manual_price',v_context) THEN RAISE EXCEPTION 'Manual sales pricing is disabled' USING ERRCODE='42501'; END IF;
        PERFORM auth._require_permission(p_actor,'pricing.override','pricing',v_owner,CASE WHEN v_party IS NULL THEN NULL ELSE v_party_type END,v_party);
      END IF;
    END IF;
    IF v_discount>v_quantity*v_price THEN RAISE EXCEPTION 'Discount exceeds gross line value' USING ERRCODE='23514'; END IF;
    IF v_discount>0 THEN
      PERFORM auth._require_permission(p_actor,'discount.apply','pricing',v_owner,CASE WHEN v_party IS NULL THEN NULL ELSE v_party_type END,v_party);
      v_cap:=settings._number(p_actor,'discount.max_line_percent',v_context||jsonb_build_object('unit','percent'));
      v_threshold:=settings._number(p_actor,'discount.require_approval_above_percent',v_context||jsonb_build_object('unit','percent'));
      IF v_cap<0 OR v_cap>100 OR v_threshold<0 OR v_threshold>100 THEN RAISE EXCEPTION 'Invalid discount limit' USING ERRCODE='22023'; END IF;
      IF v_discount*100>v_quantity*v_price*v_cap THEN RAISE EXCEPTION 'Discount exceeds effective limit' USING ERRCODE='23514'; END IF;
      IF v_discount*100>v_quantity*v_price*v_threshold THEN RAISE EXCEPTION 'Discount approval workflow required' USING ERRCODE='42501'; END IF;
    END IF;
    IF v_tax>0 THEN
      PERFORM auth._require_permission(p_actor,'order.tax.edit','order',v_owner,CASE WHEN v_party IS NULL THEN NULL ELSE v_party_type END,v_party);
    END IF;
    IF p_kind='sales' THEN
      INSERT INTO erp.sales_order_items(sales_order_id,line_number,product_id,sku_snapshot,description,unit_code,quantity,unit_price,discount_amount,tax_amount)
        VALUES(v_id,v_position,v_product_id,v_product.sku,v_product.name,v_product.unit_code,v_quantity,v_price,v_discount,v_tax);
    ELSE
      INSERT INTO erp.purchase_order_items(purchase_order_id,line_number,product_id,sku_snapshot,description,unit_code,quantity,unit_cost,discount_amount,tax_amount)
        VALUES(v_id,v_position,v_product_id,v_product.sku,v_product.name,v_product.unit_code,v_quantity,v_price,v_discount,v_tax);
    END IF;
  END LOOP;
  PERFORM erp._audit(p_actor,'order.'||p_kind||CASE WHEN p_order_id IS NULL THEN '.create_draft' ELSE '.update_draft' END,
    p_kind||'_order',v_id,jsonb_build_object('line_count',v_position,'reason',p_reason,'updated_at',v_updated));
  RETURN jsonb_build_object('id',v_id,'status','draft','updated_at',v_updated,'line_count',v_position);
""",declare='''v_party_type text; v_party_key text; v_party uuid; v_warehouse uuid; v_currency text;
v_owner uuid; v_id uuid; v_old record; v_updated timestamptz; v_expected_on date;
v_snapshot jsonb; v_line jsonb; v_position integer := 0; v_base jsonb; v_context jsonb;
v_product_id uuid; v_product record; v_quantity numeric; v_price_key text; v_price numeric;
v_discount numeric; v_tax numeric; v_amount numeric; v_cap numeric; v_threshold numeric;''')
for kind in ('sales','purchase'):
 fn(E,f'erp.save_{kind}_order_draft',"p_actor uuid, p_document jsonb, p_reason text, p_order_id uuid DEFAULT NULL, p_expected_updated_at timestamptz DEFAULT NULL",['uuid','jsonb','text','uuid','timestamptz'],'jsonb',f"RETURN erp._save_order_draft(p_actor,'{kind}',p_document,p_reason,p_order_id,p_expected_updated_at);",True)
fn(E,'erp.order_totals','p_actor uuid, p_kind text, p_order_id uuid',['uuid','text','uuid'],'jsonb',"""
  IF p_kind='sales' THEN
    SELECT id,created_by_user_id,customer_id AS party_id,currency_code,status,updated_at INTO v_order FROM erp.sales_orders WHERE id=p_order_id FOR SHARE;
  ELSIF p_kind='purchase' THEN
    SELECT id,created_by_user_id,supplier_id AS party_id,currency_code,status,updated_at INTO v_order FROM erp.purchase_orders WHERE id=p_order_id FOR SHARE;
  ELSE RAISE EXCEPTION 'Unsupported order kind' USING ERRCODE='22023'; END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='42501'; END IF;
  PERFORM auth._require_permission(p_actor,'order.'||p_kind||'.read',p_kind||'_order',v_order.created_by_user_id,
    CASE WHEN v_order.party_id IS NULL THEN NULL WHEN p_kind='sales' THEN 'customer' ELSE 'supplier' END,v_order.party_id);
  IF p_kind='sales' THEN
    SELECT count(*) AS lines,coalesce(sum(quantity*unit_price),0) AS gross,coalesce(sum(discount_amount),0) AS discount,
      coalesce(sum(tax_amount),0) AS tax,coalesce(sum(line_total),0) AS total INTO v_totals FROM erp.sales_order_items WHERE sales_order_id=p_order_id;
  ELSE
    SELECT count(*) AS lines,coalesce(sum(quantity*unit_cost),0) AS gross,coalesce(sum(discount_amount),0) AS discount,
      coalesce(sum(tax_amount),0) AS tax,coalesce(sum(line_total),0) AS total INTO v_totals FROM erp.purchase_order_items WHERE purchase_order_id=p_order_id;
  END IF;
  RETURN jsonb_build_object('id',p_order_id,'kind',p_kind,'currency',v_order.currency_code,'status',v_order.status,'updated_at',v_order.updated_at,
    'line_count',v_totals.lines,'gross',v_totals.gross,'discount',v_totals.discount,'tax',v_totals.tax,'total',v_totals.total);
""",True,'v_order record; v_totals record;')
fn(E,'erp.order_detail','p_actor uuid, p_kind text, p_order_id uuid',['uuid','text','uuid'],'jsonb',"""
  v_totals:=erp.order_totals(p_actor,p_kind,p_order_id);
  IF p_kind='sales' THEN
    SELECT jsonb_build_object('order_number',order_number,'customer_id',customer_id,'warehouse_id',warehouse_id,'currency_code',currency_code,'notes',notes)
      INTO v_header FROM erp.sales_orders WHERE id=p_order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity,'unit_price',unit_price,'discount_amount',discount_amount,'tax_amount',tax_amount) ORDER BY line_number),'[]'::jsonb)
      INTO v_lines FROM erp.sales_order_items WHERE sales_order_id=p_order_id;
  ELSE
    SELECT jsonb_build_object('order_number',order_number,'supplier_id',supplier_id,'warehouse_id',warehouse_id,'currency_code',currency_code,'notes',notes,'expected_on',expected_on)
      INTO v_header FROM erp.purchase_orders WHERE id=p_order_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity,'unit_cost',unit_cost,'discount_amount',discount_amount,'tax_amount',tax_amount) ORDER BY line_number),'[]'::jsonb)
      INTO v_lines FROM erp.purchase_order_items WHERE purchase_order_id=p_order_id;
  END IF;
  RETURN jsonb_build_object('summary',v_totals,'document',v_header||jsonb_build_object('lines',v_lines));
""",True,'v_totals jsonb; v_header jsonb; v_lines jsonb;')
fn(E,'erp.sales_payment_balance','p_actor uuid, p_order_id uuid',['uuid','uuid'],'jsonb',"""
  v_totals:=erp.order_totals(p_actor,'sales',p_order_id);
  SELECT created_by_user_id,customer_id INTO v_order FROM erp.sales_orders WHERE id=p_order_id;
  PERFORM auth._require_permission(p_actor,'payment.read','payment',v_order.created_by_user_id,
    CASE WHEN v_order.customer_id IS NULL THEN NULL ELSE 'customer' END,v_order.customer_id);
  SELECT coalesce(sum(amount) FILTER(WHERE direction='receipt'),0),coalesce(sum(amount) FILTER(WHERE direction='refund'),0)
    INTO v_receipts,v_refunds FROM erp.payments WHERE sales_order_id=p_order_id AND status='completed';
  RETURN jsonb_build_object('order_id',p_order_id,'currency',v_totals->>'currency','order_total',v_totals->'total',
    'completed_receipts',v_receipts,'completed_refunds',v_refunds,'net_paid',v_receipts-v_refunds,
    'balance',(v_totals->>'total')::numeric-v_receipts+v_refunds);
""",True,'v_totals jsonb; v_order record; v_receipts numeric; v_refunds numeric;')
for file,definitions in files.items():
 text='-- UNAPPLIED DECLARATIONS ONLY. Target: hanouti. No connection, execution or grants to business users.\n'
 text+='-- SECURITY DEFINER deployment requires the restricted owner/runtime template; see ERP_ROUTINES.md.\n'
 text+='BEGIN;\n\n'+'\n'.join(definitions)+'\nCOMMIT;\n'
 (ROOT/'migrations/hanouti'/file).write_text(text)
(ROOT/'tests/fixtures/routines-manifest.json').write_text(json.dumps(registry,indent=2)+'\n')
# Optional deployment is intentionally separate from the normal declarations.
role_sql='''-- OPTIONAL UNAPPLIED PRIVILEGE TEMPLATE. Review ERP_ROUTINES.md first.
-- Run as a provisioning administrator ONLY after 001..009 and before granting backend access.
-- Fails if roles already exist: review existing privileges rather than silently inheriting them.
-- These are PostgreSQL roles, NOT business roles in auth.roles. Neither can log in directly.
BEGIN;
CREATE ROLE hanouti_routine_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE hanouti_backend NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE, CREATE ON SCHEMA auth, erp, app, settings TO hanouti_routine_owner;
GRANT USAGE ON SCHEMA auth, erp, settings TO hanouti_backend;
GRANT SELECT (id,status) ON auth.users TO hanouti_routine_owner;
GRANT SELECT ON auth.permissions, auth.user_roles, auth.role_permissions, auth.subject_permissions, auth.party_memberships TO hanouti_routine_owner;
GRANT SELECT ON settings.setting_definitions, settings.gsettings, settings.settings TO hanouti_routine_owner;
GRANT SELECT (id,name,is_active) ON erp.customers, erp.suppliers TO hanouti_routine_owner;
GRANT SELECT (id,sku,name,unit_code,sale_price,currency_code,kind,is_active) ON erp.products TO hanouti_routine_owner;
GRANT SELECT ON erp.warehouses, erp.sales_orders, erp.sales_order_items, erp.purchase_orders, erp.purchase_order_items, erp.payments, erp.stock_movements TO hanouti_routine_owner;
-- A column UPDATE privilege is needed for SELECT ... FOR UPDATE / SHARE; no runtime table grants.
GRANT UPDATE (id) ON erp.products, erp.warehouses TO hanouti_routine_owner;
GRANT INSERT, UPDATE ON erp.sales_orders, erp.purchase_orders TO hanouti_routine_owner;
GRANT INSERT, DELETE ON erp.sales_order_items, erp.purchase_order_items TO hanouti_routine_owner;
GRANT INSERT ON erp.stock_movements, app.audit_events TO hanouti_routine_owner;
'''
for r in registry:
 role_sql+=f'ALTER FUNCTION {r["signature"]} OWNER TO hanouti_routine_owner;\n'
 if r['exposed']:role_sql+=f'GRANT EXECUTE ON FUNCTION {r["signature"]} TO hanouti_backend;\n'
role_sql+='''REVOKE CREATE ON SCHEMA auth, erp, app, settings FROM hanouti_routine_owner;
-- The application login must be a NON-superuser with NO table rights or owner membership.
-- After auditing all inherited grants, an operator may grant hanouti_backend to that login.
-- Do not grant hanouti_routine_owner to the backend or end users.
COMMIT;
'''
(ROOT/'seeds/020_erp_routine_privileges.sql').write_text(role_sql)
print('Declared',len(registry),'routines;',sum(r['exposed'] for r in registry),'public entry points. No SQL executed.')
