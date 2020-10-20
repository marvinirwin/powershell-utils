function HashString {
    Param(
        [string] [Parameter(Mandatory=$true)] $inputString
    )
    $stream = [IO.MemoryStream]::new([byte[]][char[]]$inputString)
    return Get-FileHash -InputStream $mystream -Algorithm SHA256
}

#http://jongurgul.com/blog/get-stringhash-get-filehash/ 
Function Get-StringHash([String] $String,$HashName = "SHA1") 
{ 
$StringBuilder = New-Object System.Text.StringBuilder 
[System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String))|%{ 
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
        -loglevel fatal `
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
    ffmpeg.exe -y `
        -loglevel fatal `
        -f dshow ` `
        -i video="DroidCam Source 3":audio="Microphone (DroidCam Virtual Audio)" `
        "${filename}_90.mp4";

    Write-Host "Rotating video 90 degrees";
    ffmpeg.exe -y `
        -loglevel fatal `
        -i "${filename}_90.mp4" `
        -vf "transpose=2" `
        "${filename}.mp4" 
    Remove-Item "${filename}_90.mp4"


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
