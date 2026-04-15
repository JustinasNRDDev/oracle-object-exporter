define save_directory=&1
 
@scripts/validate_and_export_type &save_directory BROKENRULE ETAAR
@scripts/validate_and_export_type &save_directory BROKENRULESCOLLECTION ETAAR
@scripts/validate_and_export_type &save_directory CURSOR_DETAILS ETAAR
@scripts/validate_and_export_type &save_directory CURSOR_REC ETAAR
 
exit
