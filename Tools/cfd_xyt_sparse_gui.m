%% cfd_xyt_sparse_gui.m
% CFD x-y-t sparse observation generator for PINN
%
% Supports:
%   1) PINN-ready CSV with columns:
%      x, y, t, u, v, p
%
%   2) Raw ParaView/OpenFOAM CSV with columns:
%      p, U:0, U:1, U:2, Points:0, Points:1, Points:2
%
% Main features:
%   - No interpolation
%   - Keeps original CFD datapoints
%   - Preserves physical time from x,y,t,u,v,p datasets
%   - GUI dialogs for Re, D, U_inf, nu, cylinder centre, etc.
%   - Separate spatial and temporal sparsity
%   - D-based wake / near-cylinder regions
%   - Random, uniform, wake-focused, boundary-focused, and probe-like sampling
%   - Exports PINN-ready sparse CSV: x,y,t,u,v,p
%   - Optional MAT export with metadata and original indices
%
% IMPORTANT:
%   OpenFOAM incompressible pressure p is assumed to be kinematic pressure
%   [m^2/s^2] for this project.
%
% © 2026 PINN-Cylinder-Flow Project Team. All rights reserved.
% External use requires prior permission from the project team.

clear; clc; close all;

%% ============================================================
% 1. SELECT CSV FILE
% ============================================================

[fileName, filePath] = uigetfile( ...
    {'*.csv','CSV Files (*.csv)'}, ...
    'Select CFD CSV file');

if isequal(fileName,0)
    disp('Cancelled.');
    return;
end

csvFile = fullfile(filePath,fileName);

T = readtable(csvFile,'VariableNamingRule','preserve');
vars = T.Properties.VariableNames;

fprintf('\nLoaded CSV:\n%s\n',csvFile);
disp('Detected CSV columns:');
disp(vars');

%% ============================================================
% 2. AUTO-DETECT CSV FORMAT
% ============================================================

hasPINN = all(cellfun(@(s) any(strcmpi(vars,s)), ...
    {'x','y','t','u','v','p'}));

hasParaView = all(cellfun(@(s) any(strcmpi(vars,s)), ...
    {'p','U:0','U:1','U:2','Points:0','Points:1','Points:2'}));

if hasPINN
    dataFormat = 'PINN_READY_XYTU VP';

    x = get_column_ci(T,'x');
    y = get_column_ci(T,'y');
    t = get_column_ci(T,'t');
    u = get_column_ci(T,'u');
    v = get_column_ci(T,'v');
    p = get_column_ci(T,'p');

    z = zeros(size(x));
    w = zeros(size(x));

    fprintf('\nDetected format: PINN-ready x,y,t,u,v,p\n');

elseif hasParaView
    dataFormat = 'PARAVIEW_RAW_SNAPSHOT';

    x = get_column_ci(T,'Points:0');
    y = get_column_ci(T,'Points:1');
    z = get_column_ci(T,'Points:2');

    u = get_column_ci(T,'U:0');
    v = get_column_ci(T,'U:1');
    w = get_column_ci(T,'U:2');

    p = get_column_ci(T,'p');

    suggestedTime = extract_time_from_filename(fileName);
    if isnan(suggestedTime)
        suggestedTimeText = '0';
    else
        suggestedTimeText = sprintf('%.12g',suggestedTime);
    end

    ansTime = inputdlg( ...
        {'Physical time of this CFD snapshot t [s]:'}, ...
        'Snapshot Time', ...
        [1 50], ...
        {suggestedTimeText});

    if isempty(ansTime)
        disp('Cancelled.');
        return;
    end

    timeValue = str2double(ansTime{1});
    if isnan(timeValue)
        error('Invalid physical time.');
    end

    t = timeValue*ones(size(x));

    fprintf('\nDetected format: raw ParaView/OpenFOAM snapshot\n');

else
    error(sprintf([ ...
        'Unknown CSV format.\n\n' ...
        'Supported formats:\n' ...
        '1) x, y, t, u, v, p\n' ...
        '2) p, U:0, U:1, U:2, Points:0, Points:1, Points:2']));
end

%% ============================================================
% 3. BASIC DATA VALIDATION
% ============================================================

x = x(:); y = y(:); z = z(:); t = t(:);
u = u(:); v = v(:); w = w(:); p = p(:);

N0 = numel(x);

if any([numel(y),numel(z),numel(t),numel(u),numel(v),numel(w),numel(p)] ~= N0)
    error('Input columns do not have the same length.');
end

originalIndexAll = (1:N0)';

finiteMask = isfinite(x) & isfinite(y) & isfinite(t) & ...
             isfinite(u) & isfinite(v) & isfinite(p);

if ~all(finiteMask)
    fprintf('\nWarning: removing %d rows containing NaN/Inf.\n', ...
        nnz(~finiteMask));

    x = x(finiteMask);
    y = y(finiteMask);
    z = z(finiteMask);
    t = t(finiteMask);
    u = u(finiteMask);
    v = v(finiteMask);
    w = w(finiteMask);
    p = p(finiteMask);

    originalIndexAll = originalIndexAll(finiteMask);
end

speed = sqrt(u.^2 + v.^2 + w.^2);
N = numel(x);

fprintf('\nValid CFD rows: %d\n',N);
fprintf('x range = [%g, %g] m\n',min(x),max(x));
fprintf('y range = [%g, %g] m\n',min(y),max(y));
fprintf('t range = [%g, %g] s\n',min(t),max(t));
fprintf('u range = [%g, %g] m/s\n',min(u),max(u));
fprintf('v range = [%g, %g] m/s\n',min(v),max(v));
fprintf('p range = [%g, %g] m^2/s^2\n',min(p),max(p));

%% ============================================================
% 4. IDENTIFY UNIQUE SPATIAL LOCATIONS AND TIMES
% ============================================================

% For the exported full x-y-t CFD dataset, repeated x-y locations are
% expected across different time steps. We keep the exact original values.
XY = [x,y];

[uniqueXY,~,spaceID] = unique(XY,'rows','stable');
[uniqueTimes,~,timeID] = unique(t,'stable');

nSpace = size(uniqueXY,1);
nTimes = numel(uniqueTimes);

fprintf('\nUnique spatial points : %d\n',nSpace);
fprintf('Unique time levels    : %d\n',nTimes);

%% ============================================================
% 5. SELECT CFD CASE PRESET
% ============================================================

caseList = {'RE100','RE200','RE3900','Custom'};

[caseIndex,ok] = listdlg( ...
    'PromptString','Select CFD case preset:', ...
    'SelectionMode','single', ...
    'ListString',caseList, ...
    'ListSize',[260 135], ...
    'Name','CFD Case');

if ok == 0
    disp('Cancelled.');
    return;
end

selectedCase = caseList{caseIndex};

switch selectedCase
    case 'RE100'
        defaultRe = 100;
    case 'RE200'
        defaultRe = 200;
    case 'RE3900'
        defaultRe = 3900;
    otherwise
        defaultRe = 200;
end

% Project defaults. Confirm/edit them in the dialog before use.
defaultD = 0.001;
defaultUinf = 0.015;
defaultNu = defaultUinf*defaultD/defaultRe;
defaultXc = 0;
defaultYc = 0;

%% ============================================================
% 6. CASE / PHYSICAL / GEOMETRIC PARAMETER DIALOG
% ============================================================

prompt = { ...
    'Reynolds number Re:', ...
    'Cylinder diameter D [m]:', ...
    'Free-stream velocity U_inf [m/s]:', ...
    'Kinematic viscosity nu [m^2/s]:', ...
    'Cylinder centre x_c [m]:', ...
    'Cylinder centre y_c [m]:', ...
    'Wake start position (x-x_c)/D:', ...
    'Wake end position (x-x_c)/D:', ...
    'Wake half-width |y-y_c|/D:', ...
    'Near-cylinder sampling thickness / D:', ...
    'Outer-boundary sampling thickness [% domain size]:', ...
    'Random seed:'};

defaults = { ...
    sprintf('%.12g',defaultRe), ...
    sprintf('%.12g',defaultD), ...
    sprintf('%.12g',defaultUinf), ...
    sprintf('%.12g',defaultNu), ...
    sprintf('%.12g',defaultXc), ...
    sprintf('%.12g',defaultYc), ...
    '0.5', ...
    '20', ...
    '5', ...
    '2', ...
    '5', ...
    '1234'};

answer = inputdlg( ...
    prompt, ...
    sprintf('CFD / Sampling Parameters - %s',selectedCase), ...
    [1 68], ...
    defaults);

if isempty(answer)
    disp('Cancelled.');
    return;
end

Re             = str2double(answer{1});
D              = str2double(answer{2});
Uinf           = str2double(answer{3});
nu             = str2double(answer{4});
xc             = str2double(answer{5});
yc             = str2double(answer{6});
wakeStartD     = str2double(answer{7});
wakeEndD       = str2double(answer{8});
wakeHalfWidthD = str2double(answer{9});
cylinderBandD  = str2double(answer{10});
outerPercent   = str2double(answer{11});
randomSeed     = round(str2double(answer{12}));

allInputs = [ ...
    Re,D,Uinf,nu,xc,yc,wakeStartD,wakeEndD, ...
    wakeHalfWidthD,cylinderBandD,outerPercent,randomSeed];

if any(isnan(allInputs))
    error('All case parameters must be numeric.');
end

if Re <= 0 || D <= 0 || Uinf <= 0 || nu <= 0
    error('Re, D, U_inf and nu must be positive.');
end

if wakeEndD <= wakeStartD
    error('Wake end x/D must be larger than wake start x/D.');
end

if wakeHalfWidthD <= 0
    error('Wake half-width must be positive.');
end

if cylinderBandD < 0
    error('Near-cylinder thickness cannot be negative.');
end

if outerPercent < 0 || outerPercent > 50
    error('Outer-boundary percentage must be between 0 and 50.');
end

%% ============================================================
% 7. REYNOLDS-NUMBER CONSISTENCY CHECK
% ============================================================

ReCalculated = Uinf*D/nu;
ReErrorPct = abs(ReCalculated-Re)/Re*100;

if ReErrorPct > 0.5

    msg = sprintf([ ...
        'The physical parameters are not fully consistent.\n\n' ...
        'Entered Re = %.8g\n' ...
        'U_inf*D/nu = %.8g\n' ...
        'Difference = %.4f %%\n\n' ...
        'Auto-correct nu using nu = U_inf*D/Re?'], ...
        Re,ReCalculated,ReErrorPct);

    choice = questdlg( ...
        msg, ...
        'Reynolds Number Check', ...
        'Auto-correct nu', ...
        'Keep entered nu', ...
        'Cancel', ...
        'Auto-correct nu');

    if strcmp(choice,'Auto-correct nu')
        nu = Uinf*D/Re;
        ReCalculated = Re;
        ReErrorPct = 0;

    elseif strcmp(choice,'Cancel') || isempty(choice)
        disp('Cancelled.');
        return;
    end
end

%% ============================================================
% 8. BUILD D-BASED SAMPLING GEOMETRY
% ============================================================

R = D/2;

wakeXmin = xc + wakeStartD*D;
wakeXmax = xc + wakeEndD*D;
wakeHalfWidth = wakeHalfWidthD*D;

nearCylinderOuterR = R + cylinderBandD*D;
outerFraction = outerPercent/100;

caseInfo = struct;
caseInfo.casePreset = selectedCase;
caseInfo.dataFormat = dataFormat;
caseInfo.Re = Re;
caseInfo.ReCalculated = ReCalculated;
caseInfo.D_m = D;
caseInfo.Uinf_mps = Uinf;
caseInfo.nu_m2ps = nu;
caseInfo.cylinderCenter_m = [xc,yc];
caseInfo.pressureType = 'OpenFOAM kinematic pressure';
caseInfo.pressureUnit = 'm^2/s^2';
caseInfo.randomSeed = randomSeed;
caseInfo.wakeStart_xOverD = wakeStartD;
caseInfo.wakeEnd_xOverD = wakeEndD;
caseInfo.wakeHalfWidth_yOverD = wakeHalfWidthD;
caseInfo.nearCylinderThickness_D = cylinderBandD;
caseInfo.outerBoundaryThickness_percent = outerPercent;
caseInfo.fullRows = N;
caseInfo.uniqueSpatialPoints = nSpace;
caseInfo.uniqueTimeLevels = nTimes;
caseInfo.timeRange_s = [min(t),max(t)];

fprintf('\n=============================================\n');
fprintf('CFD CASE INFORMATION\n');
fprintf('=============================================\n');
fprintf('Case             : %s\n',selectedCase);
fprintf('Re               : %.8g\n',Re);
fprintf('Calculated Re    : %.8g\n',ReCalculated);
fprintf('D                : %.8g m\n',D);
fprintf('U_inf            : %.8g m/s\n',Uinf);
fprintf('nu               : %.8g m^2/s\n',nu);
fprintf('Cylinder centre  : (%.8g, %.8g) m\n',xc,yc);
fprintf('Time range       : %.8g -> %.8g s\n',min(t),max(t));
fprintf('Spatial points   : %d\n',nSpace);
fprintf('Time levels      : %d\n',nTimes);

%% ============================================================
% 9. SPATIAL / TEMPORAL SPARSITY DIALOG
% ============================================================

sparseAnswer = inputdlg( ...
    { ...
    'Spatial keep ratio (0-1), e.g. 0.10 = keep 10% spatial locations:', ...
    'Temporal keep ratio (0-1), e.g. 0.50 = keep 50% time levels:'}, ...
    'PINN Sparse Observation Settings', ...
    [1 75], ...
    {'0.10','1.00'});

if isempty(sparseAnswer)
    disp('Cancelled.');
    return;
end

spatialKeepRatio = str2double(sparseAnswer{1});
temporalKeepRatio = str2double(sparseAnswer{2});

if isnan(spatialKeepRatio) || spatialKeepRatio <= 0 || spatialKeepRatio > 1
    error('Spatial keep ratio must satisfy 0 < ratio <= 1.');
end

if isnan(temporalKeepRatio) || temporalKeepRatio <= 0 || temporalKeepRatio > 1
    error('Temporal keep ratio must satisfy 0 < ratio <= 1.');
end

%% ============================================================
% 10. CHOOSE SPATIAL SAMPLING METHOD
% ============================================================

methodList = { ...
    'Random spatial points', ...
    'Uniform spatial points', ...
    'Wake-focused spatial points', ...
    'Boundary-focused spatial points', ...
    'Probe-like fixed sensors'};

[methodIndex,ok] = listdlg( ...
    'PromptString','Choose spatial observation method:', ...
    'SelectionMode','single', ...
    'ListString',methodList, ...
    'ListSize',[390 165], ...
    'Name','Spatial Sampling');

if ok == 0
    disp('Cancelled.');
    return;
end

spatialMethod = methodList{methodIndex};

%% ============================================================
% 11. CHOOSE TEMPORAL SAMPLING METHOD
% ============================================================

if nTimes == 1
    temporalMethod = 'All time levels';
    temporalKeepRatio = 1;

else
    temporalList = { ...
        'Uniform time levels', ...
        'Random time levels', ...
        'All time levels'};

    [timeMethodIndex,ok] = listdlg( ...
        'PromptString','Choose temporal observation method:', ...
        'SelectionMode','single', ...
        'ListString',temporalList, ...
        'ListSize',[320 120], ...
        'Name','Temporal Sampling');

    if ok == 0
        disp('Cancelled.');
        return;
    end

    temporalMethod = temporalList{timeMethodIndex};

    if strcmp(temporalMethod,'All time levels')
        temporalKeepRatio = 1;
    end
end

rng(randomSeed);

%% ============================================================
% 12. SELECT TEMPORAL LEVELS
% ============================================================

numTimeKeep = max(1,round(temporalKeepRatio*nTimes));

switch temporalMethod

    case 'All time levels'
        selectedTimeIDs = (1:nTimes)';

    case 'Uniform time levels'
        selectedTimeIDs = unique( ...
            round(linspace(1,nTimes,numTimeKeep))' );

    case 'Random time levels'
        selectedTimeIDs = sort(randperm(nTimes,numTimeKeep)');

    otherwise
        error('Unknown temporal method.');
end

selectedTimes = uniqueTimes(selectedTimeIDs);

%% ============================================================
% 13. SELECT SPATIAL LOCATIONS
% ============================================================

xs = uniqueXY(:,1);
ys = uniqueXY(:,2);

numSpaceKeep = max(1,round(spatialKeepRatio*nSpace));

switch spatialMethod

    case 'Random spatial points'

        selectedSpaceIDs = sort(randperm(nSpace,numSpaceKeep)');


    case 'Uniform spatial points'

        % No interpolation is performed.
        % This sorts original spatial locations in x-y order and then
        % distributes selections across that ordering.
        [~,sortedID] = sortrows([xs,ys],[1 2]);

        pos = unique(round(linspace(1,nSpace,numSpaceKeep))');
        selectedSpaceIDs = sortedID(pos);

        if numel(selectedSpaceIDs) < numSpaceKeep
            remaining = setdiff((1:nSpace)',selectedSpaceIDs,'stable');
            need = min(numSpaceKeep-numel(selectedSpaceIDs),numel(remaining));
            selectedSpaceIDs = [selectedSpaceIDs; remaining(1:need)];
        end

        selectedSpaceIDs = sort(unique(selectedSpaceIDs));


    case 'Wake-focused spatial points'

        candidate = find( ...
            xs >= wakeXmin & ...
            xs <= wakeXmax & ...
            abs(ys-yc) <= wakeHalfWidth);

        selectedSpaceIDs = choose_candidate_space( ...
            candidate,numSpaceKeep,nSpace,'wake region');


    case 'Boundary-focused spatial points'

        r = sqrt((xs-xc).^2 + (ys-yc).^2);

        xRange = max(xs)-min(xs);
        yRange = max(ys)-min(ys);

        outerTolX = outerFraction*xRange;
        outerTolY = outerFraction*yRange;

        nearOuter = ...
            abs(xs-min(xs)) <= outerTolX | ...
            abs(xs-max(xs)) <= outerTolX | ...
            abs(ys-min(ys)) <= outerTolY | ...
            abs(ys-max(ys)) <= outerTolY;

        nearCylinder = ...
            r >= R & ...
            r <= nearCylinderOuterR;

        candidate = find(nearOuter | nearCylinder);

        selectedSpaceIDs = choose_candidate_space( ...
            candidate,numSpaceKeep,nSpace, ...
            'boundary / near-cylinder region');


    case 'Probe-like fixed sensors'

        probeAnswer = inputdlg( ...
            { ...
            'Number of probe columns in x:', ...
            'Number of probe rows in y:', ...
            'Probe x/D start:', ...
            'Probe x/D end:', ...
            'Probe y/D minimum:', ...
            'Probe y/D maximum:'}, ...
            'Probe-like Sensor Layout', ...
            [1 55], ...
            {'10','3','1','20','-2','2'});

        if isempty(probeAnswer)
            disp('Cancelled.');
            return;
        end

        nProbeX = round(str2double(probeAnswer{1}));
        nProbeY = round(str2double(probeAnswer{2}));
        probeXStartD = str2double(probeAnswer{3});
        probeXEndD = str2double(probeAnswer{4});
        probeYMinD = str2double(probeAnswer{5});
        probeYMaxD = str2double(probeAnswer{6});

        probeVals = [ ...
            nProbeX,nProbeY,probeXStartD,probeXEndD, ...
            probeYMinD,probeYMaxD];

        if any(isnan(probeVals)) || nProbeX < 1 || nProbeY < 1
            error('Invalid probe-layout values.');
        end

        if probeXEndD < probeXStartD || probeYMaxD < probeYMinD
            error('Probe start/end ranges are invalid.');
        end

        probeX = xc + linspace(probeXStartD,probeXEndD,nProbeX)*D;
        probeY = yc + linspace(probeYMinD,probeYMaxD,nProbeY)*D;

        [PX,PY] = meshgrid(probeX,probeY);
        targetProbeXY = [PX(:),PY(:)];

        selectedSpaceIDs = nearest_original_points( ...
            uniqueXY,targetProbeXY);

        selectedSpaceIDs = sort(unique(selectedSpaceIDs));

        caseInfo.probeLayout.nProbeX = nProbeX;
        caseInfo.probeLayout.nProbeY = nProbeY;
        caseInfo.probeLayout.xStart_D = probeXStartD;
        caseInfo.probeLayout.xEnd_D = probeXEndD;
        caseInfo.probeLayout.yMin_D = probeYMinD;
        caseInfo.probeLayout.yMax_D = probeYMaxD;
        caseInfo.probeLayout.requestedSensors = size(targetProbeXY,1);
        caseInfo.probeLayout.actualUniqueSensors = numel(selectedSpaceIDs);

        fprintf('\nProbe-like sampling uses fixed spatial sensors.\n');
        fprintf('Requested probe positions: %d\n',size(targetProbeXY,1));
        fprintf('Unique nearest CFD points: %d\n',numel(selectedSpaceIDs));


    otherwise
        error('Unknown spatial sampling method.');
end

selectedSpaceIDs = selectedSpaceIDs(:);

%% ============================================================
% 14. BUILD SPATIOTEMPORAL OBSERVATION MASK
% ============================================================

selectedSpatialMask = ismember(spaceID,selectedSpaceIDs);
selectedTemporalMask = ismember(timeID,selectedTimeIDs);

observationMask = selectedSpatialMask & selectedTemporalMask;

sparseRowID = find(observationMask);

x_s = x(observationMask);
y_s = y(observationMask);
t_s = t(observationMask);
u_s = u(observationMask);
v_s = v(observationMask);
p_s = p(observationMask);

z_s = z(observationMask);
w_s = w(observationMask);
speed_s = speed(observationMask);

originalIndex_s = originalIndexAll(observationMask);

actualSpatialRatio = numel(selectedSpaceIDs)/nSpace;
actualTemporalRatio = numel(selectedTimeIDs)/nTimes;
actualRowRatio = nnz(observationMask)/N;

caseInfo.spatialMethod = spatialMethod;
caseInfo.temporalMethod = temporalMethod;
caseInfo.requestedSpatialKeepRatio = spatialKeepRatio;
caseInfo.actualSpatialKeepRatio = actualSpatialRatio;
caseInfo.requestedTemporalKeepRatio = temporalKeepRatio;
caseInfo.actualTemporalKeepRatio = actualTemporalRatio;
caseInfo.actualObservationRowRatio = actualRowRatio;
caseInfo.selectedSpatialPoints = numel(selectedSpaceIDs);
caseInfo.selectedTimeLevels = numel(selectedTimeIDs);
caseInfo.selectedObservationRows = nnz(observationMask);

fprintf('\n=============================================\n');
fprintf('SPARSE OBSERVATION RESULT\n');
fprintf('=============================================\n');
fprintf('Spatial method           : %s\n',spatialMethod);
fprintf('Temporal method          : %s\n',temporalMethod);
fprintf('Spatial points kept      : %d / %d (%.3f%%)\n', ...
    numel(selectedSpaceIDs),nSpace,100*actualSpatialRatio);
fprintf('Time levels kept         : %d / %d (%.3f%%)\n', ...
    numel(selectedTimeIDs),nTimes,100*actualTemporalRatio);
fprintf('Observation rows kept    : %d / %d (%.3f%%)\n', ...
    nnz(observationMask),N,100*actualRowRatio);

%% ============================================================
% 15. PLOT SPATIAL SENSOR LOCATIONS
% ============================================================

plotChoice = questdlg( ...
    'Plot selected spatial observation locations?', ...
    'Plot Sparse Locations', ...
    'Yes','No','Yes');

if strcmp(plotChoice,'Yes')

    figure('Name','PINN Sparse Spatial Locations','Color','w');

    scatter(xs,ys,5,[0.78 0.78 0.78],'filled');
    hold on;

    selectedXY = uniqueXY(selectedSpaceIDs,:);

    scatter(selectedXY(:,1),selectedXY(:,2),20,'filled');

    theta = linspace(0,2*pi,300);
    plot(xc + R*cos(theta),yc + R*sin(theta), ...
        'k-','LineWidth',1.4);

    if strcmp(spatialMethod,'Wake-focused spatial points')
        rectangle( ...
            'Position',[ ...
            wakeXmin, ...
            yc-wakeHalfWidth, ...
            wakeXmax-wakeXmin, ...
            2*wakeHalfWidth], ...
            'EdgeColor','k', ...
            'LineStyle','--');
    end

    axis equal tight;
    grid on;
    xlabel('x [m]');
    ylabel('y [m]');

    title(sprintf( ...
        '%s | Re %.0f | %s | %d spatial points', ...
        selectedCase,Re,spatialMethod,numel(selectedSpaceIDs)));

    legend( ...
        'All original CFD spatial points', ...
        'Selected PINN observation points', ...
        'Cylinder', ...
        'Location','best');
end

%% ============================================================
% 16. EXPORT PINN-READY SPARSE CSV
% ============================================================

exportChoice = questdlg( ...
    'Export sparse PINN observations to CSV?', ...
    'Export Sparse CSV', ...
    'Yes','No','Yes');

if strcmp(exportChoice,'Yes')

    methodClean = clean_method_name(spatialMethod);
    timeClean = clean_method_name(temporalMethod);

    defaultCSV = sprintf( ...
        '%s_RE%.0f_%s_%s_XYTUVP.csv', ...
        erase_filename_extension(fileName), ...
        Re, ...
        upper(methodClean), ...
        upper(timeClean));

    [outName,outPath] = uiputfile( ...
        '*.csv', ...
        'Save sparse PINN x-y-t-u-v-p CSV', ...
        fullfile(filePath,defaultCSV));

    if ~isequal(outName,0)

        SparseTable = table( ...
            x_s,y_s,t_s,u_s,v_s,p_s, ...
            'VariableNames',{'x','y','t','u','v','p'});

        writetable(SparseTable,fullfile(outPath,outName));

        fprintf('\nSaved sparse PINN CSV:\n%s\n', ...
            fullfile(outPath,outName));
    end
end

%% ============================================================
% 17. OPTIONAL FULL + SPARSE MAT EXPORT
% ============================================================

saveChoice = questdlg( ...
    'Save MATLAB MAT data with metadata?', ...
    'Save MAT', ...
    'Yes','No','Yes');

if strcmp(saveChoice,'Yes')

    methodClean = clean_method_name(spatialMethod);
    timeClean = clean_method_name(temporalMethod);

    defaultMAT = sprintf( ...
        'RE%.0f_%s_%s_PINN_SPARSE.mat', ...
        Re, ...
        upper(methodClean), ...
        upper(timeClean));

    [matName,matPath] = uiputfile( ...
        '*.mat', ...
        'Save PINN sparse MAT file', ...
        fullfile(filePath,defaultMAT));

    if ~isequal(matName,0)

        % Full dimensional CFD variables:
        x_full = x;
        y_full = y;
        t_full = t;
        u_full = u;
        v_full = v;
        p_full = p;

        % Sparse observation variables:
        x_sparse = x_s;
        y_sparse = y_s;
        t_sparse = t_s;
        u_sparse = u_s;
        v_sparse = v_s;
        p_sparse = p_s;

        selectedSpatialXY = uniqueXY(selectedSpaceIDs,:);
        selectedTimeValues = uniqueTimes(selectedTimeIDs);

        save( ...
            fullfile(matPath,matName), ...
            'x_full','y_full','t_full','u_full','v_full','p_full', ...
            'x_sparse','y_sparse','t_sparse','u_sparse','v_sparse','p_sparse', ...
            'originalIndex_s','sparseRowID','observationMask', ...
            'selectedSpaceIDs','selectedSpatialXY', ...
            'selectedTimeIDs','selectedTimeValues', ...
            'caseInfo', ...
            '-v7.3');

        fprintf('\nSaved MAT:\n%s\n', ...
            fullfile(matPath,matName));
    end
end

%% ============================================================
% 18. FINISHED
% ============================================================

summaryMessage = sprintf([ ...
    'Finished.\n\n' ...
    'Case: %s\n' ...
    'Re: %.0f\n' ...
    'Full rows: %d\n' ...
    'Unique spatial points: %d\n' ...
    'Unique time levels: %d\n\n' ...
    'Spatial method: %s\n' ...
    'Temporal method: %s\n' ...
    'Selected spatial points: %d\n' ...
    'Selected time levels: %d\n' ...
    'Sparse observation rows: %d\n' ...
    'Overall retained rows: %.3f %%\n\n' ...
    'No spatial interpolation was used.'], ...
    selectedCase, ...
    Re, ...
    N, ...
    nSpace, ...
    nTimes, ...
    spatialMethod, ...
    temporalMethod, ...
    numel(selectedSpaceIDs), ...
    numel(selectedTimeIDs), ...
    nnz(observationMask), ...
    100*actualRowRatio);

msgbox(summaryMessage,'PINN Sparse Dataset Complete');

disp('Done. No interpolation was used.');

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function data = get_column_ci(T,targetName)
% Read a table column using case-insensitive matching.

    vars = T.Properties.VariableNames;
    idx = find(strcmpi(vars,targetName),1);

    if isempty(idx)
        error('Column "%s" was not found.',targetName);
    end

    data = T.(vars{idx});
end


function timeValue = extract_time_from_filename(fileName)
% Extract the final numeric token from the filename.
% Used only as a suggested default for raw single-snapshot files.

    [~,baseName,~] = fileparts(fileName);

    tokens = regexp( ...
        baseName, ...
        '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', ...
        'match');

    if isempty(tokens)
        timeValue = NaN;
    else
        timeValue = str2double(tokens{end});
    end
end


function selected = choose_candidate_space( ...
    candidate,numKeep,nSpace,regionName)
% Randomly choose original spatial CFD points from a candidate region.

    candidate = candidate(:);

    if isempty(candidate)
        warning( ...
            'No spatial points found in %s. Falling back to global random sampling.', ...
            regionName);

        selected = sort(randperm(nSpace,numKeep)');
        return;
    end

    numCandidate = numel(candidate);
    numLocal = min(numKeep,numCandidate);

    pick = randperm(numCandidate,numLocal);
    selected = sort(candidate(pick));

    if numCandidate < numKeep
        warning([ ...
            '%s contains only %d spatial points, but %d were requested. ' ...
            'All available candidate points were used.'], ...
            regionName,numCandidate,numKeep);
    end
end


function selectedID = nearest_original_points(originalXY,targetXY)
% Map requested probe coordinates to nearest ORIGINAL CFD spatial points.
% No flow-field interpolation is performed.

    nTarget = size(targetXY,1);
    selectedID = zeros(nTarget,1);

    for k = 1:nTarget
        dx = originalXY(:,1)-targetXY(k,1);
        dy = originalXY(:,2)-targetXY(k,2);

        [~,selectedID(k)] = min(dx.^2 + dy.^2);
    end
end


function clean = clean_method_name(nameIn)

    clean = lower(char(nameIn));
    clean = strrep(clean,' ','_');
    clean = strrep(clean,'-','_');
    clean = regexprep(clean,'[^a-zA-Z0-9_]','');
end


function baseName = erase_filename_extension(fileName)

    [~,baseName,~] = fileparts(fileName);
end
