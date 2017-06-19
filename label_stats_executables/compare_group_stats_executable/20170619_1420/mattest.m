function [p,t,df] = mattest(X1, X2, varargin)
%MATTEST Two-sample t-test for identifying differentially expressed genes
% from two different conditions/phenotypes.
%
%   P = MATTEST(X1,X2) performs an unpaired t-test for differential
%   expression with a standard two-tailed and two-sample t-test on every
%   row (gene) of the expression matrices, and returns the results of the
%   p-values for every gene. The data are assumed to be normally
%   distributed in each class. X1 and X2 can be a numeric matrix or a
%   DataMatrix object. X1 and X2 must have the same number of rows. If all
%   or any of X1 and X2 are DataMatrix objects, P is a DataMatrix object
%   with row names that are the same as the first DataMatrix object, and
%   column name is 'p-values'.
%
%   [P, T] = MATTEST(...) returns the t-scores T for each gene.
%
%   [P, T, DF] = MATTEST(...) returns the degrees of freedom DF of the
%   test.
%
%   MATTEST(...,'VARTYPE', VARTYPE) specifies the variance type of the
%   test. VARTYPE can be 'equal' or 'unequal' (default). When VARTYPE is
%   'equal', MATTEST performs the test assuming equal variances. When
%   VARTYPE is 'unequal', MATTEST performs the test assuming the two
%   samples have unknown and unequal variances.
%
%   MATTEST(...,'PERMUTE', P) perform permutation tests to if P is set to
%   TRUE.  The default number of permutation is 1000. P can also be the
%   number of permutations if is set to be greater than 2. The default is
%   FALSE.
% 
%   MATTEST(...,'BOOTSTRAP', B) perform bootstrap tests to if B is set to
%   TRUE.  The default number of bootstrap is 1000. B can also be the
%   number of bootstrap if is set to be greater than 2. The default is
%   FALSE.
% 
%   MATTEST(...,'SHOWHIST',TRUE) displays histograms of the p-value
%   distribution and t-score distribution. 
%
%   MATTEST(...,'SHOWPLOT',TRUE) displays normal t-scores quantile plot.
%   The points with t-score greater than the (1 - 1/(2N)) quantile or less
%   than the 1/(2N) quantile are marked with red circles. N is total number
%   of genes in the t-test.
% 
%   MATTEST(...,'LABELS',LABELS) allows you to specify a cell array of gene
%   labels or names for each row of the input data. If LABELS are defined,
%   then clicking on a data point on the plot will show the LABEL
%   corresponding to that data point. 
% 
%   Note: If the input data contains DataMatrix objects, and 'LABELS'
%   option is not defined. The row names of the first input DataMatrix
%   object are used as LABELS. 
% 
%   Example:
%       load prostatecancerexpdata; 
%       [p,t]=mattest(dependentData,independentData, 'showplot', true);
% 
%       % Permutation t-tests.
%       [p,t]=mattest(dependentData,independentData, 'permute', true,...
%                           'Showhist', true', 'showplot', true);
% 
%       % Bootstrap t-tests.
%       [p,t]=mattest(dependentData,independentData, 'bootstrap', 2000,...
%                           'Showhist', true', 'showplot', true);
% 
%   See also AFFYGCRMA, AFFYRMA, CNSGENEEXPDEMO, GCRMA, MAFDR, MAIRPLOT,
%   MALOGLOG, MAPCAPLOT, MAVOLCANOPLOT, RMASUMMARY.

% Copyright 2005-2009 The MathWorks, Inc.


% References: 
%  [1] W. Huber, A. von Heydebreck, H. Süütmann, A. Poustka, M. Vingron;
%      "Variance stabilization applied to microarray data calibration and
%      to the quantification of differential expression", Bioinformatics
%      (2002) 18 Suppl1 S96-S104.


bioinfochecknargin(nargin,2,mfilename)

%== Parse input options
appdata = parse_inputs(varargin{:});
appdata.DataMatrixFlag = false;

if isa(X1, 'bioma.data.DataMatrix')
    if isempty(appdata.labels)
        appdata.labels = X1.RowNames;
    end
    X1 = X1.(':')(':');
    appdata.DataMatrixFlag = true;
end

if isa(X2, 'bioma.data.DataMatrix')
    if isempty(appdata.labels)
        appdata.labels = X2.RowNames;
    end
    X2 = X2.(':')(':');
    appdata.DataMatrixFlag = true;
end

appdata = check_inputdata(X1, X2, appdata);

% do ttest
if appdata.nperms ~= 0
    [p, t, df] = permutationtests(X1, X2, appdata.nperms, appdata.vartype);
elseif appdata.nboots ~= 0
    [p, t, df] = bootstraptests(X1, X2, appdata.nboots, appdata.vartype);
else
    if appdata.vartype == 1
        [~,p,~,stats] = ttest2(X1, X2, [],[],'equal',2);
    else
        [~,p,~,stats] = ttest2(X1, X2, [],[],'unequal',2);
    end
    t = stats.tstat;
    df = stats.df;
end

if appdata.DataMatrixFlag
    p = bioma.data.DataMatrix(p, appdata.labels, {'p-values'});
    t = bioma.data.DataMatrix(t, appdata.labels, {'t-scores'});
    df = bioma.data.DataMatrix(df, appdata.labels, {'df'});
end

if appdata.qplotFlag  
    df_eq = size(X1,2) + size(X2,2) - 2;
    if appdata.DataMatrixFlag
        appdata.hqpfig = plotquantilet(t.(':')(':'), df_eq, appdata.labels);
    else
       appdata.hqpfig = plotquantilet(t, df_eq, appdata.labels);
    end
end

if appdata.histFlag
    if appdata.DataMatrixFlag
        appdata.hdfig = plothistogram(t.(':')(':'), p.(':')(':'));
    else
        appdata.hdfig = plothistogram(t, p);
    end
end
end

%*********** Callbacks and helper functions ***************
function [p, t, df] = permutationtests(X1, X2, nperms, vartype)
% Perform permutation tests
[p, t, df] = resampling(X1, X2, nperms, false, vartype);
end

%------------------------------------------------------
function [p, t, df] = bootstraptests(X1, X2, nboots, vartype)
% Perform bootstrap two-sample ttest. 
%   Resampling under H0 
%   Mix the two samples
%   Draw bootstrap sample from each group
%   Compute p-value = sum(I(t_b >= t_0))/B.

[p, t, df] = resampling(X1, X2, nboots, true, vartype);
end

function [p, t, df] = resampling(X1, X2, nsamples, replace, vartype)
% Number of samples
n1 = size(X1, 2);
n2 = size(X2, 2);
n = n1 + n2;
X = [X1 X2];
m = size(X1, 1);

% Compute observed t statitics
[t,df] = computeGroupT(X1, X2, n1, n2, vartype);

% Conduct a permutation (bootstrap) test to create a sample from the null
% distribution of the t statistics. Permute the transcripts at random (with
% replacement for bootstrap), compute t-scores among the random partitions
% of the actual samples, repeat for a large number permutations.
% Bin the samples
edge = max(findedge(t), 20);
numbins = max(1000,getUpperGeneNumber(m));
t0edges = linspace(-edge, edge,numbins+1)'; % #bins odd -> edge at zero
t0bins = t0edges(1:end-1) + diff(t0edges)/2;
t0 =zeros(size(t0edges));

for i = 1:nsamples
    if replace % with replacement for Bootstrap
        grp1 = X(:, randsample(n, n1, true));
        grp2 = X(:, randsample(n, n2, true));
    else % without replacement for permutation
        [grpidx1, grpidx2] = crossvalind('LeaveMOut', n, n2);
        grp1 = X(:, grpidx1);
        grp2 = X(:, grpidx2);
    end
    t0rep = computeGroupT(grp1, grp2, n1, n2, vartype);
    t0 = t0 + histc(t0rep, t0edges);
end

t0 = t0(1:end-1); % drop the degenetated uppermost bin

% Estimate the null distribution of |t| and compute its empirical
% cumulative distribution function.
[f0, x0] = ecdf(abs(t0bins), 'freq', t0);
x0(1) = 0;

% Estimate p-values corresponding to truly null hypotheses for the observed
% t-scores from the t-test

% To filter out the same x0 returned by ecdf dued to the folding of t0bins
h = find(diff(x0)<1e-9);
f0(h) = (f0(h)+f0(h+1))./2;
x0(h+1)=[];
f0(h+1)=[];

gi = griddedInterpolant(x0, f0, 'pchip');
p = min(1,max(0,abs(1-gi(abs(t)))));

%== update class
if isa(X1, 'single')
   t = single(t);
   df = single(df);
   p = single(p);
end
end

%--------------------
function [t, df] = computeGroupT(X1, X2, ngrp1, ngrp2,vartype)
% Return group means var means and t scores. 

seg1 = var(X1,[],2);
seg2 = var(X2,[],2); 
grpmean_diff = mean(X1,2)-mean(X2,2);

if vartype == 1
    %==Two-sample assuming unequal variance t-test.
    df = ngrp1 + ngrp2 - 2;
    pooled_se = sqrt(((ngrp1-1) .* seg1 + (ngrp2-1) .* seg2) ./ df);
    grpse = pooled_se .* sqrt(1./ngrp1 + 1./ngrp2);
elseif vartype == 2
    %==Two-sample assuming unequal variance t-test.
    sg1 = seg1./ngrp1;
    sg2 = seg2./ngrp2;
    grpse = sqrt(sg1 + sg2); 
    df = double((sg1+sg2).^2 ./ (sg1.^2 ./(ngrp1-1) + sg2.^2 ./(ngrp2-1)));
end
t = double(grpmean_diff ./ grpse);

if ~isscalar(t) && vartype == 1
    df = repmat(df,size(t));
end
end

%----------------------------------------------------------
function hqpfig = plotquantilet(tscore, df, labels)
% Do quantile plot
% df - degree of freedom of equal variance.

hqpfig = figure('Units', 'Normalized',...
                'Tag', 'Bioinfo:mattest:quantilePlot',...
                'Visible', 'off');

% Remove the NaNs 
goodidx = ~isnan(tscore);
tscore = tscore(goodidx);
df = repmat(df,size(tscore));

if ~isempty(labels)
    labels = labels(goodidx);
end

[tscore, ord] = sort(tscore);
if ~isempty(labels)
    labels = labels(ord);
    
    if ~ischar(labels) && isnumeric(labels)
       labels = cellstr(num2str(labels(:)));
    end
    
end

% number of genes
N = numel(tscore);
% Get quatile function of t stats
Xq = (1:N)';
Xq = (Xq - 0.5)/N;
tquantile = tinv(Xq, df);

haxes = axes;
set(haxes, 'Parent', hqpfig,...
           'Box', 'on',...
           'GridLineStyle', '--');

if tquantile ~= 0
    set(haxes, 'XLimMode', 'manual',...
               'YLimMode', 'auto',...
               'XLim',[min(tquantile), max(tquantile)]);
end

%up-regulated threshold
upThd = tinv( 1- 0.5/N, df);
upIdx = find(tscore > upThd);
%down-regulated threshold
dnThd = tinv( 0.5/N, df);
dnIdx = find(tscore < dnThd);

hplot = plot(tquantile, tscore, 'b.',...
             tquantile(upIdx), tscore(upIdx),'ro',...
             tquantile(dnIdx), tscore(dnIdx), 'ro',...
             tquantile, tquantile, 'k-.');

set(hplot, 'parent', haxes);
set(hplot(1), 'Tag', 'QuantileLine',...
              'DisplayName', 'Quantile');
if ~isempty(upIdx)
  set(hplot(2), 'Tag', 'UpQuantile',...
                'DisplayName', 'Significant');
end

if ~isempty(dnIdx)
    set(hplot(end-1), 'Tag', 'DownQuantile',...
                      'DisplayName', 'Significant')
end

set(hplot(end), 'DisplayName', 'Diagonal')

%== Turn off data cursor for other lines
hb=hggetbehavior(hplot(end), 'Datacursor');
set(hb, 'Enable', false)

%== Enable only the quantile line
dcm_obj = datacursormode(hqpfig);
set(dcm_obj,'UpdateFcn',{@locaDataCursorUpdate, dcm_obj, labels, upIdx, dnIdx})

% Set plot labels
xlabel('Theoretical quantile')
ylabel('Sample quantile')
title('Normal Quantile Plot of t')
set(hqpfig, 'Visible', 'on');
legend('Location','NorthWest')
end

function txt = locaDataCursorUpdate(hobj,eobj, dcm, labels, upIdx, dnIdx) %#ok<INUSL>
% Update the datacursor text.
tg = get(eobj, 'Target');
c=getCursorInfo(dcm);
if strcmpi(get(tg, 'Type'), 'line')
    type = get(tg, 'Tag');
    pos = get(eobj,'Position');
    if strcmpi(type, 'QuantileLine')            
        txt = {['Label: ', labels{c.DataIndex}],...
            ['T. quantile: ',num2str(pos(1))],...
            ['S. quantile: ',num2str(pos(2))]};
    elseif strcmpi(type, 'UpQuantile')
         txt = {['Label: ', labels{upIdx(c.DataIndex)}],...
            ['T. quantile: ',num2str(pos(1))],...
            ['S. quantile: ',num2str(pos(2))]};
    elseif strcmpi(type, 'DownQuantile')
         txt = {['Label: ', labels{dnIdx(c.DataIndex)}],...
            ['T. quantile: ',num2str(pos(1))],...
            ['S. quantile: ',num2str(pos(2))]};
    end
else
    txt = [];
    return;
end
end

%**************************************
function hdfig = plothistogram(tscore, pvalue)
% Plot histograms of tscores and p-values
hdfig = figure('Units', 'Normalized',...
                'Tag', 'Bioinfo:mattest:histogram',...
                'Visible', 'off');
subplot(1,2,1);
bw = .5;
edge = findedge(tscore);
edges = -edge:bw:edge;
hgt1 = histc(tscore,edges);
bar(edges,hgt1,'histc');
h = findobj(gca,'Type','patch');
set(h,'FaceColor',[1.0 0.3 0.3], 'EdgeColor', 'w')
xlim([-11 11]);
title('t-scores')
xlabel('t-score');
ylabel('Frequency')

subplot(1,2,2)
hist(pvalue, 0.025:0.05:.975);
h = findobj(gca,'Type','patch');
set(h,'FaceColor',[0.5 0.5 0.8], 'EdgeColor', 'w')
title('p-values')
xlabel('p-value');
ylabel('Frequency')

bioinfoprivate.suptitle('Histograms of t-test Results')
set(hdfig, 'visible', 'on')
end

%-----------------------------------------------
function n = getUpperGeneNumber(n)
% Return the rounded upper gene number
% for example, 3893 genes, return 4000

fn = floor(log10(n));
cn = ceil(log10(n));
if cn-fn == 0
    return;
end

m = ceil(n/(10^fn));
n = m*10^fn;
end
%---------------------------------------------------
function edge = findedge(t)
% return the rounded max |t|
maxt = getUpperGeneNumber(abs(max(t)));
mint = getUpperGeneNumber(abs(min(t)));
edge = max(maxt, mint);
end

%--------------------------------
function appdata = check_inputdata(X1, X2, appdata)
% Check input data type is numerical and contain the same number of genes
% or rows
if ~isnumeric(X1) || ~isreal(X1) || ~isnumeric(X2) || ~isreal(X2) 
   error(message('bioinfo:mattest:ExpressionValuesNotNumericAndReal')) 
end

% validate required inputs 
if size(X1,1)~=size(X2,1)
    error(message('bioinfo:mattest:differentSize'))
end

% Check the labels size
if(~isempty(appdata.labels))
    if (~isvector(appdata.labels) || numel(appdata.labels) < size(X1,1)) && ~appdata.DataMatrixFlag
        warning(message('bioinfo:mattest:MismatchedLabels'));
        appdata.labels = [];
    end
    
    appdata.labels = appdata.labels(:);
else
    appdata.labels = (1:size(X1,1))';
end

% Check permutation and bootstrap options
if appdata.nboots ~= 0 && appdata.nperms ~= 0
     warning(message('bioinfo:mattest:UsingPermuteOptionOnly'));
     appdata.nboots = 0;
end
end
%--------------------------------
function inputStruct = parse_inputs(varargin)
% Parse input PV pairs.

% Check for the right number of inputs
if rem(nargin,2)== 1
    error(message('bioinfo:mattest:IncorrectNumberOfArguments', mfilename))
end

% Allowed inputs
okargs = {'permute', 'bootstrap', 'showhist', 'showplot', 'labels','vartype'};

% Defaults
inputStruct.vartype = 2; % variance type: 1-equal, 2-unequal
inputStruct.qplotFlag = false;  % quantile plot
inputStruct.histFlag = false;   % histgram plot
inputStruct.labels = [];        % Gene labels
inputStruct.nperms = 0;         % number of permutation
inputStruct.nboots = 0;         % number of bootstrap

for j=1:2:nargin
    [k, pval] = bioinfoprivate.pvpair(varargin{j}, varargin{j+1}, okargs, mfilename);
    switch(k)
        case 1 % permutation
            if bioinfoprivate.opttf(pval)
                if isnumeric(pval)
                    if isscalar(pval)
                        inputStruct.nperms = ceil(double(pval));
                        if inputStruct.nperms <= 2
                            error(message('bioinfo:mattest:InvalidPermutationNumber'));
                        end
                    else
                        inputStruct.nperms = 1000;
                        warning(message('bioinfo:mattest:PermuteNumberNoScalar'))
                    end
                else
                    inputStruct.nperms = 1000;
                end
            else
                inputStruct.nperms = 0;
            end
        case 2 % bootstrap
            if bioinfoprivate.opttf(pval)
                if isnumeric(pval)
                    if isscalar(pval)
                        inputStruct.nboots = ceil(double(pval));
                        if inputStruct.nboots <= 2
                            error(message('bioinfo:mattest:InvalidBootstrapNumber'));
                        end
                    else
                        inputStruct.nboots = 1000;
                        warning(message('bioinfo:mattest:BootstrapNumberNoScalar'))
                    end
                else
                    inputStruct.nboots = 1000;
                end
            else
                inputStruct.nboots = 0;
            end
        case 3 % showhist
            inputStruct.histFlag = bioinfoprivate.opttf(pval,okargs{k},mfilename);
        case 4 % show quantile plot
            inputStruct.qplotFlag = bioinfoprivate.opttf(pval,okargs{k},mfilename);
        case 5 % labels
            inputStruct.labels = pval;
        case 6 % vartype
            try 
                okvartypes = {'equal', 'unequal'};
                vartype = validatestring(pval, okvartypes,'mattest','VARTYPE');
                inputStruct.vartype = strmatch(lower(vartype), okvartypes);
            catch ME
                bioinfoprivate.bioerrorrethrow(mfilename, ME);
            end
    end
end
end
