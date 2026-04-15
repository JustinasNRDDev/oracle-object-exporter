SET TERM OFF
-- dollar negalima naudoti failo pavadinime https://forums.oracle.com/ords/apexds/post/how-to-run-a-script-with-a-dollar-sign-in-the-file-name-fro-6856
column fname new_val fname
select DECODE((select count(*) from all_views WHERE  owner = UPPER('&2') AND view_name = UPPER('&3')), 1, ('&1' || '\\'),0 , ('&1' || '\\' || 'NOT_EXISTS_')) || REPLACE('&3', '$', '_dollar') || '.' || lower(trim('&4')) fname from dual;
spool &fname	
select dbms_metadata.get_ddl('VIEW', view_name, owner)
from all_views
WHERE  owner      = UPPER('&2')
AND    view_name = UPPER('&3')
union ALL
select dbms_metadata.get_dependent_ddl('COMMENT', view_name, owner)
from all_views
WHERE  owner      = UPPER('&2')
AND    view_name = UPPER('&3')
and exists (select * from all_col_comments comm
			where comm.owner = UPPER('&2')
			and comm.table_name = UPPER('&3')
            and comm.comments is not null)
union ALL
select dbms_metadata.get_dependent_ddl('OBJECT_GRANT', view_name, owner)
from all_views
WHERE  owner      = UPPER('&2')
AND    view_name = UPPER('&3')
AND EXISTS (
SELECT 1
    FROM all_tab_privs
    WHERE table_schema = UPPER('&2')
   AND  table_name = UPPER('&3'));
spool off
SET TERM ON
