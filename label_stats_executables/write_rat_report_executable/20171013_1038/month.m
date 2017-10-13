function [n, m] = month(d,f)
%MONTH Month of date.
%   [N,M] = MONTH(D) returns the month of a serial date number or a date string, D.
%   N is the numeric representation of the month and M is the three letter
%   abbreviation.
%
%	[N,M] = MONTH(S,F) returns the year of one or more date strings S using 
%   format string F. S can be a character array where each
%	row corresponds to one date string, or one dimensional cell array of 
%	strings.  
%
%	All of the date strings in S must have the same format F, which must be
%	composed of date format symbols according to Table 2 in DATESTR help.
%	Formats with 'Q' are not accepted.  
%
%   Example:
%      19-Dec-1994 (728647)
%
%      [n, m] = month(728647)
%      n =
%          12
%      m =
%          Dec
%
%      [n, m] = month('19-Dec-1994')
%      n =
%          12
%      m =
%          Dec
%
%   See also DATEVEC, DAY, YEAR.

%   Copyright 1995-2006 The MathWorks, Inc.

if nargin < 1
    error(message('finance:month:missingInput'))
end

if nargin < 2
  f = '';
end

tFlag = false;   %Keep track if input was character array 
if ischar(d)
    d = datenum(d,f);
    tFlag = true;
end

% Generate date vectors
if nargin < 2  || tFlag
  c = datevec(d(:));
else
  c = datevec(d(:),f);
end

% Monthly strings
mths = ['NaN';'Jan';'Feb';'Mar';'Apr';'May';'Jun';'Jul'; ...
    'Aug';'Sep';'Oct';'Nov';'Dec'];

% Extract numeric months
n = c(:, 2);

% Keep track of nan values.
nanLoc = isnan(n);

% Extract monthly strings. (c(:, 2) == 0) handles the case when d = 0.
mthIdx = c(:, 2) + (c(:, 2) == 0);
mthIdx(nanLoc) = 0;
m = mths(mthIdx + 1, :);

% Preserve the dims of the inputs for n. m is a char array so it should be
% column oriented.
if ~ischar(d)
    n = reshape(n, size(d));
end


% [EOF]
