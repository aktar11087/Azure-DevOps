param(
    [Parameter(Mandatory = $true)]
    [string]
    $Service,
	[Parameter(Mandatory = $true)]
    [string]
    $ResourceGroup,
    [string]$SubscriptionID,
    [hashtable]$AppSettings = @{},
    [string]$EnviromentType = "QA",
    [string]$u4proVersion 
)

function Use-LatestContrastNetCoreExtension {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$AppServiceName
    )

    $extensionResourceName = "$AppServiceName/$ExtensionName"

    $existingExtension = Get-AzResource `
        -Name $extensionResourceName `
        -ResourceGroupName $ResourceGroupName `
        -ResourceType $SiteExtensionResourceType `
        -ApiVersion $ApiVersion `
        -ErrorAction SilentlyContinue

    if ($null -ne $existingExtension) {
        $currentVersion = $existingExtension.properties.version
        Write-Host "$ExtensionName version $currentVersion found in the App Service."

        Update-ContrastNetCoreExtension `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName `
            -AppServiceName $AppServiceName `
            -CurrentVersion $currentVersion
    }
    else {
        Write-Host "$ExtensionName is not installed in the App Service."
        Install-ContrastNetCoreExtension `
            -ResourceGroupName $ResourceGroupName `
            -AppServiceName $AppServiceName
    }
}

function Update-ContrastNetCoreExtension {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$AppServiceName,
        [string]$CurrentVersion
    )

    $latestAvailableExtension = Invoke-RestMethod `
        -Method Get `
        -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$AppServiceName/extensions/api/extensionfeed/$($ExtensionName)?api-version=$ApiVersion" `
        -Headers @{Authorization = "Bearer $((Get-AzAccessToken).Token)" }
    [System.Version] $latestVersion = ($latestAvailableExtension.value | where {($_.name -like "*Contrast.NET*")}).properties.version

    Write-Host "Current Version $CurrentVersion"
    Write-Host "Latest Version $latestVersion"
    if ($CurrentVersion -lt $latestVersion) {
        Write-Host "Version $latestVersion of $ExtensionName is available. Extension will be updated."
        Remove-AzResource `
            -Name "$AppServiceName/$ExtensionName" `
            -ResourceGroupName $ResourceGroupName `
            -ResourceType $SiteExtensionResourceType `
            -ApiVersion $ApiVersion `
            -Force
            
        Install-ContrastNetCoreExtension `
            -ResourceGroupName $ResourceGroupName `
            -AppServiceName $AppServiceName
        
            return $latestVersion
    }
    else {
        Write-Host "$ExtensionName is up to date."

        return $CurrentVersion
    }
}

function Install-ContrastNetCoreExtension {
    param(
        [string]$ResourceGroupName,
        [string]$AppServiceName
    )

    Write-Host "Instaling $ExtensionName..."

    $extensionCreated = New-AzResource `
        -Name "$AppServiceName/$ExtensionName" `
        -ResourceGroupName $ResourceGroupName `
        -ResourceType $SiteExtensionResourceType `
        -ApiVersion $ApiVersion `
        -ErrorAction Stop `
        -Force

    Write-Host "$ExtensionName version $($extensionCreated.properties.version) installed in the App Service."
}

function Add-ContrastAppSettings {
    param(
        [string]$ResourceGroupName,
        [string]$AppServiceName,
        [string]$ContrastVersion,
        [hashtable]$AppSettings = @{}
    )

    $updatedAppSettings = $AppSettings + @{ 
        "CONTRAST__SERVER__NAME"                  = "$AppServiceName"
        "CONTRAST__SERVER__ENVIRONMENT"           = "$EnviromentType"
        "CORECLR_ENABLE_PROFILING"                = "1"
        "CORECLR_PROFILER"                        = "{8B2CE134-0948-48CA-A4B2-80DDAD9F5791}"
        "CORECLR_PROFILER_PATH_32"                = "C:\home\SiteExtensions\Contrast.NetCore.Azure.SiteExtension\ContrastNetCoreAppService-$($ContrastVersion).0\runtimes\win-x86\native\ContrastProfiler.dll"
        "CORECLR_PROFILER_PATH_64"                = "C:\home\SiteExtensions\Contrast.NetCore.Azure.SiteExtension\ContrastNetCoreAppService-$($ContrastVersion).0\runtimes\win-x64\native\ContrastProfiler.dll"
        "CONTRAST__APPLICATION__VERSION"          = "$u4proVersion"
        "CONTRAST__APPLICATION__SESSION_METADATA" = "buildNumber=$($u4proVersion)" 
    }

    $webApp = Get-AzWebApp `
        -Resourcegroup $ResourceGroupName `
        -Name $AppServiceName `
        -ErrorAction Stop
    
    Set-WebAppSettings `
        -WebApp $webApp `
        -AppSettings $updatedAppSettings
}

function Set-WebAppSettings {
    [CmdletBinding()]
    param (
        [Microsoft.Azure.Commands.WebApps.Models.PSSite]$WebApp,
        [hashtable]$AppSettings = @{}
    )

    $existingAppSettings = $WebApp.SiteConfig.AppSettings

    $newAppSettings = @{}
    foreach ($item in $existingAppSettings) {
        $newAppSettings[$item.Name] = $item.Value
    }

    foreach ($extraSetting in $AppSettings.Keys) {
        $newAppSettings[$extraSetting] = $AppSettings[$extraSetting]
    }

    Write-Host "Updating App Service settings..."

    Set-AzWebApp `
        -ResourceGroupName $WebApp.ResourceGroup `
        -Name $WebApp.Name  `
        -AppSettings $newAppSettings | Out-Null

    Write-Host "App Service settings updated."
}

$ApiVersion = "2021-03-01"
$SiteExtensionResourceType = "Microsoft.Web/sites/siteextensions"
$ExtensionName = "Contrast.NetCore.Azure.SiteExtension"

try {
    $appServiceName = $Service
    $resourceGroupName = $ResourceGroup
    
    if ([string]::IsNullOrEmpty($appServiceName)) {
        Write-Error "AppService name could not be resolved using the input parameters provided."
    }
    
    $currentLock = Get-AzResourceLock -ResourceGroupName $resourceGroupName
    
    if ($null -ne $currentLock) {
        Write-Host "Deleting Lock CanNotDelete in Resource group $resourceGroupName"
        $currentLock | Remove-AzResourceLock -Force
        Write-Host "Deleted Lock CanNotDelete in Resource group $resourceGroupName"
    }
    
    $installedVersion = Use-LatestContrastNetCoreExtension `
        -SubscriptionId $SubscriptionID `
        -ResourceGroupName $resourceGroupName `
        -AppServiceName $appServiceName

    Add-ContrastAppSettings `
        -ResourceGroupName $resourceGroupName `
        -AppServiceName $appServiceName `
        -AppSettings $AppSettings `
        -ContrastVersion $installedVersion

    Restart-AzWebApp `
        -ResourceGroupName $resourceGroupName `
        -Name $appServiceName | Out-Null

    if ($null -ne $CurrentLock) {
        Write-Host "Creating Lock CanNotDelete on Resource group $resourceGroupName"
        New-AzResourceLock `
            -LockName LockResourceGroup `
            -LockLevel CanNotDelete `
            -ResourceGroupName $resourceGroupName `
            -Force
        Write-Host "Lock CanNotDelete on Resource group $resourceGroupName created"
    }

    Write-Host "$ExtensionName correctly initialized for $appServiceName App Service."
}
catch {
    Write-Error "There was an error initializing $ExtensionName for the App Service. $($_.Exception.Message)"
}
