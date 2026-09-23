classdef OptionsEditor < handle
%nansen.options.ui.OptionsEditor Edit options and manage profiles of a method
%
%   editor = nansen.options.ui.OptionsEditor(manager) opens an editor for
%   the options of the method managed by manager (nansen.options.Manager).
%
%   The editor shows the profiles of the method (defaults, presets and
%   user profiles) and the parameters of the selected profile, grouped in
%   tabs. Parameters are edited with controls matching their type, show
%   descriptions and units as tooltips, and are validated when changed.
%   Modified values are shown in bold, and invalid values in red.
%
%   Profiles can be saved, saved as new profiles (deriving from the
%   current profile), renamed, deleted and set as default.
%
%   editor = nansen.options.ui.OptionsEditor(manager, Name=Value)
%
%   NAME-VALUE ARGUMENTS:
%       Profile : Name of profile to show initially (default: default profile)
%       Values  : Values to show initially (default: values of profile)
%       Title   : Title of window
%
%   [values, wasCanceled] = editor.waitForResult() blocks until the user
%   presses OK or Cancel, and returns the values.
%
%   See also nansen.options.Manager/edit

    properties (SetAccess = private)
        Manager nansen.options.Manager {mustBeScalarOrEmpty} = nansen.options.Manager.empty
        ProfileName (1,1) string = ""       % Name of currently selected profile
        Values (1,1) struct = struct()      % Current (edited) values
        WasCanceled (1,1) logical = true    % Whether the editor was canceled
    end

    properties (Dependent, SetAccess = private)
        IsModified (1,1) logical            % Whether values differ from saved profile
        HasInvalidValues (1,1) logical      % Whether any edited values are invalid
    end

    properties (Access = private)
        Figure matlab.ui.Figure {mustBeScalarOrEmpty} = matlab.ui.Figure.empty
        HeaderLabel
        ProfileList
        ShowAdvancedCheckbox
        TabGroup
        StatusLabel
        Buttons (1,1) struct = struct()
        Controls = struct("Name", {}, "Label", {}, "Read", {}, "BaseTooltip", {})
        SavedValues (1,1) struct = struct() % Values of selected profile as saved
        InitialValues (1,1) struct = struct() % Values when editor was opened
        InvalidNames (1,:) string = string.empty(1, 0)
        IsWaiting (1,1) logical = false
    end

    properties (Constant, Access = private)
        ROW_HEIGHT = 26
        MULTILINE_ROW_HEIGHT = 70
        INVALID_COLOR = [0.85, 0.2, 0.2]
    end

    methods % Constructor / destructor

        function obj = OptionsEditor(manager, options)
            arguments
                manager (1,1) nansen.options.Manager
                options.Profile (1,1) string = manager.DefaultProfileName
                options.Values struct {mustBeScalarOrEmpty} = struct([])
                options.Title (1,1) string = ""
            end

            obj.Manager = manager;

            title = options.Title;
            if title == ""
                title = "Options: " + manager.Schema.DisplayTitle;
            end

            obj.createComponents(title)
            obj.selectProfile(options.Profile, options.Values)
            obj.InitialValues = obj.Values;
        end

        function delete(obj)
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure)
            end
        end
    end

    methods
        function [values, wasCanceled] = waitForResult(obj)
        %waitForResult Wait until user presses OK or Cancel
        %
        %   [values, wasCanceled] = editor.waitForResult() returns the
        %   values when OK was pressed, or the initial values if canceled.
            obj.IsWaiting = true;
            uiwait(obj.Figure)

            wasCanceled = obj.WasCanceled;
            if wasCanceled
                values = obj.InitialValues;
            else
                values = obj.Values;
            end
            delete(obj)
        end
    end

    methods % Get
        function tf = get.IsModified(obj)
            tf = ~isequaln(obj.Values, obj.SavedValues);
        end

        function tf = get.HasInvalidValues(obj)
            tf = ~isempty(obj.InvalidNames);
        end
    end

    methods (Access = private) % Create components

        function createComponents(obj, title)
            obj.Figure = uifigure(Name=title, Position=[100, 100, 920, 580], ...
                CloseRequestFcn=@(~, ~) obj.finish(true));

            mainGrid = uigridlayout(obj.Figure, [1, 2], ColumnWidth={230, '1x'});

            % Profiles
            leftGrid = uigridlayout(mainGrid, [4, 1], Padding=[0, 0, 0, 0], ...
                RowHeight={22, '1x', 28, 28});
            uilabel(leftGrid, Text="Profiles", FontWeight="bold");
            obj.ProfileList = uilistbox(leftGrid, ...
                ValueChangedFcn=@(~, event) obj.onProfileSelected(event));

            profileButtons = uigridlayout(leftGrid, [1, 2], Padding=[0, 0, 0, 0]);
            obj.Buttons.SetDefault = uibutton(profileButtons, Text="Set as default", ...
                Tooltip="Use this profile when no profile is specified", ...
                ButtonPushedFcn=@(~, ~) obj.onSetDefault());
            obj.Buttons.Rename = uibutton(profileButtons, Text="Rename", ...
                ButtonPushedFcn=@(~, ~) obj.onRename());

            profileButtons2 = uigridlayout(leftGrid, [1, 2], Padding=[0, 0, 0, 0]);
            obj.Buttons.Delete = uibutton(profileButtons2, Text="Delete", ...
                ButtonPushedFcn=@(~, ~) obj.onDelete());
            obj.Buttons.Reset = uibutton(profileButtons2, Text="Revert changes", ...
                Tooltip="Revert to the saved values of the profile", ...
                ButtonPushedFcn=@(~, ~) obj.onReset());

            % Parameters
            rightGrid = uigridlayout(mainGrid, [4, 1], Padding=[0, 0, 0, 0], ...
                RowHeight={'fit', 22, '1x', 28});

            obj.HeaderLabel = uilabel(rightGrid, WordWrap="on", ...
                Text=obj.getHeaderText());
            obj.ShowAdvancedCheckbox = uicheckbox(rightGrid, ...
                Text="Show advanced options", Value=false, ...
                ValueChangedFcn=@(~, ~) obj.createParameterControls());
            obj.TabGroup = uitabgroup(rightGrid);

            footerGrid = uigridlayout(rightGrid, [1, 5], Padding=[0, 0, 0, 0], ...
                ColumnWidth={'1x', 90, 90, 90, 90});
            obj.StatusLabel = uilabel(footerGrid, Text="");
            obj.Buttons.Save = uibutton(footerGrid, Text="Save", ...
                ButtonPushedFcn=@(~, ~) obj.onSave());
            obj.Buttons.SaveAs = uibutton(footerGrid, Text="Save as...", ...
                ButtonPushedFcn=@(~, ~) obj.onSaveAs());
            obj.Buttons.Cancel = uibutton(footerGrid, Text="Cancel", ...
                ButtonPushedFcn=@(~, ~) obj.finish(true));
            obj.Buttons.OK = uibutton(footerGrid, Text="OK", FontWeight="bold", ...
                ButtonPushedFcn=@(~, ~) obj.onOK());
        end

        function text = getHeaderText(obj)
            schema = obj.Manager.Schema;
            text = sprintf("%s (version %s)", schema.DisplayTitle, schema.Version);
            if schema.Description ~= ""
                text = text + newline + schema.Description;
            end
        end

        function updateProfileList(obj)
            names = obj.Manager.ProfileNames;
            defaultName = obj.Manager.DefaultProfileName;

            labels = names;
            isPreset = ismember(names, obj.Manager.Schema.PresetNames);
            labels(isPreset) = labels(isPreset) + "  [preset]";
            isDefault = names == defaultName;
            labels(isDefault) = labels(isDefault) + "  (default)";

            obj.ProfileList.Items = cellstr(labels);
            obj.ProfileList.ItemsData = cellstr(names);
            obj.ProfileList.Value = char(obj.ProfileName);
        end

        function createParameterControls(obj)
        %createParameterControls Create tabs and controls for all parameters

            delete(obj.TabGroup.Children)
            obj.Controls = obj.Controls([]);
            obj.InvalidNames = string.empty(1, 0);

            schema = obj.Manager.Schema;
            parameters = schema.Parameters;
            if isempty(parameters); return; end

            parameters = parameters(~[parameters.Internal]);
            if ~obj.ShowAdvancedCheckbox.Value && ~isempty(parameters)
                parameters = parameters(~[parameters.Advanced]);
            end
            if isempty(parameters); return; end

            groupNames = string(arrayfun(@getTopLevelGroup, parameters, UniformOutput=false));

            for groupName = unique(groupNames, "stable")
                groupParameters = parameters(groupNames == groupName);

                if groupName == ""
                    tabTitle = "General";
                else
                    tabTitle = regexprep(groupName, "([a-z0-9])([A-Z])", "$1 $2");
                end
                tab = uitab(obj.TabGroup, Title=tabTitle, ...
                    Tooltip=schema.getGroupDescription(groupName));

                isMultiline = [groupParameters.Widget] == "multiline";
                rowHeights = repmat({obj.ROW_HEIGHT}, 1, numel(groupParameters));
                rowHeights(isMultiline) = {obj.MULTILINE_ROW_HEIGHT};

                grid = uigridlayout(tab, [numel(groupParameters), 3], ...
                    ColumnWidth={'1x', '1.4x', 70}, RowHeight=rowHeights, ...
                    Scrollable="on");

                for i = 1:numel(groupParameters)
                    obj.createParameterRow(grid, i, groupParameters(i), groupName)
                end
            end

            obj.updateState()
        end

        function createParameterRow(obj, grid, row, parameter, groupName)

            labelText = parameter.DisplayLabel;
            if groupName ~= ""
                subgroups = split(extractAfter(parameter.Name, groupName + "."), ".");
                if numel(subgroups) > 1
                    labelText = strjoin(subgroups(1:end-1), " / ") + " / " + labelText;
                end
            end
            if parameter.IsDeprecated
                labelText = labelText + " (deprecated)";
            end

            tooltip = parameter.Description;
            if parameter.Units ~= ""
                tooltip = tooltip + " [" + parameter.Units + "]";
            end
            if parameter.Transient
                tooltip = tooltip + newline + "(Does not affect results)";
            end
            if parameter.IsDeprecated
                tooltip = tooltip + newline + "Deprecated: " + parameter.Deprecated;
            end
            tooltip = strtrim(tooltip);

            label = uilabel(grid, Text=labelText, Tooltip=tooltip);
            label.Layout.Row = row;
            label.Layout.Column = 1;
            if parameter.IsDeprecated; label.FontAngle = "italic"; end

            value = nansen.options.internal.getValue(obj.Values, parameter.Name);
            onChange = @() obj.onValueChanged(parameter.Name);
            [control, readFcn] = createControl(grid, parameter, value, onChange);
            control.Layout.Row = row;
            control.Layout.Column = 2;

            unitsLabel = uilabel(grid, Text=parameter.Units, FontColor=[0.4, 0.4, 0.4]);
            unitsLabel.Layout.Row = row;
            unitsLabel.Layout.Column = 3;

            obj.Controls(end+1) = struct("Name", parameter.Name, "Label", label, ...
                "Read", readFcn, "BaseTooltip", tooltip);
        end
    end

    methods (Access = private) % State

        function selectProfile(obj, name, values)
            arguments
                obj
                name (1,1) string
                values struct {mustBeScalarOrEmpty} = struct([])
            end

            % Resolve values, and show any warnings (e.g. changed defaults)
            [lastMessage, lastId] = lastwarn();
            lastwarn("")
            savedValues = obj.Manager.resolve(name);
            [message, id] = lastwarn();
            if id == "NANSEN:Options:InheritedValuesChanged"
                uialert(obj.Figure, message, "Values have changed", Icon="warning");
            elseif id == ""
                lastwarn(lastMessage, lastId)
            end

            obj.ProfileName = name;
            obj.SavedValues = savedValues;
            if isempty(values)
                obj.Values = savedValues;
            else
                obj.Values = obj.Manager.Schema.conform(values);
            end

            obj.updateProfileList()
            obj.createParameterControls()
        end

        function updateState(obj)
        %updateState Update labels, status and buttons

            for control = obj.Controls
                if ismember(control.Name, obj.InvalidNames)
                    continue % Keep invalid formatting
                end
                isModified = ~isequaln( ...
                    nansen.options.internal.getValue(obj.Values, control.Name), ...
                    nansen.options.internal.getValue(obj.SavedValues, control.Name));
                if isModified
                    control.Label.FontWeight = "bold";
                else
                    control.Label.FontWeight = "normal";
                end
            end

            profile = obj.Manager.getProfile(obj.ProfileName);

            if obj.HasInvalidValues
                obj.StatusLabel.Text = sprintf("%d invalid value(s)", numel(obj.InvalidNames));
                obj.StatusLabel.FontColor = obj.INVALID_COLOR;
            elseif obj.IsModified
                obj.StatusLabel.Text = "Modified (not saved)";
                obj.StatusLabel.FontColor = [0, 0, 0];
            else
                obj.StatusLabel.Text = "";
            end

            canSave = ~obj.HasInvalidValues;
            obj.Buttons.Save.Enable = canSave && obj.IsModified && ~profile.IsReadOnly;
            obj.Buttons.SaveAs.Enable = canSave;
            obj.Buttons.OK.Enable = canSave;
            obj.Buttons.Reset.Enable = obj.IsModified;
            obj.Buttons.Delete.Enable = ~profile.IsReadOnly;
            obj.Buttons.Rename.Enable = ~profile.IsReadOnly;
            obj.Buttons.SetDefault.Enable = obj.ProfileName ~= obj.Manager.DefaultProfileName;
        end

        function finish(obj, wasCanceled)
            obj.WasCanceled = wasCanceled;
            if obj.IsWaiting
                uiresume(obj.Figure)
            else
                delete(obj)
            end
        end
    end

    methods (Access = private) % Callbacks

        function onValueChanged(obj, name)
            idx = find([obj.Controls.Name] == name, 1);
            control = obj.Controls(idx);
            parameter = obj.Manager.Schema.getParameter(name);

            try
                value = parameter.coerce(control.Read());
                [isValid, message] = parameter.validate(value);
            catch ME
                isValid = false;
                message = string(ME.message);
            end

            if isValid
                obj.Values = nansen.options.internal.setValue(obj.Values, name, value);
                obj.InvalidNames = setdiff(obj.InvalidNames, name, "stable");
                control.Label.FontColor = [0, 0, 0];
                control.Label.Tooltip = control.BaseTooltip;
            else
                obj.InvalidNames = union(obj.InvalidNames, name, "stable");
                control.Label.FontColor = obj.INVALID_COLOR;
                control.Label.Tooltip = message;
            end

            obj.updateState()
        end

        function onProfileSelected(obj, event)
            if obj.IsModified && ~obj.confirmDiscardChanges()
                obj.ProfileList.Value = event.PreviousValue;
                return
            end
            obj.selectProfile(string(event.Value))
        end

        function onSave(obj)
            try
                obj.Manager.updateProfile(obj.ProfileName, obj.Values);
                obj.selectProfile(obj.ProfileName)
            catch ME
                uialert(obj.Figure, ME.message, "Could not save profile")
            end
        end

        function onSaveAs(obj)
            answer = inputdlg({'Name of new profile:', 'Description (optional):'}, ...
                'Save profile as', [1, 50; 3, 50]);
            if isempty(answer); return; end

            name = strtrim(string(answer{1}));
            description = strjoin(string(cellstr(answer{2})), newline);

            % The new profile derives from the current profile
            parentName = obj.ProfileName;
            if parentName == obj.Manager.Schema.DEFAULTS_NAME; parentName = ""; end

            try
                obj.Manager.createProfile(name, obj.Values, ...
                    Parent=parentName, Description=description);
                obj.selectProfile(name)
            catch ME
                uialert(obj.Figure, ME.message, "Could not save profile")
            end
        end

        function onRename(obj)
            answer = inputdlg({'New name:'}, 'Rename profile', [1, 50], cellstr(obj.ProfileName));
            if isempty(answer); return; end
            try
                newName = strtrim(string(answer{1}));
                obj.Manager.renameProfile(obj.ProfileName, newName);
                obj.ProfileName = newName;
                obj.updateProfileList()
            catch ME
                uialert(obj.Figure, ME.message, "Could not rename profile")
            end
        end

        function onDelete(obj)
            selection = uiconfirm(obj.Figure, ...
                sprintf("Delete profile ""%s""? This can not be undone.", obj.ProfileName), ...
                "Delete profile", Options={'Delete', 'Cancel'}, ...
                DefaultOption="Cancel", CancelOption="Cancel", Icon="warning");
            if selection ~= "Delete"; return; end

            try
                obj.Manager.deleteProfile(obj.ProfileName);
                obj.selectProfile(obj.Manager.DefaultProfileName)
            catch ME
                uialert(obj.Figure, ME.message, "Could not delete profile")
            end
        end

        function onSetDefault(obj)
            obj.Manager.setDefaultProfile(obj.ProfileName);
            obj.updateProfileList()
            obj.updateState()
        end

        function onReset(obj)
            obj.Values = obj.SavedValues;
            obj.createParameterControls()
        end

        function onOK(obj)
            if obj.HasInvalidValues
                uialert(obj.Figure, "Please correct invalid values first.", "Invalid values")
                return
            end
            obj.finish(false)
        end

        function tf = confirmDiscardChanges(obj)
            selection = uiconfirm(obj.Figure, ...
                sprintf("Discard unsaved changes to ""%s""?", obj.ProfileName), ...
                "Unsaved changes", Options={'Discard', 'Cancel'}, ...
                DefaultOption="Cancel", CancelOption="Cancel");
            tf = selection == "Discard";
        end
    end
end

function groupName = getTopLevelGroup(parameter)
    if contains(parameter.Name, ".")
        groupName = extractBefore(parameter.Name, ".");
    else
        groupName = "";
    end
end

function [control, readFcn] = createControl(parent, parameter, value, onChange)
%createControl Create a control for editing a parameter value
%
%   Returns the control and a function that reads the value from it.

    import nansen.options.ParameterType

    callback = @(~, ~) onChange();

    switch parameter.Type
        case ParameterType.Logical
            if isscalar(value)
                control = uicheckbox(parent, Text="", Value=value, ValueChangedFcn=callback);
                readFcn = @() control.Value;
            else
                [control, readFcn] = createArrayField(parent, value, callback);
            end

        case ParameterType.Choice
            labels = cellfun(@choiceLabel, parameter.Choices, UniformOutput=false);
            isSelected = cellfun(@(c) isequal(string(c), string(value)), parameter.Choices);
            control = uidropdown(parent, Items=labels, ItemsData=parameter.Choices, ...
                ValueChangedFcn=callback);
            if any(isSelected)
                control.Value = parameter.Choices{find(isSelected, 1)};
            end
            readFcn = @() control.Value;

        case ParameterType.Numeric
            if parameter.Widget == "color" && numel(value) == 3
                [control, readFcn] = createColorButton(parent, value, callback);
            elseif ~isscalar(value) || ~isfinite(value)
                % Numeric fields do not support NaN
                [control, readFcn] = createArrayField(parent, value, callback);
            elseif parameter.Widget == "slider" && isfinite(parameter.Min) && isfinite(parameter.Max)
                control = uislider(parent, Limits=[parameter.Min, parameter.Max], ...
                    Value=double(value), ValueChangedFcn=callback);
                if parameter.Integer
                    readFcn = @() round(control.Value);
                else
                    readFcn = @() control.Value;
                end
            else
                control = uieditfield(parent, "numeric", Value=double(value), ...
                    ValueChangedFcn=callback);
                if parameter.Min < parameter.Max
                    control.Limits = [parameter.Min, parameter.Max];
                end
                if parameter.Integer
                    control.RoundFractionalValues = "on";
                end
                readFcn = @() control.Value;
            end

        case ParameterType.Text
            if parameter.Widget == "multiline"
                control = uitextarea(parent, Value=cellstr(splitlines(string(value))), ...
                    ValueChangedFcn=callback);
                readFcn = @() strjoin(string(control.Value), newline);
            elseif any(parameter.Widget == ["folder", "file"])
                [control, readFcn] = createPathField(parent, value, parameter.Widget, callback);
            else
                control = uieditfield(parent, "text", Value=char(value), ValueChangedFcn=callback);
                readFcn = @() control.Value;
            end

        case ParameterType.List
            if iscellstr(value) || isstring(value) %#ok<ISCLSTR>
                control = uieditfield(parent, "text", Value=char(strjoin(string(value), ", ")), ...
                    Tooltip="Comma separated list", ValueChangedFcn=callback);
                readFcn = @() parseList(control.Value);
            else
                [control, readFcn] = createReadOnlyField(parent, value);
            end

        case ParameterType.Function
            if isa(value, "function_handle"); value = func2str(value); end
            control = uieditfield(parent, "text", Value=char(value), ValueChangedFcn=callback);
            readFcn = @() str2func(control.Value);

        otherwise
            [control, readFcn] = createReadOnlyField(parent, value);
    end
end

function [control, readFcn] = createArrayField(parent, value, callback)
    control = uieditfield(parent, "text", Value=mat2str(value), ...
        Tooltip="MATLAB array syntax, e.g. [1, 2, 3]", ValueChangedFcn=callback);
    readFcn = @() parseArray(control.Value, class(value));
end

function [control, readFcn] = createPathField(parent, value, widget, callback)
    control = uigridlayout(parent, [1, 2], Padding=[0, 0, 0, 0], ColumnWidth={'1x', 30});
    field = uieditfield(control, "text", Value=char(value), ValueChangedFcn=callback);
    uibutton(control, Text="...", ...
        ButtonPushedFcn=@(~, ~) browseForPath(field, widget, callback));
    readFcn = @() field.Value;
end

function browseForPath(field, widget, callback)
    if widget == "folder"
        selection = uigetdir(field.Value);
        if isequal(selection, 0); return; end
        field.Value = selection;
    else
        [fileName, folder] = uigetfile("*.*", "Select file", field.Value);
        if isequal(fileName, 0); return; end
        field.Value = fullfile(folder, fileName);
    end
    callback([], [])
end

function [control, readFcn] = createColorButton(parent, value, callback)
    control = uibutton(parent, Text="", BackgroundColor=double(value));
    control.ButtonPushedFcn = @(~, ~) pickColor(control, callback);
    readFcn = @() control.BackgroundColor;
end

function pickColor(button, callback)
    color = uisetcolor(button.BackgroundColor);
    if isequal(color, 0); return; end
    button.BackgroundColor = color;
    callback([], [])
end

function [control, readFcn] = createReadOnlyField(parent, value)
    control = uilabel(parent, Text=nansen.options.internal.valueToString(value), ...
        Tooltip="This value can not be edited here", FontColor=[0.4, 0.4, 0.4]);
    readFcn = @() value;
end

function label = choiceLabel(choice)
    if nansen.options.internal.isText(choice)
        label = char(choice);
    else
        label = char(nansen.options.internal.valueToString(choice));
    end
end

function value = parseArray(text, className)
    [value, wasSuccess] = str2num(text); %#ok<ST2NM> Allows MATLAB array syntax
    if ~wasSuccess
        error("NANSEN:Options:InvalidValue", "Could not parse ""%s"" as an array", text)
    end
    if className == "logical"
        value = logical(value);
    end
end

function values = parseList(text)
    values = strtrim(split(string(text), ","))';
    values(values == "") = [];
end
