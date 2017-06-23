# vba_pipeline
An HPC cluster-based pipeline for atlas creation, voxel- and label-based analysis (and more!)

The only guarantee that can be made for this code is that it will most assuredly NOT work outside of the Center for In Vivo Microscopy (CIVM) ecosystem.
Perhaps future versions will be supportive of external use.

Additional code is needed for the pipeline to even think about functioning.  This code can be found at:
https://github.com/jamesjcook/pipeline_utilities/blob/master/pipeline_utilities.pm

which in turn needs:
https://github.com/jamesjcook/pipeline_utilities/blob/master/civm_simple_util.pm

For the current version, the data is setup in:
study_variables.pm
Plenty of examples abound.

The pipeline is initiated by running:
vbm_pipeline_start.pl
An optional argument can be accepted, which is either:
the integer number of cluster nodes that the pipeline will try to saturate with work (default is 4).
or
a valid slurm reservation

For better idea of the order of processing within the pipeline, please see vbm_pipeline_workflow.pm.
