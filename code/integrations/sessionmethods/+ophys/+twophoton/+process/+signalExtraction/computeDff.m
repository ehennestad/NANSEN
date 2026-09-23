classdef computeDff < nansen.session.SessionMethod
%COMPUTEDFF Summary of this function goes here
%   Detailed explanation goes here
    
    properties (Constant) % SessionMethod attributes
        MethodName = 'Compute Delta F over F'
        BatchMode = 'serial'
        IsManual = false
        IsQueueable = true;
        OptionsManager = nansen.OptionsManager(mfilename('class')) % todo...
    end

    properties (Constant)
        DATA_SUBFOLDER = 'roisignals' % defined in nansen.DataMethod
        VARIABLE_PREFIX	= ''          % defined in nansen.DataMethod
    end
    
    methods
        
        function obj = computeDff(varargin)
            
            obj@nansen.session.SessionMethod(varargin{:})

            if ~nargout % how to generalize this???
                obj.runMethod()
                clear obj
            end 
        end
        
    end
    
    methods (Static)
        function options = getDefaultOptions()
        %GETDEFAULTOPTIONS Summary of this function goes here
            options = nansen.twophoton.roisignals.getDffParameters();
        end

        function schema = getOptionsSchema()
        %GETOPTIONSSCHEMA Get the options schema for this method
        %
        %   The schema defines the parameters of this method, their
        %   defaults, allowed values and documentation. It is used by 
        %   nansen.options.Manager for managing option profiles.
        %
        %   Note: Increase the version whenever parameters or default 
        %   values change. See nansen.options.Schema for details.
        
            % Available dff functions are listed by the legacy definition
            legacyOptions = nansen.twophoton.roisignals.getDffParameters();
            
            schema = nansen.options.Schema(mfilename("class"), ...
                Version="1.0.0", ...
                Title="Compute Delta F over F", ...
                Description="Compute DF/F from extracted roi signals");
            
            % Note: Text defaults are character vectors, because the dff
            % functions expect character vectors.
            
            schema.addParameter("baseline", 20, ...
                Description="Percentile of the signal used as the baseline fluorescence (F0)", ...
                Units="percentile", Min=0, Max=100, Integer=true, Size=[1, 1])
            
            schema.addParameter("dffFcn", 'dffClassic', ...
                Description="Function used for computing DF/F (from package nansen.twophoton.roisignals.process.dff)", ...
                Choices=legacyOptions.dffFcn_)
            
            schema.addParameter("correctBaseline", false, ...
                Description="Correct slow drifts of the baseline using a moving percentile filter", ...
                Size=[1, 1])
            
            schema.addParameter("correctionWindowSize", 500, ...
                Description="Window size of the moving percentile filter for baseline correction", ...
                Units="samples", Min=0, Integer=true, Size=[1, 1])
            
            schema.addParameter("correctionPrctile", 25, ...
                Description="Percentile of the moving percentile filter for baseline correction", ...
                Units="percentile", Min=0, Max=100, Integer=true, Size=[1, 1], ...
                Widget="slider")
        end
    end

    methods
        
        function runMethod(obj)

            import nansen.twophoton.roisignals.computeDff
            
            obj.SessionObjects.validateVariable('RoiSignals_MeanF')
            
            signalArray = obj.loadData('RoiSignals_MeanF');
            
            % Reshape signals to have correct dimensions and sizes for the
            % dff functions. (numsamples x numsubregions x numrois)
            if contains(signalArray.Properties.VariableNames, ...
                    'RoiSignals_NeuropilF')
                signalArray = cat(3, signalArray.RoiSignals_MeanF, ...
                    signalArray.RoiSignals_NeuropilF );
                signalArray = permute( signalArray, [1,3,2] );
            else
                signalArray = signalArray.RoiSignals_MeanF;
                signalArray = reshape(signalArray, size(signalArray, 1), 1, []);
                if ~strcmp(obj.Parameters.dffFcn, 'dffClassic')
                    errMsg = sprintf('Neuropil signals are required for the method "%s", but were not available.', obj.Parameters.dffFcn );
                    error(errMsg);
                end
            end
            
            dff = computeDff(signalArray, obj.Parameters);
            obj.saveData('RoiSignals_Dff', dff) 
            
        end
        
        function wasSuccess = preview(obj) 
            h = openDffExplorer(obj.SessionObjects);
            wasSuccess = obj.finishPreview(h);
        end

        function printTask(obj, varargin)
            fprintf(varargin{:})
        end
        
    end

end



function hDffPlugin = openDffExplorer(sessionObj)

    % Load rois
    roiArray = sessionObj.loadData('RoiArray');
    
    % Load signals
    roiSignalTable = sessionObj.loadData('RoiSignals_MeanF');
    
    
    % Create roi group
    if isa(roiArray, 'roimanager.roiGroup')
        roiGroup = roiArray;
    else
        roiGroup = roimanager.roiGroup(roiArray);
    end
    
    % Open roitable app
    hTableViewer = roimanager.RoiTable(roiGroup);
    
    % Create a roi signal array....
    rs = nansen.roisignals.RoiSignalArrayExtracted(roiSignalTable, roiGroup);

    % Open roi signalviewer app
    hSignalviewer = roisignalviewer.App(rs);
    hSignalviewer.RoiGroup = roiGroup;
    hSignalviewer.showSignal('dff')
    hSignalviewer.showLegend()
    
    % Open the dff options
    hDffPlugin = nansen.plugin.signalviewer.DffExplorer(hSignalviewer, [], 'Modal', false);
    
    % Position apps on screen
    hSignalviewer.place('bottom')
    hTableViewer.place('left')
    hTableViewer.place('bottom', hSignalviewer.Figure.OuterPosition(4) + 5)
    hDffPlugin.place('left', hTableViewer.Figure.OuterPosition(3) + 5)
    hDffPlugin.place('bottom', hSignalviewer.Figure.OuterPosition(4) + 5)
        
    % Cleanup up if plugin is deleted.
    addlistener(hDffPlugin, 'ObjectBeingDestroyed', @(s,e) delete(hSignalviewer));
    addlistener(hDffPlugin, 'ObjectBeingDestroyed', @(s,e) delete(hTableViewer));
    
    hDffPlugin.waitfor()
    
end

