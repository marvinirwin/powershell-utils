function CopyFileToVideo {
    Param(
        [string] [Parameter(Mandatory=$true)] $filename
    )
    [string]$ltUser = $env:LT_USER;
    [string]$ltKeyPassword = $env:LT_KEY_PASSWORD;
    [securestring]$secStringPassword = ConvertTo-SecureString $ltKeyPassword -AsPlainText -Force;
    [pscredential]$credential = New-Object System.Management.Automation.PSCredential ($ltUser, $secStringPassword);
    Set-SCPFile `
        -ComputerName 'marvinirwin.com' `
        -RemotePath "/video/" `
        -LocalFile "$filename" `
        -Credential $credential `
        -KeyFile ~/.ssh/id_rsa;
}


function HashString {
    Param(
        [string] [Parameter(Mandatory=$true)] $inputString
    )
    $stream = [IO.MemoryStream]::new([byte[]][char[]]$inputString)
    return Get-FileHash -InputStream $mystream -Algorithm SHA256
}

#http://jongurgul.com/blog/get-stringhash-get-filehash/ 
Function Get-StringHash([String] $String,$HashName = "SHA1") {
    $StringBuilder = New-Object System.Text.StringBuilder 
    [System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String)) | % { 
        [Void]$StringBuilder.Append($_.ToString("x2")) 
    } 
    $StringBuilder.ToString() 
}

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
        "timeScale" = 0.50;
        "characters" = @();
        "filename" = "${filename}.mov";
    };
    foreach($char in $charArray) {
        if($char -cmatch '[\u4e00-\u9fff]'){
            Write-Host "Press space when you hear $char";
            $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | out-null;
        }
        $timestamp = $stopwatch.Elapsed.TotalMilliseconds;
        $object['characters'] += , @{'timestamp' = $timestamp; 'character' = $char};
    }
    ConvertTo-Json $object | Set-Content -Encoding UTF8 "${filename}.json"
    CopyFileToVideo "$filename.json";
};

function CreateSlowedFile {
    Param (
        [string] [Parameter(Mandatory=$true)] $filename
    );
    $slowedFile = "slow_${filename}.aac";
    Write-Host "Creating slowed file $slowedFile";
    ffmpeg.exe `
        -loglevel fatal `
        -i "${filename}.mov" `
        -y `
        -vn `
        -filter:a "atempo=0.5" `
        "$slowedFile";
}

function RecordSentence {
    Param (
        [string] [Parameter(Mandatory=$true)] $sentence
    );
    $shouldRecord = Read-Host "Record $sentence ?  Press (y) to record, or enter to continue"

    if ($shouldRecord -ne "y") {
        return;
    }

    # Create a without invalid characters
    $filename = Get-StringHash $sentence.Normalize([Text.NormalizationForm]::FormC);

    # Record the sentence to filename.mp4
    Write-Host "Recording: $sentence press q to finish";

    $recordSuccess = "r";
    while ($recordSuccess -eq "r") {
        ffmpeg.exe -y `
            -loglevel error `
            -f dshow `
            -rtbufsize 100M `
            -framerate 60 `
            -audio_buffer_size 100 `
            -i video="Logitech BRIO":audio="Microphone (Logitech BRIO)" `
            "$filename.mov" `
            -pix_fmt yuv420p;
            # -f sdl :0;
        CopyFileToVideo "$filename.mov";
        $recordSuccess = Read-Host "Did the recording succeed? Press (r) to try again, or enter to continue"
    }

    # Create a slowed version of the file "slow_$filename.mov"`
    CreateSlowedFile $filename;

    $slowFilename = "slow_${filename}.aac";
    # Play the slowed down audio

    $timingSuccess = "r";

    while ($timingSuccess -eq "r") {
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
                        -loglevel fatal `
                        -autoexit `
                        -nodisp $slowFilename;
                    Write-Output "Finished playing $slowFilename";

                };
                PlaySlowedAudio $input; 
            };

        try {
          Write-Host "Press any key once you hear the character below being pronounced";
          # Record the speech timing
          RecordSpeechTiming $filename $sentence;
        } finally {
          $job | Remove-Job -Force;
        }

        $timingSuccess = Read-Host "Did the character timing succeed? Press (r) to try again, or enter key to continue"
    }
}
