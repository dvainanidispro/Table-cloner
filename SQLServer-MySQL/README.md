# Table Cloner - SQL Server to MySQL

PowerShell script για αντιγραφή δεδομένων από πίνακες/views SQL Server σε MySQL βάση δεδομένων.

## Χαρακτηριστικά

- ✅ Αντιγραφή **SQL Server → MySQL** μόνο
- ✅ Windows Authentication (χωρίς username/password) για τον SQL Server
- ✅ Υποστήριξη SQL Server Authentication (με username/password) αν χρειαστεί
- ✅ Υποστήριξη SQL Server Views ως πηγή δεδομένων
- ✅ Υποστήριξη `[schema].[table]` και `[database].[schema].[table]` format
- ✅ Batch processing για μεγάλους πίνακες
- ✅ Transaction support για ασφαλή αντιγραφή
- ✅ Truncate πίνακα προορισμού πριν την αντιγραφή (προαιρετικό)
- ✅ Preflight έλεγχος πρόσβασης στον πίνακα πηγής πριν το truncate (αποτρέπει απώλεια δεδομένων προορισμού αν υπάρχει πρόβλημα δικαιωμάτων)
- ✅ Mapping πινάκων με διαφορετικά ονόματα
- ✅ Αναλυτικό logging με timestamps
- ✅ Έγχρωμο console output
- ✅ Error handling και summary αναφορά

## Απαιτήσεις

### Λειτουργικό Σύστημα
- **Windows 10** (version 1607 ή νεότερο) ή
- **Windows 11** ή
- **Windows Server 2016** ή νεότερο ή
- **Windows 7/8/8.1** με [Windows Management Framework 5.1](https://www.microsoft.com/en-us/download/details.aspx?id=54616)

### PowerShell
- **PowerShell 5.1** ή νεότερη έκδοση
  - Έρχεται προεγκατεστημένο στα Windows 10/11 και Server 2016+
  - Για παλαιότερα Windows, εγκατάστησε το Windows Management Framework 5.1
  - Για έλεγχο της έκδοσης: `$PSVersionTable.PSVersion`

### .NET Framework
- **.NET Framework 4.6.1** ή νεότερο
  - Συνήθως ήδη εγκατεστημένο σε σύγχρονα Windows
  - Για έλεγχο: `[System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription`
  - Download: [.NET Framework Downloads](https://dotnet.microsoft.com/download/dotnet-framework)

### SQL Server (Source)
- Ο **SQL Server** πρέπει να είναι εγκατεστημένος τοπικά ή προσβάσιμος μέσω δικτύου
- Ο SQL Server client (`sqlcmd`) πρέπει να είναι διαθέσιμος στο σύστημα (δεν χρησιμοποιείται απευθείας, αλλά η ύπαρξή του επιβεβαιώνει σωστή εγκατάσταση)
- Ο **System.Data.SqlClient** (.NET driver) είναι **ενσωματωμένος** στο .NET Framework — δεν χρειάζεται ξεχωριστή εγκατάσταση

### Database Drivers

Χρειάζονται μόνο τα drivers για τη **MySQL destination**. Ο SQL Server driver είναι ήδη ενσωματωμένος στο .NET Framework.

#### Αυτόματη Εγκατάσταση (Προτεινόμενη)

Τρέξε, μία μόνο φορά, το script εγκατάστασης που κατεβάζει αυτόματα τα απαραίτητα DLL files:

```powershell
.\Install-Drivers.ps1
```

**Αν το script δεν εκτελείται λόγω execution policy**, δοκίμασε:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Install-Drivers.ps1"
```

Το script θα κατεβάσει τα MySQL drivers και τα dependencies και θα τα τοποθετήσει στο φάκελο `\lib`

#### Δομή Φακέλου

Μετά την εγκατάσταση, ο φάκελος θα έχει:

```
SQLServer-MySQL/
├── Table-Cloner.ps1
├── Install-Drivers.ps1
├── env.json
├── README.md
├── working-example.bat       (παράδειγμα sqlcmd αντιγραφής)
├── lib/                      (δημιουργείται από Install-Drivers.ps1)
│   └── *.dll                 (MySQL drivers και dependencies)
└── logs/                     (δημιουργείται από Table-Cloner.ps1)
    └── table-cloner_YYYYMMDD_HHMMSS.log
```

## Ρύθμιση (Configuration)

Επεξεργάσου το αρχείο `env.json` με τα στοιχεία των βάσεων σου:

```json
{
    "DatabaseFrom": {
        "type": "sqlserver",
        "host": "sqlserver-host.example.local",
        "port": 1433,
        "username": "",
        "password": "",
        "database": "source_database"
    },
    "DatabaseTo": {
        "type": "mysql",
        "host": "mysql-target.example.local",
        "port": 3306,
        "username": "destination_user",
        "password": "destination_password",
        "database": "destination_database"
    },
    "Settings": {
        "BatchSize": 1000,
        "TimeoutSeconds": 300,
        "LogFile": ".\\logs",
        "TruncateBeforeInsert": true
    },
    "TableMappings": [
        {
            "from": "[dbo].[SampleView]",
            "to": "sample_view"
        }
    ]
}
```

### Παράμετροι Configuration

#### DatabaseFrom (SQL Server)
- `type`: Πάντα `"sqlserver"`
- `host`: Hostname, IP, ή instance name του SQL Server. Παραδείγματα:
    - `"sqlserver-host.example.local"` — hostname
  - `"localhost"` — τοπικός default instance
  - `".\\SQLEXPRESS"` — τοπικός named instance (σημ: `\\` γιατί είναι JSON escape)
    - `"sqlserver-host.internal"` — εσωτερικό DNS hostname
- `port`: Port του SQL Server (default: `1433`). **Αγνοείται αν το host περιέχει `\`** (named instance)
- `username`: Username για SQL Server Authentication. **Κενό `""` = Windows Authentication**
- `password`: Password για SQL Server Authentication. **Κενό `""` = Windows Authentication**
- `database`: Όνομα της βάσης δεδομένων (π.χ. `"source_database"`)

> **Windows Authentication**: Αν τρέχεις το script ως administrator ή ως χρήστη με δικαιώματα στον SQL Server, άφησε τα `username` και `password` κενά (`""`). Το script θα χρησιμοποιήσει τα Windows credentials αυτόματα.

#### DatabaseTo (MySQL)
- `type`: Πάντα `"mysql"`
- `host`: Hostname ή IP της MySQL βάσης
- `port`: Port της MySQL βάσης (default: `3306`)
- `username`: Username για σύνδεση MySQL
- `password`: Password για σύνδεση MySQL
- `database`: Όνομα της βάσης δεδομένων MySQL

#### Settings
- `BatchSize`: Πόσες εγγραφές να αντιγράφονται σε κάθε transaction. Προτεινόμενες τιμές:
  
  | Σενάριο | BatchSize |
  |---------|-----------|
  | Μικροί πίνακες (5-10 columns, VARCHAR/INT) | 5000-10000 |
  | Μεσαίοι πίνακες (10-20 columns) | 1000-5000 |
  | Μεγάλοι πίνακες (20+ columns ή TEXT/BLOB) | 500-1000 |
  | Πολύ μεγάλα δεδομένα (JSON, binary) | 100-500 |
  
  **Γενικά ασφαλές**: 1000-2000 για τα περισσότερα σενάρια (default: 1000)

- `TimeoutSeconds`: Χρονικό όριο για κάθε query σε δευτερόλεπτα (default: 300)
- `LogFile`: Φάκελος για αποθήκευση των log files (default: `.\logs`)
- `TruncateBeforeInsert`: Αν θα διαγράφονται τα υπάρχοντα δεδομένα πριν την αντιγραφή (`true` ή `false`)
  - `true`: Διαγράφει όλα τα δεδομένα και κάνει clean insert (full replacement)
  - `false`: **ΠΡΟΣΟΧΗ** - Κάνει μόνο INSERT χωρίς διαγραφή. Θα προκύψουν **duplicate key errors** αν υπάρχουν PRIMARY KEY ή UNIQUE constraints, και **διπλές εγγραφές** αν τρέξεις το script πολλές φορές. Χρήσιμο μόνο για append mode όταν ξέρεις ότι δεν θα υπάρχουν conflicts.

#### TableMappings
Λίστα με τους πίνακες που θα αντιγραφούν:
- `from`: Όνομα πίνακα ή view στον SQL Server. Υποστηρίζονται:
  - `"[dbo].[TableName]"` — schema + table (προτεινόμενο)
    - `"[ExampleSourceDb].[dbo].[SampleView]"` — database + schema + table
  - `"TableName"` — απλό όνομα (χρησιμοποιεί default schema `dbo`)
- `to`: Όνομα πίνακα στη MySQL βάση προορισμού

## Χρήση

### Βασική Εκτέλεση

```powershell
.\Table-Cloner.ps1
```

Το script θα διαβάσει το `env.json` από τον τρέχοντα φάκελο.

### Εκτέλεση με Custom Configuration Path

```powershell
.\Table-Cloner.ps1 -ConfigPath "C:\path\to\custom-config.json"
```

### Εκτέλεση αν υπάρχει Execution Policy πρόβλημα

```powershell
powershell -ExecutionPolicy Bypass -File ".\Table-Cloner.ps1"
```

## Logging

Το script δημιουργεί αναλυτικά logs για κάθε εκτέλεση:

### Τοποθεσία Logs
Τα log files αποθηκεύονται στον φάκελο που ορίζεται στο `Settings.LogFile` (default: `.\logs`)

### Μορφή Log Filename
```
table-cloner_YYYYMMDD_HHMMSS.log
```

Παράδειγμα: `table-cloner_20260227_143025.log`

### Περιεχόμενο Log

Κάθε log file περιέχει:
- Timestamp για κάθε ενέργεια
- Level (INFO, SUCCESS, WARNING, ERROR)
- Λεπτομερή αναφορά για κάθε πίνακα
- Authentication mode (Windows Auth ή SQL Server Auth)
- Σύνοψη με επιτυχίες/αποτυχίες
- Stack trace σε περίπτωση critical errors

## Προϋποθέσεις για Επιτυχή Αντιγραφή

1. **Schema Compatibility**: Οι πίνακες προορισμού (MySQL) πρέπει να υπάρχουν ήδη με συμβατό schema
2. **Permissions**:
   - Source (SQL Server): `SELECT` στους πίνακες/views. Αν χρησιμοποιείς Windows Auth, ο χρήστης που τρέχει το script πρέπει να έχει πρόσβαση στη βάση
   - Destination (MySQL): `INSERT`, `TRUNCATE` (αν ενεργοποιημένο)
3. **Network**: Connectivity μεταξύ του μηχανήματος και του MySQL server
4. **Disk Space**: Επαρκής χώρος στη βάση προορισμού

## Υποστηριζόμενες Αντιγραφές

| Source       | Destination  | Supported |
|--------------|--------------|-----------|
| SQL Server   | MySQL        | ✅ Ναι    |

## Error Handling

- Κάθε πίνακας αντιγράφεται ανεξάρτητα - αν αποτύχει ένας, οι άλλοι συνεχίζουν
- Batch transactions: Αν αποτύχει ένα batch, κάνει rollback μόνο αυτό το batch
- Όλα τα errors καταγράφονται στο log file
- Exit code: 0 για επιτυχία, 1 για αποτυχία

## Tips

### Για Μεγάλους Πίνακες
- Μείωσε το `BatchSize` αν αντιμετωπίζεις memory issues
- Αύξησε το `TimeoutSeconds` αν οι queries είναι αργές

### Για Production Χρήση
- Κάνε backup πριν τρέξεις το script με `TruncateBeforeInsert: true`
- Δοκίμασε πρώτα σε test environment
- Τρέξε το script σε περιόδους χαμηλής κίνησης

### Performance
- Το `BatchSize: 1000` είναι καλή αφετηρία
- Για πολύ μεγάλους πίνακες (>1M rows), δοκίμασε `BatchSize: 5000-10000`
- Για πίνακες με πολλές στήλες ή μεγάλα data types, μείωσε το BatchSize

## Troubleshooting

### "Failed to load MySql.Data.dll"
- Τρέξε πρώτα `.\Install-Drivers.ps1` για να κατεβάσεις τα MySQL drivers
- Βεβαιώσου ότι τα DLL files είναι στον φάκελο `lib\`

### "SQL Server Connection Error"
- Βεβαιώσου ότι ο SQL Server τρέχει (ειδικά αν είναι τοπικός)
- Έλεγξε το hostname/instance name στο env.json
- Αν χρησιμοποιείς named instance (π.χ. `.\SQLEXPRESS`), το port αγνοείται
- Βεβαιώσου ότι τρέχεις το script ως administrator (αν χρειάζεται Windows Auth)
- Δοκίμασε σύνδεση μέσω `sqlcmd` για επιβεβαίωση: `sqlcmd -S sqlserver-host.example.local -d source_database -E -Q "SELECT 1"`

### "MySQL Connection Error"
- Έλεγξε τα MySQL credentials στο env.json
- Βεβαιώσου ότι ο MySQL server είναι προσβάσιμος μέσω δικτύου
- Έλεγξε firewall rules στο remote μηχάνημα

### "Table not found"
- Για SQL Server: Βεβαιώσου ότι χρησιμοποιείς σωστό format στο `from` (π.χ. `[dbo].[TableName]`)
- Για MySQL: Βεβαιώσου ότι οι πίνακες προορισμού υπάρχουν ήδη
- Έλεγξε τα ονόματα για typos

### "Permission denied" / "Preflight check FAILED"
- Το authentication μπορεί να έχει γίνει με επιτυχία, αλλά ο χρήστης να μην έχει `SELECT` δικαιώματα στον συγκεκριμένο πίνακα ή view
- Σε αυτή την περίπτωση το script **δεν θα αγγίξει τον πίνακα προορισμού** — το preflight `SELECT TOP 1` αποτυγχάνει πριν γίνει truncate
- SQL Server (Windows Auth): Βεβαιώσου ότι ο Windows χρήστης έχει `SELECT` permissions στον πίνακα/view
- SQL Server (SQL Auth): Βεβαιώσου ότι ο SQL login έχει πρόσβαση στη βάση και `SELECT` στον πίνακα/view
- **Linked Server / Cross-database views**: Αν ο πίνακας/view αναφέρεται σε linked server ή άλλη βάση, ο χρήστης χρειάζεται τα αντίστοιχα δικαιώματα και εκεί — το authentication στον primary server δεν αρκεί
- MySQL: `GRANT INSERT, DELETE ON destination_database.* TO 'user'@'%';`

## Παραδείγματα

### Παράδειγμα 1: Windows Auth + Single Table
```json
{
    "DatabaseFrom": {
        "type": "sqlserver",
        "host": "sqlserver-host.example.local",
        "port": 1433,
        "username": "",
        "password": "",
        "database": "source_database"
    },
    "DatabaseTo": {
        "type": "mysql",
        "host": "mysql-target.example.local",
        "port": 3306,
        "username": "destination_user",
        "password": "destination_password",
        "database": "destination_mirror"
    },
    "Settings": {
        "BatchSize": 2000,
        "TimeoutSeconds": 600,
        "LogFile": ".\\logs",
        "TruncateBeforeInsert": true
    },
    "TableMappings": [
        {"from": "[dbo].[SampleView]", "to": "sample_view"}
    ]
}
```

### Παράδειγμα 2: Πολλαπλοί Πίνακες με Views
```json
{
    "DatabaseFrom": {
        "type": "sqlserver",
        "host": "localhost",
        "port": 1433,
        "username": "",
        "password": "",
        "database": "source_database"
    },
    "DatabaseTo": {
        "type": "mysql",
        "host": "mysql-target.example.local",
        "port": 3306,
        "username": "destination_user",
        "password": "destination_password",
        "database": "destination_reporting"
    },
    "Settings": {
        "BatchSize": 5000,
        "TimeoutSeconds": 600,
        "LogFile": ".\\logs",
        "TruncateBeforeInsert": true
    },
    "TableMappings": [
        {"from": "[dbo].[Customers]", "to": "customers"},
        {"from": "[dbo].[Orders]", "to": "orders"},
        {"from": "[dbo].[vw_MonthlyReport]", "to": "monthly_report"}
    ]
}
```

### Παράδειγμα 3: SQL Server Authentication (Named Instance)
```json
{
    "DatabaseFrom": {
        "type": "sqlserver",
        "host": ".\\SQLEXPRESS",
        "port": 1433,
        "username": "sql_auth_user",
        "password": "sql_auth_password",
        "database": "source_database"
    },
    "DatabaseTo": {
        "type": "mysql",
        "host": "mysql-target.example.local",
        "port": 3306,
        "username": "destination_user",
        "password": "destination_password",
        "database": "destination_database"
    },
    "Settings": {
        "BatchSize": 1000,
        "TimeoutSeconds": 300,
        "LogFile": ".\\logs",
        "TruncateBeforeInsert": true
    },
    "TableMappings": [
        {"from": "[dbo].[Products]", "to": "products"}
    ]
}
```

## License

Αυτό είναι ένα template script για εσωτερική χρήση.

## Support

Για issues και προτάσεις, ελέγξτε πρώτα:
1. Τα log files για λεπτομερή error messages
2. Το troubleshooting section
3. Database server logs

---

**Σημείωση**: Το script δεν κάνει schema validation ή migration. Οι πίνακες προορισμού πρέπει να υπάρχουν ήδη με συμβατό schema.
