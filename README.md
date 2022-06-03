# bih-alignment

shell scripts (written as slurm jobs) for performing alignment of NGS reads to a reference genome on the BIH HPC cluster. 

The main scripts are found in `/scripts`:

* `alignment_script.sh` is the complete pipeline and is therefore the recommended script to use.

* `alignment_qc_script.sh` can be run if you only wish to run quality control on data that is already aligned.

The scripts in `/exec` are called by the other scripts and should not be executed in isolation.  

You can download these scripts like so:

```
git clone https://github.com/benedict909/bih-alignment
```
