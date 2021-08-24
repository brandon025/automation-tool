<# 
# License
Owner: https://github.com/brandon025
Version: 1.3
#>

# Install PowerCLI
if(Get-Module -List VMware.PowerCLI){}else{Install-Module -Name VMware.PowerCLI -Confirm:$false}
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null

### Get VM List Path
$scriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$vmPath = Join-Path -Path $scriptDir -ChildPath "VMList.csv"

$vmList = New-Object -TypeName 'System.Collections.ArrayList';
$vmFoundList = New-Object -TypeName 'System.Collections.ArrayList';
$vmObj = @()
$numRuns = 0 # Output VMList type

### GUI Menu
Function Get-Configs{
    $file = Import-LocalizedData -BaseDirectory $scriptDir -FileName configs.psd1
    $numofCPU = $file.numofCPU
    $numofMem = $file.numofMem
    $driveCMap = $file.driveCVMHD
    $driveDMap = $file.driveDVMHD
    $driveCSpace = $file.driveCSpace
    $driveDSpace = $file.driveDSpace
    $vcHosts = $file.vcHosts

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

    return $numofCPU, $numofMem, $driveCMap, $driveDMap, $driveCSpace, $driveDSpace, $vcHosts, $vmList
}

### Connect to vsphere hosts
Function Connect-VC{
    Write-Host "`n=== Connections ==="
    $cred = Get-Credential -Message 'Please enter your admin login credentials.'
    Connect-VIServer -Server $vcHosts -Credential $cred
    
}

### Get hardware data
Function Get-Hardware{
    Write-Host "
The following VM's will be updated with the following configurations: 
CPU: $numofCPU
Memory: $numOfMEM
Drive C: $driveCSpace
Drive D: $driveDSpace

=== List of VM's ==="
    $numRuns, $vmObj = Get-VMList

    # Continue script?
    if($vmFoundList.Count -gt 0){
        $confirmP = Read-Host "`nPlease confirm these changes, there is no going back (y/n)"
        
        if($confirmP -ne "Y"){
            Close-Connections
            Exit
        }
        return $numRuns, $vmObj
    }
    else{
        Write-Host "[ERROR] NO VM's were found on the host. Please try again!" -ForegroundColor Red
        Close-Connections
        Exit 
    }
}

### Update resources
Function Update-Hardware($vm){
    foreach($vms in $vm){
        # Update hardware 
        Write-Host "[Action] Updating resources for" $vms.Name "..." -ForegroundColor Green
        Update-CPUMem($vms)
        Update-HD($vms)
    }
}

### Update CPU/RAM
Function Update-CPUMem($vm){
    Write-Host "[Action] Updating CPU/Mem.." -ForegroundColor Green
    
    if($vm.MemoryGB -eq $numofMem -and $vm.NumCpu -eq $numofCpu){
        Write-Host "[Warning]" $vm.Name "CPU/memory has already been set. No changes made" -ForegroundColor Yellow
    }
    else{
        # Shutdown VM
        $powerState = Get-VMGuest -vm $vm.Name | select -ExpandProperty State    
        if(((get-vmguest -vm $vm).State) -eq 'Running'){
            Write-Host "[Action] Powering down VM.." -ForegroundColor Green
            Shutdown-VMGuest $vm -Confirm:$false | out-null
        }

        # Wait until VM is shutdown
        while (((get-vmguest -vm $vm).State) -ne 'NotRunning') {
            start-sleep -s 5
            Write-Host "Waiting for" $vm.Name "to shutdown..." -ForegroundColor Yellow
        }

        #Set CPU/Memory
        if($vm.MemoryGB -ne $numofMem){
            Set-VM $vm -memoryGB $numofMem -Confirm:$false | out-null
        }
        else{
            Write-Host "[Warning]" $vm.Name "memory has already been set. No changes made." -ForegroundColor Yellow
        }
        if($vm.NumCpu -ne $numofCPU){
            Set-VM $vm -NumCpu $numofCPU -Confirm:$false | out-null
        }
        else{
            Write-Host "[Warning]" $vm.Name "CPU has already been set. No changes made." -ForegroundColor Yellow
        }
        Write-Host "[Action] Powering up VM..." -ForegroundColor Green
        Start-VM $vm -Confirm:$false | out-null
    }
}

### Update Hard Disk
Function Update-HD($vm){
    Write-Host "[Action] Updating HD space.." -ForegroundColor Green
    # Check ESX Cluster if space is available, leave extra 10GB just in case
    $esxCluster = Get-Cluster -VM $vm | select -ExpandProperty Name
    $esxSpace = Get-Cluster $esxCluster | Get-Datastore | Sort-Object -Property FreeSpaceGB -Descending | Select -First 1 -ExpandProperty FreeSpaceGB
    $totalVMSpace = $driveCSpace + $driveDSpace + 10 
    if($esxSpace -gt $totalVMSpace){
        Write-Host "[Warning] $esxCluster only has" $esxSpace "GB left." -ForegroundColor Yellow

        # Check VM is running
            if($powerState -eq "NotRunning"){
                Write-Host "[Action] Powering up VM..." -ForegroundColor Green
                Start-VM $vm -Confirm:$false | out-null
            }

            while (((get-vmguest -vm $vm).State) -ne 'Running') {
                start-sleep -s 5
                Write-Host "Waiting for" $vm.Name "to turn on..." -ForegroundColor Yellow
            }

        # Expand Space
        $vmHD1 = Get-HardDisk -VM $vm.Name -Name $driveCMap | select -ExpandProperty CapacityGB
        if($vmHD1 -lt $driveCSpace){
            Get-VM $vm | Get-HardDisk -Name $driveCMap | Set-HardDisk -CapacityGB $driveCSpace -Confirm:$false | out-null
            Invoke-Command -ComputerName $vm.Name -ScriptBlock {
                Update-HostStorageCache | out-null
                start-sleep -s 5
                Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax | out-null
                } 
        }
        else{
            Write-Host "[Warning]" $vm.Name "$driveCMap (C:/) cannot be expanded because current VMHD >= new VMHD. No changes made." -ForegroundColor Yellow
        }
        $vmHD2 = Get-HardDisk -VM $vm.Name -Name $driveDMap | select -ExpandProperty CapacityGB
        if($vmHD2 -lt $driveDSpace){
            Get-VM $vm | Get-HardDisk -Name $driveDMap | Set-HardDisk -CapacityGB $driveDSpace -Confirm:$false | out-null
            Invoke-Command -ComputerName $vm.Name -ScriptBlock {
                Update-HostStorageCache | out-null
                start-sleep -s 5
                Resize-Partition -DriveLetter D -Size $(Get-PartitionSupportedSize -DriveLetter D).SizeMax | out-null
            }
        }
        else{
            Write-Host "[Warning]" $vm.Name "$driveDMap (D:/) cannot be expanded because current VMHD >= new VMHD. No changes made." -ForegroundColor Yellow
        }
    }
    else{
        Write-Host "[Error] $esxCluster only has" $esxSpace "GB left. Please free up some space before continuing." -ForegroundColor Red
    }
}

## Output a list of VM's
Function Get-VMList(){
    $vmObjList = @()
    if($numRuns -gt 0){
        Write-Host "`n=== Updated List of VM's ==="
        $list = $vmFoundList
    }
    else{$list = $vmList}

    # Process List
    foreach ($VC in $vcHosts){
        if($numRuns -lt 1){$vmObj = $vmObj + (Get-VM -Server $VC | ?{$list.contains($_.Name) -eq $true})}
        else{$vmObj = Get-VM -Server $VC | ?{$list.contains($_.Name) -eq $true}}
    }

    # Prepare table
    foreach($vms in $vmObj){
        # Update processed VM's list
        if($numRuns -lt 1){
            [void]$vmFoundList.add($vms.Name)
            [void]$vmList.Remove($vms.Name)
        }
        $vmInfo =[ordered]@{VMName=$vms.Name
                            Power=$vms.powerState
                            CPU=$vms.NumCpu
                            MEM=$vms.MemoryGB
                            cVMHD=Get-HardDisk $vms -Name $driveCMap | select -ExpandProperty CapacityGB
                            dVMHD=Get-HardDisk $vms -Name $driveDMap | select -ExpandProperty CapacityGB
                            DriveC = [int]((get-vmguest $vms).Disks | where {$_.Path -match "^C:"} | Select -ExpandProperty CapacityGB)
                            DriveD = [int]((get-vmguest $vms).Disks | where {$_.Path -match "^D:"} | Select -ExpandProperty CapacityGB)
      }
        
        $vmObjList += New-Object –TypeName PSObject –Property $vmInfo
}

    # Print List
    Write-Host ($vmObjList | Sort-Object VMName | Format-Table -AutoSize | Out-String)
    if($vmFoundList.Count -gt 0){
        if($vmList -gt 0){
            $sortedList = $vmList | Sort-Object
            Write-Host "HOSTS not found: $sortedList" -ForegroundColor Red
        }
   }
   return ($numRuns+1), $vmObj
}

## Close Connection
Function Close-Connections{
    foreach ($VC in $vcHosts){
        Disconnect-VIServer -Server $VC -Confirm:$false
        Write-Host "Closed connected to $VC" -ForegroundColor Green
    }
}

# Main
$numofCPU, $numofMem, $driveCMap, $driveDMap, $driveCSpace, $driveDSpace, $vcHosts, $vmList = Get-Configs
Connect-VC
$numRuns, $vmObj = Get-Hardware
Update-Hardware($vmObj)
start-sleep -s 20 # Wait for VM's to turn on
$numRuns, $vmObj = Get-VMList
Close-Connections

$quitP = Read-Host "Input any key to quit"

