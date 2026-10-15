-- UNAPPLIED DECLARATIONS ONLY. Target: hanouti. No connection, execution or grants to business users.
-- SECURITY DEFINER deployment requires the restricted owner/runtime template; see ERP_ROUTINES.md.
BEGIN;

CREATE FUNCTION auth._require_active_actor(p_actor uuid)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
IF p_actor IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=p_actor AND u.status='active') THEN
    RAISE EXCEPTION 'Active authenticated actor required' USING ERRCODE='42501';
  END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION auth._require_active_actor(uuid) FROM PUBLIC;

CREATE FUNCTION auth._party_member(p_actor uuid, p_party_type text, p_party_id uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
RETURN EXISTS (
    SELECT 1 FROM auth.party_memberships m
    WHERE m.user_id=p_actor AND m.party_type=p_party_type AND m.party_id=p_party_id
      AND m.status='active' AND m.can_act_on_behalf AND m.verified_at <= statement_timestamp()
      AND m.revoked_at IS NULL AND m.valid_from <= statement_timestamp()
      AND (m.valid_until IS NULL OR m.valid_until > statement_timestamp())
      AND ((p_party_type='customer' AND EXISTS (SELECT 1 FROM erp.customers c WHERE c.id=p_party_id AND c.is_active))
        OR (p_party_type='supplier' AND EXISTS (SELECT 1 FROM erp.suppliers s WHERE s.id=p_party_id AND s.is_active)))
  );
END;
$fn$;
REVOKE ALL ON FUNCTION auth._party_member(uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION auth.has_permission(p_actor uuid, p_code text, p_resource_type text, p_owner uuid DEFAULT NULL, p_party_type text DEFAULT NULL, p_party_id uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
v_permission auth.permissions%ROWTYPE;
v_rule record;
v_member boolean;
v_allow boolean := false;
BEGIN
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
END;
$fn$;
REVOKE ALL ON FUNCTION auth.has_permission(uuid, text, text, uuid, text, uuid) FROM PUBLIC;

CREATE FUNCTION auth._require_permission(p_actor uuid, p_code text, p_resource_type text, p_owner uuid DEFAULT NULL, p_party_type text DEFAULT NULL, p_party_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
IF NOT auth.has_permission(p_actor,p_code,p_resource_type,p_owner,p_party_type,p_party_id) THEN
    RAISE EXCEPTION 'Permission denied' USING ERRCODE='42501';
  END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION auth._require_permission(uuid, text, text, uuid, text, uuid) FROM PUBLIC;

COMMIT;
