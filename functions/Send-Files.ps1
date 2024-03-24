function Send-Files {
    <#
    .SYNOPSIS
        Sends a target file/folder from local computer to target path on remote computers.

    .DESCRIPTION
        You can enter both paths as if they're on local filesystem, the script should cut out any drive letters and insert the \\hostname\c$ for UNC path. The script only works for C drive on target computers right now.

    .PARAMETER SourcePath
        The path of the file/folder you want to send to target computers. 
        ex: C:\users\public\desktop\test.txt, 
        ex: \\networkshare\folder\test.txt

    .PARAMETER DestinationPath
        The path on the target computer where you want to send the file/folder. 
        The script will cut off any preceding drive letters and insert \\hostname\c$ - so destination paths should be on C drive of target computers.
        ex: C:\users\public\desktop\test.txt

    .PARAMETER TargetComputer
        Target computer or computers of the function.
        Single hostname, ex: 't-client-01' or 't-client-01.domain.edu'
        Path to text file containing one hostname per line, ex: 'D:\computers.txt'
        First section of a hostname to generate a list, ex: g-labpc- will create a list of all hostnames that start with 
        g-labpc- (g-labpc-01. g-labpc-02, g-labpc-03..).

    .EXAMPLE
        copy the test.txt file to all computers in stanton open lab
        Send-Files -sourcepath "C:\Users\Public\Desktop\test.txt" -destinationpath "Users\Public\Desktop" -targetcomputer "t-client-"

    .EXAMPLE
        Get-User -ComputerName "t-client-28"

    .NOTES
        ---
        Author: albddnbn (Alex B.)
        Project Site: https://github.com/albddnbn/PSTerminalMenu
    #>
    [CmdletBinding()]
    param(        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0
        )]
        [String[]]$TargetComputer,
        [ValidateScript({
                Test-Path $_ -ErrorAction SilentlyContinue
            })]
        [string]$sourcepath,
        [string]$destinationpath
    )
    ## 1. Handle Targetcomputer input if it's not supplied through pipeline.
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

        $informational_string = ""
    }
    ## 1. Make sure no $null or empty values are submitted to the ping test or scriptblock execution.
    ## 2. Ping the single target computer one time as test before attempting remote session.
    ## 3. Use session to copy file from local computer.
    ##    Report on success/fail
    ## 4. Remove the pssession.
    PROCESS {
        ForEach ($single_computer in $TargetComputer) {
            ## 1. no empty Targetcomputer values past this point
            if ($single_computer) {
                ## 2. Ping target machine one time
                $pingreply = Test-Connection $single_computer -Count 1 -Quiet

                $file_copied = $false

                if ($pingreply) {
                    if (Test-Path "\\$single_computer\c$" -ErrorAction SilentlyContinue) {

                        $target_session = New-PSSession $single_computer
                        try {
                            Copy-Item -Path "$sourcepath" -Destination "$destinationpath" -ToSession $target_session -Recurse
                            # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Transfer of $sourcepath to $destinationpath ($single_computer) complete." -foregroundcolor green
                            $informational_string += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Transfer of $sourcepath to $destinationpath ($single_computer) complete.`n"

                            $file_copied = $true
                        }
                        catch {
                            # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Failed to copy $sourcepath to $destinationpath on $single_computer." -foregroundcolor red\
                            # $informational_string += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Failed to copy $sourcepath to $destinationpath on $single_computer.`n"
                            $null
                        }

                        Remove-PSSession $target_session
                    }        
                }
            
                if (-not $file_copied) {
                    # Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Failed to copy $sourcepath to $destinationpath on $single_computer." -foregroundcolor red
                    $informational_string += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Failed to copy $sourcepath to $destinationpath on $single_computer.`n"
                }
            
            }
        }
    }
    ## 1. Write an ending message to terminal.
    END {
        ## announcement file for when function is run as background job
        if (-not $env:PSMENU_DIR) {
            $env:PSMENU_DIR = $(pwd)
        }
        ## create simple output path to reports directory
        $thedate = Get-Date -Format 'yyyy-MM-dd'
        $DIRECTORY_NAME = 'SendFiles'
        $OUTPUT_FILENAME = 'SendFiles'
        if (-not (Test-Path "$env:PSMENU_DIR\reports\$thedate\$DIRECTORY_NAME" -ErrorAction SilentlyContinue)) {
            New-Item -Path "$env:PSMENU_DIR\reports\$thedate\$DIRECTORY_NAME" -ItemType Directory -Force | Out-Null
        }
        
        $counter = 0
        do {
            $output_filepath = "$env:PSMENU_DIR\reports\$thedate\$DIRECTORY_NAME\$OUTPUT_FILENAME-$counter.txt"
            $counter++
        } until (-not (Test-Path $output_filepath -ErrorAction SilentlyContinue))
        
        
        ## Append text to file here:
        $informational_string | Out-File -FilePath $output_filepath -Append
        # $TargetComputer | Out-File -FilePath $output_filepath -Append
        "`nThe Scan-ForApporFilepath function can be used to verify file/folders' existence on target computers." | Out-File -FilePath $output_filepath -Append -Force
        
        ## then open the file:
        Invoke-Item "$output_filepath"
        
        # read-host "`nPress [ENTER] to continue."
    }
}
