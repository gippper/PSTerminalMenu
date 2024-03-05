function Get-USBDevices {
    <#
    .SYNOPSIS
        Gets a list of USB devices connected to ComputerName device(s) and outputs one report per computer.

    .DESCRIPTION
        May also be able to use a hostname file eventually.

    .PARAMETER TargetComputer
        Target computer or computers of the function.
        Single hostname, ex: 't-client-01' or 't-client-01.domain.edu'
        Path to text file containing one hostname per line, ex: 'D:\computers.txt'
        First section of a hostname to generate a list, ex: t-pc-0 will create a list of all hostnames that start with t-pc-0. (Possibly t-pc-01, t-pc-02, t-pc-03, etc.)

    .PARAMETER OutputFile
        If set to 'n' then no file will be created.
        If blank, default filename will be created.
        Any other input will be used for creation of output folder/file names.

    .EXAMPLE
        Get-USBDevicess

    .EXAMPLE
        Get-USBDevices -Targetcomputer "computername"

    .NOTES
        ---
        Author: albddnbn (Alex B.)
        Project Site: https://github.com/albddnbn/PSTerminalMenu
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0
        )]
        [String[]]$TargetComputer,
        [String]$Outputfile
    )
    ## 1. Handle Targetcomputer input if it's not supplied through pipeline.
    ## 2. Create output filepath if necessary.
    BEGIN {
        $thedate = Get-Date -Format 'yyyy-MM-dd'
        ## 1. Handle TargetComputer input if not supplied through pipeline (will be $null in BEGIN if so)
        if ($null -eq $TargetComputer) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Detected pipeline for targetcomputer." -Foregroundcolor Yellow
        }
        else {
            if (($TargetComputer -is [System.Collections.IEnumerable]) -and ($TargetComputer -isnot [string[]])) {
                $null
                ## If it's a string - check for commas, try to get-content, then try to ping.
            }
            elseif ($TargetComputer -is [string[]]) {
                if ($TargetComputer -in @('', '127.0.0.1')) {
                    $TargetComputer = @('127.0.0.1')
                }
                elseif ($Targetcomputer -like "*,*") {
                    $TargetComputer = $TargetComputer -split ','
                }
                elseif (Test-Path $Targetcomputer -erroraction SilentlyContinue) {
                    $TargetComputer = Get-Content $TargetComputer
                }
                else {
                    $test_ping = Test-Connection -ComputerName $TargetComputer -count 1 -Quiet
                    if ($test_ping) {
                        $TargetComputer = @($TargetComputer)
                    }
                    else {
                        write-host "getting AD computer"
                        $TargetComputer = $TargetComputer
                        $TargetComputer = Get-ADComputer -Filter * | Where-Object { $_.DNSHostname -match "^$TargetComputer.*" } | Select -Exp DNShostname
                        $TargetComputer = $TargetComputer | Sort-Object 
                        read-host "target $($Targetcomputer -join ', ')" -ForegroundColor cyan  
                    }
                }
            }
            $TargetComputer = $TargetComputer | Where-object { $_ -ne $null }
            # Safety catch
            if ($null -eq $TargetComputer) {
                return
            }
        }


        ## 2. Outputfile handling - either create default, create filenames using input, or skip creation if $outputfile = 'n'.
        $str_title_var = "USBDevices"
        if ($Outputfile.tolower() -eq 'n') {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Detected 'N' input for outputfile, skipping creation of outputfile."
        }
        else {
            if (Get-Command -Name "Get-OutputFileString" -ErrorAction SilentlyContinue) {
                if ($Outputfile.toLower() -eq '') {
                    $REPORT_DIRECTORY = "$str_title_var"
                }
                else {
                    $REPORT_DIRECTORY = $outputfile            
                }
                $OutputFile = Get-OutputFileString -TitleString $REPORT_DIRECTORY -Rootdirectory $env:PSMENU_DIR -FolderTitle $REPORT_DIRECTORY -ReportOutput
            }
            else {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Function was not run as part of Terminal Menu - does not have utility functions." -Foregroundcolor Yellow
                if ($outputfile.tolower() -eq '') {
                    $iterator_var = 0
                    while ($true) {
                        $outputfile = "$env:PSMENU_DIR\reports\$thedate\$REPORT_DIRECTORY\$str_title_var-$thedate"
                        if ((Test-Path "$outputfile.csv") -or (Test-Path "$outputfile.xlsx")) {
                            $iterator_var++
                            $outputfile = "$env:PSMENU_DIR\reports\$thedate\$REPORT_DIRECTORY\$str_title_var-$([string]$iterator_var)"
                        }
                        else {
                            break
                        }
                    }
                }
            }
        }

        ## Create empty results container
        $results = [system.collections.arraylist]::new()
    }
    ## 1. Make sure no $null or empty values are submitted to the ping test or scriptblock execution.
    ## 2. Ping the single target computer one time as test before attempting remote session.
    ## 3. If machine was responsive, Collect connected usb information from computer
    PROCESS {
        ## 1.
        if ($TargetComputer) {

            ## 2. Test with ping:
            $pingreply = Test-Connection $TargetComputer -Count 1 -Quiet
            if ($pingreply) {
                ## 3. Getting USB info from target machine(s):
                $connected_usb_info = Invoke-Command -Computername $targetcomputer -scriptblock {
                    $connected_usb_devices = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^USB' } | Select FriendlyName, Class, Status

                    $connected_usb_devices
                }  | Select * -ExcludeProperty RunspaceId, PSshowcomputername

                $results.add($connected_usb_info) | out-null
            }
            else {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: $TargetComputer did not respond to one ping, skipping." -Foregroundcolor Red
    
            }
        }
    }
    ## 1. If there are results - sort them by the hostname (pscomputername) property.
    ## 2. Separate results out by computer, cycle through and create a list of connected usb devices per machine.
    ## 3. Create .csv/.xlsx reports as necessary.
    ## 4. Try to open output/report folder.
    END {
        if ($results) {
            ## 1.
            $results = $results | sort -property pscomputername
            ## 2.
            $unique_hostnames = $results | Select -exp PSComputerName -Unique
            ForEach ($unique_hostname in $unique_hostnames) {
                $computers_results = $results | where-object { $_.pscomputername -eq $unique_hostname }
                Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Exporting $outputfile-$unique_hostname.csv/$outputfile-$unique_hostname.xlsx..."
                ## 3.
                if ($outputfile.tolower() -ne 'n') {
                    if (Get-Command -Name 'Output-Reports' -ErrorAction SilentlyContinue) {
                        Output-Reports -Filepath "$outputfile-$unique_hostname" -Content $computers_results -ReportTitle "$REPORT_TITLE - $thedate" -CSVFile $true -XLSXFile $true
                    }
                    else {
                        $computers_results | Export-Csv -Path "$outputfile-$unique_hostname.csv" -NoTypeInformation -Force
                    }
                }
                else {
                    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Detected 'N' input for outputfile, skipping creation of outputfile."
                    $computers_results |  format-table -autosize
                    Read-Host "Press enter to show next computer's results"
                }
            }
            ## 4.
            if ($outputfile.tolower() -ne 'n') {

                try {
                    Invoke-Item "$($env:PSMENU_DIR)\reports\$thedate\$REPORT_TITLE"
                }
                catch {
                    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: Unable to open folder for reports."
                }
            

            }
        }
        else {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] :: No results to output."
        }
        Read-Host "Press enter to return results."
        return $results    
    }
}
