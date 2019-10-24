function output_path=img_transform_exec(img,current_vorder,desired_vorder,varargin)
% function niiout=img_transform_exec(img,current_vorder,desired_vorder,output_path,write_transform,recenter)

% img='/civmnas4/rja20/SingleSegmentation_16gaj38_chass_symmetric3_RAS_N56456-inputs/N56456_color_nqa.nii.gz';
%img='/civmnas4/rja20/img_transform_testing/S64570_m000_DTI_tensor.nii';
%img='/cm/shared/CIVMdata/atlas/C57/transforms_chass_symmetric3/chass_symmetric3_to_C57/chass_symmetric3_to_MDT_warp.nii.gz';
%current_vorder='ARI';
%desired_vorder='RAS';
%varargin={};
%path_specified='/civmnas4/rja20/SingleSegmentation_16gaj38_chass_symmetric3_RAS_N56456-work/preprocess/';
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
%  Attempting to add vector and color support, maybe add tensor support at another
%  time? Hope to add code that spits out a fully usable affine.mat that
%  includes proper translation.

%% Variable Check

write_transform = 0;
recenter=1;
is_RGB=0;
is_vector=0;
is_tensor=0;
% todo: improve option handling
% using hilarious kludge to take letters (1/0) or numbers (1/0) for bools.
if length(varargin) > 0
    if ~isempty(varargin{1})
        output_path=varargin{1};
    end
    if length(varargin) > 1
        if ~isempty(varargin{2})
            try
                write_transform = str2num(varargin{2});
            catch
                write_transform = varargin{2};
            end
        end
    end
    if length(varargin) > 2
        if ~isempty(varargin{3})
            try
                recenter=str2num(varargin{3});
            catch
                recenter = varargin{3};
            end
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

%% nii +gz name swappityroo and now output names too
% feels like there is a better way to deal ith the nii or nii+gz conundrum.
suff='';
use_exact_output=0;
% Start with the input name
[out_dir, img_name, ext]=fileparts(img);
if ~exist('output_path','var')
    suff=['_' desired_vorder];
else
    % output_path was set, is it a directory or a filename.
    % we figure this out based on extension presence.
    if ~isempty(regexpi(output_path,'.nii(.gz)?'))
        % specified as a nifti file with optional gz ext.
        [out_dir, img_name, ext]=fileparts(output_path);
        use_exact_output=1;
    else 
        out_dir=output_path;
        if ~exist(output_path,'dir')
            warning('Missing dir output_path, but we''ll make it');
            mkdir(output_path);
        end
    end
end

affine_out=fullfile(out_dir,[current_vorder '_to_' desired_vorder '_affine.mat']);
if strcmp(ext,'.gz')
    nii_ext_len=4;
    img_name=img_name(1:end-nii_ext_len);
end
ext='.nii.gz';
if ~use_exact_output
    output_path=fullfile(out_dir,[img_name suff ext]);
end

%% early exit if done.
if exist(output_path,'file') ...
        && ( ~write_transform ...
        || ( write_transform && exist(affine_out,'file') )  )
    warning('Existing output:%s, not regenerating',output_path);
    return;
end

if ~recenter
    warning('This code is defficient, it will ruin your center.');
    pause(3);
end

%affine_mat.AffineTransform_double_3_3=affine_matrix_string';
%affine_mat.fixed_string=affine_fixed_string';

orig='RLAPSI';
flip_string='LRPAIS';

% not sure why current_vorder gets over written in function, but it does,
% and we wanna be sure we know what it was.
% just incase we do some sloppy code later :D
orig_current_vorder = current_vorder;
%% Load and Analyze data
try
    n1t=tic;
    if ~exist(output_path,'file')
        nii=load_niigz(img);
    else
        nii.hdr=load_niigz_hdr(img);
    end
catch
    time_1=toc(n1t);
    n2t=tic;
    if ~exist(output_path,'file')
        nii=load_nii(img);
    else
        nii.hdr=load_nii_hdr(img);
    end
    time_2=toc(n2t);
    warning(['Function load_niigz (runtime: ' num2str(time_1) ') failed with datatype: ' num2str(nii.hdr.dime.datatype) ' (perhaps because it currently doesn''t support RGB?). Used load_nii instead (runtime: ' num2str(time_2) ').']);
end
% dims=size(nii.img);
dims=nii.hdr.dime.dim(2: nii.hdr.dime.dim(1)+1);
if length(dims)>6
    error('Image has > 5 dimensions')
elseif length(dims)<3
    error('Image has < 3 dimensions')
end
if ~exist(output_path,'file')
    new=nii.img;
else 
    new = zeros(dims);
end

%{
    warning('Untested no-op code');
    if recenter
        %if strcmp('.gz',);
        origin=round(size(new)./2);
        origin=origin(1:3);
    else
        origin=[]; % I hope this automatically handles the origin if not recentering...
    end
else
%}
if ~strcmp(desired_vorder,current_vorder)
    %% Feb 2019 -- Figure out if we have RGB/vector/tensor here.
    data_string = nifti1('data_type',nii.hdr.dime.datatype);
    if strcmp(data_string(1:3),'rgb')
        is_RGB=1;
        is_vector=1;
        %todo: either here or in nifti1, pull out the intent_code that
        %matches to data_string and explicitly set in:
        % nii.hdr.dime.intent_code=verified_intent_code;
        %if length(data_string)==3;
        %     nii.hdr.dime.intent_code=2003;
        %else
        %    nii.hdr.dime.intent_code=2004;
        %    end
        
    elseif ((length(dims) > 4) && (dims(5)==3));
        is_vector=1;
    elseif ((length(dims) > 5) && (dims(5)==6)); 
        % This a GUESS at how to tell if we have tensor...which seems to be pretty reliable.
        % Using intent code would be better!
        is_tensor=1;
    end
    %% Affine transform matrix preparation
    x_row = [1 0 0];
    y_row = [0 1 0];
    z_row = [0 0 1];
    %% check first dim
    xpos=strfind(desired_vorder,current_vorder(1));
    if isempty(xpos) %assume flip
        display('Flipping first dimension')
        new=flip(new,1);
        orig_ind=strfind(orig,current_vorder(1));
        current_vorder(1)=flip_string(orig_ind);
        %xpos=strfind(desired_vorder,current_vorder(1));  %I think this is incorrect and unused code (BJA); see Evan's quickfix.
        if (is_vector) && (is_RGB ==0)
            new(:,:,:,1,1)=-1*new(:,:,:,1,1);
        end
        x_row=x_row*(-1);
    end
    %% check second dim
    ypos=strfind(desired_vorder,current_vorder(2));
    if isempty(ypos) %assume flip
        display('Flipping second dimension')
        new=flip(new,2);
        orig_ind=strfind(orig,current_vorder(2));
        current_vorder(2)=flip_string(orig_ind);
        %ypos=strfind(desired_vorder,current_vorder(2));  %I think this is incorrect and unused code (BJA); see Evan's quickfix.
        if (is_vector) && (is_RGB ==0)
            new(:,:,:,1,2)=-1*new(:,:,:,1,2);
        end
        y_row=y_row*(-1);
    end
    %% check third dim
    zpos=strfind(desired_vorder,current_vorder(3));
    if isempty(zpos) %assume flip
        display('Flipping third dimension')
        new=flip(new,3);
        orig_ind=strfind(orig,current_vorder(3));
        current_vorder(3)=flip_string(orig_ind);
        %zpos=strfind(desired_vorder,current_vorder(3)); %I think this is incorrect and unused code (BJA); see Evan's quickfix.
        if (is_vector) && (is_RGB ==0)
            new(:,:,:,1,3)=-1*new(:,:,:,1,3);
        end
        z_row=z_row*(-1);
    end
    %% Voxel order preparation
    %% quick fix for correct ordering
    % sets x,y,z pos to current, above they were in the desired
    xpos=strfind(current_vorder,desired_vorder(1));
    ypos=strfind(current_vorder,desired_vorder(2));
    zpos=strfind(current_vorder,desired_vorder(3));
    %% perform swaps
    display(['Dimension order is:' num2str(xpos) ' ' num2str(ypos) ' ' num2str(zpos)] )
    if ~exist(output_path,'file')
    if length(dims)==5
        if is_tensor
            % I think more sophisticated handling is required in for tensors! I think tensors are dim==5
            new=permute(new,[xpos ypos zpos 4 5]);
        else
            if is_vector
                new=new(:,:,:,1,[xpos, ypos, zpos]);
            end
            new=permute(new,[xpos ypos zpos 4 5]);
        end
    elseif length(dims)==4
        if is_RGB
            new=new(:,:,:,[xpos, ypos, zpos]);
        end
        new=permute(new,[xpos ypos zpos 4]);
    elseif length(dims)==3
        new=permute(new,[xpos ypos zpos]);
    end
    end
    %% save affine transform
    if (~exist(affine_out,'file') && write_transform)
        intermediate_affine_matrix = [x_row;y_row;z_row];
        iam = intermediate_affine_matrix;
        affine_matrix_for_points = [iam(xpos,:); iam(ypos,:); iam(zpos,:)]; % New code added to reflect that images are handled differently (i.e. inversely) than points
        %am4p = affine_matrix_for_points;  % New code, ibid
        affine_matrix_for_images = inv(affine_matrix_for_points); % New code, ibid
        am4i = affine_matrix_for_images; % New code, ibid
        affine_matrix_string = [am4i(1,:) am4i(2,:) am4i(3,:) 0 0 0];% New code, ibid
        %affine_matrix_string = [iam(xpos,:) iam(ypos,:) iam(zpos,:) 0 0 0];
        affine_fixed_string = [0 0 0];
        try
            % sometims missing, dont care to track it down today.
            write_affine_xform_for_ants(affine_out,affine_matrix_string,affine_fixed_string);
        catch merr
            disp(merr);
        end
        %save(affineout,'-struct','affine_mat');
    end
end
%% early exit if done.
if exist(output_path,'file')
    return;
end
%% recenter ... if you're in to that junk
if recenter
    origin=round(size(new)./2);
    origin=origin(1:3);
else
    % this ruins the origin if not recentering...
    % which is kinda silly all around :P
    origin=[];
end
%% make_nii/save_nii
newnii=make_nii(new,nii.hdr.dime.pixdim(2:4),origin,nii.hdr.dime.datatype);
%newnii=make_nii(new,nii.hdr.dime.pixdim(2:4),[0 0 0],nii.hdr.dime.datatype);
newnii.hdr.dime.intent_code=nii.hdr.dime.intent_code;
save_nii(newnii,output_path);
%newnii = nii;
%newnii.img = new;
%save_untouch_nii(newnii,niiout);
%end