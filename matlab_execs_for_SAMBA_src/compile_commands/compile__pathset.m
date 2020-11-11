[pdir]=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(pdir,''));
addpath(fullfile(pdir,'..'));
addpath(fullfile(pdir,'..','fdr_bh'));
addpath(fullfile(pdir,'..','20130227_xlwrite'));
addpath('/cm/shared/workstation_code_dev/shared/mathworks/NIFTI_20140122');
addpath('/cm/shared/workstation_code_dev/shared/mathworks/wildcardsearch');
addpath(fullfile(getenv('WKS_SHARED'),'civm_matlab_common_utils'));