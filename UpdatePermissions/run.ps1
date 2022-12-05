# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

Set-Location (Get-Item $PSScriptRoot).Parent.FullName
$Tenants = get-tenants
$APINAME = "CPV Permissions"
foreach ($TenantFilter in $Tenants) {
    $Translator = Get-Content '.\Cache_SAMSetup\PermissionsTranslator.json' | ConvertFrom-Json
    $ExpectedPermissions = Get-Content '.\Cache_SAMSetup\SAMManifest.json' | ConvertFrom-Json
    try {
        $DeleteOldPermissions = New-GraphpostRequest -Type DELETE -noauthcheck $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter.customerId)/applicationconsents/$($env:ApplicationID)" -scope "https://api.partnercenter.microsoft.com/.default" -tenantid $env:TenantID

    }
    catch {
        "no old permissions to delete, moving on"
    }

    $GraphRequest = $ExpectedPermissions.requiredResourceAccess | ForEach-Object { 
        try {
            $Resource = $_
            $Permissionsname = switch ($Resource.ResourceAppId) {
                '00000003-0000-0000-c000-000000000000' { "Graph API" }
                'fc780465-2017-40d4-a0c5-307022471b92' { 'WindowsDefenderATP' }
            }
            $Scope = ($Translator | Where-Object { $_.id -in $Resource.ResourceAccess.id } | Where-Object { $_.value -notin 'profile', 'openid', 'offline_access' }).value -join ', '
            if ($Scope) {
                $RequiredCPVPerms = [PSCustomObject]@{
                    EnterpriseApplicationId = $_.ResourceAppId
                    Scope                   = "$Scope"
                }
                $AppBody = @"
{
  "ApplicationGrants":[ $(ConvertTo-Json -InputObject $RequiredCPVPerms -Compress -Depth 10)],
  "ApplicationId": "$($env:ApplicationID)",
  "DisplayName": "CIPP-SAM"
}
"@
                $CPVConsent = New-GraphpostRequest -body $AppBody -Type POST -noauthcheck $true -uri "https://api.partnercenter.microsoft.com/v1/customers/$($TenantFilter.customerId)/applicationconsents" -scope "https://api.partnercenter.microsoft.com/.default" -tenantid $env:TenantID
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -Tenant $TenantFilter.defaultDomainName  -message "Succesfully set CPV Permissions for $PermissionsName" -Sev "Error"

                "Succesfully set CPV permissions for $Permissionsname"

            } 
        }
        catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -Tenant $TenantFilter.defaultDomainName  -message "Could not set CPV permissions for $PermissionsName. Does the Tenant have a license for this API? Error: $($_.Exception.message)" -Sev "Error"
            "Could not set CPV permissions for $PermissionsName. Does the Tenant have a license for this API? Error: $($_.Exception.message)"
        }
    }
}
# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

