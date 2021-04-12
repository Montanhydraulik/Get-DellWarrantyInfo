[CmdletBinding()]
Param(
	[Parameter(Mandatory=$true)]
	[ValidateCount(1,100)]
	[String[]]
	$ServiceTags,
	
	[Parameter(Mandatory=$false)]
	[System.IO.FileInfo]
	$ExportToIniFile
)

Set-Variable API_KEY -Option Constant -Value 'YOUR_API_KEY'
Set-Variable KEY_SECRET -Option Constant -Value 'YOUR_KEY_SECRET'

Set-Variable AUTH_URI -Option Constant -Value 'https://apigtwb2c.us.dell.com/auth/oauth/v2/token'
Set-Variable WARRANTY_URI -Option Constant -Value 'https://apigtwb2c.us.dell.com/PROD/sbil/eapi/v5/asset-entitlements'

Set-Variable DATE_FORMAT -Option Constant -Value 'yyyy-MM-dd'

function Delete-IniFile-IfNecessary() {
	if ($ExportToIniFile -eq $null) {
		Return
	}
	if ([System.IO.File]::Exists($ExportToIniFile)) {
		Remove-Item -Path $ExportToIniFile | Out-Null
	}
}

function AppendTo-IniFile-IfNecessary($InputObject) {
	if ($ExportToIniFile -eq $null) {
		Return
	}
	
	if (![System.IO.File]::Exists($ExportToIniFile)) {
		New-Item -ItemType File -Path $ExportToIniFile | Out-Null
	}
	
	Add-Content -Path $ExportToIniFile -Value "[$($InputObject.'Service Tag')]"
	Add-Content -Path $ExportToIniFile -Value "Model=$($InputObject.'Model')"
	Add-Content -Path $ExportToIniFile -Value "ModelSeries=$($InputObject.'Model Series')"
	Add-Content -Path $ExportToIniFile -Value "ShipDate=$($InputObject.'Ship Date')"
	Add-Content -Path $ExportToIniFile -Value "EndDate=$($InputObject.'End Date')"
	Add-Content -Path $ExportToIniFile -Value "ServiceLevelDescription=$($InputObject.'Service Level Description')"
	Add-Content -Path $ExportToIniFile -Value ""
}

function Get-Token {
	$encodedOAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$API_KEY`:$KEY_SECRET"))
	$authHeaders = @{'Authorization' = "Basic $encodedOAuth"}
	$authBody = 'grant_type=client_credentials'
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$authResult = Invoke-RestMethod -Uri $AUTH_URI -Method Post -Headers $authHeaders -Body $authBody
	return $authResult.access_token
}

Delete-IniFile-IfNecessary

$token = Get-Token
$headers = @{'Accept' = 'application/json'; 'Authorization' = "Bearer $token"}
$body = @{'servicetags' = ($ServiceTags -Join ', ')}
$assets = Invoke-RestMethod -Uri $WARRANTY_URI -Method Get -Headers $headers -Body $body -ContentType "application/json" -ea 0

foreach ($asset in $assets) {
	if ($asset.invalid) {
		continue
	}
	
	$serviceTag = $asset.serviceTag
	$model = $asset.productLineDescription
	$modelSeries = $asset.productLobDescription
	$shipDate = $asset.shipDate | Get-Date -f $DATE_FORMAT
	$serviceLevelDescription = ''
	$entitlementEndDate = $null
	foreach ($entitlement in $asset.entitlements) {
		if ($entitlement.endDate -gt $entitlementEndDate) {
			$serviceLevelDescription = $entitlement.serviceLevelDescription
			$entitlementEndDate = $entitlement.endDate
		}
	}
	$endDate = $entitlementEndDate | Get-Date -f $DATE_FORMAT

	$object = New-Object PSObject -Property @{
		'Service Tag' = $serviceTag
		'Model' =  $model
		'Model Series' = $modelSeries
		'Ship Date' = $shipDate
		'End Date' = $endDate
		'Service Level Description' = $serviceLevelDescription
	}
	
	AppendTo-IniFile-IfNecessary $object
	
	$object
}
