function [F, err, iter, Fcond, e_list, time_step, illcond, maxit, maxrank, F_cell, B_cell, b_cell, restart] = als_sys_var(A,G,F,e,als_options,als_variant,debugging,verbose)
% ALS_SYS_VAR is a modified version of the original ALS algorithm found
% in Beylkin and Mohlenkamp 2005. ALS_SYS solves AF = G by iterating as in
% the original ALS until matrices gets ill-conditioned. Then it fixes the
% existing tensor terms in F by subtracting them to the RHS of AF=G and
% continue to iterate with smaller tensor terms. The process is repeated 
% and in the end the current tensor terms and the fixed ones are added to
% obtain the solution F. The modification mitigates the ill-conditioned 
% matrices, obtaining more accurate solutions. See the paper for details.
% Inputs:
%   F - inital guess. If it is empty a random guess will be used. If
%   it's a scalar ALS_SYS will start with a random tensor of that
%   rank.
%   e - desired error
%   debugging - 1 if all F, B (the ALS matrix) and b (RHS vector of the
%   system of equations where the ALS matrix is in) are saved in cell
%   arrays.
%   tol_it - maximum number of tolerated iterations. Default if 1000.
%   tol_rank - maximum tolerated rank for F. Default is 20.
%   e_type - type of error ('average' or 'total'). Default is (point)
%   average. 
%   r_tol - minimum decrease in error between iterations. Default is 1e-3.
%   alpha - regularization factor. Default is 1e-12.
%   newcond_r_tol - tolerated decrease for preconditon. Default is 1e-2.
%   newcond_it_tol - maximum number of tolerated iterations for
%   preconditon. Default is 15.
%   w_tol - if the smallest divide by the largest normalization constant is
%   < w_tol, stop iterations.
% Outputs:
%   F - obtained solution.
%   err - achieved error.
%   iter - number of iterations.
%   Fcond - condition number for F during the run.
%   e_list - indices when new tensor term was added
%   t_step - computing time for als onestep during the run
%   illcond - 1 if an als matrix were illcond.
%   maxit - 1 if maximum number of tolerated iterations was exceeded.
%   F_cell - all F during a run
%   B_cell - all B (ALS matrices) during a run
%   b_cell - all b (RHS vectors) during a run
%
% See also MAIN_RUN.

% Elis Stefansson, Aug 2015

%% assign
[max_osc,max_it_rank] = deal(als_variant{:});

if isempty(als_options)
    tol_it = 2000;
    tol_rank = 20;
    e_type = 'average';
    r_tol = 1e-3;
    w_tol = sqrt(eps);
    alpha = 1e-12;
    newcond_r_tol = 0.01;
    newcond_it_tol = 15;
else
    [tol_it,tol_rank,e_type,r_tol,alpha,newcond_r_tol,newcond_it_tol] = ...
        deal(als_options{:});
    w_tol = sqrt(eps);
end

if strcmp(e_type,'average')
    norA = sqrt(prod(size(G)));
elseif strcmp(e_type,'total')
    norA = 1;
else
    error('wrong type of error specified');
end

if nargin < 8
    verbose = 1;
end

%% documentation
if debugging == 1
    maxit = 0; %1 if max iter exceeded
    maxrank = 0; %1 if max rank exceeded
    illcond = 0; %1 if ill-conditioned matrix
    B_cell{1,2} = {}; %just to make sure it has correct dims
    b_cell{1,2} = {};
else
    maxit = 0;
    maxrank = 0;
    illcond = 0;
    F_cell = {};
    B_cell = {};
    b_cell = {};
end
%%% Variant %%%
restart = []; %when F is incooporated in G and als restarts.
osc = 0; %how many tolerated oscillations, we don't want error to oscillate
F_saved = []; %saved tensor terms of F
%%% Variant %%%

%% main script
nd = ndims(G);
sizeG = size(G);
% sG = sizeG(1); %For simplicity, assuming all meshes are the same.

if isempty(F)
    U = cell(1,nd);
    for n = 1:nd
        U{n} = matrandnorm(sizeG(n),1);
    end
    F = ktensor(U);
    F = arrange(F);
    
elseif isfloat(F)
    terms = F;
    U = cell(1,nd);
    for n = 1:nd
        U{n} = matrandnorm(sizeG(n),terms);
    end
    F = ktensor(U);
    F = arrange(F);
    
else
    F = arrange(F);
end

%%% documentation %%%
if debugging == 1
    F_cell{1,4} = {F};
end
%%% documentation %%%

old_err = norm(SRMultV(A,F)-G)/norA;

reverseStr = '';
addStr = '';
msg = '';

stopforloop = 0;
useStop = 1;
e_count = 2;
e_list(1) = 1;

if useStop
    FS = stoploop({'Exit execution at current iteration?', 'Stop'}) ;
end

[AtA, AtG] = prepareAG_4_als_sys(A, G);

for iter = 1:tol_it
    
    %%%%%% Debugging %%%%%%
    if length(size(F)) == 0 %Set = 2 for seeing 2D-solutions
        sol = double(F)';
        %[xx,yy] = meshgrid(x1,x2);
        %surf(xx,yy,sol,'EdgeColor','none');
        figure(6)
        %surf(sol,'EdgeColor','none');
        imagesc(sol);
        xlabel('x');ylabel('y');zlabel('u');
        if iter ~= 1
            title(['Solution, time step:', num2str(time_step(iter-1))]);
        end
        pause(0.0001)
    end
    %%%%%% Debugging %%%%%%
    
    % Display progress
    if verbose
        msg = sprintf('Iteration: %d (%d), error=%2.9f (%2.9f), rank(F)=%d\n', iter, tol_it, old_err, e, ncomponents(F));
        fprintf([reverseStr, msg]);
        reverseStr = repmat(sprintf('\b'), 1, length(msg));
    end
    
    step_time = tic;
    [Fn, status, F_cell_onestep, B_cell_onestep, b_cell_onestep] = als_onestep_sys(AtA,AtG,F,alpha,debugging);
    time_step(iter) = toc(step_time);
    
    %%% documentation %%%
    if debugging == 1
        F_cell{iter,1} = F_cell_onestep;
        B_cell{iter,1} = B_cell_onestep;
        b_cell{iter,1} = b_cell_onestep;
    end
    %%% documentation %%%
    
    %%% Variant %%%
    % incooporate F in G and restart
    if status == 0 || osc > max_osc || ncomponents(F) > max_it_rank
        
        restart = [restart iter];
        
        % reset oscillations
        osc = 0;
        
        % save F
        if isempty(F_saved)
            F_saved = F;
        else
            F_saved = F+F_saved;
            %save('F_saved','F_saved') %backup if something goes wrong
        end    
        
        F_saved = arrange(F_saved);
        if abs(F_saved.lambda(end)/F_saved.lambda(1)) < w_tol
            stopforloop = 1;
        end
        
        % incooporate F in G
        G = G-SRMultV(A,F);
        addStr = repmat(sprintf(' '), 1, length(msg));
        fprintf(addStr);
        [AtA, AtG] = prepareAG_4_als_sys(A, G);
        
        % create new F
        for n = 1:nd
            U{n} = matrandnorm(sizeG(n),1);
        end
	    F = ktensor(U);
        F = arrange(F);
        
        % precondition new F
        count = 0;
        err_newF = 1;
        err_oldF = 2;
        while count < newcond_it_tol && (abs(err_newF - err_oldF)/err_oldF) > newcond_r_tol
            [F] = als_onestep_sys(AtA,AtG,F,alpha,debugging);
            err_oldF = err_newF;
            err_newF = F.lambda; %% TODO some error here for 2d heat
            count = count + 1;
        end
        
    else
        F = Fn;
    end
    %%% Variant %%%
    
    F = arrange(F);
    Fcond(iter) = norm(F.lambda)/norm(F);
    err(iter) = norm(SRMultV(A,F)-G)/norA;
    %err(iter) = norm(SRMultV(A,F)-G);
    
    if err(iter) <= e
        break;
    end
    
    %if( ncomponents(F) >= tol_rank )
    %    disp('Maximum rank reached. Quitting...');
    %    maxrank = 1;
    %    break;
    %end
    
    %%% Variant %%%
    if err(iter)-old_err > 0 % don't want
        osc = osc+1;
    end
    %%% Variant %%%
    
    if abs(err(iter) - old_err)/old_err < r_tol
        clear nF U
        
        %%% Variant %%%
        % commented for variant:
        %if( ncomponents(F)+1 > tol_rank )
        %    disp('Maximum rank reached. Quitting...');
        %    maxrank = 1;
        %    break;
        %end
        %%% Variant %%%
        
        e_list(e_count) = iter;
        e_count = e_count + 1;
        
        % debugging:
        %fprintf('increased rank on iteration %i\n',iter);
        addStr = repmat(sprintf(' '), 1, length(msg));
        fprintf(addStr);
        
        for n = 1:nd
            U{n} = matrandnorm(sizeG(n),1);
        end
        nF = ktensor(U);
        
        % Precondition the new rank 1 tensor
        count = 1;
        err_newF = 1;
        err_oldF = 2;
        
        % debugging:
        %fprintf('Conditioning new term. Error: %f\n', norm(G-SRMultV(A,F)));
        
        clear F_cell_precond B_cell_precond b_cell_precond
        
        [AtA2, AtG2] = prepareAG_4_als_sys(A, G-SRMultV(A,F));
        
        while count < newcond_it_tol && (abs(err_newF - err_oldF)/err_oldF) > newcond_r_tol
            
            [nF, status, F_cell_onestep, B_cell_onestep, b_cell_onestep] = als_onestep_sys(AtA2,AtG2,nF,alpha,debugging);
            err_oldF = err_newF;
            err_newF = nF.lambda;
            
            %%% documentation %%%
            if debugging == 1
                if count == 1
                    F_cell_precond = F_cell_onestep;
                    B_cell_precond = B_cell_onestep;
                    b_cell_precond = b_cell_onestep;
                else
                    F_cell_precond = [F_cell_precond, F_cell_onestep];
                    B_cell_precond = [B_cell_precond, B_cell_onestep];
                    b_cell_precond = [b_cell_precond, b_cell_onestep];
                end
            end
            %%% documentation %%%
            
            count = count + 1;
            
        end
        
        %%% documenation %%%
        if debugging == 1
            F_cell{iter,2} = F_cell_precond;
            B_cell{iter,2} = B_cell_precond;
            b_cell{iter,2} = b_cell_precond;
        end
        %%% documentation %%%
        
        F = arrange(F + nF);
        
        %%% documentation %%%
        if debugging == 1
            F_cell{iter,3} = {F};
        end
        %%% documentation %%%
        
        % debugging
        %fprintf('Conditioning complete. Error: %f, count:%d\n', norm(G-SRMultV(A,F)), count);
        
    end
    old_err = err(iter);
    
    %Check quit option
    if useStop
        if FS.Stop()
            break;
        end
    end
    
    if stopforloop
        break;
    end
end

if iter == tol_it
    maxit = 1;
end

if useStop
    FS.Clear() ;  % Clear up the box
    clear FS ;    % this structure has no use anymore
end

if ~illcond && verbose
    msg = sprintf('Iteration: %d (%d), error=%2.9f (%2.9f), rank(F)=%d\n', iter, tol_it, err(iter), e, ncomponents(F));
    fprintf([reverseStr, msg]);
end

%%% Variant %%%
% Obtain solution combining F with saved tensor terms
if isempty(F_saved) == 0
    F = F_saved+F;
end
F = arrange(F);
%%% Variant %%%

end