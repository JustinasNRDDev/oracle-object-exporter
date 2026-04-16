set verify off
--SET TERM ON
--prompt validate_and_export &1 &2 &3 &4
SET TERM ON

column function_name new_val next_step
select 
decode(count(name), null, 'exit', 1, 'export_proc') function_name 
from all_source 
where owner='&3' and name='&2' and type in ('PROCEDURE') and line = 1;
SET TERM OFF

@scripts/&&next_step &1 &2 &3 &4