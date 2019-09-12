function niiout=img_transform_exe_V4(img,current_vorder,desired_vorder,varargin)
%% Modified 8 Feb 2016, BJ Anderson, CIVM
%  Added code to write corresponding affine transform matrix in ANTs format
%% Modified 22 March 2017, BJ Anderson, CIVM
%  Was originally creating affine matrix that transformed points, while the
%  ITK/ANTs paradigm is the same for affine, where the inverse needs to
%  be used. So it was updated to calculate the points transform, then
%  invert for "normal" use with images.
%% Modified 25 July 2017, BJ Anderson, CIVM
%  Making it more general to handle recentering issue.
%  Recentering in theory can be turned off now.
%  Code is handled differently if only recentering.
%  If no recentering and current_vorder and desired_vorder are the same,
%  then it just copies the file with the desired_vorder suffix.

%% 5 February 2019, BJ Anderson, CIVM
%  Attempting to add 

%% Variable Check

write_transform = 0;
recenter=1;

if length(varargin) > 0
    
    if ~isempty(varargin{1})
        temp_path = varargin{1};
        [path_specified, ~,~] = fileparts(temp_path);
        path_specified = [path_specified '/'];
    end
    
    if length(varargin) > 1
        if ~isempty(varargin{2})
            write_transform = varargin{2};
        end
    end
    
    if length(varargin) > 1
        if ~isempty(varargin{2})
            write_transform = varargin{2};
        end
    end
    
end


% image check
if ~exist(img,'file')
    error('Image cannot be found, please specify the full path as a string');
elseif ~strcmp(img(end-3:end),'.nii') && ~strcmp(img(end-6:end),'.nii.gz')
    error('Input image must be in NIfTI format')
end

%voxel order checks
if ~ischar(current_vorder)
    error('Current Voxel Order is not a string')
end
if length(current_vorder)~=3
    error('Current Voxel Order is not 3 characters long')
end
if  sum(isstrprop(current_vorder,'lower'))>0
    error('Current Voxel Order must be all upper case letters')
end
if strcmp(current_vorder(1),current_vorder(2)) || strcmp(current_vorder(1),current_vorder(3)) || strcmp(current_vorder(2),current_vorder(3))
    error('Current voxel order contains repeated elements! All three letters must be unique')
end
if isempty(strfind('RLAPSI',current_vorder(1))) || isempty(strfind('RLAPSI',current_vorder(2))) || isempty(strfind('RLAPSI',current_vorder(3)))
    error('Please use only R L A P S or I for current voxel order')
end


if  ~ischar(desired_vorder)
    error('Desired Voxel Order is not a string')
end
if  length(desired_vorder)~=3
    error('Desired Voxel Order is not 3 characters long')
end

if  sum(isstrprop(desired_vorder,'lower'))>0
    error('Desired Voxel Order must be all upper case letters')
end
if strcmp(desired_vorder(1),desired_vorder(2)) || strcmp(desired_vorder(1),desired_vorder(3)) || strcmp(desired_vorder(2),desired_vorder(3))
    error('Desired voxel order contains repeated elements! All three letters must be unique')
end
if isempty(strfind('RLAPSI',desired_vorder(1))) || isempty(strfind('RLAPSI',desired_vorder(2))) || isempty(strfind('RLAPSI',desired_vorder(3)))
    error('Please use only R L A P S or I for desired voxel order')
end

if strcmp(desired_vorder,current_vorder)
        if recenter
            if strcmp('.gz',);
            origin=round(size(new)./2);
            origin=origin(1:3);
        else
            origin=[]; % I hope this automatically handles the origin if not recentering...
        end
else
    
    %% Load and Analyze data
    nii=load_nii(img);
    %nii=load_untouch_nii(img);
    dims=size(nii.img);
    if length(dims)>5
        error('Image has > 5 dimensions')
    elseif length(dims)<3
        error('Image has < 3 dimensions')
    end
    new=nii.img;
    
    %% Voxel order preparation
    
    orig='RLAPSI';
    flip='LRPAIS';
    
    %% Affine transform matrix preparation
    x_row = [1 0 0];  % x and y are swapped in Matlab
    y_row = [0 1 0];  % x and y are swapped in Matlab
    z_row = [0 0 1];
    
    orig_current_vorder = current_vorder;
    %% check first dim
    xpos=strfind(desired_vorder,current_vorder(1));
    if isempty(xpos) %assume flip
        display('Flipping first dimension')
        new=flipdim(new,1);
        orig_ind=strfind(orig,current_vorder(1));
        current_vorder(1)=flip(orig_ind);
        %xpos=strfind(desired_vorder,current_vorder(1));  %I think this is incorrect and unused code (BJA); see Evan's quickfix.
        
        x_row=x_row*(-1);
    end
    
    %% check second dim
    ypos=strfind(desired_vorder,current_vorder(2));
    if isempty(ypos) %assume flip
        display('Flipping second dimension')
        new=flipdim(new,2);
        orig_ind=strfind(orig,current_vorder(2));
        current_vorder(2)=flip(orig_ind);
        %ypos=strfind(desired_vorder,current_vorder(2));  %I think this is incorrect and unused code (BJA); see Evan's quickfix.
        y_row=y_row*(-1);
    end
    
    %% check third dim
    zpos=strfind(desired_vorder,current_vorder(3));
    if isempty(zpos) %assume flip
        display('Flipping third dimension')
        new=flipdim(new,3);
        orig_ind=strfind(orig,current_vorder(3));
        current_vorder(3)=flip(orig_ind);
        %zpos=strfind(desired_vorder,current_vorder(3)); %I think this is incorrect and unused code (BJA); see Evan's quickfix.
        
        z_row=z_row*(-1);
    end
    %% quick fix for correct ordering
    xpos=strfind(current_vorder,desired_vorder(1));
    ypos=strfind(current_vorder,desired_vorder(2));
    zpos=strfind(current_vorder,desired_vorder(3));
    
    %% perform swaps
    display(['Dimension order is:' num2str(xpos) ' ' num2str(ypos) ' ' num2str(zpos)] )
    
    if length(dims)==5
        new=permute(new,[xpos ypos zpos 4 5]);
    elseif length(dims)==4
        new=permute(new,[xpos ypos zpos 4]);
    elseif length(dims)==3
        new=permute(new,[xpos ypos zpos]);
    end
    
    intermediate_affine_matrix = [x_row;y_row;z_row];
    iam = intermediate_affine_matrix;
    affine_matrix_for_points = [iam(xpos,:); iam(ypos,:); iam(zpos,:)]; % New code added to reflect that images are handled differently (i.e. inversely) than points
    %am4p = affine_matrix_for_points;  % New code, ibid
    affine_matrix_for_images = inv(affine_matrix_for_points); % New code, ibid
    am4i = affine_matrix_for_images; % New code, ibid
    affine_matrix_string = [am4i(1,:) am4i(2,:) am4i(3,:) 0 0 0];% New code, ibid
    %affine_matrix_string = [iam(xpos,:) iam(ypos,:) iam(zpos,:) 0 0 0];
    affine_fixed_string = [0 0 0];
    
    %% make and save outputs
    
    [path name ext]=fileparts(img);
    
    %affine_mat.AffineTransform_double_3_3=affine_matrix_string';
    %affine_mat.fixed_string=affine_fixed_string';
    affineout=[path '/' orig_current_vorder '_to_' desired_vorder '_affine.mat'];
    if (~exist(affineout,'file') && write_transform)
        write_affine_xform_for_ants(affineout,affine_matrix_string,affine_fixed_string);
        %save(affineout,'-struct','affine_mat');
    end
    
    num=0;
    if strcmp(ext,'.gz')
        ext='.nii.gz';
        num=4;
    end
    
    if recenter
        origin=round(size(new)./2);
        origin=origin(1:3);
    else
        origin=[]; % I hope this automatically handles the origin if not recentering...
    end
    newnii=make_nii(new,nii.hdr.dime.pixdim(2:4),origin,nii.hdr.dime.datatype);
    %newnii=make_nii(new,nii.hdr.dime.pixdim(2:4),[0 0 0],nii.hdr.dime.datatype);
end
if exist('path_specified','var')
    path = path_specified;
end

niiout=[path '/' name(1:end-num) '_' desired_vorder ext];

save_nii(newnii,niiout);
%newnii = nii;
%newnii.img = new;
%save_untouch_nii(newnii,niiout);
end
end