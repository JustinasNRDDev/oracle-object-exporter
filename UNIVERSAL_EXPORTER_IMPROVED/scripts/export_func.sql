SET HEAD ON
SET ECHO OFF
SET FEED OFF
SET LINESIZE 32000
SET TRIMSPOOL ON
SET NEWPAGE NONE
SET PAGESIZE 0
SET DEFINE ON
SET VERIFY OFF
SET TERM ON

--select '&1' || '\\' || '&2' || '.' || lower(trim('&4')) fname from dual;
column fname new_val fname
select '&1' || '\\' || '&2' || '.' || lower(trim('&4')) fname from dual;
SET TERM OFF
spool &fname REPLACE

select
case 
   when t.type = 'FUNCTION' and t.line= 1 then
     'create or replace ' || REGEXP_REPLACE(t.mod, '(\S+)\s+(\S+)', '\1 \2') 
   else t.text
end Modified_Text
from
(select 
s.text,
s.type,
s.line,
case 
   when 
      instr(s.text, ('"' || upper(s.name) || '"')) > 0 then
         replace(s.text,  ('"' || s.name || '"'),  ('"' || s.owner || '"') || ('."' || s.name || '"'))
   when
      instr(s.text, (' ' || upper(s.name) || ' ')) > 0 then
         replace(s.text,  upper(s.name),  upper((s.owner || '.' || s.name)))
   when
      rtrim(s.text) = s.text and instr(s.text, (' ' || s.name)) > 0 then
         replace(s.text,  s.name,  (s.owner || '.' || s.name))
   when
      instr(s.text, (' ' || lower(s.name) || ' ')) > 0 then
         replace(s.text,  lower(s.name),  lower((s.owner || '.' || s.name)))
   when
      rtrim(s.text) = s.text and instr(s.text, (' ' || lower(s.name))) > 0 then
         replace(s.text,  lower(s.name),  lower((s.owner || '.' || s.name)))
   else
      s.text
end mod from all_source s where s.owner='&3' and s.name='&2' and s.type='FUNCTION') t order by t.line;

prompt /
prompt show errors
prompt

SPOOL OFF

