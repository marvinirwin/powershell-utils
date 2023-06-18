[string]$ltUser = $env:LT_USER;
[string]$ltKeyPassword = $env:LT_KEY_PASSWORD;
[securestring]$secStringPassword = ConvertTo-SecureString $ltKeyPassword -AsPlainText -Force;
[pscredential]$credential = New-Object System.Management.Automation.PSCredential($ltUser, $secStringPassword);

function CopyFileToVideo {
    Param(
        [string] [Parameter(Mandatory = $true)] $filename
    )
    Write-Host "Moving $filename to marvinirwin.com";
    Set-SCPFile `
        -ComputerName '165.227.49.247' `
        -RemotePath "/video/" `
        -LocalFile "$filename" `
        -Credential $credential `
        -KeyFile ~/.ssh/id_rsa;
}


function HashString {
    Param(
        [string] [Parameter(Mandatory = $true)] $inputString
    )
    $stream = [IO.MemoryStream]::new([byte[]][char[]]$inputString)
    return Get-FileHash -InputStream $mystream -Algorithm SHA256
}

function VideoFilename {
    Param(
        [string] [Parameter(Mandatory = $true)] $sentence
    )
    return "$(Get-StringHash $sentence).mkv"
}
function WebMFilename {
    Param(
        [string] [Parameter(Mandatory = $true)] $sentence
    )
    return "$(Get-StringHash $sentence).webm"
}
function JsonFilename {
    Param(
        [string] [Parameter(Mandatory = $true)] $sentence
    )
    return "$(Get-StringHash $sentence).json"
}
function SlowFilename {
    Param(
        [string] [Parameter(Mandatory = $true)] $sentence
    )
    return "slow_$(Get-StringHash $sentence).aac"
}
function AudioFilename {
    Param(
        [string] [Parameter(Mandatory = $true)] $sentence
    )
    return "$(Get-StringHash $sentence).wav"
}

#http://jongurgul.com/blog/get-stringhash-get-filehash/ 
Function Get-StringHash([String] $String, $HashName = "SHA1") {
    $StringBuilder = New-Object System.Text.StringBuilder;
    [System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($String.Normalize([Text.NormalizationForm]::FormC))
    ) | % { [Void]$StringBuilder.Append($_.ToString("x2")) }
         
    RETURN $StringBuilder.ToString() 
}

function RecordSpeechTiming {
    Param (
        [string] [Parameter(Mandatory = $true)] $sentence
    );
    # I'll assume normalized
    $stopwatch = New-Object System.Diagnostics.Stopwatch;
    $stopwatch.Start();
    $charArray = $sentence.toCharArray();
    $object = @{
        "sentence"      = $sentence;
        "timeScale"     = 0.50;
        "characters"    = @();
        "filename"      = VideoFilename $sentence;
        "audioFilename" = AudioFilename $sentence;
    };
    foreach ($char in $charArray) {
        if ($char -cmatch '[\u4e00-\u9fff]') {
            Write-Host "Press space when you hear $char";
            $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | out-null;
        }
        $timestamp = $stopwatch.Elapsed.TotalMilliseconds;
        $object['characters'] += , @{'timestamp' = $timestamp; 'character' = $char };
    }
    ConvertTo-Json $object | Set-Content -Encoding UTF8 $(JsonFilename $sentence)
    # CopyFileToVideo "$filename.json";
};

function CreateSlowedFile {
    Param (
        [string] [Parameter(Mandatory = $true)] $sentence
    );

    Write-Host "Creating slowed file $(SlowFilename $sentence)";
    ffmpeg.exe `
        -loglevel error `
        -i $(VideoFilename $sentence) `
        -y `
        -vn `
        -filter:a "atempo=0.5" `
    $(SlowFilename $sentence);
}
function CreateAudioFile {
    Param (
        [string] [Parameter(Mandatory = $true)] $sentence
    );

    Write-Host "Creating audio file $(AudioFilename $sentence)";
    ffmpeg.exe `
        -loglevel error `
        -i $(VideoFilename $sentence) `
        -y `
        -vn `
    $(AudioFilename $sentence);
}

function Read-Char() {
    Param (
        [string] [Parameter(Mandatory = $true)] $prompt
    );
    Write-Host $prompt;
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    return $key.Character;
}

function CreateWebM () {
    Param (
        [string] [Parameter(Mandatory = $true)] $sentence
    );
    Write-Host "Creating WebM $(WebMFilename $sentence)";
    ffmpeg.exe -y `
        -loglevel error `
        -i $(VideoFilename $sentence) `
    $(WebMFilename $sentence);

}

function Upload-S3File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$key,
        [Parameter(Mandatory = $true)]
        [string]$file
    )
    Write-Host "Initializing upload to S3..."
    $accessKey = [System.Environment]::GetEnvironmentVariable('AWS_ACCESS_KEY_ID')
    $secretKey = [System.Environment]::GetEnvironmentVariable('AWS_SECRET_ACCESS_KEY')
    $region = [System.Environment]::GetEnvironmentVariable('AWS_DEFAULT_REGION')
    Write-Host "File upload completed successfully."
    $bucket = [System.Environment]::GetEnvironmentVariable('AWS_S3_BUCKET')
    $s3Client = New-Object Amazon.S3.AmazonS3Client($accessKey, $secretKey, $region)
    $putObjectRequest = New-Object Amazon.S3.Model.PutObjectRequest
    $putObjectRequest.BucketName = $bucket
    $putObjectRequest.Key = $key
    $putObjectRequest.FilePath = $file
    $putObjectRequest.CannedACL = [Amazon.S3.S3CannedACL]::PublicRead
    $s3Client.PutObject($putObjectRequest)
}


function RecordSentence {
    Param (
        [string] [Parameter(Mandatory = $true)] $sentence
    );
    $shouldRecord = Read-Char "$sentence Record (y) Continue (Enter)"

    if ($shouldRecord -ne "y") {
        return;
    }

    # Record the sentence to filename.mp4
    clear;
    Write-Host "$sentence (press q to finish)";

    $recordSuccess = "r";
    $videoFilter = "crop=in_w-900:in_h-200"
    # -filter:v "transpose=1" 
    while ($recordSuccess -eq "r") {
        ffmpeg.exe -y `
            -loglevel fatal `
            -f dshow `
            -rtbufsize 2G `
            -framerate 60 `
            -audio_buffer_size 30 `
            -i video="$env:WEBCAM":audio="$env:MICROPHONE" `
            -filter:v $videoFilter `
            -preset ultrafast `
            -tune zerolatency `
        $(VideoFilename $sentence) `
            -pix_fmt yuv420p `
            -filter:v $videoFilter `
            -window_x -1 `
            -window_y -1 `
            -vf "$videoFilter,scale=320:-1" `
            -f sdl :0 `
            -vn `
        $(AudioFilename $sentence);
        
        $recordSuccess = Read-Char "Retry (r) Continue (Enter)";
    }

    # CopyFileToVideo $(VideoFilename $sentenc);

    CreateWebM $sentence;
    CreateSlowedFile $sentence;
    CreateAudioFile $sentence;

    # Play the slowed down audio

    $timingSuccess = "r";

    while ($timingSuccess -eq "r") {
        $job = Start-Job `
            -InputObject $(SlowFilename $sentence) `
            -Init ([ScriptBlock]::Create("Set-Location '$pwd'")) `
            -ScriptBlock { 
            [Console]::OutputEncoding = [Text.Encoding]::Utf8;
            function PlaySlowedAudio {
                Param (
                    [string] [Parameter(Mandatory = $true)] $slowFilename
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
            RecordSpeechTiming $sentence;
        }
        finally {
            $job | Remove-Job -Force;
        }

        $timingSuccess = Read-Char "Retry (r) Continue (Enter)"
    }
    Remove-Item $(SlowFilename $sentence);
}
