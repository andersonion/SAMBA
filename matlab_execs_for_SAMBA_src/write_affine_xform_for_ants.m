function [ A_thru_L ] = write_affine_xform_for_ants(out_file_path, A_thru_L,varargin)
%WRITE AFFINE TRANSFORM THAT IS COMPATIBLE WITH ANTs 
%   Detailed explanation goes here
if ~(isempty(varargin{1}))
    if( length(varargin) == 1)
        fixed=varargin{1};
    else 
        fixed_1=varargin{1};
        fixed_2=varargin{2};
        fixed_3=varargin{3};
        fixed = [fixed_1 fixed_2 fixed_3];
    end
else
    fixed=[0 0 0];
end
fixed=double(fixed);
A_thru_L=double(A_thru_L);
size_transform = size(A_thru_L);

if size_transform(1) > 1  % Required format: 1x12 double
    total_size = size_transform(1)*size_transform(2);
    A_thru_L = reshape(A_thru_L',1,total_size);
end

if (size_transform(2) == 9)
    A_thru_L = [A_thru_L 0 0 0] % Default translation is NO translation
end
[path,name,ext] = fileparts(out_file_path);
text_file = [path '/' name '.txt']

%file_name='';
fID = fopen(text_file,'w');
fprintf(fID,'#Insight Transform File V1.0\n');
fprintf(fID,'#Transform 0\n');
fprintf(fID,'Transform: AffineTransform_double_3_3\n');
fprintf(fID,'Parameters: %01.16f %01.16f %01.16f %01.16f %01.16f %01.16f %01.16f %01.16f %01.16f %01.16f %01.16f %01.16f\n',A_thru_L);
fprintf(fID,'FixedParameters: %01.16f %01.16f %01.16f\n',fixed);
fclose(fID);
%% Bonus try to convert to the usual '.mat' format transform.
cmd= ['ConvertTransformFile 3 ' text_file ' ' out_file_path ' --convertToAffineType']
[s,sout]=system(cmd);
if exist(out_file_path,'file')
    cmd_2 = ['rm ' text_file];
    system(cmd_2);
    fprintf('Created transform %s!\n',out_file_path);
else
    fprintf('Created transform %s!\n',text_file);
end

end

