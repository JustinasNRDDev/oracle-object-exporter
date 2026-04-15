# UNIVERSAL_EXPORTER Workspace

Sutvarkyta root struktura ilgalaikei projekto pletrai ir naudojimui.

## Katalogai

1. `UNIVERSAL_EXPORTER_IMPROVED`
   - Source kodas (Python) tolesnei pletrai ir tobulinimui.
   - Cia keiciama logika, skriptai, validacijos, build procesas.

2. `UNIVERSAL_EXPORTER_V1`
   - Runtime leidinys be Python source.
   - Skirtas vykdymui per `oracle_exporter.exe`.

## Ar Python reikalingas?

Taip, jei norite toliau tobulinti projekta, Python source yra reikalingas.

- Be Python galite tik vykdyti esama `.exe`.
- Su Python galite keisti `run_export.py`, plesti funkcionaluma, taisyti logika ir perbuildinti nauja `.exe` versija.

## Git paruosimas

Root lygyje pridetas `.gitignore`, kuris neitraukia runtime rezultatu:

- `logs/**`
- `EXPORTED_OBJECTS/**`

Palikti `.gitkeep`, kad katalogu struktura isliktu repozitorijoje.

## Rekomenduojamas darbo modelis

1. Kurti ir testuoti pakeitimus `UNIVERSAL_EXPORTER_IMPROVED`.
2. Isleisti stabilia versija i `UNIVERSAL_EXPORTER_V1`.
3. `UNIVERSAL_EXPORTER_V1` naudoti vykdymui aplinkose be Python.
"# oracle-object-exporter" 
