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

            $outputFolderName = "${parentFolder}_${fileNameNoExt}_fda"

            # This is the "batch folder" that process_maestro2-dcm.py later reads,
            # one per source .fda file.
            $outputFolder = Join-Path $OutputRoot $outputFolderName

            if (-not (Test-Path $outputFolder)) {
                New-Item -Path $outputFolder -ItemType Directory | Out-Null
            }

            # Run the EXE. Flags:
            #   -allDcm: export all as DICOM files.
            & $DICOM_OCT_EXPORT_EXE $inputFile $outputFolder -allDcm
        }
    }
}