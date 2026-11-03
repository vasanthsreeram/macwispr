# CI only (disposable runner, admin): give the machine a real audio endpoint pair.
# Installs VB-Audio Virtual Cable (signed driver, official download, pinned hash):
# audio played to "CABLE Input" comes back on the recording device "CABLE Output".
$ErrorActionPreference = "Stop"
$url = "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip"
$sha = "B950E39F01AF1D04EA623C8F6D8EB9B6EA5C477C637295FABF20631C85116BFB"
$dir = Join-Path $env:RUNNER_TEMP "vbcable"
New-Item -ItemType Directory -Force $dir | Out-Null
Invoke-WebRequest $url -OutFile "$dir\pack.zip"
$got = (Get-FileHash "$dir\pack.zip" -Algorithm SHA256).Hash
if ($got -ne $sha) { throw "VB-CABLE pack hash mismatch: $got" }
Expand-Archive "$dir\pack.zip" -DestinationPath $dir -Force

$inf = "$dir\vbMmeCable64_win10.inf"
$sig = Get-AuthenticodeSignature "$dir\vbaudio_cable64_win10.cat"
"catalog signature: $($sig.Status) signer: $($sig.SignerCertificate.Subject) issuer: $($sig.SignerCertificate.Issuer)"
if ($sig.Status -ne "Valid") { throw "driver catalog signature is not valid" }
# Trusting the publisher only skips the interactive "install this device software?" prompt.
$cer = "$dir\vbaudio.cer"
[IO.File]::WriteAllBytes($cer, $sig.SignerCertificate.Export("Cert"))
certutil -addstore -f TrustedPublisher $cer | Out-Null

# Windows Server ships with the audio service disabled.
foreach ($svc in "AudioEndpointBuilder", "Audiosrv") {
    Set-Service $svc -StartupType Automatic
    Start-Service $svc
}

python "$PSScriptRoot\ci_root_device.py" $inf "VBAudioVACWDM"
if ($LASTEXITCODE) { throw "root device install failed" }
Start-Sleep 5
Restart-Service Audiosrv -Force
Start-Sleep 3
Get-PnpDevice -Class MEDIA, AudioEndpoint -ErrorAction SilentlyContinue |
    Format-Table Status, Class, FriendlyName, InstanceId -AutoSize | Out-String -Width 200
