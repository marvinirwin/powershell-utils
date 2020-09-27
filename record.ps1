
foreach($sentence in Get-Content -encoding UTF8 $args[0]) {
    # Create a without invalid characters
    $filename = $sentence;
    [System.IO.Path]::GetInvalidFileNameChars() | % {$filename = $filename.replace($_,'_')};

    # Record the sentence to filename.mp4
    Write-Host "Recording: $line press q to finish";
    C:\Users\Hanzhou\Downloads\ffmpeg.exe -y -loglevel quiet -f dshow -i video="DroidCam Source 3":audio="Microphone (DroidCam Virtual Audio)" "${filename}.mp4";

    # Create a slowed version of the file "slow_$filename.mp4"
    CreateSlowedFile "${filename}.mp4}";

    # Play the slowed down audio 
    Start-Job -ScriptBlock {PlaySlowedAudio "slow_${filename}.mp4";} | out-null;

    Write-Host "Press any key once you hear the character below being pronounced";
    
    # Record the speech timing
    RecordSpeechTiming $filename $line;
}

function RecordSpeechTiming {
    Param (
        [string] [Parameter(Mandatory=$true)] $filename,
        [string] [Parameter(Mandatory=$true)] $sentence
    );
    # I'll assume normalized
    $stopwatch = New-Object System.Diagnostics.Stopwatch;
    $stopwatch.Start();
    $charArray = $line.toCharArray();
    $object = @{
        "sentence" = $sentence;
        "timeScale" = 0.5;
        "characters" = @();
        "filename" = $filename;
    };
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
        
    C:\Users\Hanzhou\Downloads\ffplay.exe -loglevel quiet -autoexit -nodisp $slowedFile;
};

function CreateSlowedFile {
    Param (
        [string] [Parameter(Mandatory=$true)] $videoFile
    );
    $slowedFile = "slow_${videoFile}";
    ffmpeg -i $video File -loglevel quiet -filter:v "setpts=2*PTS" -filter:a "atempo=0.5" $slowedFile;
}