function RecordSpeechTiming {
    Param (
        [string] [Parameter(Mandatory=$true)] $filename,
        [string] [Parameter(Mandatory=$true)] $sentence
    );
    # I'll assume normalized
    $stopwatch = New-Object System.Diagnostics.Stopwatch;
    $stopwatch.Start();
    $charArray = $sentence.toCharArray();
    $object = @{
        "sentence" = $sentence;
        "timeScale" = 0.25;
        "characters" = @();
        "filename" = "${filename}.mp4";
    };
    foreach($char in $charArray) {
        if($char -cmatch '[\u4e00-\u9fff]'){
            Write-Host $char;
            $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | out-null;
        }
        $timestamp = $stopwatch.Elapsed.TotalMilliseconds;
        $object['characters'] += , @{'timestamp' = $timestamp; 'character' = $char};
    }
    ConvertTo-Json $object | Set-Content -Encoding UTF8 "${filename}.json"
};



function CreateSlowedFile {
    Param (
        [string] [Parameter(Mandatory=$true)] $filename
    );
    $slowedFile = "slow_${filename}.aac";
    Write-Host "Creating slowed file $slowedFile";
    ffmpeg.exe -i "${filename}.mp4" `
        -y `
        -loglevel error `
        -vn `
        -filter:a "atempo=0.5,atempo=0.5" `
        "$slowedFile";
}

function RotateVideo {
    Param (
        [string] [Parameter(Mandatory=$true)] $filename
    );

}


foreach($sentence in Get-Content -encoding UTF8 $args[0]) {
    # Create a without invalid characters
    $filename = $sentence;
    [System.IO.Path]::GetInvalidFileNameChars() | % {$filename = $filename.replace($_,'_')};

    # Record the sentence to filename.mp4
    Write-Host "Recording: $sentence press q to finish";
    ffmpeg.exe -y `
        -loglevel error `
        -f dshow ` `
        -i video="DroidCam Source 3":audio="Microphone (DroidCam Virtual Audio)" `
        "${filename}_90.mp4";

    Write-Host "Rotating video 90 degrees";
    ffmpeg.exe -y `
        -loglevel error `
        -i "${filename}_90.mp4" `
        -vf "transpose=1" `
        "${filename}.mp4" 


    # Create a slowed version of the file "slow_$filename.mp4"
    CreateSlowedFile $filename;

    $slowFilename = "slow_${filename}.aac";
    # Play the slowed down audio
    $job = Start-Job `
        -InputObject $slowFilename `
        -Init ([ScriptBlock]::Create("Set-Location '$pwd'")) `
        -ScriptBlock { 
            [Console]::OutputEncoding = [Text.Encoding]::Utf8;
            function PlaySlowedAudio {
                Param (
                    [string] [Parameter(Mandatory=$true)] $slowFilename
                );
                Write-Output "Playing $slowFilename";
                ffplay.exe `
                    -loglevel error `
                    -autoexit `
                    -nodisp $slowFilename;
                Write-Output "Finished playing $slowFilename";
            };
            PlaySlowedAudio $input; 
        };
    Write-Host "Press any key once you hear the character below being pronounced";
    # Record the speech timing
    RecordSpeechTiming $filename $sentence;
}

