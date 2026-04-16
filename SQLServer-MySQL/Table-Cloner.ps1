#Requires -Version 5.1

<#
.SYNOPSIS
    Αντιγράφει δεδομένα από πίνακες μιας βάσης δεδομένων σε άλλη.
    
.DESCRIPTION
    Το script διαβάζει τις ρυθμίσεις από το env.json και αντιγράφει δεδομένα
    από πίνακες/views της βάσης προέλευσης στη βάση προορισμού.
    Υποστηρίζει SQL Server (πηγή) και MySQL (προορισμός).
    Ο SQL Server μπορεί να χρησιμοποιεί Windows Authentication (χωρίς username/password).
    
.PARAMETER ConfigPath
    Η διαδρομή του αρχείου env.json. Default: .\env.json
#>

param(
    [string]$ConfigPath = ".\env.json"
)

# Πάντα δουλεύουμε paths relative στο folder του script (όχι στο current $PWD)
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# Αν δοθεί σχετικό path για config, το θεωρούμε relative στο folder του script
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $scriptRoot $ConfigPath
}

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

# Δημιουργία SQL Server connection
function Get-SqlServerConnection {
    param(
        [hashtable]$DbConfig
    )
    
    try {
        # Δημιουργία connection string
        # Αν host περιέχει backslash (named instance π.χ. .\SQLEXPRESS), δεν χρησιμοποιούμε port
        if ($DbConfig.host -match '\\') {
            $serverPart = $DbConfig.host
        }
        else {
            $serverPart = "$($DbConfig.host),$($DbConfig.port)"
        }
        
        # Αν username/password είναι κενά, χρησιμοποιούμε Windows Authentication
        if ([string]::IsNullOrWhiteSpace($DbConfig.username)) {
            $connectionString = "Server=$serverPart;Database=$($DbConfig.database);Integrated Security=True;TrustServerCertificate=True;"
        }
        else {
            $connectionString = "Server=$serverPart;Database=$($DbConfig.database);User ID=$($DbConfig.username);Password=$($DbConfig.password);TrustServerCertificate=True;"
        }
        
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
        
        return $connection
    }
    catch {
        throw "SQL Server Connection Error: $($_.Exception.Message)"
    }
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
    
    switch ($DbConfig.type.ToLower()) {
        'sqlserver' { return Get-SqlServerConnection -DbConfig $DbConfig }
        'mysql' { return Get-MySqlConnection -DbConfig $DbConfig }
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
        'SqlConnection' { New-Object System.Data.SqlClient.SqlDataAdapter($command) }
        'MySqlConnection' { New-Object MySql.Data.MySqlClient.MySqlDataAdapter($command) }
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

# Truncate πίνακα (πάντα MySQL destination)
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
        if ($BatchSize -le 0) {
            throw "BatchSize must be an integer greater than 0. Current value: $BatchSize"
        }

        # Διάβασμα δεδομένων από source (SQL Server)
        # Το SourceTable μπορεί να είναι σε μορφή [schema].[table] ή [db].[schema].[table]
        Write-Log "Reading data from '$SourceTable'..."
        $query = "SET NOCOUNT ON; SELECT * FROM $SourceTable"
        $sourceData = Invoke-DatabaseQuery -Connection $SourceConnection -Query $query -Timeout $Timeout
        
        $totalRows = $sourceData.Rows.Count
        Write-Log "Found $totalRows rows to copy"
        
        if ($totalRows -eq 0) {
            Write-Log "No data to copy" -Level WARNING
            return $true
        }
        
        # Δημιουργία λίστας με τα ονόματα των στηλών
        $columns = @()
        foreach ($column in $sourceData.Columns) {
            $columns += $column.ColumnName
        }
        
        # MySQL destination: χρήση backtick quoting
        $columnList = ($columns | ForEach-Object { "``$_``" }) -join ", "
        $colCount = $columns.Count
        
        # Αντιγραφή δεδομένων σε batches — ένα multi-row INSERT ανά batch
        $copiedRows = 0
        for ($i = 0; $i -lt $totalRows; $i += $BatchSize) {
            $batchEnd = [Math]::Min($i + $BatchSize, $totalRows)
            $batchCount = $batchEnd - $i
            
            Write-Log "Copying rows $($i+1) to $batchEnd..."
            
            $transaction = $DestConnection.BeginTransaction()
            
            try {
                $command = $DestConnection.CreateCommand()
                $command.Transaction = $transaction
                $command.CommandTimeout = $Timeout
                
                # Χτίζουμε ένα INSERT ... VALUES (row0), (row1), ... για όλο το batch
                $valueTuples = [System.Collections.Generic.List[string]]::new()
                
                for ($j = $i; $j -lt $batchEnd; $j++) {
                    $rowIndex = $j - $i
                    $row = $sourceData.Rows[$j]
                    
                    $placeholders = [System.Collections.Generic.List[string]]::new()
                    for ($k = 0; $k -lt $colCount; $k++) {
                        $paramName = "@p${k}_${rowIndex}"
                        [void]$placeholders.Add($paramName)
                        
                        $value = $row[$columns[$k]]
                        if ([DBNull]::Value.Equals($value) -or $null -eq $value) {
                            $value = [DBNull]::Value
                        }
                        
                        $param = $command.CreateParameter()
                        $param.ParameterName = $paramName
                        $param.Value = $value
                        [void]$command.Parameters.Add($param)
                    }
                    
                    [void]$valueTuples.Add("($($placeholders -join ', '))")
                }
                
                $command.CommandText = "INSERT INTO ``$DestTable`` ($columnList) VALUES $($valueTuples -join ', ')"
                [void]$command.ExecuteNonQuery()
                
                $transaction.Commit()
                $copiedRows += $batchCount
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
    $logDirRaw = [string]$config.Settings.LogFile
    if ([string]::IsNullOrWhiteSpace($logDirRaw)) {
        $logDirRaw = ".\\logs"
    }

    # Αν είναι σχετικό, το κάνουμε relative στο folder του script.
    $logDir = if ([System.IO.Path]::IsPathRooted($logDirRaw)) { $logDirRaw } else { Join-Path $scriptRoot $logDirRaw }

    # Guard: δεν επιτρέπουμε log directory εκτός του folder του script
        $scriptRootFull = [System.IO.Path]::GetFullPath($scriptRoot).TrimEnd('\') + '\'
        $logDirFull = [System.IO.Path]::GetFullPath($logDir)
        $logDirFullNorm = $logDirFull.TrimEnd('\') + '\'
        if (-not $logDirFullNorm.StartsWith($scriptRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to write logs outside script folder. LogFile='$logDirRaw' resolved to '$logDirFull'."
        }

    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    # Δημιουργία log file με timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:logFilePath = Join-Path $logDir "table-cloner_$timestamp.log"
    
    Write-Log "=== Table Cloner Script Started ==="
    Write-Log "Configuration loaded from: $ConfigPath"
    
    # Εμφάνιση source info (SQL Server)
    $authMode = if ([string]::IsNullOrWhiteSpace($config.DatabaseFrom.username)) { "Windows Auth" } else { "SQL Server Auth" }
    Write-Log "Source: $($config.DatabaseFrom.type) - $($config.DatabaseFrom.host)/$($config.DatabaseFrom.database) ($authMode)"
    Write-Log "Destination: $($config.DatabaseTo.type) - $($config.DatabaseTo.host):$($config.DatabaseTo.port)/$($config.DatabaseTo.database)"
    Write-Log "Tables to copy: $($config.TableMappings.Count)"
    
    # Φόρτωση MySQL driver (για τον destination)
    Write-Log "Loading MySQL driver..."
    try {
        # Προσθήκη Assembly Resolve handler για να redirect παλιές εκδόσεις
        $onAssemblyResolve = [System.ResolveEventHandler] {
            param($eventSender, $e)
            
            # Αν ζητάει System.Threading.Tasks.Extensions, redirect στην έκδοση που έχουμε
            if ($e.Name -like "System.Threading.Tasks.Extensions*") {
                $tasksExtCandidate = Join-Path $scriptRoot "lib\System.Threading.Tasks.Extensions.dll"
                if (Test-Path -LiteralPath $tasksExtCandidate) {
                    $tasksExtPath = Resolve-Path -LiteralPath $tasksExtCandidate
                    return [System.Reflection.Assembly]::LoadFile($tasksExtPath.Path)
                }
            }
            # Αν ζητάει System.Runtime.CompilerServices.Unsafe, redirect στην έκδοση που έχουμε
            if ($e.Name -like "System.Runtime.CompilerServices.Unsafe*") {
                $unsafeCandidate = Join-Path $scriptRoot "lib\System.Runtime.CompilerServices.Unsafe.dll"
                if (Test-Path -LiteralPath $unsafeCandidate) {
                    $unsafePath = Resolve-Path -LiteralPath $unsafeCandidate
                    return [System.Reflection.Assembly]::LoadFile($unsafePath.Path)
                }
            }
            return $null
        }
        
        [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)
        
        # Φόρτωση dependencies πρώτα με LoadFile για να αποφύγουμε dependency issues
        $unsafeDllPath = Join-Path $scriptRoot "lib\System.Runtime.CompilerServices.Unsafe.dll"
        $tasksExtDllPath = Join-Path $scriptRoot "lib\System.Threading.Tasks.Extensions.dll"
        $memoryDllPath = Join-Path $scriptRoot "lib\System.Memory.dll"
        $protobufDllPath = Join-Path $scriptRoot "lib\Google.Protobuf.dll"
        $lz4DllPath = Join-Path $scriptRoot "lib\K4os.Compression.LZ4.Streams.dll"
        $bouncyDllPath = Join-Path $scriptRoot "lib\BouncyCastle.Cryptography.dll"
        $mysqlDllPath = Join-Path $scriptRoot "lib\MySql.Data.dll"

        if (Test-Path -LiteralPath $unsafeDllPath) {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $unsafeDllPath).Path) | Out-Null
        }
        if (Test-Path -LiteralPath $tasksExtDllPath) {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $tasksExtDllPath).Path) | Out-Null
        }
        if (Test-Path -LiteralPath $memoryDllPath) {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $memoryDllPath).Path) | Out-Null
        }
        if (Test-Path -LiteralPath $protobufDllPath) {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $protobufDllPath).Path) | Out-Null
        }
        if (Test-Path -LiteralPath $lz4DllPath) {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $lz4DllPath).Path) | Out-Null
        }
        if (Test-Path -LiteralPath $bouncyDllPath) {
            [System.Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $bouncyDllPath).Path) | Out-Null
        }
        # Τέλος φόρτωση του MySQL.Data
        [System.Reflection.Assembly]::LoadFile((Resolve-Path -LiteralPath $mysqlDllPath).Path) | Out-Null
    }
    catch {
        Write-Log "Failed to load MySQL.Data.dll. Run Install-Drivers.ps1 first." -Level ERROR
        throw
    }
    
    # Ο SQL Server driver (System.Data.SqlClient) είναι ενσωματωμένος στο .NET Framework
    # Δεν χρειάζεται επιπλέον φόρτωση
    
    # Σύνδεση στις βάσεις δεδομένων
    Write-Log "Connecting to source database (SQL Server)..."
    $sourceConn = Get-DatabaseConnection -DbConfig @{
        type = $config.DatabaseFrom.type
        host = $config.DatabaseFrom.host
        port = $config.DatabaseFrom.port
        database = $config.DatabaseFrom.database
        username = $config.DatabaseFrom.username
        password = $config.DatabaseFrom.password
    }
    Write-Log "Source connection established" -Level SUCCESS
    
    Write-Log "Connecting to destination database (MySQL)..."
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

        # Preflight check: έλεγχος πρόσβασης στον πίνακα προέλευσης πριν αγγίξουμε τον προορισμό
        Write-Log "Preflight check: verifying read access on '$sourceTable'..."
        try {
            $preflightQuery = "SET NOCOUNT ON; SELECT TOP 1 1 AS preflight_check FROM $sourceTable"
            Invoke-DatabaseQuery -Connection $sourceConn -Query $preflightQuery -Timeout $config.Settings.TimeoutSeconds | Out-Null
            Write-Log "Preflight check passed" -Level SUCCESS
        }
        catch {
            Write-Log "Preflight check FAILED for '$sourceTable': $($_.Exception.Message)" -Level ERROR
            Write-Log "Skipping '$sourceTable' -> '$destTable' (destination untouched)" -Level WARNING
            $failCount++
            continue
        }

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
