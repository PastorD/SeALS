function [ Dpunch] = diffop_region_spectral( x, D, region)
%REGIONDIFFOP Adds boundary conditions to derivative for the region.
% Inputs:
%   x - the underlying grid. If x is a vector, then it is assumed the grid
%   is uniform along each dimension
%   D - the derivative operator
%   region - the interval where the derivative does not apply.
% Outputs:
%   Dpunch - derivative operator incooporating region.
%
%   See also MAKEDIFFOP.


d = length(x);
opDU = cell(d,d); %derivative operator in each direction
                  %column is derivative direction, row is U{i}
               
for ii = 1:d
    
    d_ind = (x{ii} >= region(ii,1)) & (x{ii} <= region(ii,2)); %nodes interior
    
    DCanv = D{ii};
    DCanv(d_ind,:) = 0; %knock out the parts affecting the interior boundary    
        
    if d == 1
         opDU{ii,ii} = DCanv(:);
    else
        for jj = 1:d
            if ii == jj
                opDU{jj,ii} = [DCanv(:), D{ii}(:)];
            else
                id = eye(size(D{jj}));
                idRest = id;
                idRest(d_ind,:) = 0;                
                opDU{jj,ii} = [id(:)-idRest(:),  idRest(:)];
                
            end
        end
    end
end

Dpunch = cell(d,1);

for i=1:d
    Dpunch{i} = ktensor(opDU(:,i));
end

end