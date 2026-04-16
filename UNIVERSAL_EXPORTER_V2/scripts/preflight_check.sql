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

with required_privs (privilege_name) as (
    select 'CREATE SESSION' from dual union all
    select 'SELECT ANY DICTIONARY' from dual union all
    select 'CREATE ANY TABLE' from dual union all
    select 'CREATE ANY INDEX' from dual union all
    select 'CREATE ANY SEQUENCE' from dual union all
    select 'CREATE ANY VIEW' from dual union all
    select 'DROP ANY VIEW' from dual union all
    select 'CREATE ANY TYPE' from dual union all
    select 'ALTER ANY TYPE' from dual union all
    select 'DROP ANY TYPE' from dual union all
    select 'CREATE ANY PROCEDURE' from dual union all
    select 'ALTER ANY PROCEDURE' from dual union all
    select 'DROP ANY PROCEDURE' from dual union all
    select 'DEBUG ANY PROCEDURE' from dual
),
current_privs as (
    select privilege as privilege_name
    from session_privs
)
select 'PREFLIGHT_MISSING_PRIV:' || r.privilege_name
from required_privs r
left join current_privs c
    on c.privilege_name = r.privilege_name
where c.privilege_name is null
order by r.privilege_name;

select 'PREFLIGHT_MISSING_ROLE:SELECT_CATALOG_ROLE'
from dual
where not exists (
    select 1
    from session_roles
    where role = 'SELECT_CATALOG_ROLE'
);

select 'PREFLIGHT_DONE' from dual;

exit success
