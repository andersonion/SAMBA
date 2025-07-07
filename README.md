# SAMBA
Welcome to SAMBA, the Small Animal Multivariate Brain Analysis pipeline suite!

SAMBA is an HPC cluster-based pipeline for atlas creation, voxel- and label-based analysis (and more!)

This code was designed and tested to function within the data ecosystem of Duke University's Center for In Vivo Microscopy (CIVM), and may need adaptation for local use.  Feel free to download and modify as needed to meet your needs (or even better, generalize and commit those modified parts and lower the bar of entry for other potential users).
It is hoped that future versions will be able to offer more support for external users.

A mouse atlas with 332 labels (L/R for 166 structures/regions) that was co-developed with SAMBA can be downloaded here:
https://zenodo.org/records/15178373

------
A note about lookup tables associated with atlases:
This should be a space-delimited text file, and must have the format where first column is ROI number and second is structure/name.  Any columns after this are ignored here.
The file name needs be "${atlas_name}_labels_lookup.txt"
BE SURE THAT THE LAST LINE IS TERMINTATED WITH SOME FORM OF NEW LINE--or else structure names will not be added to label statistic files.
This can be fixed in a bash terminal with this basic command:
'echo "" >> $lookup_file'.

Also, pretty please keep stupid special characters out of the structure names, ideally limited to underscores and dashes--NO SPACES, as this anything after the space will be lost to the infinite void.
------



The pipeline is initiated by running:
vbm_pipeline_start.pl

Two optional arguments can be accepted, the first is a headfile with the basic input parameters for the pipeline.  If the first option is not an existing file, it will default to starting up based on study_variables.pm (not recommended).  Please see input_parameters_template.headfile for a good starting point.

The second option (or first if no headfile is specified) is one of the following:
the integer number of cluster nodes that the pipeline will try to saturate with work (default is 4).
or
a valid slurm reservation

For better idea of the order of processing within the pipeline, please see vbm_pipeline_workflow.pm.

## Output Directory: `BIGGUS_DISKUS`

SAMBA writes its outputs to a shared working directory defined by the environment variable `BIGGUS_DISKUS`. Ideally, this location should be **persistent**, **writable**, and (optionally) **shared between users**. If you expect to be the only user needing to touch the output data, then the last requirement can be ignored, and using a user-specific folder should be acceptable.

### How `BIGGUS_DISKUS` is Determined

When the container starts, `BIGGUS_DISKUS` is set using the following logic:

1. If the `BIGGUS_DISKUS` environment variable is defined, that value is used.
2. Otherwise, SAMBA tries common cluster workspace variables:
   - `$SCRATCH` (e.g., `/scratch/users/username`)
   - `$WORK` (e.g., `/work/projects/projectname`)
3. If none of those are set, SAMBA falls back to:

   ```
   $HOME/samba_scratch
   ```

### How to Override It

To manually set the output directory:

```
export BIGGUS_DISKUS=/path/to/shared/output
singularity exec samba.sif samba-pipe headfile.hf
```

This directory **must exist and be writable** by the user running the container.

---

## Supporting Multi-User Workflows

If multiple users need access to the same SAMBA outputs:

- The parent directory of `BIGGUS_DISKUS` should reside on a **shared filesystem** (e.g., NFS, Lustre, GPFS).
- It should be **group-owned** by a shared UNIX group:

  ```
  chgrp -R yourgroup /shared/path
  chmod -R g+rw /shared/path
  ```

- Set the `setgid` bit on directories to preserve group ownership:

  ```
  find /shared/path -type d -exec chmod g+s {} \;
  ```

This ensures that all users in the same group can access and write to SAMBA output files.

---

## Permissions and Binding Caveats

- If `BIGGUS_DISKUS` defaults to `$HOME`, outputs may be private to the current user unless permissions are manually updated.
- Running SAMBA in a container does **not** automatically grant write access to host directories unless explicitly mounted. You may need to use the `--bind` flag:

  ```
  singularity exec --bind /shared/path samba.sif samba-pipe headfile.hf
  ```
