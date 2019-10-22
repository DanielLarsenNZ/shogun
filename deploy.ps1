$location = 'westus2'
$loc = 'wus2'
$rg = 'shogun-rg'
$tags = 'project=shogun'
$storage = "shogun$loc"
$functionApp = "shogun-$loc-fn"
$insights = 'shogun-insights'
$insightsLocation = 'australiaeast'

# Create Resource Group
az group create -n $rg --location $location --tags $tags


# STORAGE ACCOUNTS
# https://docs.microsoft.com/en-us/cli/azure/storage/account?view=azure-cli-latest#az-storage-account-create
az storage account create -n $storage -g $rg -l $location --tags $tags --sku Standard_LRS

$storageConnection = ( az storage account show-connection-string -g $rg -n $storage | ConvertFrom-Json ).connectionString


# APPLICATION INSIGHTS
#  https://docs.microsoft.com/en-us/cli/azure/ext/application-insights/monitor/app-insights/component?view=azure-cli-latest
az extension add -n application-insights

$instrumentationKey = ( az monitor app-insights component create --app $insights --location $insightsLocation -g $rg --tags $tags | ConvertFrom-Json ).instrumentationKey

# FUNCTION APP
az functionapp create -n $functionApp -g $rg --tags $tags --consumption-plan-location $location -s $storage --app-insights $insights --app-insights-key $instrumentationKey

<#
# Package and zip the Function App
dotnet publish .\Examples.Pipeline.Functions\ --configuration Release -o '../_functionzip'
Compress-Archive -Path ./_functionzip/* -DestinationPath ./deployfunction.zip -Force

# Deploy source code
az functionapp deployment source config-zip -g $rg -n $functionApp --src ./deployfunction.zip
#>


# APP SETTINGS
az functionapp config appsettings set -n $functionApp -g $rg --settings "APPINSIGHTS_INSTRUMENTATIONKEY=$instrumentationKey" "Azurestorage=$storageConnection"


# Tear down
# az group delete -n $rg --yes
