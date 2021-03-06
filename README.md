# bih-alignment

Scripts for performing alignment of NGS reads to a reference genome on the BIH HPC cluster. 
The pipeline takes the input fastq files in the following location on the BIH cluster: `//fast/groups/ag_sanders/work/data/${project_name}/fastq`, where `${project_name}` is the name of the sequencing run *and* directory.

The alignment pipeline scripts found in `/scripts` are shell scripts written as slurm jobs:

* `alignment_script.sh` is the complete pipeline and is therefore the recommended script to use.

* `alignment_qc_script.sh` can be run if you only wish to run quality control on data that is already aligned.

The files in `/exec` are called by the main scripts and should not be executed in isolation.  

## Installation

You can download this repository like so:

```
git clone https://github.com/benedict909/bih-alignment
```

And install the required conda environment into your BIH cluster conda workspace like so:

```
conda env create -f //fast/groups/ag_sanders/work/tools/conda_envs/alignmentenv_20220505.yml
```
Or by downloading the same .yml from this repo.

## Configuration

The following parameters need setting in the global options section in `scripts/alignment_scripts.sh` at the start of each new project:

* `project_name`: the name of the folder in `//fast/groups/ag_sanders/work/data` containing the reads (which should contain a dir named fastq/)

* `memperthread` the memory assigned per thread in slurm job (recommended 2-4G)

* `mate1_suffix`: the suffix of read pair mate 1 fastq file (e.g. `_1_sequence.txt.gz`)

* `run_qc`: whether the alignment QC script should be run automatically after alignment is complete [TRUE/FALSE] (default = TRUE)

With these 4 parameters set you should be able to run the pipeline. Further information on each step of the pipeline can be found in the comments of each script.
