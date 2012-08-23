function [y]=multifuncrs(X, funs, eps, varargin)
% Cross approximation of a function of _several_ TT-tensors.
%   [Y]=MULTIFUNCRS(X,FUNS,EPS, VARARGIN)
%   Computes approximation to the function FUNS(X{1},...,X{N}) with accuracy EPS
%   X should be a cell array of nx TT-tensors of equal sizes.
%   The function FUNS should receive a 2d array V of sizes I x N, where the
%   first dimension stays for the reduced set of spatial indices, and  the
%   second is the enumerator of X. For example, FUNS=@(x)(x(:,1)+x(:,2)).
%
%   Options are provided in form
%   'PropertyName1',PropertyValue1,'PropertyName2',PropertyValue2 and so
%   on. The parameters are set to default (in brackets in the following)
%   The list of option names and default values are:
%       o y0 - initial approximation [random rank-2 tensor]
%       o nswp - maximal number of DMRG sweeps [10]
%       o verb - verbosity level, 0-silent, 1-sweep info, 2-block info [1]
%       o kickrank - the rank-increasing parameter [5]
%
%   The method is based on the alternating approximation, with 
%   the one-block enrichment via KICKRANK random vectors.
%
% TT-Toolbox 2.2, 2009-2012
%
%This is TT Toolbox, written by Ivan Oseledets et al.
%Institute of Numerical Mathematics, Moscow, Russia
%webpage: http://spring.inm.ras.ru/osel
%
%For all questions, bugs and suggestions please mail
%ivan.oseledets@gmail.com
%---------------------------

nswp = 10;
kickrank = 5;
y = [];
verb = 1;
% kicktype = 'rand';
kicktype = 'amr-two';
% pcatype = 'svd';
pcatype = 'uchol';

for i=1:2:length(varargin)-1
    switch lower(varargin{i})
        case 'nswp'
            nswp=varargin{i+1};
        case 'y0'
            y=varargin{i+1};
        case 'kickrank'
            kickrank=varargin{i+1};
        case 'verb'
            verb=varargin{i+1};
        case 'kicktype'
            kicktype=varargin{i+1};            
        case 'pcatype'
            pcatype=varargin{i+1};
            
        otherwise
            error('Unrecognized option: %s\n',varargin{i});
    end
end

nx = numel(X);
d = X{1}.d;
n = X{1}.n;
rx = zeros(d+1,nx);
crX = cell(d,nx);
for i=1:nx
    rx(:,i) = X{i}.r;
    crX(:,i) = core2cell(X{i});
end;

if (isempty(y))
    y = tt_rand(n, d, 2);
end;
ry = y.r;
cry = core2cell(y);

Ry = cell(d+1,1);
Ry{1} = 1; Ry{d+1}=1;
Rx = cell(d+1,nx);
for i=1:nx
    Rx{1,i}=1; Rx{d+1,i}=1;
end;

block_order = [+(d), -(d)];

% Orth
for i=d:-1:2
    cr = cry{i};
    cr = reshape(cr, ry(i), n(i)*ry(i+1));
    [cr, rv]=qr(cr.', 0);    
    cr2 = cry{i-1};
    cr2 = reshape(cr2, ry(i-1)*n(i-1), ry(i));
    cr2 = cr2*(rv.');
    ry(i) = size(cr, 2);
    cr = reshape(cr.', ry(i), n(i), ry(i+1));
    cry{i-1} = reshape(cr2, ry(i-1), n(i-1), ry(i));
    cry{i} = cr;

    % Interface matrix for Y
    Ry{i} = reshape(cr, ry(i)*n(i), ry(i+1))*Ry{i+1};
    Ry{i} = reshape(Ry{i}, ry(i), n(i)*ry(i+1));
    curind = maxvol2(Ry{i}.');
    Ry{i} = Ry{i}(:, curind);
    % Interface matrices for X
    for j=1:nx
        Rx{i,j} = reshape(crX{i,j}, rx(i,j)*n(i), rx(i+1,j));
        Rx{i,j} = Rx{i,j}*Rx{i+1,j};
        Rx{i,j} = reshape(Rx{i,j}, rx(i,j), n(i)*ry(i+1));
        Rx{i,j} = Rx{i,j}(:, curind);
    end;
end;


last_sweep = false;
swp = 1;
i = 1;

% dy_old = ones(d,1);
dy = zeros(d,1);
max_dy = 0;
% For extra-rank addition
% dpows = ones(d,1)*min_dpow;
% dranks = zeros(d,1);

cur_order = block_order;
order_index = 1;
dir = sign(cur_order(order_index));

% DMRG sweeps
while (swp<=nswp)
    
    oldy = reshape(cry{i}, ry(i)*n(i)*ry(i+1), 1);
    
    if (~last_sweep)
        % Compute the X superblocks
        curbl = zeros(ry(i)*n(i)*ry(i+1), nx);
        for j=1:nx
            cr = reshape(crX{i,j}, rx(i,j), n(i)*rx(i+1,j));
            cr = Rx{i,j}*cr;
            cr = reshape(cr, ry(i)*n(i), rx(i+1,j));
            cr = cr*Rx{i+1,j};
            curbl(:,j) = cr(:);
        end;
        % Call the function
        newy = funs(curbl);
        % Multiply with inverted Ry
        newy = reshape(newy, ry(i)*n(i), ry(i+1));
        newy = newy / (Ry{i+1});
        newy = reshape(newy, ry(i), n(i)*ry(i+1));
        newy = (Ry{i}) \ newy;
    else
        newy = oldy;
    end;

    dy(i) = norm(newy(:)-oldy)/norm(newy(:));
    max_dy = max(max_dy, dy(i));

    % Truncation
    if (dir>0) % left-to-right
        newy = reshape(newy, ry(i)*n(i), ry(i+1));
    else
        newy = reshape(newy, ry(i), n(i)*ry(i+1));
    end;

    if (kickrank>=0)
        [u,s,v]=svd(newy, 'econ');
        s = diag(s);
        if (last_sweep)
            r = my_chop2(s, eps/sqrt(d)*norm(s));
        else            
            % Truncate taking into account the (r+1) overhead in the cross
            cums = (s.*(2:numel(s)+1)').^2;
            cums = cumsum(cums(end:-1:1));
            cums = cums(end:-1:1)./cums(1);
            r = find(cums<(eps^2/d), 1);
            if (isempty(r))
                r = numel(s);
            end;
        end;
        r = min(r, numel(s));
    else
        if (dir>0)
            [u,v]=qr(newy, 0);
            v=v';
            r = size(u,2);
            s = ones(r,1);
        else
            [v,u]=qr(newy.', 0);
            v=conj(v);
            u=u.';
            r = size(u,2);
            s = ones(r,1);
        end;
    end;

    if (verb>1)
    	fprintf('=funcrs4=   block %d{%d}, dy: %3.3e, r: %d\n', i, dir, dy(i), r);
    end;    
    
    % Kicks and interfaces
    if (dir>0)&&(i<d) % left-to-right, kickrank, etc
        u = u(:,1:r);
        v = v(:,1:r)*diag(s(1:r));

        % kick
        radd = 0; rv = 1;
        if (~last_sweep)&&(kickrank>0)
            if (strcmp(kicktype, 'amr-two'))
                % AMR(two)-like kick. See also the M.Sc.Thesis by D. Zheltkov.
                % The left indices are nested, but the right are chosen
                % randomly. In Zheltkov's work, from all possible n^(d-k)
                % values. However, in the functional-cross it would result
                % in a d^2 complexity. Here, I use only the neighbouring
                % core for randomization. Additionally, the actual kick is
                % performed via the Z=PCA(supercore), since otherwise the
                % rank grows too high.
                
                % Compute the X superblocks
                ind2 = unique(ceil(rand(ry(i+1), 1)*(ry(i+2)*n(i+1))));
                rkick = numel(ind2);
                curbl = zeros(ry(i)*n(i)*rkick, nx);
                for j=1:nx
                    cr1 = reshape(crX{i,j}, rx(i,j), n(i)*rx(i+1,j));
                    cr1 = Rx{i,j}*cr1;
                    cr1 = reshape(cr1, ry(i)*n(i), rx(i+1,j));
                    cr2 = reshape(crX{i+1,j}, rx(i+1,j)*n(i+1), rx(i+2,j));                    
                    cr2 = cr2*Rx{i+2,j}; % now its size rx
                    cr2 = reshape(cr2, rx(i+1,j), n(i+1)*ry(i+2));
                    cr2 = cr2(:, ind2);
                    curbl(:,j) = reshape(cr1*cr2, ry(i)*n(i)*rkick, 1);
                end;
                % Call the function
                uk = funs(curbl);
                uk = reshape(uk, ry(i), n(i)*rkick);
                uk = Ry{i} \ uk;
                uk = reshape(uk, ry(i)*n(i), rkick);
                if (strcmp(pcatype, 'svd'))
                    [uk,sk,vk]=svd(uk, 'econ');
                    uk = uk(:,1:min(kickrank, size(uk,2)));
                else
                    uk = uchol(uk.', kickrank+1);
                    uk = uk(:,end:-1:max(end-kickrank+1,1));
                end;
            else
                uk = rand(ry(i)*n(i), kickrank);
            end;
            [u,rv]=qr([u,uk], 0);
            radd = size(uk,2);
        end;
        v = [v, zeros(ry(i+1), radd)];
        v = rv*(v');
        r = size(u,2);

        cr2 = cry{i+1};
        cr2 = reshape(cr2, ry(i+1), n(i+1)*ry(i+2));
        v = v*cr2; % size r+radd, n2, r3

        ry(i+1) = r;

        u = reshape(u, ry(i), n(i), r);
        v = reshape(v, r, n(i+1), ry(i+2));

        % Stuff back
        cry{i} = u;
        cry{i+1} = v;
        
        % Recompute left interface matrices
        % Interface matrix for Y
        Ry{i+1} = Ry{i}*reshape(u, ry(i), n(i)*ry(i+1));
        Ry{i+1} = reshape(Ry{i+1}, ry(i)*n(i), ry(i+1));
        curind = maxvol2(Ry{i+1});
        Ry{i+1} = Ry{i+1}(curind, :);
        % Interface matrices for X
        for j=1:nx
            Rx{i+1,j} = reshape(crX{i,j}, rx(i,j), n(i)*rx(i+1,j));
            Rx{i+1,j} = Rx{i,j}*Rx{i+1,j};
            Rx{i+1,j} = reshape(Rx{i+1,j}, ry(i)*n(i), rx(i+1,j));
            Rx{i+1,j} = Rx{i+1,j}(curind, :);
        end;
    elseif (dir<0)&&(i>1) % right-to-left
        u = u(:,1:r)*diag(s(1:r));
        v = conj(v(:,1:r));
        % kick
        radd = 0; rv = 1;
        if (~last_sweep)&&(kickrank>0)
            if (strcmp(kicktype, 'amr-two'))
                % Compute the X superblocks
                ind2 = unique(ceil(rand(ry(i), 1)*(ry(i-1)*n(i-1))));
                rkick = numel(ind2);
                curbl = zeros(rkick*n(i)*ry(i+1), nx);
                for j=1:nx
                    cr1 = reshape(crX{i,j}, rx(i,j)*n(i), rx(i+1,j));
                    cr1 = cr1*Rx{i+1,j};
                    cr1 = reshape(cr1, rx(i,j), n(i)*ry(i+1));
                    cr2 = reshape(crX{i-1,j}, rx(i-1,j), n(i-1)*rx(i,j));                    
                    cr2 = Rx{i-1,j}*cr2; % now its size rx
                    cr2 = reshape(cr2, ry(i-1)*n(i-1), rx(i,j));
                    cr2 = cr2(ind2, :);
                    curbl(:,j) = reshape(cr2*cr1, rkick*n(i)*ry(i+1), 1);
                end;
                % Call the function
                uk = funs(curbl);
                uk = reshape(uk, rkick*n(i), ry(i+1));
                uk = uk / Ry{i+1};
                uk = reshape(uk, rkick, n(i)*ry(i+1));
                if (strcmp(pcatype, 'svd'))
                    [vk,sk,uk]=svd(uk, 'econ');
                    uk = uk(:,1:min(kickrank, size(uk,2)));
                else
                    uk = uchol(uk, kickrank+1);
                    uk = uk(:,end:-1:max(end-kickrank+1,1));
                end;                
            else
                uk = rand(n(i)*ry(i+1), kickrank);
            end;            
%             uk = rand(n(i)*ry(i+1), kickrank);
            [v,rv]=qr([v,uk], 0);
            radd = size(uk,2);
        end;
        
        u = [u, zeros(ry(i), radd)];
        u = u*(rv.');
        cr2 = cry{i-1};
        cr2 = reshape(cr2, ry(i-1)*n(i-1), ry(i));
        u = cr2*u;
        
        r = size(v,2);
        
        u = reshape(u, ry(i-1), n(i-1), r);
        v = reshape(v.', r, n(i), ry(i+1));
                
        % Stuff back
        ry(i) = r;
        cry{i-1} = u;
        cry{i} = v;
        
        % Recompute left interface matrices
        % Interface matrix for Y
        Ry{i} = reshape(v, ry(i)*n(i), ry(i+1))*Ry{i+1};
        Ry{i} = reshape(Ry{i}, ry(i), n(i)*ry(i+1));
        curind = maxvol2(Ry{i}.');
        Ry{i} = Ry{i}(:, curind);
        % Interface matrices for X
        for j=1:nx
            Rx{i,j} = reshape(crX{i,j}, rx(i,j)*n(i), rx(i+1,j));
            Rx{i,j} = Rx{i,j}*Rx{i+1,j};
            Rx{i,j} = reshape(Rx{i,j}, rx(i,j), n(i)*ry(i+1));
            Rx{i,j} = Rx{i,j}(:, curind);
        end;
    elseif ((dir>0)&&(i==d))||((dir<0)&&(i==1))
        % Just stuff back the last core
        newy = u(:,1:r)*diag(s(1:r))*(v(:,1:r)');
        newy = reshape(newy, ry(i), n(i), ry(i+1));
        cry{i} = newy;
    end;
    
    
    i = i+dir;
    % Reversing, residue check, etc
    cur_order(order_index) = cur_order(order_index) - dir;
    % New direction
    if (cur_order(order_index)==0)
        order_index = order_index+1;

        if (verb>0)
            fprintf('=funcrs4= sweep %d{%d}, max_dy: %3.3e, erank: %g\n', swp, order_index-1, max_dy, sqrt(ry(1:d)'*(n.*ry(2:d+1))/sum(n)));
        end;

        if (last_sweep)
            break;
        end;

        if (max_dy<eps)
            last_sweep=true;
            kickrank=0;
        end;

        if (order_index>numel(cur_order)) % New global sweep
            cur_order = block_order;
            order_index = 1;
            %residue
            if (last_sweep)
                cur_order = d-1;
            end;

            max_dy = 0;
            swp = swp+1;
        end;

        dir = sign(cur_order(order_index));
        i = i+dir;
    end;
end

y = cell2core(y, cry);

end
