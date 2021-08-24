<# 
# License
Owner: https://github.com/brandon025
Version: 1.1
#>

# Get path to list of vms
$scriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$vmPath = Join-Path -Path $scriptDir -ChildPath "vmlist.csv"

$vmList = New-Object -TypeName 'System.Collections.ArrayList';

# GUI Menu
[int]$choice = Read-Host "Choose your input for a list of VM's:
1) Prompt me for a list of VM's
2) Bulk update from CSV file
3) Exit
    
Choice"

switch($choice){
    1{
        $myInput = Read-Host "List of VM (Comma Separated)"
        $tempArrList = $myInput.Split(",").Trim()
        foreach($vms in $tempArrList){
            if($vmList.contains($vms) -eq $false){
                [void]$vmList.add($vms)
            }
        }
    }
    2{
        # Pass CSV data to arraylist
        Import-Csv -Path $vmPath | %{
            if($vmList.contains($_.Name) -eq $false){
                [void]$vmList.add($_.Name)
            }
        }
    }
    3{Exit}
    default { Exit }
}


$vmObjList = @()
# Flush DNS
Write-Host "[Flushing DNS Cache]" -ForegroundColor Green
ipconfig /flushdns

# Check if host IPv6 exists
Write-Host "[Verifying IPV6 addresses]" -ForegroundColor Green
$vmList | %{
    Write-Host "Checking $_..." -ForegroundColor Green
    if(($cimSession = New-CimSession -ComputerName $_ -EA SilentlyContinue)){
        $ipv6adapter = (Get-NetIPAddress -cimSession $cimSession -AddressFamily IPv6 -InterfaceAlias Ethernet* -PrefixOrigin Manual).IPAddress
        $ipv6addr = (resolve-dnsname $_ -Type AAAA).IPAddress
        $vmInfo =[ordered]@{Hostname=$_
                            IPV6Adapter=$ipv6adapter
                            IPV6Lookup=$ipv6addr
                            Match=$ipv6addr -eq $ipv6adapter

                            }
        
        $vmObjList += New-Object –TypeName PSObject –Property $vmInfo
        }
    else{
        Write-Host "$_ SKIPPED! Cannot connect to server via RDP..." -ForegroundColor Yellow
    }
    $cimSession | Remove-CimSession
}

$vmObjList | Sort-Object -Property Match,Hostname | Format-Table
Write-Host "WARNING! Please check if all IPV6 addresses is valid first.." -ForegroundColor Yellow
$continue = Read-Host "Do you still want to continue disabling the IPV4 adapters (Y/n)"

# Remove IPv4 
if($continue -ieq "n"){exit}
$vmObjList.Hostname | % {
    Write-Host "Disabling V4 network adapter on $_..." -ForegroundColor Green
    Invoke-Command -ComputerName $_ -ScriptBlock { Disable-NetAdapterBinding -Name * -ComponentID ms_tcpip }}
$quitP = Read-Host "Input any key to quit"
