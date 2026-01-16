#Requires -Version 5.1

<#
.SYNOPSIS
    Κατεβάζει τα απαραίτητα database drivers για το Table-Cloner script.
    
.DESCRIPTION
    Το script κατεβάζει τα MySql.Data.dll και Npgsql.dll από NuGet
    και τα τοποθετεί στον τρέχοντα φάκελο.
#>

Write-Host "`n=== Table Cloner - Driver Installation ===" -ForegroundColor Cyan
Write-Host "This script will download both MySQL and PostgreSQL drivers.`n" -ForegroundColor White
# Δημιουργία φακέλου lib αν δεν υπάρχει
$libDir = Join-Path $PWD "lib"
if (-not (Test-Path $libDir)) {
    New-Item -Path $libDir -ItemType Directory -Force | Out-Null
    Write-Host "Created lib directory" -ForegroundColor Green
}
# URLs για τα NuGet packages
# Χρησιμοποιούμε εκδόσεις συμβατές με .NET Framework 4.8
$mysqlPackageUrl = "https://www.nuget.org/api/v2/package/MySql.Data/8.0.33"
$npgsqlPackageUrl = "https://www.nuget.org/api/v2/package/Npgsql/3.2.7"

# MySQL Dependencies
$googleProtobufUrl = "https://www.nuget.org/api/v2/package/Google.Protobuf/3.21.9"
$lz4StreamsUrl = "https://www.nuget.org/api/v2/package/K4os.Compression.LZ4.Streams/1.3.5"
$bouncyCastleUrl = "https://www.nuget.org/api/v2/package/BouncyCastle.Cryptography/2.2.1"
$systemMemoryUrl = "https://www.nuget.org/api/v2/package/System.Memory/4.5.5"
$unsafeUrl = "https://www.nuget.org/api/v2/package/System.Runtime.CompilerServices.Unsafe/4.5.3"

# Temp directory
$tempDir = Join-Path $PWD "temp_drivers"

try {
    # Δημιουργία temp directory
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    
    # Κατέβασμα MySQL Driver
    Write-Host "[1/16] Downloading MySQL.Data driver..." -ForegroundColor Yellow
    $mysqlZip = Join-Path $tempDir "MySql.Data.zip"
    Invoke-WebRequest -Uri $mysqlPackageUrl -OutFile $mysqlZip -UseBasicParsing
    Write-Host "      Downloaded successfully" -ForegroundColor Green
    
    # Εξαγωγή MySQL DLL
    Write-Host "[2/16] Extracting MySql.Data.dll..." -ForegroundColor Yellow
    $mysqlExtract = Join-Path $tempDir "mysql_extract"
    Expand-Archive -Path $mysqlZip -DestinationPath $mysqlExtract -Force
    
    # Αναζήτηση του DLL για .NET Framework 4.8
    $mysqlDll = Get-ChildItem -Path $mysqlExtract -Filter "MySql.Data.dll" -Recurse | 
                Where-Object { $_.FullName -match "net(4[0-9]{2}|48)" } | 
                Sort-Object { $_.Directory.Name } -Descending | 
                Select-Object -First 1
    
    if ($mysqlDll) {
        Copy-Item $mysqlDll.FullName -Destination (Join-Path $libDir "MySql.Data.dll") -Force
        Write-Host "      MySql.Data.dll installed successfully" -ForegroundColor Green
    } else {
        throw "Could not find MySql.Data.dll in package"
    }
    
    # Κατέβασμα MySQL Dependencies
    Write-Host "[3/16] Downloading Google.Protobuf..." -ForegroundColor Yellow
    $protobufZip = Join-Path $tempDir "Google.Protobuf.zip"
    Invoke-WebRequest -Uri $googleProtobufUrl -OutFile $protobufZip -UseBasicParsing
    
    Write-Host "[4/16] Extracting Google.Protobuf.dll..." -ForegroundColor Yellow
    $protobufExtract = Join-Path $tempDir "protobuf_extract"
    Expand-Archive -Path $protobufZip -DestinationPath $protobufExtract -Force
    $protobufDll = Get-ChildItem -Path $protobufExtract -Filter "Google.Protobuf.dll" -Recurse | 
                   Where-Object { $_.FullName -match "net(4[0-9]{2}|standard)" } | 
                   Sort-Object { $_.Directory.Name } -Descending | Select-Object -First 1
    if ($protobufDll) {
        Copy-Item $protobufDll.FullName -Destination (Join-Path $libDir "Google.Protobuf.dll") -Force
        Write-Host "      Google.Protobuf.dll installed successfully" -ForegroundColor Green
    }
    
    Write-Host "[5/16] Downloading K4os.Compression.LZ4.Streams..." -ForegroundColor Yellow
    $lz4Zip = Join-Path $tempDir "K4os.Compression.LZ4.Streams.zip"
    Invoke-WebRequest -Uri $lz4StreamsUrl -OutFile $lz4Zip -UseBasicParsing
    
    Write-Host "[6/16] Extracting K4os.Compression.LZ4.Streams.dll..." -ForegroundColor Yellow
    $lz4Extract = Join-Path $tempDir "lz4_extract"
    Expand-Archive -Path $lz4Zip -DestinationPath $lz4Extract -Force
    $lz4Dll = Get-ChildItem -Path $lz4Extract -Filter "K4os.Compression.LZ4.Streams.dll" -Recurse | 
              Where-Object { $_.FullName -match "net(4[0-9]{2}|standard)" } | 
              Sort-Object { $_.Directory.Name } -Descending | Select-Object -First 1
    if ($lz4Dll) {
        Copy-Item $lz4Dll.FullName -Destination (Join-Path $libDir "K4os.Compression.LZ4.Streams.dll") -Force
        Write-Host "      K4os.Compression.LZ4.Streams.dll installed successfully" -ForegroundColor Green
    }
    
    Write-Host "[7/16] Downloading BouncyCastle.Cryptography..." -ForegroundColor Yellow
    $bouncyZip = Join-Path $tempDir "BouncyCastle.Cryptography.zip"
    Invoke-WebRequest -Uri $bouncyCastleUrl -OutFile $bouncyZip -UseBasicParsing
    
    Write-Host "[8/16] Extracting BouncyCastle.Cryptography.dll..." -ForegroundColor Yellow
    $bouncyExtract = Join-Path $tempDir "bouncy_extract"
    Expand-Archive -Path $bouncyZip -DestinationPath $bouncyExtract -Force
    $bouncyDll = Get-ChildItem -Path $bouncyExtract -Filter "BouncyCastle.Cryptography.dll" -Recurse | 
                 Where-Object { $_.FullName -match "net(4[0-9]{2}|standard)" } | 
                 Sort-Object { $_.Directory.Name } -Descending | Select-Object -First 1
    if ($bouncyDll) {
        Copy-Item $bouncyDll.FullName -Destination (Join-Path $libDir "BouncyCastle.Cryptography.dll") -Force
        Write-Host "      BouncyCastle.Cryptography.dll installed successfully" -ForegroundColor Green
    }
    
    Write-Host "[9/16] Downloading System.Memory..." -ForegroundColor Yellow
    $memoryZip = Join-Path $tempDir "System.Memory.zip"
    Invoke-WebRequest -Uri $systemMemoryUrl -OutFile $memoryZip -UseBasicParsing
    
    Write-Host "[10/16] Extracting System.Memory.dll..." -ForegroundColor Yellow
    $memoryExtract = Join-Path $tempDir "memory_extract"
    Expand-Archive -Path $memoryZip -DestinationPath $memoryExtract -Force
    $memoryDll = Get-ChildItem -Path $memoryExtract -Filter "System.Memory.dll" -Recurse | 
                 Where-Object { $_.FullName -match "net(4[0-9]{2}|standard)" } | 
                 Sort-Object { $_.Directory.Name } -Descending | Select-Object -First 1
    if ($memoryDll) {
        Copy-Item $memoryDll.FullName -Destination (Join-Path $libDir "System.Memory.dll") -Force
        Write-Host "      System.Memory.dll installed successfully" -ForegroundColor Green
    }
    
    Write-Host "[11/16] Downloading System.Runtime.CompilerServices.Unsafe..." -ForegroundColor Yellow
    $unsafeZip = Join-Path $tempDir "System.Runtime.CompilerServices.Unsafe.zip"
    Invoke-WebRequest -Uri $unsafeUrl -OutFile $unsafeZip -UseBasicParsing
    
    Write-Host "[12/16] Extracting System.Runtime.CompilerServices.Unsafe.dll..." -ForegroundColor Yellow
    $unsafeExtract = Join-Path $tempDir "unsafe_extract"
    Expand-Archive -Path $unsafeZip -DestinationPath $unsafeExtract -Force
    # Πρέπει να πάρουμε το implementation assembly από lib\net461, όχι από ref\ ή netstandard
    $unsafeDll = Get-ChildItem -Path $unsafeExtract -Filter "System.Runtime.CompilerServices.Unsafe.dll" -Recurse | 
                 Where-Object { $_.FullName -match "\\lib\\net(4[0-9]{2})" -and $_.FullName -notmatch "\\ref\\" } | 
                 Sort-Object { $_.Directory.Name } -Descending | Select-Object -First 1
    if ($unsafeDll) {
        Copy-Item $unsafeDll.FullName -Destination (Join-Path $libDir "System.Runtime.CompilerServices.Unsafe.dll") -Force
        Write-Host "      System.Runtime.CompilerServices.Unsafe.dll installed successfully" -ForegroundColor Green
    }
    
    # Κατέβασμα PostgreSQL Driver
    Write-Host "[13/16] Downloading Npgsql driver..." -ForegroundColor Yellow
    $npgsqlZip = Join-Path $tempDir "Npgsql.zip"
    Invoke-WebRequest -Uri $npgsqlPackageUrl -OutFile $npgsqlZip -UseBasicParsing
    Write-Host "      Downloaded successfully" -ForegroundColor Green
    
    # Εξαγωγή Npgsql DLL
    Write-Host "[14/16] Extracting Npgsql.dll..." -ForegroundColor Yellow
    $npgsqlExtract = Join-Path $tempDir "npgsql_extract"
    Expand-Archive -Path $npgsqlZip -DestinationPath $npgsqlExtract -Force
    
    # Αναζήτηση του DLL για .NET Framework 4.8
    $npgsqlDll = Get-ChildItem -Path $npgsqlExtract -Filter "Npgsql.dll" -Recurse | 
                 Where-Object { $_.FullName -match "net(4[0-9]{2}|48)" } | 
                 Sort-Object { $_.Directory.Name } -Descending | 
                 Select-Object -First 1
    
    if ($npgsqlDll) {
        Copy-Item $npgsqlDll.FullName -Destination (Join-Path $libDir "Npgsql.dll") -Force
        Write-Host "      Npgsql.dll installed successfully" -ForegroundColor Green
    } else {
        throw "Could not find Npgsql.dll in package"
    }
    
    # Κατέβασμα Npgsql dependency: System.Threading.Tasks.Extensions
    Write-Host "[15/16] Downloading System.Threading.Tasks.Extensions..." -ForegroundColor Yellow
    # Κατεβάζουμε την 4.5.4 που έχει και τις παλιότερες εκδόσεις μέσα
    $tasksExtUrl = "https://www.nuget.org/api/v2/package/System.Threading.Tasks.Extensions/4.5.4"
    $tasksExtZip = Join-Path $tempDir "System.Threading.Tasks.Extensions.zip"
    Invoke-WebRequest -Uri $tasksExtUrl -OutFile $tasksExtZip -UseBasicParsing
    
    Write-Host "[16/16] Extracting System.Threading.Tasks.Extensions.dll..." -ForegroundColor Yellow
    $tasksExtExtract = Join-Path $tempDir "tasksext_extract"
    Expand-Archive -Path $tasksExtZip -DestinationPath $tasksExtExtract -Force
    
    $tasksExtDll = Get-ChildItem -Path $tasksExtExtract -Filter "System.Threading.Tasks.Extensions.dll" -Recurse | 
                   Where-Object { $_.FullName -match "net(4[0-9]{2}|standard)" } | 
                   Sort-Object { $_.Directory.Name } -Descending |
                   Select-Object -First 1
    
    if ($tasksExtDll) {
        Copy-Item $tasksExtDll.FullName -Destination (Join-Path $libDir "System.Threading.Tasks.Extensions.dll") -Force
        Write-Host "      System.Threading.Tasks.Extensions.dll installed successfully" -ForegroundColor Green
    } else {
        throw "Could not find System.Threading.Tasks.Extensions.dll in package"
    }
    
    # Καθαρισμός
    Write-Host "`nCleaning up temporary files..." -ForegroundColor Yellow
    Remove-Item $tempDir -Recurse -Force
    
    Write-Host "`n=== Installation Completed Successfully ===" -ForegroundColor Green
    Write-Host "\nInstalled drivers in lib/ directory:" -ForegroundColor White
    Write-Host "  - MySql.Data.dll (with dependencies)" -ForegroundColor Cyan
    Write-Host "  - Npgsql.dll (with dependencies)" -ForegroundColor Cyan
    Write-Host "`nNote: The Table-Cloner script will only load the driver(s) it needs." -ForegroundColor Yellow
    Write-Host "      You can delete any DLL you don't need if you want." -ForegroundColor Yellow
    Write-Host "`nYou can now run Table-Cloner.ps1" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host "`n=== Installation Failed ===" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nPlease check your internet connection and try again." -ForegroundColor Yellow
    
    # Καθαρισμός σε περίπτωση error
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    exit 1
}
