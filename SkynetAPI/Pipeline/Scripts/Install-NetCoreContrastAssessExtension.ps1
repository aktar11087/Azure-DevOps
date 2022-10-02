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
