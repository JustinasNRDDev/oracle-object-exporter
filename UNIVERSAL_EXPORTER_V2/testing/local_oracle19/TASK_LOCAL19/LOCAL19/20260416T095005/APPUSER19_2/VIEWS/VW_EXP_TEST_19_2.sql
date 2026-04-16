old   3: WHERE owner = UPPER('&2')
new   3: WHERE owner = UPPER('APPUSER19_2')
old   4: AND view_name = UPPER('&3')
new   4: AND view_name = UPPER('VW_EXP_TEST_19_2')
old   8: WHERE owner = UPPER('&2')
new   8: WHERE owner = UPPER('APPUSER19_2')
old   9: AND view_name = UPPER('&3')
new   9: AND view_name = UPPER('VW_EXP_TEST_19_2')
old  13:     where comm.owner = UPPER('&2')
new  13:     where comm.owner = UPPER('APPUSER19_2')
old  14:     and comm.table_name = UPPER('&3')
new  14:     and comm.table_name = UPPER('VW_EXP_TEST_19_2')
old  20: WHERE owner = UPPER('&2')
new  20: WHERE owner = UPPER('APPUSER19_2')
old  21: AND view_name = UPPER('&3')
new  21: AND view_name = UPPER('VW_EXP_TEST_19_2')
old  25:     WHERE owner = UPPER('&2')
new  25:     WHERE owner = UPPER('APPUSER19_2')
old  26:     AND table_name = UPPER('&3')
new  26:     AND table_name = UPPER('VW_EXP_TEST_19_2')

DBMS_METADATA.GET_DDL('VIEW',VIEW_NAME,OWNER)                                   
--------------------------------------------------------------------------------
                                                                                
  CREATE OR REPLACE FORCE EDITIONABLE VIEW "APPUSER19_2"."VW_EXP_TEST_19_2" (   
"I                                                                              
                                                                                

