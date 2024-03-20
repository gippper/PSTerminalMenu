function Send-RebootsJob {
    <#
    .SYNOPSIS
        DIFFERENCE FROM SEND-REBOOTS - this function does not have any Read-Host 's to prompt/confirm details.
        Reboots the target computer(s) either with/without a message displayed to logged in users.

    .DESCRIPTION
        If a reboot msg isn't provided, no reboot msg/warning will be shown to logged in users.

    .PARAMETER TargetComputer
        Target computer or computers of the function.
        Single hostname, ex: 't-client-01' or 't-client-01.domain.edu'
        Path to text file containing one hostname per line, ex: 'D:\computers.txt'
        First section of a hostname to generate a list, ex: t-pc-0 will create a list of all hostnames that start with t-pc-0. (Possibly t-pc-01, t-pc-02, t-pc-03, etc.)

    .EXAMPLE
        Send-Reboot -TargetComputer "t-client-" -RebootMessage "This computer will reboot in 5 minutes." -RebootTimeInSeconds 300

    .NOTES
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
        [Parameter(Mandatory = $false)]
        [string]$RebootMessage,
        # the time before reboot in seconds, 3600 = 1hr, 300 = 5min
        [Parameter(Mandatory = $false)]
        [string]$RebootTimeInSeconds = 300
    )
    ## 1. Confirm time before reboot w/user
    ## 2. Handling of TargetComputer input
    ## 3. typecast reboot time to double to be sure
    ## 4. container for offline computers
    BEGIN {
        ## 1. Confirmation
        # $reply = Read-Host "Sending reboot in $RebootTimeInSeconds seconds, or $([double]$RebootTimeInSeconds / 60) minutes, OK? (y/n)"
        # if ($reply.ToLower() -eq 'y') {
    
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
        # }
        ## 3. typecast to double
        $RebootTimeInSeconds = [double]$RebootTimeInSeconds

        ## 4. container for offline computers
        $offline_computers = [system.collections.arraylist]::new()

    }
    ## 1. Make sure no $null or empty values are submitted to the ping test or scriptblock execution.
    ## 2. Ping the single target computer one time as test before attempting remote session and/or reboot.
    ## 3. Send reboot either with or without message
    ## 4. If machine was offline - add it to list to output at end.
    PROCESS {
        ForEach ($single_computer in $TargetComputer) {

            ## 1. empty Targetcomputer values will cause errors to display during test-connection / rest of code
            if ($single_computer) {
                ## 2. Ping test
                $ping_result = Test-Connection $single_computer -count 1 -Quiet
                if ($ping_result) {
                    if ($RebootMessage) {
                        Invoke-Command -ComputerName $single_computer -ScriptBlock {
                            shutdown  /r /t $using:reboottime /c "$using:RebootMessage"
                        }
                        $reboot_method = "Reboot w/popup msg"
                    }
                    else {
                        Restart-Computer $single_computer
                        $reboot_method = "Reboot using Restart-Computer (no Force)" # 2-28-2024
                    }
                    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Reboot sent to $single_computer using $reboot_method." -ForegroundColor Green
                }
                else {
                    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: $single_computer is offline." -Foregroundcolor Yellow
                    $offline_computers.add($single_computer) | Out-Null
                }
            }
        }
    }
    ## Output offline computers to terminal, and to file if requested
    END {

        if (-not $env:PSMENU_DIR) {
            $env:PSMENU_DIR = pwd
        }
        ## create simple output path to reports directory
        $thedate = Get-Date -Format 'yyyy-MM-dd'
        $DIRECTORY_NAME = 'SentReboots'
        $OUTPUT_FILENAME = 'SentReboots'
        if (-not (Test-Path "$env:PSMENU_DIR\reports\$thedate\$DIRECTORY_NAME" -ErrorAction SilentlyContinue)) {
            New-Item -Path "$env:PSMENU_DIR\reports\$thedate\$DIRECTORY_NAME" -ItemType Directory -Force | Out-Null
        }
        
        $counter = 0
        do {
            $output_filepath = "$env:PSMENU_DIR\reports\$thedate\$DIRECTORY_NAME\$OUTPUT_FILENAME-$counter.txt"
        } until (-not (Test-Path $output_filepath -ErrorAction SilentlyContinue))

        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: These computers were already offline." | Out-File -FilePath $output_filepath -Append
        $missed_computers | Out-File -FilePath $output_filepath -Append

        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Reboots sent to computers listed below." | Out-File -FilePath $output_filepath -Append
        $TargetComputer | Out-File -FilePath $output_filepath -Append

        Invoke-Item "$output_filepath"

        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Reboot(s) sent."
        # Read-Host "`nPress [ENTER] to continue."
    }
}

