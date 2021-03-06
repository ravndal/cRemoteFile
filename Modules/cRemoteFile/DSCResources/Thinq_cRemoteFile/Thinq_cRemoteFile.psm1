function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Target,

		[parameter(Mandatory = $true)]
		[System.String]
		$SourceUri
	)

	$returnValue = @{
		Target = $Target
		Exists = (Test-Path $Target)
		Source = $SourceUri
	}

	$returnValue
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Target,

		[parameter(Mandatory = $true)]
		[System.String]
		$SourceUri,

		[System.String]
		$Hash,

		[ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512")]
		[System.String]
		$HashAlgorithm = "SHA256"
	)

	$uri = $SourceUri -as [System.URI]


	if($uri.Scheme -eq $null) {
		Write-Error "Unable to handle '$SourceUri', can't decide what kind of source this is"
		return		
	}

    # Check if Target already exists, if does, verify the hash
	if(Test-Path $Target) {

		Write-Verbose "Target '$Target' file already exists"

		if($Hash -ne $null) {
			Write-Verbose "File exits, and hash is provided, will verifying hash on '$Target'"
			$targetHash = (Get-FileHash -Path $Target -Algorithm $HashAlgorithm).Hash
			
			if($targetHash -eq $Hash) {
				Write-Verbose "Hash is a match, everything is ok"
				return
			} 
			else {
				Write-Verbose "Expected '$Hash' but got '$targetHash', backing up existing file."
                
	    		$fi = Get-Item $Target
	    		$temp = $Target.Replace($fi.Extension, "." + $targetHash + $fi.Extension)

	    		if(Test-Path $temp) {
	    			Write-Verbose "Backup already exists"
	    			Remove-Item -Path $Target -Force
	    		} else {
	    			Write-Verbose "Moved existing file to '$temp'"
                    Move-Item -Path $Target -Destination $temp -Force
	    		}
			}
		} else {
			Write-Verbose "File exists, but no hash is provided. Assuming that everything is ok"
			return
		}
	} 
	else
    {	
		$targetPath = Split-Path $Target -Parent
		New-Item -Type Directory -Path $targetPath -Force
    } 

	$tempFile = [System.IO.Path]::GetTempFileName()
	
	# DownloadFile
	if($uri.Scheme.StartsWith("http","CurrentCultureIgnoreCase")) {
	    Write-Verbose "Downloading $SourceUri to '$tempFile'" 
	    Invoke-StreamDownload -Url $SourceUri -Headers $Headers -TargetFile  $tempFile
	} 
	# Copy File
	elseif($uri.Scheme.StartsWith("file","CurrentCultureIgnoreCase")) {
	    Write-Verbose "Copying file from '$SourceUri' to '$tempFile'"
		Copy-Item -Path $SourceUri -Destination $tempFile
	} 
	# Unhandled file
	else {
		Write-Error ("Unable to handle '{0}' because the uri-scheme '{1}' is not supported!" -f $SourceUri, $uri.Scheme)
		return
	}

	# Verify hash of newly downloaded file
	if($Hash -ne $null) {
		Write-Verbose "Generating hash from newly downloaded/copied file: '$tempFile'"
		$tempHash = (Get-FileHash -Path $tempFile -Algorithm $HashAlgorithm).Hash
		Write-Verbose "HashValue: $tempHash"
		
		if($tempHash -ne $Hash) {
			Write-Error "Expected '$Hash' but got '$tempHash', maybe '$SourceUri' has changed since last Hash was generated"
			return
		} else {
            Write-Verbose "Hash verified!"
        }
	}

	# Copy file to correct location
    Write-Verbose "Copyting file to destination: '$Target'"
	Move-Item -Path $tempFile -Destination $Target -Force

}


function Test-TargetResource {
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Target,

		[parameter(Mandatory = $true)]
		[System.String]
		$SourceUri,

		[System.String]
		$Hash,

		[ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512")]
		[System.String]
		$HashAlgorithm = "SHA256"
	)

	$exists = Test-Path $Target

	if(!$exists) {
		Write-Verbose "Target file '$Target' does not exist, will download '$SourceUri'"
		return $false
	}

	if($Hash -ne $null) {
		Write-Verbose "Target file '$Target' already exists, verifying hash"
		$targetHash = (Get-FileHash -Path $Target -Algorithm $HashAlgorithm).Hash
		if($targetHash -ne $Hash) {
			Write-Verbose "=> Expected '$Hash' but got '$targetHash', will download '$SourceUri' again"
			return $false
		}
		else {
			Write-Verbose "=> Hash is match"
		}
	}

	Write-Verbose "Everything is ok, no need to download file again"
	return $true
}

function Invoke-StreamDownload {
    [CmdletBinding()]
	param(
		[string] $Url,
		[string] $TargetFile,
		[Hashtable] $Headers, 
        [int] $BufferInKB = 32
	)
   	$uri = New-Object "System.Uri" "$Url"

   	$request = [System.Net.HttpWebRequest]::Create($uri)
    if($Headers -ne $null -and $Headers.Count -gt 0) {
        Write-Verbose ("Adding {0} headers" -f $Headers.Count)
   	    foreach($key in $Headers.Keys) {
            Write-Verbose "Adding header $key"
   		    $request.Headers.Add($key, $headers.$key) 
   	    }
    }
    try {

        $request.set_Timeout(15000) #15 second timeout
	    $response = $request.GetResponse()

   	    $responseContentLength = $response.get_ContentLength()

	    $totalLength = if($responseContentLength -gt 1024) {[System.Math]::Floor($responseContentLength/1024) } else { 1 }
	    $size = Get-Size $responseContentLength

   	    Write-Verbose "Requsting content: '$url' ($size)"

   	    $responseStream = $response.GetResponseStream()
  	    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $TargetFile, Create

   	    $buffer = new-object byte[] (32*1024)
   	    $count = $responseStream.Read($buffer,0,$buffer.length)
   	    $downloadedBytes = $count
        
        while ($count -gt 0)
        {
            $targetStream.Write($buffer, 0, $count)
            $count = $responseStream.Read($buffer,0,$buffer.length)
            $downloadedBytes = $downloadedBytes + $count
            Write-Progress -activity "Downloading file '$($url.split('/') | Select -Last 1)'" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes/1024)) / $totalLength)  * 100)
        }
    }
    catch [System.OutOfMemoryException] {
        throw "Received OutOfMemoryException. Possible cause is the requested file being too big. $_"
    }
    catch [System.Exception] {
        Write-Error $_
        throw "Invoking web request failed with error $($_.Exception.Response.StatusCode.Value__): $($_.Exception.Response.StatusDescription)"
    } finally {
        Write-Verbose "Cleaning up"
        $targetStream.Flush()
        $targetStream.Close()
        $targetStream.Dispose()
        $targetStream.Dispose()
        $responseStream.Dispose()
    }
    Write-Progress -activity "Finished downloading file '$($url.split('/') | Select -Last 1)'"
}

function Estimate-HashGeneration 
{
	param([string]$file) 

	$size = (Get-Item -Path $file).Length / (1024*1024)
	$min = $size / 15
	$max = $size / 25
	$avg = (($min+$max) / 2 )
	if($avg -lt 1) { 
		return 1;
	}
	return  $avg
}

function Get-Size {
    param ([long] $r)
    if($r -lt 1024) { return ("{0}bytes" -f $r) }
    $l = 1; $size = "byte"    
    foreach($s in ("", "kb", "mb", "gb")) { if($r -gt $l) { $l = $l*1024; $size = $s } }
    return ("{0}{1}" -f ([System.Math]::Floor($r*1024/$l)  ),$size)
}

Export-ModuleMember -Function *-TargetResource
