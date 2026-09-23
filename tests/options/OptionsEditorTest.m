classdef (TestTags = {'UI'}) OptionsEditorTest < matlab.uitest.TestCase
%OptionsEditorTest Interactive tests for nansen.options.ui.OptionsEditor
%
%   These tests open windows, and require a display. Exclude them with:
%       runtests("tests/options", ExcludeTag="UI")

    properties
        Manager nansen.options.Manager {mustBeScalarOrEmpty}
        Editor nansen.options.ui.OptionsEditor {mustBeScalarOrEmpty}
    end

    methods (TestClassSetup)
        function addCodeToPath(testCase)
            rootPath = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(rootPath, "code"), IncludingSubfolders=true))
        end
    end

    methods (TestMethodSetup)
        function openEditor(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);

            schema = nansen.options.Schema("test.editor", Title="Editor test");
            schema.addParameter("Preprocessing.binSize", 5, Min=1, Max=100, ...
                Integer=true, Description="Number of frames to bin", Units="frames")
            schema.addParameter("Preprocessing.method", "mean", Choices={"mean", "max"})
            schema.addParameter("Detection.threshold", 0.5)
            schema.addParameter("Detection.useGpu", false)
            schema.addPreset("Fast", {"binSize", 10})

            testCase.Manager = nansen.options.Manager(schema, Location=fixture.Folder);
            testCase.Editor = nansen.options.ui.OptionsEditor(testCase.Manager);
            testCase.addTeardown(@() delete(testCase.Editor))
        end
    end

    methods (Test)
        function testShowsProfilesAndGroups(testCase)
            figure = testCase.getFigure();
            listbox = findall(figure, "Type", "uilistbox");
            testCase.verifyEqual(string(listbox.ItemsData), ["Defaults", "Fast"])

            tabs = findall(figure, "Type", "uitab");
            testCase.verifyEqual(sort(string({tabs.Title})), ["Detection", "Preprocessing"])
        end

        function testSelectPreset(testCase)
            listbox = findall(testCase.getFigure(), "Type", "uilistbox");
            testCase.choose(listbox, "Fast  [preset]")
            testCase.verifyEqual(testCase.Editor.ProfileName, "Fast")
            testCase.verifyEqual(testCase.Editor.Values.Preprocessing.binSize, 10)
        end

        function testEditValue(testCase)
            field = findall(testCase.getFigure(), "Type", "uinumericeditfield", "Value", 5);
            testCase.type(field, 7)
            testCase.verifyEqual(testCase.Editor.Values.Preprocessing.binSize, 7)
            testCase.verifyTrue(testCase.Editor.IsModified)
        end
    end

    methods (Access = private)
        function figure = getFigure(~)
            figure = findall(groot, "Type", "figure", "Name", "Options: Editor test");
            figure = figure(1);
        end
    end
end
