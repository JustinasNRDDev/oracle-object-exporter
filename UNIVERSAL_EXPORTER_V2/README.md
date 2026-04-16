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

oracle_exporter_task.bat TASK ENV [SCHEMA] [--dry-run]

Pavyzdziai:

oracle_exporter_task.bat TASK_123 DEV
oracle_exporter_task.bat TASK_123 DEV APPUSER19
oracle_exporter_task.bat TASK_123 DEV --dry-run
oracle_exporter_task.bat TASK_123 DEV APPUSER19 --dry-run

## Ka tiksliai duoda --dry-run

`--dry-run` yra saugus planavimo rezimas pries realu eksporta.

Kas ivyksta su `--dry-run`:

1. Patikrinami ivesties argumentai (TASK, ENV, optional SCHEMA).
2. Nuskaitymas ir validacija:
	- `config/exporter.yaml`
	- `tasks/<TASK>/objects.txt`
3. Patikrinama, kad egzistuoja connection failas is config ir ji galima perskaityti.
4. Suformuojamas pilnas vykdymo planas: kiekvienam zingsniui atspausdinamos SQL*Plus komandos (`EXECUTE | ...`).
5. Sukuriamas run logas `logs/bat_export_<timestamp>.log`.

Ko `--dry-run` nedaro:

1. Nepaleidzia SQL*Plus komandu.
2. Nesijungia prie Oracle DB.
3. Neeksportuoja objektu turinio i failus.

Svarbi praktine pastaba:

- `--dry-run` gali sukurti tik run katalogo struktura po `EXPORTED_OBJECTS/...` ir log faila, bet ne objektu DDL/source turini.
- Jei reikia tik patikrinti plana pries produkcini paleidima, visada pirma naudokite `--dry-run`.

## Struktura

- `oracle_exporter_task.bat` - pagrindinis entrypoint.
- `scripts/run_export_task.bat` - pagrindinis task parseris ir vykdymo variklis (BAT), su tuo paciu CLI (`TASK ENV [SCHEMA] [--dry-run]`) ir named parametru palaikymu.
- `config/exporter.yaml` - baziniai nustatymai (connection, extensions, ddl_source).
- `tasks/<TASK>/objects.txt` - task objektu sarasai.
- `scripts/*.sql` - SQL*Plus eksportavimo skriptai.
- `logs/` - vykdymo logai.
- `EXPORTED_OBJECTS/` - sugeneruoti objektai.

Path/logikos pastaba:

- Paleidimo `.bat` failai visus vidinius kelius skaiciuoja nuo savo direktorijos (`%~dp0`), todel eksporteri galima paleisti is bet kurios vietos (nebutina pirma `cd` i projekto kataloga).

## Pastabos

- `objects.txt` formatas: [ENV] blokai, `schema:`, ir objektu tipai (`packages`, `procedures`, `functions`, `tables`, `views`, `types`).
- NLS koduote gali buti nurodyta task faile per `nls_lang:`.
