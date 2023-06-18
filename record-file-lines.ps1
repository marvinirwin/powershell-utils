. "${PSScriptRoot}/recording-utils"


# TODO make two options, either record all sentences which don't have sentences yet, or record one where 
$readMode = Read-Char "Read unfinished sentences (u), or review old ones (o)?";

function File-Sentences() {
    Param (
        [Parameter(Mandatory=$true)] $filename
    );
    $sentences = [System.Collections.ArrayList]@();
    foreach($sentence in Get-Content -encoding UTF8 $filename) {
        $sentences.Add(@{
            'sentence' = $sentence 
            'lastModified' = $(Get-ChildItem $(JsonFilename $sentence) -ErrorAction SilentlyContinue | Select -ExpandProperty LastWriteTime)
        }) | Out-Null;

    }
    return $sentences;
}

function Unrecorded-Sentence() {
    Param (
        [Parameter(Mandatory=$true)] $sentences
    );
    return $sentences `
        | Where-Object {$_.lastModified -eq $null} `
        | Select-Object -First 1;
}


while ($true) {
    
    switch ($readMode)
    {
        u {

            $unRecordedSentence = Unrecorded-Sentence $(File-Sentences $args[0]);
            while ($unRecordedSentence -ne $null) {
                RecordSentence $unRecordedSentence['sentence'];
                $unRecordedSentence = Unrecorded-Sentence $(File-Sentences $args[0]);
            }
        }
        o {
            $sentences = File-Sentences $args[0];
            $sorted = $sentences `
                | Sort-Object -Property lastModified -Descending `
                | % { $_['sentence'].subString(0, [System.Math]::Min(10, $_['sentence'].Length))  } `
                | % { "$($_)..." } `
                | Select-Object -First 10;

            $chosenSentenceIndex = menu -ReturnIndex $sorted;
            RecordSentence $sentences[$chosenSentenceIndex]['sentence'];
        }
        default {
            Throw "Enter (u) or (o)"
        }
    }
}


