<#
.SYNOPSIS
    Preprocessing step: batch-converts raw Maestro2 .fda files to DICOM.

.DESCRIPTION
    Wraps Topcon's DicomOctExport.exe (installed with the DICOM OCT Export tool,
    see README) to convert every .fda file under $BaseRoot into a folder of
    standard DICOM files.

    Must be run on Windows (the exporter is a native .exe), via PowerShell:
        .\process-maestro2-fda.ps1

    REQUIRED: update the three variables below for your machine before running.
#>

$DICOM_OCT_EXPORT_EXE = "C:\path\to\DicomOctExport.exe"
$BaseRoot = "D:\path\to\raw\maestro2"
$GlobalOutputRoot = "D:\path\to\preprocessed\maestro2"

# Ensure global output root exists
if (-not (Test-Path $GlobalOutputRoot)) {
    New-Item -Path $GlobalOutputRoot -ItemType Directory | Out-Null
}

# Take a snapshot of all input folders at the start, excluding '_output'
$InputFolders = Get-ChildItem -Path $BaseRoot -Recurse -Directory | Where-Object {
    $_.FullName -notmatch '_output$'
}

foreach ($folder in $InputFolders) {
    $InputRoot = $folder.FullName

    # Mirror structure inside GlobalOutputRoot, e.g. $BaseRoot\siteA -> $GlobalOutputRoot\siteA_output
    $relativePath = $InputRoot.Substring($BaseRoot.Length).TrimStart('\')
    $OutputRoot = Join-Path $GlobalOutputRoot ($relativePath + "_output")

    if (-not (Test-Path $OutputRoot)) {
        New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
    }

    Get-ChildItem -Path $InputRoot -Filter *.fda -Recurse | ForEach-Object {
        $inputFile = $_.FullName

        if (Test-Path $inputFile -PathType Leaf) {
            $parentFolder = $_.Directory.Name
            $fileNameNoExt = $_.BaseName

            # UAB exports nest an extra folder level, so include the grandparent
            # to keep output folder names unique across sites.
            if ($_.Directory.FullName -match "UAB") {
                # include grandparent as well
                $grandParentFolder = Split-Path $_.Directory.FullName -Parent | Split-Path -Leaf
                $outputFolderName = "${grandParentFolder}_${parentFolder}_${fileNameNoExt}_fda"
            }
            else {
                $outputFolderName = "${parentFolder}_${fileNameNoExt}_fda"
            }

            # This is the "batch folder" that process_maestro2-dcm.py later reads,
            # one per source .fda file.
            $outputFolder = Join-Path $OutputRoot $outputFolderName

            if (-not (Test-Path $outputFolder)) {
                New-Item -Path $outputFolder -ItemType Directory | Out-Null
            }

            # Retry loop (max 3 times) - the exporter occasionally writes a
            # truncated set of files, so re-run until the expected count shows up.
            $maxRetries = 3
            $retryCount = 0
            $success = $false

            while (-not $success -and $retryCount -lt $maxRetries) {
                $retryCount++

                # Clean folder before retry
                Get-ChildItem -Path $outputFolder -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

                # Run the EXE. Flags:
                #   -octa        export OCTA flow volume
                #   -enfaceSlabs export en face slab renders
                #   -segDcm      export retinal layer segmentation as DICOM
                #   -dcm         export structural OCT/fundus DICOM
                & $DICOM_OCT_EXPORT_EXE $inputFile $outputFolder -octa -enfaceSlabs -segDcm -dcm

                # Wait a bit to ensure files are written
                Start-Sleep -Seconds 2

                # Count files created
                $fileCount = (Get-ChildItem -Path $outputFolder -File | Measure-Object).Count

                # 8 files = full OCTA scan (OCT + OCTA + enface + segmentation),
                # 3 files = structural-only scan (no OCTA data acquired for this eye).
                if ($fileCount -eq 8 -or $fileCount -eq 3) {
                    $success = $true
                    Write-Host "SUCCESS: $inputFile -> $fileCount files created."
                }
                else {
                    Write-Host "WARNING: $inputFile -> $fileCount files created (attempt $retryCount). Retrying..."
                }
            }

            if (-not $success) {
                Write-Host "FAILED: $inputFile -> Did not reach 8 or 3 files after $maxRetries attempts." -ForegroundColor Red
            }
        }
    }
}