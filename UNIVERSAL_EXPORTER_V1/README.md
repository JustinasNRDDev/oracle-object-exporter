# UNIVERSAL_EXPORTER_V1

Task-oriented Oracle objektu eksportavimas su vienu core vykdymo varikliu.

## Startas

1. Susikurkite task aplanka pagal sablona: `tasks/TASK_TEMPLATE`.
2. Pervadinkite, pvz. i `tasks/TASK_123` ir uzpildykite `objects.txt`.
3. Patikrinkite prisijungimu failus per `config/exporter.yaml` (`connDEV.conf`, `connTEST.conf`, `connPROD.conf`).
4. Paleiskite:

oracle_exporter.exe TASK_123 DEV
oracle_exporter.exe TASK_123 DEV APPUSER19

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
nls_lang: LITHUANIAN_LITHUANIA.UTF8
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

- oracle_exporter.exe - pagrindinis vykdymo variklis.
- config/exporter.yaml - baziniai nustatymai (connection, extensions, output, task root).
- tasks/ - task aplankai su objects.txt.
- scripts/ - SQL*Plus eksportavimo skriptai.
- logs/ - run logai ir sugeneruoti tarpiniai SQL.

## Public aplankas dalinimuisi (UNIVERSAL_EXPORTER_V1_PUBLIC)

`UNIVERSAL_EXPORTER_V1_PUBLIC` yra dalinimuisi paruostas runtime aplankas,
kuriame paliekami tik failai, reikalingi normaliam paleidimui.

Paskirtis:
- perduoti eksporteri kolegoms arba kitai komandai be testiniu artefaktu,
- tureti svaru paketa darbiniam naudojimui,
- mazinti triuksma (test failai, git failai, seni logai).

Kas turi buti `UNIVERSAL_EXPORTER_V1_PUBLIC` viduje:
1. `oracle_exporter.exe`
2. `config/exporter.yaml`
3. `scripts/*.sql`
4. `tasks/TASK_TEMPLATE/objects.txt` (arba bent vienas veikiantis task sablonas)
5. tuscias `logs/` katalogas
6. tuscias `EXPORTED_OBJECTS/` katalogas

Ko neturetu buti public aplanke:
1. `testing/`
2. `.git/`, `.gitignore` ir kiti git failai
3. seni `logs/*.log`
4. jau sugeneruoti eksporto rezultatai is `EXPORTED_OBJECTS/`
5. laikini ar lokalus dev failai

Rekomenduojama minimali struktura:

UNIVERSAL_EXPORTER_V1_PUBLIC/
	oracle_exporter.exe
	README.md
	config/
		exporter.yaml
	scripts/
		...sql failai...
	tasks/
		TASK_TEMPLATE/
			objects.txt
	logs/
	EXPORTED_OBJECTS/

Paleidimas is `UNIVERSAL_EXPORTER_V1_PUBLIC` nesikeicia:

oracle_exporter.exe TASK_123 DEV
oracle_exporter.exe TASK_123 DEV --dry-run
oracle_exporter.exe TASK_123 DEV --preflight

## YAML paskirtis

YAML saugo bendra logika ir nustatymus:
- defaults: sqlplus_executable, output_root, task_root, task_objects_file_name, nls_lang, strict/post-check.
- environments: connection, ddl_source, optional nls/export extension override.
- output: TABLES/VIEWS/TYPES subfolderiai.

Task mode objektu sarasu neima is YAML - jie imami is task objects.txt.

## Paleidimo variantai

Task mode (rekomenduojamas):

oracle_exporter.exe TASK_123 DEV
oracle_exporter.exe TASK_123 DEV APPUSER19

Papildomi variantai:

oracle_exporter.exe TASK_123 DEV --dry-run
oracle_exporter.exe TASK_123 DEV --preflight
oracle_exporter.exe TASK_123 DEV --check
oracle_exporter.exe TASK_123 DEV --nls-lang LITHUANIAN_LITHUANIA.UTF8
oracle_exporter.exe TASK_123 DEV --task-root tasks --task-objects-file objects.txt

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

oracle_exporter.exe TASK_123 DEV --preflight
oracle_exporter.exe TASK_123 DEV APPUSER19 --preflight
oracle_exporter.exe TASK_123 DEV --check

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

