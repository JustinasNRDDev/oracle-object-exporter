# UNIVERSAL_EXPORTER_IMPROVED

Task-oriented Oracle objektu eksportavimas su vienu core vykdymo varikliu.

Pagrindine ideja:
- core logika yra viename vykdomame faile (oracle_exporter.exe),
- baziniai nustatymai yra YAML faile,
- eksportuojamu objektu sarasai laikomi pagal task aplankus (`tasks/<TASK>/objects.txt`).

## Greitas naudojimas

Tikslinis paleidimas (task mode):

oracle_exporter.exe TASK_123 DEV
oracle_exporter.exe TASK_123 DEV APPUSER19

Reiksme:
1. TASK_123 - task aplankas su objects.txt failu.
2. DEV - aplinkos sekcija is objects.txt (`[DEV]`).
3. APPUSER19 - optional schema filtras.

Jei schema nenurodyta, eksportuojamos visos schemas is pasirinkto aplinkos bloko.

## Task failo formatas

Failas: `tasks/TASK_123/objects.txt`

Pavyzdys:

[DEV]
nls_lang: Lithuanian_lithuania.utf8
schema:APPUSER19
packages: PCK_1,PCK_2,PCK_3
procedures: PRC_1,PRC_2,PRC_3
functions: FNC_1,FNC_2
tables: TABLE_1,TABLE_2
views: VIEW_1,VIEW_2
types: TYPE_1,TYPE_2

schema:APPUSER19_2
packages: PCK_1,PCK_2,PCK_3
procedures: PRC_1,PRC_2,PRC_3
functions: FNC_1,FNC_2
tables: TABLE_1,TABLE_2
views: VIEW_1,VIEW_2
types: TYPE_1,TYPE_2

[TEST]
schema:APPUSER19
packages: PCK_A

Pastabos:
- `nls_lang` yra optional ir gali buti nurodytas environment lygyje.
- Jei `nls_lang` nera task faile, naudojamas YAML default arba YAML environment override.
- Komentarai: eilutes su `#`, `--`, `;`.

## Projekto struktura

- run_export.py - pagrindinis vykdymo variklis.
- oracle_exporter.bat - task-komandos wrapperis per Python.
- oracle_exporter_task.bat - task-komandos wrapperis per .bat adapteri.
- scripts/run_export_task.bat - .bat adapteris, kuris islaiko ta pati CLI ir perduoda vykdyma i PowerShell varikli.
- scripts/run_export_task.ps1 - task parseris ir vykdymo variklis (PowerShell).
- build_oracle_exporter_exe.bat - one-file .exe surinkimas.
- config/exporter.yaml - baziniai nustatymai (connection, extensions, output, task root).
- tasks/ - task aplankai su objects.txt.
- scripts/ - SQL*Plus eksportavimo skriptai.
- logs/ - run logai ir sugeneruoti tarpiniai SQL.

## YAML paskirtis

YAML saugo bendra logika ir nustatymus:
- defaults: sqlplus_executable, output_root, task_root, task_objects_file_name, nls_lang, strict/post-check.
- environments: connection, ddl_source, optional nls/export extension override.
- output: TABLES/VIEWS/TYPES subfolderiai.

Task mode objektu sarasu neima is YAML - jie imami is task objects.txt.

## Paleidimo variantai

Task mode (rekomenduojamas):

python run_export.py TASK_123 DEV
python run_export.py TASK_123 DEV APPUSER19

Papildomi variantai:

python run_export.py TASK_123 DEV --dry-run
python run_export.py TASK_123 DEV --preflight
python run_export.py TASK_123 DEV --check
python run_export.py TASK_123 DEV --nls-lang Lithuanian_lithuania.utf8
python run_export.py TASK_123 DEV --task-root tasks --task-objects-file objects.txt

## Ka tiksliai duoda --dry-run

`--dry-run` yra saugus planavimo rezimas pries realu eksporta.

Kas ivyksta su `--dry-run`:

1. Patikrinami ivesties argumentai (TASK, ENV, optional SCHEMA).
2. Nuskaitymas ir validacija:
	- `config/exporter.yaml`
	- `tasks/<TASK>/objects.txt`
3. Patikrinama, kad egzistuoja connection failas is config ir ji galima perskaityti.
4. Suformuojamas pilnas vykdymo planas: kiekvienam zingsniui atspausdinamos SQL*Plus komandos (`EXECUTE | ...`).
5. Sukuriamas run logas.

Ko `--dry-run` nedaro:

1. Nepaleidzia SQL*Plus komandu.
2. Nesijungia prie Oracle DB.
3. Neeksportuoja objektu turinio i failus.

Svarbi praktine pastaba:

- Gali buti sukurti tik planavimo artefaktai (pvz. logai ar laikina run struktura), bet ne realus objektu DDL/source turinys.
- Jei reikia tik pasitikrinti plana pries gyva paleidima, pirma naudokite `--dry-run`.

## Ka tiksliai duoda --preflight

`--preflight` (alias `--check`) yra paruosties patikra pries realu eksporta.

Kas ivyksta su `--preflight`:

1. Patikrinama, ar pasiekiamas `sqlplus` (`PATH` arba `sqlplus_executable`).
2. Patikrinama, ar yra visi privalomi `scripts/*.sql` failai (iskaitant `preflight_check.sql`).
3. Nuskaitymas ir validacija:
	- `config/exporter.yaml`
	- `tasks/<TASK>/objects.txt`
4. Patikrinamas prisijungimas prie Oracle DB.
5. Surenkama Oracle teisiu ir capability suvestine pagal tipus (`packages`, `procedures`, `functions`, `types`, `tables`, `views`).
6. Task'e prasomi objektu tipai palyginami su realiomis naudotojo galimybemis.

Ko `--preflight` nedaro:

1. Neeksportuoja objektu failu.
2. Nevykdo realiu objekto eksporto SQL skriptu.

Pavyzdziai:

python run_export.py TASK_123 DEV --preflight
python run_export.py TASK_123 DEV APPUSER19 --preflight
python run_export.py TASK_123 DEV --check

Legacy YAML mode (be TASK) vis dar palaikomas atgaliniam suderinamumui:

python run_export.py --env DEV

## .exe surinkimas

1. Paleisti build skripta:

build_oracle_exporter_exe.bat

2. Po build bus sukurta:

- dist/oracle_exporter.exe
- oracle_exporter.exe (projekto root)

3. Naudoti:

oracle_exporter.exe TASK_123 DEV
oracle_exporter.exe TASK_123 DEV APPUSER19

Svarbu: exe tikisi, kad salia bus `config/`, `scripts/` ir `tasks/` katalogai.

## Release + pasirasymas (automatizuota)

Naujas skriptas:

- release_sign_and_publish.ps1

Ka jis daro vienu paleidimu:

1. Buildina exe is source.
2. Gali pasirasyt su code-signing sertifikatu.
3. Verifikuoja parasa.
4. Nukopijuoja exe i `../UNIVERSAL_EXPORTER_V1` (nebent nurodytas `-SkipPublishToRuntime`).
5. Sugeneruoja hash ir release ataskaita:
	 - `release/oracle_exporter.sha256.txt`
	 - `release/oracle_exporter.release.json`

Pavyzdziai:

- tik build + publish (be pasirasymo):
	powershell -ExecutionPolicy Bypass -File .\release_sign_and_publish.ps1 -NoSign

- build + pasirasymas su PFX:
	powershell -ExecutionPolicy Bypass -File .\release_sign_and_publish.ps1 -PfxPath C:\certs\company_codesign.pfx -PfxPassword (Read-Host "PFX password" -AsSecureString)

- build + pasirasymas su sertifikatu is cert store (thumbprint):
	powershell -ExecutionPolicy Bypass -File .\release_sign_and_publish.ps1 -CertThumbprint "THUMBPRINT_HEX"

Pastaba: jei neturite SignTool (Windows SDK Signing Tools), galite paleisti su `-NoSign`.

## Rezultatai ir logai

Eksporto failai rasomi i:

- EXPORTED_OBJECTS/<TASK>/<ENV>/<TIMESTAMP>/<SCHEMA>/...

Pagal tipa:
- routines: schema root
- tables: TABLES
- views: VIEWS
- types: TYPES

Logai:
- logs/export_<timestamp>.log
- logs/generated_sql/<timestamp>/
- logs/post_check_<timestamp>.txt (jei rastos klaidos)

Post-check tikrina ORA/SP2/PLS/TNS parasus ir skenuoja failus pagal sukonfiguruotus export_extensions.
