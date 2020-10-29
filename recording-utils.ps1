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
        "filename" = "${filename}.mp4";
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
};

function CreateSlowedFile {
    Param (
        [string] [Parameter(Mandatory=$true)] $filename
    );
    $slowedFile = "slow_${filename}.aac";
    Write-Host "Creating slowed file $slowedFile";
    ffmpeg.exe -i "${filename}.mp4" `
        -y `
        -vn `
        -filter:a "atempo=0.5" `
        "$slowedFile";
}

function RecordSentence {
    Param (
        [string] [Parameter(Mandatory=$true)] $sentence
    );
    # Create a without invalid characters
    $filename = Get-StringHash $sentence.Normalize([Text.NormalizationForm]::FormC);

    # Record the sentence to filename.mp4
    Write-Host "Recording: $sentence press q to finish";
    # TODO will this resolve the location with PATH?
    Invoke-NativeCommand -FilePath ffmpeg.exe -ArgumentList @(
        "-y",
        "-f", "dshow",
        "-loglevel", "fatal",  
        "-i", "video=@device_pnp_\\?\usb#vid_07ca&pid_313a&mi_00#7&14881977&0&0000#{65e8773d-8f56-11d0-a3b9-00a0c9223196}\global:audio=@device_cm_{33D9A762-90C8-11D0-BD43-00A0C911CE86}\wave_{6EDC73A4-7FF7-4F94-957A-AB29B58F2895}",
        "${filename}.mp4",
        "-pix_fmt", "yuv420p",
        "-window_x", "0",
        "-window_y", "0",
        "-f", "sdl", ":0"
    ) | Receive-RawPipeline;

    <#ffmpeg.exe -y `
        -f dshow `
        -rtbufsize 100M `
        -s 1920x1080 `
        -r 30 `
        -i video="@device_pnp_\\?\usb#vid_07ca&pid_313a&mi_00#7&14881977&0&0000#{65e8773d-8f56-11d0-a3b9-00a0c9223196}\global":audio="@device_cm_{33D9A762-90C8-11D0-BD43-00A0C911CE86}\wave_{6EDC73A4-7FF7-4F94-957A-AB29B58F2895}" `
        -c:v libx264 `
        -q 0 `
        -f h264 – |
        ffmpeg -f h264 -i – -an -c:v copy -f mp4 file.mp4 -an -c:v copy -f h264 pipe:play | ffplay -i pipe:play
        "${filename}_90.mp4";#>

    <# Write-Host "Rotating video 90 degrees";
    ffmpeg.exe -y `
        -loglevel fatal `
        -i "${filename}_90.mp4" `
        -vf "transpose=2" `
        "${filename}.mp4" 
    Remove-Item "${filename}_90.mp4"#>


    # Create a slowed version of the file "slow_$filename.mp4"`
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

}
