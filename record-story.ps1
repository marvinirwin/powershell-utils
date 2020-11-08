. "${PSScriptRoot}/recording-utils"


$story = Get-Content -Encoding UTF8 $args[0] -Raw;

Function splitAppend {
  $sentences = $args[1].Split($args[0]);
  return $sentences | % {$_ + $args[0]};
}

$splits = splitAppend "。" $story;
foreach($sentence in $splits) {
    $sentence = $sentence + "。";
    RecordSentence $sentence;
}

