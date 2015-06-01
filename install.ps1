function Install-Module($ModuleName)
{
    $SourcePath = $SourcePath = "Modules\" + $ModuleName

    if(!(Test-Path $SourcePath)) {
        Write-Error  ("{0} is missing, run create.ps1 first" -f $SourcePath)
        return;
    } 

    $TargetPath = ("{0}\Documents\WindowsPowerShell\Modules\{1}" -f $env:USERPROFILE, $ModuleName)


    # Remove items if exits
    if(Test-Path $TargetPath) {

        $message  = ('Module already exists, if you proceed, this script will replace the module at ' + $TargetPath)
        $question = 'Are you sure you want to proceed?'

        $OptYes = (New-Object Management.Automation.Host.ChoiceDescription '&Yes', ('Removes the existing module, and replaces it with the one located at ' + $SourcePath))
        $OptNo = (New-Object Management.Automation.Host.ChoiceDescription '&No','Abort, do NOT remove existing module')
        
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]($OptYes, $OptNo)

        $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)

        if ($decision -eq 0) {
            Write-Output "Removing existing module..."
            Remove-Item $TargetPath -Recurse -Force
        } else {
            Write-Output "Aborting... module is NOT installed"
            return
        }
    }

    Copy-Item $SourcePath $TargetPath -Container -Recurse -Force
    Write-Output ("Installed at location: " + $TargetPath)
    Get-DscResource -Module $ModuleName
}

Install-Module "cRemoteFile"