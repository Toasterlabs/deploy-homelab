<#	
    .NOTES
	=========================================================================================================
        Filename:	deploy-homelab.ps1
        Version:	0.6 
        Created:	03/2016
                    
	    Author:         Marc Dekeyser (a.k.a. Toasterlabs)
	    Blog:	https://geekswithblogs.net/marcde
	=========================================================================================================
	
    .SYNOPSIS
	    This script will deploy a number of virtual machines in a VMWare environment.

    .DESCRIPTION
        I was tired of building a lab out manually so I automated it...

    .HOWTO
        Change the pluginpath, user, pass, host and hostname to match your environment. At the end of the script, change
        InfluxDB-IP, InfluxDB-port & InfluxDB-Name to the values of your Influx DB Server and DB Name
    
    .EXAMPLE
        .\deploy-homelab.ps1

    .FUTURE
        I should really start making use of those parameters...

    .parameter vcenterinstance
        Your vCenter instance

    .parameter vcenterUser
        Your vCenter username

    .parameter vcenterinstance
        Your vCenter Password

    .parameter TargetCluster
        The target cluster for your deployment

    .parameter SourceVMTemplate
        VM Template you will be deploying your machines from

    .Parameter SourceCustomSpec
        Customization specification to be used

    .parameter $datastore
        Datastore to deploy on

    .parameter $datastore2
        Datastore for additional disks

    .parameter vms
        The machine names you want to deploy

#>



# Variables
# ------vSphere Targeting Variables tracked below------
$vCenterInstance = "your-vcenter-instance-here"
$vCenterUser = "vcenter-usernam"
$vCenterPass = "vcenter-password"

## Whilst not pretty this has to be here unless we like to see red text!
# This section insures that the PowerCLI PowerShell Modules are currently active. The pipe to Out-Null can be removed if you desire additional
# Console output.
Get-Module -ListAvailable VMware* | Import-Module | Out-Null


# This section logs on to the defined vCenter instance above
Connect-VIServer $vCenterInstance -User $vCenterUser -Password $vCenterPass -WarningAction SilentlyContinue


$TargetCluster = ""
$SourceVMTemplate = ""
$SourceCustomSpec = ""
$datastore = ""
$datastore2 = ""

# ------Virtual Machines to create------
$vms = ""


# ------Network Settings for domaincontrollers------
$WDC01NetworkSettings = 'netsh interface ip set address "Ethernet0" static 192.168.10.10 255.255.255.0 192.168.10.254'

$WDC02NetworkSettings = 'netsh interface ip set address "Ethernet0" static 192.168.10.11 255.255.255.0 192.168.10.254'
$WDC02DNSSettings = 'Set-DNSClientServerAddress –interfaceIndex 12 –ServerAddresses (“192.168.10.10”,”192.168.10.11”)'

$EDC01NetworkSettings = 'netsh interface ip set address "Ethernet0" static 192.168.11.10 255.255.255.0 192.168.11.254'
$EDC01DNSSettings = 'Set-DNSClientServerAddress –interfaceIndex 12 –ServerAddresses (“192.168.10.10”)'

$EDC02NetworkSettings = 'netsh interface ip set address "Ethernet0" static 192.168.11.11 255.255.255.0 192.168.11.254'
$EDC02DNSSettings = 'Set-DNSClientServerAddress –interfaceIndex 12 –ServerAddresses (“192.168.10.10”)'

# ------This Section Contains the Scripts to be executed against New Domain Controller VMs------
# This Command will Install the AD Role on the target virtual machine.
$InstallADRole = 'Install-WindowsFeature -Name "AD-Domain-Services" -Restart'
# This Scriptblock will define settings for a new AD Forest and then provision it with said settings.
# NOTE - Make sure to define the DSRM Password below in the line below that defines the $DSRMPWord Variable!!!!
$ConfigureNewDomain = 'Write-Verbose -Message "Configuring Active Directory" -Verbose;
                       $DomainMode = "Win2012R2";
                       $ForestMode = "Win2012R2";
                       $DomainName = "corp.toasterlabs.org";
                      
                       $DSRMPWord = ConvertTo-SecureString -String "YOURPASSWORDHERE" -AsPlainText -Force;
                       Install-ADDSForest -ForestMode $ForestMode -DomainMode $DomainMode -DomainName $DomainName -InstallDns -SafeModeAdministratorPassword $DSRMPWord -Force'

$AddDomainController ='Import-Module ADDSDeployment;
                      Write-Verbose -Message "Configuring Active Directory" -Verbose;
                      $DomainName = "corp.toasterlabs.org";
                      $DSRMPWord = ConvertTo-SecureString -String "YOURPASSWORDHERE" -AsPlainText -Force;
                      $ADDSUser = "Corp\Administrator";
                      $ADDSPWord = ConvertTo-SecureString -String "YOURPASSWORDHERE" -AsPlainText -Force;
                      $ADDSCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ADDSUser, $ADDSPWord;
                      install-addsDomainController -domainname $domainName -credential $ADDSCredential -InstallDNS -SafeModeAdministratorPassword $DSRMPWord -force'

# ------This Section Contains the Scripts to be install DHCP------
$installDHCP = 'Add-WindowsFeature  -IncludeManagementTools dhcp'
               

# END Variables

foreach($vm in $vms){
    Write-Verbose -Message "Deploying Virtual Machine with Name: [$vm] using Template: [$SourceVMTemplate] and Customization Specification: [$SourceCustomSpec], on Cluster: [$TargetCluster] and Datastore [$datastore]. Waiting for completion..." -Verbose
    New-VM -Name $vm -Template $SourceVMTemplate -ResourcePool $TargetCluster -OSCustomizationSpec $SourceCustomSpec -Datastore $datastore
    
    # If the vm is not a domain controller I want to add a 200GB thinprovisioned disk
    if ($vm -notlike "*DC0*"){
        Write-Verbose -Message "Adding 200GB disk to [$vm] on datastore [$datastore2]" -Verbose
        $adddisk = get-vm $vm
        $vm | New-HardDisk -CapacityGB 200 -ThinProvisioned -Datastore $datastore2 -Confirm:$false
    }
    
    # if the vm is an exchange box I need to change the memory allocation to 13GB (what a memory hog!)
    if($vm -like "*EX*"){
        Write-Verbose -Message "Setting memory on [$vm] to [13GB]" -Verbose
        set-vm $vm -MemoryGB 13 -confirm:$false -whatif
    }

    # if the vm is a Lync box I need to change the memory allocation to 8GB
    if($vm -like "*LY*"){
        Write-Verbose -Message "Setting memory on [$vm] to [8GB]" -Verbose
        set-vm $vm -MemoryGB 8 -confirm:$false -whatif

    }


    # Setting networks depending on machine name

    switch -Wildcard ($vm)
        {
           "USDCW*" 
                {
                    Write-Verbose -Message "Setting network on [$vm] to [US DC West]" -Verbose
                    $DistributedSwitchPortgroup = Get-VDPortgroup -name "US DC West"
                    get-vm $vm | Get-NetworkAdapter |Set-NetworkAdapter -Portgroup $DistributedSwitchPortgroup  -Confirm:$false
                }
           "USDCE*" 
                {
                    Write-Verbose -Message "Setting network on [$vm] to [US DC East]" -Verbose
                    $DistributedSwitchPortgroup = Get-VDPortgroup -name "US DC East"
                    get-vm $vm | Get-NetworkAdapter |Set-NetworkAdapter -portgroup $DistributedSwitchPortgroup -Confirm:$false

                }
           "USDCC*" 
                {
                    Write-Verbose -Message "Setting network on [$vm] to [US DC Central]" -Verbose
                    $DistributedSwitchPortgroup = Get-VDPortgroup -name "US DC Central"
                    get-vm $vm | Get-NetworkAdapter |Set-NetworkAdapter -Portgroup $DistributedSwitchPortgroup -Confirm:$false

                }
           "DMZ*" 
                {
                    Write-Verbose -Message "Setting network on [$vm] to [DMZ]" -Verbose
                    $DistributedSwitchPortgroup = Get-VDPortgroup -name "DMZ"
                    get-vm $vm | Get-NetworkAdapter |Set-NetworkAdapter -Portgroup $DistributedSwitchPortgroup -Confirm:$false
                }
        }

    # Starting VM
    Write-Verbose -Message "Virtual Machine [$vm] Deployed. Powering On" -Verbose
    Start-VM -VM $vm

    # ------This Section Targets and Executes the Scripts on the New Domain Controller Guest VM------
    # We first verify that the guest customization has finished on on the new DC VM by using the below loops to look for the relevant events within vCenter.
    Write-Verbose -Message "Verifying that Customization for VM [$vm] has started ..." -Verbose
       while($True)
               {
		            $DCvmEvents = Get-VIEvent -Entity $vm
		            $DCstartedEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationStartedEvent" }
		            if ($DCstartedEvent)
		                {
			                break
		                }
		                else
		                {
			                Start-Sleep -Seconds 5
		                }
	          }
    Write-Verbose -Message "Customization of VM [$vm] has started. Checking for Completed Status......." -Verbose
	    while($True)
	          {
	                $DCvmEvents = Get-VIEvent -Entity $vm
	                $DCSucceededEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationSucceeded" }
                    $DCFailureEvent = $DCvmEvents | Where { $_.GetType().Name -eq "CustomizationFailed" }
	                   if ($DCFailureEvent)
		                {
			                Write-Warning -Message "Customization of VM [$vm] failed" -Verbose
                            return $False
		                }
		                if ($DCSucceededEvent)
		                {
                            break
		                }
                        Start-Sleep -Seconds 5
	                }



     Write-Verbose -Message "Customization of VM [$vm] Completed Successfully!" -Verbose
           
     # NOTE - The below Sleep command is to help prevent situations where the post customization reboot is delayed slightly causing
     # the Wait-Tools command to think everything is fine and carrying on with the script before all services are ready. Value can be adjusted for your environment.
     Start-Sleep -Seconds 30
     Write-Verbose -Message "Waiting for VM [$vm] to complete post-customization reboot." -Verbose
     Wait-Tools -VM $vm -TimeoutSeconds 300
         
     # NOTE - Another short sleep here to make sure that other services have time to come up after VMware Tools are ready.
     Start-Sleep -Seconds 30

    # NOTE - local credentials
    $DCLocalUser = "$VM\Administrator"
    $DCLocalPWord = ConvertTo-SecureString -String "YOURPASSWORDHERE" -AsPlainText -Force
    $DCLocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DCLocalUser, $DCLocalPWord


     # After Customization Verification is done we change the IP of the VM to the value defined near the top of the script
     Write-Verbose -Message "Getting ready to change IP Settings on VM [$vm] if defined. And configuring it as part of the domain." -Verbose
     switch ($vm)
        {
            USDCWDC01 
                {
                    Invoke-VMScript -ScriptText $WDC01NetworkSettings -VM $vm -GuestCredential $DCLocalCredential

                    # NOTE - The Below Sleep Command is due to it taking a few seconds for VMware Tools to read the IP Change so that we can return the below output.
                    # This is strctly informational and can be commented out if needed, but it's helpful when you want to verify that the settings defined above have been
                    # applied successfully within the VM. We use the Get-VM command to return the reported IP information from Tools at the Hypervisor Layer.
                    Start-Sleep 30
                    $DCEffectiveAddress = (Get-VM $vm).guest.ipaddress[0]
                    Write-Verbose -Message "Assigned IP for VM [$vm] is [$DCEffectiveAddress]" -Verbose

                    # Then we Actually install the AD Role and configure the new domain
                    Write-Verbose -Message "Getting Ready to Install Active Directory Services on $vm" -Verbose
                    Invoke-VMScript -ScriptText $InstallADRole -VM $vm -GuestCredential $DCLocalCredential
                    Write-Verbose -Message "Configuring New AD Forest on $vm" -Verbose
                    Invoke-VMScript -ScriptText $ConfigureNewDomain -VM $vm -GuestCredential $DCLocalCredential
                }
            USDCWDC02 
                {
                    Invoke-VMScript -ScriptText $WDC02NetworkSettings -VM $vm -GuestCredential $DCLocalCredential
                    Invoke-VMScript -ScriptText $WDC02DNSSettings -VM $vm -GuestCredential $DCLocalCredential

                    # NOTE - The Below Sleep Command is due to it taking a few seconds for VMware Tools to read the IP Change so that we can return the below output.
                    # This is strctly informational and can be commented out if needed, but it's helpful when you want to verify that the settings defined above have been
                    # applied successfully within the VM. We use the Get-VM command to return the reported IP information from Tools at the Hypervisor Layer.
                    Start-Sleep 30
                    $DCEffectiveAddress = (Get-VM $vm).guest.ipaddress[0]
                    Write-Verbose -Message "Assigned IP for VM [$vm] is [$DCEffectiveAddress]" -Verbose

                    # Then we install the AD Role and Add the domain controller to the domain
                    Write-Verbose -Message "Getting Ready to Install Active Directory Services on $vm" -Verbose
                    Invoke-VMScript -ScriptText $InstallADRole -VM $vm -GuestCredential $DCLocalCredential
                    Write-Verbose -Message "Configuring [$vm] as a Domain Controller" -Verbose
                    Invoke-VMScript -ScriptText $AddDomainController -VM $vm -GuestCredential $DCLocalCredential
                }
            USDCEDC01 
                {
                    Invoke-VMScript -ScriptText $EDC01NetworkSettings -VM $vm -GuestCredential $DCLocalCredential
                    Invoke-VMScript -ScriptText $EDC01DNSSettings -VM $vm -GuestCredential $DCLocalCredential

                    # NOTE - The Below Sleep Command is due to it taking a few seconds for VMware Tools to read the IP Change so that we can return the below output.
                    # This is strctly informational and can be commented out if needed, but it's helpful when you want to verify that the settings defined above have been
                    # applied successfully within the VM. We use the Get-VM command to return the reported IP information from Tools at the Hypervisor Layer.
                    Start-Sleep 30
                    $DCEffectiveAddress = (Get-VM $vm).guest.ipaddress[0]
                    Write-Verbose -Message "Assigned IP for VM [$vm] is [$DCEffectiveAddress]" -Verbose

                    # Then we install the AD Role and Add the domain controller to the domain
                    Write-Verbose -Message "Getting Ready to Install Active Directory Services on $vm" -Verbose
                    Invoke-VMScript -ScriptText $InstallADRole -VM $vm -GuestCredential $DCLocalCredential
                    Write-Verbose -Message "Configuring [$vm] as a Domain Controller" -Verbose
                    Invoke-VMScript -ScriptText $AddDomainController -VM $vm -GuestCredential $DCLocalCredential
                }
            USDCEDC02 
                {         
                    Invoke-VMScript -ScriptText $EDC02NetworkSettings -VM $vm -GuestCredential $DCLocalCredential
                    Invoke-VMScript -ScriptText $EDC02DNSSettings -VM $VM -GuestCredential $DCLocalCredential

                    # NOTE - The Below Sleep Command is due to it taking a few seconds for VMware Tools to read the IP Change so that we can return the below output.
                    # This is strctly informational and can be commented out if needed, but it's helpful when you want to verify that the settings defined above have been
                    # applied successfully within the VM. We use the Get-VM command to return the reported IP information from Tools at the Hypervisor Layer.
                    Start-Sleep 30
                    $DCEffectiveAddress = (Get-VM $vm).guest.ipaddress[0]
                    Write-Verbose -Message "Assigned IP for VM [$vm] is [$DCEffectiveAddress]" -Verbose

                    # Then we install the AD Role and Add the domain controller to the domain
                    Write-Verbose -Message "Getting Ready to Install Active Directory Services on $vm" -Verbose
                    Invoke-VMScript -ScriptText $InstallADRole -VM $vm -GuestCredential $DCLocalCredential
                    Write-Verbose -Message "Configuring [$vm] as a Domain Controller" -Verbose
                    Invoke-VMScript -ScriptText $AddDomainController -VM $vm -GuestCredential $DCLocalCredential
                    Invoke-VMScript -ScriptText $installDHCP -VM $vm -GuestCredential $DCLocalCredential
                }
        }
}