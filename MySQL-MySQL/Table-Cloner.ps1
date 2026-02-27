#Requires -Version 5.1

<#
.SYNOPSIS
    Αντιγράφει δεδομένα από πίνακες μιας βάσης δεδομένων σε άλλη.
    
.DESCRIPTION
    Το script διαβάζει τις ρυθμίσεις από το env.json και αντιγράφει δεδομένα
    από πίνακες/views της βάσης προέλευσης στη βάση προορισμού.
    Υποστηρίζει μόνο MySQL βάσεις.
    
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

# Δημιουργία connection ανάλογα με τον τύπο της βάσης
function Get-DatabaseConnection {
    param(
        [hashtable]$DbConfig
    )
    
    if ($DbConfig.type.ToLower() -ne 'mysql') {
        throw "Unsupported database type: $($DbConfig.type). Only MySQL is supported."
    }
    
    return Get-MySqlConnection -DbConfig $DbConfig
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
    
    $adapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($command)
    
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
        [string]$TableName
    )
    
    Write-Log "Truncating table '$TableName'..."
    
    $query = "TRUNCATE TABLE ``$TableName``"
    
    Invoke-DatabaseNonQuery -Connection $Connection -Query $query
}

# Αντιγραφή δεδομένων από έναν πίνακα σε άλλον
function Copy-TableData {
    param(
        [System.Data.Common.DbConnection]$SourceConnection,
        [System.Data.Common.DbConnection]$DestConnection,
        [string]$SourceTable,
        [string]$DestTable,
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
        
        $columnList = ($columns | ForEach-Object { "``$_``" }) -join ", "
        $valuePlaceholders = ($columns | ForEach-Object { "@$_" }) -join ", "
        
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
    
    # Φόρτωση MySQL driver
    Write-Log "Loading MySQL driver..."
    try {
        # Προσθήκη Assembly Resolve handler για να redirect παλιές εκδόσεις
        $onAssemblyResolve = [System.ResolveEventHandler] {
            param($eventSender, $e)
            
            # Αν ζητάει System.Threading.Tasks.Extensions, redirect στην έκδοση που έχουμε
            if ($e.Name -like "System.Threading.Tasks.Extensions*") {
                if (Test-Path "lib\System.Threading.Tasks.Extensions.dll") {
                    $tasksExtPath = Resolve-Path "lib\System.Threading.Tasks.Extensions.dll"
                    return [System.Reflection.Assembly]::LoadFile($tasksExtPath.Path)
                }
            }
            # Αν ζητάει System.Runtime.CompilerServices.Unsafe, redirect στην έκδοση που έχουμε
            if ($e.Name -like "System.Runtime.CompilerServices.Unsafe*") {
                if (Test-Path "lib\System.Runtime.CompilerServices.Unsafe.dll") {
                    $unsafePath = Resolve-Path "lib\System.Runtime.CompilerServices.Unsafe.dll"
                    return [System.Reflection.Assembly]::LoadFile($unsafePath.Path)
                }
            }
            return $null
        }
        
        [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)
        
        # Φόρτωση dependencies πρώτα με LoadFile για να αποφύγουμε dependency issues
        if (Test-Path "lib\System.Runtime.CompilerServices.Unsafe.dll") {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path "lib\System.Runtime.CompilerServices.Unsafe.dll").Path) | Out-Null
        }
        if (Test-Path "lib\System.Threading.Tasks.Extensions.dll") {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path "lib\System.Threading.Tasks.Extensions.dll").Path) | Out-Null
        }
        if (Test-Path "lib\System.Memory.dll") {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path "lib\System.Memory.dll").Path) | Out-Null
        }
        if (Test-Path "lib\Google.Protobuf.dll") {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path "lib\Google.Protobuf.dll").Path) | Out-Null
        }
        if (Test-Path "lib\K4os.Compression.LZ4.Streams.dll") {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path "lib\K4os.Compression.LZ4.Streams.dll").Path) | Out-Null
        }
        if (Test-Path "lib\BouncyCastle.Cryptography.dll") {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path "lib\BouncyCastle.Cryptography.dll").Path) | Out-Null
        }
        # Τέλος φόρτωση του MySQL.Data
        [System.Reflection.Assembly]::LoadFile((Resolve-Path "lib\MySql.Data.dll").Path) | Out-Null
    }
    catch {
        Write-Log "Failed to load MySQL.Data.dll. Please ensure the driver is available." -Level ERROR
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
                Clear-DestinationTable -Connection $destConn -TableName $destTable
            }
            
            # Αντιγραφή δεδομένων
            $success = Copy-TableData `
                -SourceConnection $sourceConn `
                -DestConnection $destConn `
                -SourceTable $sourceTable `
                -DestTable $destTable `
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

# Αναμονή 3 δευτερολέπτων πριν κλείσει το παράθυρο
Start-Sleep -Seconds 3

#endregion
