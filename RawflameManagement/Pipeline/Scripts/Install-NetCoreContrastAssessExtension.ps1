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


catch {
    Write-Error "There was an error initializing $ExtensionName for the App Service. $($_.Exception.Message)"
}
