param (
    [Parameter(Mandatory = $true)] [string] $InputHarFile,
    [Parameter(Mandatory = $false)] [string] $DomainName,
    [Parameter(Mandatory = $false)] [int] $RunEverySeconds = 60
)

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

function Run() {

    $global:TIMEOUT_SECONDS = 2
    $global:MAX_REQUEST_COUNT = 0
    #$OUTPUT_HAR_FILEPATH = "../_work/1947-$(New-Guid)-output.har"

    $har = Get-Content -Path $InputHarFile | ConvertFrom-Json

    $output = @{log = @{ 
        entries = ( @{ }, @{ } ) } # not sure how to instantiate an empty array here
        __dateTime = Get-Date
    }

    $i = 0

    $bigMeasure = Measure-Command {
        
        $har.log.entries | ForEach-Object -ThrottleLimit 8 -Parallel {
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
            
            $TIMEOUT_SECONDS = $using:TIMEOUT_SECONDS
            $MAX_REQUEST_COUNT = $using:MAX_REQUEST_COUNT
            $output = $using:output
            $i = $using:i
            $DomainName = $using:DomainName

            $entry = $_
            #Write-Host $entry

            # only GETs and HEADs
            if ($entry.request.method -notin 'GET', 'HEAD') { continue }

            if (!$entry.request.url.Contains($DomainName)) { continue }

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
            
            # Headers to dictionary
            $headers = @{}
            foreach ($header in $entry.request.headers) {
                if ($header.name.StartsWith(':')) { continue }
                $headers.Add($header.name, $header.value)
            }
            
            Write-Host "$($entry.request.method) $($entry.request.url)" -ForegroundColor Yellow

            $entryMeasure = Measure-Command {
                
                # Retry up to 3 times
                for ($j = 0; $j -lt 3; $j++) {
                    try {
                        $response = Invoke-WebRequest -Uri $entry.request.url -Method $entry.request.method -UseBasicParsing `
                            -TimeoutSec $TIMEOUT_SECONDS -SkipHttpErrorCheck -Headers $headers
                        break
                    }
                    catch {
                        Write-Host "$($j + 1) $($_.Exception.Message)" -ForegroundColor DarkYellow                
                        $outEntry.response = @{ }
                        $outEntry.__error = $_           
                    }
                }

                Write-Host "$($response.StatusCode) $($response.StatusDescription)" -ForegroundColor White
                $outEntry.response = @{ 
                    status = $response.StatusCode 
                    statusText = $response.StatusDescription
                    __rawContentLength = $response.RawContentLength
                    __headers = $response.Headers
                }
            }
            
            $outEntry.response.measure = SecondsMeasure -Measure $entryMeasure
            $outEntry.time = $entryMeasure.TotalMilliseconds # TODO toint
            $output.log.entries = $output.log.entries += $outEntry
        }
    }

    #$rps = (1 / $bigMeasure.TotalSeconds) * $i

    $output.log.__metrics = @{
        #requestCount = $i
        measure = SecondsMeasure -Measure $bigMeasure
        #rps = (1 / $bigMeasure.TotalSeconds) * $i
        #rpm = $rps * 60
        #averageResponseMs = $bigMeasure.TotalMilliseconds / $i
    }

    Write-Host ($output.log.__metrics | ConvertTo-Json -Depth 5)
    #Set-Content -Path $OUTPUT_HAR_FILEPATH -Value ($output | ConvertTo-Json -Depth 5)
    
    return (SecondsMeasure -Measure $bigMeasure).TotalSeconds
}

while ($true) {
    $bigDuration = Run
    $sleepSeconds = [math]::Max(0,($RunEverySeconds - $bigDuration))
    Write-Host "Running again in $sleepSeconds seconds"
    Start-Sleep -Seconds $sleepSeconds
}
