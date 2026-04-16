old   3: WHERE owner = UPPER('&2')
new   3: WHERE owner = UPPER('APPUSER19')
old   4: AND table_name = UPPER('&3')
new   4: AND table_name = UPPER('TEST1')
old   8: WHERE owner = UPPER('&2')
new   8: WHERE owner = UPPER('APPUSER19')
old   9: AND table_name = UPPER('&3')
new   9: AND table_name = UPPER('TEST1')
old  13:     where comm.owner = UPPER('&2')
new  13:     where comm.owner = UPPER('APPUSER19')
old  14:     and comm.table_name = UPPER('&3')
new  14:     and comm.table_name = UPPER('TEST1')
old  22:     WHERE i.table_name = UPPER('&3')
new  22:     WHERE i.table_name = UPPER('TEST1')
old  23:     AND i.table_owner = UPPER('&2')
new  23:     AND i.table_owner = UPPER('APPUSER19')
old  36: WHERE owner = UPPER('&2')
new  36: WHERE owner = UPPER('APPUSER19')
old  37: AND table_name = UPPER('&3')
new  37: AND table_name = UPPER('TEST1')
old  41:     where trg.table_owner = UPPER('&2')
new  41:     where trg.table_owner = UPPER('APPUSER19')
old  42:     and trg.table_name = UPPER('&3')
new  42:     and trg.table_name = UPPER('TEST1')
old  47: WHERE owner = UPPER('&2')
new  47: WHERE owner = UPPER('APPUSER19')
old  48: AND table_name = UPPER('&3')
new  48: AND table_name = UPPER('TEST1')
old  52:     WHERE owner = UPPER('&2')
new  52:     WHERE owner = UPPER('APPUSER19')
old  53:     AND table_name = UPPER('&3')
new  53:     AND table_name = UPPER('TEST1')

DBMS_METADATA.GET_DDL('TABLE',TABLE_NAME,OWNER)                                 
--------------------------------------------------------------------------------
                                                                                
  CREATE TABLE "APPUSER19"."TEST1"                                              
   (	"ID" NUMBER,                                                               
	"NAME" VARCHAR2(200),                                                          
                                                                                

