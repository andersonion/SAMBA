# vba_pipeline
Welcome to SAMBA, the Small Animal Multivariate Brain Analysis pipeline suite!

SAMBA is an HPC cluster-based pipeline for atlas creation, voxel- and label-based analysis (and more!)

This code was designed and tested to function within the data ecosystem of the Center for In Vivo Microscopy (CIVM), and may need adaptation for local use.  Feel free to download and modify as needed to meet your needs (or even better, generalize and commit those modified parts and lower the bar of entry for other potential users).
Perhaps future versions will be supportive of external use.

There is some critical support code that is needed for the pipeline function.  This code can be found at:
https://github.com/jamesjcook/pipeline_utilities/blob/master/pipeline_utilities.pm

which in turn needs:

https://github.com/jamesjcook/pipeline_utilities/blob/master/civm_simple_util.pm

For the current version, a pipeline run is setup in:
study_variables.pm, where plenty of examples abound.

The pipeline is initiated by running:
vbm_pipeline_start.pl
An optional argument can be accepted, which is either:
the integer number of cluster nodes that the pipeline will try to saturate with work (default is 4).
or
a valid slurm reservation

For better idea of the order of processing within the pipeline, please see vbm_pipeline_workflow.pm.
