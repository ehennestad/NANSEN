classdef LegacyCompatibilityTest < matlab.unittest.TestCase
%LegacyCompatibilityTest Tests for the adapter to legacy option definitions

    methods (TestClassSetup)
        function addCodeToPath(testCase)
            rootPath = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(rootPath, "code"), IncludingSubfolders=true))
        end
    end

    methods (Test)

        function testInferSchemaFromLegacyStruct(testCase)
            S = struct();
            S.a = 1;
            S.a_ = struct('type', 'slider', 'args', {{'Min', 0, 'Max', 10}});
            S.Group.b = 'x';
            S.Group.b_ = {'x', 'y'};
            S.Group.c = 'secret';
            S.Group.c_ = 'internal';
            S.Group.d = '';
            S.Group.d_ = 'uigetdir';

            schema = nansen.options.legacy.inferSchema(S, "legacy.method");
            testCase.verifyTrue(schema.IsInferred)
            testCase.verifyEqual(schema.ParameterNames, ["a", "Group.b", "Group.c", "Group.d"])
            testCase.verifyEqual(schema.getParameter("a").Widget, "slider")
            testCase.verifyEqual(schema.getParameter("a").Max, 10)
            testCase.verifyEqual(schema.getParameter("b").Choices, {'x', 'y'})
            testCase.verifyTrue(schema.getParameter("c").Internal)
            testCase.verifyEqual(schema.getParameter("d").Widget, "folder")

            % Converting back gives an equivalent struct
            E = nansen.options.legacy.toEditorStruct(schema);
            testCase.verifyEqual(E.Group.b_, {'x', 'y'})
            testCase.verifyEqual(E.Group.c_, 'internal')
            testCase.verifyEqual(E.Group.d_, 'uigetdir')
            testCase.verifyEqual(nansen.options.legacy.fromEditorStruct(schema, E), ...
                schema.getDefaults())
        end

        function testParseParameterComments(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            filePath = fullfile(fixture.Folder, "defaults.m");
            writelines([ ...
                "function P = defaults()"
                "    P.binSize = 5;               % Number of frames to bin"
                "    P.Group.method = 'mean';     % Method for binning"
                "    P.Group.method_ = {'mean', 'max'}; % Config field"
                "    P.noComment = 1;"
                "end"], filePath)

            descriptions = nansen.options.legacy.parseParameterComments(filePath);
            testCase.verifyEqual(descriptions.binSize, "Number of frames to bin")
            testCase.verifyEqual(descriptions.Group.method, "Method for binning")
            testCase.verifyFalse(isfield(descriptions, "noComment"))
            testCase.verifyFalse(isfield(descriptions.Group, "method_"))
        end

        function testComputeDffSchemaMatchesLegacyDefaults(testCase)
            className = "ophys.twophoton.process.signalExtraction.computeDff";
            schema = nansen.options.getSchema(className);

            testCase.verifyFalse(schema.IsInferred)
            testCase.verifyEqual(schema.Name, className)

            legacyOptions = feval(className + ".getDefaultOptions");

            % Defaults are the same
            testCase.verifyEqual(schema.getDefaults(), ...
                nansen.options.legacy.removeConfigFields(legacyOptions))

            % Also the editor configuration is the same
            testCase.verifyEqual(nansen.options.legacy.toEditorStruct(schema), legacyOptions)
        end

        function testInferSchemaFromLegacyFunction(testCase)
            schema = nansen.options.getSchema("nansen.twophoton.roisignals.getDffParameters");
            testCase.verifyTrue(schema.IsInferred)
            testCase.verifyTrue(schema.hasParameter("dffFcn"))
            testCase.verifyNotEmpty(schema.getParameter("dffFcn").Choices)
            testCase.verifyEqual(schema.getParameter("correctBaseline").Description, ...
                "Moving baseline?")
        end
    end
end
