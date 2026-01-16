#Requires -Version 5.1

<#
.SYNOPSIS
    Αντιγράφει δεδομένα από πίνακες μιας βάσης δεδομένων σε άλλη.
    
.DESCRIPTION
    Το script διαβάζει τις ρυθμίσεις από το env.json και αντιγράφει δεδομένα
    από πίνακες/views της βάσης προέλευσης στη βάση προορισμού.
    Υποστηρίζει MySQL και PostgreSQL βάσεις.
    
.PARAMETER ConfigPath
    Η διαδρομή του αρχείου env.json. Default: .\env.json
#>

param(
    [string]$ConfigPath = ".\env.json"
)

#region Helper Functions

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Γράφει στο console με χρώμα ανάλογα με το level
    switch ($Level) {
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        default   { Write-Host $logMessage }
    }
    
    # Γράφει στο log file
    Add-Content -Path $script:logFilePath -Value $logMessage
}

# Δημιουργία MySQL connection
function Get-MySqlConnection {
    param(
        [hashtable]$DbConfig
    )
    
    try {
        $connectionString = "Server=$($DbConfig.host);Port=$($DbConfig.port);Database=$($DbConfig.database);Uid=$($DbConfig.username);Pwd=$($DbConfig.password);CharSet=utf8;"
        
        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
        
        return $connection
    }
    catch {
        throw "MySQL Connection Error: $($_.Exception.Message)"
    }
}

# Δημιουργία PostgreSQL connection
function Get-PostgreSqlConnection {
    param(
        [hashtable]$DbConfig
    )
    
    try {
        $connectionString = "Host=$($DbConfig.host);Port=$($DbConfig.port);Database=$($DbConfig.database);Username=$($DbConfig.username);Password=$($DbConfig.password);"
        
        $connection = New-Object Npgsql.NpgsqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
        
        return $connection
    }
    catch {
        throw "PostgreSQL Connection Error: $($_.Exception.Message)"
    }
}

# Δημιουργία connection ανάλογα με τον τύπο της βάσης
function Get-DatabaseConnection {
    param(
        [hashtable]$DbConfig
    )
    
    switch ($DbConfig.type.ToLower()) {
        'mysql' { return Get-MySqlConnection -DbConfig $DbConfig }
        'postgresql' { return Get-PostgreSqlConnection -DbConfig $DbConfig }
        default { throw "Unsupported database type: $($DbConfig.type)" }
    }
}

# Εκτέλεση query και επιστροφή DataTable
function Invoke-DatabaseQuery {
    param(
        [System.Data.Common.DbConnection]$Connection,
        [string]$Query,
        [int]$Timeout = 300
    )
    
    $command = $Connection.CreateCommand()
    $command.CommandText = $Query
    $command.CommandTimeout = $Timeout
    
    $adapter = switch ($Connection.GetType().Name) {
        'MySqlConnection' { New-Object MySql.Data.MySqlClient.MySqlDataAdapter($command) }
        'NpgsqlConnection' { New-Object Npgsql.NpgsqlDataAdapter($command) }
    }
    
    $dataTable = New-Object System.Data.DataTable
    [void]$adapter.Fill($dataTable)
    
    # Επιστροφή με τρόπο που αποτρέπει το unwrapping από το PowerShell
    return ,$dataTable
}

# Εκτέλεση non-query command (INSERT, TRUNCATE, κλπ)
function Invoke-DatabaseNonQuery {
    param(
        [System.Data.Common.DbConnection]$Connection,
        [string]$Query,
        [int]$Timeout = 300
    )
    
    $command = $Connection.CreateCommand()
    $command.CommandText = $Query
    $command.CommandTimeout = $Timeout
    
    return $command.ExecuteNonQuery()
}

# Truncate πίνακα
function Clear-DestinationTable {
    param(
        [System.Data.Common.DbConnection]$Connection,
        [string]$TableName,
        [string]$DbType
    )
    
    Write-Log "Truncating table '$TableName'..."
    
    $query = switch ($DbType.ToLower()) {
        'mysql' { "TRUNCATE TABLE ``$TableName``" }
        'postgresql' { "TRUNCATE TABLE `"$TableName`" CASCADE" }
    }
    
    Invoke-DatabaseNonQuery -Connection $Connection -Query $query
}

# Αντιγραφή δεδομένων από έναν πίνακα σε άλλον
function Copy-TableData {
    param(
        [System.Data.Common.DbConnection]$SourceConnection,
        [System.Data.Common.DbConnection]$DestConnection,
        [string]$SourceTable,
        [string]$DestTable,
        [string]$DestDbType,
        [int]$BatchSize,
        [int]$Timeout
    )
    
    try {
        # Διάβασμα δεδομένων από source
        Write-Log "Reading data from '$SourceTable'..."
        $query = "SELECT * FROM $SourceTable"
        $sourceData = Invoke-DatabaseQuery -Connection $SourceConnection -Query $query -Timeout $Timeout
        
        $totalRows = $sourceData.Rows.Count
        Write-Log "Found $totalRows rows to copy"
        
        if ($totalRows -eq 0) {
            Write-Log "No data to copy" -Level WARNING
            return $true
        }
        
        # Δημιουργία INSERT statement template
        # Δημιουργία λίστας με τα ονόματα των στηλών  
        $columns = @()
        foreach ($column in $sourceData.Columns) {
            $columns += $column.ColumnName
        }
        
        $columnList = switch ($DestDbType.ToLower()) {
            'mysql' { ($columns | ForEach-Object { "``$_``" }) -join ", " }
            'postgresql' { ($columns | ForEach-Object { "`"$_`"" }) -join ", " }
        }
        
        $valuePlaceholders = switch ($DestDbType.ToLower()) {
            'mysql' { 
                ($columns | ForEach-Object { "@$_" }) -join ", "
            }
            'postgresql' { 
                ($columns | ForEach-Object { "@$_" }) -join ", "
            }
        }
        
        $insertTemplate = "INSERT INTO $DestTable ($columnList) VALUES ($valuePlaceholders)"
        
        # Αντιγραφή δεδομένων σε batches
        $copiedRows = 0
        for ($i = 0; $i -lt $totalRows; $i += $BatchSize) {
            $batchEnd = [Math]::Min($i + $BatchSize, $totalRows)
            $batchSize = $batchEnd - $i
            
            Write-Log "Copying rows $($i+1) to $batchEnd..."
            
            # Δημιουργία transaction για το batch
            $transaction = $DestConnection.BeginTransaction()
            
            try {
                for ($j = $i; $j -lt $batchEnd; $j++) {
                    $row = $sourceData.Rows[$j]
                    
                    $command = $DestConnection.CreateCommand()
                    $command.CommandText = $insertTemplate
                    $command.Transaction = $transaction
                    $command.CommandTimeout = $Timeout
                    
                    # Προσθήκη parameters
                    for ($k = 0; $k -lt $columns.Count; $k++) {
                        $columnName = $columns[$k]
                        $value = $row[$columnName]
                        
                        # Χειρισμός null και empty values
                        if ([DBNull]::Value.Equals($value) -or $null -eq $value) {
                            $value = [DBNull]::Value
                        }
                        elseif ($value -is [string] -and [string]::IsNullOrEmpty($value)) {
                            # Κενά strings μένουν κενά, δεν γίνονται null
                            $value = ""
                        }
                        
                        $param = $command.CreateParameter()
                        $param.ParameterName = "@$columnName"
                        $param.Value = $value
                        [void]$command.Parameters.Add($param)
                    }
                    
                    [void]$command.ExecuteNonQuery()
                }
                
                $transaction.Commit()
                $copiedRows += $batchSize
            }
            catch {
                $transaction.Rollback()
                throw "Batch insert failed: $($_.Exception.Message)"
            }
        }
        
        Write-Log "Successfully copied $copiedRows rows" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Failed to copy data: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

#endregion

#region Main Script

try {
    # Έλεγχος ύπαρξης config file
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    # Διάβασμα configuration
    Write-Host "`nLoading configuration from $ConfigPath..." -ForegroundColor Cyan
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    
    # Δημιουργία log directory
    $logDir = $config.Settings.LogFile
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    # Δημιουργία log file με timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:logFilePath = Join-Path $logDir "table-cloner_$timestamp.log"
    
    Write-Log "=== Table Cloner Script Started ==="
    Write-Log "Configuration loaded from: $ConfigPath"
    Write-Log "Source: $($config.DatabaseFrom.type) - $($config.DatabaseFrom.host):$($config.DatabaseFrom.port)/$($config.DatabaseFrom.database)"
    Write-Log "Destination: $($config.DatabaseTo.type) - $($config.DatabaseTo.host):$($config.DatabaseTo.port)/$($config.DatabaseTo.database)"
    Write-Log "Tables to copy: $($config.TableMappings.Count)"
    
    # Έλεγχος και φόρτωση required assemblies για PostgreSQL μόνο
    Write-Log "Loading PostgreSQL driver..."
    try {
        # Φόρτωση dependencies πρώτα
        if (Test-Path "lib\System.Runtime.CompilerServices.Unsafe.dll") {
            Add-Type -Path "lib\System.Runtime.CompilerServices.Unsafe.dll"
        }
        if (Test-Path "lib\System.Threading.Tasks.Extensions.dll") {
            Add-Type -Path "lib\System.Threading.Tasks.Extensions.dll"
        }
        # Μετά φόρτωση του Npgsql
        Add-Type -Path "lib\Npgsql.dll"
        Write-Log "PostgreSQL driver loaded successfully" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to load Npgsql.dll: $($_.Exception.Message)" -Level ERROR
        if ($_.Exception.LoaderExceptions) {
            Write-Log "Loader Exceptions:" -Level ERROR
            $_.Exception.LoaderExceptions | Select-Object -Unique | ForEach-Object {
                Write-Log "  - $($_.Message)" -Level ERROR
            }
        }
        throw
    }
    
    # Σύνδεση στις βάσεις δεδομένων
    Write-Log "Connecting to source database..."
    $sourceConn = Get-DatabaseConnection -DbConfig @{
        type = $config.DatabaseFrom.type
        host = $config.DatabaseFrom.host
        port = $config.DatabaseFrom.port
        database = $config.DatabaseFrom.database
        username = $config.DatabaseFrom.username
        password = $config.DatabaseFrom.password
    }
    Write-Log "Source connection established" -Level SUCCESS
    
    Write-Log "Connecting to destination database..."
    $destConn = Get-DatabaseConnection -DbConfig @{
        type = $config.DatabaseTo.type
        host = $config.DatabaseTo.host
        port = $config.DatabaseTo.port
        database = $config.DatabaseTo.database
        username = $config.DatabaseTo.username
        password = $config.DatabaseTo.password
    }
    Write-Log "Destination connection established" -Level SUCCESS
    
    # Αντιγραφή κάθε πίνακα
    $successCount = 0
    $failCount = 0
    
    foreach ($mapping in $config.TableMappings) {
        $sourceTable = $mapping.from
        $destTable = $mapping.to
        
        Write-Log "`n--- Processing: $sourceTable -> $destTable ---"
        
        try {
            # Truncate αν ζητείται
            if ($config.Settings.TruncateBeforeInsert) {
                Clear-DestinationTable -Connection $destConn -TableName $destTable -DbType $config.DatabaseTo.type
            }
            
            # Αντιγραφή δεδομένων
            $success = Copy-TableData `
                -SourceConnection $sourceConn `
                -DestConnection $destConn `
                -SourceTable $sourceTable `
                -DestTable $destTable `
                -DestDbType $config.DatabaseTo.type `
                -BatchSize $config.Settings.BatchSize `
                -Timeout $config.Settings.TimeoutSeconds
            
            if ($success) {
                Write-Log "Table '$sourceTable' -> '$destTable': SUCCESS" -Level SUCCESS
                $successCount++
            }
            else {
                Write-Log "Table '$sourceTable' -> '$destTable': FAILED" -Level ERROR
                $failCount++
            }
        }
        catch {
            Write-Log "Table '$sourceTable' -> '$destTable': ERROR - $($_.Exception.Message)" -Level ERROR
            $failCount++
        }
    }
    
    # Κλείσιμο συνδέσεων
    Write-Log "`nClosing connections..."
    $sourceConn.Close()
    $destConn.Close()
    
    # Σύνοψη
    Write-Log "`n=== Summary ==="
    Write-Log "Total tables: $($config.TableMappings.Count)"
    Write-Log "Successful: $successCount" -Level SUCCESS
    Write-Log "Failed: $failCount" $(if ($failCount -gt 0) { 'ERROR' } else { 'INFO' })
    Write-Log "=== Table Cloner Script Completed ==="
    Write-Log "Log file: $script:logFilePath"
    
    if ($failCount -gt 0) {
        exit 1
    }
}
catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
finally {
    # Cleanup connections αν υπάρχουν ακόμα
    if ($sourceConn -and $sourceConn.State -eq 'Open') {
        $sourceConn.Close()
    }
    if ($destConn -and $destConn.State -eq 'Open') {
        $destConn.Close()
    }
}

#endregion
