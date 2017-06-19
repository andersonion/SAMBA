function study_stats_by_contrast_exec(input_path,contrast_or_contrasts,string_of_runnos,output_path)
%
%
% The stats files are assumed to be in the directory specified by the input_path, in the form of {runno}*stats.txt
% For the pipeline, the wildcard should correspond to _{atlas_id}_labels_in_{space}_space_.
% If multiple files in the folder match this pattern, then the one most recently "touched"  will be used.
%
% out_file is optional; if an existing directory is specified, it will be
% used with the default format for output name: studywide_stats_for_{contrast}.txt


if ~isdeployed
    
    if ~exist('contrast','var')
        contrast_or_contrasts='volume,e1';
    end
    
    if ~exist('input_path','var')
        input_path='/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_affine_native_space/chass_symmetric2/stats/individual_label_statistics/';
    end
    
    if ~exist('output_path','var')
        output_path=['/glusterspace/VBM_13colton01_chass_symmetric2_April2017analysis-work/dwi/SyN_0p5_3_0p5_fa/faMDT_nos2_n28_i6/stats_by_region/labels/post_affine_native_space/chass_symmetric2/stats/studywide_label_statistcs/studywide_stats_for_' contrast_or_contrasts '.txt'];
    end
    
    if ~exist('string_of_runnos','var')
        string_of_runnos = 'N51211,N51221,N51231,N51383,N51386,N51404,N51406,N51193,N51136,N51201,N51234,N51241,N51252,N51282,N51390,N51392,N51393,N51133,N51388,N51124,N51130,N51131,N51164,N51182,N51151,N51622,N51620,N51617';
        %string_of_runnos = 'N51406,N51193';
    end
end

if exist('output_path','var')
    if ~exist(output_path,'dir')
        output_path = input_path;
    else
        if ~strcmp('/',output_path(end))
            out_file2=output_path;
        end
    end
else
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
    
    figure_support = 0; % First round of code will not support figures, but want to keep code just in case
    
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
                T=table();
                T=readtable(mystatsfile,'HeaderLines',4,'Delimiter','\t');
                
                def_vol = 'volume_mm3';
                if strcmp(contrast,'volume')
                    contrast=def_vol;
                end
                
                if strcmp(contrast,'vol')
                    contrast=def_vol;
                end
                
                if strcmp(contrast,'volume (mm3)')
                    contrast=def_vol;
                end
                
                c_data = eval(['T.' contrast]);
                if ~current_width;
                    master_T.ROI = T.ROI;
                    current_width = 1;
                end
                master_T.(runno)=c_data;
                
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
