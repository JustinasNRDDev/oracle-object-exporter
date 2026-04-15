define save_directory=&1
 
@scripts/validate_and_export_procedure &save_directory AUX_LOAD_IMONE_TIPAS_1 SEARCH_ENT
@scripts/validate_and_export_procedure &save_directory AUX_LOAD_IMONE SEARCH_ENT
 
exit
