# UNIVERSAL_EXPORTER_V2

Oracle objektu eksportavimas be Python ir be .exe pasirasymo.

Sis variantas skirtas darbo aplinkai, kur:
- nera Python,
- nera admin teisiu,
- .bat + PowerShell paleidimas veikia patikimiau nei nepasirasytas exe.

## Kas reikalinga

1. Windows PowerShell (standartiskai yra Windows aplinkoje).
2. SQL*Plus (Oracle client) PATH arba nurodytas `sqlplus_executable` config'e.
3. Prisijungimo failai pagal `config/exporter.yaml`.

## Paleidimas

Komanda:

oracle_exporter_task.bat TASK ENV [SCHEMA] [--dry-run]

Pavyzdziai:

oracle_exporter_task.bat TASK_123 DEV
oracle_exporter_task.bat TASK_123 DEV APPUSER19
oracle_exporter_task.bat TASK_123 DEV --dry-run
oracle_exporter_task.bat TASK_123 DEV APPUSER19 --dry-run

## Struktura

- `oracle_exporter_task.bat` - pagrindinis entrypoint.
- `scripts/run_export_task.ps1` - task parseris ir vykdymo variklis (PowerShell).
- `config/exporter.yaml` - baziniai nustatymai (connection, extensions, ddl_source).
- `tasks/<TASK>/objects.txt` - task objektu sarasai.
- `scripts/*.sql` - SQL*Plus eksportavimo skriptai.
- `logs/` - vykdymo logai.
- `EXPORTED_OBJECTS/` - sugeneruoti objektai.

## Pastabos

- `--dry-run` rezime SQLPlus nebus vykdomas, tik parodomas vykdymo planas.
- `objects.txt` formatas: [ENV] blokai, `schema:`, ir objektu tipai (`packages`, `procedures`, `functions`, `tables`, `views`, `types`).
- NLS koduote gali buti nurodyta task faile per `nls_lang:`.
