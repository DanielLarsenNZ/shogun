# Input bindings are passed in via param block.
param($Timer)

function SecondsMeasure ($Measure) {
    # cut down the measure object to Seconds
    return @{
        Ticks = $Measure.Ticks
        Milliseconds = $Measure.Milliseconds
        Seconds = $Measure.Seconds
        TotalMilliseconds = $Measure.TotalMilliseconds
        TotalSeconds = $Measure.TotalSeconds
    } 
}

$TIMEOUT_SECONDS = 2
$MAX_REQUEST_COUNT = 0
$INPUT_FILEPATH = './shogun-dynamic.json'
#$OUTPUT_HAR_FILEPATH = "../_work/1947-$(New-Guid)-output.har"

$json = Get-Content -Path $INPUT_FILEPATH | ConvertFrom-Json

$output = @{log = @{ 
    entries = ( @{ }, @{ } ) } # not sure how to instantiate an empty array here
    __dateTime = Get-Date
}

# How to new an empty Hashtable?
$outVars = @{ }

$i = 0

$bigMeasure = Measure-Command {
    foreach ($entry in $json.entries) {

        # only GETs, HEADs, POSTS for now
        if ($entry.request.method -notin 'GET', 'HEAD', 'POST') { continue }

        # HAR logic
        # if browser retrieved from cache, ignore
        # if ($entry._fromCache -ne $null) { continue }

        # if max entry limit reached, quit
        if ($MAX_REQUEST_COUNT -gt 0 -and $i -gt $MAX_REQUEST_COUNT) { break }

        $i += 1
        
        $outEntry = @{
            __number = $i
            startedDateTime = Get-Date # TODO ISO DATE
            request = @{
                url = $entry.request.url
                method = $entry.request.method
            }
        }
        
        # Map headers
        $headers = $entry.request.headers | % { @{ $_.name = $_.value } }

        $entryMeasure = Measure-Command {
            try {
                $url = $entry.request.url
                
                if ($url.Contains('{') -and $url.Contains('}')) {
                    # Rewrite URL
                    # https://powershellexplained.com/2017-01-13-powershell-variable-substitution-in-strings/
                    foreach( $var in $outVars.GetEnumerator() )
                    {
                        $pattern = "{$($var.key)}" 
                        $url = $url.Replace($pattern, $var.Value)
                    }
                }

                Write-Host "$($entry.request.method) $($url)" -ForegroundColor Yellow
                
                switch ($entry.request.method) {
                    { ( $_ -eq 'GET' ) -or ( $_ -eq 'HEAD' ) } {
                        $response = Invoke-WebRequest -Uri $url -Method $entry.request.method -UseBasicParsing `
                            -TimeoutSec $TIMEOUT_SECONDS -Headers $headers
                    }
                    'POST' {
                        $response = Invoke-WebRequest -Uri $url -Method $entry.request.method -UseBasicParsing `
                            -TimeoutSec $TIMEOUT_SECONDS -Headers $headers `
                            -Body ( $entry.request.body.json | ConvertTo-Json )
                    }
                    Default { continue }
                }

                Write-Host "$($response.StatusCode) $($response.StatusDescription)" -ForegroundColor White
                
                $outEntry.response = @{ 
                    status = $response.StatusCode 
                    statusText = $response.StatusDescription
                    __rawContentLength = $response.RawContentLength
                    __headers = $response.Headers
                }

                $responseJson = ( $response.Content | ConvertFrom-Json )

                # OUT VARS ==========================
                if ($entry.out -ne $null) {
                    foreach ($outVar in $entry.out | Get-Member -MemberType NoteProperty)
                    {
                        $name = $outVar.Name
                        $prop = $entry.out.$name
                        $outVars[$outVar.Name] = $responseJson.$prop
                    }
                }

            } catch {
                Write-Host "$($_.Exception.Message)" -ForegroundColor DarkYellow                
                $outEntry.response = @{ }
                $outEntry.__error = $_
            }
        }
        
        $outEntry.response.measure = SecondsMeasure -Measure $entryMeasure
        $outEntry.time = $entryMeasure.TotalMilliseconds # TODO toint

        $output.log.entries = $output.log.entries += $outEntry
    }
}

#$rps = (1 / $bigMeasure.TotalSeconds) * $i

$output.log.__metrics = @{
    requestCount = $i
    measure = SecondsMeasure -Measure $bigMeasure
    #rps = (1 / $bigMeasure.TotalSeconds) * $i
    #rpm = $rps * 60
    averageResponseMs = $bigMeasure.TotalMilliseconds / $i
}

Write-Host ($output.log.__metrics | ConvertTo-Json -Depth 5)
#Set-Content -Path $OUTPUT_HAR_FILEPATH -Value ($output | ConvertTo-Json -Depth 5)
