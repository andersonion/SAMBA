function calculate_jacobian(in_warp,out_file,do_log_jacobian)
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
%%  Update 20 July 2016 (BJ Anderson)
%   It appears that (in the context of warps produced by antsRegistration),
%   that the voxel polarity should be negative by default: dx = -|dx|, dy =
%   -|dy|, dz = -|dz|.  If Direction Cosine Matrix (DCM) has any negatives
%   along the diagonal, that needs to be passed to this function and the
%   polarity of that dimension should be swapped.
%
%%  UPDATE 22 July 2016 (BJ Anderson)
%   This script previously calculated log-jacobian in LOG-10, NOT natural log!
% 
%   Pipeline code is updated as of 22 July 2016 to calculate LN instead (this
%   script).
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

out_nii = my_nii;


% Get absolute values of voxel_size...though for the origin business it may
% work our right getting the polarity as well.
abs_dx = voxel_size(1);
abs_dy = voxel_size(2);
abs_dz = voxel_size(3);

out_nii.hdr.dime.data_type = 16; % %this is necessary!  Don't trust the default of '32'!
out_nii.hdr.dime.dim(1)=3;
out_nii.hdr.dime.dim(6)=1;


% Hopefully this origin business is unnecessary and should be correctly
% handled by the CopyHeaderInformation function.
%origin = [round(my_nii.hdr.hist.qoffset_x/abs_dx),round(my_nii.hdr.hist.qoffset_y/abs_dy),round(my_nii.hdr.hist.qoffset_z/abs_dz)];
%origin = size(my_data(:,:,:,1,1))+origin-1;

%if rotate_around_z %% Original code for handling DCM = (-1,-1,1)
%     dz = -dz;
%end

dx = (-1)*my_nii.hdr.hist.srow_x(1); % The default for Nifti appears to be DCM=(-(dx)/abs(dx),-(dy)/abs(dy),(dz)/abs(dz));
dy = (-1)*my_nii.hdr.hist.srow_y(2); % See note directly above
dz = my_nii.hdr.hist.srow_z(3);

if ( (abs(dx/abs_dx) ~= 1) ||  (abs(dy/abs_dy) ~= 1) || (abs(dz/abs_dz) ~= 1) )
    msg = ['Unsupported Direction Cosine Matrix. Currently only diagonal DCMs are supported. dx = ' num2str(dx) ' dy = ' num2str(dy) ' dz = ' num2str(dz) '.'];
    error(msg) 

end

x_volume = squeeze(my_data(:,:,:,1,1));
y_volume = squeeze(my_data(:,:,:,1,2));
z_volume = squeeze(my_data(:,:,:,1,3));


jac = jacobian_2(x_volume,y_volume,z_volume,-dx,-dy,-dz);



if (~do_log_jacobian)
    jac_nii = out_nii;
    jac_nii.img = jac;
    %jac_nii = make_nii(jac,voxel_size,origin,data_type);
    save_untouch_nii(jac_nii,out_file);
else
    %log_jac = log10(jac);
    log_jac = log(jac); % Fixed as of 22 July 2016.
    log_jac_nii = out_nii;
    log_jac_nii.img = log_jac;
    %log_jac_nii = make_nii(log_jac,voxel_size,origin,data_type);
    save_untouch_nii(log_jac_nii,out_file);
end
cmd = [ap 'CopyImageHeaderInformation  ' in_warp ' ' out_file ' ' out_file ' 1 1 1'];
%system(cmd);  % As you can see, I guess I didn't actually call the CopyHeaderInformation command.  Will leave in here in case it is needed.
end