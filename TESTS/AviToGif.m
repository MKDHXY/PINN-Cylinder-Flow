%% AVI_TO_GIF_GUI.m
% Batch AVI -> compressed GIF
% All settings are selected through dialog boxes.
%
% MATLAB R2016b or newer recommended.
% imresize requires Image Processing Toolbox.

clear;
clc;

%% =========================================================
% 1. SELECT AVI FILES
% ==========================================================

[fileNames, inputPath] = uigetfile( ...
    {'*.avi','AVI Video Files (*.avi)'}, ...
    'Select one or more AVI files', ...
    'MultiSelect','on');

if isequal(fileNames,0)
    disp('Cancelled.');
    return;
end

if ischar(fileNames)
    fileNames = {fileNames};
end


%% =========================================================
% 2. SELECT OUTPUT FOLDER
% ==========================================================

outputPath = uigetdir(inputPath, ...
    'Select folder for exported GIF files');

if isequal(outputPath,0)
    disp('Cancelled.');
    return;
end


%% =========================================================
% 3. QUALITY / SIZE DIALOG
% ==========================================================

prompt = { ...
    'Target maximum GIF size (MB):', ...
    'Initial GIF width (pixels):', ...
    'Initial FPS:', ...
    'Initial number of colours (16-256):'};

dlgtitle = 'GIF Compression Settings';

dims = [1 45];

defaultValues = { ...
    '5', ...      % target MB
    '600', ...    % width
    '8', ...      % FPS
    '64'};        % colours

answer = inputdlg( ...
    prompt, ...
    dlgtitle, ...
    dims, ...
    defaultValues);

if isempty(answer)
    disp('Cancelled.');
    return;
end


%% Read user settings

targetMB = str2double(answer{1});
startWidth = round(str2double(answer{2}));
startFPS = str2double(answer{3});
startColors = round(str2double(answer{4}));


%% Check input values

if isnan(targetMB) || targetMB <= 0
    error('Target size must be greater than 0 MB.');
end

if isnan(startWidth) || startWidth < 100
    error('Width must be at least 100 pixels.');
end

if isnan(startFPS) || startFPS <= 0
    error('FPS must be greater than 0.');
end

if isnan(startColors)
    error('Invalid colour number.');
end

startColors = max(16,min(256,startColors));


%% =========================================================
% 4. SHOW SETTINGS
% ==========================================================

message = sprintf([ ...
    'Files selected: %d\n\n' ...
    'Target size: %.1f MB\n' ...
    'Initial width: %d px\n' ...
    'Initial FPS: %.1f\n' ...
    'Initial colours: %d\n\n' ...
    'The program will automatically reduce quality\n' ...
    'if the GIF is larger than the target size.'], ...
    numel(fileNames), ...
    targetMB, ...
    startWidth, ...
    startFPS, ...
    startColors);

choice = questdlg( ...
    message, ...
    'Confirm GIF Settings', ...
    'Start', ...
    'Cancel', ...
    'Start');

if ~strcmp(choice,'Start')
    disp('Cancelled.');
    return;
end


%% =========================================================
% 5. PROCESS ALL AVI FILES
% ==========================================================

for fileID = 1:numel(fileNames)

    inputFile = fullfile(inputPath,fileNames{fileID});

    [~,baseName,~] = fileparts(fileNames{fileID});

    outputFile = fullfile( ...
        outputPath, ...
        [baseName '.gif']);

    fprintf('\n');
    fprintf('========================================\n');
    fprintf('File %d / %d\n',fileID,numel(fileNames));
    fprintf('%s\n',fileNames{fileID});
    fprintf('========================================\n');


    %% Starting parameters

    currentWidth = startWidth;
    currentFPS = startFPS;
    currentColors = startColors;

    maxAttempts = 8;

    success = false;


    %% =====================================================
    % AUTOMATIC SIZE CONTROL
    % ======================================================

    for attempt = 1:maxAttempts

        fprintf('\nCompression attempt %d\n',attempt);
        fprintf('Width   : %d px\n',currentWidth);
        fprintf('FPS     : %.2f\n',currentFPS);
        fprintf('Colours : %d\n',currentColors);


        %% Delete previous trial GIF

        if exist(outputFile,'file')
            delete(outputFile);
        end


        %% Convert AVI -> GIF

        convertAVItoGIF( ...
            inputFile, ...
            outputFile, ...
            currentWidth, ...
            currentFPS, ...
            currentColors);


        %% Check generated size

        info = dir(outputFile);

        gifMB = info.bytes / 1024 / 1024;

        fprintf('GIF size: %.2f MB\n',gifMB);


        %% Target reached

        if gifMB <= targetMB

            fprintf('\nTARGET ACHIEVED!\n');

            success = true;

            break;

        end


        %% =================================================
        % AUTOMATIC QUALITY REDUCTION
        % ==================================================

        ratio = targetMB / gifMB;


        % First reduce colour depth
        if currentColors > 32

            currentColors = max(32, ...
                round(currentColors * 0.75));


        % Then reduce FPS
        elseif currentFPS > 5

            currentFPS = max(5, ...
                currentFPS * 0.8);


        % Then reduce resolution
        else

            % Estimate required width reduction
            scaleFactor = sqrt(max(0.5,ratio));

            currentWidth = round( ...
                currentWidth * scaleFactor);

            currentWidth = max(320,currentWidth);

        end

    end


    %% =====================================================
    % RESULT
    % ======================================================

    outputInfo = dir(outputFile);
    inputInfo = dir(inputFile);

    outputMB = outputInfo.bytes/1024/1024;
    inputMB = inputInfo.bytes/1024/1024;

    fprintf('\n----------------------------------------\n');
    fprintf('Original AVI : %.2f MB\n',inputMB);
    fprintf('Final GIF    : %.2f MB\n',outputMB);
    fprintf('Final width  : %d px\n',currentWidth);
    fprintf('Final FPS    : %.2f\n',currentFPS);
    fprintf('Final colours: %d\n',currentColors);
    fprintf('Saved to:\n%s\n',outputFile);
    fprintf('----------------------------------------\n');

    if ~success

        fprintf([ ...
            '\nWarning: Target size was not fully reached.\n' ...
            'The smallest attempted version was kept.\n']);

    end

end


%% =========================================================
% 6. FINISHED DIALOG
% ==========================================================

msgbox( ...
    sprintf( ...
    ['Finished!\n\n' ...
     '%d GIF file(s) exported to:\n%s'], ...
     numel(fileNames), ...
     outputPath), ...
    'AVI to GIF Complete');


%% =========================================================
% LOCAL FUNCTION
% ==========================================================

function convertAVItoGIF( ...
    inputFile, ...
    outputFile, ...
    targetWidth, ...
    targetFPS, ...
    nColors)

    v = VideoReader(inputFile);

    originalFPS = v.FrameRate;

    frameStep = max(1,round(originalFPS/targetFPS));

    actualFPS = originalFPS/frameStep;

    delayTime = 1/actualFPS;

    frameNumber = 0;
    gifFrameNumber = 0;

    map = [];


    while hasFrame(v)

        frame = readFrame(v);

        frameNumber = frameNumber + 1;


        %% Skip frames

        if mod(frameNumber-1,frameStep) ~= 0
            continue;
        end


        %% Resize

        oldWidth = size(frame,2);

        if oldWidth > targetWidth

            scale = targetWidth/oldWidth;

            frame = imresize(frame,scale);

        end


        %% First GIF frame

        if gifFrameNumber == 0

            [indexedFrame,map] = ...
                rgb2ind(frame,nColors,'nodither');

            imwrite( ...
                indexedFrame, ...
                map, ...
                outputFile, ...
                'gif', ...
                'LoopCount',Inf, ...
                'DelayTime',delayTime);


        %% Following GIF frames

        else

            indexedFrame = ...
                rgb2ind(frame,map,'nodither');

            imwrite( ...
                indexedFrame, ...
                map, ...
                outputFile, ...
                'gif', ...
                'WriteMode','append', ...
                'DelayTime',delayTime);

        end


        gifFrameNumber = gifFrameNumber + 1;

        fprintf( ...
            'Frames written: %d\r', ...
            gifFrameNumber);

    end

    fprintf('\n');

end