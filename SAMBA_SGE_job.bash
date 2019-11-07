#!/bin/bash
#SBATCH 
#SBATCH --reservation=
#SBATCH  --mem=8000 
#SBATCH  -v
#SBATCH  -s 
#SBATCH  --output=${HOME}/SAMBA_sbatch/slurm-%j.out 
#$ -l h_vmem=8000M,vf=8000M
#$ -M ${USER}@duke.edu 
#$ -m ea 
#$ -o ${HOME}/SAMBA_sbatch/slurm-$TASK_ID.out 
#$ -e ${HOME}/SAMBA_sbatch/slurm-$TASK_ID.out
