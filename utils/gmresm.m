function [x,flag,relres,iter,resvec] = gmresm(A,b,restart,tol,maxit,M1,M2,x,varargin)
%GMRES   Generalized Minimum Residual Method.
%   X = GMRES(A,B) attempts to solve the system of linear equations A*X = B
%   for X.  The N-by-N coefficient matrix A must be square and the right
%   hand side column vector B must have length N. This uses the unrestarted
%   method with MIN(N,10) total iterations.
%
%   X = GMRES(AFUN,B) accepts a function handle AFUN instead of the matrix
%   A. AFUN(X) accepts a vector input X and returns the matrix-vector
%   product A*X. In all of the following syntaxes, you can replace A by
%   AFUN.
%
%   X = GMRES(A,B,RESTART) restarts the method every RESTART iterations.
%   If RESTART is N or [] then GMRES uses the unrestarted method as above.
%
%   X = GMRES(A,B,RESTART,TOL) specifies the tolerance of the method.  If
%   TOL is [] then GMRES uses the default, 1e-6.
%
%   X = GMRES(A,B,RESTART,TOL,MAXIT) specifies the maximum number of outer
%   iterations. Note: the total number of iterations is RESTART*MAXIT. If
%   MAXIT is [] then GMRES uses the default, MIN(N/RESTART,10). If RESTART
%   is N or [] then the total number of iterations is MAXIT.
%
%   X = GMRES(A,B,RESTART,TOL,MAXIT,M) and
%   X = GMRES(A,B,RESTART,TOL,MAXIT,M1,M2) use preconditioner M or M=M1*M2
%   and effectively solve the system inv(M)*A*X = inv(M)*B for X. If M is
%   [] then a preconditioner is not applied.  M may be a function handle
%   returning M\X.
%
%   X = GMRES(A,B,RESTART,TOL,MAXIT,M1,M2,X0) specifies the first initial
%   guess. If X0 is [] then GMRES uses the default, an all zero vector.
%
%   [X,FLAG] = GMRES(A,B,...) also returns a convergence FLAG:
%    0 GMRES converged to the desired tolerance TOL within MAXIT iterations.
%    1 GMRES iterated MAXIT times but did not converge.
%    2 preconditioner M was ill-conditioned.
%    3 GMRES stagnated (two consecutive iterates were the same).
%
%   [X,FLAG,RELRES] = GMRES(A,B,...) also returns the relative residual
%   NORM(B-A*X)/NORM(B). If FLAG is 0, then RELRES <= TOL. Note with
%   preconditioners M1,M2, the residual is NORM(M2\(M1\(B-A*X))).
%
%   [X,FLAG,RELRES,ITER] = GMRES(A,B,...) also returns both the outer and
%   inner iteration numbers at which X was computed: 0 <= ITER(1) <= MAXIT
%   and 0 <= ITER(2) <= RESTART.
%
%   [X,FLAG,RELRES,ITER,RESVEC] = GMRES(A,B,...) also returns a vector of
%   the residual norms at each inner iteration, including NORM(B-A*X0).
%   Note with preconditioners M1,M2, the residual is NORM(M2\(M1\(B-A*X))).
%
%   Example:
%      n = 21; A = gallery('wilk',n);  b = sum(A,2);
%      tol = 1e-12;  maxit = 15; M = diag([10:-1:1 1 1:10]);
%      x = gmres(A,b,10,tol,maxit,M);
%   Or, use this matrix-vector product function
%      %-----------------------------------------------------------------%
%      function y = afun(x,n)
%      y = [0; x(1:n-1)] + [((n-1)/2:-1:0)'; (1:(n-1)/2)'].*x+[x(2:n); 0];
%      %-----------------------------------------------------------------%
%   and this preconditioner backsolve function
%      %------------------------------------------%
%      function y = mfun(r,n)
%      y = r ./ [((n-1)/2:-1:1)'; 1; (1:(n-1)/2)'];
%      %------------------------------------------%
%   as inputs to GMRES:
%      x1 = gmres(@(x)afun(x,n),b,10,tol,maxit,@(x)mfun(x,n));
%
%   Class support for inputs A,B,M1,M2,X0 and the output of AFUN:
%      float: double
%
%   See also BICG, BICGSTAB, BICGSTABL, CGS, LSQR, MINRES, PCG, QMR, SYMMLQ,
%   TFQMR, ILU, FUNCTION_HANDLE.

%   References
%   H.F. Walker, "Implementation of the GMRES Method Using Householder
%   Transformations", SIAM J. Sci. Comp. Vol 9. No 1. January 1988.

%   Copyright 1984-2013 The MathWorks, Inc.

if (nargin < 2)
    error(message('MATLAB:gmres:NumInputs'));
end

% Determine whether A is a matrix or a function.
[atype,afun,afcnstr] = iterchk2(A);
if strcmp(atype,'matrix')
    % Check matrix and right hand side vector inputs have appropriate sizes
    [m,n] = size(A);
    if (m ~= n)
        error(message('MATLAB:gmres:SquareMatrix'));
    end
    if ~isequal(size(b(:,1)),[m,1])
        error(message('MATLAB:gmres:VectorSize', m));
    end
else
    m = size(b,1);
    n = m;
    if ~iscolumn(b)
        error(message('MATLAB:gmres:Vector'));
    end
end

k = size(b, 2); % number of columns

% Assign default values to unspecified parameters
if (nargin < 3) || isempty(restart) || (restart == n)
    restarted = false;
else
    restarted = true;
end
if (nargin < 4) || isempty(tol)
    tol = 1e-6;
end
warned = 0;
if tol < eps
    warning(message('MATLAB:gmres:tooSmallTolerance'));
    warned = 1;
    tol = eps;
elseif tol >= 1
    warning(message('MATLAB:gmres:tooBigTolerance'));
    warned = 1;
    tol = 1-eps;
end
if (nargin < 5) || isempty(maxit)
    if restarted
        maxit = min(ceil(n/restart),10);
    else
        maxit = min(n,10);
    end
end

if restarted
    outer = maxit;
    if restart > n
        warning(message('MATLAB:gmres:tooManyInnerItsRestart',restart, n));
        restart = n;
    end
    inner = restart;
else
    outer = 1;
    if maxit > n
        warning(message('MATLAB:gmres:tooManyInnerItsMaxit',maxit, n));
        maxit = n;
    end
    inner = maxit;
end

% Check for all zero right hand side vector => all zero solution
n2b = sqrt(sum(b.^2));                   % Norm of rhs vector, b
if (max(n2b) == 0)                    % if    rhs vector is all zeros
    x = zeros(n,k);              % then  solution is all zeros
    flag = 0;                    % a valid solution has been obtained
    relres = 0;                  % the relative residual is actually 0/0
    iter = [0 0];                % no iterations need be performed
    resvec = 0;                  % resvec(1) = norm(b-A*x) = norm(0)
    if (nargout < 2)
        itermsg2('gmres',tol,maxit,0,flag,iter,NaN);
    end
    return
end

if ((nargin >= 6) && ~isempty(M1))
    existM1 = 1;
    [m1type,m1fun,m1fcnstr] = iterchk2(M1);
    if strcmp(m1type,'matrix')
        if ~isequal(size(M1),[m,m])
            error(message('MATLAB:gmres:PreConditioner1Size', m));
        end
    end
else
    existM1 = 0;
    m1type = 'matrix';
end

if ((nargin >= 7) && ~isempty(M2))
    existM2 = 1;
    [m2type,m2fun,m2fcnstr] = iterchk2(M2);
    if strcmp(m2type,'matrix')
        if ~isequal(size(M2),[m,m])
            error(message('MATLAB:gmres:PreConditioner2Size', m));
        end
    end
else
    existM2 = 0;
    m2type = 'matrix';
end

if ((nargin >= 8) && ~isempty(x))
    if ~isequal(size(x),[n,k])
        error(message('MATLAB:gmres:XoSize', n));
    end
else
    x = zeros(n,k);
end

if ((nargin > 8) && strcmp(atype,'matrix') && ...
        strcmp(m1type,'matrix') && strcmp(m2type,'matrix'))
    error(message('MATLAB:gmres:TooManyInputs'));
end

% Set up for the method
flag = 1;
xmin = x;                        % Iterate which has minimal residual so far
imin = zeros(1, k);                        % "Outer" iteration at which xmin was computed
jmin = zeros(1, k);                        % "Inner" iteration at which xmin was computed
tolb = tol * n2b;                % Relative tolerance
evalxm = 0;
stag = 0;
moresteps = 0;
maxmsteps = min([floor(n/50),5,n-maxit]);
maxstagsteps = 3;
minupdated = false(1, k);

x0iszero = (sqrt(sum(x.^2)) == 0);
r = b - customAfun(afun, atype, afcnstr, x, varargin{:});
normr = sqrt(sum(r.^2));                 % Norm of initial residual
if (all(normr <= tolb))               % Initial guess is a good enough solution
    flag = 0;
    relres = normr ./ n2b;
    iter = [0 0];
    resvec = normr;
    if (nargout < 2)
        itermsg2('gmres',tol,maxit,[0 0],flag,iter,relres);
    end
    return
end
minv_b = b;

if existM1
    r = iterapp2('mldivide',m1fun,m1type,m1fcnstr,r,varargin{:});
    if ~all(x0iszero)
        minv_b = iterapp2('mldivide',m1fun,m1type,m1fcnstr,b,varargin{:});
    else
        minv_b = r;
    end
    if ~all(isfinite(r(:))) || ~all(isfinite(minv_b(:)))
        flag = 2;
        x = xmin;
        relres = normr ./ n2b;
        iter = [0 0];
        resvec = normr;
        return
    end
end

if existM2
    r = iterapp2('mldivide',m2fun,m2type,m2fcnstr,r,varargin{:});
    if ~all(x0iszero)
        minv_b = iterapp2('mldivide',m2fun,m2type,m2fcnstr,minv_b,varargin{:});
    else
        minv_b = r;
    end
    if ~all(isfinite(r(:))) || ~all(isfinite(minv_b(:)))
        flag = 2;
        x = xmin;
        relres = normr ./ n2b;
        iter = [0 0];
        resvec = normr;
        return
    end
end

normr = sqrt(sum(r.^2));                 % norm of the preconditioned residual
n2minv_b = sqrt(sum(minv_b.^2));         % norm of the preconditioned rhs
clear minv_b;
tolb = tol * n2minv_b;
if (all(normr <= tolb))               % Initial guess is a good enough solution
    flag = 0;
    relres = normr ./ n2minv_b;
    iter = [0 0];
    resvec = n2minv_b;
    if (nargout < 2)
        itermsg2('gmres',tol,maxit,[0 0],flag,iter,relres);
    end
    return
end

resvec = zeros(inner*outer+1,k);  % Preallocate vector for norm of residuals
resvec(1, :) = normr;                % resvec(1) = norm(b-A*x0)
normrmin = normr;                 % Norm of residual from xmin

%  Preallocate J to hold the Given's rotation constants.
J = zeros(2,k,inner);

U = zeros(n,k,inner);
R = zeros(inner,inner,k);
w = zeros(inner+1,k);

for outiter = 1 : outer
    %  Construct u for Householder reflector.
    %  u = r + sign(r(1))*||r||*e1
    u = r;
    normr = sqrt(sum(r.^2));
    beta = scalarsign(r(1,:)).*normr;
    u(1,:) = u(1,:) + beta;
    u = bsxfun(@times, u, 1./sqrt(sum(u.^2)));
    
    U(:,:,1) = u;
    
    %  Apply Householder projection to r.
    %  w = r - 2*u*u'*r;
    w(1,:) = -beta;
    
    for initer = 1 : inner
        %  Form P1*P2*P3...Pj*ej.
        %  v = Pj*ej = ej - 2*u*u'*ej
        v = bsxfun(@times, u, -2*u(initer, :));
        v(initer, :) = v(initer, :) + 1;
        %  v = P1*P2*...Pjm1*(Pj*ej)
        for h = (initer-1):-1:1
            v = v - bsxfun(@times, U(:,:,h), 2*sum(U(:,:,h) .* v));
        end
        %  Explicitly normalize v to reduce the effects of round-off.
        v = bsxfun(@times, v, 1./sqrt(sum(v.^2)));
        
        %  Apply A to v.
        v = customAfun(afun, atype, afcnstr, v, varargin{:});
        %  Apply Preconditioner.
        if existM1
            v = iterapp2('mldivide',m1fun,m1type,m1fcnstr,v,varargin{:});
            if ~all(isfinite(v(:)))
                flag = 2;
                break
            end
        end
        
        if existM2
            v = iterapp2('mldivide',m2fun,m2type,m2fcnstr,v,varargin{:});
            if ~all(isfinite(v(:)))
                flag = 2;
                break
            end
        end
        %  Form Pj*Pj-1*...P1*Av.
        for h = 1:initer
            v = v - bsxfun(@times, U(:,:,h), 2*sum(U(:,:,h) .* v));
        end
        
        %  Determine Pj+1.
        if (initer ~= size(v, 1))
            %  Construct u for Householder reflector Pj+1.
            u = [zeros(initer,k); v(initer+1:end,:)];
            alpha = sqrt(sum(u.^2));
            alphaisnot0 = find(alpha ~= 0);
            alpha(alphaisnot0) = scalarsign(v(initer+1, alphaisnot0)).*alpha(alphaisnot0);
            %  u = v(initer+1:end) +
            %        sign(v(initer+1))*||v(initer+1:end)||*e_{initer+1)
            u(initer+1, :) = u(initer+1, :) + alpha;
            u(:, alphaisnot0) = bsxfun(@times, u(:, alphaisnot0), 1./sqrt(sum(u(:, alphaisnot0).^2)));
            U(:,alphaisnot0,initer+1) = u(:, alphaisnot0);
            
            %  Apply Pj+1 to v.
            %  v = v - 2*u*(u'*v);
            v(initer+2:end,alphaisnot0) = 0;
            v(initer+1,alphaisnot0) = -alpha(alphaisnot0);
        end
        
        %  Apply Given's rotations to the newly formed v.
        for colJ = 1:initer-1
            tmpv = v(colJ, :);
            v(colJ, :)   = conj(J(1,:,colJ)).*v(colJ, :) + conj(J(2,:,colJ)).*v(colJ+1, :);
            v(colJ+1, :) = -J(2,:,colJ).*tmpv + J(1,:,colJ).*v(colJ+1, :);
        end
        
        %  Compute Given's rotation Jm.
        if ~(initer==size(v, 1))
            rho = sqrt(sum(v(initer:initer+1, :).^2));
            J(:,:,initer) = bsxfun(@times, v(initer:initer+1, :), 1./rho);
            w(initer+1, :) = -J(2,:,initer).*w(initer, :);
            w(initer, :) = conj(J(1,:,initer)).*w(initer, :);
            v(initer, :) = rho;
            v(initer+1, :) = 0;
        end
        
        for i = 1 : k
            R(:,initer,i) = v(1:inner, i);
        end
        
        normr = abs(w(initer+1, :));
        resvec((outiter-1)*inner+initer+1, :) = normr;
        normr_act = normr;
        
        if (all(normr <= tolb) || stag >= maxstagsteps || moresteps)
            if evalxm == 0
                ytmp = zeros(initer, k);
                for i = 1 : k
                    ytmp(:, i) = R(1:initer,1:initer,i) \ w(1:initer, i);
                end
                additive = bsxfun(@times, U(:,:,initer), -2*ytmp(initer,:).*conj(U(initer, :, initer)));
                additive(initer, :) = additive(initer, :) + ytmp(initer, :);
                for h = initer-1 : -1 : 1
                    additive(h, :) = additive(h, :) + ytmp(h, :);
                    additive = additive - bsxfun(@times, U(:,:,h), 2*sum(U(:,:,h).*additive));
                end
                if all(sqrt(sum(additive.^2)) < eps*sqrt(sum(x.^2)))
                    stag = stag + 1;
                else
                    stag = 0;
                end
                xm = x + additive;
                evalxm = 1;
            elseif evalxm == 1
                addvc = zeros(initer, k);
                for i = 1 : k
                    addvc(:, i) = [-(R(1:initer-1,1:initer-1,i)\R(1:initer-1,initer,i)) * (w(initer,i)/R(initer,initer,i)); w(initer,i)/R(initer,initer,i)];
                end
                if all(sqrt(sum(addvc.^2)) < eps*sqrt(sum(xm.^2)))
                    stag = stag + 1;
                else
                    stag = 0;
                end
                additive = bsxfun(@times, U(:,:,initer), -2*addvc(initer,:).*conj(U(initer, :, initer)));
                additive(initer, :) = additive(initer, :) + addvc(initer, :);
                for h = initer-1 : -1 : 1
                    additive(h, :) = additive(h, :) + addvc(h, :);
                    additive = additive - bsxfun(@times, U(:,:,h), 2*sum(U(:,:,h).*additive));
                end
                xm = xm + additive;
            end
            r = b - customAfun(afun, atype, afcnstr, xm, varargin{:});
            if all(sqrt(sum(r.^2)) <= tol*n2b)
                x = xm;
                flag = 0;
                iter = [outiter, initer];
                break
            end
            minv_r = r;
            if existM1
                minv_r = iterapp2('mldivide',m1fun,m1type,m1fcnstr,r,varargin{:});
                if ~all(isfinite(minv_r(:)))
                    flag = 2;
                    break
                end
            end
            if existM2
                minv_r = iterapp2('mldivide',m2fun,m2type,m2fcnstr,minv_r,varargin{:});
                if ~all(isfinite(minv_r(:)))
                    flag = 2;
                    break
                end
            end
            
            normr_act = sqrt(sum(minv_r.^2));
            resvec((outiter-1)*inner+initer+1, :) = normr_act;
            
            tobeupdated = find(normr_act <= normrmin);
            normrmin(tobeupdated) = normr_act(tobeupdated);
            imin(tobeupdated) = outiter;
            jmin(tobeupdated) = initer;
            xmin(:, tobeupdated) = xm(:, tobeupdated);
            minupdated(tobeupdated) = true;
            
            if all(normr_act <= tolb)
                x = xm;
                flag = 0;
                iter = [outiter, initer];
                break
            else
                if stag >= maxstagsteps && moresteps == 0
                    stag = 0;
                end
                moresteps = moresteps + 1;
                if moresteps >= maxmsteps
                    if ~warned
                        warning(message('MATLAB:gmres:tooSmallTolerance'));
                    end
                    flag = 3;
                    iter = [outiter, initer];
                    break;
                end
            end
        end
        
        tobeupdated = find(normr_act <= normrmin);
        normrmin(tobeupdated) = normr_act(tobeupdated);
        imin(tobeupdated) = outiter;
        jmin(tobeupdated) = initer;
        minupdated(tobeupdated) = true;
        
        if stag >= maxstagsteps
            flag = 3;
            break;
        end
    end         % ends inner loop
    
    evalxm = 0;
    
    if flag ~= 0
        idx = zeros(1, k);
        idx(minupdated) = jmin;
        idx(~minupdated) = initer;
        additive = zeros(n, k);
        for i = 1 : k
            y = R(1:idx(i),1:idx(i), i) \ w(1:idx(i), i);
            additive(:, i) = U(:,i,idx(i))*(-2*y(idx(i))*conj(U(idx(i),i,idx(i))));
            additive(idx(i), i) = additive(idx(i), i) + y(idx(i));
            for h = idx(i)-1 : -1 : 1
                additive(h, i) = additive(h, i) + y(h);
                additive(:, i) = additive(:, i) - U(:,i,h)*(2*(U(:,i,h)'*additive(:, i)));
            end
        end
        x = x + additive;
        xmin = x;
        r = b - customAfun(afun, atype, afcnstr, x, varargin{:});
        minv_r = r;
        if existM1
            minv_r = iterapp2('mldivide',m1fun,m1type,m1fcnstr,r,varargin{:});
            if ~all(isfinite(minv_r(:)))
                flag = 2;
                break
            end
        end
        if existM2
            minv_r = iterapp2('mldivide',m2fun,m2type,m2fcnstr,minv_r,varargin{:});
            if ~all(isfinite(minv_r(:)))
                flag = 2;
                break
            end
        end
        normr_act = sqrt(sum(minv_r.^2));
        r = minv_r;
    end
    
    tobeupdated = find(normr_act <= normrmin);
    xmin(:, tobeupdated) = x(:, tobeupdated);
    normrmin(tobeupdated) = normr_act(tobeupdated);
    imin(tobeupdated) = outiter;
    jmin(tobeupdated) = initer;
    
    if flag == 3
        break;
    end
    if all(normr_act <= tolb)
        flag = 0;
        iter = [outiter, initer];
        break;
    end
    minupdated = false(1, k);
end         % ends outer loop

% returned solution is that with minimum residual
if flag == 0
    relres = normr_act ./ n2minv_b;
else
    x = xmin;
    iter = [imin jmin];
    relres = normr_act ./ n2minv_b;
end

% truncate the zeros from resvec
if flag <= 1 || flag == 3
    resvec = resvec(1:(outiter-1)*inner+initer+1, :);
    %indices = resvec==0;
    %resvec = resvec(~indices);
else
    if initer == 0
        resvec = resvec(1:(outiter-1)*inner+1, :);
    else
        resvec = resvec(1:(outiter-1)*inner+initer, :);
    end
end

% only display a message if the output flag is not used
if nargout < 2
    if restarted
        itermsg2(sprintf('gmres(%d)',restart),tol,maxit,[outiter initer],flag,iter,relres);
    else
        itermsg2(sprintf('gmres'),tol,maxit,initer,flag,iter(2),relres);
    end
end

function sgn = scalarsign(d)
sgn = sign(d);
sgn(sgn == 0) = 1;

function Ax = customAfun(afun, atype, afcnstr, x, varargin)
[n, k] = size(x);
Ax = iterapp2('mtimes',afun,atype,afcnstr,x,varargin{:});