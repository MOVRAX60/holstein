# Windows Air-Gap Asset Downloader for K3s and Rancher
# Downloads all assets to projectroot/airgap/ structure

param(
    [string]$K3sVersion = "v1.33.4+k3s1",
    [string]$RancherVersion = "v2.8.0",
    [string]$CertManagerVersion = "v1.13.2",
    [string]$HelmVersion = "v3.13.3"
)

# Set up directory structure in project root
$ProjectRoot = Get-Location
$AirgapDir = Join-Path $ProjectRoot "airgap"
$BinariesDir = Join-Path $AirgapDir "binaries"
$ImagesDir = Join-Path $AirgapDir "images"
$ChartsDir = Join-Path $AirgapDir "charts"
$ManifestsDir = Join-Path $AirgapDir "manifests"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    Clear-Host
    Write-ColorOutput "=================================================" "Blue"
    Write-ColorOutput "    Windows Air-Gap Asset Downloader" "Blue"
    Write-ColorOutput "=================================================" "Blue"
    Write-ColorOutput "K3s Version: $K3sVersion" "Cyan"
    Write-ColorOutput "Rancher Version: $RancherVersion" "Cyan"
    Write-ColorOutput "Cert-Manager Version: $CertManagerVersion" "Cyan"
    Write-ColorOutput "Helm Version: $HelmVersion" "Cyan"
    Write-ColorOutput "Project Root: $ProjectRoot" "Cyan"
    Write-ColorOutput "Airgap Directory: $AirgapDir" "Cyan"
    Write-Host ""
}

function New-DirectoryIfNotExists {
    param([string]$Path)
    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-ColorOutput "Created directory: $Path" "Green"
    }
}

function Download-FileWithProgress {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Description
    )

    if (Test-Path $OutputPath) {
        Write-ColorOutput "Already exists: $Description" "Yellow"
        return
    }

    Write-ColorOutput "Downloading: $Description" "Cyan"
    Write-ColorOutput "URL: $Url" "Gray"

    try {
        $webClient = New-Object System.Net.WebClient

        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action {
            $percent = $Event.SourceEventArgs.ProgressPercentage
            Write-Progress -Activity "Downloading $Description" -Status "$percent% Complete" -PercentComplete $percent
        } | Out-Null

        $webClient.DownloadFile($Url, $OutputPath)
        Write-Progress -Activity "Downloading $Description" -Completed

        $fileSize = (Get-Item $OutputPath).Length / 1MB
        Write-ColorOutput "✓ Downloaded: $Description ($([math]::Round($fileSize, 2)) MB)" "Green"

        $webClient.Dispose()
        Get-EventSubscriber | Unregister-Event
    }
    catch {
        Write-ColorOutput "✗ Failed to download $Description`: $($_.Exception.Message)" "Red"
        throw
    }
}

function Initialize-DirectoryStructure {
    Write-ColorOutput "=== Creating Directory Structure ===" "Blue"

    New-DirectoryIfNotExists $AirgapDir
    New-DirectoryIfNotExists $BinariesDir
    New-DirectoryIfNotExists $ImagesDir
    New-DirectoryIfNotExists $ChartsDir
    New-DirectoryIfNotExists $ManifestsDir

    Write-ColorOutput "✓ Directory structure created" "Green"
}

function Download-K3sAssets {
    Write-ColorOutput "=== Downloading K3s Assets ===" "Blue"

    # K3s binary
    $k3sBinaryUrl = "https://github.com/k3s-io/k3s/releases/download/$K3sVersion/k3s"
    $k3sBinaryPath = Join-Path $BinariesDir "k3s"
    Download-FileWithProgress $k3sBinaryUrl $k3sBinaryPath "K3s Binary"

    # K3s air-gap images
    $k3sImagesUrl = "https://github.com/k3s-io/k3s/releases/download/$K3sVersion/k3s-airgap-images-amd64.tar"
    $k3sImagesPath = Join-Path $ImagesDir "k3s-airgap-images-amd64.tar"
    Download-FileWithProgress $k3sImagesUrl $k3sImagesPath "K3s Air-gap Images"

    # K3s install script
    $k3sInstallUrl = "https://get.k3s.io"
    $k3sInstallPath = Join-Path $BinariesDir "k3s-install.sh"
    Download-FileWithProgress $k3sInstallUrl $k3sInstallPath "K3s Install Script"
}

function Download-HelmAssets {
    Write-ColorOutput "=== Downloading Helm Assets ===" "Blue"

    $helmUrl = "https://get.helm.sh/helm-$HelmVersion-linux-amd64.tar.gz"
    $helmPath = Join-Path $BinariesDir "helm-$HelmVersion-linux-amd64.tar.gz"
    Download-FileWithProgress $helmUrl $helmPath "Helm Binary Archive"
}

function Download-CertManagerAssets {
    Write-ColorOutput "=== Downloading cert-manager Assets ===" "Blue"

    # cert-manager CRDs
    $certManagerCrdsUrl = "https://github.com/cert-manager/cert-manager/releases/download/$CertManagerVersion/cert-manager.crds.yaml"
    $certManagerCrdsPath = Join-Path $ManifestsDir "cert-manager.crds.yaml"
    Download-FileWithProgress $certManagerCrdsUrl $certManagerCrdsPath "cert-manager CRDs"

    # cert-manager manifests
    $certManagerUrl = "https://github.com/cert-manager/cert-manager/releases/download/$CertManagerVersion/cert-manager.yaml"
    $certManagerPath = Join-Path $ManifestsDir "cert-manager.yaml"
    Download-FileWithProgress $certManagerUrl $certManagerPath "cert-manager Manifests"
}

function Download-RancherCharts {
    Write-ColorOutput "=== Downloading Rancher Charts ===" "Blue"

    # Extract Helm first if needed
    $helmBinary = Join-Path $BinariesDir "helm"
    $helmArchive = Join-Path $BinariesDir "helm-$HelmVersion-linux-amd64.tar.gz"

    if (!(Test-Path $helmBinary) -and (Test-Path $helmArchive)) {
        Write-ColorOutput "Extracting Helm for chart download..." "Cyan"
        Expand-Archive -Path $helmArchive -DestinationPath $BinariesDir -Force
        $extractedHelm = Join-Path $BinariesDir "linux-amd64\helm"
        if (Test-Path $extractedHelm) {
            Copy-Item $extractedHelm $helmBinary
            Remove-Item (Join-Path $BinariesDir "linux-amd64") -Recurse -Force
        }
    }

    if (Test-Path $helmBinary) {
        # Use extracted Helm to download charts
        $env:PATH = "$BinariesDir;$env:PATH"

        # Download Rancher chart
        $rancherChartPath = Join-Path $ChartsDir "rancher-$RancherVersion.tgz"
        if (!(Test-Path $rancherChartPath)) {
            Write-ColorOutput "Downloading Rancher chart..." "Cyan"
            & $helmBinary repo add rancher-stable https://releases.rancher.com/server-charts/stable --force-update
            & $helmBinary repo update
            & $helmBinary pull rancher-stable/rancher --version $RancherVersion --destination $ChartsDir
            Write-ColorOutput "✓ Downloaded Rancher chart" "Green"
        }

        # Download cert-manager chart
        $certManagerChartPath = Join-Path $ChartsDir "cert-manager-$CertManagerVersion.tgz"
        if (!(Test-Path $certManagerChartPath)) {
            Write-ColorOutput "Downloading cert-manager chart..." "Cyan"
            & $helmBinary repo add jetstack https://charts.jetstack.io --force-update
            & $helmBinary repo update
            & $helmBinary pull jetstack/cert-manager --version $CertManagerVersion --destination $ChartsDir
            Write-ColorOutput "✓ Downloaded cert-manager chart" "Green"
        }
    } else {
        Write-ColorOutput "Helm binary not available for chart download" "Yellow"
    }
}

function Create-ImageLists {
    Write-ColorOutput "=== Creating Container Image Lists ===" "Blue"

    # Rancher image list
    $rancherImages = @(
        "rancher/rancher:$RancherVersion",
        "rancher/rancher-webhook:v0.3.8",
        "rancher/fleet:v0.8.1",
        "rancher/fleet-agent:v0.8.1",
        "rancher/gitjob:v0.1.38",
        "rancher/shell:v0.1.20",
        "rancher/kubectl:v1.28.4"
    )

    # cert-manager images
    $certManagerImages = @(
        "quay.io/jetstack/cert-manager-controller:$CertManagerVersion",
        "quay.io/jetstack/cert-manager-webhook:$CertManagerVersion",
        "quay.io/jetstack/cert-manager-cainjector:$CertManagerVersion",
        "quay.io/jetstack/cert-manager-ctl:$CertManagerVersion"
    )

    $allImages = $rancherImages + $certManagerImages

    # Save image list
    $imageListPath = Join-Path $ImagesDir "container-images.txt"
    $allImages | Out-File -FilePath $imageListPath -Encoding UTF8
    Write-ColorOutput "✓ Created image list: $imageListPath" "Green"

    # Create Docker pull script
    $dockerScriptPath = Join-Path $ImagesDir "pull-and-save-images.sh"
    $dockerScript = @(
        "#!/bin/bash",
        "# Docker script to pull and save container images",
        "# Run this on a machine with Docker and internet access",
        "",
        "set -e",
        "echo 'Pulling and saving container images...'",
        ""
    )

    foreach ($image in $allImages) {
        $safeName = $image -replace "[/:]", "_"
        $dockerScript += "echo 'Processing: $image'"
        $dockerScript += "docker pull $image"
        $dockerScript += "docker save $image -o $safeName.tar"
        $dockerScript += ""
    }

    $dockerScript += "echo 'All images saved successfully!'"
    $dockerScript += "echo 'Transfer all .tar files to your air-gapped system'"

    $dockerScript | Out-File -FilePath $dockerScriptPath -Encoding UTF8
    Write-ColorOutput "✓ Created Docker script: $dockerScriptPath" "Green"
}

function Create-VersionInfo {
    Write-ColorOutput "=== Creating Version Info ===" "Blue"

    $versionInfo = @{
        "k3s_version" = $K3sVersion
        "rancher_version" = $RancherVersion
        "cert_manager_version" = $CertManagerVersion
        "helm_version" = $HelmVersion
        "download_date" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        "downloaded_by" = $env:USERNAME
    }

    $versionPath = Join-Path $AirgapDir "versions.json"
    $versionInfo | ConvertTo-Json -Depth 3 | Out-File -FilePath $versionPath -Encoding UTF8
    Write-ColorOutput "✓ Created version info: $versionPath" "Green"
}

function Show-DownloadSummary {
    Write-ColorOutput "" "White"
    Write-ColorOutput "=== Download Complete ===" "Blue"

    if (Test-Path $AirgapDir) {
        $totalSize = (Get-ChildItem $AirgapDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB
        Write-ColorOutput "✓ All assets downloaded to: $AirgapDir" "Green"
        Write-ColorOutput "Total size: $([math]::Round($totalSize, 2)) MB" "Cyan"

        Write-ColorOutput "" "White"
        Write-ColorOutput "Downloaded Components:" "Cyan"
        Write-ColorOutput "  • K3s $K3sVersion binary and images" "White"
        Write-ColorOutput "  • Helm $HelmVersion binary" "White"
        Write-ColorOutput "  • cert-manager $CertManagerVersion manifests and charts" "White"
        Write-ColorOutput "  • Rancher $RancherVersion charts" "White"
        Write-ColorOutput "  • Container image lists and Docker scripts" "White"

        Write-ColorOutput "" "White"
        Write-ColorOutput "Directory Structure:" "Yellow"
        Write-ColorOutput "  $AirgapDir/" "Cyan"
        Write-ColorOutput "  ├── binaries/     (K3s, Helm binaries)" "White"
        Write-ColorOutput "  ├── images/       (Container images and lists)" "White"
        Write-ColorOutput "  ├── charts/       (Helm charts)" "White"
        Write-ColorOutput "  ├── manifests/    (Kubernetes manifests)" "White"
        Write-ColorOutput "  └── versions.json (Version information)" "White"

        Write-ColorOutput "" "White"
        Write-ColorOutput "Next Steps:" "Yellow"
        Write-ColorOutput "1. If you have Docker, run: ./airgap/images/pull-and-save-images.sh" "Cyan"
        Write-ColorOutput "2. Transfer entire project directory to Linux system" "Cyan"
        Write-ColorOutput "3. Run the Linux installation script" "Cyan"
    }
}

# Main execution
function Start-Download {
    Write-Header

    try {
        # Test internet connection
        Write-ColorOutput "Testing internet connection..." "Yellow"
        $response = Invoke-WebRequest -Uri "https://github.com" -Method Head -TimeoutSec 10
        Write-ColorOutput "✓ Internet connection OK" "Green"

        # Download all assets
        Initialize-DirectoryStructure
        Download-K3sAssets
        Download-HelmAssets
        Download-CertManagerAssets
        Download-RancherCharts
        Create-ImageLists
        Create-VersionInfo
        Show-DownloadSummary

    }
    catch {
        Write-ColorOutput "Error: $($_.Exception.Message)" "Red"
        exit 1
    }
}

# Run the download
Start-Download