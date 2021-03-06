#!/bin/bash
#
#SBATCH --job-name=aln
#SBATCH --output=//fast/groups/ag_sanders/work/projects/benedict/logs/2022
#
#SBATCH --cpus-per-task=64
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --time=2-00:00
#SBATCH --mem-per-cpu=4G
#SBATCH --exclusive
#SBATCH --partition=highmem
#SBATCH --mail-type=ALL
#SBATCH --mail-user=benedict.monteiro@mdc-berlin.de

# BIH cluster Paired end sequencing data alignment script June 2022
# This script takes .fastq format files, performs QC on them, before aligning to reference genome and outputting alignment QC metrics
echo 'Running alignment script' ; date

##################################################################################################
# 1. Set global options
##################################################################################################
printf '\n ### 1. Setting global options ####\n'

# Needs changing these for each new project:
project_name=FOO # the name of the folder in //fast/groups/ag_sanders/work/data containig the reads (which should contain a dir named fastq/)
memperthread=4G # memory assigned per thread in slurm job
mate1_suffix=_1_sequence.txt.gz # suffix of read pair mate 1 fastq file (e.g. _R1.fastq.gz)
run_qc=TRUE # whether the alignment QC script should be run automatically [TRUE/FALSE]

# Probably don't need changing at the start of a new project:
mate2_suffix=$(echo $mate1_suffix | sed 's/1/2/') # suffix of mate 2 fastq file
ref_genome=//fast/groups/ag_sanders/work/data/reference/genomes/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz # path to reference genome
fastq_dir=//fast/groups/ag_sanders/work/data/${project_name}/fastq # dir containing fastq format files
n_threads=$(nproc) # number of threads given to slurm job, for highest efficiency use a multiple of 4 (e.g. 32, 64, etc.)
n_threads_divided=$(expr $n_threads / 4)

##################################################################################################
# 2. Activate conda environment
##################################################################################################
printf '\n ### 2. Activating conda environment ####\n'

# dependencies: r samtools picard bwa fastqc multiqc bedtools
# the conda env can be installed with: conda env create -f //fast/groups/ag_sanders/work/tools/conda_envs/alignmentenv_20220505.yml

# test if conda env is present
condaenvexists=$(conda env list | grep 'alignmentenv' | awk '{print $1}')
[ -z ${condaenvexists} ] && { echo "ERROR: alignmentenv conda env not found in conda env list" ; exit ; } || echo ''
[ ${condaenvexists} = "alignmentenv" ] && echo "alignmentenv conda env found in conda env list" || { echo "ERROR: alignmentenv conda env not found in conda env list" ; exit ; }

conda init bash
source ~/.bashrc
conda activate alignmentenv

##################################################################################################
# 3. Initiation
##################################################################################################
printf '\n ### 3. Initiating script #####\n'

# test if sequencing project directory exists
if [[ ! -d /fast/groups/ag_sanders/work/data/${project_name} ]]
then
	echo "ERROR: this dir does not exist: /fast/groups/ag_sanders/work/data/${project_name}"
	echo "please set project_name in global options to a real directory!"
	exit
fi

# create directories
tmp_dir=//fast/groups/ag_sanders/scratch/${project_name} ; mkdir -m 775 $tmp_dir
bam_dir=//fast/groups/ag_sanders/work/data/${project_name}/bam; mkdir -m 775 $bam_dir
qc_dir=//fast/groups/ag_sanders/work/data/${project_name}/qc ; mkdir -m 775 $qc_dir
statsdir=${qc_dir}/alignment_stats ; mkdir -m 775 $statsdir

echo "Temporary/intermediate files will be written to ${tmp_dir}"
echo "Final .bam files will be written to ${bam_dir}"

# confirm that there are .fastq files in the fastq_dir
[ ! $(ls ${fastq_dir}/*${mate1_suffix} | wc -l) -ge 1 ] && { echo "ERROR: no files were found with the suffix ${mate1_suffix} in ${fastq_dir}" ; exit ; }
testfile=$(ls $fastq_dir | head -n1)
if [ ! $(zcat ${fastq_dir}/${testfile} | cut -c 1) = '@' ]
then
	echo "Error: No fastq files were found in ${fastq_dir}/, exiting script"
	exit
fi

# test if $run_qc is set correctly
if [ $run_qc = 'TRUE' ]
then
	echo "QC script will be run following alignment completion"
elif [ $run_qc = 'FALSE' ]
then
	echo "QC script will *NOT* be run following alignment completion"
else
	echo "ERROR: run_qc in Global Options must = TRUE or FALSE (currently it is neither!)"
	exit
fi

##################################################################################################
# 4. Run FastQC quality assessment on raw sequencing data
##################################################################################################
printf '\n ### 4. Run QC on sequencing reads #####\n'

fastqc_dir=${qc_dir}/fastqc ; mkdir -m 775 $fastqc_dir
multiqc_dir=${qc_dir}/multiqc ; mkdir -m 775 $multiqc_dir

# run FastQC to generate quality metrics on
fastqc -q -t $n_threads -o ${fastqc_dir} ${fastq_dir}/*

# run multiqc
multiqc -o $multiqc_dir $fastqc_dir

##################################################################################################
# 5. Alignment
##################################################################################################
printf '\n ### 5. Running alignment #####\n'

# make unique list of library names by removing suffixes
fastq_files=$(ls $fastq_dir)
libraries=$(echo $fastq_files | sed -e "s/${mate1_suffix}//g;s/${mate2_suffix}//g" | \
        tr ' ' '\n' | sort -u | tr '\n' ' ' | less)

samdir=${tmp_dir}/sam ; mkdir -m 775 $samdir

# perform alignment all libraries
for library in $libraries
do
	(
	echo "performing alignment on ${library}"
        input1=${fastq_dir}/${library}${mate1_suffix}
        input2=${fastq_dir}/${library}${mate2_suffix}

        ID=$(zcat $input1 | head -n1 |  cut -f 1-3 -d ":" | cut -f 1 -d '.' | sed 's/@//')

        bwa mem -t 4 -v 1 -R $(echo "@RG\tID:${library}\tSM:${project_name}") \
        	$ref_genome $input1 $input2 > ${samdir}/${library}.sam
	) &
        if [[ $(jobs -r -p | wc -l) -ge $n_threads_divided ]]; # allows n_threads / 4 number of iterations to be executed in parallel
        then
                wait -n # if there are n_threads_divided iterations running wait here for space to start next job
        fi
done
wait # wait for all jobs in the above loop to be done

##################################################################################################
# 6. Process BAM files
##################################################################################################
printf '\n ### 6. Processing BAM files #####\n'

# make dir on scratch drive for intermediate bam files
bam_tmpdir=${tmp_dir}/bam_tmpdir ; mkdir -m 775 $bam_tmpdir
mdup_metrics_dir=${statsdir}/mdup_metrics ; mkdir -m 775 $mdup_metrics_dir

# convert, process, filter SAM files
for library in $libraries
do
        (
	echo "processing ${library}.sam"
        # convert SAM to BAM
        samtools view -@ 4 -h -b ${samdir}/${library}.sam > ${bam_tmpdir}/${library}.bam # convert SAM to BAM

        # sort BAM file
        samtools sort -@ 4 -m $memperthread ${bam_tmpdir}/${library}.bam > ${bam_tmpdir}/${library}.sort.bam
        samtools index -@ 4 ${bam_tmpdir}/${library}.sort.bam # generate index

        # Mark duplicated reads in BAM file
        picard MarkDuplicates -I ${bam_tmpdir}/${library}.sort.bam \
                -O ${bam_tmpdir}/${library}.sort.mdup.bam \
                -M ${mdup_metrics_dir}/${library}_mdup_metrics.txt
        samtools index -@ 4 ${bam_tmpdir}/${library}.sort.mdup.bam # generate index

	# copy sorted marked duplicates BAM files and their indexes to work drive
	cp ${bam_tmpdir}/${library}.sort.mdup.bam* $bam_dir
	) &
        if [[ $(jobs -r -p | wc -l) -ge $n_threads_divided ]]; # allows n_threads / 4 number of iterations to be executed in parallel
        then
                wait -n # if there are n_threads_divided iterations running wait here for space to start next job
        fi
done
wait # wait for all jobs in the above loop to be done

# change permissions of output folders so all group members can read/write
chmod -R 774 $bam_dir
chmod -R 774 $qc_dir

echo "Finished alignment script on ${project_name}!" ; date

if [ $run_qc = 'TRUE' ]
then
	echo "launching QC script //fast/groups/ag_sanders/work/projects/benedict/master_scripts/alignment/exec/alignment_qc_exec.sh"
	bash //fast/groups/ag_sanders/work/projects/benedict/master_scripts/alignment/exec/alignment_qc_exec.sh \
		$project_name
fi
