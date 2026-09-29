$ErrorActionPreference = 'Stop'

$environmentFile = Join-Path (Get-Location).Path '.deploy.env'
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code $LASTEXITCODE)."
    }
}

try {
    $publicIp = $env:PUBLIC_IP
    $username = $env:SSH_USERNAME
    $privateKey = $env:SSH_PRIVATE_KEY

    $parsedIp = $null
    if (-not [System.Net.IPAddress]::TryParse($publicIp, [ref]$parsedIp) -or
        $parsedIp.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'PUBLIC_IP must contain a valid IPv4 address.'
    }
    if ($username -ne 'ubuntu') {
        throw 'The chat-ec2-private-key Jenkins credential must use the ubuntu username.'
    }
    if ([string]::IsNullOrWhiteSpace($privateKey) -or -not (Test-Path -LiteralPath $privateKey)) {
        throw 'The SSH private key supplied by Jenkins was not found.'
    }
    if ([string]::IsNullOrWhiteSpace($env:CHAT_MONGODB_URI) -or
        [string]::IsNullOrWhiteSpace($env:CHAT_JWT_SECRET)) {
        throw 'The chat-mongodb-uri and chat-jwt-secret Jenkins credentials must not be empty.'
    }

    $frontendOrigin = "http://$publicIp"
    $environmentContent = @"
MONGODB_URI=$($env:CHAT_MONGODB_URI)
JWT_SECRET=$($env:CHAT_JWT_SECRET)
PORT=5001
NODE_ENV=production
FRONTEND_ORIGIN=$frontendOrigin
FRONTEND_PORT=80
"@
    [System.IO.File]::WriteAllText($environmentFile, $environmentContent, $utf8WithoutBom)

    $sshOptions = @(
        '-i', $privateKey,
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=NUL',
        '-o', 'ConnectTimeout=10'
    )
    $hostAddress = "$username@$publicIp"
    $connected = $false

    for ($attempt = 1; $attempt -le 30; $attempt++) {
        & ssh @sshOptions $hostAddress 'exit' *> $null
        if ($LASTEXITCODE -eq 0) {
            $connected = $true
            break
        }
        if ($attempt -lt 30) {
            Start-Sleep -Seconds 10
        }
    }
    if (-not $connected) {
        throw "Could not connect to $hostAddress after 30 attempts. Check the EC2 status, SSH key, and admin CIDR."
    }

    Invoke-CheckedCommand -Executable 'scp' -Arguments ($sshOptions + @(
        'scripts/deploy-ec2.sh',
        "${hostAddress}:/tmp/chat-deploy-ec2.sh"
    )) -FailureMessage 'Could not upload the EC2 deployment script'
    Invoke-CheckedCommand -Executable 'scp' -Arguments ($sshOptions + @(
        $environmentFile,
        "${hostAddress}:/home/ubuntu/chat-app.env"
    )) -FailureMessage 'Could not upload the application environment'
    Invoke-CheckedCommand -Executable 'ssh' -Arguments ($sshOptions + @(
        $hostAddress,
        'sudo bash /tmp/chat-deploy-ec2.sh ubuntu'
    )) -FailureMessage 'Remote application deployment failed'
}
catch {
    Write-Host "Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $environmentFile) {
        Remove-Item -LiteralPath $environmentFile -Force
    }
}
