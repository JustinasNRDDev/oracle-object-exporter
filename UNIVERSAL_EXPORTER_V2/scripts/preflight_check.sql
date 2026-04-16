set heading off
set feedback off
set verify off
set pagesize 0
set linesize 32767
set trimspool on
set termout on
set echo off

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback

select 'PREFLIGHT_CONN_OK' from dual;

with priv_flags as (
    select
        max(case when privilege = 'CREATE SESSION' then 1 else 0 end) as create_session,
        max(case when privilege = 'SELECT ANY DICTIONARY' then 1 else 0 end) as select_any_dictionary,
        max(case when privilege = 'DEBUG ANY PROCEDURE' then 1 else 0 end) as debug_any_procedure
    from session_privs
),
role_flags as (
    select
        max(case when role = 'SELECT_CATALOG_ROLE' then 1 else 0 end) as select_catalog_role
    from session_roles
),
combined as (
    select
        nvl(p.create_session, 0) as create_session,
        nvl(p.select_any_dictionary, 0) as select_any_dictionary,
        nvl(p.debug_any_procedure, 0) as debug_any_procedure,
        nvl(r.select_catalog_role, 0) as select_catalog_role
    from priv_flags p
    cross join role_flags r
),
capabilities as (
    select
        create_session,
        select_any_dictionary,
        debug_any_procedure,
        select_catalog_role,
        case
            when create_session = 1
                 and (debug_any_procedure = 1 or select_any_dictionary = 1 or select_catalog_role = 1)
            then 1 else 0
        end as can_procedures,
        case
            when create_session = 1
                 and (select_any_dictionary = 1 or select_catalog_role = 1)
            then 1 else 0
        end as can_packages,
        case
            when create_session = 1
                 and (select_any_dictionary = 1 or select_catalog_role = 1)
            then 1 else 0
        end as can_functions,
        case
            when create_session = 1
                 and (select_any_dictionary = 1 or select_catalog_role = 1)
            then 1 else 0
        end as can_types,
        case
            when create_session = 1
                 and (select_any_dictionary = 1 or select_catalog_role = 1)
            then 1 else 0
        end as can_tables,
        case
            when create_session = 1
                 and (select_any_dictionary = 1 or select_catalog_role = 1)
            then 1 else 0
        end as can_views
    from combined
)
select line
from (
    select 1 as ord, 'PREFLIGHT_PRIV:CREATE_SESSION:' || create_session as line from capabilities
    union all
    select 2 as ord, 'PREFLIGHT_PRIV:SELECT_ANY_DICTIONARY:' || select_any_dictionary as line from capabilities
    union all
    select 3 as ord, 'PREFLIGHT_PRIV:DEBUG_ANY_PROCEDURE:' || debug_any_procedure as line from capabilities
    union all
    select 4 as ord, 'PREFLIGHT_ROLE:SELECT_CATALOG_ROLE:' || select_catalog_role as line from capabilities
    union all
    select 5 as ord, 'PREFLIGHT_CAPABILITY:PACKAGES:' || can_packages as line from capabilities
    union all
    select 6 as ord, 'PREFLIGHT_CAPABILITY:PROCEDURES:' || can_procedures as line from capabilities
    union all
    select 7 as ord, 'PREFLIGHT_CAPABILITY:FUNCTIONS:' || can_functions as line from capabilities
    union all
    select 8 as ord, 'PREFLIGHT_CAPABILITY:TYPES:' || can_types as line from capabilities
    union all
    select 9 as ord, 'PREFLIGHT_CAPABILITY:TABLES:' || can_tables as line from capabilities
    union all
    select 10 as ord, 'PREFLIGHT_CAPABILITY:VIEWS:' || can_views as line from capabilities
)
order by ord;

select 'PREFLIGHT_DONE' from dual;

exit success
