<# 
# License
Owner: https://github.com/brandon025
Version: 1.0

### Get VM List Path
$scriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$vmPath = Join-Path -Path $scriptDir -ChildPath "VMObjectsList.csv"

$vmList = New-Object -TypeName 'System.Collections.ArrayList';

### GUI Menu
Function Get-Configs{

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

    return $vmList
}

# Check for any DNS Entries
Function Get-DNSEntry($vm){
    $DNSEntry = (Resolve-DnsName -ea SilentlyContinue -Name $vm).name
    if ($DNSEntry){ return $DNSEntry} else { return "[NA] $vm" }

}

# Check for any IP Entries
Function Get-IPAddress($vm){
    $IPList = (Resolve-DnsName -ea SilentlyContinue -Name $vm).IPAddress
    if ($IPList){ return $IPList} else { return "NA" } 
}

# Check for any AD records
Function Get-OUObject($vm){
    TRY
    {
        if (Get-adcomputer -ea SilentlyContinue $vm) { return $true } else { return $false } 
    }
    Catch
    {
        return $false
    }
}

# Check connection
Function Get-Connection($vm){
    return Test-Connection $vm -Count 1 -Quiet 
}

## Output a list of VM's
Function Get-VMList{
    $vmObjList = @()
    Write-Host "`n=== VM Status ==="

    # Prepare table
    foreach($vm in $vmList){
        # Update processed VM's list
        $vmInfo =[ordered]@{DNS = Get-DNSEntry($vm)
                            ADExist = Get-OUOBject($vm)
                            Ping = Get-Connection($vm)
                            IP = Get-IPAddress($vm)
                            
      }
        $vmObjList += New-Object –TypeName PSObject –Property $vmInfo
    }

    # Print List
    Write-Host ($vmObjList | Sort-Object DNS | Format-Table -AutoSize | Out-String)
}

# Main 
$vmList = Get-Configs
Get-VMList

$quitP = Read-Host "Input any key to quit"
