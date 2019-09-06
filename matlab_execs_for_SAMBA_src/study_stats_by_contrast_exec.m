function study_stats_by_contrast_exec(input_path,contrast_or_contrasts,string_of_runnos,output_path)
% study_stats_by_contrast_exec(input_path,contrast_string,runno_string,output_path)
% input_path - directory of stat files
% contrast_string - comma list of contrasts to look at, 
%                   (fieldnames of stat sheet).
% runno_string - comma list of runnnos
% output_path - where to save the grouped stats, either a directory or a
% file.
%
% stat files in the directory specified by the input_path, in the form of {runno}*stats.txt
% For the pipeline, the wildcard should correspond to _{atlas_id}_labels_in_{space}_space_.
% If MUTLTIPLE files match this pattern, the one most recently modified will be used.
%
% output_path is optional; if an existing directory is specified, it will be
% used with the default format for output name: studywide_stats_for_{contrast}.txt


if ~isdeployed
    if ~exist('contrast_or_contrasts','var')
        contrast_or_contrasts='volume,dwi,fa,fa_std,dwi_std,fa_CoV,dwi_CoV'; end
    if ~exist('input_path','var')
        input_path='/civmnas4/rja20/'; end
    if ~exist('output_path','var')
        output_path=['EMPTY TESTING /civmnas4/rja20/studywide_stats_for_' contrast_or_contrasts '.txt']; end
    if ~exist('string_of_runnos','var')
        string_of_runnos = 'N57008,N57009,N57010,N57020'; end
        %string_of_runnos = 'N51406,N51193'; end
end

if exist('output_path','var')
    if ~strcmp('/',output_path(end))
        out_file2=output_path;
    end
else
    error('Need output path specified!');
    output_path = input_path;
end
contrast_or_contrasts_cell=strsplit(contrast_or_contrasts,',');

for cc = 1:length(contrast_or_contrasts_cell)
    contrast = contrast_or_contrasts_cell{cc};
    fprintf('Creating study-wide stats file for contrast: %s\n',contrast);
    if  ~exist('out_file2','var')
        out_file = [output_path '/studywide_stats_for_' contrast '.txt'];
    else
        out_file = out_file2;
    end
    
    % First round of code will not support figures, but want to keep code just in case
    figure_support = 0; 
    allrunnos = strsplit(string_of_runnos,',');
    master_timestamp=0;
    if exist(out_file,'file')
        %new_table = 0;
        mt_info = dir(out_file);
        master_timestamp=mt_info.datenum;
        master_T = readtable(out_file,'ReadVariableNames',1,'HeaderLines',0,'Delimiter','\t');
    else
        master_T = table();
    end
    
    existing_runnos = master_T.Properties.VariableNames;
    
    current_width = length(existing_runnos);
    for i=1:numel(allrunnos)
        action_code=0; %  0: append, 1: update(replace), 2: skip,
        runno=char(allrunnos{i});
        col_idx = find(strcmp(runno,existing_runnos),1);
        if isempty(col_idx)
            action_code = 0;
            col_idx = 0;
        else
            action_code = 1;
        end
        %master_T(ismember(master_T.runno
        potential_files= dir([input_path '/' runno '*stats.txt']);
        %potential_files= dir([input_path '/*stats.txt']);
        % Find most recent files, if somehow there are multiple
        if isempty(potential_files)
            fprintf('Potential error: no input files found for runno: %s; will continue tabulating statistics anyways.\n',runno);
        else
            for tt = 1:length(potential_files)
                time_stamps(tt) = potential_files(tt).datenum;
            end
            t_idx=find(time_stamps==max(time_stamps(:)));
            c_timestamp = time_stamps(t_idx);
            mystatsfile=[input_path '/' potential_files(t_idx).name];
            
            if action_code
                % Is runno stats file older than studywide stats file?
                if c_timestamp < master_timestamp
                    action_code = 2; % skip if runno file is older
                    fprintf('Data for %s already found; skipping...\n',runno)
                end % else update/replace data
            end
            
            if action_code < 2
                T = readtable(mystatsfile,'Delimiter','\t');
                if ~strcmp(T.Properties.VariableNames{1},'ROI')
                    % We used to write several lines of header info, but that is replaced
                    % with writetable, with no headers.
                    T=readtable(mystatsfile,'HeaderLines',4,'Delimiter','\t');
                    %T=readtable(mystatsfile,'Format','%f %s','CommentStyle','#','HeaderLines',4,'Delimiter','\t');
                end
                    
                def_vol = 'volume_mm3';
                if strcmp(contrast,'volume') ...
                    || strcmp(contrast,'vol') ...
                    || strcmp(contrast,'volume (mm3)')
                    contrast=def_vol;
                end
                % After 19 Feb 2019 we start explicitly providing stats beyond
                % the implied mean value of the contrast
                try
                    c_data = T.([contrast '_mean']);
                catch
                    % Backwards compatible line; also needed for volume
                    c_data = T.(contrast);
                end
                
                temp_T = table();
                temp_T.ROI = T.ROI;
                try
                    temp_T.structure = T.structure;
                catch
                end
                temp_T.(runno)=c_data;
                
                
                if ~current_width;
                    master_T = temp_T;
                    current_width = 1;
                else
                    try
                        master_T = outerjoin(master_T,temp_T,'Keys',{'ROI','structure'},'MergeKeys',1);
                    catch

                       master_T = outerjoin(master_T,temp_T,'Keys',{'ROI'},'MergeKeys',1);
                    end
                end
   
            end
        end
    end
    %%
    
    writetable(master_T,out_file,'Delimiter','\t')
end


if figure_support
    figure_dir = '/Volumes/alex/ROI_FIGS/'
    ind=[1 4 11 15 16 25]
    legend=[{'Cg'} {'ac'} {'ic'} {'fi'} {'cc'} {'ot'}]
    G=[repmat({'3mob '},1,9) repmat({'3moc '},1,9) repmat({'1wkb '},1,9) repmat({'1wkc '},1,8)]
    for j=1:numel(ind)
        mytitle=['FA_' legend{j}]
        mysize=3;
        set(gca, 'FontSize', 18, 'LineWidth', 3); %<- Set properties
        set(gca,'XTick',[1 2 3 4]);
        boxplot(fa(:,1+ind(j)), G, 'whisker',1)
        title(['FA ' legend{j}],'FontSize', 18)
        
        print([figure_dir mytitle '.png'],'-dpng','-r300');
    end
    
    for j=1:numel(ind)
        mytitle=['RD_' legend{j}]
        mysize=3;
        set(gca, 'FontSize', 28, 'LineWidth', 3); %<- Set properties
        set(gca,'XTick',[1 2 3 4]);
        boxplot(rd(:,1+ind(j)), G, 'whisker',1)
        title(['RD ' legend{j}],'FontSize', 28)
        
        print([figure_dir mytitle '.png'],'-dpng','-r300');
    end
    
    for j=1:numel(ind)
        mytitle=['E1_' legend{j}]
        mysize=3;
        set(gca, 'FontSize', 28, 'LineWidth', 3); %<- Set properties
        set(gca,'XTick',[1 2 3 4]);
        boxplot(e1(:,1+ind(j)), G, 'whisker',1)
        title(['E1 ' legend{j}],'FontSize', 28)
        
        print([figure_dir mytitle '.png'],'-dpng','-r300');
    end
    
    for j=1:numel(ind)
        mytitle=['ADC_' legend{j}]
        mysize=3;
        set(gca, 'FontSize', 28, 'LineWidth', 3); %<- Set properties
        set(gca,'XTick',[1 2 3 4]);
        boxplot(adc(:,1+ind(j)), G, 'whisker',1)
        title(['ADC ' legend{j}],'FontSize', 28)
        
        print([figure_dir mytitle '.png'],'-dpng','-r300');
    end
    figure(1)
    for j=1:numel(ind)
        mytitle=['Volume_' legend{j}]
        mysize=3;
        set(gca, 'FontSize', 28, 'LineWidth', 3); %<- Set properties
        set(gca,'XTick',[1 2 3 4]);
        boxplot(vol(:,1+ind(j)), G, 'whisker',1)
        title(['Volume ' legend{j}],'FontSize', 28)
        
        print([figure_dir mytitle '.png'],'-dpng','-r300');
    end
    
    allvols=[]; % was originally hardcoded
    
    allvols2=100*allvols./repmat(allvols(:,28), 1,28);
    allvols2(:,28)=allvols(:,28);
    
    vollegend={'Cingulum' 'Mesencephalon'}; % et cetera, et cetera, et cetera...
    for j=1:numel(vollegend)
        mytitle=['NormedVolume_' vollegend{j}]
        mysize=3;
        set(gca, 'FontSize', 28, 'LineWidth', 3); %<- Set properties
        set(gca,'XTick',[1 2 3 4]);
        boxplot(allvols2(:,j), G, 'whisker',1)
        title(['Volume ' vollegend{j}],'FontSize', 28)
        
        print([figure_dir mytitle '.png'],'-dpng','-r300');
    end
end
end
