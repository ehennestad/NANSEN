classdef MetaTableViewer < handle & uiw.mixin.AssignPVPairs
%MetaTableViewer Implementation of UI table for viewing metadata tables.
%
%   This class is built around the Table class from the Widgets Toolbox.
%   This is a very responsive java based table implementation. This class
%   extends the functionality of the uiw.widget.Table in primarily two
%   ways:
%       1) Columns can be filtered
%       2) Settings for columns are saved until next time table is opened.
%           (Columns widths, column visibility and column label is saved
%           across matlab sessions) Todo: Also save column editable...

    
% - - - - - - - - - - - - - - - TODO - - - - - - - - - - - - - - - - -
    %  *[ ] Update table without emptying data! Use add column/remove
    %   [ ] jTable.setPreserveSelectionsAfterSorting(true); Is this useful
    %       here???
    %   [ ] Save table settings to project folder

    %       column from the java column model when hiding/showing columns
    %   [ ] Outsource everything column related to column model
    %   [ ] Create table with all columns and store the tablecolumn objects in the column model if rows are hidden? 
    %
    %   [x] Make ignore column editable 
    %   [x] Set method for metaTable...
    %   [x] Revert change from metatable. need to get formatted data from
    %       table!
    %   [ ] Should the filter be a RowModel?
    %   [ ] Straighten out what to do about the MetaTable property.
    %       Problem: if the input metatable was a MetaTable object, it
    %       might contain data which is not renderable in the uitable, i.e
    %       structs. If table data is changed, and data is put back into
    %       the table version of the MetaTable, the set.MetaTable methods
    %       creates a downstream bug because it sets it, and consequently
    %       the MetaTableCell property without getting formatted data from
    %       the metatable class. For now, I keep as it is, because the only
    %       column I edit is the ignore column, and the MetaTable property
    %       is not used anywhere. But this can be a BIG PROBLEM if things
    %       change some time.
    
% - - - - - - - - - - - - - - PROPERTIES - - - - - - - - - - - - - - - 

    properties (Constant, Hidden)
        VALID_TABLE_CLASS = {'nansen.metadata.MetaTable', 'table'};
    end
    
    properties % Table preferences
        ShowIgnoredEntries = true
        AllowTableEdits = true
        MetaTableType = 'session'
    end
    
    properties
        SelectedEntries         % Selected rows from full table, irrespective of sorting and filtering.
        CellEditCallback
        KeyPressCallback
        
        MouseDoubleClickedFcn = [] % This should be internalized, but for now it is assigned from session browser/nansen
        
        DeleteColumnFcn = []    % This should be internalized, but for now it is assigned from session browser/nansen
        UpdateColumnFcn = []    % This should be internalized, but for now it is assigned from session browser/nansen
    end
    
    properties (SetAccess = private, SetObservable = true)
        MetaTable               % Table version of the table data
        MetaTableCell cell      % Cell array version of the table data
        MetaTableVariableNames  % Cell array of variable names in full table
        MetaTableVariableAttributes % Struct with attributes of metatable variables.
    end
    
    properties (SetAccess = private)
        ColumnModel             % Class instance for updating columns based on user preferences.
        ColumnFilter            % Class instance for filtering data based on column variables.
    end
    
    properties %(Access = private)
        DisplayedRows % Rows of the original metatable which are currently displayed (not implemented yet)
        DisplayedColumns % Columns of the original metatable which are currently displayed (not implemented yet)
        
        AppRef
        Parent
        HTable
        JTable
        
        ColumnContextMenu = []
        TableContextMenu = []
        
        DataFilterMap = []  % Boolean "map" (numRows x numColumns) with false for cells that is outside filter range
        ExternalFilterMap = [] % Boolean vector with rows that are "filtered" externally. Todo: Formalize this better.
        FilterChangedListener event.listener
        
        ColumnWidthChangedListener
        ColumnsRearrangedListener
        MouseDraggedInHeaderListener
        
        ColumnPressedTimer
    end
    
    properties (Access = private)
        lastMousePressTic
        isConstructed = false;
    end
    
    events
        TableUpdated
    end
    
    
% - - - - - - - - - - - - - - - METHODS - - - - - - - - - - - - - - - 
    
    methods % Structors
        
        function obj = MetaTableViewer(varargin)
        %MetaTableViewer Construct for MetaTableViewer
        
            % Take care of input arguments.
            obj.parseInputs(varargin)
            
            % Initialize the column model.
            obj.ColumnModel = nansen.ui.MetaTableColumnLayout(obj);
            
            obj.createUiTable()
            
            obj.ColumnFilter = nansen.ui.MetaTableColumnFilter(obj, obj.AppRef);
            
            if ~isempty(obj.MetaTableCell)
                obj.refreshTable()
                obj.HTable.Visible = 'on'; % Make table visible
                drawnow
            end
        end
       
        function delete(obj)
            if ~isempty(obj.HTable) && isvalid(obj.HTable)
                columnWidths = obj.HTable.ColumnWidth;
                obj.ColumnModel.setColumnWidths(columnWidths);
            
                delete(obj.ColumnModel)
                
                delete(obj.HTable)
            end
        end
        
    end
    
    methods % Set/get
        
        function set.MetaTable(obj, newTable)
        % Set method for metatable. 
        %
        % 1) If the newValue is a MetaTable object, the table data is
        %    retrieved before updating the property. 
        % 2) After new value is set it is passed on the onMetaTableSet 
        %    method which will also update the metaTableCell property and
        %    update the ui table.
        
            if isa(newTable, 'nansen.metadata.MetaTable')
                obj.MetaTable = newTable.entries;
            elseif isa(newTable, 'table')
                obj.MetaTable = newTable;
            else
                error('New value of MetaTable property must be a MetaTable or a table object')
            end
            
            obj.onMetaTableSet(newTable)
            
        end
       
        function set.ColumnFilter(obj, newValue)
            obj.ColumnFilter = newValue;
            if ~isempty(newValue)
                obj.onColumnFilterSet()
            end
        end
            
        function set.ShowIgnoredEntries(obj, newValue)
            
            assert(islogical(newValue), 'Value for ShowIgnoredEntries must be a boolean')
            obj.ShowIgnoredEntries = newValue;
            
            obj.refreshTable()

        end
        
        function set.AllowTableEdits(obj, newValue)
            
            assert(islogical(newValue), 'Value for AllowTableEdits must be a boolean')
            obj.AllowTableEdits = newValue;
                      
            obj.updateColumnEditable()

        end
        
        function set.KeyPressCallback(obj, newValue)
            
        end
    end
        
    methods % Public methods
        
        function refreshColumnModel(obj)
        %refreshColumnModel Refresh the columnmodel 
        %
        %   Note: This method should be called whenever a new metatable is
        %   set, and whenever a metatable variable definition is changed.
        %
        %   Todo: {Find a way to make this happen when it is needed, instead
        %   of requiring this method to be called explicitly. This fix need
        %   to be implemented on the class (table model) owning the 
        %   columnmodel}
            
            obj.ColumnModel.updateColumnEditableState()
        end
        
        function resetTable(obj)
            obj.MetaTable = table.empty;
        end
        
        function resetColumnFilters(obj)
            obj.ColumnFilter.resetFilters()
        end
        
        function updateCells(obj, rowIdx, colIdx, newData)
        %updateCells Update subset of cells...
        
            obj.MetaTableCell(rowIdx, colIdx) = newData;
            
            % Todo: Need to find the corresponding cell in the viewable
            % table...
            
            % Get based on user selection of which columns to display
            colIdxVisible = obj.getCurrentColumnSelection();
            
            % Get based on filter states
            rowIdxVisible = obj.getCurrentRowSelection();
            
            % Get the row taking the table sorting into account:
            %dataInd = get(obj.HTable.JTable.Model, 'Indexes');

            if ~isempty(obj.HTable.RowSortIndex)
                rowIdxVisible = rowIdxVisible(obj.HTable.RowSortIndex);
            end
            
            tableDataView = newData(:, colIdxVisible);

            % Rearrange columns according to current state of the java 
            % column model
            [javaColIndex, ~] = obj.ColumnModel.getColumnModelIndexOrder();
            javaColIndex = javaColIndex(1:numel(colIdxVisible));
            tableDataView(:, javaColIndex) = tableDataView;
            
            [~, uiTableRowIdx] = intersect(rowIdxVisible, rowIdx, 'stable');
            [~, uiTableColIdx] = intersect(colIdxVisible, colIdx, 'stable');
            
            for i = 1:numel(uiTableRowIdx)
                for j = 1:numel(uiTableColIdx)
                    iRow = uiTableRowIdx(i);
                    jCol = uiTableColIdx(j);
                    thisValue = tableDataView(i, j);
                    obj.HTable.setCell(iRow, jCol, thisValue)
                end
            end
            
            drawnow
            return
            
            % Assign updated table data to the uitable property
            obj.HTable.Data = tableDataView;
            
            
            
            
            [~, uiTableRowIdx] = intersect(rowIdxVisible, rowIdx, 'stable');
            [~, uiTableColIdx] = intersect(colIdxVisible, colIdx, 'stable');
            
            
            % This is ad hoc, seems to work, but need to understand
            % better what is going on here (todo)!
            if numel(colIdx) == 1
                columnIndexOrder = obj.ColumnModel.getColumnModelIndexOrder();
                uiTableColIdx = columnIndexOrder(uiTableColIdx);
            end
            columnIndexOrder = obj.ColumnModel.getColumnModelIndexOrder();

            % Rearrange data table columns...
            [~, ~, dataTableColIdx] = intersect(colIdxVisible, columnIndexOrder);
                        
            % Only continue with those columns that are visible
            newData = newData(:, dataTableColIdx);

            for i = 1:numel(uiTableRowIdx)
                for j = 1:numel(uiTableColIdx)
                    iRow = uiTableRowIdx(i);
                    jCol = uiTableColIdx(j);
                    thisValue = newData(i, j);
                    obj.HTable.setCell(iRow, jCol, thisValue)
                end
            end
            
            %obj.HTable.setCell(uiTableRowIdx, uiTableColIdx, newData)
            %obj.HTable.Data(uiTableRowIdx, uiTableColIdx) = newData;
            drawnow
            
        end
        
        function updateTableRow(obj, rowIdx, tableRowData)
        %updateTableRow Update data of specified table row                      
            % Count number of columns and get column indices
            colIdx = 1:size(tableRowData, 2);
            
            if isa(tableRowData, 'table')
                newData = table2cell(tableRowData);
            elseif isa(tableRowData, 'cell')
                %pass
            else
                error('Table row data is in the wrong format')
            end
            
            % Refresh cells of ui table...
            obj.updateCells(rowIdx, colIdx, newData)
        end        
        
        function appendTableRow(obj, rowData)
            % Would be neat, but havent found a way to do it.
        end
        
        function updateVisibleRows(obj, rowInd)

            [numRows, ~] = size(obj.MetaTable);
            obj.ExternalFilterMap = false(numRows, 1);
            obj.ExternalFilterMap(rowInd) = true;
            
            obj.updateTableView(rowInd)
        end
        
        function refreshTable(obj, newTable, flushTable)
        %refreshTable Method for refreshing the table
        
            % TODO: Make sure the selection is maintained.
            
            % Note: If [] is provided as 2nd arg, the table is not reset.
            % This might be used in some cases where the table should be
            % kept, but the flushTable flag is provided.
            
            if nargin >= 2 && ~(isnumeric(newTable) && isempty(newTable))
                obj.MetaTable = newTable;
            end
            
            if nargin < 3
                flushTable = false;
            end
            
            % Todo: Save selection
            %selectedEntries = obj.getSelectedEntries();

            if flushTable % Empty table, gives smoother update in some cases
                obj.HTable.Data = {};
                obj.DataFilterMap = []; % reset data filter map
                obj.ColumnFilter.onMetaTableChanged()
            else
                if ~isempty(obj.ColumnFilter)
                    obj.ColumnFilter.onMetaTableUpdated()
                end
            end
            
            drawnow
            obj.updateColumnLayout()
            obj.updateTableView()
            
            drawnow
            % Todo: Restore selection
            %obj.setSelectedEntries(selectedEntries);
            
        end
        
        function replaceTable(obj, newTable)
            obj.MetaTable = newTable;
            obj.ColumnFilter.onMetaTableChanged()
            obj.updateTableView()
        end
        
        function rowInd = getMetaTableRows(obj, rowIndDisplay)
            
            % Todo: Determine if this method is useful in 
            % getSelectedEntries/setSelectedEntries?
            dataInd = get(obj.HTable.JTable.Model, 'Indexes');
            
            if ~isempty(dataInd)
                rowInd = dataInd(rowIndDisplay)+1; % +1 because java indices start at 0
            else
                rowInd = rowIndDisplay; 
            end
      
            % Get currently visible row and column indices.
            visibleRowInd = obj.getCurrentRowSelection();
            
            % Get row and column indices for original data (unfiltered, unsorted, allcolumns)
            rowInd = visibleRowInd(rowInd);
            
            % Make sure output is a column vector
            if iscolumn(rowInd)
                rowInd = transpose(rowInd);
            end
            
        end
        
        function IND = getSelectedEntries(obj)
        %getSelectedEntries Get selected entries based on the MetaTable
        %
        %   Get selected entry from original metatable taking column
        %   sorting and filtering into account.
        
            IND = obj.HTable.SelectedRows;
            
            dataInd = get(obj.HTable.JTable.Model, 'Indexes');

            if ~isempty(dataInd)
                IND = dataInd(IND)+1; % +1 because java indices start at 0
                IND = transpose( double( sort(IND) ) ); % return as row vector
            else
                IND = IND; 
            end
            
            % Get currently visible row and column indices.
            visibleRowInd = obj.getCurrentRowSelection();
            
            % Get row and column indices for original data (unfiltered, unsorted, allcolumns)
            IND = visibleRowInd(IND);
        end
       
        function setSelectedEntries(obj, IND)
        %setSelectedEntries Set row selection
        
            % Get currently visible row indices.
            visibleRowInd = obj.getCurrentRowSelection();
            
            % Get row indices based on the underlying table model (taking sorting into account)
            dataInd = get(obj.HTable.JTable.Model, 'Indexes') + 1;
            if isempty(dataInd)
                dataInd = 1:numel(visibleRowInd);
            end
            
            % Reorder the visible row indices according to possible sort
            % order
            visibleRowInd = visibleRowInd(dataInd);
            
            % Find the rownumber corresponding to the given entries.
            selectedRows = find(ismember(visibleRowInd, IND));

            % Set the row selection
            obj.HTable.SelectedRows = selectedRows;
            
        end

    end
   
    methods (Access = private) % Create components
        
        function parseInputs(obj, listOfArgs)
         %parseInputs Input parser that checks for expected input classes
            
            [nvPairs, remainingArgs] = utility.getnvpairs(listOfArgs);
            
            % Need to set name value pairs first
            obj.assignPVPairs(nvPairs{:})
            
            
            if isempty(remainingArgs);    return;    end
            
            % Check if first argument is a graphical container
            % Todo: check that graphical object is an actual container...
            if isgraphics(remainingArgs{1})
                obj.Parent = remainingArgs{1};
                remainingArgs = remainingArgs(2:end);
            end
            
            if isempty(remainingArgs);    return;    end

            % Check if first argument in list is a valid metatable class
            if obj.isValidTableClass( remainingArgs{1} )
                obj.MetaTable = remainingArgs{1};
                remainingArgs = remainingArgs(2:end);
            end
            
            
            if isempty(remainingArgs);    return;    end

        end
        
        function createUiTable(obj)
            
            for i = 1:2
            
                try
                    obj.HTable = uim.widget.StylableTable(...
                        'Parent', obj.Parent,...
                        'Tag','MetaTable',...
                        'Editable', true, ...
                        'RowHeight', 30, ...
                        'FontSize', 8, ...
                        'FontName', 'helvetica', ...
                        'FontName', 'avenir next', ...
                        'SelectionMode', 'discontiguous', ...
                        'Sortable', true, ...
                        'Units','normalized', ...
                        'Position',[0 0.0 1 1], ...
                        'HeaderPressedCallback', @obj.onMousePressedInHeader, ...
                        'HeaderReleasedCallback', @obj.onMouseReleasedFromHeader, ...
                        'MouseClickedCallback', @obj.onMousePressedInTable, ...
                        'Visible', 'off', ...
                        'BackgroundColor', [1,1,0.5]);
                    break
                
                catch ME
                    switch ME.identifier
                        case 'MATLAB:Java:ClassLoad'
                            nansen.config.path.addUiwidgetsJarToJavaClassPath()
                        otherwise
                            rethrow(ME)
                    end
                end
            end
            
            if isempty(obj.HTable)
                tf = nansen.setup.isUiwidgetsOnJavapath();
                if ~tf
                    error('Failed to create the gui. Try to install to Widgets Toolbox v1.3.330 again')
                else
                    error('Nansen:MetaTableViewer:CorruptedJavaPath', ...
                        'uiwidget jar is on javapath, but table creation failed.')
                end
            end
            
            obj.HTable.CellEditCallback = @obj.onCellValueEdited;
            obj.HTable.JTable.getTableHeader().setReorderingAllowed(true);
            obj.JTable = obj.HTable.JTable;

            % Listener that detects if column widths change if user drags
            % column headers edges to resize columns.
            obj.ColumnWidthChangedListener = listener(obj.HTable, ...
                'ColumnWidthChanged', @obj.onColumnWidthChanged);
            
            obj.ColumnsRearrangedListener = listener(obj.HTable, ...
                'ColumnsRearranged', @obj.onColumnsRearranged);
            
            obj.MouseDraggedInHeaderListener = listener(obj.HTable, ...
                'MouseDraggedInHeader', @obj.onMouseDraggedInTableHeader);
            
            obj.HTable.Theme = uim.style.tableLight;
            
        end
        
        function createColumnContextMenu(obj)
        %createColumnContextMenu Create a context menu for columns
        
        % Note: This context menu is reused for all columns, but because
        % it's appeareance might depend on the column it is opened above,
        % some changes are done in the method openColumnContextMenu before
        % it is made visible. Also, a callback function is set there.
        
            hFigure = ancestor(obj.Parent, 'figure');
            
            % Create a context menu item for each of the different column
            % formats.

            obj.ColumnContextMenu = uicontextmenu(hFigure);
            
            % Create items of the menu for columns of char type
            hTmp = uimenu(obj.ColumnContextMenu, 'Label', 'Sort A-Z');
            hTmp.Tag = 'Sort Ascend';
            
            hTmp = uimenu(obj.ColumnContextMenu, 'Label', 'Sort Z-A');
            hTmp.Tag = 'Sort Descend';
            
% %             hTmp = uimenu(obj.ColumnContextMenu, 'Label', 'Filter...');
% %             hTmp.Tag = 'Filter';
% %             hTmp.Separator = 'on';
            
            hTmp = uimenu(obj.ColumnContextMenu, 'Label', 'Reset Filters');
            hTmp.Tag = 'Reset Filters';
            hTmp.Separator = 'on';
            
            hTmp = uimenu(obj.ColumnContextMenu, 'Label', 'Hide this column');
            hTmp.Tag = 'Hide Column';
            hTmp.Separator = 'on';
            
            hTmp = uimenu(obj.ColumnContextMenu, 'Label', 'Column settings...');
            hTmp.Tag = 'ColumnSettings';
            hTmp.MenuSelectedFcn = @(s,e) obj.ColumnModel.editSettings;
            
            
            hTmp = uimenu(obj.ColumnContextMenu, 'Label', 'Update column data');
            hTmp.Separator = 'on';
            hTmp.Tag = 'Update Column';
              hSubMenu = uimenu(hTmp, 'Label', 'Update selected rows');
              hSubMenu.Tag = 'Update selected rows';
              hSubMenu = uimenu(hTmp, 'Label', 'Update all rows');
              hSubMenu.Tag = 'Update all rows';
                
            hTmp = uimenu(obj.ColumnContextMenu, 'Label', 'Delete this column');
            hTmp.Tag = 'Delete Column';
            
        end
        
        function createColumnFilterComponents(obj)
            % todo
        end
        
    end
    
    methods (Access = {?nansen.MetaTableViewer, ?nansen.ui.MetaTableColumnLayout, ?nansen.ui.MetaTableColumnFilter})
           
        function updateColumnLayout(obj) %protected
        %updateColumnLayout Update the columnlayout based on user settings
        
            if isempty(obj.ColumnModel); return; end
            if isempty(obj.MetaTable); return; end
            
            colIndices = obj.ColumnModel.getColumnIndices();
            
            % Set column names
            [columnLabels, variableNames] = obj.ColumnModel.getColumnNames();
            obj.HTable.ColumnName = columnLabels;

            obj.updateColumnEditable()
            
            % Set column widths
            newColumnWidths = obj.ColumnModel.getColumnWidths();
            obj.changeColumnWidths(newColumnWidths)
            
            
            T = obj.MetaTableCell; % Column format is determined from the cell version of table.
            T = T(:, colIndices);
            
            % Return if table has no rows. 
            if size(T,1)==0; return; end
            
            % Set column format and formatdata
            dataTypes = cellfun(@(cell) class(cell), T(1,:), 'uni', 0);
            colFormatData = arrayfun(@(i) [], 1:numel(dataTypes), 'uni', 0);
            
            
% % %             % Note: Important to reset this before updating. Columns can be 
% % %             % rearranged and number of columns can change. If 
% % %             % ColumnFormatData does not match the specified column format
% % %             % an error might occur.
% % %             obj.HTable.ColumnFormatData = colFormatData;
            
            
            % All numeric types should be called 'numeric'
            isNumeric = cellfun(@(cell) isnumeric(cell), T(1,:), 'uni', 1);
            dataTypes(isNumeric) = {'numeric'};
            
            isDatetime = cellfun(@(cell) isdatetime(cell), T(1,:), 'uni', 1);
            dataTypes(isDatetime) = {'date'};
        
            % Todo: get from nansen preferences...      
            colFormatData(isDatetime) = {'MMM-dd-yyyy    '};      
            
            % NOTE: This is temporary. Need to generalize, not make special
            % treatment for session table
            customVars = nansen.metadata.utility.getCustomTableVariableNames();
            [customVars, iA] = intersect(variableNames, customVars);
            
            for i = 1:numel(customVars)
                thisName = customVars{i};
                varFcn = nansen.metadata.utility.getCustomTableVariableFcn(thisName);
                varDef = varFcn();
                
                if isa(varDef, 'nansen.metadata.abstract.TableVariable')
                    if isprop(varDef, 'LIST_ALTERNATIVES')
                        dataTypes(iA(i)) = {'popup'};
                        colFormatData(iA(i)) = {varDef.LIST_ALTERNATIVES};
                    end
                end
            end
            
            % Update the column formatting properties
            obj.HTable.ColumnFormat = dataTypes;
            obj.HTable.ColumnFormatData = colFormatData;

            % Set column names. Do this last because this will control that
            % the correct number of columns are shown.
            obj.HTable.ColumnName = columnLabels;
            
            obj.ColumnModel.updateJavaColumnModel()

            % Maybe call this separately???
            %obj.updateTableView()
            
            % Need to update theme...? I should really comment nonsensical
            % stuff better.
            obj.HTable.Theme = obj.HTable.Theme;

        end
        
        function updateColumnEditable(obj)
        %updateColumnEditable Update the ColumnEditable property of table
        %
        %   Set column editable, adjusting for which columns are currently
        %   displayed and whether table should be editable or not.
            
            if isempty(obj.ColumnModel); return; end % On construction...
            
            % Set column editable (By default, none are editable)
            allowEdit = obj.ColumnModel.getColumnIsEditable;
            
            % Set ignoreFlag to editable if options allow
            columnNames = obj.ColumnModel.getColumnNames();
            if obj.AllowTableEdits
                allowEdit( contains(lower(columnNames), 'ignore') ) = true;
                allowEdit( contains(lower(columnNames), 'description') ) = true;
            else
                allowEdit(:) = false;
            end
                        
            obj.HTable.ColumnEditable = allowEdit;
            
        end
        
        function updateTableView(obj, visibleRows)

            if isempty(obj.ColumnModel); return; end % On construction...
                        
            [numRows, numColumns] = size(obj.MetaTableCell); %#ok<ASGLU>

            if nargin < 2; visibleRows = 1:numRows; end
            
            % Get based on user selection of which columns to display
            visibleColumns = obj.getCurrentColumnSelection();
            
            % Get visible rows based on filter states
            filteredRows = obj.getCurrentRowSelection(); 
            visibleRows = intersect(filteredRows, visibleRows, 'stable');
            

            % Get subset of data from metatable that should be put in the
            % uitable. 
            tableDataView = obj.MetaTableCell(visibleRows, visibleColumns);

            % Rearrange columns according to current state of the java 
            % column model
            [javaColIndex, ~] = obj.ColumnModel.getColumnModelIndexOrder();
            javaColIndex = javaColIndex(1:numel(visibleColumns));
            tableDataView(:, javaColIndex) = tableDataView;
            
            % Assign updated table data to the uitable property
            obj.HTable.Data = tableDataView;
            obj.HTable.Visible = 'on';
            drawnow
        end
        
        function changeColumnNames(obj, newNames)
            obj.HTable.ColumnName = newNames;
        end % Todo: make dependent property and set method (?)
        
        function changeColumnWidths(obj, newWidths)
            
            if isa(obj.HTable, 'uim.widget.StylableTable')
                % Use custom method of table model to set column width.
                obj.HTable.changeColumnWidths(newWidths)
            else
                obj.HTable.ColumnWidth = newWidths;
            end
            
        end % Todo: make dependent property and set method (?)
        
        function changeColumnToShow(obj)
            
        end % Todo: make dependent property and set method (?)
        
        function changeColumnOrder(obj)
            % todo howdo
        end

    end
    
    methods (Access = private) % Update table & internal housekeeping
                
        function onMetaTableSet(obj, newTable)
        %onMetaTableSet Internal callback for when the MetaTable property
        %is set.
        %
        % Need to store the metatable as a cell array for presenting it in
        % the UI table. (Relevant mostly for MetaTable objects because they
        % might contain column data that needs to be formatted.
        
            import nansen.metadata.utility.getMetaTableVariableAttributes
        
            if isa(newTable, 'nansen.metadata.MetaTable')
                T = newTable.getFormattedTableData();
                obj.MetaTableCell = table2cell(T);
            elseif isa(newTable, 'table')
                obj.MetaTableCell = table2cell(newTable);
            end
            
            % Get metatable variable attributes based on table type.
            try
                S = getMetaTableVariableAttributes(obj.MetaTableType);
            catch
                S = obj.getDefaultMetaTableVariableAttributes();
            end
            
            obj.MetaTableVariableAttributes = S;
                        
        end
        
        function onColumnFilterSet(obj)
        %onColumnFilterSet Callback for property value set.    
            if ~isempty(obj.FilterChangedListener)
                delete(obj.FilterChangedListener)
            end
            
            obj.FilterChangedListener = addlistener(obj.ColumnFilter, ...
                'FilterUpdated', @obj.onFilterUpdated);
        end
        
        function onFilterUpdated(obj, src, evt)
        %onFilterUpdated Callback for table filter update events
            
            obj.updateTableView()
            
            if ~isempty(obj.ExternalFilterMap)
                visibleRows = find( obj.ExternalFilterMap );
            else
                visibleRows = 1:size(obj.MetaTableCell, 1);
            end
            
            rows = obj.getCurrentRowSelection(); 
            rows = intersect(rows, visibleRows, 'stable');
            
            evtdata = uiw.event.EventData('RowIndices', rows, 'Type', 'TableFilterUpdate');
            obj.notify('TableUpdated', evtdata)
        end
        
        function rowInd = getCurrentRowSelection(obj)
            % Get row indices that are visible in the uitable

            % Initialize the data filter map if it is empty.
            [numRows, numColumns] = size(obj.MetaTableCell);
            if isempty(obj.DataFilterMap)
                obj.DataFilterMap = true(numRows, numColumns);
            end
            
            % Remove ignored entries based on preference in settings.
            if ~obj.ShowIgnoredEntries
                
                varNames = obj.MetaTable.Properties.VariableNames;
                
                isIgnoreColumn = contains(lower(varNames), 'ignore');
                if any(isIgnoreColumn)
                
                    isIgnored = [ obj.MetaTableCell{:, isIgnoreColumn} ];
                
                    % Negate values of the ignore flag in the filter map
                    obj.DataFilterMap(:, isIgnoreColumn) = ~isIgnored;
                end
            end
            
            % Get indices for rows where all cells in the map are true
            rowInd = find( all(obj.DataFilterMap, 2) );
            
            if ~isempty(obj.ExternalFilterMap)
                rowInd = intersect(rowInd, find(obj.ExternalFilterMap), 'stable');
            end
            
        end
        
        function colInd = getCurrentColumnSelection(obj)
            % Get column indices that are visible in the uitable
            if isempty(obj.ColumnModel); return; end % On construction...
            
            colInd = obj.ColumnModel.getColumnIndices();
        end
        
        function S = getDefaultMetaTableVariableAttributes(obj)
                    
            varNames = obj.MetaTable.Properties.VariableNames;
            numVars = numel(varNames);
            
            S = struct('Name', varNames);
            [S(1:numVars).IsCustom] = deal(false);
            [S(1:numVars).IsEditable] = deal(false);
            [S(1:numVars).HasFunction] = deal(false);

        end
    end
 
    methods (Access = private) % Mouse / user event callbacks
        
        function onHeaderPressTimerRunOut(obj, src, evt)
            
            if isempty(obj.ColumnPressedTimer)
                return
            end
            
            stop(obj.ColumnPressedTimer)
            delete(obj.ColumnPressedTimer)
            obj.ColumnPressedTimer = [];
            
            clickPosX = get(evt, 'X');
            clickPosY = get(evt, 'Y');
            obj.openColumnFilter(clickPosX, clickPosY)
            
        end

        function onMousePressedInHeader(obj, src, evt)
            
            buttonNum = get(evt, 'Button');
            obj.lastMousePressTic = tic;

            % Need to call this to make sure filterdropdowns disappear if
            % mouse is pressed in column header...
            obj.ColumnFilter.hideFilters();
            
            % Check the cursor type of the mouse pointer. If it equals 11,
            % it corresponds with the special case when the pointer is
            % clicked on the border between to columns. In this case, abort.
            if obj.HTable.JTable.getTableHeader().getCursor().getType() == 11
                return
            end
            
            
            if buttonNum == 1 && get(evt, 'ClickCount') == 1
                
                if isempty(obj.ColumnPressedTimer)
                    obj.ColumnPressedTimer = timer();
                    obj.ColumnPressedTimer.Period = 1;
                    obj.ColumnPressedTimer.StartDelay = 0.25;
                    obj.ColumnPressedTimer.TimerFcn = @(s,e) obj.onHeaderPressTimerRunOut(s, evt);
                    start(obj.ColumnPressedTimer)
                    obj.HTable.JTable.getModel().setSortable(0)
                end
                
            elseif buttonNum == 3 %rightclick
                
                % These are coords in table
                clickPosX = get(evt, 'X');
                clickPosY = get(evt, 'Y');
                
                % todo: get column header x- and y positions in figure.
                
                obj.openColumnContextMenu(clickPosX, clickPosY);
            end

        end
        
        function onMouseDraggedInTableHeader(obj, src, evt)
            
            if ~isempty( obj.ColumnPressedTimer )
                % Simulate mouse release to cancel the timer
                obj.onMouseReleasedFromHeader([], [])
            end
            
            dPos = (evt.MousePointCurrent -  evt.MousePointStart);
            dS = sqrt(sum(dPos.^2));
            
            if dS > 10
                if ~isempty(obj.ColumnFilter)  
                    obj.ColumnFilter.hideFilters();
                end
            end
        end
        
        function onMouseReleasedFromHeader(obj, src, evt)
                        
            if ~isempty(obj.ColumnPressedTimer)
                stop(obj.ColumnPressedTimer)
                delete(obj.ColumnPressedTimer)
                obj.ColumnPressedTimer = [];
                
                % Mouse was released before 1 second passed.
                obj.HTable.JTable.getModel().setSortable(1)
            end            
        end
        
        function onMousePressedInTable(obj, src, evt)
        %onMousePressedInTable Callback for mousepress in table.
        %
        %   This function is primarily used for 
        %       1) Creating an action on doubleclick
        %       2) Selecting cell on right click

            % Return if instance is not valid.
            if ~exist('obj', 'var') || ~isvalid(obj); return; end

            obj.ColumnFilter.hideFilters()

            if strcmp(evt.SelectionType, 'normal')
                % Do nothing.
                % Get row where mouse press ocurred.
                row = evt.Cell(1); col = evt.Cell(2);
                if row == 0 || col == 0
                    obj.HTable.SelectedRows = [];
                    
                    % Make sure editable cell is not in focus, because that
                    % shit is ugly...
                    colIdx = find( ~obj.HTable.ColumnEditable, 1, 'first');
                    selectionModel = obj.HTable.JTable.getColumnModel.getSelectionModel;
                    set(selectionModel, 'LeadSelectionIndex', colIdx-1)
                end
                
                    
            elseif strcmp(evt.SelectionType, 'open')
            
                if ~isempty(obj.MouseDoubleClickedFcn)
                    obj.MouseDoubleClickedFcn(src, evt)
                end
                
                % Todo:
                % Double click action should depend on which column click
                % happens over.

% %                     if isequal(get(event, 'button'), 3)
% %                         return
% %                     end
% %                     
% %                     currentFields = app.tableSettings.FieldNames(app.tableSettings.FieldsToShow);
% %                     so = retrieveSessionObject(app, app.highlightedSessions(end));
% %                     
% %                     if numel(app.highlightedSessions) > 1
% %                         warning('Multiple sessions, selected, operation applies to last session only.')
% %                     end
% %                     
% %                     if strcmp(currentFields{j+1}, 'Notes')
% %                         app.showNotes(so.sessionID)
% %                     else
% %                         %so.openFolder
% %                         openFolder(so.sessionID, 'datadrive', 'processed')
% %                     end

                    
            elseif evt.Button == 3 || strcmp(evt.SelectionType, 'alt')
                
                if ismac && evt.Button == 1 && evt.MetaOn
                    return % Command click on mac should not count as right click
                end

                % Get row where mouse press ocurred.
                row = evt.Cell(1); col = evt.Cell(2);
                
                % Select row where mouse is pressed if it is not already
                % selected
                if ~ismember(row, obj.HTable.SelectedRows) 
                    if row > 0 && col > 0
                        obj.HTable.SelectedRows = row;
                    else
                        obj.HTable.SelectedRows = [];
                        return
                    end
                end

                % Open context menu for table
                if ~isempty(obj.TableContextMenu)
                    position = obj.getTableContextMenuPosition(evt.Position);
                    obj.openTableContextMenu(position(1), position(2));
                end
            end

        end  
        
        function onMouseMotionInTable(obj, src, evt)
            % This functionality is put in the nansen app for now.            
        end
        
        function onCellValueEdited(obj, src, evtData)
        %onCellValueEdited Callback for value change in cell
        %
        %   1) Update original table data
        %   2) Modify evtData and pass on to class' CellEditCallback
            
        % Todo: For time being (oct2021) the only editable column is the
        % ignore flag column. Should refresh the table if ignore rows are
        % set to hidden, but for now, the ignored rows will disappear on
        % next table update.
        
            % Get currently visible row and column indices.
            rowInd = obj.getCurrentRowSelection();
            colInd = obj.getCurrentColumnSelection();
            
            % Get row and column indices for original data (unfiltered, unsorted, allcolumns)
            tableRowInd = rowInd(evtData.Indices(1));
            
            evtColIdx = obj.ColumnModel.getColumnIdx( evtData.Indices(2) ); % 2 is for columns
            tableColInd = colInd(evtColIdx);
            
            
            % Update value in table and table cell array
            %obj.MetaTable(tableRowInd, tableColInd) = {evtData.NewValue};
            obj.MetaTableCell{tableRowInd, tableColInd} = evtData.NewValue;
            
            % Invoke external callback if it is assigned.
            if ~isempty( obj.CellEditCallback )
                evtData.Indices = [tableRowInd, tableColInd];
                obj.CellEditCallback(src, evtData)
            end
        end
        
        function onColumnWidthChanged(obj, src, event)
        %onColumnWidthChanged Callback for events where column widths are
        %changed by resizing column widths in from gui.
            obj.ColumnModel.setColumnWidths(obj.HTable.ColumnWidth)
        end
        
        function onColumnsRearranged(obj, src, evt)
        %onColumnsRearranged Callback for event when columns are rearranged
        %
        % This event is triggered when user drags columns to rearrange
            
            % Tell columnmodel of new order...
            newColumnArrangement = obj.HTable.getColumnOrder;
            obj.ColumnModel.setNewColumnOrder(newColumnArrangement)
                        
            if ~isempty(obj.ColumnFilter)  
                obj.ColumnFilter.hideFilters();
            end
        end
        
        function columnIdx = getColumnAtPoint(obj, x, y)
        %getColumnAtPoint Returns the column index at point (x,y)
        %    
        %   Conversion from java to matlab:
            
            mPos = java.awt.Point(x, y);
            columnIdx = obj.HTable.JTable.columnAtPoint(mPos) + 1; 
            % Note, java indexing starts at 0, so added 1.
            
        end
        
        function position = getTableContextMenuPosition(obj, eventPosition)
        %getTableContextMenuPosition Get cmenu position from event position
        
            % Get scroll positions in table
            xScroll = obj.HTable.getHorizontalScrollOffset();
            yScroll = obj.HTable.getVerticalScrollOffset();
                        
            % Get position where mouseclick occured (in figure)
            clickPosX = eventPosition(1) - xScroll;
            clickPosY = eventPosition(2) - yScroll;
            
            % Convert to position inside table
            tablePosition = getpixelposition(obj.HTable, true);
            tableLocationX = tablePosition(1); 
            tableHeight = tablePosition(4);
            
            positionX = clickPosX + tableLocationX + 1; % +1 because ad hoc...
            positionY = tableHeight - clickPosY + 19; % +15 because ad hoc... size of table header?
            
            position = [positionX, positionY];
            
        end
        
        function figureCoords = javapoint2figurepoint(obj, javaCoords)
        %javapoint2figurepoint Find coordinates of point in figure units
        %
        %   figureCoords = javapoint2figurepoint(obj, javaCoords) returns
        %   figureCoords ([x,y]) of point in figure (measured from lower 
        %   left corner) based on javaCoords ([x,y]) from a java mouse
        %   event in the table (measured from upper left corner in table).
        
            % Note:
            % x is position measured from left inside table
            % y is position measured from top inside table
           

            % Get pixel position of table referenced in figure.
            tablePosition = getpixelposition(obj.HTable, true);
            
            x0 = tablePosition(1);
            y0 = tablePosition(2);
            tableHeight = tablePosition(4);
            
            xPosition = x0 + javaCoords(1);
            yPosition = y0 + tableHeight - javaCoords(2);
             
            figureCoords = [xPosition, yPosition];
            
        end
        
        function openColumnContextMenu(obj, x, y)
            
            colNumber = obj.getColumnAtPoint(x, y);
            if colNumber == 0; return; end
            
            if isempty(obj.ColumnContextMenu)
                obj.createColumnContextMenu()
            end

            columnType = obj.HTable.ColumnFormat{colNumber};
            
            [~, varNames] = obj.ColumnModel.getColumnNames();
            currentColumnName = varNames{colNumber};
            
            isMatch = strcmp( {obj.MetaTableVariableAttributes.Name}, currentColumnName );
            if any(isMatch)
                varAttr = obj.MetaTableVariableAttributes(isMatch); 
            else
                error('Variable attributes does not exist. This is unexpected.')
            end
            
            % Select appearance of context menu based on column type:
            for i = 1:numel(obj.ColumnContextMenu.Children)
                hTmp = obj.ColumnContextMenu.Children(i);
                
                switch hTmp.Tag
                    case 'Sort Ascend'
                        switch columnType
                            case 'char'
                                hTmp.Label = 'Sort A-Z';
                            case 'numeric'
                                hTmp.Label = 'Sort low-high';
                            case 'logical'
                                hTmp.Label = 'Sort false-true';
                        end
                        hTmp.Callback = @(s,e,iCol,dir) obj.sortColumn(colNumber,'ascend');

                    case 'Sort Descend'
                        switch columnType
                            case 'char'
                                hTmp.Label = 'Sort Z-A';
                            case 'numeric'
                                hTmp.Label = 'Sort high-low';
                            case 'logical'
                                hTmp.Label = 'Sort true-false';
                        end
                        hTmp.Callback = @(s,e,iCol,dir) obj.sortColumn(colNumber,'descend');
                        
                    case 'Filter'
                        hTmp.Callback = @(s,e,iCol) obj.filterColumn(colNumber);
                    case 'Reset Filters'
                        hTmp.Callback = @(s,e,iCol) obj.resetColumnFilters();
                        
                    case 'Hide Column'
                        hTmp.Callback = @(s,e,iCol) obj.hideColumn(colNumber);
                        
                    case 'Update Column'
                        if varAttr.HasFunction % (Does it have to be custom?)% varAttr.IsCustom && varAttr.HasFunction
                            hTmp.Enable = 'on';
                            if ~isempty(obj.UpdateColumnFcn) 
                                % Children are reversed from creation
                                hTmp.Children(2).Callback = @(name, mode) obj.UpdateColumnFcn(currentColumnName, 'SelectedRows');
                                hTmp.Children(1).Callback = @(name, mode) obj.UpdateColumnFcn(currentColumnName, 'AllRows');
                            end
                        else
                            hTmp.Enable = 'off';
                        end
                        
                    case 'Delete Column'
                        if varAttr.IsCustom
                            hTmp.Enable = 'on';
                            if ~isempty(obj.DeleteColumnFcn)
                                hTmp.Callback = @(colName, evt) obj.DeleteColumnFcn(currentColumnName);
                            end
                        else
                            hTmp.Enable = 'off';
                        end
                        
                    otherwise
                        % Do nothing
                end
            end
            

            % Get the coordinates for where to show the context menu
            figurePoint = obj.javapoint2figurepoint([x, y]);
            
            % Adjust for the horizontal scroll position in the table.
            xOff = obj.HTable.getHorizontalScrollOffset();
            figurePoint = figurePoint - [xOff, 0];
            
            % Set position and make menu visible.
            obj.ColumnContextMenu.Position = figurePoint;
            obj.ColumnContextMenu.Visible = 'on';
            
        end
        
        function openTableContextMenu(obj, x, y)
            
            if isempty(obj.TableContextMenu); return; end

            % Set position and make menu visible.
            obj.TableContextMenu.Position = [x,y]; 
            obj.TableContextMenu.Visible = 'on';
            
        end
        
        function openColumnFilter(obj, x, y)
        %openColumnFilter Open column filter as dropdown below column header             
            
            tableColumnIdx = obj.getColumnAtPoint(x, y);
            if tableColumnIdx == 0; return; end
            
            colIndices = obj.ColumnModel.getColumnIndices();
            dataColumnIndex = colIndices(tableColumnIdx);
            
            obj.ColumnFilter.openFilterControl(dataColumnIndex)     

        end
        
        function filterColumn(obj, columnNumber)
        %filterColumn Open column filter in sidepanel
        
            colIndices = obj.ColumnModel.getColumnIndices();
            dataColumnIndex = colIndices(columnNumber);
            
            obj.ColumnFilter.openFilterControl(dataColumnIndex)            
            obj.AppRef.showSidePanel()
            
        end
        
        function sortColumn(obj, columnIdx, sortDirection)
        %sortColumn Sort column in specified direction                
            sortAscend = strcmp(sortDirection, 'ascend');
            sortDescend = strcmp(sortDirection, 'descend');
            
            obj.HTable.JTable.sortColumn(columnIdx-1, 1, sortAscend)

        end
        
        function hideColumn(obj, columnNumber)
        	obj.ColumnModel.hideColumn(columnNumber);
        end
        
    end
    
    methods (Static)
        
        function tf = isValidTableClass(var)
        %isValidTable Test if var satisfies the list of valid table classes
            VALID_CLASSES = nansen.MetaTableViewer.VALID_TABLE_CLASS;
            tf = any(cellfun(@(type) isa(var, type), VALID_CLASSES));
        end
        
    end
    
end