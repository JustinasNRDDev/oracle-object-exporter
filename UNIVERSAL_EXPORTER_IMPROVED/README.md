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
python run_export.py TASK_123 DEV --nls-lang Lithuanian_lithuania.utf8
python run_export.py TASK_123 DEV --task-root tasks --task-objects-file objects.txt

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
