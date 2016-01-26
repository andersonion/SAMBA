% J = jacobian(S)
%   Determinant of Jacobian of a displacement field
%
% Herve Lombaert, Jan. 8th, 2013
% 
% Modified by BJ Anderson, CIVM, Duke University, Jan. 21, 2016
% Added necessary dx,dy,dz options and related input option handling

%
function det_J = jacobian(varargin)%sx,sy,sz,dx,dy,dz)

sx = varargin{1};
sy = varargin{2};
sz = varargin{3};



if nargin > 3 & ~isempty(varargin{4})
    dx = varargin{4};
else
    dx = 1;
end

if nargin > 4 & ~isempty(varargin{5})
    dy = varargin{5};
else
    dy = 1;
end

if nargin > 5 & ~isempty(varargin{6})
    dz = varargin{6};
else
    dz = 1;
end
            
    % Gradients
    [gx_y,gx_x,gx_z] = gradient(sx,dy,dx,dz);
    [gy_y,gy_x,gy_z] = gradient(sy,dy,dx,dz);
    [gz_y,gz_x,gz_z] = gradient(sz,dy,dx,dz);
    
    
    % Add identity
    gx_x = gx_x + 1;
    gy_y = gy_y + 1;
    gz_z = gz_z + 1;
    
    % Determinant
    det_J = gx_x.*gy_y.*gz_z + ...
            gy_x.*gz_y.*gx_z + ...
            gz_x.*gx_y.*gy_z - ...
            gz_x.*gy_y.*gx_z - ...
            gy_x.*gx_y.*gz_z - ...
            gx_x.*gz_y.*gy_z;
end
