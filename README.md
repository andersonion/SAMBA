# SAMBA
Welcome to SAMBA, the Small Animal Multivariate Brain Analysis pipeline suite!

SAMBA is an HPC cluster-based pipeline for atlas creation, voxel- and label-based analysis (and more!)

This code was designed and tested to function within the data ecosystem of Duke University's Center for In Vivo Microscopy (CIVM), and may need adaptation for local use.  Feel free to download and modify as needed to meet your needs (or even better, generalize and commit those modified parts and lower the bar of entry for other potential users).
It is hoped that future versions will be able to offer more support for external users.

There is some critical support code that is needed for the pipeline function.  This code can be found at:
https://github.com/jamesjcook/pipeline_utilities/blob/master/pipeline_utilities.pm

which in turn needs:

https://github.com/jamesjcook/pipeline_utilities/blob/master/civm_simple_util.pm

The pipeline is initiated by running:
vbm_pipeline_start.pl

Two optional arguments can be accepted, the first is a headfile with the basic input parameters for the pipeline.  If the first option is not an existing file, it will default to starting up based on study_variables.pm (not recommended).  Please see input_parameters_template.headfile for a good starting point.

The second option (or first if no headfile is specified) is one of the following:
the integer number of cluster nodes that the pipeline will try to saturate with work (default is 4).
or
a valid slurm reservation

For better idea of the order of processing within the pipeline, please see vbm_pipeline_workflow.pm.
