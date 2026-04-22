# UNIVERSAL_EXPORTER_V2

Oracle objektu eksportavimas be Python, be PowerShell ir be .exe pasirasymo.

Sis variantas skirtas darbo aplinkai, kur:
- nera Python,
- nera admin teisiu,
- reikia paleidimo tik su `.bat` sintakse (be PowerShell).

## Kas reikalinga

1. SQL*Plus (Oracle client) PATH arba nurodytas `sqlplus_executable` config'e.
2. Prisijungimo failai pagal `config/exporter.yaml`.

## Paleidimas

Komanda:

oracle_exporter_task.bat TASK ENV [SCHEMA] [--dry-run] [--preflight] [-ConfigPath path]
oracle_exporter_task.bat --ls [ENV] [SCHEMA] [--dry-run] [--preflight] [-ConfigPath path]

Pavyzdziai:

oracle_exporter_task.bat TASK_123 DEV
oracle_exporter_task.bat TASK_123 DEV APPUSER19
oracle_exporter_task.bat TASK_123 DEV --dry-run
oracle_exporter_task.bat TASK_123 DEV APPUSER19 --dry-run
oracle_exporter_task.bat TASK_123 DEV --preflight
oracle_exporter_task.bat TASK_123 DEV APPUSER19 --preflight
oracle_exporter_task.bat TASK_123 DEV --preflight -ConfigPath .\config\exporter.yaml
oracle_exporter_task.bat --ls
oracle_exporter_task.bat --ls DEV --dry-run

## Task sarasas ir pasirinkimas (--ls)

`--ls` skirtas greitai pasirinkti jau esama task is `EXPORTED_OBJECTS`.

Kas vyksta:

1. Isspausdinami visi task katalogai, kuriuose yra `objects.txt`.
2. Jei pasiekiamas PowerShell, task galima pasirinkti su Up/Down rodyklemis ir Enter.
3. Jei PowerShell nepasiekiamas, veikia fallback pasirinkimas pagal numeri.
4. Po task pasirinkimo galite ivesti ENV (pvz. DEV/TEST/PROD) ir optional SCHEMA.

Pavyzdziai:

oracle_exporter_task.bat --ls
oracle_exporter_task.bat --ls DEV
oracle_exporter_task.bat --ls DEV APPUSER19 --preflight

## Ka tiksliai duoda --dry-run

`--dry-run` yra saugus planavimo rezimas pries realu eksporta.

Kas ivyksta su `--dry-run`:

1. Patikrinami ivesties argumentai (TASK, ENV, optional SCHEMA).
2. Nuskaitymas ir validacija:
	- `config/exporter.yaml`
	- `EXPORTED_OBJECTS/<TASK>/objects.txt`
3. Patikrinama, kad egzistuoja connection failas is config ir ji galima perskaityti.
4. Suformuojamas vykdymo planas su auksto lygio zingsniu suvestine (`START`/`DONE`) ir pilnu objektu sarasu ataskaitoje.
5. Sukuriamas run logas `logs/bat_export_<timestamp>.log`.

Ko `--dry-run` nedaro:

1. Nepaleidzia SQL*Plus komandu.
2. Nesijungia prie Oracle DB.
3. Neeksportuoja objektu turinio i failus.

Svarbi praktine pastaba:

- `--dry-run` gali sukurti tik run katalogo struktura po `EXPORTED_OBJECTS/...` ir log faila, bet ne objektu DDL/source turini.
- Jei reikia tik patikrinti plana pries produkcini paleidima, visada pirma naudokite `--dry-run`.

## Eksportuotu objektu sarasas vienoje vietoje

Pagrindinis run logas `logs/bat_export_<timestamp>.log` dabar paliktas svarus (tiek realiame vykdyme, tiek `--dry-run`):

- neberaso `OBJECT LIST`, `EXPORTED OBJECT`, `PLAN OBJECT` ir `QUEUE` eiluciu;
- palieka tik auksto lygio eiga (START/DONE/BATCH/summary).

`--dry-run` rezime neberasomos per-objekto `EXECUTE` komandos.

Run pabaigoje vis dar rasomas objektu kiekio summary:

- `exported_objects=<kiekis>` (realus vykdymas)
- `planned_objects=<kiekis>` (`--dry-run`)

Pilnas objektu sarasas rasomas i atskira faila:

- `logs/exported_objects_<timestamp>.txt`

Failo formatas:

- `mode|schema|step|object`

Kur `mode` yra `EXPORT` (realus vykdymas) arba `PLAN` (`--dry-run`).

## DB prisijungimas vykdymo metu

Realiame eksporte (be `--dry-run`) objektu SQL komandos dabar sujungiamos i viena SQL*Plus batch ir vykdomos per viena DB sesija per run.

Ką tai duoda:

1. Nebedaromas naujas prisijungimas kiekvienam objektui.
2. Mazesne prisijungimu apkrova DB puseje.
3. Greitesnis vykdymas, kai task'e yra daug objektu.

## Ka tiksliai duoda --preflight

`--preflight` (arba alias `--check`) yra paruosties patikra pries paleidima.

Kas ivyksta su `--preflight`:

1. Patikrinami ivesties argumentai ir task failo struktura.
2. Patikrinama, ar pasiekiamas `sqlplus` (`PATH` arba `sqlplus_executable`).
3. Patikrinama, ar yra visi privalomi `scripts/*.sql` failai, reikalingi eksportui.
4. Patikrinamas prisijungimas prie Oracle DB.
5. Oracle sesijoje surenkama teisiu suvestine ir apskaiciuojamos eksporto galimybes pagal objektu tipus.
6. Preflight palygina task'e nurodytus objektu tipus su realiomis galimybemis ir aiskiai pranesa, kas leidziama / kas neleidziama.

Ko `--preflight` nedaro:

1. Neeksportuoja objektu i failus.
2. Nevykdo realiu objektu eksporto SQL skriptu.

Minimalios Oracle teises objektu eksportui:

1. Bazine teise prisijungimui:
- `CREATE SESSION`

2. Jei reikia proceduru source eksporto:
- `DEBUG ANY PROCEDURE`

3. Jei reikia `tables`, `views`, `types` (ir daugeliu atveju platesnio source skaitymo):
- `SELECT_CATALOG_ROLE` arba
- `SELECT ANY DICTIONARY`

Kitaip tariant, pilno development teisiu rinkinio paprastam eksportui nereikia.

Ka tiksliai pamatysite `--preflight` rezultate:

- Teisiu suvestine (`CREATE SESSION`, `SELECT ANY DICTIONARY`, `DEBUG ANY PROCEDURE`, `SELECT_CATALOG_ROLE`).
- Galimybiu matrica pagal tipus: `packages`, `procedures`, `functions`, `types`, `tables`, `views`.
- Jei task'e yra tipu, kuriems naudotojas teisiu neturi, preflight baigsis klaida ir parodys trukstamus tipus.

## Struktura

- `oracle_exporter_task.bat` - pagrindinis entrypoint.
- `scripts/run_export_task.bat` - pagrindinis task parseris ir vykdymo variklis (BAT), su tuo paciu CLI (`TASK ENV [SCHEMA] [--dry-run]`) ir named parametru palaikymu.
- `config/exporter.yaml` - baziniai nustatymai (connection, extensions, ddl_source).
- `EXPORTED_OBJECTS/<TASK>/objects.txt` - task objektu sarasai.
- `scripts/*.sql` - SQL*Plus eksportavimo skriptai.
- `logs/` - vykdymo logai.
- `EXPORTED_OBJECTS/` - sugeneruoti objektai.

Path/logikos pastaba:

- Paleidimo `.bat` failai visus vidinius kelius skaiciuoja nuo savo direktorijos (`%~dp0`), todel eksporteri galima paleisti is bet kurios vietos (nebutina pirma `cd` i projekto kataloga).
- Jei nurodytas task aplankas dar neegzistuoja, skriptas paklaus ar ji sukurti ir automatiskai sugeneruos uzkomentuota `objects.txt` sablona.

## Pastabos

- `objects.txt` formatas: [ENV] blokai, `schema:`, ir objektu tipai (`packages`, `procedures`, `functions`, `tables`, `views`, `types`).
- NLS koduote gali buti nurodyta task faile per `nls_lang:`.
- `config/exporter.yaml` `export_extensions` reiksmes gali buti bet kokios (pvz. `pr`, `prc`, `fc`, `fnc`, `pkgx`, `sqlx` ir pan.) - jos neberibojamos iki fiksuoto saraso.

## Testavimas

- Test scenariju kontraktas: `testing/TEST_SCENARIOS.md`
- Automatiniu kontraktiniu testu paleidimas: `testing/run_contract_tests.bat`

Komanda:

testing\run_contract_tests.bat

Testu tikslas:

- Uzfiksuoti funkcini kontrakta, kad perrasant i Python/EXE/C# butu islaikytas identiskas elgesys.
