-- ============================================================================
-- RBAC FRAMEWORK: Step 8 - ADMIN_WH Warehouse
-- ============================================================================
-- Purpose: Creates a minimal warehouse for RBAC deployment and admin tasks.
-- ============================================================================

use role DEPLOYMENT_ADMIN;

create warehouse if not exists ADMIN_WH
warehouse_size = 'XSMALL'
auto_suspend = 60
auto_resume = TRUE
initially_suspended = TRUE
comment = 'Warehouse for RBAC framework deployment and administration.'
;
