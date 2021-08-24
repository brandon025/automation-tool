<#
# License
Author: https://github.com/brandon025
[Version] 1.0
#>

# Configuration paths
$openSSLDir = "C:\Program Files\OpenSSL-Win64\bin"
$scriptDir = $PSScriptRoot
$logfile = "$scriptDir\logs.txt"

# Generate SSL configs, CSR, and key with OpenSSL
Function Create-SSL{
    # Define CN
    $commonName = Read-Host -Prompt "Enter the cname (IE: dns.domain.com)"
    # if($commonName -match '^[\w-]*\.[\w-]*\.*[\w]*$'){}else{Write-Host "[ERROR] $commonName is not a valid domain name" -ForegroundColor Red; return}

    # Check if cname already exists
    $sslexists = Test-Path -Path "$scriptDir\config\$commonName.conf", "$scriptDir\key\$commonName.key", "$scriptDir\csr\$commonName.csr", "$scriptDir\pfx\$commonName.pfx"
    $order = ("Config File:", "Key File:", "CSR File:", "PFX File:")
    $i = 0
    if($sslexists -contains $true){
        Write-Host "`n`nUh-oh! The common name seems to exist already..." -ForegroundColor Yellow
        $sslexists | %{ Write-Host $order[$i] $_ -ForegroundColor Yellow; $i+=1 }
        $exists = Read-Host -Prompt "Do you want to overwrite? (Y/n)"
        if($exists -ne "y" ){return}
    }

    # Define SANS
    $sans = Read-Host -Prompt "Enter ALT/SANS name (CNAME already included, separate by comma, leave blank for none)"
    $skip = $false
    if($sans){
        $sans = $sans.Trim().replace(' ','').split(',')
       # $sans | %{if($_ -match '^[\w-]*\.[\w-]*\.*[\w]*$'){}else{Write-Host "[ERROR] $_ is not a valid domain name" -ForegroundColor Red; $skip = $true}}
        if($skip){return}
    }

# Build the config file
    $configFile = @"
# -------------- BEGIN CONFIG --------------
# OpenSSL configuration to generate a new key with signing requst for a x509v3
# multidomain certificate

[ req ]
default_bits = 4096
default_md = sha512
default_keyfile = key.pem
prompt = no
encrypt_key = no

# base request
distinguished_name = req_distinguished_name

# extensions
req_extensions = v3_req

# distinguished_name
[ req_distinguished_name ]
countryName = "US" # C=
stateOrProvinceName = "California" # ST=
localityName = "Santa Clara" # L=
organizationName = "IT" # O=
organizationalUnitName = "Sysadmins" # OU=
commonName = $commonName # CN= server name if not using a cname
emailAddress = "myemailaddress@domain.com" # CN/emailAddress=
# req_extensions
[ v3_req ]
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth

[alt_names]
DNS.1 = $commonName
"@

    # Add ALT NAMES
    $counter = 1
    if($sans.count -gt 1){
        $sans | %{
            $counter += 1
            $configFile += @"

DNS.$counter = $_
"@
}
}

    # Create Config File
    Write-Host "Generating Config File" -ForegroundColor Green
    $configFile | Out-File -FilePath $scriptDir\config\$($commonName).conf -Force -Encoding ascii

    # Change directory
    Set-Location -Path $openSSLDir

    # Generate the key and csr
    Write-Host "Generating the key and csr files" -ForegroundColor Green
    Start-Process -Wait .\openssl.exe -Argumentlist "req -newkey rsa:4096 -keyout $scriptDir\key\$commonName.key -sha256 -out $scriptDir\csr\$commonName.csr -config $scriptDir\config\$commonName.conf"

    # Write out CSR file
    Write-Host "Getting CSR contents... `n`n" -ForegroundColor Green
    Start-Sleep -s 5
    Get-Content $scriptDir\csr\$commonName.csr
    Write-Host "`n`rCN: $commonName" -ForegroundColor Yellow
    Write-Host "SANS (alt names): $sans" -ForegroundColor Yellow
    Write-Log "init" $commonName
}

# Generate SSL CSR, and key with existing configuration
Function Create-manualSSL{
    Write-Host "`n`r`n`rPlease place your manual configuration files in the config path (IE: $scriptDir\config\cname.conf)..."
    $commonName = Read-Host -Prompt "Enter the CNAME"
    # if($commonName -match '^[\w-]*\.[\w-]*\.*[\w]*$'){}else{Write-Host "[ERROR] $commonName is not a valid domain name" -ForegroundColor Red; return}
    if(Test-Path -Path "$scriptDir\config\$commonName.conf"){
        # Check if cname already exists
        $sslexists = Test-Path -Path "$scriptDir\key\$commonName.key", "$scriptDir\csr\$commonName.csr", "$scriptDir\pfx\$commonName.pfx"
        $order = ("Key File:", "CSR File:", "PFX File:")
        $i = 0
        if($sslexists -contains $true){
            Write-Host "`n`nUh-oh! The SSL files seems to exist already..." -ForegroundColor Yellow
            $sslexists | %{ Write-Host $order[$i] $_ -ForegroundColor Yellow; $i+=1 }
            $exists = Read-Host -Prompt "Do you want to overwrite? (Y/n)"
            if($exists -ne "y" ){return}
        }
        Set-Location -Path $openSSLDir
        Start-Process -Wait .\openssl.exe -Argumentlist "req -newkey rsa:4096 -keyout $scriptDir\key\$commonName.key -sha256 -out $scriptDir\csr\$commonName.csr -config $scriptDir\config\$commonName.conf"
        # Write out CSR file
        Write-Host "Getting CSR contents... `n`n" -ForegroundColor Green
        Start-Sleep -s 5
        Get-Content $scriptDir\csr\$commonName.csr
        Write-Log "init" $commonName
    }
    else{
        Write-Host "[ERROR] Cannot find config file, please try again..." -ForegroundColor Red
    }
}

# Generate PFX file with cert
Function Create-PFXFile{
    $commonName = Read-Host -Prompt "Enter the cname"
    # if($commonName -match '^[\w-]*\.[\w-]*\.*[\w]*$'){}else{Write-Host "[ERROR] $commonName is not a valid domain name" -ForegroundColor Red; return}
    # Check paths
    Write-Host "Checking Paths..." -ForegroundColor Green
    $sslexists = Test-Path -Path "$scriptDir\key\$commonName.key", "$scriptDir\cer\$commonName.cer", "$scriptDir\pfx\$commonName.pfx"
    $order = ("Key File:", "CER File:", "PFX File:")

    $i = 0
    $sslexists | %{ Write-Host $order[$i] $_ -ForegroundColor Yellow; $i+=1 }

    if($sslexists[2]){
        $choice = Read-Host -Prompt "PFX file already exists... do you want to overwrite? (Y/n)"
        if($choice -ne "Y"){return}
    }
    if(!$sslexists[0]){
        Write-Host "[ERROR] Please generate the key first and place in $scriptDir\key..." -ForegroundColor Red
        return
    }
    if(!$sslexists[1]){
        Write-Host "[ERROR] No certificate was founded. Please generate one first and place in $scriptDir\key..." -ForegroundColor Red
        return
    }

    Set-Location -Path $openSSLDir
    Start-Process -Wait .\openssl.exe -Argumentlist "pkcs12 -export -out $scriptDir\pfx\$commonName.pfx -inkey $scriptDir\key\$commonName.key -in $scriptDir\cer\$commonName.cer"
    Start-Sleep -s 5
    Write-Log "pfx" $commonName
}

# Create logs
Function Write-Log($func, $commonName){
    # Write history log
    Write-Host "`r`n`r`nChecking if file exists ($scriptDir)..." -ForegroundColor Green

    if($func -eq "init"){
       $sslexists = Test-Path -Path "$scriptDir\config\$commonName.conf", "$scriptDir\key\$commonName.key", "$scriptDir\csr\$commonName.csr"
       $order = ("Config", "Key", "CSR")
       $i = 0
       if($sslexists -contains $false){
            Write-Host "[ERROR] some file contents is missing..." -ForegroundColor Red
            Add-Content $scriptDir\logs.txt "[ERROR] some file contents is missing..."
       }
       Add-Content $scriptDir\logs.txt -NoNewLine "$([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( (Get-Date), 'Pacific Standard Time').tostring("MM-dd-yyyy (hh:mm:ss tt PST)")): [$commonName] $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) - Created: "
       Write-Host -NoNewline "Founded: " -ForegroundColor Yellow
       $sslexists | %{
            if($_ -eq $true){
                Write-Host -NoNewLine $order[$i] -ForegroundColor Yellow
                Add-Content $scriptDir\logs.txt -NoNewline $order[$i]
                $i+=1
                if($i -lt $order.count){
                    Write-Host -NoNewLine ", " -ForegroundColor Yellow
                    Add-Content $scriptDir\logs.txt -NoNewline ", "
                }
            }
        }
        Add-Content $scriptDir\logs.txt ""
    }
    elseif($func -eq "pfx"){
        if(Test-Path -Path "$scriptDir\pfx\$commonName.pfx"){
            Write-Host "PFX file: True" -ForegroundColor Yellow
            Add-Content $scriptDir\logs.txt "$([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( (Get-Date), 'Pacific Standard Time').tostring("MM-dd-yyyy (hh:mm:ss tt PST)")): [$commonName] $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) - Created: PFX "
        }
        else{
            Write-Host "[ERROR] PFX was not founded. Something went wrong..." -Foregroundcolor Red
            Add-Content $scriptDir\logs.txt "$([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId( (Get-Date), 'Pacific Standard Time').tostring("MM-dd-yyyy (hh:mm:ss tt PST)")): [$commonName] $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) - ERROR creating PFX files!"
        }
    }
}

# Main
while(1){
Write-Host "`n`n==============================================================
OPENSSL Generator
Version: 1.0

[Warning] WE ARE NOT RESPONSIBLE FOR ANY ISSUES CAUSED BY THIS SCRIPT. USE WITH CAUTION!
==============================================================

1) Create Config + CSR + Key
2) Create CSR + Key with a custom config file
3) Create PFX
4) OpenSSL Log History (LAST 25)
5) Quit

" -ForegroundColor Blue

    $choice = Read-Host -Prompt "Choose an option"

    switch ($choice)
    {
       1{Create-SSL}
       2{Create-ManualSSL}
       3{Create-PFXFile}
       4{Write-Host " === OPENSSL LOG FILE START ===" -ForegroundColor Blue; Get-Content $logfile -Tail 25; Write-Host " === OPENSSL LOG FILE END ===" -ForegroundColor Blue}
       5{return}
       default {Write-Host "[Error] Not a valid option! Please select a valid number again..." -ForegroundColor Red}
    }
}
