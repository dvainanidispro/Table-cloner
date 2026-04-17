# Table Cloner Templates

Συλλογή από PowerShell templates για αντιγραφή δεδομένων μεταξύ συγκεκριμένων ζευγών βάσεων δεδομένων.

Κάθε φάκελος περιέχει αυτόνομο script για ένα συγκεκριμένο source/target σενάριο, μαζί με το δικό του documentation, sample `env.json`, installer για drivers και φάκελο logs.

## Τι κάνει το repository

- Αντιγράφει δεδομένα από πίνακες ή views μεταξύ βάσεων.
- Υποστηρίζει batch processing για μεγάλους όγκους δεδομένων.
- Χρησιμοποιεί transactions και αναλυτικό logging ανά εκτέλεση.
- Υποστηρίζει mapping μεταξύ διαφορετικών ονομάτων πινάκων.
- Περιλαμβάνει επιλογές για ασφαλέστερη εκτέλεση, όπως προαιρετικό truncate πριν το insert.

## Διαθέσιμα templates

| Σενάριο | Φάκελος | README |
|---|---|---|
| MySQL -> MySQL | `MySQL-MySQL/` | [MySQL-MySQL/README.md](./MySQL-MySQL/README.md) |
| MySQL -> PostgreSQL | `MySQL-PostgreSQL/` | [MySQL-PostgreSQL/README.md](./MySQL-PostgreSQL/README.md) |
| PostgreSQL -> PostgreSQL | `PostgreSQL-PostgreSQL/` | [PostgreSQL-PostgreSQL/README.md](./PostgreSQL-PostgreSQL/README.md) |
| SQL Server -> MySQL | `SQLServer-MySQL/` | [SQLServer-MySQL/README.md](./SQLServer-MySQL/README.md) |

## Πώς να το δεις

Διάλεξε τον φάκελο που αντιστοιχεί στο migration που θέλεις να κάνεις και άνοιξε το αντίστοιχο README. Εκεί υπάρχουν οι λεπτομέρειες για prerequisites, drivers, configuration, execution και troubleshooting.

## Σημειώσεις

- Τα templates είναι χωρισμένα ανά database combination, όχι ως ένα ενιαίο universal tool.
- Το schema των πινάκων προορισμού πρέπει να υπάρχει ήδη και να είναι συμβατό με τα δεδομένα που θα μεταφερθούν. Το script δεν δημιουργεί ή τροποποιεί το schema, παρά μόνο αντιγράφει τα δεδομένα.
- Οι οδηγίες εγκατάστασης και ρυθμίσεων παραμένουν σκόπιμα στα επιμέρους README αρχεία.
