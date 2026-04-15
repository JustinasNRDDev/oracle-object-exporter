# UNIVERSAL_EXPORTER Workspace

Sutvarkyta root struktura ilgalaikei projekto pletrai ir naudojimui.

## Katalogai

1. `UNIVERSAL_EXPORTER_IMPROVED`
   - Source kodas (Python) tolesnei pletrai ir tobulinimui.
   - Cia keiciama logika, skriptai, validacijos, build procesas.

2. `UNIVERSAL_EXPORTER_V1`
   - Runtime leidinys be Python source.
   - Skirtas vykdymui per `oracle_exporter.exe`.

3. `UNIVERSAL_EXPORTER_V2`
   - Runtime leidinys be Python ir be `.exe` pasirasymo poreikio.
   - Skirtas vykdymui per `oracle_exporter_task.bat` (BAT + PowerShell).

## Ar Python reikalingas?

Taip, jei norite toliau tobulinti projekta, Python source yra reikalingas.

- Be Python galite vykdyti:
   - `UNIVERSAL_EXPORTER_V1` per `oracle_exporter.exe`.
   - `UNIVERSAL_EXPORTER_V2` per `oracle_exporter_task.bat` (PowerShell + SQL*Plus).
- Su Python galite keisti `run_export.py`, plesti funkcionaluma, taisyti logika ir perbuildinti nauja `.exe` versija.

## Git paruosimas

Root lygyje pridetas `.gitignore`, kuris neitraukia runtime rezultatu:

- `logs/**`
- `EXPORTED_OBJECTS/**`

Palikti `.gitkeep`, kad katalogu struktura isliktu repozitorijoje.

## Rekomenduojamas darbo modelis

1. Kurti ir testuoti pakeitimus `UNIVERSAL_EXPORTER_IMPROVED`.
2. Isleisti stabilia versija i `UNIVERSAL_EXPORTER_V1`.
3. Jei darbo aplinkoje blokuojamas `.exe`, naudoti `UNIVERSAL_EXPORTER_V2` per BAT + PowerShell.
