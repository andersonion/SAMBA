function [ new_vectors ] = transform_bvecs(varargin)
%TRANSFORM_BVECS For input bvec(s), rotate according to the reverse order
% of the stack, maintaining consistency to how the transforms would be used
% in the context of warp and transforming an image in ANTs/ITK framework.
%
% This is programmed with the expectation that the various input arguments
% will be fed via a linux-type command line, meaning strings are split by
% spaces.  Because of this, inputs associated with a dash option are
% treated as separate strings, i.e. '-o /glusterspace/test.txt' is actually
% parsed as '-o' followed by '/glusterspace/test.txt'.
%
% PLEASE NO EXTRA SPACES WITHIN EACH TRANSFORM STRING!
%
% options:
% -h Print help?  Need to add this!
% -b {constant bvalue}, for all non-zero bvecs
% -o {output file name} (extension will be ignored)
% -e Exact file name will be used for output, '_bvals' will be placed
%    before last file extension. Must be used with -o.
% -f {format option} Format of output file
% -p {prefix string} Prefix for any subvolumes, i.e. 'm' for 'm00','m01'...
% -u Force all vectors to upper hemisphere (all positive z components)
% -x (as part of transform chain) Rotate around x ("flip" x)
% -y (as part of transform chain) Rotate around y ("flip" y)
% -z (as part of transform chain) Rotate around z ("flip" z)
% -t {transform/transform stack} (optional)
% Transform chain options:
% -x/-y/-z Rotate around axis (or more specifically, negates along that axis).
% ants_affine.mat/[ants_affine.mat,{inverse? 0/1}]
% {ALS}_to_{RAS} Any valid A/P S/I L/R triplet to another
% "DSI b-table check"-style, i.e. '012fy'--only to be used for b-table checking! (i.e., don't use this as an ALS_to_RAS transform, etc.) 
% Please see 'help' below for important information about
% using NiFTis, and about gradient configuration.
new_vectors=[];
if length(varargin) > 0
    bvector_array=varargin{1};
else
     % Print help
    display_help();
    if isdeployed
        exit;
    else
        return;
    end
end
if (~exist('bvector_array','var') || strcmp(bvector_array,'-h') ||  strcmp(bvector_array,'')|| ~exist(bvector_array,'file'))
    % Print help
    display_help();
    if isdeployed
        exit;
    else
        return;
    end
end


%% Parse inputs


number_of_extra_inputs = length(varargin); % This is a historical misnomer; it's actually the MATLAB index of the last input.

% Defaults
format = 2; % DSI studio format is the default
subindex_prefix = 'm';
upper_hemisphere = 1;
exact_naming = 0;
ecc_suffix='';
ecc_flag=0;
upper_hemisphere_suffix='';
uh_dim=3;
uh_dim_string='z';

used_args=[];
xform_args=[];
for ii = 2:number_of_extra_inputs
    if ~ismember(ii,used_args)
        current_input = varargin{ii};
        if strcmp(current_input(1),'-')
            switch current_input(2)
                case 'h' % Print help
                    display_help();
                    if isdeployed
                        exit;
                    end
                case 'b' % constant b-value
                    used_args = [used_args ii];
                    v1 = (varargin{ii+1});
                    if(~isempty(v1))
                        b_value = str2num(v1);
                        used_args = [used_args (ii+1)];
                    end
                    
                case 'f' % FORMAT
                    used_args = [used_args ii];
                    v2 = (varargin{ii+1});
                    if(~isempty(v2))
                        format = str2num(v2);
                        used_args = [used_args (ii+1)];
                    end
                case 'o'
                    used_args = [used_args ii];
                    v2 = (varargin{ii+1});
                    if(~isempty(v2))
                        output_file_without_extension = v2;
                        used_args = [used_args (ii+1)];
                    end
                case 'e'
                    used_args = [used_args (ii+1)];
                    exact_naming =1;
                case 't' % Transform  -- generally redundant, just need to remove
                    used_args = [used_args ii];
                case 'p'
                    used_args = [used_args ii];
                    v3 = (varargin{ii+1});
                    if(~isempty(v3))
                        subindex_prefix =v3(2:end);
                        used_args = [used_args (ii+1)];
                    end
                case 'u'
                    used_args = [used_args ii];
                    v1 = (varargin{ii+1});
                    if(~isempty(v1) && ~strcmp(v1(1),'-'))
                        if strcmp(v1,'0')
                            upper_hemisphere = 0;
                        else
                            upper_hemisphere =1;
                            switch v1 
                            case 'x'
                                uh_dim=1;
                                uh_dim_string='x';
                            case 'y'
                                uh_dim=2;
                                uh_dim_string='y';
                            otherwise % Same as default values
                                uh_dim=3;
                                uh_dim_string='z';
                            end
                        end
                        used_args = [used_args (ii+1)];
                    else
                        upper_hemisphere = 1;
                    end

                case 'x'
                    xform_args = [xform_args ii];
                case 'y'
                    xform_args = [xform_args ii];
                case 'z'
                    xform_args = [xform_args ii];
                otherwise
                    disp(['Invalid option "' current_input '"  will be ignored.']);
                    v4 = (varargin{ii+1});
                    if(~isempty(v4)) && ~(strcmp(v4(1),'-'))
                        disp(['"' v4 '" will be treated as part of the transform chain.']);
                    end
            end
        else  % Assume all unaccounted vargargins are transforms
            % check for warp and ignore (nii/nii.gz)
            
            warp_test = strsplit(current_input,'.');
            if ~(strcmp(warp_test{end},'nii') || (strcmp(warp_test{end},'gz') && strcmp(warp_test{end-1},'nii')))
                xform_args = [xform_args ii];
            end
        end
    end
end

number_of_xforms = length(xform_args);

if number_of_xforms == 0
    xform_args={'identity'};
end
%vectors=csvread(bvector_array);
vectors=dlmread(bvector_array);

if ((size(vectors,1) == 3) || (size(vectors,1) == 4))
    vectors = vectors';
end

if (size(vectors,2) == 4)
    
    % Split off bvals if present
    bval_ind = find(max(vectors) > 1);
    
    if ~exist('b_value','var')
        bvals = vectors(:,bval_ind);
    end
    vectors(:,bval_ind)=[];
    
elseif (size(vectors,2) ~= 3)
    bad_dims=size(vectors);
    error('Non-vector input table detected.  The size of one dimension needs to be 3 or 4.\nAn array size of %i by %i was found in:\n\t%s.',bad_dims(1),bad_dims(2),bvector_array);
    %error_msg=sprintf('Non-vector input table detected.  The size of one dimension needs to be 3 or 4.\n...an array size of %i by %i was found in %s.',bad_dims(1),bad_dims(2),bvector_array);
    %error(error_msg);
end

num_vectors = length(vectors);

new_vectors = zeros(size(vectors));
if exist('b_value','var')
    bvals = zeros([1 num_vectors]); % invert?
end


for vv = 1:num_vectors
    temp_bvec = vectors(vv,:)';
    if ~(sum(temp_bvec) == 0)
        if exist('b_value','var')
            bvals(vv)=b_value;
        end
        
        for xx = number_of_xforms:-1:1
            %for xx = 1:number_of_xforms
            use_inverse = 0;
            current_input = varargin{xform_args(xx)};
            
            % Strip off "[" and "]" if present
            current_input = strsplit(current_input,'[');
            current_input = strjoin(current_input,'');
            current_input = strsplit(current_input,']');
            current_input = strjoin(current_input,'');
            
            input_parts = strsplit(current_input,',');
            current_transform = input_parts{1};
            if length(input_parts) > 1
                use_inverse = str2num(input_parts{end});
            end
            
            apply_xform = 1;
            % Check for subvolume specific transform
            sep_string = ['_' subindex_prefix 'X'];
            subvolume_test = strsplit(current_transform,sep_string);
            clear MM;
            if length(subvolume_test) > 1
                prefix = [ subvolume_test{1} '_' subindex_prefix];
                zero_width = 1;
                stop_it = 0;
                skip_it = 0;
                X_test = subvolume_test{2};
                for yy = 1:4
                    if ~stop_it
                        if strcmp(X_test(yy),'X')
                            zero_width = zero_width + 1;
                        else
                            stop_it=1;
                            skip_it = yy;
                        end
                    end
                end
                suffix = X_test(skip_it:end);
                MM = sprintf(['' '%0' num2str(zero_width) '.' num2str(zero_width) 's'] ,num2str(vv-1));
                current_transform = [prefix MM suffix] ;
                
                if ~exist(current_transform,'file')
                    msg = ['File not found: ' current_transform '. No eddy current correction applied to volume ' subindex_prefix MM '. *May be ok if this the first volume (0).'];
                    disp(msg);
                else
                    ecc_flag=1;
                end
            end
            
            
            if apply_xform

                if strcmp(current_transform,'identity')
                    rotation=[1 0 0; 0 1 0; 0 0 1];
                else
                    rotation=read_ants_rotation_for_bvecs(current_transform,use_inverse);
                end
                temp_bvec = rotation*temp_bvec;
            end
        end
        
            
        if (upper_hemisphere && (temp_bvec(uh_dim) < 0))
            temp_bvec = -1*temp_bvec;
        end
        
        % 30 October 2018 (Tues) Normalize:
        
        norm=(sum(temp_bvec.*temp_bvec))^(-0.5);
        temp_bvec=norm*temp_bvec;
        
        
        new_vectors(vv,:) = temp_bvec';
    end
end

bvals = bvals';

if ecc_flag
   ecc_suffix = '_ecc'; 
end

if upper_hemisphere
    upper_hemisphere_suffix=['_uh' uh_dim_string];
end
                    

% -o output file name

if ~exist('output_file_without_extension','var')
    if strcmp(bvector_array((end-2):end),'.gz')
        bvector_array((end-2):end)=[];
    end
    [out_dir,filename_prefix,ext]=fileparts(bvector_array);
    if ~isempty(out_dir)
        out_dir = [out_dir '/'];
    end
    if isempty(filename_prefix)
        filename_prefix=[upper_hemisphere_suffix ecc_suffix];
    else
        filename_prefix =[filename_prefix upper_hemisphere_suffix ecc_suffix];
    end
    
    if strcmp(filename_prefix(1),'_')
        filename_prefix(1)=[];
    end
    
    
    output_file_without_extension = [out_dir filename_prefix];
    
else
    if exact_naming
        [out_dir,filename_prefix,ext]=fileparts(output_file_without_extension);
        if ~isempty(out_dir)
            out_dir = [out_dir '/'];
        end
        exact_bvecs_name = [out_dir filename_prefix ext];
        exact_bvals_name = [out_dir filename_prefix '_bvals' ext];
    else
        if ~(exist(output_file_without_extension,'dir') == 7)
            [out_dir,filename_prefix,ext]=fileparts(output_file_without_extension);
            if ~isempty(out_dir)
                out_dir = [out_dir '/'];
            end
            if (isempty(filename_prefix) && ~upper_hemisphere_suffix && ~ecc_suffix)
                filename_prefix='';
            else
                filename_prefix =[filename_prefix upper_hemisphere_suffix ecc_suffix '_'];
            end
            output_file_without_extension = [out_dir filename_prefix];
        end
    end
end


% -f FORMAT

% 1: FSL(Bedpost/Probtrackx)
% Each b-vector -> column, bx/by/bz -> row
% Space delimited, no suffix, by is flipped!

% 2: DSI Studio
% Each b-vector -> row, bx/by/bz -> column
% Space delimited, .txt suffix

% 3: Diffusion Toolkit/Trackvis
% Each b-vector -> row, bx/by/bz -> column
% Comma delimited, .txt suffix

% 4: Camino
% CURRENTLY UNSUPPORTED
% (until I get the chance to check on the format)

% 5: MRtrix
% CURRENTLY UNSUPPORTED
% (but I suspect that a final '-z' is needed to account for the software ignoring the [-1 -1 1] Direction Cosine Matrix)

ext='';
switch format
    case 1
        ext='';
    case 2
        ext='.txt';
    case 3
        ext='.txt';
        %case 4
        %
    otherwise
        
end


if ~exist('exact_bvecs_name','var')
    exact_bvecs_name = [output_file_without_extension  'bvecs' ext];
end
if (exist('bvals','var') && ~exist('exact_bvals_name','var'))
    exact_bvals_name = [output_file_without_extension  'bvals' ext];
end

switch format
    case 1
        new_vectors(2,:)=new_vectors(2,:);
        disp(['Writing bvecs file: ' exact_bvecs_name '...'])
        dlmwrite(exact_bvecs_name,new_vectors','delimiter',' ','precision',12)
        if exist('bvals','var')
            disp(['Writing bvals file: ' exact_bvals_name '...'])
            dlmwrite(exact_bvals_name,bvals,'delimiter',' ','precision',4)
        end
    case 2
        dlmwrite(exact_bvecs_name,new_vectors,'delimiter',' ','precision',12)
        disp(['Writing bvecs file: ' exact_bvecs_name '...'])
        if exist('bvals','var')
            disp(['Writing bvals file: ' exact_bvals_name '...'])
            dlmwrite(exact_bvals_name,bvals','delimiter',' ','precision',4)
        end
        
    case 3
        dlmwrite(exact_bvecs_name,new_vectors,'delimiter',',','precision',12)
        disp(['Writing bvecs file: ' exact_bvecs_name '...'])
        if exist('bvals','var')
            disp(['Writing bvals file: ' exact_bvals_name '...'])
            dlmwrite(exact_bvals_name,bvals','delimiter',',','precision',4)
        end
        %case 4
        %
    otherwise
        
end


%% Prep work


%
end

function display_help()

help_text = ['TRANSFORM_BVECS'...
    ' For input bvec(s), rotate according to the reverse order'...
    ' of the stack, maintaining consistency to how the transforms would be used'...
    ' in the context of warp and transforming an image in ANTs/ITK framework.'...
    ''...
    ' This is programmed with the expectation that the various input arguments'...
    ' will be fed via a linux-type command line, meaning strings are split by'...
    ' spaces.  Because of this, inputs associated with a dash option are'...
    ' treated as separate strings, i.e. ''-o /glusterspace/test.txt'' is actually'...
    ' parsed as ''-o'' followed by ''/glusterspace/test.txt''.'...
    ''...
    ' PLEASE NO EXTRA SPACES WITHIN EACH TRANSFORM STRING!'...
    ''...
    ' options:'...
    ' -h Print help?  Need to add this!'...
    ' -b {constant bvalue}, for all non-zero bvecs'...
    ' -o {output file name} (extension will be ignored)'...
    ' -e Exact file name will be used for output, ''_bvals'' will be placed'...
    '    before last file extension. Must be used with -o.'...
    ' -f {format option} Format of output file'...
    ' -p {prefix string} Prefix for any subvolumes, i.e. ''m'' for ''m00'',''m01''...'...
    ' -u Force all vectors to upper hemisphere (all positive z components)'...
    ' -x (as part of transform chain) Rotate around x'...
    ' -y (as part of transform chain) Rotate around y'...
    ' -z (as part of transform chain) Rotate around z'...
    ' -t {transform/transform stack} (optional)'...
    ' Transform chain options:'...
    ' -x/-y/-z Rotate around axis'...
    ' ants_affine.mat/[ants_affine.mat,{inverse? 0/1}]'...
    ' {ALS}_to_{RAS} Any valid A/P S/I L/R triplet to another'...
    ' PLEASE NOTE: If at any time the images are converted to NiFTi (*.nii or *.nii.gz),'...
    ' the default is to have an implicit [-1 -1 1] along the diagonal of the Direction Cosine Matrix'...
    ' (though it MIGHT be [1 1 1] if converting from Dicom);'...
    ' the [-1 -1 1] needs to be account for be inserting "-z" OR "-x -y" at the'...
    ' appropriate point in the transform chain.'...
    ' ALSO NOTE: There is also a possible change in coordinates due to the particular'...
    ' gradient orientation used to acquire the data.  In the CIVM lab (up until October 2018,'...
    ' at least), both 7T and 9T data MOST LIKELY (but not always) would need a polarity'...
    ' along x.  If this is the case, then first transform that should be applied,'...
    ' i.e. the last transform specified, should be "-x".'];
    
    disp(help_text)
    end

