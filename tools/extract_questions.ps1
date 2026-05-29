param(
  [string]$SourceDir = '',
  [string]$OutFile = (Join-Path (Split-Path $PSScriptRoot -Parent) 'questions.js'),
  [string]$ReportFile = (Join-Path (Split-Path $PSScriptRoot -Parent) 'extraction-report.json')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $SourceDir) {
  $root = Split-Path $PSScriptRoot -Parent
  $SourceDir = (Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -like '*2024-2025*' } | Select-Object -First 1).FullName
}
if (-not $SourceDir) {
  throw 'Could not find source question directory.'
}

$rxAnswer = '^\u3010\u6b63\u786e\u7b54\u6848\u662f\u3011\s*[:\uff1a]?\s*(.+)$'
$rxAnswerStart = '^\u3010\u6b63\u786e\u7b54\u6848\u662f\u3011'
$rxChapter = '^(\u7b2c.+\u7ae0|\u5bfc\u8bba|\u5171\u4ea7\u4e3b\u4e49\u662f)'
$rxChapterSkip = '\u76ee\u6807|\u603b\u5171|\u6b63\u786e\u7b54\u6848'
$rxGoal = '^\u76ee\u6807\s*\d+\s*[\uff08(]([^\uff09)]+)[\uff09)]'
$rxMultiple = '\u591a\u9879\u9009\u62e9'
$rxSingle = '\u5355\u9879\u9009\u62e9'
$rxJudge = '\u5224\u65ad\u9898'
$rxTotal = '\u603b\u5171\s*(\d+)\s*\u9053'
$rxQuestionStart = '^\s*(\d+)[\u3001\.\uff0e]\s*(.+)$'
$rxOption = '^([A-D])[\.\uff0e\u3001]?\s*(.+)$'
$rxQuestionHeading = '^\u76ee\u6807|^\u4e00\u3001|^\u4e8c\u3001|^\u4e09\u3001'

function Normalize-Text([string]$text) {
  if ($null -eq $text) { return '' }
  return ($text -replace [char]0x00A0, ' ' -replace '\s+', ' ').Trim()
}

function Get-DocxLines([string]$path) {
  $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
  try {
    $entry = $zip.GetEntry('word/document.xml')
    $reader = [System.IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8)
    try { [xml]$doc = $reader.ReadToEnd() } finally { $reader.Close() }
  } finally {
    $zip.Dispose()
  }

  $ns = [Xml.XmlNamespaceManager]::new($doc.NameTable)
  $ns.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
  return @($doc.SelectNodes('//w:p', $ns) | ForEach-Object {
    Normalize-Text (($_.SelectNodes('.//w:t', $ns) | ForEach-Object { $_.'#text' }) -join '')
  } | Where-Object { $_ })
}

function Get-DocLines([string]$path) {
  $bytes = [IO.File]::ReadAllBytes($path)
  $text = [Text.Encoding]::Unicode.GetString($bytes)
  $text = $text -replace '[^\u0009\u000A\u000D\u0020-\u007E\u00A0\u3000-\u303F\u4E00-\u9FFF\uFF00-\uFFEF]', "`n"
  $text = $text -replace 'Root Entry|SummaryInformation|DocumentSummaryInformation|WordDocument|WPS Office|KSOProductBuildVer|WpsCustomData', "`n"
  return @($text -split "[`r`n]+" | ForEach-Object { Normalize-Text $_ } | Where-Object { $_ })
}

function Get-Lines([string]$path) {
  if ([IO.Path]::GetExtension($path).ToLowerInvariant() -eq '.docx') {
    return Get-DocxLines $path
  }
  return Get-DocLines $path
}

function Normalize-Lines($lines) {
  $result = [System.Collections.Generic.List[string]]::new()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = Normalize-Text $lines[$i]
    if (-not $line) { continue }
    if ($line -match '^\d+[\u3001\.\uff0e]$' -and $i + 1 -lt $lines.Count) {
      $nextQuestionText = Normalize-Text $lines[$i + 1]
      if ($nextQuestionText -and $nextQuestionText -notmatch $script:rxAnswerStart) {
        $result.Add("$line$nextQuestionText")
        $i++
        continue
      }
    }
    if ($line -match '^[A-D]$' -and $i + 1 -lt $lines.Count) {
      $next = Normalize-Text $lines[$i + 1]
      if ($next -and $next -notmatch '^(A|B|C|D)$' -and $next -notmatch $script:rxAnswerStart -and $next -notmatch $script:rxQuestionStart) {
        $result.Add("$line.$next")
        $i++
        continue
      }
    }
    $result.Add($line)
  }
  return @($result)
}

function Make-QuestionId([string]$fileStem, [string]$goal, [string]$type, [int]$index) {
  $safeStem = ($fileStem -replace '\s+', '-' -replace '[^\u4e00-\u9fffA-Za-z0-9\-]', '')
  $safeGoal = ($goal -replace '\s+', '' -replace '[^\u4e00-\u9fffA-Za-z0-9]', '')
  return "$safeStem-$safeGoal-$type-$('{0:D3}' -f $index)"
}

function Split-InlineOptions($current) {
  if ($null -eq $current -or $current.type -eq 'judge' -or $current.options.Count -gt 0) { return }
  $text = [string]$current.question
  $matches = [regex]::Matches($text, '(?<![A-Za-z])([A-D])[\.\uff0e\u3001]?')
  if ($matches.Count -lt 2 -or $matches[0].Index -le 0) { return }

  $options = @()
  for ($i = 0; $i -lt $matches.Count; $i++) {
    $start = $matches[$i].Index + $matches[$i].Length
    $end = if ($i + 1 -lt $matches.Count) { $matches[$i + 1].Index } else { $text.Length }
    $optionText = Normalize-Text $text.Substring($start, $end - $start)
    if ($optionText) {
      $options += [pscustomobject]@{ key = $matches[$i].Groups[1].Value; text = $optionText }
    }
  }
  if ($options.Count -ge 2) {
    $current.question = Normalize-Text $text.Substring(0, $matches[0].Index)
    $current.options = $options
  }
}

function Parse-Questions([string]$path) {
  $rawLines = Get-Lines $path
  $lines = Normalize-Lines $rawLines
  $fileStem = [IO.Path]::GetFileNameWithoutExtension($path)
  $chapter = $fileStem
  $goal = ''
  $type = ''
  $questions = [System.Collections.Generic.List[object]]::new()
  $current = $null
  $typeCounters = @{}

  foreach ($line in $lines) {
    if ($line -match $script:rxChapter) {
      if ($line -notmatch $script:rxChapterSkip) { $chapter = $line }
    }
    if ($line -match $script:rxGoal) {
      $goal = $Matches[1]
      continue
    }
    if ($line -match $script:rxMultiple) {
      $type = 'multiple'
      continue
    }
    if ($line -match $script:rxSingle) {
      $type = 'single'
      continue
    }
    if ($line -match $script:rxJudge) {
      $type = 'judge'
      continue
    }
    if ($line -match $script:rxAnswer) {
      if ($null -ne $current) {
        $answerText = (Normalize-Text $Matches[1]).ToUpperInvariant()
        if ($current.type -eq 'judge' -or $answerText -match '\u6b63\u786e|\u9519\u8bef|\u662f|\u5426') {
          $current.type = 'judge'
          if ($answerText -match '\u6b63\u786e|\u662f') {
            $answer = @([regex]::Unescape('\u662f'))
          } elseif ($answerText -match '\u9519\u8bef|\u5426') {
            $answer = @([regex]::Unescape('\u5426'))
          } else {
            $answer = @($answerText)
          }
        } else {
          Split-InlineOptions $current
          $answer = @($answerText.ToCharArray() | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^[A-D]$' })
        }
        $current.answer = $answer
        $questions.Add([pscustomobject]$current)
        $current = $null
      }
      continue
    }
    if ($line -match $script:rxQuestionStart -and $type) {
      $key = "$goal|$type"
      if (-not $typeCounters.ContainsKey($key)) { $typeCounters[$key] = 0 }
      $typeCounters[$key]++
      $current = [ordered]@{
        id = Make-QuestionId $fileStem $goal $type $typeCounters[$key]
        chapter = $chapter
        goal = $goal
        type = $type
        question = Normalize-Text $Matches[2]
        options = @()
        answer = @()
      }
      continue
    }
    if ($type -and $null -eq $current -and $line -notmatch $script:rxQuestionHeading -and $line -notmatch $script:rxOption -and $line -notmatch $script:rxAnswerStart -and $line -notmatch '^(PAGE|\d+|[A-Z])$') {
      $key = "$goal|$type"
      if (-not $typeCounters.ContainsKey($key)) { $typeCounters[$key] = 0 }
      $typeCounters[$key]++
      $current = [ordered]@{
        id = Make-QuestionId $fileStem $goal $type $typeCounters[$key]
        chapter = $chapter
        goal = $goal
        type = $type
        question = Normalize-Text $line
        options = @()
        answer = @()
      }
      continue
    }
    if ($null -ne $current) {
      if ($current.type -ne 'judge' -and $line -match $script:rxOption) {
        $current.options += [pscustomobject]@{ key = $Matches[1]; text = Normalize-Text $Matches[2] }
      } elseif ($line -notmatch $script:rxQuestionHeading) {
        $current.question = Normalize-Text ($current.question + ' ' + $line)
      }
    }
  }

  $answerMarkers = ($lines | Where-Object { $_ -match $script:rxAnswerStart }).Count
  $joined = $lines -join "`n"
  return [pscustomobject]@{
    file = [IO.Path]::GetFileName($path)
    declaredTotal = if ($joined -match $script:rxTotal) { [int]$Matches[1] } else { $null }
    answerMarkers = $answerMarkers
    parsed = $questions.Count
    questions = @($questions)
  }
}

$allQuestions = [System.Collections.Generic.List[object]]::new()
$report = [System.Collections.Generic.List[object]]::new()

Get-ChildItem -LiteralPath $SourceDir -File | Where-Object { $_.Extension -in '.doc', '.docx' } | Sort-Object Name | ForEach-Object {
  $parsed = Parse-Questions $_.FullName
  foreach ($q in $parsed.questions) { $allQuestions.Add($q) }
  $report.Add([pscustomobject]@{
    file = $parsed.file
    declaredTotal = $parsed.declaredTotal
    answerMarkers = $parsed.answerMarkers
    parsed = $parsed.parsed
    ok = ($parsed.answerMarkers -eq $parsed.parsed)
  })
}

$questionsJson = $allQuestions | ConvertTo-Json -Depth 8
$js = "window.QUESTION_BANK = $questionsJson;`n"
[IO.File]::WriteAllText($OutFile, $js, [Text.UTF8Encoding]::new($false))

$reportObject = [pscustomobject]@{
  generatedAt = (Get-Date).ToString('s')
  sourceDir = $SourceDir
  totalQuestions = $allQuestions.Count
  files = @($report)
}
[IO.File]::WriteAllText($ReportFile, ($reportObject | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

$reportObject | ConvertTo-Json -Depth 6
