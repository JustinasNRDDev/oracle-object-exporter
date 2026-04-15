DECLARE
	l_ddl_stmt varchar2(4000);

BEGIN
  FOR cur_rec IN (SELECT owner,
                         object_name,
                         object_type,
                         DECODE(object_type, 'PACKAGE', 1,
                                             'PACKAGE BODY', 2, 2) AS recompile_order
                  FROM   dba_objects
                  WHERE  object_type IN ('PACKAGE', 'PACKAGE BODY')
                  AND    status != 'VALID'
                  AND owner = 'AIS2'
                  ORDER BY 4)
  LOOP
    BEGIN
      IF cur_rec.object_type = 'PACKAGE' THEN
		l_ddl_stmt := 'ALTER ' || cur_rec.object_type || ' "' || cur_rec.owner || '"."' || cur_rec.object_name || '" COMPILE';
        EXECUTE IMMEDIATE l_ddl_stmt;
		--DBMS_OUTPUT.put_line(l_ddl_stmt);
      ElSE
	  l_ddl_stmt := 'ALTER PACKAGE "' || cur_rec.owner || '"."' || cur_rec.object_name || '" COMPILE BODY';
       EXECUTE IMMEDIATE l_ddl_stmt;
	   --DBMS_OUTPUT.put_line(l_ddl_stmt);
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.put_line('Klaida vykdant: ' || l_ddl_stmt);
    END;
  END LOOP;
END;
/