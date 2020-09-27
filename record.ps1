function Record {
  foreach($line in Get-Content -encoding UTF8 ~\Documents\test_recording_sentences.txt) {
    $filename = $line;
    [System.IO.Path]::GetInvalidFileNameChars() | % {$filename = $filename.replace($_,'_')};
    Write-Host "Recording: $line press q to finish";
    C:\Users\Hanzhou\Downloads\ffmpeg.exe -y -loglevel quiet -f dshow -i video="DroidCam Source 3":audio="Microphone (DroidCam Virtual Audio)" "${filename}.mp4";
    function RecordSpeechTiming {
        Param (
            [string] [Parameter(Mandatory=$true)] $filename,
            [string] [Parameter(Mandatory=$true)] $sentence
        );
        # I'll assume normalized
        $stopwatch = New-Object System.Diagnostics.Stopwatch;
        $stopwatch.Start();
        $charArray = $line.toCharArray();
        $timestamps = $();
        foreach($char in $charArray) {
          if($char -cmatch '[\u4e00-\u9fff]'){
            Write-Host $char;
            $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | out-null;
          }
          $timestamp = $stopwatch.Elapsed.TotalMilliseconds;
          $timestamps += , @{'timestamp' = $timestamp; 'character' = $char};
        }
        ConvertTo-Json $timestamps | Set-Content "${filename}.json"
    };
    function PlaySlowedAudio {
        Param (
            [string] [Parameter(Mandatory=$true)] $videoFile
        );
        $slowedFile = "slow${videoFile}";
        ffmpeg -i $videoFile -loglevel quiet -filter:v "setpts=2*PTS" -filter:a "atempo=0.5" $slowedFile;
        C:\Users\Hanzhou\Downloads\ffplay.exe $videoFile -loglevel quiet -autoexit -nodisp $slowedFile;
    };
    Start-Job -ScriptBlock {PlaySlowedAudio "${filename}.mp4";} | out-null;
    Write-Host "Press any key once you hear the character below being pronounced";
    
    RecordSpeechTiming $filename $line;
  }
}

Record;