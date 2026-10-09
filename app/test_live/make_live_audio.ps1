# Two synthetic recordings for the live check of the speech and tutor routes:
# an English self-introduction with a learner's typical slips (SAPI, Zira)
# and a Turkish sentence (WinRT, Tolga). 16-bit mono WAV.
param([Parameter(Mandatory = $true)][string]$OutDir)

Add-Type -AssemblyName System.Speech
$english = 'Hello. My name is Ali. I am thirty years old. I am work in a bank in Istanbul. ' +
  'I live with my wife and my cat. Every morning I am drinking coffee and I go to work by metro. ' +
  'In the weekend I like play football with my friends. I want learn English because I want travel to London.'
$sapi = New-Object System.Speech.Synthesis.SpeechSynthesizer
$sapi.SelectVoice('Microsoft Zira Desktop')
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$sapi.SetOutputToWaveFile((Join-Path $OutDir 'live_en.wav'), $format)
$sapi.Speak($english)
$sapi.Dispose()

# WinRT: synthesize to a stream, then copy it to a file.
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Await($operation, [Type]$resultType) {
  $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($operation))
  $task.Wait() | Out-Null
  $task.Result
}
$winrt = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$winrt.Voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -eq 'tr-TR' } | Select-Object -First 1
$stream = Await ($winrt.SynthesizeTextToStreamAsync('Canım sıkıldı, hadi dışarı çıkalım.')) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
$reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
$size = [uint32]$stream.Size
$null = Await ($reader.LoadAsync($size)) ([uint32])
$bytes = New-Object byte[] $size
$reader.ReadBytes($bytes)
[System.IO.File]::WriteAllBytes((Join-Path $OutDir 'live_tr.wav'), $bytes)

Get-ChildItem $OutDir -Filter 'live_*.wav' | ForEach-Object { $_.Name + ' ' + $_.Length }
