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
