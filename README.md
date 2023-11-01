# Update-UpnSuffix
A script that updates the User Principal Name (UPN) suffix for users in your domain based on their existing UPN prefix and a new domain suffix. 
You can also specify a subdomain that you'd like to add. Run with -verbose for console output, otherwise the script runs silently unless it encounters an error.

This script contains two "modes" Update and Restore. Update is the default state and will replace the UPN value with the value of the specified "AlternateIDAttribute".
The Restore mode is an alternative mode that lets you walk back from a previous Update mode execution. It will restore the previous UPN value with the value stored in the "BackupAttribute".

# Supportability
The scripts, samples, and tools made available here are provided as-is. These resources are developed in partnership with the community. As such, support is not available. If you find an issue or have questions please reach out through the issues list and I'll do my best to assist, however there is no associated SLA. Use at your own risk.

## NOTES
    Run with -verbose for console output, otherwise the script runs silently unless it encounters an error and logs to the log file.

    The $logPath attribute will automatically create a new log at the specified path with the date and time appended to the file name. The user running the script will need the appropriate permissions to create a new file at the specified path.

## REQUIREMENTS
    - Active Directory PowerShell Module
    - You must have the necessary privileges to read and update user attributes in Active Directory.

## PARAMETER csvPath
    Mandatory Parameter - The path to the CSV file containing user information.

## PARAMETER logPath
    Mandatory Parameter - The path to the log file where changes will be recorded.

## PARAMETER Subdomain
    Optional Parameter - The subdomain you would like to add to the new UPN (e.g Subdomain.domain.com).

## PARAMETER ExcludedSuffixes
    Optional Parameter - A comma separated list in quotes of suffixes you would like to exclude from processing. If a user has one of these it is skipped (e.g 'domain.com,contoso.com')")

## PARAMETER AlternateIDAttribute
    Mandatory Parameter - The name of the attribute (usually AlternateID) you want to base the new UPN on.

## PARAMETER BackupAttribute
    Mandatory Parameter - The name of the attribute where you want to store the old UPN value

## EXAMPLE
    .\Update-UPNSuffix.ps1 -csvPath "C:\Users.csv" -logPath "C:\" -Subdomain "Subdomain" -AlternateIDAttribute "AlternateIDAttribute" -BackupAttribute "extensionAttribute6" -ExcludedSuffixes "domain.com,contoso.com"

## EXAMPLE
    .\Update-UPNSuffix.ps1 -csvPath "C:\Users.csv" -logPath "C:\" -AlternateIDAttribute "AlternateIDAttribute" -BackupAttribute "extensionAttribute6"

## Example
    .\Update-UPNSuffix.ps1 -Restore -csvPath "C:\Users.csv" -logPath "C:\" -RestoreAttribute "extensionAttribute6"