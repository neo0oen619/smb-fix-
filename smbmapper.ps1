function Get-TailscaleClients {
    try {
        $status = tailscale status 2>$null
        if (-not $status) { return @() }
        
        $clients = @()
        foreach ($line in $status) {
            if ($line -match '^(100\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+(\S+)') {
                $ip = $matches[1]
                $name = $matches[2]
                $clients += [PSCustomObject]@{IP=$ip; Name=$name}
            }
        }
        return $clients
    } catch {
        return @()
    }
}

function Read-SecurePassword([string]$prompt = "Enter Password: ") {
    Write-Host $prompt -NoNewline
    $password = Read-Host -AsSecureString
    return $password
}

function ConvertFrom-SecureStringToPlainText($secureString) {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-FreeDriveLetters($count) {
    $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
    $letters = @()
    $asciiZ = [int][char]'Z'
    $asciiA = [int][char]'D' # Start from D to avoid system reserved drives C:, A:, B:
    for ($i = $asciiZ; $i -ge $asciiA; $i--) {
        $letter = [char]$i
        if ($usedLetters -notcontains $letter) {
            $letters += $letter
            if ($letters.Count -eq $count) {
                break
            }
        }
    }
    if ($letters.Count -lt $count) {
        Write-Warning "Not enough free drive letters available!"
    }
    return $letters
}

Write-Host "=== SMB Drive Mapper Interactive ===`n"

# Tailscale IP selection
$clients = Get-TailscaleClients

if ($clients.Count -gt 0) {
    Write-Host "Available Tailscale clients:"
    for ($i=0; $i -lt $clients.Count; $i++) {
        Write-Host "[$i] $($clients[$i].IP)  $($clients[$i].Name)"
    }

    $selectedIndex = Read-Host "Select IP address by number (or type 'M' to manually enter IP)"
    if ($selectedIndex -match '^[0-9]+$' -and
        [int]$selectedIndex -ge 0 -and
        [int]$selectedIndex -lt $clients.Count) {
        $targetIP = $clients[$selectedIndex].IP
    } else {
        $targetIP = Read-Host "Enter the target IP address manually"
    }
} else {
    Write-Host "Could not detect Tailscale clients automatically."
    $targetIP = Read-Host "Enter the target IP address manually"
}

Write-Host "`nTarget IP set to: $targetIP`n"

$userName = Read-Host "Enter SMB username"

$securePwd = Read-SecurePassword "Enter SMB password: "
$password = ConvertFrom-SecureStringToPlainText $securePwd

do {
    $shareCountInput = Read-Host "How many shares do you want to map?"
} while (-not ($shareCountInput -match '^\d+$') -or [int]$shareCountInput -le 0)

$shareCount = [int]$shareCountInput

$shareNames = @()
for ($i=1; $i -le $shareCount; $i++) {
    $shareName = Read-Host "Enter name of share #$i"
    $shareNames += $shareName
}

Write-Host "`nShares to map: $($shareNames -join ', ')`n"

# Get free drive letters (D-Z range)
$freeLetters = Get-FreeDriveLetters $shareCount

if ($freeLetters.Count -lt $shareCount) {
    Write-Host "Aborting due to insufficient free drive letters." -ForegroundColor Red
    exit 1
}

for ($i=0; $i -lt $shareCount; $i++) {
    $driveLetter = $freeLetters[$i]
    $drive = "${driveLetter}:"   # Correct way to append colon safely
    $share = $shareNames[$i]
    $sharePath = "\\$targetIP\$share"

    # Remove existing mapping if any
    if (Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue) {
        Write-Host "Removing existing mapping for $drive..."
        net use $drive /delete /y | Out-Null
    }

    Write-Host "Mapping $sharePath to drive $drive..."
    $netOutput = net use $drive $sharePath /user:$userName $password /persistent:no 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully mapped $share to $drive" -ForegroundColor Green
    } else {
        Write-Host "Failed to map $share to ${drive}:" -ForegroundColor Red
        Write-Host $netOutput
    }
    Write-Host ""
}

Write-Host "Drive mapping complete."
