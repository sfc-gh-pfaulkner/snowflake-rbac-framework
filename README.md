# Snowflake RBAC Framework

Reusable infrastructure for Snowflake Role-Based Access Control. Deploys to both accounts and provides stored procedures, tags, masking policies, and CI/CD workflow templates that domain code repos consume.

---

## Architecture

This framework requires **two separate Snowflake accounts**:

| Account | Identifier | Contains | Clone Types |
|---------|-----------|----------|-------------|
| DEV | DEVACC | DEV_ databases, DEV_ roles, WIP/TEST clones | WIP_, TEST_ |
| PROD | PRODACC | PROD_ databases, PROD_ roles, UAT/PREPROD clones | UAT_, PREPROD_ |

Each account gets its own `ADMIN_DB` (procedures, tags, lookup tables) and `GOVERNANCE_DB` (masking policies).

---

## Prerequisites

### Snowflake CLI (`snow`)

```bash
pip install snowflake-cli-labs
snow --version
```

### Key Pair Authentication

Generate a key pair and register it with your user **in both accounts**:

```bash
mkdir -p ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/.snowflake/rsa_key.p8 -nocrypt
openssl rsa -in ~/.snowflake/rsa_key.p8 -pubout -out ~/.snowflake/rsa_key.pub
```

Register a named key pair in both accounts:
```sql
ALTER USER <your_user> ADD KEY PAIR my_key
  PUBLIC_KEY = '<public key contents without BEGIN/END headers>';
```

To verify:
```sql
SHOW USER KEY PAIRS IN USER <your_user>;
```

### Connection Setup

`~/.snowflake/connections.toml`:

```toml
[DEVACC]
account = "<DEVACC identifier>"
user = "<your-user>"
authenticator = "snowflake_jwt"
private_key_file = "~/.snowflake/rsa_key.p8"

[PRODACC]
account = "<PRODACC identifier>"
user = "<your-user>"
authenticator = "snowflake_jwt"
private_key_file = "~/.snowflake/rsa_key.p8"
```

Do not set a default role — always pass `--role` explicitly.

Test both:
```bash
snow connection test -c DEVACC
snow connection test -c PRODACC
```

---

## Deploying the Framework

### Step 1: ACCOUNTADMIN prerequisites (both accounts)

Creates `GOVERNANCE_DB` with session policy, and the `DEPLOYMENT_ADMIN` role with minimum required privileges.

```bash
snow sql -f scripts/00_session_policy.sql -c DEVACC --role ACCOUNTADMIN --warehouse COMPUTE_WH
snow sql -f scripts/01_deployment_admin.sql -c DEVACC --role ACCOUNTADMIN --warehouse COMPUTE_WH

snow sql -f scripts/00_session_policy.sql -c PRODACC --role ACCOUNTADMIN --warehouse COMPUTE_WH
snow sql -f scripts/01_deployment_admin.sql -c PRODACC --role ACCOUNTADMIN --warehouse COMPUTE_WH
```

### Step 2: Deploy framework scripts (both accounts)

Creates `ADMIN_DB`, all procedures, tags, and masking policies. After this, the domain code repo takes over for environment/domain/database provisioning.

```bash
./deploy.sh --connection DEVACC
./deploy.sh --connection PRODACC
```

---

## What This Framework Provides

### Stored Procedures (in ADMIN_DB.DEPLOY)

| Procedure | Purpose |
|-----------|---------|
| `DEPLOY_ENVIRONMENT` | Registers an environment (DEV, PROD) and creates env-level roles |
| `DEPLOY_DOMAIN` | Registers a domain and creates domain-level roles per environment |
| `DEPLOY_DATABASE` | Creates a domain database with standard database roles |
| `DEPLOY_SCHEMA` | Creates a managed-access schema with schema-level roles |
| `DEPLOY_WAREHOUSE` | Creates a warehouse with ownership and USAGE grants |
| `DEPLOY_CLONE` | Creates WIP/TEST/UAT/PREPROD/SAFE clones with appropriate access |
| `DROP_CLONE` | Drops a clone and cleans up grants |
| `FIND_CLONE_BLOCKERS` | Diagnoses why a clone cannot be created |
| `DEPLOY_DP_ROLE` | Creates a data product access role |

### Tags (in ADMIN_DB.TAGS)

| Tag | Purpose |
|-----|---------|
| `ENVIRONMENT` | Classifies objects by environment |
| `DOMAIN` | Classifies objects by business domain |
| `PII_CATEGORY` | Type of personal data (NAME, EMAIL, PHONE, etc.) |
| `PII_CLASSIFICATION` | Sensitivity level (CONFIDENTIAL, SENSITIVE) — triggers masking |

### Masking Policies (in GOVERNANCE_DB.ACCESS_CONTROL)

Tag-based masking attached to `PII_CLASSIFICATION`. Automatically masks STRING, NUMBER, and DATE columns unless the querying user has `PII_<DOMAIN>_FULL_ACCESS` or `PII_<DOMAIN>_PARTIAL_ACCESS` in session.

### Reusable CI/CD Workflow Templates

| Template | Purpose |
|----------|---------|
| `deploy-to-clone.yml` | Creates a clone, patches DCM manifest, deploys |
| `deploy-to-prod.yml` | Deploys to production, cleans up clones |
| `deploy-to-base.yml` | Deploys directly to a base database |

These are `workflow_call` templates — they define *how* to deploy. Domain code repos provide trigger workflows that call these.

---

## Role Hierarchy (per account)

```
ACCOUNTADMIN
 └── DEPLOYMENT_ADMIN
SYSADMIN
 └── <ENV>_SYSADMIN
      ├── <ENV>_<DOMAIN>_SYSADMIN
      │    ├── <ENV>_<DOMAIN>_ETL
      │    │    └── <ENV>_<DOMAIN>_READER
      │    ├── <ENV>_<DOMAIN>_RBAC (owns database roles)
      │    └── <ENV>_<DOMAIN>_DEVELOPER (DEV only)
      └── ...
```

Functional roles (ANALYST, MANAGER, DATASTEWARD, POWERBI, DEVELOPER) are managed by the domain code repo via DCM.

---

## Clone Types

| Type | Account | Source DB | Purpose | Access Model |
|------|---------|-----------|---------|--------------|
| WIP | DEVACC | DEV_*_DB | Developer workspace | DEVELOPER role gets full RWC |
| SAFE | DEVACC | DEV_*_DB | Rollback snapshot (auto-created with WIP) | No role access |
| TEST | DEVACC | DEV_*_DB | Automated testing | ANALYST, MANAGER, DATASTEWARD, POWERBI get read-only |
| UAT | PRODACC | PROD_*_DB | User acceptance testing | ANALYST, MANAGER, DATASTEWARD, POWERBI get read-only |
| PREPROD | PRODACC | PROD_*_DB | Pre-production validation | MANAGER only gets read-only |

---

## Script Reference

| File | Purpose |
|------|---------|
| `00_session_policy.sql` | Session policy blocking privileged secondary roles |
| `01_deployment_admin.sql` | DEPLOYMENT_ADMIN role with minimum required privileges |
| `02_admin_db.sql` | ADMIN_DB database |
| `03_admin_db_deploy_schema.sql` | DEPLOY schema (managed access) |
| `04_admin_db_tags_schema.sql` | TAGS schema (managed access) |
| `05_admin_db_database_roles.sql` | DB-level roles on ADMIN_DB |
| `06_admin_db_deploy_schema_roles.sql` | DEPLOY schema roles with future grants |
| `07_admin_db_tags_schema_roles.sql` | TAGS schema roles with future grants |
| `08_admin_wh.sql` | ADMIN_WH warehouse |
| `09_admin_db_environments_table.sql` | ENVIRONMENTS lookup table |
| `10_admin_db_domains_table.sql` | DOMAINS lookup table |
| `11_admin_db_environment_tag.sql` | ENVIRONMENT tag |
| `12_admin_db_domain_tag.sql` | DOMAIN tag |
| `13_admin_db_deploy_environment_proc.sql` | DEPLOY_ENVIRONMENT procedure |
| `14_admin_db_deploy_domain_proc.sql` | DEPLOY_DOMAIN procedure |
| `15_admin_db_deploy_database_proc.sql` | DEPLOY_DATABASE procedure |
| `16_admin_db_deploy_schema_proc.sql` | DEPLOY_SCHEMA procedure |
| `17_admin_db_deploy_warehouse_proc.sql` | DEPLOY_WAREHOUSE procedure |
| `18_admin_db_deploy_dp_role_proc.sql` | DEPLOY_DP_ROLE procedure |
| `19_admin_db_deploy_clone.sql` | DEPLOY_CLONE / _PROVISION_CLONE procedures |
| `24_admin_db_drop_clone.sql` | DROP_CLONE procedure |
| `26_admin_db_find_clone_blockers.sql` | FIND_CLONE_BLOCKERS procedure |
| `30_pii_governance.sql` | PII tags, masking policies |
| `99_teardown.sql` | Full tear-down (testing only) |

---

## Linting

```bash
pip install pre-commit sqlfluff yamllint
pre-commit install
```

Runs SQLFluff (SQL style), yamllint (YAML syntax), and security checks on every commit. The `.github/workflows/lint.yml` workflow enforces the same on PRs.
