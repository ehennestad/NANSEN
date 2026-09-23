classdef SchemaTest < matlab.unittest.TestCase
%SchemaTest Tests for nansen.options.Schema and nansen.options.Parameter
%
%   Run with: runtests("tests/options")

    properties
        Schema
    end

    methods (TestClassSetup)
        function addCodeToPath(testCase)
            rootPath = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(rootPath, "code"), IncludingSubfolders=true))
        end
    end

    methods (TestMethodSetup)
        function createSchema(testCase)
            s = nansen.options.Schema("test.method", Version="1.1.0");
            s.addParameter("Preprocessing.binSize", 5, Min=1, Integer=true, ...
                Description="Number of frames to bin", Units="frames")
            s.addParameter("Preprocessing.method", "mean", Choices={"mean", "max"})
            s.addParameter("Run.numWorkers", 4, Transient=true)
            s.addParameter("threshold", 0.5, Validator=@(x) assert(x < 1, "Must be < 1"))
            s.addParameter("window", [1, 2])
            s.addParameter("useGpu", false)
            s.addParameter("label", 'abc')
            s.addParameter("hiddenSetting", "x", Internal=true)
            s.addPreset("Fast", {"binSize", 10}, Description="Heavy binning")
            testCase.Schema = s;
        end
    end

    methods (Test)

        function testDefaults(testCase)
            S = testCase.Schema.getDefaults();
            testCase.verifyEqual(S.Preprocessing.binSize, 5)
            testCase.verifyEqual(S.Preprocessing.method, "mean")
            testCase.verifyEqual(S.window, [1, 2])
        end

        function testParameterAttributes(testCase)
            p = testCase.Schema.getParameter("binSize");
            testCase.verifyEqual(p.Name, "Preprocessing.binSize")
            testCase.verifyEqual(p.GroupName, "Preprocessing")
            testCase.verifyEqual(p.ShortName, "binSize")
            testCase.verifyEqual(p.DisplayLabel, "Bin size")
            testCase.verifyEqual(p.Type, nansen.options.ParameterType.Numeric)
            testCase.verifyEqual(testCase.Schema.getParameter("method").Type, ...
                nansen.options.ParameterType.Choice)
        end

        function testInvalidDefinitionsThrow(testCase)
            s = testCase.Schema;
            testCase.verifyError(@() s.addParameter("x", "c", Choices={"a", "b"}), ...
                "NANSEN:Options:InvalidDefault")
            testCase.verifyError(@() s.addParameter("y", -1, Min=0), ...
                "NANSEN:Options:InvalidDefault")
            testCase.verifyError(@() s.addParameter("bad name", 1), ...
                "NANSEN:Options:InvalidName")
            testCase.verifyError(@() s.addParameter("z", 1, Widget="unknown"), ...
                "MATLAB:validators:mustBeMember")
            testCase.verifyError(@() nansen.options.Schema("x", Version="one"), ...
                "NANSEN:Options:InvalidVersion")
            % Structs with fields are groups, not parameter values
            testCase.verifyError(@() s.addParameter("roi", struct("x", 1)), ...
                "NANSEN:Options:InvalidDefault")
        end

        function testDuplicateAndConflictingNames(testCase)
            s = testCase.Schema;
            testCase.verifyError(@() s.addParameter("threshold", 1), ...
                "NANSEN:Options:DuplicateParameter")
            testCase.verifyError(@() s.addParameter("Preprocessing", 1), ...
                "NANSEN:Options:DuplicateParameter")
            testCase.verifyError(@() s.addParameter("threshold.sub", 1), ...
                "NANSEN:Options:DuplicateParameter")
        end

        function testResolveName(testCase)
            s = testCase.Schema;
            testCase.verifyEqual(s.resolveName("binSize"), "Preprocessing.binSize")
            testCase.verifyEqual(s.resolveName("Preprocessing.binSize"), "Preprocessing.binSize")
            testCase.verifyError(@() s.resolveName("nonExisting"), ...
                "NANSEN:Options:UnknownParameter")

            s.addParameter("Detection.method", "a")
            testCase.verifyError(@() s.resolveName("method"), "NANSEN:Options:AmbiguousName")
        end

        function testApplyOverridesValidates(testCase)
            s = testCase.Schema;
            S = s.applyOverrides(s.getDefaults(), {"binSize", 3, "method", "max"});
            testCase.verifyEqual(S.Preprocessing.binSize, 3)
            testCase.verifyEqual(S.Preprocessing.method, "max")

            invalidOverrides = {{"binSize", 1.5}, {"binSize", 0}, ...
                {"method", "median"}, {"threshold", 2}, {"useGpu", "yes"}};
            for i = 1:numel(invalidOverrides)
                testCase.verifyError(@() s.applyOverrides(s.getDefaults(), invalidOverrides{i}), ...
                    "NANSEN:Options:InvalidValue")
            end
        end

        function testConformFillsAndCoerces(testCase)
            s = testCase.Schema;
            S = struct("window", [3; 4], "useGpu", 1, "label", "text", ...
                "Preprocessing", struct("binSize", int8(2), "method", 'max'));
            [S, issues] = s.conform(S);

            testCase.verifyEqual(S.window, [3, 4])            % Orientation
            testCase.verifyClass(S.useGpu, "logical")         % Class
            testCase.verifyClass(S.Preprocessing.binSize, "double")
            testCase.verifyClass(S.Preprocessing.method, "string")
            testCase.verifyClass(S.label, "char")
            testCase.verifyEqual(S.threshold, 0.5)            % Filled in
            testCase.verifyTrue(ismember("threshold", issues.Name))
        end

        function testConformUnknownFields(testCase)
            s = testCase.Schema;
            S = s.getDefaults();
            S.extra = 1;
            testCase.verifyError(@() s.conform(S), "NANSEN:Options:UnknownParameter")

            conformed = s.conform(S, Unknown="drop");
            testCase.verifyFalse(isfield(conformed, "extra"))

            conformed = s.conform(S, Unknown="keep");
            testCase.verifyEqual(conformed.extra, 1)

            testCase.verifyWarning(@() s.conform(S, Unknown="warn"), ...
                "NANSEN:Options:UnknownParameter")
        end

        function testValidateReportsIssues(testCase)
            s = testCase.Schema;
            S = s.getDefaults();
            S.extra = 1;
            S.threshold = 5;
            S = rmfield(S, "useGpu");

            [isValid, issues] = s.validate(S);
            testCase.verifyFalse(isValid)
            testCase.verifyEqual(sort(issues.Issue)', ["invalid", "missing", "unknown"])

            testCase.verifyTrue(s.validate(s.getDefaults()))
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

        function testHashIsIndependentOfFieldOrderAndTextClass(testCase)
            s = testCase.Schema;
            S = s.getDefaults();
            testCase.verifyEqual(s.computeHash(orderfields(S)), s.computeHash(S))

            T = S;
            T.Preprocessing.method = 'mean'; % char instead of string
            testCase.verifyEqual(s.computeHash(T), s.computeHash(S))
        end

        function testPresets(testCase)
            s = testCase.Schema;
            S = s.getPresetValues("Fast");
            testCase.verifyEqual(S.Preprocessing.binSize, 10)
            testCase.verifyEqual(s.getPreset("Fast").Type, nansen.options.ProfileType.Preset)
            testCase.verifyError(@() s.addPreset("Defaults", {}), "NANSEN:Options:ReservedName")
            testCase.verifyError(@() s.addPreset("Bad", {"binSize", 0}), "NANSEN:Options:InvalidValue")
        end

        function testMigration(testCase)
            s = testCase.Schema;
            s.addMigration("1.0.0", "1.1.0", @(S) nansen.options.migrate.renameField( ...
                S, "binSize", "Preprocessing.binSize"), Description="Moved binSize to group")

            [S, log] = s.migrate(struct("binSize", 7), "1.0.0");
            testCase.verifyEqual(S.Preprocessing.binSize, 7)
            testCase.verifyEqual(log, "1.0.0 -> 1.1.0: Moved binSize to group")

            % Partial structs without the field are unchanged
            S = s.migrate(struct("threshold", 0.2), "1.0.0");
            testCase.verifyEqual(S, struct("threshold", 0.2))

            testCase.verifyError(@() s.addMigration("2.0.0", "1.0.0", @(S) S), ...
                "NANSEN:Options:InvalidInput")
        end

        function testChainedMigrations(testCase)
            s = nansen.options.Schema("test", Version="3.0.0");
            s.addParameter("c", 1)
            s.addMigration("1.0.0", "2.0.0", @(S) nansen.options.migrate.renameField(S, "a", "b"))
            s.addMigration("2.0.0", "3.0.0", @(S) nansen.options.migrate.renameField( ...
                S, "b", "c", Convert=@(x) x * 10))

            [S, log] = s.migrate(struct("a", 1), "1.0.0");
            testCase.verifyEqual(S, struct("c", 10))
            testCase.verifyNumElements(log, 2)
        end

        function testModifyParameter(testCase)
            s = testCase.Schema;
            hashBefore = s.getDefaultsHash();
            s.modifyParameter("binSize", Default=8, Max=20)

            p = s.getParameter("Preprocessing.binSize");
            testCase.verifyEqual(p.Default, 8)
            testCase.verifyEqual(p.Max, 20)
            testCase.verifyEqual(p.Description, "Number of frames to bin") % Kept
            testCase.verifyNotEqual(s.getDefaultsHash(), hashBefore)

            testCase.verifyError(@() s.modifyParameter("binSize", Default=50), ...
                "NANSEN:Options:InvalidDefault")
        end

        function testValidatorFunctions(testCase)
            p = nansen.options.Parameter("x", 1, Validator=@mustBePositive);
            testCase.verifyTrue(p.validate(2))
            testCase.verifyFalse(p.validate(-2))

            p = nansen.options.Parameter("x", 1, Validator=@(x) x < 10);
            testCase.verifyTrue(p.validate(2))
            [isValid, message] = p.validate(20);
            testCase.verifyFalse(isValid)
            testCase.verifyNotEmpty(message)
        end

        function testSizeValidation(testCase)
            p = nansen.options.Parameter("x", [1, 2], Size=[1, NaN]);
            testCase.verifyTrue(p.validate([1, 2, 3]))
            testCase.verifyFalse(p.validate([1; 2]))
        end

        function testTable(testCase)
            T = testCase.Schema.toTable();
            testCase.verifyFalse(ismember("hiddenSetting", T.Name))
            testCase.verifyEqual(T.Units(T.Name == "Preprocessing.binSize"), "frames")

            T = testCase.Schema.toTable(IncludeInternal=true);
            testCase.verifyTrue(ismember("hiddenSetting", T.Name))
        end

        function testJsonSchema(testCase)
            J = testCase.Schema.toJsonSchema();
            props = J("properties");
            testCase.verifyEqual(props.Preprocessing.properties.binSize.type, "integer")
            testCase.verifyEqual(props.Preprocessing.properties.method.enum, {"mean", "max"})

            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            filePath = fullfile(fixture.Folder, "schema.json");
            testCase.Schema.writeJsonSchema(filePath)
            decoded = jsondecode(fileread(filePath));
            testCase.verifyEqual(string(decoded.version), "1.1.0")
        end

        function testGroups(testCase)
            s = testCase.Schema;
            testCase.verifyEqual(s.GroupNames, ["Preprocessing", "Run"])
            testCase.verifyNumElements(s.getGroupParameters("Preprocessing"), 2)
            s.setGroupDescription("Preprocessing", "Steps before processing")
            testCase.verifyEqual(s.getGroupDescription("Preprocessing"), "Steps before processing")
        end

        function testDisplay(testCase)
            output = evalc("disp(testCase.Schema)");
            testCase.verifySubstring(output, "Preprocessing.binSize")
            testCase.verifySubstring(output, "Presets: Fast")
        end
    end
end
