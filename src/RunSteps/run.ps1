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
$INPUT_HAR_FILEPATH = './1947.har'
#$OUTPUT_HAR_FILEPATH = "../_work/1947-$(New-Guid)-output.har"

$har = Get-Content -Path $INPUT_HAR_FILEPATH | ConvertFrom-Json

$output = @{log = @{ 
    entries = ( @{ }, @{ } ) } # not sure how to instantiate an empty array here
    __dateTime = Get-Date
}

$i = 0


$bigMeasure = Measure-Command {
    foreach ($entry in $har.log.entries) {

        # only GETs and HEADs
        if ($entry.request.method -notin 'GET', 'HEAD') { continue }

        # if browser retrieved from cache, ignore
        if ($entry._fromCache -ne $null) { continue }

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
        
        $entryMeasure = Measure-Command {
            try {
                Write-Host "$($entry.request.method) $($entry.request.url)" -ForegroundColor Yellow
                $response = Invoke-WebRequest -Uri $entry.request.url -Method $entry.request.method -UseBasicParsing `
                    -TimeoutSec $TIMEOUT_SECONDS -SkipHttpErrorCheck

                Write-Host "$($response.StatusCode) $($response.StatusDescription)" -ForegroundColor White
                $outEntry.response = @{ 
                    status = $response.StatusCode 
                    statusText = $response.StatusDescription
                    __rawContentLength = $response.RawContentLength
                    __headers = $response.Headers
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
