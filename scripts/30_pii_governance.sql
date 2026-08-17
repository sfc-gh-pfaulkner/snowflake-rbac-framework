-- ============================================================================
-- RBAC FRAMEWORK: Step 20 - PII Governance (Tags, Masking Policies, Roles)
-- ============================================================================
-- Purpose: Creates PII tagging and masking infrastructure in GOVERNANCE_DB.
--          Tag-based masking policies automatically mask PII columns unless the
--          querying role has the appropriate PII access role in session.
--
-- Prerequisites: Script 00 (GOVERNANCE_DB exists)
-- Run as: ACCOUNTADMIN (pass --role ACCOUNTADMIN on the CLI)
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Create ACCESS_CONTROL schema in GOVERNANCE_DB
-- ─────────────────────────────────────────────────────────────────────────────
create schema if not exists GOVERNANCE_DB.ACCESS_CONTROL
    with managed access
    comment = 'Masking policies and access control objects.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Create PII tags (in ADMIN_DB.TAGS alongside ENVIRONMENT and DOMAIN)
-- ─────────────────────────────────────────────────────────────────────────────
create tag if not exists ADMIN_DB.TAGS.PII_CATEGORY
    allowed_values 'NAME', 'ADDRESS', 'EMAIL', 'PHONE', 'SENSITIVE_DATE', 'BANK_DETAIL', 'NATIONAL_ID', 'FINANCIAL_PROFILE'
    comment = 'Identifies the type of personal data in the column.';

create tag if not exists ADMIN_DB.TAGS.PII_CLASSIFICATION
    allowed_values 'CONFIDENTIAL', 'SENSITIVE'
    comment = 'Sensitivity level — determines masking behaviour.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. PII access roles (PII_<domain>_FULL_ACCESS, PII_<domain>_PARTIAL_ACCESS)
--    These are provisioned by Okta SCIM — NOT created here.
--    See the PII governance design document for the operating model.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Detach existing policies from tag (allows CREATE OR REPLACE on re-run)
--    Silently ignored on first run when policies don't exist yet.
-- ─────────────────────────────────────────────────────────────────────────────
execute immediate $$
begin
    alter tag ADMIN_DB.TAGS.PII_CLASSIFICATION unset
        masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_STRING_PII_BY_DOMAIN,
        masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_NUMBER_PII_BY_DOMAIN,
        masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_DATE_PII_BY_DOMAIN;
exception
    when other then NULL;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Masking policy: STRING
-- ─────────────────────────────────────────────────────────────────────────────
create or replace masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_STRING_PII_BY_DOMAIN
    as (VAL string) returns string ->
    case
        when system$get_tag_on_current_column('ADMIN_DB.TAGS.PII_CLASSIFICATION')
            is null
            then VAL
        when coalesce(system$get_tag_on_current_table('ADMIN_DB.TAGS.DOMAIN'), '')
            = ''
            then '***MASKED***'
        when is_role_in_session(
            'PII_' ||
            upper(system$get_tag_on_current_table('ADMIN_DB.TAGS.DOMAIN')) ||
            '_FULL_ACCESS'
        )
            then VAL
        when is_role_in_session(
            'PII_' ||
            upper(system$get_tag_on_current_table('ADMIN_DB.TAGS.DOMAIN')) ||
            '_PARTIAL_ACCESS'
        )
            then
                case upper(system$get_tag_on_current_column('ADMIN_DB.TAGS.PII_CLASSIFICATION'))
                    when 'SENSITIVE' then '***MASKED***'
                    when 'CONFIDENTIAL' then left(VAL, 1) || repeat('*', greatest(length(VAL) - 1, 0))
                    else '***MASKED***'
                end
        else '***MASKED***'
    end;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Masking policy: NUMBER
-- ─────────────────────────────────────────────────────────────────────────────
create or replace masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_NUMBER_PII_BY_DOMAIN
    as (VAL number) returns number ->
    case
        when system$get_tag_on_current_column('ADMIN_DB.TAGS.PII_CLASSIFICATION')
            is null
            then VAL
        when coalesce(system$get_tag_on_current_table('ADMIN_DB.TAGS.DOMAIN'), '')
            = ''
            then null
        when is_role_in_session(
            'PII_' ||
            upper(system$get_tag_on_current_table('ADMIN_DB.TAGS.DOMAIN')) ||
            '_FULL_ACCESS'
        )
            then VAL
        else null
    end;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Masking policy: DATE
-- ─────────────────────────────────────────────────────────────────────────────
create or replace masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_DATE_PII_BY_DOMAIN
    as (VAL date) returns date ->
    case
        when system$get_tag_on_current_column('ADMIN_DB.TAGS.PII_CLASSIFICATION')
            is null
            then VAL
        when coalesce(system$get_tag_on_current_table('ADMIN_DB.TAGS.DOMAIN'), '')
            = ''
            then null
        when is_role_in_session(
            'PII_' ||
            upper(system$get_tag_on_current_table('ADMIN_DB.TAGS.DOMAIN')) ||
            '_FULL_ACCESS'
        )
            then VAL
        when is_role_in_session(
            'PII_' ||
            upper(system$get_tag_on_current_table('ADMIN_DB.TAGS.DOMAIN')) ||
            '_PARTIAL_ACCESS'
        )
            then date_from_parts(year(VAL), 1, 1)
        else null
    end;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Attach masking policies to PII_CLASSIFICATION tag
-- ─────────────────────────────────────────────────────────────────────────────
alter tag ADMIN_DB.TAGS.PII_CLASSIFICATION set
    masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_STRING_PII_BY_DOMAIN,
    masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_NUMBER_PII_BY_DOMAIN,
    masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_DATE_PII_BY_DOMAIN;
