set verify off
--SET TERM ON
--prompt validate_and_export &1 &2 &3 &4
SET TERM ON

column package_name new_val next_step
select 
decode(count(name), null, 'exit', 1, decode('&3', 'SPEC', 'export_spec', 'exit'), 2, decode('&3', 'SPEC', 'export_spec', 'BODY', 'export_body', 'SPEC_AND_BODY','export_spec_and_body', 'exit')) package_name 
from all_source 
where owner='&4' and name='&2' and type in ('PACKAGE', 'PACKAGE BODY') and line = 1;
SET TERM OFF

@scripts/&&next_step &1 &2 &4 &5