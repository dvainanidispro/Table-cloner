#Requires -Version 5.1

<#
.SYNOPSIS
    Κατεβάζει τα απαραίτητα database drivers για το Table-Cloner script.
    
.DESCRIPTION
    Το script κατεβάζει τα MySql.Data.dll και Npgsql.dll από NuGet
    και τα τοποθετεί στον τρέχοντα φάκελο.
#>

Write-Host "`n=== Table Cloner - Driver Installation ===" -ForegroundColor Cyan
Write-Host "This script will download PostgreSQL drivers only.`n" -ForegroundColor White
# Δημιουργία φακέλου lib αν δεν υπάρχει
$libDir = Join-Path $PWD "lib"
if (-not (Test-Path $libDir)) {
    New-Item -Path $libDir -ItemType Directory -Force | Out-Null
    Write-Host "Created lib directory" -ForegroundColor Green
}

# URLs για τα NuGet packages
# Χρησιμοποιούμε εκδόσεις συμβατές με .NET Framework 4.8
$npgsqlPackageUrl = "https://www.nuget.org/api/v2/package/Npgsql/3.2.7"
$unsafeUrl = "https://www.nuget.org/api/v2/package/System.Runtime.CompilerServices.Unsafe/4.5.3"
$tasksExtensionsUrl = "https://www.nuget.org/api/v2/package/System.Threading.Tasks.Extensions/4.3.0"

# Temp directory
$tempDir = Join-Path $PWD "temp_drivers"

try {
    # Δημιουργία temp directory
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    
    # Κατέβασμα System.Runtime.CompilerServices.Unsafe (dependency του Npgsql)
    Write-Host "[1/6] Downloading System.Runtime.CompilerServices.Unsafe..." -ForegroundColor Yellow
    $unsafeZip = Join-Path $tempDir "System.Runtime.CompilerServices.Unsafe.zip"
    Invoke-WebRequest -Uri $unsafeUrl -OutFile $unsafeZip -UseBasicParsing
    
    Write-Host "[2/6] Extracting System.Runtime.CompilerServices.Unsafe.dll..." -ForegroundColor Yellow
    $unsafeExtract = Join-Path $tempDir "unsafe_extract"
    Expand-Archive -Path $unsafeZip -DestinationPath $unsafeExtract -Force
    # Πρέπει να πάρουμε το implementation assembly από lib\net461, όχι από ref\ ή netstandard
    $unsafeDll = Get-ChildItem -Path $unsafeExtract -Filter "System.Runtime.CompilerServices.Unsafe.dll" -Recurse | 
                 Where-Object { $_.FullName -match "\\lib\\net(4[0-9]{2})" -and $_.FullName -notmatch "\\ref\\" } | 
                 Sort-Object { $_.Directory.Name } -Descending | Select-Object -First 1
    if ($unsafeDll) {
        Copy-Item $unsafeDll.FullName -Destination (Join-Path $libDir "System.Runtime.CompilerServices.Unsafe.dll") -Force
        Write-Host "      System.Runtime.CompilerServices.Unsafe.dll installed successfully" -ForegroundColor Green
    } else {
        throw "Could not find System.Runtime.CompilerServices.Unsafe.dll in package"
    }
    
    # Κατέβασμα System.Threading.Tasks.Extensions (dependency του Npgsql)
    Write-Host "[3/6] Downloading System.Threading.Tasks.Extensions..." -ForegroundColor Yellow
    $tasksZip = Join-Path $tempDir "System.Threading.Tasks.Extensions.zip"
    Invoke-WebRequest -Uri $tasksExtensionsUrl -OutFile $tasksZip -UseBasicParsing
    
    Write-Host "[4/6] Extracting System.Threading.Tasks.Extensions.dll..." -ForegroundColor Yellow
    $tasksExtract = Join-Path $tempDir "tasks_extract"
    Expand-Archive -Path $tasksZip -DestinationPath $tasksExtract -Force
    # Χρησιμοποιούμε το portable version που έχει την σωστή assembly version (4.1.0.0)
    $tasksDll = Get-ChildItem -Path $tasksExtract -Filter "System.Threading.Tasks.Extensions.dll" -Recurse | 
                Where-Object { $_.FullName -match "portable" } | 
                Select-Object -First 1
    if ($tasksDll) {
        Copy-Item $tasksDll.FullName -Destination (Join-Path $libDir "System.Threading.Tasks.Extensions.dll") -Force
        Write-Host "      System.Threading.Tasks.Extensions.dll installed successfully" -ForegroundColor Green
    } else {
        throw "Could not find System.Threading.Tasks.Extensions.dll in package"
    }
    
    # Κατέβασμα PostgreSQL Driver
    Write-Host "[5/6] Downloading Npgsql driver..." -ForegroundColor Yellow
    # Κατέβασμα PostgreSQL Driver
    Write-Host "[5/6] Downloading Npgsql driver..." -ForegroundColor Yellow
    $npgsqlZip = Join-Path $tempDir "Npgsql.zip"
    Invoke-WebRequest -Uri $npgsqlPackageUrl -OutFile $npgsqlZip -UseBasicParsing
    Write-Host "      Downloaded successfully" -ForegroundColor Green
    
    # Εξαγωγή Npgsql DLL
    Write-Host "[6/6] Extracting Npgsql.dll..." -ForegroundColor Yellow
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
    
    # Καθαρισμός
    Write-Host "`nCleaning up temporary files..." -ForegroundColor Yellow
    Remove-Item $tempDir -Recurse -Force
    
    Write-Host "`n=== Installation Completed Successfully ===" -ForegroundColor Green
    Write-Host "`nInstalled drivers in lib/ directory:" -ForegroundColor White
    Write-Host "  - Npgsql.dll (with dependencies)" -ForegroundColor Cyan
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
