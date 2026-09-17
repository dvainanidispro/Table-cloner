#Requires -Version 5.1

<#
.SYNOPSIS
    Αντιγράφει δεδομένα από πίνακες μιας βάσης δεδομένων σε άλλη.
    
.DESCRIPTION
    Το script διαβάζει τις ρυθμίσεις από αρχείο JSON (προεπιλογή: env.json) και αντιγράφει δεδομένα
    από πίνακες/views της βάσης προέλευσης στη βάση προορισμού.
    Υποστηρίζει MySQL και PostgreSQL βάσεις.
    
.PARAMETER ConfigPath
    Το όνομα του αρχείου JSON στον ίδιο φάκελο με το script. Default: env.json

.EXAMPLE
    .\Table-Cloner.ps1 transfers.json

.EXAMPLE
    .\Table-Cloner.ps1 -ConfigPath transfers.json
#>

param(
    [Parameter(Position = 0)]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_) -or
            $_.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
            [System.IO.Path]::GetExtension($_) -ine '.json') {
            throw "Specify a JSON filename only (for example, transfers.json), without a path."
        }
        $true
    })]
    [string]$ConfigPath = "env.json"
)

# Πάντα δουλεύουμε paths relative στο folder του script (όχι στο current $PWD)
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# Το αρχείο JSON βρίσκεται πάντα στον ίδιο φάκελο με το script
$ConfigPath = Join-Path $scriptRoot $ConfigPath

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

# Εκτίμηση μεγέθους δεδομένων ενός DataTable (σε bytes)
function Get-DataTableSizeEstimate {
    param([System.Data.DataTable]$DataTable)
    
    [long]$totalBytes = 0
    foreach ($row in $DataTable.Rows) {
        foreach ($col in $DataTable.Columns) {
            $value = $row[$col]
            if ([DBNull]::Value.Equals($value) -or $null -eq $value) { continue }
            switch ($value.GetType().Name) {
                'String'   { $totalBytes += [System.Text.Encoding]::UTF8.GetByteCount($value) }
                'Byte[]'   { $totalBytes += $value.Length }
                'Int16'    { $totalBytes += 2 }
                'Int32'    { $totalBytes += 4 }
                'Int64'    { $totalBytes += 8 }
                'Single'   { $totalBytes += 4 }
                'Double'   { $totalBytes += 8 }
                'Decimal'  { $totalBytes += 16 }
                'Boolean'  { $totalBytes += 1 }
                'DateTime' { $totalBytes += 8 }
                'Byte'     { $totalBytes += 1 }
                default    { $totalBytes += 8 }
            }
        }
    }
    return $totalBytes
}

# Μορφοποίηση μεγέθους bytes για πιο καθαρά logs
function Format-ByteSize {
    param([double]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }

    return "{0:N0} B" -f $Bytes
}

# Υπολογίζει ένα προτεινόμενο εύρος BatchSize με βάση το μέσο μέγεθος γραμμής
function Get-BatchSizeRecommendation {
    param(
        [long]$TotalBytes,
        [int]$TotalRows,
        [int]$CurrentBatchSize,
        [int]$ColumnCount
    )

    if ($TotalRows -le 0) {
        return $null
    }

    [double]$avgRowBytes = [Math]::Max(($TotalBytes / [double]$TotalRows), 1)
    [long]$targetMinBatchBytes = 1MB
    [long]$targetMaxBatchBytes = 8MB

    $maxRowsByColumnCount = switch ($ColumnCount) {
        { $_ -le 10 } { 15000; break }
        { $_ -le 20 } { 10000; break }
        { $_ -le 40 } { 5000; break }
        default { 2000 }
    }

    $recommendedMinRows = [int][Math]::Ceiling($targetMinBatchBytes / $avgRowBytes)
    $recommendedMaxRows = [int][Math]::Floor($targetMaxBatchBytes / $avgRowBytes)

    $recommendedMinRows = [Math]::Min($recommendedMinRows, $maxRowsByColumnCount)
    $recommendedMinRows = [Math]::Max(1, [Math]::Min($recommendedMinRows, $TotalRows))
    $recommendedMaxRows = [Math]::Min($recommendedMaxRows, $maxRowsByColumnCount)
    $recommendedMaxRows = [Math]::Max($recommendedMinRows, [Math]::Min($recommendedMaxRows, $TotalRows))

    return [pscustomobject]@{
        AverageRowBytes = [long][Math]::Round($avgRowBytes)
        CurrentBatchBytes = [long][Math]::Round([Math]::Min($CurrentBatchSize, $TotalRows) * $avgRowBytes)
        RecommendedMinRows = $recommendedMinRows
        RecommendedMaxRows = $recommendedMaxRows
        TargetMinBatchBytes = $targetMinBatchBytes
        TargetMaxBatchBytes = $targetMaxBatchBytes
    }
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
        if ($BatchSize -le 0) {
            throw "BatchSize must be an integer greater than 0. Current value: $BatchSize"
        }

        # Διάβασμα δεδομένων από source
        Write-Log "Reading data from '$SourceTable'..."
        $query = "SELECT * FROM $SourceTable"
        $sourceData = Invoke-DatabaseQuery -Connection $SourceConnection -Query $query -Timeout $Timeout
        
        $totalRows = $sourceData.Rows.Count
        Write-Log "Found $totalRows rows to copy"

        # Δημιουργία λίστας με τα ονόματα των στηλών  
        $columns = @()
        foreach ($column in $sourceData.Columns) {
            $columns += $column.ColumnName
        }
        $colCount = $columns.Count
        
        if ($totalRows -gt 0) {
            $dataBytes = Get-DataTableSizeEstimate -DataTable $sourceData
            $dataSizeStr = Format-ByteSize -Bytes $dataBytes
            Write-Log "Estimated data size: $dataSizeStr"

            $batchRecommendation = Get-BatchSizeRecommendation -TotalBytes $dataBytes -TotalRows $totalRows -CurrentBatchSize $BatchSize -ColumnCount $colCount
            if ($batchRecommendation) {
                $currentBatchRows = [Math]::Min($BatchSize, $totalRows)
                $currentBatchSizeStr = Format-ByteSize -Bytes $batchRecommendation.CurrentBatchBytes
                $averageRowSizeStr = Format-ByteSize -Bytes $batchRecommendation.AverageRowBytes
                $targetBatchRangeStr = "$(Format-ByteSize -Bytes $batchRecommendation.TargetMinBatchBytes)-$(Format-ByteSize -Bytes $batchRecommendation.TargetMaxBatchBytes)"

                Write-Log "Current batch size: $($currentBatchRows.ToString('N0')) rows (~$currentBatchSizeStr per batch, avg row size ~$averageRowSizeStr)"
                Write-Log "Recommended batch size (heuristic): $($batchRecommendation.RecommendedMinRows.ToString('N0'))-$($batchRecommendation.RecommendedMaxRows.ToString('N0')) rows (target payload ~$targetBatchRangeStr)"
            }
        }
        
        if ($totalRows -eq 0) {
            Write-Log "No data to copy" -Level WARNING
            return $true
        }

        # Δημιουργία INSERT statement template
        $columnList = switch ($DestDbType.ToLower()) {
            'mysql' { ($columns | ForEach-Object { "``$_``" }) -join ", " }
            'postgresql' { ($columns | ForEach-Object { "`"$_`"" }) -join ", " }
        }
        $tableRef = switch ($DestDbType.ToLower()) {
            'mysql' { "``$DestTable``" }
            'postgresql' { "`"$DestTable`"" }
        }
        
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
                
                $command.CommandText = "INSERT INTO $tableRef ($columnList) VALUES $($valueTuples -join ', ')"
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
    $validateOnly = $config.Settings.ValidateOnly -eq $true
    
    # Δημιουργία log directory
    $logDir = [string]$config.Settings.LogFile
    if ([string]::IsNullOrWhiteSpace($logDir)) { $logDir = '.\logs' }
    if (-not [System.IO.Path]::IsPathRooted($logDir)) {
        $logDir = Join-Path $scriptRoot $logDir
    }
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    # Δημιουργία log file με timestamp
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logPrefix = 'table-cloner'
    if ($PSBoundParameters.ContainsKey('ConfigPath')) {
        $logPrefix += '_' + [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
    }
    $script:logFilePath = Join-Path $logDir "${logPrefix}_$timestamp.log"
    
    Write-Log "=== Table Cloner Script Started ==="
    Write-Log "Configuration loaded from: $ConfigPath"
    Write-Log "Source: $($config.DatabaseFrom.type) - $($config.DatabaseFrom.host):$($config.DatabaseFrom.port)/$($config.DatabaseFrom.database)"
    Write-Log "Destination: $($config.DatabaseTo.type) - $($config.DatabaseTo.host):$($config.DatabaseTo.port)/$($config.DatabaseTo.database)"
    if ($validateOnly) {
        Write-Log "ValidateOnly enabled: checking connections and source read access; TRUNCATE and copying are skipped."
        Write-Log "Tables to validate: $($config.TableMappings.Count)"
    }
    else {
        Write-Log "Tables to copy: $($config.TableMappings.Count)"
    }
    
    # Έλεγχος και φόρτωση required assemblies για MySQL
    if ($config.DatabaseFrom.type -eq 'mysql' -or $config.DatabaseTo.type -eq 'mysql') {
        Write-Log "Loading MySQL driver..."
        try {
            # Προσθήκη Assembly Resolve handler για να redirect παλιές εκδόσεις
            $onAssemblyResolve = [System.ResolveEventHandler] {
                param($eventSender, $e)
                
                # Αν ζητάει System.Threading.Tasks.Extensions, redirect στην έκδοση που έχουμε
                if ($e.Name -like "System.Threading.Tasks.Extensions*") {
                    $tasksExtPath = Resolve-Path (Join-Path $scriptRoot "lib\System.Threading.Tasks.Extensions.dll")
                    return [System.Reflection.Assembly]::LoadFile($tasksExtPath.Path)
                }
                return $null
            }
            
            [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)
            
            # Φόρτωση dependencies πρώτα με LoadFile για να αποφύγουμε dependency issues
            if (Test-Path (Join-Path $scriptRoot "lib\System.Threading.Tasks.Extensions.dll")) {
                [System.Reflection.Assembly]::LoadFile((Resolve-Path (Join-Path $scriptRoot "lib\System.Threading.Tasks.Extensions.dll")).Path) | Out-Null
            }
            if (Test-Path (Join-Path $scriptRoot "lib\Google.Protobuf.dll")) {
                [System.Reflection.Assembly]::LoadFile((Resolve-Path (Join-Path $scriptRoot "lib\Google.Protobuf.dll")).Path) | Out-Null
            }
            if (Test-Path (Join-Path $scriptRoot "lib\K4os.Compression.LZ4.Streams.dll")) {
                [System.Reflection.Assembly]::LoadFile((Resolve-Path (Join-Path $scriptRoot "lib\K4os.Compression.LZ4.Streams.dll")).Path) | Out-Null
            }
            if (Test-Path (Join-Path $scriptRoot "lib\BouncyCastle.Cryptography.dll")) {
                [System.Reflection.Assembly]::LoadFile((Resolve-Path (Join-Path $scriptRoot "lib\BouncyCastle.Cryptography.dll")).Path) | Out-Null
            }
            if (Test-Path (Join-Path $scriptRoot "lib\System.Memory.dll")) {
                [System.Reflection.Assembly]::LoadFile((Resolve-Path (Join-Path $scriptRoot "lib\System.Memory.dll")).Path) | Out-Null
            }
            # Τέλος φόρτωση του MySQL.Data
            [System.Reflection.Assembly]::LoadFile((Resolve-Path (Join-Path $scriptRoot "lib\MySql.Data.dll")).Path) | Out-Null
        }
        catch {
            Write-Log "Failed to load MySQL.Data.dll. Please ensure the driver is available." -Level ERROR
            throw
        }
    }
    
    # Έλεγχος και φόρτωση required assemblies για PostgreSQL
    if ($config.DatabaseFrom.type -eq 'postgresql' -or $config.DatabaseTo.type -eq 'postgresql') {
        Write-Log "Loading PostgreSQL driver..."
        try {
            # Φόρτωση dependencies πρώτα
            if (Test-Path (Join-Path $scriptRoot "lib\System.Runtime.CompilerServices.Unsafe.dll")) {
                Add-Type -Path (Join-Path $scriptRoot "lib\System.Runtime.CompilerServices.Unsafe.dll") -ErrorAction Stop
            }
            if (Test-Path (Join-Path $scriptRoot "lib\System.Threading.Tasks.Extensions.dll")) {
                Add-Type -Path (Join-Path $scriptRoot "lib\System.Threading.Tasks.Extensions.dll") -ErrorAction Stop
            }
            # Μετά φόρτωση του Npgsql
            Add-Type -Path (Join-Path $scriptRoot "lib\Npgsql.dll") -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to load Npgsql.dll. Please ensure the driver is available." -Level ERROR
            throw
        }
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

        # Preflight check: έλεγχος πρόσβασης στον πίνακα προέλευσης πριν αγγίξουμε τον προορισμό
        Write-Log "Preflight check: verifying read access on '$sourceTable'..."
        try {
            $preflightQuery = "SELECT 1 FROM $sourceTable LIMIT 1"
            Invoke-DatabaseQuery -Connection $sourceConn -Query $preflightQuery -Timeout $config.Settings.TimeoutSeconds | Out-Null
            Write-Log "Preflight check passed" -Level SUCCESS
        }
        catch {
            Write-Log "Preflight check FAILED for '$sourceTable': $($_.Exception.Message)" -Level ERROR
            Write-Log "Skipping '$sourceTable' -> '$destTable' (destination untouched)" -Level WARNING
            $failCount++
            continue
        }

        if ($validateOnly) {
            Write-Log "Table '$sourceTable' -> '$destTable': VALIDATED (copy skipped)" -Level SUCCESS
            $successCount++
            continue
        }

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

# Αναμονή 3 δευτερολέπτων πριν κλείσει το παράθυρο
Start-Sleep -Seconds 3

#endregion
