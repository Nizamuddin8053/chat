[CmdletBinding()]
param(
    [ValidateSet("deploy", "destroy")]
    [string]$Action = "deploy",
    [string]$AwsRegion = "ap-south-1",
    [string]$KeyName = "chat-app-deploy",
    [string]$SshPrivateKey = "$HOME\.ssh\chat-app-deploy",
    [string]$AdminCidr,
    [string]$MongoDbUri = $env:CHAT_MONGODB_URI,
    [string]$JwtSecret = $env:CHAT_JWT_SECRET,
    [string]$RepositoryUrl = "https://github.com/Nizamuddin8053/chat.git"
)

$ErrorActionPreference = "Stop"
$infraDir = Join-Path $PSScriptRoot "infra"
$playbook = Join-Path $PSScriptRoot "ansible\site.yml"
$inventory = $null
$varsFile = $null

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required and must be available on PATH."
    }
}

Require-Command "terraform"

if (-not $AdminCidr) {
    $AdminCidr = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com").Trim() + "/32"
}
if (-not (Test-Path "$SshPrivateKey.pub")) {
    throw "Public key not found at $SshPrivateKey.pub."
}

$env:TF_VAR_aws_region = $AwsRegion
$env:TF_VAR_key_name = $KeyName
$env:TF_VAR_admin_cidr = $AdminCidr
$env:TF_VAR_ssh_public_key = (Get-Content "$SshPrivateKey.pub" -Raw).Trim()

try {
    if ($Action -eq "destroy") {
        Push-Location $infraDir
        try {
            terraform destroy -auto-approve
        } finally {
            Pop-Location
        }
        exit 0
    }

    Require-Command "ansible-playbook"
    if (-not $MongoDbUri) {
        throw "Set -MongoDbUri or CHAT_MONGODB_URI before deploying."
    }
    if (-not $JwtSecret) {
        throw "Set -JwtSecret or CHAT_JWT_SECRET before deploying."
    }

    Push-Location $infraDir
    terraform init -input=false
    terraform apply -auto-approve -input=false
    $publicIp = (terraform output -raw public_ip).Trim()
    Pop-Location

    $inventory = Join-Path $env:TEMP "chat-app-inventory-$PID.ini"
    $varsFile = Join-Path $env:TEMP "chat-app-vars-$PID.json"
    "[chat]`n$publicIp ansible_user=ubuntu" | Set-Content $inventory
    @{
        required_frontend_origin = "http://$publicIp"
        required_mongodb_uri = $MongoDbUri
        required_jwt_secret = $JwtSecret
        repository_url = $RepositoryUrl
    } | ConvertTo-Json | Set-Content $varsFile

    ansible-playbook $playbook -i $inventory --private-key $SshPrivateKey `
        --extra-vars "@$varsFile" --ssh-extra-args "-o StrictHostKeyChecking=no"

    Write-Host "Application deployed at http://$publicIp"
    Write-Host "Run .\deploy.ps1 -Action destroy when you are finished to delete the AWS resources."
} finally {
    if ($inventory -and (Test-Path $inventory)) { Remove-Item $inventory -Force }
    if ($varsFile -and (Test-Path $varsFile)) { Remove-Item $varsFile -Force }
    Remove-Item Env:TF_VAR_ssh_public_key -ErrorAction SilentlyContinue
}
