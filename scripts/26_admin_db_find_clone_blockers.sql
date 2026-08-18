-- ============================================================================
-- RBAC FRAMEWORK: Step 26 - FIND_CLONE_BLOCKERS Procedure
-- ============================================================================
-- Purpose: Diagnostic utility that identifies objects in a database which
--          prevent a successful clone. Tests each schema and then each object
--          type individually to pinpoint the blocker.
--
-- Owner:   DEPLOYMENT_ADMIN
-- Caller:  EXECUTE AS CALLER (must be called as ACCOUNTADMIN)
-- Params:  SOURCE_DB - fully qualified database name to test
--
-- Usage:   CALL ADMIN_DB.DEPLOY.FIND_CLONE_BLOCKERS('DEV_HR_CORE_DB');
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

create or replace procedure ADMIN_DB.DEPLOY.FIND_CLONE_BLOCKERS(SOURCE_DB VARCHAR)
returns VARCHAR
language sql
comment = 'Diagnostic: identifies objects that block database cloning by testing each schema and object individually.'
execute as caller
as
$$
begin
    -- Caller must be ACCOUNTADMIN
    if (current_role() != 'ACCOUNTADMIN') then
        return 'ERROR: Must be called as ACCOUNTADMIN. Current role: ' || current_role();
    end if;

    let RESULT VARCHAR := '';
    let TEST_DB VARCHAR := :SOURCE_DB || '_CLONE_TEST_' || replace(CURRENT_SESSION(), '-', '_');
    let PROBLEM_COUNT INTEGER := 0;
    let SCHEMA_NAME VARCHAR;
    let OBJECT_NAME VARCHAR;
    let OBJECT_TYPE VARCHAR;
    let ERR_MSG VARCHAR;
    let SQL_TEXT VARCHAR;
    let LF VARCHAR := CHAR(10);

    -- Start message
    RESULT := 'Starting clone analysis for database: ' || :SOURCE_DB;

    -- Clean up any leftover TEST database from a prior run
    execute immediate 'drop database if exists ' || :TEST_DB;

    -- Phase 1: Identify schemas that cannot be cloned
    let FAILING_SCHEMAS ARRAY := array_construct();
    let PASSING_SCHEMAS ARRAY := array_construct();
    let SCHEMA_RS RESULTSET := (execute immediate
        'select SCHEMA_NAME from ' || :SOURCE_DB || '.INFORMATION_SCHEMA.SCHEMATA where SCHEMA_NAME != ''INFORMATION_SCHEMA''');
    let SCHEMA_CURSOR cursor for SCHEMA_RS;

    for REC in SCHEMA_CURSOR do
        SCHEMA_NAME := REC.SCHEMA_NAME;
        begin
            execute immediate 'create database if not exists ' || :TEST_DB;
            SQL_TEXT := 'create schema ' || :TEST_DB || '.TEST_SCHEMA CLONE ' || :SOURCE_DB || '.' || :SCHEMA_NAME;
            execute immediate :SQL_TEXT;
            execute immediate 'drop schema if exists ' || :TEST_DB || '.TEST_SCHEMA';
            PASSING_SCHEMAS := ARRAY_APPEND(:PASSING_SCHEMAS, :SCHEMA_NAME);
        exception
            when OTHER then
                FAILING_SCHEMAS := ARRAY_APPEND(:FAILING_SCHEMAS, :SCHEMA_NAME);
                execute immediate 'drop schema if exists ' || :TEST_DB || '.TEST_SCHEMA';
        end;
    end for;

    -- If no schemas failed, the database should clone fine
    if (array_size(:FAILING_SCHEMAS) = 0) then
        execute immediate 'drop database if exists ' || :TEST_DB;
        RESULT := :RESULT || :LF || :LF || 'Result: No clone-blocking problems found. All schemas cloned successfully.';
        RESULT := :RESULT || :LF || 'Schemas tested: ' || ARRAY_TO_STRING(:PASSING_SCHEMAS, ', ');
        return :RESULT;
    end if;

    -- Phase 2: For each failing schema, identify the problematic objects
    execute immediate 'create database if not exists ' || :TEST_DB;

    let SCHEMA_IDX INTEGER := 0;
    WHILE (:SCHEMA_IDX < array_size(:FAILING_SCHEMAS)) do
        SCHEMA_NAME := :FAILING_SCHEMAS[:SCHEMA_IDX];

        execute immediate 'create schema if not exists ' || :TEST_DB || '.OBJ_TEST';

        -- Test tables
        let TBL_RS RESULTSET := (execute immediate
            'select TABLE_NAME from ' || :SOURCE_DB || '.INFORMATION_SCHEMA.tables where TABLE_SCHEMA = ''' || :SCHEMA_NAME || ''' and TABLE_TYPE = ''BASE table''');
        let TBL_CURSOR cursor for TBL_RS;

        for TREC in TBL_CURSOR do
            OBJECT_NAME := TREC.TABLE_NAME;
            begin
                SQL_TEXT := 'create table ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '" CLONE ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '"';
                execute immediate :SQL_TEXT;
                execute immediate 'drop table if exists ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '"';
            exception
                when OTHER then
                    PROBLEM_COUNT := :PROBLEM_COUNT + 1;
                    ERR_MSG := SQLERRM;
                    RESULT := :RESULT || :LF || '  [table] ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '" - ' || :ERR_MSG;
            end;
        end for;

        -- Test views
        let VIEW_RS RESULTSET := (execute immediate
            'select TABLE_NAME from ' || :SOURCE_DB || '.INFORMATION_SCHEMA.tables where TABLE_SCHEMA = ''' || :SCHEMA_NAME || ''' and TABLE_TYPE = ''view''');
        let VIEW_CURSOR cursor for VIEW_RS;

        for VREC in VIEW_CURSOR do
            OBJECT_NAME := VREC.TABLE_NAME;
            begin
                SQL_TEXT := 'create view ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '" CLONE ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '"';
                execute immediate :SQL_TEXT;
                execute immediate 'drop view if exists ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '"';
            exception
                when OTHER then
                    PROBLEM_COUNT := :PROBLEM_COUNT + 1;
                    ERR_MSG := SQLERRM;
                    RESULT := :RESULT || :LF || '  [view] ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '" - ' || :ERR_MSG;
            end;
        end for;

        -- Test stages
        let STAGE_RS RESULTSET := (execute immediate 'SHOW STAGES in ' || :SOURCE_DB || '.' || :SCHEMA_NAME);
        let STAGE_CURSOR cursor for STAGE_RS;
        for SREC in STAGE_CURSOR do
            OBJECT_NAME := SREC."name";
            begin
                SQL_TEXT := 'create STAGE ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '" CLONE ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '"';
                execute immediate :SQL_TEXT;
                execute immediate 'drop STAGE if exists ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '"';
            exception
                when OTHER then
                    PROBLEM_COUNT := :PROBLEM_COUNT + 1;
                    ERR_MSG := SQLERRM;
                    RESULT := :RESULT || :LF || '  [STAGE] ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '" - ' || :ERR_MSG;
            end;
        end for;

        -- Test file formats
        let FF_RS RESULTSET := (execute immediate 'SHOW FILE FORMATS in ' || :SOURCE_DB || '.' || :SCHEMA_NAME);
        let FF_CURSOR cursor for FF_RS;
        for FREC in FF_CURSOR do
            OBJECT_NAME := FREC."name";
            begin
                SQL_TEXT := 'create FILE FORMAT ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '" CLONE ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '"';
                execute immediate :SQL_TEXT;
                execute immediate 'drop FILE FORMAT if exists ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '"';
            exception
                when OTHER then
                    PROBLEM_COUNT := :PROBLEM_COUNT + 1;
                    ERR_MSG := SQLERRM;
                    RESULT := :RESULT || :LF || '  [FILE FORMAT] ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '" - ' || :ERR_MSG;
            end;
        end for;

        -- Test sequences
        let SEQ_RS RESULTSET := (execute immediate 'SHOW SEQUENCES in ' || :SOURCE_DB || '.' || :SCHEMA_NAME);
        let SEQ_CURSOR cursor for SEQ_RS;
        for SEQREC in SEQ_CURSOR do
            OBJECT_NAME := SEQREC."name";
            begin
                SQL_TEXT := 'create SEQUENCE ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '" CLONE ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '"';
                execute immediate :SQL_TEXT;
                execute immediate 'drop SEQUENCE if exists ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '"';
            exception
                when OTHER then
                    PROBLEM_COUNT := :PROBLEM_COUNT + 1;
                    ERR_MSG := SQLERRM;
                    RESULT := :RESULT || :LF || '  [SEQUENCE] ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '" - ' || :ERR_MSG;
            end;
        end for;

        -- Test streams
        let STREAM_RS RESULTSET := (execute immediate 'SHOW STREAMS in ' || :SOURCE_DB || '.' || :SCHEMA_NAME);
        let STREAM_CURSOR cursor for STREAM_RS;
        for STRREC in STREAM_CURSOR do
            OBJECT_NAME := STRREC."name";
            begin
                SQL_TEXT := 'create STREAM ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '" CLONE ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '"';
                execute immediate :SQL_TEXT;
                execute immediate 'drop STREAM if exists ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '"';
            exception
                when OTHER then
                    PROBLEM_COUNT := :PROBLEM_COUNT + 1;
                    ERR_MSG := SQLERRM;
                    RESULT := :RESULT || :LF || '  [STREAM] ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '" - ' || :ERR_MSG;
            end;
        end for;

        -- Test tasks
        let TASK_RS RESULTSET := (execute immediate 'SHOW TASKS in ' || :SOURCE_DB || '.' || :SCHEMA_NAME);
        let TASK_CURSOR cursor for TASK_RS;
        for TASKREC in TASK_CURSOR do
            OBJECT_NAME := TASKREC."name";
            begin
                SQL_TEXT := 'create TASK ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '" CLONE ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '"';
                execute immediate :SQL_TEXT;
                execute immediate 'drop TASK if exists ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '"';
            exception
                when OTHER then
                    PROBLEM_COUNT := :PROBLEM_COUNT + 1;
                    ERR_MSG := SQLERRM;
                    RESULT := :RESULT || :LF || '  [TASK] ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '" - ' || :ERR_MSG;
            end;
        end for;

        -- Test pipes
        let PIPE_RS RESULTSET := (execute immediate 'SHOW PIPES in ' || :SOURCE_DB || '.' || :SCHEMA_NAME);
        let PIPE_CURSOR cursor for PIPE_RS;
        for PIPEREC in PIPE_CURSOR do
            OBJECT_NAME := PIPEREC."name";
            begin
                SQL_TEXT := 'create PIPE ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '" CLONE ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '"';
                execute immediate :SQL_TEXT;
                execute immediate 'drop PIPE if exists ' || :TEST_DB || '.OBJ_TEST."' || :OBJECT_NAME || '"';
            exception
                when OTHER then
                    PROBLEM_COUNT := :PROBLEM_COUNT + 1;
                    ERR_MSG := SQLERRM;
                    RESULT := :RESULT || :LF || '  [PIPE] ' || :SOURCE_DB || '.' || :SCHEMA_NAME || '."' || :OBJECT_NAME || '" - ' || :ERR_MSG;
            end;
        end for;

        execute immediate 'drop schema if exists ' || :TEST_DB || '.OBJ_TEST';

        SCHEMA_IDX := :SCHEMA_IDX + 1;
    end WHILE;

    -- Clean up TEST database
    execute immediate 'drop database if exists ' || :TEST_DB;

    -- Build final result
    if (:PROBLEM_COUNT = 0) then
        RESULT := :RESULT || :LF || :LF || 'Result: Schemas failed at schema-level clone but all individual objects cloned successfully.';
        RESULT := :RESULT || :LF || 'Failing schemas: ' || ARRAY_TO_STRING(:FAILING_SCHEMAS, ', ');
        RESULT := :RESULT || :LF || 'This may indicate a schema-level property or cross-object dependency is blocking the clone.';
    else
        RESULT := :RESULT || :LF || :LF || 'Result: Found ' || :PROBLEM_COUNT || ' object(s) blocking clone in ' || array_size(:FAILING_SCHEMAS) || ' schema(s).';
    end if;

    RESULT := :RESULT || :LF || :LF || 'Cloneable schemas: ' || ARRAY_TO_STRING(:PASSING_SCHEMAS, ', ');
    RESULT := :RESULT || :LF || 'Failing schemas: ' || ARRAY_TO_STRING(:FAILING_SCHEMAS, ', ');

    return :RESULT;
end;
$$
;
