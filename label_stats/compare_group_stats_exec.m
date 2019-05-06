function compare_group_stats_exec(stats_file,contrast,group_1_name,group_2_name,group_1_runno_string,group_2_runno_string,out_dir,skip_first_row)
% Calculates various statistical tests with a binary model between two groups
%
% stats_file: the headerless, tab-delimited input .txt file; first entry must be 'ROI', and the various runnos filling out the rest of the first row
%            Note that the global volume will be appended to the end of the
%            file, labeled as ROI '0' (zero), replacing the exterior.
% contrast: which quantitative contrast to compare; 'vol','volume', and  'volume_mm3_' are all recognized as volume, and will be normalized by the global volumes.
% group_1_name/group_2_name: string describing the group ('control','treated','cb57', etc)
% group_1_runno_string/group_2_runno_string: comma-delimited string of runnos in the respective groups.
% out_dir: [optional] directory which to write the output; default is to put it in the same dir as the stats_file.
% skip_first_row: [optional] binary flag, indicator whether or not to EXCLUDE the exterior; default: 1
%
% Note that a two-line header is written in the form of:
%   {group_1_name}(n={n_specimens_in_group_1}):{comma_delimited_string_of_group_1_runnos}
%   {group_2_name}(n={n_specimens_in_group_2}):{comma_delimited_string_of_group_2_runnos}

vols=0;

if ~isdeployed
    contrast='fa';
    stats_file=['/civmnas4/rja20/studywide_stats_for_' contrast '.txt'];
    group_1_name='us';
    group_2_name='them';
    group_1_runno_string='N57008,N57009';
    group_2_runno_string='N57010,N57020';
    [out_dir,~,~]=fileparts(stats_file);
    vols=0;
end

if exist(stats_file,'dir')
   stats_file = [stats_file '/studywide_stats_for_' contrast '.txt'];
end
if ~exist('out_dir','var')
    [out_dir,~,~]=fileparts(stats_file);
    out_dir=[out_dir '/'];
end

if ~exist(out_dir,'dir')
    mkdir(out_dir);
    chmod_cmd = ['chmod 777 ' out_dir];
    system(chmod_cmd);
end
if ~exist('skip_first_row','var')
    skip_first_row = 1; % The default is to assume the first ROI is 0 (exterior) and that we want to ignore it.
else
    if ischar(skip_first_row)
       skip_first_row = str2num(skip_first_row); 
    end
    skip_first_row= ~(skip_first_row==0); % force logical/boolean
end

switch contrast
    case 'volume'
        vols=1;
    case 'vol'
        vols=1;
    case 'volume_mm3_'
        vols=1;
    otherwise
        vols=0;
end

group_1_runnos = strsplit(group_1_runno_string,',');
group_2_runnos = strsplit(group_2_runno_string,',');

num_g1 = length(group_1_runnos);
num_g2 = length(group_2_runnos);

out_file=[out_dir '/' contrast '_group_stats_' group_1_name '_n' num2str(num_g1) '_vs_' group_2_name '_n' num2str(num_g2) '.txt'];


% Load stats file as a table
%stats_table = readtable(stats_file,'ReadVariableNames',1,'HeaderLines',0,'Delimiter','\t','TreatAsEmpty',{'NA','NaN','NULL'} );
stats_table = readtable(stats_file,'ReadVariableNames',1,'HeaderLines',0,'Delimiter','\t' );

num_labels = size(stats_table,1)-skip_first_row; % We are assuming ROI "0" is the exterior

ROIs = stats_table.ROI((skip_first_row+1):end);
fprintf('Comparing %s of groups: %s (n = %i) vs. %s (n = %i) for %i labels...\n',contrast,group_1_name,num_g1,group_2_name,num_g2,num_labels)

% For each group:
% initialize_array
g1_array = zeros([num_labels num_g1]);
g2_array = zeros([num_labels num_g2]);

% find group1 variables
% put columns from table into array
for gg1 = 1:num_g1
    g1_array(:,gg1)=eval(['stats_table.' group_1_runnos{gg1} '(' num2str(skip_first_row +1) ':end)' ]);
end

for gg2 = 1:num_g2
    g2_array(:,gg2)=eval(['stats_table.' group_2_runnos{gg2} '(' num2str(skip_first_row+1) ':end)' ]);
end

num_g2=size(g2_array,2);
num_g1=size(g1_array,2);
num_labels=size(g1_array,1);

%if dealing with volumes normalize first

if vols==1;
    g1_ext=0;
    g2_ext=0;
    if ~skip_first_row
        g1_ext=g1_array(1,:);
        g2_ext=g2_array(1,:);
    end
    
    brain_g2_array=sum(g2_array)-g2_ext; % Account for CSF?
    brain_g1_array=sum(g1_array)-g1_ext;
    
    g2_array=100*g2_array./repmat(brain_g2_array,num_labels,1);
    g1_array=100*g1_array./repmat(brain_g1_array,num_labels,1);
    %APPEND BRAIN
    g2_array=[g2_array;brain_g2_array];
    g1_array=[g1_array;brain_g1_array];
    
    num_g1 = num_g1+1;
    num_g2 = num_g2+1;
    ROIs = [ROIs' 0]'; % Note that '0' refers to global now, instead of exterior
end

[h, p, table, stats]=ttest2(g2_array',g1_array');

%[hBH, crit_p,  adj_p]=fdr_bh(p,0.05,'pdep','yes'); % Maybe this was used with and older version of fdr_bh?
[~, ~, ~, adj_p]=fdr_bh(p,0.05,'pdep','yes');

[ppermute,~,~]=mattest(g2_array,g1_array,'Permute', 1000);


%pooledsd=sqrt(std(g1_array').^2/num_g1+std(g2_array').^2/num_g2);
pooledsd=sqrt((num_g1-1).*std(g1_array').^2+(num_g2-1).*std(g2_array').^2)./sqrt(num_g1+num_g2-2);
cohen_d=-(mean(g1_array')-mean(g2_array'))./pooledsd;
difference=-(mean(g1_array')-mean(g2_array'))*100./mean(g1_array');

ci_l_g2=mean(g2_array')-1.96*std(g2_array');
ci_h_g2=mean(g2_array')+1.96*std(g2_array');
%ci_l_g1=mean(g1_array')-1.96*std(g1_array');
%ci_h_g1=mean(g1_array')+1.96*std(g1_array');
ci_l_g1=nanmean(g1_array')-1.96*nanstd(g1_array');
ci_h_g1=nanmean(g1_array')+1.96*nanstd(g1_array');


%%
sig_idx = find(adj_p<0.05);
num_sigs = length(sig_idx);
if (num_sigs > 0 )
    
    sig_ROIs=ROIs(sig_idx);
    

    fprintf('\nLabels featuring uncorrected significant differences:\n')
    for ss = 1:num_sigs
        if mod(ss,15) && ~(ss==num_sigs)
            fprintf('%i, ',sig_ROIs(ss));
        else
            fprintf('%i\n',sig_ROIs(ss));
        end
        
        if (ss==num_sigs)
            fprintf('\n');
        end
    end
end

mystats=[ROIs'; mean(g2_array'); mean(g1_array') ;std(g2_array'); std(g1_array') ;std(g2_array')/sqrt(num_g2); std(g1_array')/sqrt(num_g1);ci_l_g2; ci_l_g1; ci_h_g1; ci_h_g2; h; p; ppermute'; adj_p; table;stats.tstat;cohen_d;difference];

myheader={'ROI', ['mean_' group_2_name ], ['mean_' group_1_name ], ['std_' group_2_name ], ['std_' group_1_name ], ['sem_' group_2_name ], ['sem_' group_1_name ], ['ci1_' group_2_name ],['ci2_' group_2_name ],['ci1_' group_1_name ],['ci2_' group_1_name ], 'hypothesis', 'p_value', 'ppermute', 'P_FDR_0p05_BH', 'CI_1', 'CI_2', 't_stats', 'cohen_d' ,'difference'};

out_table = array2table(mystats','VariableNames',myheader);
out_file_head=[out_file '.hd'];
[of_dir,of_name,of_ext]=fileparts(out_file);
out_file_temp=[of_dir '/' of_name '.tmp' of_ext];
fprintf('\nWriting table to file:\n%s\n',out_file)
writetable(out_table,out_file_temp,'Delimiter','\t')

fid = fopen(out_file_head, 'a');
fprintf(fid, '%s(n=%i):%s\n',group_1_name,num_g1,group_1_runno_string);
fprintf(fid, '%s(n=%i):%s\n',group_2_name,num_g2,group_2_runno_string);
fclose (fid);

cat_cmd = ['cat ' out_file_head ' ' out_file_temp ' > ' out_file];
system(cat_cmd);
rm_cmd_1 = ['rm ' out_file_head];
rm_cmd_2 = ['rm ' out_file_temp];
system(rm_cmd_1);
system(rm_cmd_2);

end
