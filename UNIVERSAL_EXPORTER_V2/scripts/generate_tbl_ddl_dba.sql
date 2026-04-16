SET TERM OFF
-- dollar negalima naudoti failo pavadinime https://forums.oracle.com/ords/apexds/post/how-to-run-a-script-with-a-dollar-sign-in-the-file-name-fro-6856
column fname new_val fname
select DECODE((select count(*) from dba_tables WHERE owner = UPPER('&2') AND table_name = UPPER('&3')), 1, ('&1' || '\\'), 0, ('&1' || '\\' || 'NOT_EXISTS_')) || REPLACE('&3', '$', '_dollar') || '.' || trim('&4') fname from dual;
spool &fname
select dbms_metadata.get_ddl('TABLE', table_name, owner)
from dba_tables
WHERE owner = UPPER('&2')
AND table_name = UPPER('&3')
union ALL
select dbms_metadata.get_dependent_ddl('COMMENT', table_name, owner)
from dba_tables
WHERE owner = UPPER('&2')
AND table_name = UPPER('&3')
and exists (
    select *
    from dba_col_comments comm
    where comm.owner = UPPER('&2')
    and comm.table_name = UPPER('&3')
    and comm.comments is not null
)
union ALL
select *
from (
    SELECT DBMS_METADATA.GET_DDL('INDEX', i.index_name, i.table_owner)
    FROM dba_indexes i
    WHERE i.table_name = UPPER('&3')
    AND i.table_owner = UPPER('&2')
    AND i.index_name NOT IN (
        SELECT c.index_name
        FROM dba_constraints c
        WHERE c.constraint_type IN ('P', 'U')
        AND c.table_name = i.table_name
        AND c.owner = i.table_owner
    )
    order by i.index_name
)
union ALL
select dbms_metadata.get_dependent_ddl('TRIGGER', table_name, owner)
from dba_tables
WHERE owner = UPPER('&2')
AND table_name = UPPER('&3')
and exists (
    select *
    from dba_triggers trg
    where trg.table_owner = UPPER('&2')
    and trg.table_name = UPPER('&3')
)
union ALL
select dbms_metadata.get_dependent_ddl('OBJECT_GRANT', table_name, owner)
from dba_tables
WHERE owner = UPPER('&2')
AND table_name = UPPER('&3')
AND EXISTS (
    SELECT 1
    FROM dba_tab_privs
    WHERE owner = UPPER('&2')
    AND table_name = UPPER('&3')
);
spool off
SET TERM ON
