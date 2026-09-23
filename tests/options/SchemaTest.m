classdef SchemaTest < matlab.unittest.TestCase
%SchemaTest Tests for nansen.options.Schema and nansen.options.Parameter
%
%   Run with: runtests('tests/options')

    properties
        Schema
    end

    methods (TestClassSetup)
        function addCodeToPath(testCase)
            rootPath = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(rootPath, 'code'), 'IncludingSubfolders', true))
        end
    end

    methods (TestMethodSetup)
        function createSchema(testCase)
            s = nansen.options.Schema('test.method', 'Version', '1.1.0');
            s.addParameter('Preprocessing.binSize', 5, 'Min', 1, 'Integer', true, ...
                'Description', 'Number of frames to bin')
            s.addParameter('Preprocessing.method', 'mean', 'Choices', {'mean', 'max'})
            s.addParameter('Run.numWorkers', 4, 'Transient', true)
            s.addParameter('threshold', 0.5, 'Validator', @(x) assert(x < 1, 'Must be < 1'))
            s.addParameter('window', [1, 2])
            s.addParameter('useGpu', false)
            s.addParameter('hiddenSetting', 'x', 'Internal', true)
            s.addPreset('Fast', {'binSize', 10}, 'Heavy binning')
            testCase.Schema = s;
        end
    end

    methods (Test)

        function testDefaults(testCase)
            S = testCase.Schema.getDefaults();
            testCase.verifyEqual(S.Preprocessing.binSize, 5)
            testCase.verifyEqual(S.Preprocessing.method, 'mean')
            testCase.verifyEqual(S.window, [1, 2])
        end

        function testInvalidDefaultThrows(testCase)
            testCase.verifyError(@() testCase.Schema.addParameter('x', 'c', ...
                'Choices', {'a', 'b'}), 'NANSEN:Options:InvalidDefault')
            testCase.verifyError(@() testCase.Schema.addParameter('y', -1, ...
                'Min', 0), 'NANSEN:Options:InvalidDefault')
        end

        function testDuplicateAndConflictingNames(testCase)
            testCase.verifyError(@() testCase.Schema.addParameter('threshold', 1), ...
                'NANSEN:Options:DuplicateParameter')
            testCase.verifyError(@() testCase.Schema.addParameter('Preprocessing', 1), ...
                'NANSEN:Options:DuplicateParameter')
            testCase.verifyError(@() testCase.Schema.addParameter('threshold.sub', 1), ...
                'NANSEN:Options:DuplicateParameter')
        end

        function testResolveShortName(testCase)
            testCase.verifyEqual(testCase.Schema.resolveName('binSize'), 'Preprocessing.binSize')
            testCase.verifyError(@() testCase.Schema.resolveName('nonExisting'), ...
                'NANSEN:Options:UnknownParameter')
        end

        function testApplyOverridesValidates(testCase)
            s = testCase.Schema;
            S = s.applyOverrides(s.getDefaults(), {'binSize', 3, 'method', 'max'});
            testCase.verifyEqual(S.Preprocessing.binSize, 3)
            testCase.verifyEqual(S.Preprocessing.method, 'max')

            testCase.verifyError(@() s.applyOverrides(s.getDefaults(), {'binSize', 1.5}), ...
                'NANSEN:Options:InvalidValue')
            testCase.verifyError(@() s.applyOverrides(s.getDefaults(), {'method', 'median'}), ...
                'NANSEN:Options:InvalidValue')
            testCase.verifyError(@() s.applyOverrides(s.getDefaults(), {'threshold', 2}), ...
                'NANSEN:Options:InvalidValue')
        end

        function testConformFillsAndCoerces(testCase)
            s = testCase.Schema;
            S = struct('window', [3; 4], 'useGpu', 1, ...
                'Preprocessing', struct('binSize', int8(2)), ...
                'method_', {{'mean', 'max'}}); % Legacy config field is ignored
            [S, issues] = s.conform(S);

            testCase.verifyEqual(S.window, [3, 4])            % Orientation
            testCase.verifyClass(S.useGpu, 'logical')         % Class
            testCase.verifyClass(S.Preprocessing.binSize, 'double')
            testCase.verifyEqual(S.Preprocessing.method, 'mean') % Filled in
            testCase.verifyTrue(any(strcmp({issues.Name}, 'Preprocessing.method')))
        end

        function testConformUnknownFields(testCase)
            s = testCase.Schema;
            S = s.getDefaults(); S.extra = 1;
            testCase.verifyError(@() s.conform(S), 'NANSEN:Options:UnknownParameter')

            conformed = s.conform(S, 'Unknown', 'drop');
            testCase.verifyFalse(isfield(conformed, 'extra'))

            conformed = s.conform(S, 'Unknown', 'keep');
            testCase.verifyEqual(conformed.extra, 1)
        end

        function testValidateReportsIssues(testCase)
            s = testCase.Schema;
            S = s.getDefaults();
            S.extra = 1;
            S.threshold = 5;
            S = rmfield(S, 'useGpu');
            [isValid, issues] = s.validate(S);
            testCase.verifyFalse(isValid)
            testCase.verifyEqual(sort({issues.Type}), sort({'invalid', 'missing', 'unknown'}))
        end

        function testHashIgnoresTransientParameters(testCase)
            s = testCase.Schema;
            S = s.getDefaults();
            hashA = s.computeHash(S);

            S.Run.numWorkers = 16;
            testCase.verifyEqual(s.computeHash(S), hashA)

            S.threshold = 0.1;
            testCase.verifyNotEqual(s.computeHash(S), hashA)
        end

        function testHashIsIndependentOfFieldOrder(testCase)
            s = testCase.Schema;
            S = s.getDefaults();
            testCase.verifyEqual(s.computeHash(orderfields(S)), s.computeHash(S))
        end

        function testPresets(testCase)
            s = testCase.Schema;
            S = s.getPresetValues('Fast');
            testCase.verifyEqual(S.Preprocessing.binSize, 10)
            testCase.verifyError(@() s.addPreset('Defaults', {}), 'NANSEN:Options:ReservedName')
            testCase.verifyError(@() s.addPreset('Bad', {'binSize', 0}), 'NANSEN:Options:InvalidValue')
        end

        function testMigration(testCase)
            s = testCase.Schema;
            s.addMigration('1.0.0', '1.1.0', @(S) nansen.options.migrate.renameField( ...
                S, 'binSize', 'Preprocessing.binSize'), 'Moved binSize to group')

            [S, log] = s.migrate(struct('binSize', 7), '1.0.0');
            testCase.verifyEqual(S.Preprocessing.binSize, 7)
            testCase.verifyNumElements(log, 1)

            % Partial structs without the field are unchanged
            S = s.migrate(struct('threshold', 0.2), '1.0.0');
            testCase.verifyEqual(S, struct('threshold', 0.2))
        end

        function testModifyParameter(testCase)
            s = testCase.Schema;
            hashBefore = s.getDefaultsHash();
            s.modifyParameter('binSize', 'Default', 8, 'Max', 20)
            p = s.getParameter('Preprocessing.binSize');
            testCase.verifyEqual(p.Default, 8)
            testCase.verifyEqual(p.Max, 20)
            testCase.verifyEqual(p.Description, 'Number of frames to bin') % Kept
            testCase.verifyNotEqual(s.getDefaultsHash(), hashBefore)
        end

        function testEditorStructRoundTrip(testCase)
            s = testCase.Schema;
            E = s.toEditorStruct();
            testCase.verifyEqual(E.Preprocessing.method_, {'mean', 'max'})
            testCase.verifyEqual(E.hiddenSetting_, 'internal')
            testCase.verifyEqual(E.Run.numWorkers_, 'transient')
            testCase.verifyEqual(s.fromEditorStruct(E), s.getDefaults())
        end

        function testFromLegacyStruct(testCase)
            S = struct();
            S.a = 1;
            S.a_ = struct('type', 'slider', 'args', {{'Min', 0, 'Max', 10}});
            S.Group.b = 'x';
            S.Group.b_ = {'x', 'y'};
            S.Group.c = 'secret';
            S.Group.c_ = 'internal';

            schema = nansen.options.Schema.fromStruct(S, 'legacy.method');
            testCase.verifyTrue(schema.IsInferred)
            testCase.verifyEqual(schema.ParameterNames, {'a', 'Group.b', 'Group.c'})
            testCase.verifyEqual(schema.getParameter('a').Max, 10)
            testCase.verifyEqual(schema.getParameter('b').Choices, {'x', 'y'})
            testCase.verifyTrue(schema.getParameter('c').Internal)

            % Converting back gives the original struct
            testCase.verifyEqual(schema.toEditorStruct(), S)
        end

        function testTableAndJsonSchema(testCase)
            T = testCase.Schema.toTable();
            testCase.verifyFalse(any(strcmp(T.Name, 'hiddenSetting')))

            J = testCase.Schema.toJsonSchema();
            props = J('properties');
            testCase.verifyEqual(props.Preprocessing.properties.binSize.type, 'integer')
            testCase.verifyEqual(props.Preprocessing.properties.method.enum, {'mean', 'max'})

            filePath = [tempname, '.json'];
            cleanup = onCleanup(@() delete(filePath));
            testCase.Schema.writeJsonSchema(filePath)
            testCase.verifyTrue(isfile(filePath))
        end
    end

end
