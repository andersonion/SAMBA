function calculate_jacobian(in_warp,out_file,do_log_jacobian,rotate_around_z)
%% A crude but effective (i.e. non-opaque) calculation of the Jacobian determinant of a warp field.
%  Required file: jacobian_2.m.
%
%  Written by BJ Anderson, CIVM, January 2016
%
%  This does not smartly handle the various rotation information that
%  resides in the nifti header. I have imperically found that for our
%  typical CIVM header with the (-1 -1 1) rotation matrix (and
%  corresponding signage in the s_row field), and centered about the
%  origin, we should "rotate_around_z". In turn, what I have found to
%  produce righteous results is changing dz to -dz.  I do not understand
%  the situation well enough to be able to handle other cases with a degree
%  of confidence.
%
%  I have modified the jacobian_2 script to account for non-unitary step
%  sizes in the matrix.
%
%  We implement ANTs copy header information to ensure consistency between
%  the out_file and the in_warp.
%
%  This version has been tested and produces pretty good results (within
%  the limits of the mean-differences/gradient method).
%

%%
%addpath('/home/rja20/cluster_code/workstation_code/shared/mathworks/NIfTI_20140122/')
addpath('/cm/shared/workstation_code/shared/mathworks/NIFTI_20140122/') % Will call general code instead of my copy
ap = '/cm/shared/apps/ANTS/';

my_file = in_warp;

my_nii=load_untouch_nii(my_file);
my_data = my_nii.img;

voxel_size = my_nii.hdr.dime.pixdim(2:4);
%origin = [my_nii.hdr.hist.qoffset_x,my_nii.hdr.hist.qoffset_y,my_nii.hdr.hist.qoffset_z]

dx = voxel_size(1);
dy = voxel_size(2);
dz = voxel_size(3);

data_type = 16; % %This is necessary!  Don't trust the default of '32'!

% Hopefully this origin business is unnecessary and should be correctly
% handled by the CopyHeaderInformation function.
origin = [round(my_nii.hdr.hist.qoffset_x/dx),round(my_nii.hdr.hist.qoffset_y/dy),round(my_nii.hdr.hist.qoffset_z/dz)];
origin = size(my_data(:,:,:,1,1))+origin-1;

if rotate_around_z
    dz = -dz;
end

x_volume = squeeze(my_data(:,:,:,1,1));
y_volume = squeeze(my_data(:,:,:,1,2));
z_volume = squeeze(my_data(:,:,:,1,3));


jac = jacobian_2(x_volume,y_volume,z_volume,dx,dy,dz);



if (~do_log_jacobian)
    jac_nii = make_nii(jac,voxel_size,origin,data_type);
    save_nii(jac_nii,out_file);
else
    log_jac = log10(jac);
    log_jac_nii = make_nii(log_jac,voxel_size,origin,data_type);
    save_nii(log_jac_nii,out_file);
end
cmd = [ap 'CopyImageHeaderInformation  ' in_warp ' ' out_file ' ' out_file ' 1 1 1'];
%system(cmd);  % As you can see, I guess I didn't actually call the CopyHeaderInformation command.  Will leave in here in case it is needed.
end