function Remove-Module($ModuleName)
{
    $TargetPath = ("{0}\Documents\WindowsPowerShell\Modules\{1}" -f $env:USERPROFILE, $ModuleName)

    if(!(Test-Path $TargetPath)) {
        Write-Output "Looks like it's already removed"
        return
    }
    
    Remove-Item $TargetPath -Recurse -Force
    Write-Output ("Removed module from location: " + $TargetPath)
}

Remove-Module "cRemoteFile"