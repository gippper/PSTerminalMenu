function Install-ApplicationJob {
    <#
	.SYNOPSIS
        Uses $env:PSMENU_DIR/deploy/applications folder to present menu to user. 
        Multiple app selections can be made, and then installed sequentially on target machine(s).
        Application folders should be PSADT folders, this function uses the traditional PSADT silent installation line to execute.
            Ex: For the Notepad++ application, the folder name is 'Notepad++', and installation script is 'Deploy-Notepad++.ps1'.

	.DESCRIPTION
        You can find some pre-made PSADT installation folders here:
        https://dtccedu-my.sharepoint.com/:f:/g/personal/abuddenb_dtcc_edu/Ervb5x-KkbdHvVcCBb9SK5kBCINk2Jtuvh240abVnpsS_A?e=kRsjKx
        Applications in the 'working' folder have been tested and are working for the most part.

	.PARAMETER TargetComputer
        Target computer or computers of the function.
        Single hostname, ex: 't-client-01' or 't-client-01.domain.edu'
        Path to text file containing one hostname per line, ex: 'D:\computers.txt'
        First section of a hostname to generate a list, ex: g-labpc- will create a list of all hostnames that start with 
        g-labpc- (g-labpc-01. g-labpc-02, g-labpc-03..).
        
    .PARAMETER AppName
        If supplied, the function will look for a folder in $env:PSMENU_DIR\deploy\applications with a name that = $AppName.
        If not supplied, the function will present menu of all folders in $env:PSMENU_DIR\deploy\applications to user.

	.EXAMPLE
        Run installation(s) on all hostnames starting with 's-a231-':
		Install-Application -TargetComputer 's-a231-'

    .EXAMPLE
        Run installation(s) on local computer:
        Install-Application

    .EXAMPLE
        Install Chrome on all hostnames starting with 's-c137-'.
        Install-Application -Targetcomputer 's-c137-' -AppName 'Chrome'

	.NOTES
        PSADT Folders: https://dtccedu-my.sharepoint.com/:f:/g/personal/abuddenb_dtcc_edu/Ervb5x-KkbdHvVcCBb9SK5kBCINk2Jtuvh240abVnpsS_A?e=kRsjKx
        ---
        Author: albddnbn (Alex B.)
        Project Site: https://github.com/albddnbn/PSTerminalMenu
    #>
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0
        )]
        [String[]]$TargetComputer,
        [ValidateScript({
                if (Test-Path "$env:PSMENU_DIR\deploy\applications\$_" -ErrorAction SilentlyContinue) {
                    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Found $($_) in $env:PSMENU_DIR\deploy\applications." -Foregroundcolor Green
                    return $true
                }
                else {
                    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: $($_) not found in $env:PSMENU_DIR\deploy\applications." -Foregroundcolor Red
                    return $false
                }
            })]
        [Parameter(
            Mandatory = $true )]
        [string]$AppName,
        [String]$DoNotDisturb = 'y'
    )
    ## 1. Handle Targetcomputer input if it's not supplied through pipeline.
    ## 2. If AppName parameter was not supplied, apps chosen through menu will be installed on target machine(s).
    ##    - menu presented uses the 'PS-Menu' module: https://github.com/chrisseroka/ps-menu
    ## 3. Define scriptblock - installs specified app using PSADT folder/script on local machine.
    ## 4. Prompt - should this script skip over computers that have users logged in?
    ## 5. create empty containers for reports:
    BEGIN {
        ## 1. Handle TargetComputer input if not supplied through pipeline (will be $null in BEGIN if so)
        if ($null -eq $TargetComputer) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Detected pipeline for targetcomputer." -Foregroundcolor Yellow
        }
        else {
            ## Assigns localhost value
            if ($TargetComputer -in @('', '127.0.0.1', 'localhost')) {
                $TargetComputer = @('127.0.0.1')
            }
            ## If input is a file, gets content
            elseif ($(Test-Path $Targetcomputer -erroraction SilentlyContinue) -and ($TargetComputer.count -eq 1)) {
                $TargetComputer = Get-Content $TargetComputer
            }
            ## A. Separates any comma-separated strings into an array, otherwise just creates array
            ## B. Then, cycles through the array to process each hostname/hostname substring using LDAP query
            else {
                ## A.
                if ($Targetcomputer -like "*,*") {
                    $TargetComputer = $TargetComputer -split ','
                }
                else {
                    $Targetcomputer = @($Targetcomputer)
                }
        
                ## B. LDAP query each TargetComputer item, create new list / sets back to Targetcomputer when done.
                $NewTargetComputer = [System.Collections.Arraylist]::new()
                foreach ($computer in $TargetComputer) {
                    ## CREDITS FOR The code this was adapted from: https://intunedrivemapping.azurewebsites.net/DriveMapping
                    if ([string]::IsNullOrEmpty($env:USERDNSDOMAIN) -and [string]::IsNullOrEmpty($searchRoot)) {
                        Write-Error "LDAP query `$env:USERDNSDOMAIN is not available!"
                        Write-Warning "You can override your AD Domain in the `$overrideUserDnsDomain variable"
                    }
                    else {
        
                        # if no domain specified fallback to PowerShell environment variable
                        if ([string]::IsNullOrEmpty($searchRoot)) {
                            $searchRoot = $env:USERDNSDOMAIN
                        }
                        $searcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher
                        $searcher.Filter = "(&(objectclass=computer)(cn=$computer*))"
                        $searcher.SearchRoot = "LDAP://$searchRoot"
                        [void]$searcher.PropertiesToLoad.Add("name")
                        $list = [System.Collections.Generic.List[String]]@()
                        $results = $searcher.FindAll()
                        foreach ($result in $results) {
                            $resultItem = $result.Properties
                            [void]$List.add($resultItem.name)
                        }
                        $NewTargetComputer += $list
                    }
                }
                $TargetComputer = $NewTargetComputer
            }
            $TargetComputer = $TargetComputer | Where-object { $_ -ne $null } | Select -Unique
            # Safety catch
            if ($null -eq $TargetComputer) {
                return
            }
        }
        
        ## 2. If AppName parameter was not supplied, apps chosen through menu will be installed on target machine(s).

        $chosen_apps = $AppName -split ','
        if ($chosen_apps -is [string]) {
            $chosen_apps = @($chosen_apps)
        }
        # validate the applist:
        ForEach ($single_app in $chosen_apps) {
            if (-not (Test-Path "$env:PSMENU_DIR\deploy\applications\$single_app")) {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: $single_app not found in $env:PSMENU_DIR\deploy\applications." -Foregroundcolor Red
                Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Ending function." -Foregroundcolor Red
                return
            }
        }
        
        ## 3. Define scriptblock - installs specified app using PSADT folder/script on local machine.
        $install_local_psadt_block = {
            param(
                $app_to_install,
                $do_not_disturb
            )
            ## Remove previous psadt folders:
            # Remove-Item -Path "C:\temp\$app_to_install" -Recurse -Force -ErrorAction SilentlyContinue
            # Safety net since psadt script silent installs close app-related processes w/o prompting user
            $check_for_user = (get-process -name 'explorer' -includeusername -erroraction silentlycontinue).username
            if ($check_for_user) {
                if ($($do_not_disturb) -eq 'y') {
                    Write-Host "[$env:COMPUTERNAME] :: Skipping, $check_for_user logged in."
                    Continue
                }
            }
            # get the installation script
            $Installationscript = Get-ChildItem -Path "C:\temp" -Filter "Deploy-$app_to_install.ps1" -File -Recurse -ErrorAction SilentlyContinue
            # unblock files:
            Get-ChildItem -Path "C:\temp" -Recurse | Unblock-File
            # $AppFolder = Get-ChildItem -Path 'C:\temp' -Filter "$app_to_install" -Directory -Erroraction silentlycontinue
            if ($Installationscript) {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$env:COMPUTERNAME] :: Found $($Installationscript.Fullname), installing."
                Set-Location "$($Installationscript.DirectoryName)"
                Powershell.exe -ExecutionPolicy Bypass ".\Deploy-$($app_to_install).ps1" -DeploymentType "Install" -DeployMode "Silent"
            }
            else {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$env:COMPUTERNAME] :: ERROR - Couldn't find the app deployment script!" -Foregroundcolor Red
            }
        }
        Clear-Host

        ## 4. Prompt - should this script skip over computers that have users logged in?
        ##    - script runs 'silent' installation of PSADT - this means installations will likely close the app / associated processes
        ##      before uninstalling / installing. This could disturb users.
        $skip_pcs = $DoNotDisturb.ToLower()
    
        ## 5. create empty containers for reports:
        ## computers that were unresponsive
        ## apps that weren't able to be installed (weren't found in deployment folder for some reason.)
        ## - If they were presented in menu / chosen, apps should definitely be in deployment folder, though.
        $unresponsive_computers = [system.collections.arraylist]::new()
        $skipped_applications = [system.collections.arraylist]::new()
    
    
    }
    ## 1. Make sure no $null or empty values are submitted to the ping test or scriptblock execution.
    ## 2. Ping the single target computer one time as test before attempting remote session.
    ## 3. If machine was responsive, cycle through chosen apps and run the local psadt install scriptblock for each one,
    ##    on each target machine.
    ##    3.1 --> Check for app/deployment folder in ./deploy/applications, move on to next installation if not found
    ##    3.2 --> Copy PSADT folder to target machine/session
    ##    3.3 --> Execute PSADT installation script on target machine/session
    ##    3.4 --> Cleanup PSADT folder in C:\temp
    PROCESS {
        ForEach ($single_computer in $TargetComputer) {

            ## 1. empty Targetcomputer values will cause errors to display during test-connection / rest of code
            if ($single_computer) {
                ## 2. Ping test
                $ping_result = Test-Connection $single_computer -count 1 -Quiet
                if ($ping_result) {
                    if ($single_computer -eq '127.0.0.1') {
                        $single_computer = $env:COMPUTERNAME
                    }
                    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: $single_computer responded to one ping, proceeding with installation(s)." -Foregroundcolor Green

                    ## create sesion
                    $single_target_session = New-PSSession $single_computer
                    ## 3. Install chosen apps by creating remote session and cycling through list
                    ForEach ($single_application in $chosen_apps) {
                        ## 3.1 Check for app/deployment folder in ./deploy/applications
                        $DeploymentFolder = $ApplicationList | Where-Object { $_.Name -eq $single_application }
                        if (-not $DeploymentFolder) {
                            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: $single_application not found in $env:PSMENU_DIR\deploy\applications." -Foregroundcolor Red
                            $skipped_applications.Add($single_application) | Out-Null
                            continue
                        }

                        ## Make sure there isn't an existing deployment folder on target machine:
                        Invoke-Command -Session $single_target_session -scriptblock {
                            Remove-Item -Path "C:\temp\$($using:DeploymentFolder.Name)" -Recurse -Force -ErrorAction SilentlyContinue
                        }

                        ## 3.2 Copy PSADT folder to target machine/session
                        Copy-Item -Path "$($DeploymentFolder.fullname)" -Destination "C:\temp\$($DeploymentFolder.Name)" -ToSession $single_target_session -Recurse -Force
                
                        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: $($DeploymentFolder.name) copied to $single_computer."
                        ## 3.3 Execute PSADT installation script on target mach8ine/session
                        Invoke-Command -Session $single_target_session -scriptblock $install_local_psadt_block -ArgumentList $single_application, $skip_pcs
                        # Start-Sleep -Seconds 1
                        ## 3.4 Cleanup PSADT folder in temp
                        $folder_to_delete = "C:\temp\$($DeploymentFolder.Name)"
                        Invoke-Command -Session $single_target_session -command {
                            Remove-Item -Path "$($using:folder_to_delete)" -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                else {
                    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Ping fail from $single_computer - added to 'unresponsive list'." -Foregroundcolor Red
                    $unresponsive_computers.Add($single_computer) | Out-Null
                }
            }
        }
    }
    ## 1. Open the folder that will contain reports if necessary.
    END {

        ## create simple output path to reports directory
        if (-not (Test-Path "$env:PSMENU_DIR\reports\$thedate\installs" -ErrorAction SilentlyContinue)) {
            New-Item -Path "$env:PSMENU_DIR\reports\$thedate\installs" -ItemType Directory -Force | Out-Null
        }


        $output_filepath = "$env:PSMENU_DIR\reports\$thedate\installs\InstallApps-$(Get-Date -Format 'yyyy-MM-dd').txt"
        $counter = 0
        do {
            $output_filepath = "$env:PSMENU_DIR\reports\$thedate\installs\InstallApps-$(Get-Date -Format 'yyyy-MM-dd-HH-mm')-$counter.txt"
        } until (-not (Test-Path $output_filepath -ErrorAction SilentlyContinue))

        if ($unresponsive_computers) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Unresponsive computers:" -Foregroundcolor Yellow
            $unresponsive_computers | Sort-Object
        }
        if ($skipped_applications) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Skipped applications:" -Foregroundcolor Yellow
            $skipped_applications | Sort-Object
        }
        #Read-Host "Press enter to continue."
        ## Output announcement to completedjobs directory
        $Announcement = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Install-Application for $AppName with do not disturb set to $skip_pcs on $($TargetComputer -join ', ') completed."

        $Announcement += "`nUnresponsive Computers"
        $Announcement += $unresponsive_computers | Sort-Object
        $Announcement += "`nSkipped Applications"
        $Announcement += $skipped_applications | Sort-Object
        $Announcement | Out-File "$output_filepath" -Append
        ## open the file to let user know that function (as background job) has completed.
        Invoke-Item "$output_filepath"
    }
    
}