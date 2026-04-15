REM script generated at 20260415T101816
REM master.sql

SET HEAD OFF
SET ECHO OFF
SET FEED OFF
SET LINESIZE 32767
SET LONG 2000000000
SET LONGCHUNKSIZE 32767
SET TRIMSPOOL ON
SET NEWPAGE NONE
SET PAGESIZE 0
SET DEFINE ON
SET VERIFY OFF
SET TERM ON
SET SERVEROUTPUT OFF


BEGIN
  DBMS_METADATA.set_transform_param(
    DBMS_METADATA.session_transform,
    'SQLTERMINATOR',
    TRUE
  );
  DBMS_METADATA.set_transform_param(
    DBMS_METADATA.session_transform,
    'PRETTY',
    TRUE
  );
  DBMS_METADATA.set_transform_param(
    DBMS_METADATA.session_transform,
    'SEGMENT_ATTRIBUTES',
    TRUE
  );
  DBMS_METADATA.set_transform_param(
    DBMS_METADATA.session_transform,
    'STORAGE',
    TRUE
  );
  DBMS_METADATA.set_transform_param(
    DBMS_METADATA.session_transform,
    'CONSTRAINTS',
    TRUE
  );
  DBMS_METADATA.set_transform_param(
    DBMS_METADATA.session_transform,
    'REF_CONSTRAINTS',
    TRUE
  );
END;
/
column tbl_exists new_val table_exists 
SET TERM OFF 
select DECODE(count(*), 0, '- NOT EXISTS', ' - EXISTS') tbl_exists from all_views WHERE  owner = UPPER('ETAAR') AND view_name = UPPER('TAAR_V_TAA_REGISTRACIJOS'); 
SET TERM ON 
prompt TAAR_V_TAA_REGISTRACIJOS &table_exists 
@scripts/generate_view_ddl C:\Users\jusstr\Documents\slq_scripts\Diegimai\_TAAR\_ETAAR_UTF8_FIXES_cols_tu_varchar2\UNIVERSAL_EXPORTER_HIPPREG_PRODUI\EXPORTED_OBJECTS\DEV\20260415T101816\ETAAR\VIEWS ETAAR TAAR_V_TAA_REGISTRACIJOS

prompt
SET DEFINE OFF
show err
exit