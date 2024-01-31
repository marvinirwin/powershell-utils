<# [string]$ltUser = $env:LT_USER;
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
} #>


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

function insertToDatabase($sentence, $characterTimings) {
    # Assumes SHA1 function exists
    $sentenceHash = Get-StringHash $sentence

    try {
        # Configure and open the database connection
        $connectionString = "Host=db-postgresql-sgp1-25152-do-user-4530359-0.b.db.ondigitalocean.com;Port=25060;Database=postgres;Username=doadmin;Password=AVNS_iN8DhlA7v3mVugbbrjH;"
        $connection = New-Object -TypeName Npgsql.NpgsqlConnection -ArgumentList $connectionString
        $connection.Open()

        # Select existing rows
        $selectCommand = $connection.CreateCommand()
        $selectCommand.CommandText = "SELECT * FROM video_metadata WHERE sentence_hash = :hash;"
        $selectCommand.Parameters.AddWithValue("hash", $sentenceHash)
        $reader = $selectCommand.ExecuteReader()

        $rows = while ($reader.Read()) { $reader.GetValue(0) }

        # Close the reader
        $reader.Close()

        # Prepare base metadata
        $baseMetadata = @{
            "sentence"      = $sentence
            "sentence_hash" = $sentenceHash
            "metadata"      = ConvertTo-Json -InputObject @{
                "sentence"      = $sentence
                "timeScale"     = 0.5
                "characters"    = $characterTimings
                "filename"      = $sentenceHash + "-video"
                "audioFilename" = $sentenceHash + "-audio"
            }
        }

        $insertCommand = $connection.CreateCommand()
        if ($rows.Count -gt 0) {
            # Update existing metadata
            $insertCommand.CommandText = "UPDATE video_metadata SET sentence = :sentence, sentence_hash = :hash, metadata = :metadata, s3_url = :url WHERE video_metadata_id = :id;"
            $insertCommand.Parameters.AddWithValue("id", $rows[0])
        }
        else {
            # Insert new metadata
            $insertCommand.CommandText = "INSERT INTO video_metadata (sentence, sentence_hash, metadata, s3_url) VALUES (:sentence, :hash, :metadata, :url);"
        }
        $insertCommand.Parameters.AddWithValue("sentence", $baseMetadata["sentence"])
        $insertCommand.Parameters.AddWithValue("hash", $baseMetadata["sentence_hash"])
        $insertCommand.Parameters.AddWithValue("metadata", $baseMetadata["metadata"])
        $insertCommand.Parameters.AddWithValue("url", "https://languagetrainer-documents.s3.us-west-2.amazonaws.com/" + $sentenceHash + "-video")

        $insertCommand.ExecuteNonQuery() > 0
    }
    catch {
        throw "Error: $_"
    }
    finally {
        # Always close the connection, even if an error occurred
        $connection.Close()
    }
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
    
    $audioKey = Get-StringHash $sentence + '-audio'
    $videoKey = Get-StringHash $sentence + '-video'

    # Upload video and audio files to S3
    Write-Host "Preparing to upload files to S3..."
    Upload-S3File -key $audioKey -file $audioFile
    Upload-S3File -key $videoKey -file $videoFile
    Write-Host "Files uploaded successfully to S3."

    Write-Host "Setting database record"
    $jsonFilename = JsonFilename $sentence
    $characterTimings = Get-Content $jsonFilename | ConvertFrom-Json
    insertToDatabase $sentence $characterTimings
    Write-Host "Finished setting database record"

    Remove-Item $(SlowFilename $sentence);
}
