# Table Cloner - PostgreSQL to PostgreSQL

PowerShell script για αντιγραφή δεδομένων από πίνακες PostgreSQL σε άλλη PostgreSQL βάση δεδομένων.

## Χαρακτηριστικά

- ✅ Αντιγραφή **PostgreSQL → PostgreSQL** μόνο
- ✅ Υποστήριξη PostgreSQL Views ως πηγή δεδομένων
- ✅ Batch processing για μεγάλους πίνακες
- ✅ Transaction support για ασφαλή αντιγραφή
- ✅ Truncate πίνακα προορισμού πριν την αντιγραφή (προαιρετικό)
- ✅ Preflight έλεγχος πρόσβασης στον πίνακα πηγής πριν το truncate (αποτρέπει απώλεια δεδομένων προορισμού αν υπάρχει πρόβλημα δικαιωμάτων)
- ✅ Mapping πινάκων με διαφορετικά ονόματα
- ✅ Αναλυτικό logging με timestamps
- ✅ Έγχρωμο console output
- ✅ Error handling και summary αναφορά

- ✅ `ValidateOnly` για έλεγχο σύνδεσης σε πηγή και προορισμό και πρόσβασης ανάγνωσης στην πηγή, χωρίς αντιγραφή
- ✅ Επιλογή αρχείου JSON με παράμετρο (προεπιλογή: `env.json`)

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

### Database Drivers

Το script χρειάζεται τα αντίστοιχα .NET drivers ανάλογα με τους τύπους βάσεων που χρησιμοποιείς.

#### Αυτόματη Εγκατάσταση (Προτεινόμενη)

Τρέξε, μία μόνο φορά, το script εγκατάστασης που κατεβάζει αυτόματα τα απαραίτητα DLL files:

```powershell
.\Install-Drivers.ps1
```

**Αν το script δεν εκτελείται λόγω execution policy**, δοκίμασε:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Install-Drivers.ps1"
```

Το script θα κατεβάσει απαραίτητα drivers και τα dependencies και θα τα τοποθετήσει στο φάκελο `\lib`

#### Δομή Φακέλου

Μετά την εγκατάσταση, ο φάκελος θα έχει:

```
Table-cloner/
├── Table-Cloner.ps1
├── Install-Drivers.ps1
├── env.json
├── README.md
├── lib/                          (δημιουργείται από Install-Drivers.ps1)
│   └── *.dll                     (database drivers και dependencies)
└── logs/                         (δημιουργείται από Table-Cloner.ps1)
    └── table-cloner_YYYYMMDD_HHMMSS.log
```

## Ρύθμιση (Configuration)

Επεξεργάσου το αρχείο `env.json` με τα στοιχεία των βάσεων σου:

```json
{
    "DatabaseFrom": {
        "type": "postgresql",
        "host": "remotehost",
        "port": 5432,
        "username": "user_from",
        "password": "password_from",
        "database": "original_db"
    },
    "DatabaseTo": {
        "type": "postgresql",
        "host": "localhost",
        "port": 5432,
        "username": "user_to",
        "password": "password_to",
        "database": "backup_db"
    },
    "Settings": {
        "ValidateOnly": false,
        "BatchSize": 1000,
        "TimeoutSeconds": 300,
        "LogFile": ".\\logs",
        "TruncateBeforeInsert": true
    },
    "TableMappings": [
        {
            "from": "users",
            "to": "app_users"
        },
        {
            "from": "orders",
            "to": "customer_orders"
        }
    ]
}
```

### Παράμετροι Configuration

#### DatabaseFrom / DatabaseTo
- `type`: Τύπος βάσης (πρέπει να είναι `postgresql`)
- `host`: Hostname ή IP της βάσης
- `port`: Port της βάσης (5432 για PostgreSQL)
- `username`: Username για σύνδεση
- `password`: Password για σύνδεση
- `database`: Όνομα της βάσης δεδομένων

#### Settings
- `ValidateOnly`: Προαιρετικό boolean (`true` ή `false`, χωρίς εισαγωγικά).
  - `true`: Ελέγχει τη σύνδεση και στις δύο βάσεις: στη βάση PostgreSQL (πηγή) και στη βάση PostgreSQL (προορισμός), με τα στοιχεία του JSON. Στην πηγή ελέγχει επιπλέον την πρόσβαση ανάγνωσης για κάθε πίνακα/view. Καταγράφει τα αποτελέσματα, χωρίς `TRUNCATE` ή αντιγραφή, ακόμη και αν το `TruncateBeforeInsert` είναι `true`.
  - `false` ή απουσία της ρύθμισης: Εκτελεί κανονικά την αντιγραφή.
  - Στον προορισμό επιβεβαιώνει ότι επιτρέπεται η σύνδεση στη συγκεκριμένη βάση, όχι ότι υπάρχουν δικαιώματα `INSERT` ή `TRUNCATE` στους πίνακες. Αυτά ελέγχονται στην πράξη κατά την κανονική αντιγραφή.
- `BatchSize`: Πόσες εγγραφές να αντιγράφονται σε κάθε transaction. Προτεινόμενες τιμές:
  
  | Σενάριο | BatchSize |
  |---------|-----------|
  | Μικροί πίνακες (5-10 columns, VARCHAR/INT) | 5000-10000 |
  | Μεσαίοι πίνακες (10-20 columns) | 1000-5000 |
  | Μεγάλοι πίνακες (20+ columns ή TEXT/BLOB) | 500-1000 |
  | Πολύ μεγάλα δεδομένα (JSON, binary) | 100-500 |
  
**Γενικά ασφαλές**: 1000-2000 για τα περισσότερα σενάρια (default: 1000). Στο log εμφανίζεται επίσης heuristic εκτίμηση για το current batch size και ένα προτεινόμενο εύρος τιμών, με βάση το συνολικό estimated data size και το μέσο μέγεθος γραμμής.

- `TimeoutSeconds`: Χρονικό όριο για κάθε query σε δευτερόλεπτα (default: 300)
- `LogFile`: Φάκελος για αποθήκευση των log files (default: `.\logs`)
- `TruncateBeforeInsert`: Αν θα διαγράφονται τα υπάρχοντα δεδομένα πριν την αντιγραφή (`true` ή `false`)
  - `true`: Διαγράφει όλα τα δεδομένα και κάνει clean insert (full replacement)
  - `false`: **ΠΡΟΣΟΧΗ** - Κάνει μόνο INSERT χωρίς διαγραφή. Θα προκύψουν **duplicate key errors** αν υπάρχουν PRIMARY KEY ή UNIQUE constraints, και **διπλές εγγραφές** αν τρέξεις το script πολλές φορές. Χρήσιμο μόνο για append mode όταν ξέρεις ότι δεν θα υπάρχουν conflicts.

#### TableMappings
Λίστα με τους πίνακες που θα αντιγραφούν:
- `from`: Όνομα πίνακα ή view στη βάση προέλευσης
- `to`: Όνομα πίνακα στη βάση προορισμού

## Χρήση

### Βασική Εκτέλεση

```powershell
.\Table-Cloner.ps1
```

Χωρίς παράμετρο, το script διαβάζει το `env.json` από **τον φάκελο του script**, ανεξάρτητα από τον τρέχοντα φάκελο εκτέλεσης.

### Εκτέλεση με διαφορετικό αρχείο JSON

```powershell
.\Table-Cloner.ps1 transfers.json
```

Ή με ονομαστική παράμετρο:

```powershell
.\Table-Cloner.ps1 -ConfigPath "transfers.json"
```

Το `transfers.json` πρέπει να βρίσκεται στον ίδιο φάκελο με το `Table-Cloner.ps1`. Η παράμετρος δέχεται μόνο όνομα αρχείου `.json`, όχι διαδρομή. Για όνομα με κενά, χρησιμοποίησε εισαγωγικά, π.χ. `"night transfers.json"`.

### Εκτέλεση με Run with PowerShell

Κάνε δεξί κλικ στο `Table-Cloner.ps1` και επίλεξε **Run with PowerShell**. Χρησιμοποιείται αυτόματα το `env.json` από τον φάκελο του script, επειδή δεν δίνεται παράμετρος.

### Έλεγχος χωρίς αντιγραφή

Στο `Settings` του JSON που θα χρησιμοποιήσεις, όρισε:

```json
"ValidateOnly": true
```

Εκτέλεσε το script με οποιονδήποτε από τους παραπάνω τρόπους. Θα ελεγχθούν η σύνδεση στην πηγή, η σύνδεση στον προορισμό και η πρόσβαση ανάγνωσης στους πίνακες/views της πηγής, με αποτελέσματα στην κονσόλα και στο log. Δεν θα εκτελεστεί `INSERT` ή `TRUNCATE` στον προορισμό ούτε θα ελεγχθούν τα αντίστοιχα δικαιώματα. Για κανονική αντιγραφή, άλλαξε την τιμή σε `false` ή αφαίρεσε τη ρύθμιση.

### Εκτέλεση αν υπάρχει Execution Policy πρόβλημα

```powershell
powershell -ExecutionPolicy Bypass -File ".\Table-Cloner.ps1"
```

Με διαφορετικό JSON:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Table-Cloner.ps1" -ConfigPath "transfers.json"
```

### Εκτέλεση από το Windows Task Scheduler

Δημιούργησε ένα task και όρισε την επιθυμητή ώρα στην καρτέλα **Triggers**. Στην καρτέλα **Actions**, επίλεξε **New → Start a program** και συμπλήρωσε, για παράδειγμα:

| Πεδίο | Τιμή |
|-------|------|
| **Program/script** | `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` |
| **Add arguments (optional)** | `-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Transfers\PostgreSQL-PostgreSQL\Table-Cloner.ps1" -ConfigPath "transfers.json"` |
| **Start in (optional)** | `C:\Transfers\PostgreSQL-PostgreSQL` |

Αντικατάστησε τη διαδρομή του παραδείγματος με τον δικό σου φάκελο. Στο **Start in** βάλε τον φάκελο χωρίς εισαγωγικά. Το JSON αναζητείται πάντα δίπλα στο script, ακόμη και αν το **Start in** μείνει κενό.

Για το προεπιλεγμένο `env.json`, τα **Add arguments** είναι:

```text
-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Transfers\PostgreSQL-PostgreSQL\Table-Cloner.ps1"
```

Για διαφορετικές μεταφορές σε διαφορετικές ώρες, δημιούργησε ξεχωριστά tasks με το ίδιο script και διαφορετικό `-ConfigPath`, π.χ. `"morning.json"` και `"night.json"`. Κάθε JSON περιέχει τις δικές του ρυθμίσεις και `TableMappings`.

## Logging

Το script δημιουργεί αναλυτικά logs για κάθε εκτέλεση:

### Τοποθεσία Logs

Οι σχετικές διαδρομές logs υπολογίζονται από τον φάκελο του script.

Τα log files αποθηκεύονται στον φάκελο που ορίζεται στο `Settings.LogFile` (default: `.\logs`)

### Μορφή Log Filename

Χωρίς παράμετρο ή με **Run with PowerShell**, χρησιμοποιείται το `env.json` και το όνομα του log παραμένει:

```
table-cloner_YYYYMMDD_HHMMSS.log
```

Όταν δίνεται ρητά όνομα JSON ως παράμετρος, προστίθεται στο όνομα του log χωρίς την επέκταση `.json`. Αυτό ισχύει και όταν δίνεται ρητά το `env.json`.

| Εκτέλεση | Παράδειγμα ονόματος log |
|----------|------------------------|
| `.\Table-Cloner.ps1` ή **Run with PowerShell** | `table-cloner_20260417_133541.log` |
| `.\Table-Cloner.ps1 new-transfer.json` | `table-cloner_new-transfer_20260417_133541.log` |
| `.\Table-Cloner.ps1 -ConfigPath env.json` | `table-cloner_env_20260417_133541.log` |

Η ίδια ονομασία εφαρμόζεται και στην εκτέλεση μέσω Task Scheduler και στη λειτουργία `ValidateOnly`. Ο φάκελος εξακολουθεί να ορίζεται από το `Settings.LogFile` του επιλεγμένου JSON.

### Περιεχόμενο Log

Κάθε log file περιέχει:
- Timestamp για κάθε ενέργεια
- Level (INFO, SUCCESS, WARNING, ERROR)
- Λεπτομερή αναφορά για κάθε πίνακα
- Estimated data size, average row size, current batch payload και προτεινόμενο εύρος `BatchSize` (heuristic)
- Σύνοψη με επιτυχίες/αποτυχίες
- Stack trace σε περίπτωση critical errors

## Προϋποθέσεις για Επιτυχή Αντιγραφή

1. **Schema Compatibility**: Οι πίνακες προορισμού πρέπει να υπάρχουν ήδη με συμβατό schema
2. **Permissions**: Τα credentials πρέπει να έχουν δικαιώματα:
   - Source: `SELECT` στους πίνακες/views
   - Destination: `INSERT`, `TRUNCATE` (αν ενεργοποιημένο)
3. **Network**: Connectivity μεταξύ του μηχανήματος που τρέχει το script και των database servers
4. **Disk Space**: Επαρκής χώρος στη βάση προορισμού

## Υποστηριζόμενες Αντιγραφές

| Source       | Destination  | Supported |
|--------------|--------------|-----------|
| MySQL        | MySQL        | ✅ Ναι    |
| MySQL        | PostgreSQL   | ✅ Ναι    |
| PostgreSQL   | PostgreSQL   | ✅ Ναι    |
| PostgreSQL   | MySQL        | ❌ Όχι    |

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
- Χρησιμοποίησε και το log output (`Current batch size` / `Recommended batch size`) για να κάνεις fine-tuning ανά πίνακα

## Troubleshooting

### "Failed to load Npgsql.dll"
- Βεβαιώσου ότι τα DLL files είναι στον φάκελο lib/
- Έλεγξε ότι έχεις την σωστή έκδοση (.NET Framework compatible)
- Τρέξε το Install-Drivers.ps1 ξανά

### "Connection Error"
- Έλεγξε τα credentials στο env.json
- Βεβαιώσου ότι ο database server είναι προσβάσιμος
- Έλεγξε firewall rules

### "Table not found"
- Βεβαιώσου ότι οι πίνακες προορισμού υπάρχουν ήδη
- Έλεγξε τα ονόματα των πινάκων για typos

### "Permission denied"
- Βεβαιώσου ότι ο user έχει τα απαραίτητα privileges
- Για PostgreSQL source: `GRANT SELECT ON ALL TABLES IN SCHEMA public TO user;`
- Για PostgreSQL destination: `GRANT INSERT, TRUNCATE ON ALL TABLES IN SCHEMA public TO user;`
- Για PostgreSQL destination: `GRANT INSERT, TRUNCATE ON ALL TABLES IN SCHEMA public TO user;`

## Παραδείγματα

### Παράδειγμα 1: PostgreSQL → PostgreSQL
```json
{
    "DatabaseFrom": {
        "type": "postgresql",
        "host": "postgres-source.example.local",
        "port": 5432,
        "username": "source_reader",
        "password": "source_password",
        "database": "source_database"
    },
    "DatabaseTo": {
        "type": "postgresql",
        "host": "postgres-target.example.local",
        "port": 5432,
        "username": "destination_user",
        "password": "destination_password",
        "database": "destination_database"
    },
    "Settings": {
        "BatchSize": 2000,
        "TimeoutSeconds": 600,
        "LogFile": ".\\logs",
        "TruncateBeforeInsert": true
    },
    "TableMappings": [
        {"from": "customers", "to": "customers"},
        {"from": "products", "to": "products"}
    ]
}
```

### Παράδειγμα 2: Χρήση PostgreSQL Views
```json
{
    "DatabaseFrom": {
        "type": "postgresql",
        "host": "postgres-source.example.local",
        "port": 5432,
        "username": "source_user",
        "password": "source_password",
        "database": "source_database"
    },
    "DatabaseTo": {
        "type": "postgresql",
        "host": "postgres-target.example.local",
        "port": 5432,
        "username": "destination_user",
        "password": "destination_password",
        "database": "destination_database"
    },
    "Settings": {
        "BatchSize": 1000,
        "TimeoutSeconds": 300,
        "LogFile": "C:\\Logs\\TableCloner",
        "TruncateBeforeInsert": false
    },
    "TableMappings": [
        {"from": "vw_active_users", "to": "users"},
        {"from": "vw_monthly_sales", "to": "sales_archive"}
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
