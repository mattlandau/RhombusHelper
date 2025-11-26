[CmdletBinding(PositionalBinding=$false)]
param([Parameter(mandatory=$true)][string]$APIKey, 
	[Parameter(mandatory=$true)][string]$CameraUUID, 
	[Parameter(mandatory=$true)][string]$UnixEpochSeconds, 
	[Parameter(mandatory=$true)][int]$DurationInSeconds, 
	[Parameter(mandatory=$true)][string]$FilePath)

function Main {
	param([string]$APIKey, [string]$CameraUUID, [string]$UnixEpochSeconds, [string]$FilePath)
	
	#WAN test mode
	$WANTest = $false
	
	Write-Host "CameraId: $CameraUUID, UnixEpochSeconds: $UnixEpochSeconds, Duration: $DurationInSeconds seconds"
	Write-Host "Unix Epoch (ms): " + $UnixEpochSeconds
	$InitialURI = GetMpdTemplate -APIKey $APIKey -CameraUUID $CameraUUID -WANTest $WANTest
	$DefinitiveURI = ($InitialURI -replace "{START_TIME}", $UnixEpochSeconds) -replace "{DURATION}", $DurationInSeconds
	$FederatedSessionToken = GetFederatedSessionToken -APIKey $APIKey
	$Cookie = "RSESSIONID=RFT:" + $FederatedSessionToken
	$Nonce = [System.Guid]::NewGuid().ToString()
	GetMpd -APIKey $APIKey -URI $DefinitiveURI -Cookie $Cookie
	GetWholeFile -APIKey $APIKey -DurationInSeconds $DurationInSeconds -URI $DefinitiveURI -Cookie $Cookie -FilePath $FilePath -Nonce $Nonce 
	RemoveTempFiles -Nonce $Nonce -DurationInSeconds $DurationInSeconds 
}

function GetMpd {
	param([string]$APIKey, [string]$URI, [string]$Cookie)
        $headers=@{}
        $headers.Add("accept", "application/json")
        $headers.Add("x-auth-scheme", "api-token")
        $headers.Add("content-type", "application/json")
        $headers.Add("x-auth-apikey", $APIKey)
	$headers.Add("Cookie",$Cookie)
	$response = Invoke-WebRequest -Uri $URI -Method GET -Headers $headers
}

function GetMpdTemplate {
	param([string]$APIKey, [string]$CameraUUID, [bool]$WANTest)
	$headers=@{}
	$headers.Add("accept", "application/json")
	$headers.Add("x-auth-scheme", "api-token")
	$headers.Add("content-type", "application/json")
	$headers.Add("x-auth-apikey", $APIKey)
	$Body = "{`"cameraUuid`":`"$CameraUUID`"}"
	$response = Invoke-WebRequest -Uri 'https://api2.rhombussystems.com/api/camera/getMediaUris' -Method POST -Headers $headers -ContentType 'application/json' -Body "$Body" 
	$responseObject = ConvertFrom-JSON $response

	if (-not $WANTest) {
		$InitialLANURI = $responseObject.lanVodMpdUrisTemplates
		Write-Host $InitialLANURI	
		return $InitialLANURI
	} else {
		$InitialWANURI = $responseObject.wanVodMpdUriTemplate
        	Write-Host $InitialWANURI 
		return $InitialWANURI
	}
}

function GetFederatedSessionToken {
	param([string]$APIKey)
	$headers=@{}
	$headers.Add("accept", "application/json")
	$headers.Add("x-auth-scheme", "api-token")
	$headers.Add("content-type", "application/json")
	$headers.Add("x-auth-apikey", $APIKey)
	$response = Invoke-WebRequest -Uri 'https://api2.rhombussystems.com/api/org/generateFederatedSessionToken' -Method POST -Headers $headers -ContentType 'application/json' -Body '{"durationSec":3600}'
	$ResponseObject = ConvertFrom-JSON $response
	return $ResponseObject.federatedSessionToken
}

function GetPart {
	param([string]$APIKey, [string]$URI, [string]$Segment, [string]$Cookie, [string]$Nonce)
	$URI = $URI -replace "clip.mpd", $Segment
        $URI = $URI -replace "file.mpd", $Segment
	$headers=@{}
        $headers.Add("accept", "*/*")
        $headers.Add("x-auth-scheme", "api-token")
        $headers.Add("content-type", "application/json")
        $headers.Add("x-auth-apikey", $APIKey)
	$headers.Add("Cookie", $Cookie)
        $FileName = $Nonce + "_" + $Segment
	Write-Host "Getting $URI with Cookie $Cookie to $FileName"
	$Response = Invoke-WebRequest -Uri $URI -Method GET -Headers $headers -ContentType 'application/json' -OutFile $FileName 
	return $Response
}

function GetHeaderFile {
        param([string]$APIKey, [string]$URI, [string]$Page, [string]$Cookie, [string]$FilePath)
        $URI = $URI -replace "file.mpd", $Page
	$URI = $URI -replace "clip.mpd", $Page
        $headers=@{}
        $headers.Add("accept", "*/*")
        $headers.Add("x-auth-scheme", "api-token")
        $headers.Add("content-type", "application/json")
        $headers.Add("x-auth-apikey", $APIKey)
        $headers.Add("Cookie", $Cookie)
        $Response = Invoke-WebRequest -Uri $URI -Method GET -Headers $headers -ContentType 'application/json' -OutFile $FilePath
}


function GetWholeFile {
	param([string]$APIKey, [int]$DurationInSeconds, [string]$URI, [string]$Cookie, [string]$FilePath, [string]$Nonce)
	GetHeaderFile -APIKey $APIKey -URI $URI -Cookie $Cookie -FilePath $FilePath -Page "seg_init.mp4"
	$iterations = [math]::Ceiling($DurationInSeconds / 2)
	for ($i = 0; $i -lt $iterations; $i++) {
		$start = $i * 2
		$IPlusOne = $i + 1
		$Segment = "seg_" + ($i + 1).ToString() + ".m4v"
		Write-Host "Getting seg_$IPlusOne.m4v"
		$Response = GetPart -APIKey $APIKey -URI $URI -Segment $Segment -Cookie $Cookie -Nonce $Nonce
		$FileName = $Nonce + "_" + $Segment
		$fileContent = Get-Content -Path $FileName -AsByteStream -Raw
		Add-Content -Path $FilePath -Value $fileContent -AsByteStream
	}
}

function RemoveTempFiles {
	param([int]$DurationInSeconds, [string]$Nonce)
	$iterations = [math]::Floor($DurationInSeconds / 2)
	for ($i = 0; $i -lt $iterations; $i++) {
		$start = $i * 2
        	$Segment = $Nonce + "_seg_" + ($i + 1).ToString() + ".m4v"
		Remove-Item -Path $Segment
	}
}

Main -APIKey $APIKey -CameraUUID $CameraUUID -UnixEpochSeconds $UnixEpochSeconds -DurationInSeconds $DurationInSeconds -FilePath $FilePath
