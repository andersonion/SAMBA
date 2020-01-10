#!/bin/bash
#SBATCH 
#SBATCH --reservation=
#SBATCH  --mem=8000 
#SBATCH  -v
#SBATCH  -s 
#SBATCH  --output=${HOME}/SAMBA_sbatch/slurm-%j.out 
#$ -l h_vmem=8000M,vf=8000M

