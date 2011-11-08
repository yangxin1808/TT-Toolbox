function [tt2]=tt_reshape(tt1,sz,eps)
%[TT1]=TT_RESHAPE(TT,SZ)
%[TT1]=TT_RESHAPE(TT,SZ,EPS)
%Reshapes TT-tensor into a new one, with dimensions specified by SZ
%Optionally, accuracy EPS can be specified, default is 1e-14
%Works in TT2

d1=tt1.d;
n1=tt1.n;
d2 = numel(sz);
if ( prod(sz) ~= prod(n1) )
 error('Reshape: incorrect sizes \n');
end

if (nargin<3)||(isempty(eps))
    eps = 1e-14;
end;

% if (d2>d1) % We have to split some cores -> perform QRs
    for i=d1:-1:2
%         fprintf('initial QR %d -> %d ...', i, i-1);    
%         cr = core(tt1,i);
        cr = tt1{i};
        r1 = size(cr,1); r2 = size(cr,3);
        cr = reshape(cr, r1, n1(i)*r2);
        [cr,rv]=qr(cr.', 0); % Size n*r2, r1new - r1nwe,r1
        cr0 = tt1{i-1};
%         cr0 = core(tt1, i-1);
        r0 = size(cr0, 1);
        cr0 = reshape(cr0, r0*n1(i-1), r1);
        cr0 = cr0*(rv.'); % r0*n0, r1new
        r1 = size(cr,2);        
        cr0 = reshape(cr0, r0, n1(i-1), r1);
        cr = reshape(cr.', r1, n1(i), r2);
        tt1{i} = cr;
        tt1{i-1} = cr0;
%         fprintf('done\n');    
    end;
% end;

r1 = tt1.r;
r2 = ones(d2+1,1);
    
i1 = 1; % Working index in tt1
i2 = 1; % Working index in tt2
core2 = zeros(0,1);
last_ps2 = 1;
curcr2 = 1;
restn2 = sz;
n2 = ones(d2,1);
while (i1<=d1)    
    if (restn2(i2)>=n1(i1)) % We can convolve core1 (or its part) to core2        
        curcr1 = tt1{i1};
        if (mod(restn2(i2), n1(i1))==0)           
            % Convolve the whole core1 to core2            
            %         fprintf('merge core1 %d to core2 %d ...', i1, i2);
            if (i1<d1)  % &&(d2>d1) % QR to the next core - for safety
                %             fprintf('QR core1 %d to core1 %d ...', i1, i1+1);
                curcr1 = reshape(curcr1, r1(i1)*n1(i1), r1(i1+1));
                [curcr1, rv]=qr(curcr1, 0);
                curcr12 = tt1{i1+1};
                curcr12 = reshape(curcr12, r1(i1+1), n1(i1+1)*r1(i1+2));
                curcr12 = rv*curcr12;
                r1(i1+1)=size(curcr12, 1);
                tt1{i1+1} = reshape(curcr12, r1(i1+1), n1(i1+1), r1(i1+2));
                %             fprintf('done\n');
            end;
            
            curcr1 = reshape(curcr1, r1(i1), n1(i1)*r1(i1+1));
            curcr2 = curcr2*curcr1; % size r21*nold, dn*r22
            r2(i2+1)=r1(i1+1);
            % Update the sizes of tt2
            n2(i2)=n2(i2)*n1(i1);
            restn2(i2)=restn2(i2)/n1(i1);
            curcr2 = reshape(curcr2, r2(i2)*n2(i2), r2(i2+1));
            %         fprintf('done\n');
            i1 = i1+1; % current core1 is over
        else
            % Only GCD is available - we have to split
            n12 = gcd(restn2(i2), n1(i1));
            curcr1 = reshape(curcr1, r1(i1)*n12, (n1(i1)/n12)*r1(i1+1));
            [u,s,v]=svd(curcr1, 'econ');
            s = diag(s);
            r = my_chop2(s, eps*norm(s)/sqrt(d2-1));
            u = u(:,1:r);
            v = conj(v(:,1:r))*diag(s(1:r));
            u = reshape(u, r1(i1), n12*r);
            curcr2 = curcr2*u; % size r21*nold, dn*r22
            r2(i2+1)=r;
            % Update the sizes of tt2
            n2(i2)=n2(i2)*n12;
            restn2(i2)=restn2(i2)/n2;
            curcr2 = reshape(curcr2, r2(i2)*n2(i2), r2(i2+1));
            r1(i1) = r;
            % and tt1
            n1(i1) = n1(i1)/n12;
            curcr1 = reshape(v.', r1(i1), n1(i1), r1(i1+1));
            tt1{i1} = curcr1;
        end;
    else % We have to split a piece of the nest core(s!)
        if (mod(n1(i1), restn2(i2))==0)
            % That's nice, we can just split i1-th core
            curcr1 = tt1{i1};
            curcr1 = reshape(curcr1, r1(i1)*restn2(i2), (n1(i1)/restn2(i2))*r1(i1+1));
            [u,s,v]=svd(curcr1, 'econ');
            s = diag(s);
            r = my_chop2(s, eps*norm(s)/sqrt(d2-1));
            u = u(:,1:r);
            v = conj(v(:,1:r))*diag(s(1:r));
            u = reshape(u, r1(i1), restn2(i2)*r);
            curcr2 = curcr2*u; % size r21*n2, restn2*r
            % Update the sizes
            n2(i2)=n2(i2)*restn2(i2);
            n1(i1) = n1(i1)/restn2(i2);
            restn2(i2)=1;
            curcr2 = reshape(curcr2, r2(i2), n2(i2), r);
            r2(i2+1) = r;
            curcr1 = reshape(v.', r, n1(i1), r1(i1+1));
            r1(i1) = r;
            tt1{i1}=curcr1;
        else
            % This will not be easy.
            % We have to merge tt1's cores until it will be divisible by
            % restn2. If we really need all of them - ....[censored].... =(
            i1new = i1+1;
            curcr1 = reshape(curcr1, r1(i1)*n1(i1), r1(i1+1));
%             while (mod(n1(i1), restn2(i2))~=0)&&(i1new<=d1)
                cr1new = tt1{i1new};
                cr1new = reshape(cr1new, r1(i1new), n1(i1new)*r1(i1new+1));
                curcr1 = curcr1*cr1new; % size r1(i1)*n1(i1), n1new*r1new
                n1(i1) = n1(i1)*n1(i1new);
                curcr1 = reshape(curcr1, r1(i1)*n1(i1), r1(i1new+1));
                i1new = i1new+1;
%             end;
            % Reduce dimension of tt1
            tt1.n = [n1(1:i1); n1(i1new:d1)];
            tt1.r = [r1(1:i1); r1(i1new:d1+1)];
            if (i1new<=d1)
                crlast = tt1.core(tt1.ps(i1new):end);
            else
                crlast = [];
            end;
            tt1.core = [tt1.core(1:tt1.ps(i1)-1); curcr1(:); crlast];
            n1 = tt1.n;
            r1 = tt1.r;
            d1 = numel(n1);
            tt1.d = d1;
            tt1.ps = cumsum([1; r1(1:d1).*n1.*r1(2:d1+1)]);
        end;
    end;
    
    if (restn2(i2)==1) % The core of tt2 is finished
        core2(last_ps2:last_ps2+r2(i2)*n2(i2)*r2(i2+1)-1) = curcr2(:);
        last_ps2 = last_ps2 + r2(i2)*n2(i2)*r2(i2+1);
        i2 = i2+1;
        % Start new core2
        curcr2 = 1;
    end;
end;

tt2 = tt_tensor;
tt2.d = d2;
tt2.n = n2;
tt2.r = r2;
tt2.core = core2;
tt2.ps = cumsum([1; r2(1:d2).*n2.*r2(2:d2+1)]);

% tt1=tt_tensor;
% %Now we have to determine the set of elementary operations.
% %In new tensor, dimensions are either merged, or split, and this
% %'diagram' has to be derived
% i1=1;
% cr1=[];
% 
% for i=1:d
%   %Determine what to do with the first core: split or merge
%   if ( sz(i1) < n(i) ) %split
%       %Determine the number of cores to split
%       cm=cumprod(sz); 
%       ff=find(cm>n(i)); ff=ff(1); ff=ff-1;
%       spt=sz(1:ff); %These are new! dimensions
%       core=cr(ps(i):ps(i+1)-1); %Core to split
%       core=reshape(core,[r(i),spt
%   elseif ( sz(i1) == n(i) ) %do nothing
%   else %Merge
%       %Determine the number of cores to merge
%   end
% end
% if ( nargin == 2 )
%     
% elseif ( nargin == 3 )
%     
% end
%     error('Reshape function is not implemented yet');
% return
end