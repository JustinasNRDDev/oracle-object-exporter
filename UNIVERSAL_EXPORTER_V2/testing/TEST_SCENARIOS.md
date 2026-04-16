# UNIVERSAL_EXPORTER_V2 Contract Test Scenarios

Tikslas: uzfiksuoti funkcini kontrakta, kad BAT, Python, EXE ar C# realizacijos elgtusi vienodai.

## Scope

- CLI argumentu apdorojimas
- Task/objects failo vieta ir bootstrap elgsena
- Dry-run planavimo logika
- DDL saltinio ir extension taisykles
- Path savarankiskumas (paleidimas is bet kurios vietos)
- Preflight capability matrica pagal skirtingus Oracle teisiu profilius

## Kontraktiniai scenarijai

1. CT-001 Help output
- Given: paleidimas su --help
- When: vykdoma komanda
- Then: isvedamas Usage tekstas ir komanda baigiasi su klaidos kodu 1
- Automatizuota: taip

2. CT-002 Task aplanko nera, naudotojas atsisako kurti
- Given: nurodytas neegzistuojantis task aplankas
- When: i klausima del sukurimo atsakoma N
- Then: vykdymas nutraukiamas, aplankas nesukuriamas
- Automatizuota: taip

3. CT-003 Task aplanko nera, naudotojas sutinka kurti
- Given: nurodytas neegzistuojantis task aplankas
- When: i klausima del sukurimo atsakoma Y
- Then: sukuriamas aplankas ir EXPORTED_OBJECTS/<TASK>/objects.txt sablonas
- Automatizuota: taip

4. CT-004 Task aplankas yra, bet nera objects.txt
- Given: egzistuojantis task aplankas be objects.txt
- When: naudotojas patvirtina sablono kurima
- Then: sukuriamas objects.txt sablonas
- Automatizuota: taip

5. CT-005 Objects failo sablono struktura
- Given: automatiskai sugeneruotas objects.txt
- When: failas perskaitomas
- Then: failas turi uzkomentuotas [DEV], [TEST], [PROD] sekcijas ir tipu laukus
- Automatizuota: taip

6. CT-006 Truksta [ENV] sekcijos
- Given: objects.txt neturi [DEV]
- When: paleidziama su ENV=DEV
- Then: gaunama klaida, kad nerasta aplinkos sekcija
- Automatizuota: taip

7. CT-007 Objekto eilute pries schema
- Given: objects.txt turi objects eilute pries schema
- When: paleidziama komanda
- Then: gaunama klaida del netinkamos eiluciu tvarkos
- Automatizuota: taip

8. CT-008 Schema filtras nerastas
- Given: objects.txt neturi nurodytos schemos
- When: paleidziama su konkrecia SCHEMA
- Then: gaunama klaida del nerastos schemos
- Automatizuota: taip

9. CT-009 Truksta connection failo
- Given: config rodo i neegzistuojanti connection faila
- When: paleidziama komanda
- Then: gaunama klaida del nerasto connection failo
- Automatizuota: taip

10. CT-010 DDL source = dba
- Given: config nustatyta ddl_source=dba
- When: dry-run su tables ir views
- Then: naudojami generate_tbl_ddl_dba.sql ir generate_view_ddl_dba.sql
- Automatizuota: taip

11. CT-011 DDL source = all
- Given: config nustatyta ddl_source=all
- When: dry-run su tables ir views
- Then: naudojami generate_tbl_ddl.sql ir generate_view_ddl.sql
- Automatizuota: taip

12. CT-012 Custom extension laisve
- Given: config export_extensions su nestandartiniais suffix (pvz. PrX123, FcX123)
- When: dry-run
- Then: EXECUTE planuose extension perduodami tiksliai kaip sukonfiguruota
- Automatizuota: taip

13. CT-013 Named argumentu palaikymas
- Given: paleidimas su -TaskName/-EnvironmentName/-SchemaName/-DryRun/-ConfigPath
- When: vykdoma komanda
- Then: rezultatas atitinka positional varianta
- Automatizuota: taip

14. CT-014 Paleidimas is kito working directory
- Given: komanda paleidziama ne is projekto root
- When: naudojamas entrypoint failo pilnas kelias
- Then: vykdymas sekmingas, SQL skriptu keliai tvarkingai issprendziami
- Automatizuota: taip

15. CT-015 Dry-run nekviecia realaus DB vykdymo
- Given: dry-run rezimas
- When: paleidziama komanda
- Then: gaunamas EXECUTE planas ir RUN END, be realaus SQL vykdymo
- Automatizuota: taip

16. CT-016 Real-run smoke su testine DB
- Given: galiojantis connection i test DB ir testiniai objektai
- When: dry-run paleidziamas be --dry-run
- Then: sugeneruojami realus failai su nurodytais extension
- Automatizuota: ne (rankinis scenarijus)

17. CT-017 Preflight profilis PRC+TBL (procedures + tables/views/types)
- Given: naudotojas turi teises `CREATE SESSION`, `SELECT_CATALOG_ROLE`, `SELECT ANY DICTIONARY`, `DEBUG ANY PROCEDURE`
- Given: preflight config naudoja `connection_file: "%ORACLE19_CONN_PRC_TBL%\\connDEB.conf"`
- Given: task `TASK_1_MIXED` turi objektu tipus `procedures`, `tables`, `views`, `types`
- When: paleidziama `oracle_exporter_task.bat TASK_1_MIXED DEB --preflight -ConfigPath <path>\\exporter_prc_tbl.yaml`
- Then: `PREFLIGHT CAPABILITIES` turi rodyti bent `procedures=YES`, `tables=YES`, `views=YES`, `types=YES`
- Then: preflight neturi grazinti klaidos `preflight truksta teisiu task tipams`
- Automatizuota: ne (rankinis scenarijus, priklauso nuo lokalios Oracle teisiu konfiguracijos)

## Vykdymas

Automatinius testus paleisti:

- testing\run_contract_tests.bat

Pastaba ateities perrasymams:

Jei realizacija bus perrasyta i Python/EXE/C#, testu scenariju failas lieka nepakeistas kaip funkcionalumo kontraktas. Automatinius testus reikia pritaikyti tik paleidimo komandos sluoksniui, o ne scenariju turiniui.