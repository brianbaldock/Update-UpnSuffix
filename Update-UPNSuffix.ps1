<#
    .DESCRIPTION
        This script updates the User Principal Name (UPN) suffix for users in your domain based on their existing UPN prefix and a new domain suffix.
        This script is expecting that the users have an alternateID attribute somewhere that contains their routable UPN prefix and suffix (e.g. user.name@domain.com which is stored in extensionAttribute1 or some other attribute).
        This script also looks to you to specify a backup attribute that will store the old UPN value in case you need to revert the change. 
        You can also specify a subdomain that you'd like to add but this subdomain must be preemptively added to the forest upn suffixes or else the script will skip the user.
        You can also specify a list of excluded suffixes incase you are looking to only target a specific subset of domains suffixes in your forest.

        This script contains two "modes" Update and Restore. 
        Update Mode is the default state and will replace the UPN value with the value of the specified "AlternateIDAttribute".
        Restore mode is an alternative mode that lets you walk back from a previous Update mode execution. It will restore the previous UPN value with the value stored in the "BackupAttribute".
    
    .NOTES
        Run with -verbose for console output, otherwise the script runs silently unless it encounters an error and logs to the log file.
    
    .NOTES
        The $logPath attribute will automatically create a new log at the specified path with the date and time appended to the file name. The user running the script will need the appropriate permissions to create a new file at the specified path.

    .NOTES
        The sample scripts are not supported under any Microsoft standard support 
        program or service. The sample scripts are provided AS IS without warranty  
        of any kind. Microsoft further disclaims all implied warranties including,  
        without limitation, any implied warranties of merchantability or of fitness for 
        a particular purpose. The entire risk arising out of the use or performance of  
        the sample scripts and documentation remains with you. In no event shall 
        Microsoft, its authors, or anyone else involved in the creation, production, or 
        delivery of the scripts be liable for any damages whatsoever (including, 
        without limitation, damages for loss of business profits, business interruption, 
        loss of business information, or other pecuniary loss) arising out of the use 
        of or inability to use the sample scripts or documentation, even if Microsoft 
        has been advised of the possibility of such damages.

        Author: Brian Baldock - brian.baldock@microsoft.com

    .COMPONENT
        - Active Directory PowerShell Module
        - You must have the necessary privileges to read and update user attributes in Active Directory.

    .PARAMETER csvPath
        Mandatory Parameter - The path to the CSV file containing user information.

    .PARAMETER logPath
        Mandatory Parameter - The path to the log file where changes will be recorded.

    .PARAMETER Subdomain
        Optional Parameter - The subdomain you would like to add to the new UPN (e.g Subdomain.domain.com).

    .PARAMETER ExcludedSuffixes
        Optional Parameter - A comma separated list in quotes of suffixes you would like to exclude from processing. If a user has one of these it is skipped (e.g 'domain.com,contoso.com')")

    .PARAMETER AlternateIDAttribute
        Mandatory Parameter - The name of the attribute (usually AlternateID) you want to base the new UPN on.

    .PARAMETER BackupAttribute
        Mandatory Parameter - The name of the attribute where you want to store the old UPN value

    .EXAMPLE
        .\Update-UPNSuffix.ps1 -csvPath "C:\Users.csv" -logPath "C:\" -Subdomain "Subdomain" -AlternateIDAttribute "AlternateIDAttribute" -BackupAttribute "extensionAttribute6" -ExcludedSuffixes "domain.com,contoso.com"

    .EXAMPLE
        .\Update-UPNSuffix.ps1 -csvPath "C:\Users.csv" -logPath "C:\" -AlternateIDAttribute "AlternateIDAttribute" -BackupAttribute "extensionAttribute6"
    
    .EXAMPLE
        .\Update-UPNSuffix.ps1 -Restore -csvPath "C:\Users.csv" -logPath "C:\" -RestoreAttribute "extensionAttribute6"

#>

#Requires -Modules ActiveDirectory

[CmdletBinding(DefaultParameterSetName='Update')]
param(
    [Parameter(Mandatory=$True,ParameterSetName='Update',Position=0,HelpMessage="Please enter the path to the csv file (e.g C:\Users.csv)")]
    [Parameter(Mandatory=$True,ParameterSetName='Restore',Position=2,HelpMessage="Please enter the path to the csv file (e.g C:\Users.csv)")]
    [string]$csvPath,

    [Parameter(Mandatory=$True,ParameterSetName='Update',Position=1,HelpMessage="Please enter the log path (e.g C:\Log.csv)")]
    [Parameter(Mandatory=$True,ParameterSetName='Restore',Position=3,HelpMessage="Please enter the log path (e.g C:\Log.csv)")]
    [string]$logPath,

    [Parameter(Mandatory=$True,ParameterSetName='Update',Position=2,HelpMessage="Please enter the name of the attribute (usually AlternateID) you want to overwrite the UPN value with (e.g AlternateID)")]
    [string]$AlternateIDAttribute,

    [Parameter(Mandatory=$True,ParameterSetName='Update',Position=3,HelpMessage="Please enter the name of the attribute you want to use to store the backup of the current UPN value (e.g extensionAttribute6)")]
    [string]$BackupAttribute,
    
    [Parameter(Mandatory=$False,ParameterSetName='Update',Position=4,HelpMessage="Please enter the subdomain you would like to add to the new UPN, do not include the full domain (e.g Subdomain)")]
    [string]$Subdomain,

    [Parameter(Mandatory=$False,ParameterSetName='Update',Position=5,HelpMessage="Please enter a comma separated list in quotes of suffixes you would like to exclude from processing. If a user has one of these it is skipped (e.g 'domain.com,contoso.com')")]
    [string]$ExcludedSuffixes,

    [Parameter(Mandatory=$True,ParameterSetName='Restore',Position=0,HelpMessage="This parameter sets the script into restore mode in case you need to restore your UPN to the previous version after running this script.")]
    [switch]$Restore,

    [Parameter(Mandatory=$False,ParameterSetName='Restore',Position=1,HelpMessage="Please enter the name of the Attribute that contains the previous UPN value you want to restore from (e.g extensionAttribute6)")]
    [string]$RestoreAttribute
)

begin{
    # Test Log File Path
    try{
        $Date = Get-Date -Format "yyyy-MM-dd_HH-mm.fff"
        New-Item -Path $logPath -ItemType File -Name log_$($Date).csv -ErrorAction Stop
        $logPath = "$($logPath)log_$($Date).csv"
        Add-Content $logPath "Date-Changed,Mode,Name,sAMAccountName,OldUPN,NewUPN,Status,Details"
    }
    catch{
        Write-Error "Unable to access log file"
    }
}

process{
    # Get forest UPN suffixes
    try{
        Write-Verbose "Reading forest UPN suffixes."
        $DomainSuffixes = (Get-ADForest).UPNSuffixes
    }
    catch{
        Write-Error "Unable to read UPN suffixes from forest. Please check your permissions"
        $Status = "Error"
        $Details = "Unable to read UPN Suffixes from forest. Please check your permissions."
    }

    # Import CSV
    try{
        $Users = Import-Csv -Path $csvPath
    }
    catch{
        Write-Error "Unable to import CSV file. Please check the path and format of the file."
        $Status = "Error"
        $Details = "Unable to import CSV file. Please check the path and format of the file."
    }

    if ($PSCmdlet.ParameterSetName -eq 'Restore'){
        #Restore Mode
        Write-Verbose "Entering Restore Mode"
        $RestoreMode = "Restore"
        foreach($User in $Users){
            # Check if user exists in AD
            try {
                Write-Verbose "Checking if $($User.SamAccountName) exists in Active Directory."
                $ADUser = Get-ADUser -Identity $User.SamAccountName -Properties $RestoreAttribute, UserPrincipalName
            }
            catch {
                Write-Error "Unable to find user $($User.SamAccountName) in Active Directory."
                $Status = "Error"
                $Details = "Unable to find user $($User.SamAccountName) in Active Directory."
            }
            # Date variable for logging
            $Date = Get-Date -Format "yyyy/MM/dd HH:mm:ss"

            # Variable to store old UPN value
            $OldUPN = $ADUser.UserPrincipalName

            # Check if backup attribute is not null
            if ($ADUser.$RestoreAttribute) {
                Write-Verbose "UPN restore is possible for $($ADUser.Name). Backup attribute $($RestoreAttribute) is populated with $($ADUser.$RestoreAttribute)."
                Write-Verbose "Attempting to restore the UPN for $($ADUser.Name) from $($RestoreAttribute): $($ADUser.$RestoreAttribute)."
                try{
                    Set-ADUser -Identity $ADUser.SamAccountName -UserPrincipalName $ADUser.$RestoreAttribute
                    # Re-query the UserPrincipalName attribute to ensure the update was successful
                    $UpdatedUPN = ((Get-ADUser -Identity $ADUser.SamAccountName -Properties UserPrincipalName).UserPrincipalName) 
                    if ($UpdatedUPN = ($ADUser.$RestoreAttribute)) {
                        Write-Verbose "UPN successfully restored from $($RestoreAttribute) for $($ADUser.Name), updated value: $($UpdatedUPN)"
                        Write-Verbose "Clearing the value of $($RestoreAttribute) for $($ADUser.Name)"
                        try{
                            Set-ADUser -Identity $ADUser.SamAccountName -Clear $RestoreAttribute
                            $Status = "Success"
                            $Details = "UPN successfully restored from $($RestoreAttribute) for $($ADUser.Name), updated value: $($UpdatedUPN) and cleared $($RestoreAttribute)"
                        }
                        catch{
                            Write-Verbose "Unable to clear $($RestoreAttribute) for $($ADUser.Name) and the restored UPN value may not be valid. Current value: $($UpdatedUPN)"
                            $Status = "Fail"
                            $Details = "Unable to clear $($RestoreAttribute) for $($ADUser.Name) and the restored UPN value may not be valid. Current value: $($UpdatedUPN)"
                        }
                    }
                    else{
                        Write-Verbose "UPN restore failed for $($ADUser.Name), the $($RestoreAttribute) attribute may not be populated with a valid UPN value. Current value: $($ADUser.$RestoreAttribute)"
                        $Status = "Fail"
                        $Details = "UPN restore failed for $($ADUser.Name), the $($RestoreAttribute) attribute may not be populated with a valid UPN value. Current value: $($ADUser.$RestoreAttribute)"
                    }
                }
                catch{
                    Write-Verbose "UPN restore failed for $($ADUser.Name), the $($RestoreAttribute) attribute may not be populated with a valid UPN value. Current value: $($ADUser.$RestoreAttribute)"
                    $Status = "Fail"
                    $Details = "UPN restore failed for $($ADUser.Name), the $($RestoreAttribute) attribute may not be populated with a valid UPN value. Current value: $($ADUser.$RestoreAttribute)"
                }
            }
            # Write to log file
            Write-Verbose "Log file updated."
            $LogEntry = "$($Date),$($RestoreMode),$($ADUser.Name),$($User.sAMAccountName),$($OldUPN),$($NewUPN),$($Status),$($Details)"
            Add-Content -Path $logPath -Value $LogEntry
        }
    }
    else{
        #Update Mode
        $UpdateMode = "Update"
        Write-Verbose "Executing Update (default) Mode"
        foreach($User in $Users){
            # Check if user exists in AD
            try {
                Write-Verbose "Checking if $($User.SamAccountName) exists in Active Directory."
                $ADUser = Get-ADUser -Identity $User.SamAccountName -Properties $AlternateIDAttribute, $BackupAttribute, UserPrincipalName
            }
            catch {
                Write-Error "Unable to find user $($User.SamAccountName) in Active Directory."
                $Status = "Error"
                $Details = "Unable to find user $($User.SamAccountName) in Active Directory."
            }
            # Date variable for logging
            $Date = Get-Date -Format "yyyy/MM/dd HH:mm:ss"

            # Variable to store old UPN value
            $OldUPN = $ADUser.UserPrincipalName

            # Extract domain suffix from existing UPN (Attribute specified by parameter)
            $DomainSuffixExtraction = $ADUser.$AlternateIDAttribute.Split("@")[1]

            # Check if domain suffix is in the exclusion list
            if ($ExcludedSuffixes){
                Write-Verbose "Domain suffix exclusions are specified, checking if user suffix is in the list."
                if (($ADUser.UserPrincipalName.Split("@")[1]) -in $ExcludedSuffixes) {
                    Write-Verbose "Domain suffix $($ADUser.UserPrincipalName.Split("@")[1]) is in the exclusion list, UPN will not be updated."
                    $Status = "Error"
                    $Details = "Domain suffix $($ADUser.UserPrincipalName.Split("@")[1]) is in the exclusion list, UPN will not be updated."
                }
                else{
                    if ($Subdomain) {
                        Write-Verbose "Subdomain specified. New UPN will be $($Subdomain).$($DomainSuffixExtraction). Checking if new UPN exists in Forest suffixes."
                        $NewDomainSuffix = "$($Subdomain).$($DomainSuffixExtraction)"
                        if ($NewDomainSuffix -notin $DomainSuffixes) {
                            Write-Error "UPN change skipped for $($ADUser.Name). New domain suffix with subdomain ($($NewDomainSuffix)) not in forest UPN suffixes."
                            $Status = "Skipped"
                            $Details = "UPN change skipped for $($ADUser.Name). New domain suffix with subdomain ($($NewDomainSuffix)) not in forest UPN suffixes."
                        }
                        else{
                            $RegenFullDomain = "$($Subdomain).$($DomainSuffixExtraction)"
                            $NewUPN = "$($ADUser.$AlternateIDAttribute.Split("@")[0])@$($RegenFullDomain)"
                            try{
                                Set-ADUser -Identity $ADUser.SamAccountName -UserPrincipalName $NewUPN -Replace @{$BackupAttribute = $OldUPN}
                                Write-Verbose "UPN successfully changed for $($ADUser.Name), updated value: $($NewUPN)"
                                $Status = "Success"
                                $Details = "UPN successfully updated for $($ADUser.Name), updated value: $($NewUPN)"
                            }
                            catch{
                                Write-Verbose "UPN change failed for $($ADUser.Name)"
                                $Status = "Fail"
                                $Details = "UPN change failed for $($ADUser.Name) the UPN value stored in $($AlternateIDAttribute) may not be valid. Current value: $($ADUser.$AlternateIDAttribute)"
                            }
                        }
                    }
                    else{
                        if ($ADUser.$BackupAttribute) {
                            Write-Verbose "UPN change skipped for $($ADUser.Name). Backup attribute already set."
                            $Status = "Skipped"
                            $Details = "$($ADUser.Name) already has value: $($ADUser.$BackupAttribute) for $($BackupAttribute). UPN may have previously been modified. No change applied."
                        }
                        else{
                            if (($ADUser.$AlternateIDAttribute.Split("@")[1]) -notin $DomainSuffixes) {
                                Write-Error "UPN change skipped for $($ADUser.Name). Domain suffix $($ADUser.$AlternateIDAttribute.Split("@")[1]) not in forest UPN suffixes."
                                $Status = "Skipped"
                                $Details = "UPN change skipped for $($ADUser.Name). Domain suffix $($ADUser.$AlternateIDAttribute.Split("@")[1]) not in forest UPN suffixes."
                            }
                            else{
                                Write-Verbose "Subdomain not specified. New UPN will replicate the $($AlternateIDAttribute) value as defined by parameter."
                                $NewUPN = "$($ADUser.$AlternateIDAttribute)"
                                try{
                                    Set-ADUser -Identity $ADUser.SamAccountName -UserPrincipalName $NewUPN -Replace @{$BackupAttribute = $OldUPN}
                                    Write-Verbose "UPN successfully changed for $($ADUser.Name), updated value: $($NewUPN)"
                                    $Status = "Success"
                                    $Details = "UPN successfully updated for $($ADUser.Name), updated value: $($NewUPN)"
                                }
                                catch{
                                    Write-Verbose "UPN change failed for $($ADUser.Name)"
                                    $Status = "Fail"
                                    $Details = "UPN change failed for $($ADUser.Name) the UPN value stored in $($AlternateIDAttribute) may not be valid. Current value: $($ADUser.$AlternateIDAttribute)"
                                }
                            }
                        }
                    }
                }
            }
            else{
                if ($Subdomain) {
                    Write-Verbose "Subdomain specified. New UPN will be $($Subdomain).$($DomainSuffixExtraction). Checking if new UPN exists in Forest suffixes."
                    $NewDomainSuffix = "$($Subdomain).$($DomainSuffixExtraction)"
                    if ($NewDomainSuffix -notin $DomainSuffixes) {
                        Write-Error "UPN change skipped for $($ADUser.Name). New domain suffix with subdomain ($($NewDomainSuffix)) not in forest UPN suffixes."
                        $Status = "Skipped"
                        $Details = "UPN change skipped for $($ADUser.Name). New domain suffix with subdomain ($($NewDomainSuffix)) not in forest UPN suffixes."
                    }
                    else{
                        $RegenFullDomain = "$($Subdomain).$($DomainSuffixExtraction)"
                        $NewUPN = "$($ADUser.$AlternateIDAttribute.Split("@")[0])@$($RegenFullDomain)"
                        try{
                            Set-ADUser -Identity $ADUser.SamAccountName -UserPrincipalName $NewUPN -Replace @{$BackupAttribute = $OldUPN}
                            Write-Verbose "UPN successfully changed for $($ADUser.Name), updated value: $($NewUPN)"
                            $Status = "Success"
                            $Details = "UPN successfully updated for $($ADUser.Name), updated value: $($NewUPN)"
                        }
                        catch{
                            Write-Verbose "UPN change failed for $($ADUser.Name)"
                            $Status = "Fail"
                            $Details = "UPN change failed for $($ADUser.Name) the UPN value stored in $($AlternateIDAttribute) may not be valid. Current value: $($ADUser.$AlternateIDAttribute)"
                        }
                    }
                }
                else{
                    if ($ADUser.$BackupAttribute) {
                        Write-Verbose "UPN change skipped for $($ADUser.Name). Backup attribute already set."
                        $Status = "Skipped"
                        $Details = "$($ADUser.Name) already has value: $($ADUser.$BackupAttribute) for $($BackupAttribute). UPN may have previously been modified. No change applied."
                    }
                    else{
                        if (($ADUser.$AlternateIDAttribute.Split("@")[1]) -notin $DomainSuffixes) {
                            Write-Error "UPN change skipped for $($ADUser.Name). Domain suffix $($ADUser.$AlternateIDAttribute.Split("@")[1]) not in forest UPN suffixes."
                            $Status = "Skipped"
                            $Details = "UPN change skipped for $($ADUser.Name). Domain suffix $($ADUser.$AlternateIDAttribute.Split("@")[1]) not in forest UPN suffixes."
                        }
                        else{
                            Write-Verbose "Subdomain not specified. New UPN will replicate the $($AlternateIDAttribute) value as defined by parameter."
                            $NewUPN = "$($ADUser.$AlternateIDAttribute)"
                            try{
                                Set-ADUser -Identity $ADUser.SamAccountName -UserPrincipalName $NewUPN -Replace @{$BackupAttribute = $OldUPN}
                                Write-Verbose "UPN successfully changed for $($ADUser.Name), updated value: $($NewUPN)"
                                $Status = "Success"
                                $Details = "UPN successfully updated for $($ADUser.Name), updated value: $($NewUPN)"
                            }
                            catch{
                                Write-Verbose "UPN change failed for $($ADUser.Name)"
                                $Status = "Fail"
                                $Details = "UPN change failed for $($ADUser.Name) the UPN value stored in $($AlternateIDAttribute) may not be valid. Current value: $($ADUser.$AlternateIDAttribute)"
                            }
                        }
                    }
                }
            }
            # Write to log file
            Write-Verbose "Log file updated."
            $LogEntry = "$($Date),$($UpdateMode),$($ADUser.Name),$($User.sAMAccountName),$($OldUPN),$($NewUPN),$($Status),$($Details)"
            Add-Content -Path $logPath -Value $LogEntry
        }
    }   
}