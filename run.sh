#!/bin/bash
#SBATCH --job-name=nanom6a_pipeline
#SBATCH --time=16:00:00
#SBATCH --nodes=1 --ntasks-per-node=1
#SBATCH --account=pas1405
#SBATCH --mail-type=ALL

module load nextflow

export NXF_EXECUTOR="slurm"
nextflow run nanom6a.nf -profile slurm -resume
