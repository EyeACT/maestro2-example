# maestro2-example

Sample pipeline for converting raw Topcon Maestro2 OCT/OCT-A exports (`.fda` files) into a
standardized DICOM folder structure, following the layout used by the AI-READI Topcon
imaging pipeline.

The pipeline has two steps:

1. **Preprocessing** ([process-maestro2-fda.ps1](process-maestro2-fda.ps1)) - runs on Windows
   and converts raw `.fda` files into standard DICOM files using Topcon's DICOM OCT Export
   tool.
2. **Processing** ([process_maestro2-dcm.py](process_maestro2-dcm.py)) - reads the DICOM files
   produced in step 1 and organizes them into a final
   `<modality>/<submodality>/topcon_maestro2/<patient_id>/` structure, plus `manifest.tsv`
   files describing each scan.

[print_dicom_tags.py](print_dicom_tags.py) is an optional utility for dumping every tag in a
single DICOM file, useful for debugging at any point in the pipeline.

## Prerequisites

- A Windows machine with PowerShell, to run the preprocessing step (Topcon's exporter is a
  native `.exe`).
- Topcon's **DICOM OCT Export** tool, installed at the **research license level**. The
  standard license only exports structural OCT/fundus DICOM - the research level is required
  to also export OCTA flow volumes, en face renders, and segmentation data, which this
  pipeline expects. Request access from
  [Topcon Healthcare](https://topconhealthcare.com/article/topcon-healthcare-expands-access-to-standardized-dicom-oct-imaging-data/).
- Python 3.12 and [mise](https://mise.jdx.dev/getting-started.html) + `uv`, for the processing
  step (mise installs `uv` automatically, see `mise.toml`).

## Install dependencies

```bash
# Install Python 3.12 and uv (as specified in mise.toml)
mise install

# Activate the virtual environment
uv venv

# Install project dependencies
uv pip install -r requirements.txt
```

## Step 1: Preprocess raw .fda files into DICOM

`process-maestro2-fda.ps1` wraps Topcon's `DicomOctExport.exe` (installed as part of the
research-level tool above) and batch-converts every `.fda` file it finds.

1. **Required:** open the script and replace the placeholder paths at the top with real ones
   for your machine - it will not run correctly until you do:
   - `$DICOM_OCT_EXPORT_EXE` - path to `DicomOctExport.exe` from the installed Topcon tool.
   - `$BaseRoot` - folder containing your raw Maestro2 `.fda` files (searched recursively).
   - `$GlobalOutputRoot` - where the exported DICOM files should be written.
2. Run it in PowerShell:

   ```powershell
   .\process-maestro2-fda.ps1
   ```

The script mirrors `$BaseRoot`'s folder structure under `$GlobalOutputRoot`, appending
`_output` to each folder name. For every `.fda` file it finds, it creates one "batch folder"
inside the matching `_output` folder and runs the exporter with
`-octa -enfaceSlabs -segDcm -dcm`, so each batch folder ends up containing:

- the structural OCT volume and fundus photo (always)
- the OCTA flow volume, its en face renders, and the retinal layer segmentation (when the
  scan includes OCTA data - this requires the research license)

It retries up to 3 times per file if the expected file count (8 for a full OCTA scan, 3 for a
structural-only scan) isn't produced.

## Step 2: Organize DICOM files into the final structure

`process_maestro2-dcm.py` reads the batch folders from one `_output` directory produced in
step 1 and organizes their files into the final per-patient/per-modality layout.

1. **Required:** open the script and replace the placeholder paths near the top with real
   ones for your machine - it will not run correctly until you do:
   - `INPUT_FOLDER` - one of the `_output` folders from step 1 (its immediate subfolders must
     be the individual batch folders). If `$BaseRoot` had multiple site subfolders, run this
     script once per corresponding `_output` folder.
   - `OUTPUT_FOLDER` - where the organized, final structure should be written.
2. Run it:

   ```bash
   python process_maestro2-dcm.py
   ```

This produces, under `OUTPUT_FOLDER`:

- `<modality>/<submodality>/topcon_maestro2/<patient_id>/` folders containing the renamed
  DICOM files (modality/submodality is derived from each file's DICOM `Modality` and
  `SeriesDescription` tags - see `PROTOCOL_MAP` in the script)
- one `manifest.tsv` per modality folder, listing every scan (patient ID, laterality,
  anatomic region, imaging type, image dimensions, and file path) - this is where the OCTA
  scans exported via the research-level license show up alongside the structural OCT data
- `logs/organize_log.csv` and `logs/organize_manifest.csv` recording anything that failed to
  process and every file that was copied

## Inspecting DICOM tags

Use `print_dicom_tags.py` at any point to dump every tag in a single DICOM file - handy for
verifying the `Modality`/`SeriesDescription` combination of a scan that step 2 classified as
`unknown_protocol`, or for confirming OCTA metrics/tags are present after preprocessing:

```bash
python print_dicom_tags.py path/to/file.dcm
```

## Using this with Triton data

Topcon's Triton is the same underlying platform/exporter family as the Maestro2, so this
pipeline can process Triton `.fda` exports with the same two steps. The only change needed is
in `process_maestro2-dcm.py`'s `PROTOCOL_MAP` and `MANIFEST_META` dictionaries: update the
`Modality`/`SeriesDescription` keys to match the tags Triton writes (use
`print_dicom_tags.py` on a sample file to check them), and update `DEVICE_FOLDER` and the
protocol names accordingly. `process-maestro2-fda.ps1` and its `DicomOctExport.exe` call
require no changes.
