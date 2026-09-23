classdef LegacyCompatibilityTest < matlab.unittest.TestCase
%LegacyCompatibilityTest Check that schemas agree with legacy definitions

    methods (TestClassSetup)
        function addCodeToPath(testCase)
            rootPath = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(rootPath, 'code'), 'IncludingSubfolders', true))
        end
    end

    methods (Test)
        function testComputeDffSchemaMatchesLegacyDefaults(testCase)
            className = 'ophys.twophoton.process.signalExtraction.computeDff';
            schema = nansen.options.getSchema(className);

            testCase.verifyFalse(schema.IsInferred)
            testCase.verifyEqual(schema.Name, className)

            legacyOptions = feval([className, '.getDefaultOptions']);

            % Defaults are the same
            testCase.verifyEqual(schema.getDefaults(), ...
                nansen.options.Schema.removeEditorConfigFields(legacyOptions))

            % Also the editor configuration is the same
            testCase.verifyEqual(schema.toEditorStruct(), legacyOptions)
        end

        function testInferSchemaFromLegacyFunction(testCase)
            schema = nansen.options.getSchema('nansen.twophoton.roisignals.getDffParameters');
            testCase.verifyTrue(schema.IsInferred)
            testCase.verifyTrue(schema.hasParameter('dffFcn'))
            testCase.verifyEqual(schema.getParameter('correctBaseline').Description, ...
                'Moving baseline?')
        end
    end
end
