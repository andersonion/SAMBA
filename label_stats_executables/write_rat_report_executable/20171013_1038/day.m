function dom = day(d,f) 
%DAY  Day of month. 
%   DOM = DAY(D) returns the day of the month given a serial date number 
%   or date string, D. 
% 
%	DOM = DAY(S,F) returns the day of one or more date strings S using 
%   format string F. S can be a character array where each
%	row corresponds to one date string, or one dimensional cell array of 
%	strings.  
%
%	All of the date strings in S must have the same format F, which must be
%	composed of date format symbols according to Table 2 in DATESTR help.
%	Formats with 'Q' are not accepted.  
%
%   For example, dom = day(728647) or dom = day('19-Dec-1994') 
%   returns dom = 19. 
%  
%   See also MONTH, YEAR.
 
%       Copyright 1995-2006 The MathWorks, Inc.
 
if nargin < 1 
  error(message('finance:day:missingInputs')) 
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

dom = c(:,3);            % Extract day of month 
if ~ischar(d) 
  dom = reshape(dom,size(d)); 
end
