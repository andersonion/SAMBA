function rotation=read_ants_rotation_for_bvecs(input,use_inverse)
%% Originally was read_ants_rotation.m, acquired from Evan Calabrese
%  Interestingly, when used to rotate bvecs, it seems that it would produce
%  the right answer in the case of truly rigid rotations. If the transform
%  has full affine freedom, then it can produces errors of up to half a
%  degree in our tests.
%
%  The bug was that the incoming vector from the ants transform was being
%  reshaped as :
%  a d g
%  b e h
%  c f i
%
%  instead of the presumed "general" ANTs convention:
%  a b c
%  d e f
%  g h i
%
%  So the proper thing to do is transpose the reshaped rotation matrix.
%  However, the nuance is that for ANTs, one needs to use the INVERSE
%  transform when dealing with points (as opposed to images). This is the
%  same source of the infamous Jacobian Headaches of 2015/2016
%
%  The transposed matrix needs to be inverted before extracting the
%  rotation component.  This order of operation appears to matter, in that
%  extracting the rotation component before inverting can produce bvec
%  errors up to 0.15 degrees, as per our testing.
%
%  This bug had a sister error in my (BJA's) version of img_transform.m, in
%  which I would write the transform that would be appropriate for
%  transforming points, when I'm claiming to be producing a transform that
%  can be applied to the images.  This has been rectified as well.  The
%  point is that the two errors essentially cancelled each other out,
%  making detection of these slight errors very difficult.


%argument check
if exist(input,'file')
    [path name ext]=fileparts(input);
    if ~strcmp(ext,'.mat')
        error('Please specify an ANTS *.mat affine as input');
    end

    my_file = open(input);%load(input);
    
    % Begin code update, 7 June 2017, BJA: attempt to make robust; hope to
    % read in any transform type that is 9 or more elements long, and
    % reshape the first 9 into a 3x3 (valid) affine matrix
    affines= who('-file',input,'*Transform*');
    input_vector = eval(sprintf('my_file.%s(1:9)',affines{1}));
    rotation=reshape(input_vector,3,3); 
    % End code update.
    
    % get 3x3 matrix and extract rotation only
    %if exist('my_file.AffineTransform_double_3_3','var')
    %rotation=reshape(my_file.AffineTransform_double_3_3(1:9),3,3); % Previous 'stable' code
    %else
    %    rotation=reshape(my_file.CompositeTransform_double_3_3(1:9),3,3);
    %    rotation=reshape(my_file.MatrixOffsetTransformBase_double_3_3(1:9),3,3);
    %end

    rotation = rotation'; % Now it is in proper ANTs format.
else
   switch input
       case '-x'
           rotation = [-1 0 0; 0 1 0; 0 0 1];
       case '-y'
           rotation = [1 0 0; 0 -1 0; 0 0 1];
       case '-z'
           rotation = [1 0 0; 0 1 0; 0 0 -1];
       otherwise %let's hope this is an ALS_to_RAS type transform
           if (length(input)==10) && strcmp(input(4:7),'_to_') % Confirming ALS_to_RAS type
              rotation = rotation_matrix_from_img_transform(input);
           else % let's hope this is a "dsi_studio_btable_check" string
               % keep in mind that the transform described is what they
               % have applied to the bvecs, so it should be literal (vs
               % inverse, as in other cases)
               rotation=[1 0 0; 0 1 0; 0 0 1];
               if strcmp(input((end-1):(end)),'fz')
                   rotation(3,:)=-1*rotation(3,:);
                   input((end-1):(end))=[];
               end
               
                if strcmp(input((end-1):(end)),'fy')
                   rotation(2,:)=-1*rotation(2,:);
                   input((end-1):(end))=[];
                end
                
                if strcmp(input((end-1):(end)),'fx')
                   rotation(1,:)=-1*rotation(1,:);
                   input((end-1):(end))=[];
                end
               
               perm_dims=1+[str2num(input(1)),str2num(input(2)),str2num(input(3))];
               
               if max(perm_dims)>3
                   die;
               else
                   rotation=rotation(perm_dims,:);
               end           
               use_inverse=1; % Because up is down in this land.
           end
   end
end

% If we want to mimic the effect of the inverse of the transform as in
% image space, we DON'T want to invert it.  

if ~use_inverse
    rotation=inv(rotation);
end
mag=sqrt(rotation(1,:).^2 + rotation(2,:).^2 + rotation(3,:).^2);
rotation=rotation./repmat(mag',1,3);
end
