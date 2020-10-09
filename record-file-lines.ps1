. "${PSScriptRoot}/recording-utils"


foreach($sentence in Get-Content -encoding UTF8 $args[0]) {
    RecordSentence $sentence
}

