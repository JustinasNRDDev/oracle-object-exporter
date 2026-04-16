# Local Oracle 19c testavimo aplankas

Sitas aplankas skirtas gyvam `UNIVERSAL_EXPORTER_V1` (EXE runtime) testavimui su lokaliu Oracle 19c konteineriu.

## Kas yra siame aplanke

- `sql/setup_test_objects.sql` - sukuria testinius objektus schemose `APPUSER19` ir `APPUSER19_2`.
- `sql/cleanup_test_objects.sql` - panaikina testinius objektus.
- `data/*.txt` - eksportuojamu objektu sarasai abiem schemoms.
- `setup_objects.ps1` - paleidzia testiniu objektu sukurima.
- `run_live_export.ps1` - paleidzia gyva eksporta per `oracle_exporter.exe --env LOCAL19`.
- `cleanup_objects.ps1` - paleidzia objektu isvalyma.

## Reikalavimai

1. Turi veikti `sqlplus`.
2. Turi buti prieinamas `%ORACLE19_CONN%` (arba User lygio `ORACLE19_CONN`) su failu `connDEV.conf`.
3. `connDEV.conf` turi tureti veikianti `ADMIN_USER` prisijungima.
4. DB turi egzistuoti schemos:
   - `APPUSER19`
   - `APPUSER19_2`

## Ka pakeicia pagrindinis konfigas

Atnaujintas `config/exporter.yaml`:
- nauja aplinka: `LOCAL19`
- naujos catalog schemos: `APPUSER19`, `APPUSER19_2`
- objektu sarasai nukreipti i sita aplanka: `testing/local_oracle19/data/...`
- LOCAL19 testavimo seka pagal nutylejima: `packages`, `procedures`, `functions`, `types`, `view_ddl`
- LOCAL19 naudoja `ddl_source: dba`, kad view/table DDL paieska eitu per `DBA_*` rodinius
- Po realaus run automatinis post-check iesko `ORA-/SP2-/PLS-/TNS-` parasu eksportuotuose failuose

## Testavimo eiga

1. Sukurti testinius objektus:

```powershell
./testing/local_oracle19/setup_objects.ps1
```

2. (Rekomenduojama) Pirma pasitikrinti plana su `--dry-run`:

```powershell
.\oracle_exporter.exe --config config/exporter.yaml --env LOCAL19 --dry-run
```

`--dry-run` validuoja konfiguracija ir parodo visas planuojamas SQL*Plus komandas, bet neprisijungia prie DB ir neeksportuoja objektu turinio.

3. Paleisti gyva eksporta:

```powershell
./testing/local_oracle19/run_live_export.ps1
```

4. Patikrinti rezultata:

```text
EXPORTED_OBJECTS/LOCAL19/<timestamp>/APPUSER19/...
EXPORTED_OBJECTS/LOCAL19/<timestamp>/APPUSER19_2/...
```

5. (Pasirinktinai) Isvalyti objektus:

```powershell
./testing/local_oracle19/cleanup_objects.ps1
```

## Naudojami testiniai objektai

### APPUSER19
- package: `PKG_EXP_TEST_19`
- procedure: `PR_EXP_TEST_19`
- function: `FN_EXP_TEST_19`
- type: `TP_EXP_TEST_19` (with type body)
- view: `VW_EXP_TEST_19`

### APPUSER19_2
- package: `PKG_EXP_TEST_19_2`
- procedure: `PR_EXP_TEST_19_2`
- function: `FN_EXP_TEST_19_2`
- type: `TP_EXP_TEST_19_2` (with type body)
- view: `VW_EXP_TEST_19_2`

## Optional table export

LOCAL19 aplinkoje `table_ddl` jau ijungtas `APPUSER19` schemai (pagal realias lenteles `table_list_APPUSER19.txt`).

Jei noresite plesti ir i `APPUSER19_2`, tuomet:

1. papildyti `schema_steps` su `table_ddl` `APPUSER19_2` schemai,
2. uzpildyti `table_list_APPUSER19_2.txt` realiomis lentelemis.
