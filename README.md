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

## --dry-run (visur vienoda logika)

`--dry-run` skirtas saugiai pasitikrinti vykdymo plana pries realu eksporta.

Kas vyksta:
- tikrinami argumentai ir konfiguracija,
- nuskaitymas `config/exporter.yaml` ir task `objects.txt`,
- validuojama, kad connection failas egzistuoja,
- atspausdinamas pilnas EXECUTE planas,
- sukuriamas vykdymo logas.

Kas nevyksta:
- SQL*Plus komandos nepaleidziamos,
- prisijungimas prie DB nevyksta,
- objektu turinys neeksportuojamas.

Komandu pavyzdziai:
- `UNIVERSAL_EXPORTER_IMPROVED`: `python run_export.py TASK_123 DEV --dry-run`
- `UNIVERSAL_EXPORTER_V1`: `oracle_exporter.exe TASK_123 DEV --dry-run`
- `UNIVERSAL_EXPORTER_V2`: `oracle_exporter_task.bat TASK_123 DEV --dry-run`

## Oracle teises pilnam projekto vystymui

Pilnas development profilis reikalingas tada, kai norite ne tik eksportuoti, bet ir aktyviai vystyti/keisti objektus (kurti, alter'inti, drop'inti, derinti):

- `CREATE SESSION`
- `SELECT_CATALOG_ROLE`
- `SELECT ANY DICTIONARY`
- `CREATE ANY TABLE`
- `CREATE ANY INDEX`
- `CREATE ANY SEQUENCE`
- `CREATE ANY VIEW`
- `DROP ANY VIEW`
- `CREATE ANY TYPE`
- `ALTER ANY TYPE`
- `DROP ANY TYPE`
- `CREATE ANY PROCEDURE`
- `ALTER ANY PROCEDURE`
- `DROP ANY PROCEDURE`
- `DEBUG ANY PROCEDURE`

Pastaba:
- Paprastam DB objektu eksportavimui pilno development profilio nereikia.
- Minimalios eksporto teises ir preflight capability patikra aprasytos `UNIVERSAL_EXPORTER_V2/README.md`.

## Nuo nulio: Oracle ir aplinkos paruosimas (naujokui)

Sis skyrius skirtas naujam komandos nariui, kad nuo tuscio kompiuterio galetu paleisti, taisyti ir plesti projekta.

### 1) Isankstines salygos

1. Turite Oracle DB su PDB `ORCLPDB1`.
2. Turite SQL*Plus (pvz. Oracle Instant Client su SQL*Plus).
3. Turite administratoriaus prisijungima (SYS/SYSTEM), su kuriuo sukursite roles ir naudotojus.

### 2) SQL*Plus pasiekiamumas per PATH (Windows)

Rekomenduojama i `PATH` itraukti Instant Client kataloga per Windows Environment Variables GUI.

Greitas patikrinimas naujame terminale:

```bat
sqlplus -v
```

Jei komanda nerandama, papildykite PATH ir is naujo paleiskite VS Code.

### 3) Naudotoju ir roliu sukurimas Oracle DB

Zemiau yra pilnas pavyzdys, kaip paruosiamas development naudotojas, testiniu objektu schemos ir eksporto profiliu naudotojai.

```sql
ALTER SESSION SET CONTAINER = ORCLPDB1;

-- Pilnam projekto vystymui (development)
CREATE USER admin_user IDENTIFIED BY "xxx";
CREATE ROLE developer_admin_role;

GRANT CREATE SESSION TO developer_admin_role;
GRANT SELECT ANY DICTIONARY TO developer_admin_role;
GRANT CREATE ANY TABLE TO developer_admin_role;
GRANT CREATE ANY INDEX TO developer_admin_role;
GRANT CREATE ANY SEQUENCE TO developer_admin_role;
GRANT CREATE ANY VIEW TO developer_admin_role;
GRANT DROP ANY VIEW TO developer_admin_role;
GRANT CREATE ANY TYPE TO developer_admin_role;
GRANT ALTER ANY TYPE TO developer_admin_role;
GRANT DROP ANY TYPE TO developer_admin_role;
GRANT CREATE ANY PROCEDURE TO developer_admin_role;
GRANT ALTER ANY PROCEDURE TO developer_admin_role;
GRANT DROP ANY PROCEDURE TO developer_admin_role;
GRANT DEBUG ANY PROCEDURE TO developer_admin_role;
GRANT SELECT_CATALOG_ROLE TO developer_admin_role;

GRANT developer_admin_role TO admin_user;

-- Objektu savininku schemos testavimui
CREATE USER appuser19 IDENTIFIED BY "xxx";
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE TO appuser19;
ALTER USER appuser19 QUOTA UNLIMITED ON USERS;

CREATE USER appuser19_2 IDENTIFIED BY "xxx";
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE TO appuser19_2;
ALTER USER appuser19_2 QUOTA UNLIMITED ON USERS;

-- Eksporto profilis: tik procedure capability
CREATE USER admin_user_prc IDENTIFIED BY "xxx";
CREATE ROLE dev_admin_role_prc;
GRANT dev_admin_role_prc TO admin_user_prc;
GRANT CREATE SESSION TO dev_admin_role_prc;
GRANT DEBUG ANY PROCEDURE TO dev_admin_role_prc;

-- Eksporto profilis: table/view/type capability
CREATE USER admin_user_tbl IDENTIFIED BY "xxx";
CREATE ROLE dev_admin_role_tbl;
GRANT dev_admin_role_tbl TO admin_user_tbl;
GRANT CREATE SESSION TO dev_admin_role_tbl;
GRANT SELECT_CATALOG_ROLE TO dev_admin_role_tbl;
GRANT SELECT ANY DICTIONARY TO dev_admin_role_tbl;

-- Eksporto profilis: procedure + table/view/type capability
CREATE USER admin_user_prc_tbl IDENTIFIED BY "xxx";
CREATE ROLE dev_admin_role_prc_tbl;
GRANT dev_admin_role_prc_tbl TO admin_user_prc_tbl;
GRANT CREATE SESSION TO dev_admin_role_prc_tbl;
GRANT SELECT_CATALOG_ROLE TO dev_admin_role_prc_tbl;
GRANT SELECT ANY DICTIONARY TO dev_admin_role_prc_tbl;
GRANT DEBUG ANY PROCEDURE TO dev_admin_role_prc_tbl;
```

### 4) Connection failai ir globalus aplinkos kintamieji

Projektas skaito connection failus per `%ORACLE19_CONN%` ir papildomus capability testu kelius.

Rekomenduojama lokali struktura (pavyzdys):

```text
C:\oracle\conn\full\connDEV.conf
C:\oracle\conn\full\connTEST.conf
C:\oracle\conn\full\connPROD.conf

C:\oracle\conn\prc\connDEB.conf
C:\oracle\conn\tbl\connDEB.conf
C:\oracle\conn\prc_tbl\connDEB.conf
```

`conn*.conf` failuose viena eilute, pvz.:

```text
admin_user/xxx@localhost:1521/ORCLPDB1
```

arba capability profiliams:

```text
admin_user_prc/xxx@localhost:1521/ORCLPDB1
admin_user_tbl/xxx@localhost:1521/ORCLPDB1
admin_user_prc_tbl/xxx@localhost:1521/ORCLPDB1
```

Globaliu kintamuju pavyzdys (`setx`, paleisti viena karta):

```bat
setx ORACLE19_CONN "C:\oracle\conn\full"
setx ORACLE19_CONN_PRC "C:\oracle\conn\prc"
setx ORACLE19_CONN_TBL "C:\oracle\conn\tbl"
setx ORACLE19_CONN_PRC_TBL "C:\oracle\conn\prc_tbl"
```

Po `setx` butina perkrauti VS Code, kad nauji kintamieji butu matomi procesuose.

### 5) Greitas patikrinimas po setup

```bat
echo %ORACLE19_CONN%
echo %ORACLE19_CONN_PRC%
echo %ORACLE19_CONN_TBL%
echo %ORACLE19_CONN_PRC_TBL%
sqlplus -v
```

Tada galite pradeti nuo:

1. `UNIVERSAL_EXPORTER_IMPROVED` source vystymui ir testams.
2. `UNIVERSAL_EXPORTER_V2` preflight/dry-run capability tikrinimui.

Saugumo pastaba: tikru slaptazodziu nelaikykite repozitorijoje ir nesiuskite i Git.
