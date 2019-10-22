# Shogun

"Do it yourself" HTTP load testing using a PowerShell Function in Azure Functions.

> 👷‍👷‍ Work in progress! ⚒

1. Record a HAR file in Microsoft Edge Dev Developer tools and save as `./src/1947.har`
1. Run `./deploy.ps1`
1. Run the Function locally - or - Publish to Azure Functions

Every minute, Shogun will invoke all requests it finds in the HAR file where:

1. Request Method = GET or HEAD
1. Browser did not retrieve from cache

Contributions and Issues welcome.